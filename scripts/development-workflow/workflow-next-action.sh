#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-next-action.sh --branch <branch> [--repo <name>] [--repo-root <path>]
  ./scripts/development-workflow/workflow-next-action.sh --pr <number> [--repo <name>] [--repo-root <path>]
  ./scripts/development-workflow/workflow-next-action.sh --development <path> [--repo <name>] [--repo-root <path>]

Classifies the next deterministic workflow action and prints stable key=value lines.

For --development, the script runs 'git fetch --prune origin' unless WORKFLOW_SKIP_FETCH
is set (e.g. run one fetch before looping over many development folders).
EOF
}

# Escape string for use in extended regular expression (grep -E). POSIX sed: ] first in
# bracket expression makes it literal; prefix each ERE metacharacter with backslash.
ere_escape() {
  printf '%s\n' "$1" | sed 's/[]\.^$*+?{}()|[\]/\\&/g'
}

branch_name=""
pr_number=""
development_path=""
target_repo=""
repo_root="$(workflow_repo_root)"

require_option_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      require_option_value "$@"
      branch_name="$2"
      shift 2
      ;;
    --pr)
      require_option_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --development)
      require_option_value "$@"
      development_path="$2"
      shift 2
      ;;
    --repo)
      require_option_value "$@"
      target_repo="$2"
      shift 2
      ;;
    --repo-root)
      require_option_value "$@"
      repo_root="$2"
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

cd "$repo_root"

mode_context="$(workflow_repository_mode "$repo_root")"
workflow_mode="$(workflow_context_value WORKFLOW_MODE "$mode_context")"

repository_context_for_action() {
  local action_kind="$1"
  local context=""
  local action_repository_kind="single_repo_context"
  local action_repository=""
  local action_github_repo=""
  local action_local_path=""

  if [ "$workflow_mode" = "workflow_hub" ]; then
    case "$action_kind" in
      implementation)
        if ! context="$(workflow_repository_context "$target_repo" "$repo_root")"; then
          return 1
        fi
        action_repository_kind="product_repo_owned"
        action_repository="$(workflow_context_value TARGET_REPO_NAME "$context")"
        action_github_repo="$(workflow_github_repo_from_context "$context")"
        action_local_path="$(workflow_context_value TARGET_LOCAL_PATH "$context")"
        ;;
      *)
        action_repository_kind="hub_owned"
        action_repository="$(basename "$repo_root")"
        ;;
    esac
  else
    context="$(workflow_repository_context "" "$repo_root")"
    action_repository="$(workflow_context_value TARGET_REPO_NAME "$context")"
    action_github_repo="$(workflow_github_repo_from_context "$context")"
    action_local_path="$(workflow_context_value TARGET_LOCAL_PATH "$context")"
  fi

  print_kv WORKFLOW_MODE "$workflow_mode"
  print_kv ACTION_REPOSITORY_KIND "$action_repository_kind"
  print_kv ACTION_REPOSITORY "$action_repository"
  [ -n "$action_github_repo" ] && print_kv ACTION_GITHUB_REPO "$action_github_repo"
  [ -n "$action_local_path" ] && print_kv ACTION_LOCAL_PATH "$action_local_path"
}

github_repo_args_for_action() {
  local action_kind="$1"
  local context=""
  local action_github_repo=""

  if [ "$workflow_mode" = "workflow_hub" ] && [ "$action_kind" = "implementation" ]; then
    context="$(workflow_repository_context "$target_repo" "$repo_root")"
    action_github_repo="$(workflow_github_repo_from_context "$context")"
    if [ -n "$action_github_repo" ]; then
      printf '%s\n%s\n' "--repo" "$action_github_repo"
    fi
  fi
}

