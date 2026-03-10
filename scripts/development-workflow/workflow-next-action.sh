#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-next-action.sh --branch <branch>
  ./scripts/development-workflow/workflow-next-action.sh --pr <number>
  ./scripts/development-workflow/workflow-next-action.sh --development <path>

Classifies the next deterministic workflow action and prints stable key=value lines.
EOF
}

branch_name=""
pr_number=""
development_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      branch_name="$2"
      shift 2
      ;;
    --pr)
      pr_number="$2"
      shift 2
      ;;
    --development)
      development_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
  esac
done

targets=0
[ -n "$branch_name" ] && targets=$((targets + 1))
[ -n "$pr_number" ] && targets=$((targets + 1))
[ -n "$development_path" ] && targets=$((targets + 1))

if [ "$targets" -ne 1 ]; then
  usage >&2
  exit 64
fi

cd_workflow_repo_root

if [ -n "$pr_number" ]; then
  require_gh
  pr_json="$(gh pr view "$pr_number" --json headRefName,labels)"
  branch_name="$(printf '%s\n' "$pr_json" | jq -r '.headRefName')"
  labels="$(printf '%s\n' "$pr_json" | jq -r '[.labels[].name] | join(",")')"

  print_kv TARGET "pr:$pr_number"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_AGENT "$(reviewer_for_branch "$branch_name")"

  case ",$labels," in
    *,agent:ready-for-review,*)
      print_kv NEXT_ACTION wait-human-review
      exit 0
      ;;
    *,agent:needs-fixes,*)
      print_kv NEXT_ACTION resume-fix-loop
      exit 0
      ;;
    *)
      print_kv NEXT_ACTION resolve-pr-readiness
      exit 0
      ;;
  esac
fi

if [ -n "$branch_name" ]; then
  if gh_available; then
    pr_number="$(open_pr_number_for_branch "$branch_name")"
  else
    pr_number=""
  fi

  print_kv TARGET "branch:$branch_name"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_AGENT "$(reviewer_for_branch "$branch_name")"

  if [ -n "$pr_number" ]; then
    pr_json="$(gh pr view "$pr_number" --json labels)"
    labels="$(printf '%s\n' "$pr_json" | jq -r '[.labels[].name] | join(",")')"
    print_kv PR_NUMBER "$pr_number"
    case ",$labels," in
      *,agent:ready-for-review,*)
        print_kv NEXT_ACTION wait-human-review
        exit 0
        ;;
      *,agent:needs-fixes,*)
        print_kv NEXT_ACTION resume-fix-loop
        exit 0
        ;;
      *)
        print_kv NEXT_ACTION resolve-pr-readiness
        exit 0
        ;;
    esac
  fi

  case "$(branch_prefix "$branch_name")" in
    spec)
      print_kv NEXT_ACTION run-spec-review-and-open-pr
      ;;
    implementation-plan)
      print_kv NEXT_ACTION run-plan-review-and-open-pr
      ;;
    feature|fix|hotfix)
      print_kv NEXT_ACTION run-code-review-and-open-pr
      ;;
    *)
      print_kv NEXT_ACTION unknown
      ;;
  esac
  exit 0
fi

if [ ! -d "$development_path" ]; then
  echo "Development path does not exist: $development_path" >&2
  exit 66
fi

spec_files=("$development_path"/1_*_specs.md)
if [ "${#spec_files[@]}" -eq 0 ] || [ ! -f "${spec_files[0]}" ]; then
  echo "No spec file found in $development_path" >&2
  exit 66
fi
if [ "${#spec_files[@]}" -gt 1 ]; then
  echo "Multiple spec files found in $development_path; cannot determine which to use" >&2
  exit 66
fi
spec_file="${spec_files[0]}"

# Optional: read Linear issue ID from spec for orchestrator (tracker is source of truth for status)
linear_issue=""
if linear_line="$(grep -m 1 '^\*\*Linear Issue\*\*: ' "$spec_file" 2>/dev/null)"; then
  linear_issue="$(printf '%s\n' "$linear_line" | sed 's/^\*\*Linear Issue\*\*: //' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
[ -n "$linear_issue" ] && print_kv LINEAR_ISSUE "$linear_issue"

# Derive workflow status from repo state so issue tracker remains source of truth (no Status line in spec required)
slug="$(basename "$development_path" | sed 's/^[0-9]\{14\}_//')"
plan_file=""
for f in "$development_path"/2_*_implementation-plan.md; do
  [ -f "$f" ] && plan_file="$f" && break
done
feature_branch_exists=0
if [ -n "$slug" ] && git show-ref -q "refs/remotes/origin/feature/$slug" 2>/dev/null; then
  feature_branch_exists=1
fi

if [ -z "$plan_file" ]; then
  status_line="Spec Ready"
  next_action="write-plan"
elif [ "$feature_branch_exists" -eq 1 ]; then
  status_line="In Development"
  next_action="resolve-development-pr"
else
  status_line="Plan Ready"
  next_action="implement"
fi

print_kv TARGET "development:$development_path"
print_kv SPEC_FILE "$spec_file"
print_kv STATUS "$status_line"
print_kv NEXT_ACTION "$next_action"
