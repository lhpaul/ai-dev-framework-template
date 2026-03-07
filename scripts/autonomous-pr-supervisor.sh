#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/autonomous-pr-supervisor.sh --pr <number> [--event-name name] [--review-author login] [--review-state state]

Runs Codex non-interactively against an open workflow PR so the reviewer loop can continue without
an interactive terminal session.
EOF
}

pr_number=""
event_name="manual"
review_author=""
review_state=""
model="${CODEX_MODEL:-gpt-5.4}"
reasoning_effort="${CODEX_REASONING_EFFORT:-medium}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      pr_number="$2"
      shift 2
      ;;
    --event-name)
      event_name="$2"
      shift 2
      ;;
    --review-author)
      review_author="$2"
      shift 2
      ;;
    --review-state)
      review_state="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [ -z "$pr_number" ]; then
  usage >&2
  exit 64
fi

require_gh
if ! have_cmd codex; then
  echo "Codex CLI is required for autonomous PR supervision." >&2
  exit 2
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is required for autonomous PR supervision." >&2
  exit 2
fi

cd_workflow_repo_root

pr_state_json="$(gh pr view "$pr_number" --json headRefName,baseRefName,state,isDraft,labels,url)"
pr_state="$(printf '%s\n' "$pr_state_json" | jq -r '.state')"
is_draft="$(printf '%s\n' "$pr_state_json" | jq -r '.isDraft')"
branch_name="$(printf '%s\n' "$pr_state_json" | jq -r '.headRefName')"
base_branch="$(printf '%s\n' "$pr_state_json" | jq -r '.baseRefName')"
pr_url="$(printf '%s\n' "$pr_state_json" | jq -r '.url')"

if [ "$pr_state" != "OPEN" ]; then
  echo "PR #$pr_number is not open; nothing to supervise."
  exit 0
fi

if [ "$is_draft" = "true" ]; then
  echo "PR #$pr_number is a draft; skipping autonomous supervisor."
  exit 0
fi

case "$(branch_prefix "$branch_name")" in
  spec|implementation-plan|feature|fix|hotfix) ;;
  *)
    echo "Branch $branch_name is not a managed workflow branch; skipping autonomous supervisor."
    exit 0
    ;;
esac

workflow_state="$(./scripts/workflow-next-action.sh --pr "$pr_number")"
next_action="$(printf '%s\n' "$workflow_state" | sed -n 's/^NEXT_ACTION=//p' | head -n 1)"

if [ "$next_action" = "wait-human-review" ]; then
  echo "PR #$pr_number is already waiting on human review."
  exit 0
fi

prompt_file="$(mktemp)"
output_file="$(mktemp)"
trap 'rm -f "$prompt_file" "$output_file"' EXIT

cat >"$prompt_file" <<EOF
Resume the autonomous PR supervisor for PR #$pr_number on branch $branch_name targeting $base_branch.

Repository state:
- PR URL: $pr_url
- Event name: $event_name
- Review author: ${review_author:-n/a}
- Review state: ${review_state:-n/a}
- Current workflow-next-action output:
$workflow_state

You are operating inside the repository checkout. Follow AGENTS.md and the workflow protocols exactly, especially:
- docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md
- docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md

Goal:
- Keep PR #$pr_number moving until it reaches a real terminal condition without human intervention.

Required behavior:
1. Inspect the current PR state, labels, latest Greptile review comments, and helper script outputs.
2. If Greptile or CI left blocking issues, fix them directly on branch $branch_name.
3. Commit with Conventional Commits and push any repo-tracked fixes.
4. Use these helpers instead of re-implementing state logic:
   - ./scripts/workflow-next-action.sh
   - ./scripts/workflow-resume.sh
   - ./scripts/pr-review-loop.sh
   - ./scripts/pr-ci-loop.sh
5. Use gh for GitHub interactions.
6. Continue until one of:
   - the PR can be marked ready for human review
   - a real human product/architecture decision is required
   - retry/timeout limits from the workflow protocol are hit

Important constraints:
- Do not stop after summarizing findings; actually apply the next fix/review/push cycle when possible.
- If the PR is already waiting on human review, exit cleanly without changing files.
- If you must escalate, leave a concise PR comment explaining the blocker and why automation stopped.
EOF

printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null

codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --color never \
  -C "$(workflow_repo_root)" \
  -m "$model" \
  -c "model_reasoning_effort=\"$reasoning_effort\"" \
  -o "$output_file" \
  - <"$prompt_file"

printf '%s\n' "Autonomous PR supervisor completed for PR #$pr_number."
printf '%s\n' "--- Codex summary ---"
cat "$output_file"