if [ -n "$pr_number" ]; then
  require_gh
  pr_view_args=()
  if [ "$workflow_mode" = "workflow_hub" ] && [ -n "$target_repo" ]; then
    while IFS= read -r arg; do
      [ -n "$arg" ] && pr_view_args+=("$arg")
    done < <(github_repo_args_for_action implementation)
  fi
  if [ "${#pr_view_args[@]}" -gt 0 ]; then
    if ! pr_json="$(gh pr view "$pr_number" "${pr_view_args[@]}" --json headRefName,labels,isDraft,comments)"; then
      echo "ERROR: could not read PR #$pr_number from the selected GitHub repository." >&2
      exit 1
    fi
  else
    if ! pr_json="$(gh pr view "$pr_number" --json headRefName,labels,isDraft,comments)"; then
      echo "ERROR: could not read PR #$pr_number." >&2
      exit 1
    fi
  fi
  branch_name="$(printf '%s\n' "$pr_json" | jq -r '.headRefName')"
  labels="$(printf '%s\n' "$pr_json" | jq -r '[.labels[].name] | join(",")')"
  case "$(branch_prefix "$branch_name")" in
    feature|refactor|fix|hotfix) repository_context_for_action implementation ;;
    *) repository_context_for_action hub ;;
  esac

  print_kv TARGET "pr:$pr_number"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_AGENT "$(reviewer_for_branch "$branch_name")"

  case ",$labels," in
    *,ready-for-human-review,*)
      print_kv NEXT_ACTION wait-human-review
      exit 0
      ;;
    *,needs-fixes,*)
      print_kv NEXT_ACTION resume-fix-loop
      exit 0
      ;;
    *)
      # Detect pre-label orphaned run: non-draft PR with no readiness labels (neither
      # ready-for-regression nor ready-for-human-review) and no reviewer loop summary
      # comment — the agent timed out before post-review steps ran.
      # PRs with ready-for-regression but no ready-for-human-review are an "incomplete
      # run (post-regression)" — distinct from the pre-label orphaned case.
      is_draft="$(printf '%s\n' "$pr_json" | jq -r '.isDraft')"
      has_review_summary="$(printf '%s\n' "$pr_json" | jq -r '[.comments[].body] | any(test("Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback")) | tostring')"
      if [ "$is_draft" = "false" ] && [ "$has_review_summary" = "false" ]; then
        case ",$labels," in
          *,ready-for-regression,*) ;;  # Not orphaned — incomplete run (post-regression, pre-Step-7)
          *) print_kv ORPHANED_PR true ;;
        esac
      fi
      print_kv NEXT_ACTION resolve-pr-readiness
      exit 0
      ;;
  esac
fi

if [ -n "$branch_name" ]; then
  case "$(branch_prefix "$branch_name")" in
    feature|refactor|fix|hotfix) action_kind="implementation" ;;
    *) action_kind="hub" ;;
  esac
  repository_context_for_action "$action_kind"
  pr_list_args=()
  pr_view_args=()
  if [ "$action_kind" = "implementation" ]; then
    while IFS= read -r arg; do
      [ -n "$arg" ] && pr_list_args+=("$arg")
      [ -n "$arg" ] && pr_view_args+=("$arg")
    done < <(github_repo_args_for_action implementation)
  fi
  if gh_available; then
    if [ "${#pr_list_args[@]}" -gt 0 ]; then
      pr_number="$(gh pr list "${pr_list_args[@]}" --head "$branch_name" --state open --limit 100 --json number --jq '.[0].number // empty')"
    else
      pr_number="$(open_pr_number_for_branch "$branch_name")"
    fi
  else
    pr_number=""
  fi

  print_kv TARGET "branch:$branch_name"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_AGENT "$(reviewer_for_branch "$branch_name")"

  if [ -n "$pr_number" ]; then
    if [ "${#pr_view_args[@]}" -gt 0 ]; then
      if ! pr_json="$(gh pr view "$pr_number" "${pr_view_args[@]}" --json labels,isDraft,comments)"; then
        echo "ERROR: could not read PR #$pr_number from the selected GitHub repository." >&2
        exit 1
      fi
    else
      if ! pr_json="$(gh pr view "$pr_number" --json labels,isDraft,comments)"; then
        echo "ERROR: could not read PR #$pr_number." >&2
        exit 1
      fi
    fi
    labels="$(printf '%s\n' "$pr_json" | jq -r '[.labels[].name] | join(",")')"
    print_kv PR_NUMBER "$pr_number"
    case ",$labels," in
      *,ready-for-human-review,*)
        print_kv NEXT_ACTION wait-human-review
        exit 0
        ;;
      *,needs-fixes,*)
        print_kv NEXT_ACTION resume-fix-loop
        exit 0
        ;;
      *)
        # Detect pre-label orphaned run: non-draft PR with no readiness labels (neither
        # ready-for-regression nor ready-for-human-review) and no reviewer loop summary
        # comment — the agent timed out before post-review steps ran.
        # PRs with ready-for-regression but no ready-for-human-review are an "incomplete
        # run (post-regression)" — distinct from the pre-label orphaned case.
        is_draft="$(printf '%s\n' "$pr_json" | jq -r '.isDraft')"
        has_review_summary="$(printf '%s\n' "$pr_json" | jq -r '[.comments[].body] | any(test("Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback")) | tostring')"
        if [ "$is_draft" = "false" ] && [ "$has_review_summary" = "false" ]; then
          case ",$labels," in
            *,ready-for-regression,*) ;;  # Not orphaned — incomplete run (post-regression, pre-Step-7)
            *) print_kv ORPHANED_PR true ;;
          esac
        fi
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
    feature|refactor|fix|hotfix)
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

spec_file=""
for f in "$development_path"/1_*_specs.md "$development_path"/1_*_specs.doc.md; do
  [ -f "$f" ] && spec_file="$f" && break
done

# Derive workflow status from repo state so issue tracker remains source of truth (no Status line in spec required)
slug="$(basename "$development_path" | sed 's/^[0-9]\{14\}_//')"
plan_file=""
for f in "$development_path"/2_*_implementation-plan.md "$development_path"/2_*_implementation-plan.doc.md; do
  [ -f "$f" ] && plan_file="$f" && break
done

# A development folder must contain at least a spec or a plan file.
# Spec-only (Full Pipeline not yet at plan stage) and plan-only (Refactor path) are both valid.
if [ -z "$spec_file" ] && [ -z "$plan_file" ]; then
  echo "No spec or plan file found in $development_path" >&2
  exit 66
fi

feature_branch_exists=0
# Refresh remote refs so feature branch check is accurate. Skip if caller set WORKFLOW_SKIP_FETCH (e.g. one fetch before a loop).
if [ -z "${WORKFLOW_SKIP_FETCH:-}" ]; then
  if ! git fetch --prune origin 2>/dev/null; then
    echo "workflow-next-action.sh: warning: git fetch --prune origin failed; refs may be stale" >&2
  fi
fi
# Determine the expected branch prefix from the folder contents:
#   - Spec file present → Full Pipeline → feature/
#   - Plan-only (no spec) → Refactor → refactor/
# This avoids cross-matching: a refactor/*-user-auth branch won't be mistaken
# for progress on a Full Pipeline feature/*-user-auth item, and vice versa.
if [ -n "$spec_file" ]; then
  dev_prefix="feature"
else
  dev_prefix="refactor"
fi

# Check for the expected branch (fix/ and hotfix/ don't use development folders).
if [ -n "$slug" ]; then
  slug_ere="$(ere_escape "$slug")"
  if git show-ref --verify -q "refs/remotes/origin/${dev_prefix}/$slug" 2>/dev/null; then
    feature_branch_exists=1
  else
    # Issue-tracker-prefixed branches: [prefix]/[issue-id]-[slug]
    #   Linear/Jira: ENG-123-user-auth  (pattern: [A-Z]+-[0-9]+-)
    #   GitHub Issues: 42-user-auth     (pattern: [0-9]+-)
    # Anchor to end: branch must end with the slug (no extra suffixes like -v2 or -phase-2).
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      if [ "$ref" = "$slug" ] || echo "$ref" | grep -qE "^([A-Z]+-)?[0-9]+-${slug_ere}$"; then
        feature_branch_exists=1
        break
      fi
    done < <(git show-ref 2>/dev/null | sed -n "s|.*refs/remotes/origin/${dev_prefix}/||p")
  fi
fi

# When no live dev branch exists and a plan is present, the item could be either
# "Plan Ready (not yet started)" or "Done (branch merged and cleaned up)".
# Disambiguate with a VCS-level merged-PR check — no issue tracker required.
# Falls back gracefully to "Plan Ready" when gh is unavailable (non-GitHub VCS).
feature_branch_merged=0
if [ "$feature_branch_exists" -eq 0 ] && [ -n "$plan_file" ] && gh_available; then
  # Use the same scoped dev_prefix determined above (feature or refactor).
  # Try exact branch name first: [prefix]/<slug>
  merged_pr_args=()
  if [ "$dev_prefix" != "spec" ] && [ "$workflow_mode" = "workflow_hub" ]; then
    while IFS= read -r arg; do
      [ -n "$arg" ] && merged_pr_args+=("$arg")
    done < <(github_repo_args_for_action implementation)
  fi
  if [ "${#merged_pr_args[@]}" -gt 0 ]; then
    if ! merged_count="$(gh pr list "${merged_pr_args[@]}" --state merged --head "${dev_prefix}/$slug" --limit 100 --json number --jq 'length' 2>/dev/null)"; then
      echo "workflow-next-action.sh: warning: could not query merged PRs for ${dev_prefix}/$slug; treating as not merged" >&2
      merged_count=0
    fi
  else
    if ! merged_count="$(gh pr list --state merged --head "${dev_prefix}/$slug" --limit 100 --json number --jq 'length' 2>/dev/null)"; then
      echo "workflow-next-action.sh: warning: could not query merged PRs for ${dev_prefix}/$slug; treating as not merged" >&2
      merged_count=0
    fi
  fi
  if [ "${merged_count:-0}" -gt 0 ]; then
    feature_branch_merged=1
  else
    # Try issue-tracker-prefixed pattern: [prefix]/<ISSUE-ID>-<slug>
    # Matches Linear (ENG-123), Jira (PROJ-456), and GitHub Issues (42) prefixes.
    merged_heads_json=""
    if [ "${#merged_pr_args[@]}" -gt 0 ]; then
      if ! merged_heads_json="$(gh pr list "${merged_pr_args[@]}" --state merged --limit 500 --json headRefName 2>/dev/null)"; then
        echo "workflow-next-action.sh: warning: could not scan merged PR heads; treating as not merged" >&2
      fi
    elif ! merged_heads_json="$(gh pr list --state merged --limit 500 --json headRefName 2>/dev/null)"; then
      echo "workflow-next-action.sh: warning: could not scan merged PR heads; treating as not merged" >&2
    fi
    if [ -n "$merged_heads_json" ]; then
      if printf '%s\n' "$merged_heads_json" \
          | jq -r '.[].headRefName' 2>/dev/null \
          | sed -n "s|^${dev_prefix}/||p" \
          | grep -qE "^([A-Z]+-)?[0-9]+-${slug_ere}$"; then
        feature_branch_merged=1
      fi
    fi
  fi
fi

# IMPORTANT: The VCS-derived status below is a best-effort heuristic. It cannot reliably
# distinguish "spec/plan PR not yet merged" from "spec/plan PR merged", and development
# folders may be stale (items completed or cancelled in the tracker without folder updates).
# When an issue tracker is configured (e.g., Linear), the orchestrator MUST use the tracker
# as the primary source of truth for item status and should only call this script to enrich
# tracker data with VCS-level detail (branch existence, PR state). Do not use the STATUS
# output from this script to override the tracker status.
if [ -z "$plan_file" ] && [ -n "$spec_file" ]; then
  # Full Pipeline: spec exists but no plan yet
  status_line="Spec Ready"
  next_action="write-plan"
elif [ -z "$plan_file" ] && [ -z "$spec_file" ]; then
  # Should not reach here (guarded above), but be defensive
  status_line="Unknown"
  next_action="unknown"
elif [ "$feature_branch_exists" -eq 1 ]; then
  status_line="In Development"
  next_action="resolve-development-pr"
elif [ "$feature_branch_merged" -eq 1 ]; then
  status_line="Done"
  next_action="skip"
else
  # Plan exists, no live or merged dev branch — ready to implement.
  # Covers both Full Pipeline (spec + plan) and Refactor (plan only).
  status_line="Plan Ready"
  next_action="implement"
fi

# PLAN_FILE is intentionally not emitted; callers that need the path should scan
# "$development_path"/2_*_implementation-plan.md directly.
print_kv TARGET "development:$development_path"
[ -n "$spec_file" ] && print_kv SPEC_FILE "$spec_file"
print_kv STATUS "$status_line"
print_kv NEXT_ACTION "$next_action"
case "$next_action" in
  implement|resolve-development-pr) repository_context_for_action implementation ;;
  *) repository_context_for_action hub ;;
esac

# Optional: read Linear issue ID from spec for orchestrator (tracker is source of truth for status)
linear_issue=""
if [ -n "$spec_file" ] && linear_line="$(grep -m 1 '^\*\*Linear Issue\*\*: ' "$spec_file" 2>/dev/null)"; then
  linear_issue="$(printf '%s\n' "$linear_line" | sed 's/^\*\*Linear Issue\*\*: //' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
if [ -n "$linear_issue" ]; then
  print_kv LINEAR_ISSUE "$linear_issue"
fi
exit 0
