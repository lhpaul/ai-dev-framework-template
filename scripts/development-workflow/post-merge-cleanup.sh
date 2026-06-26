#!/usr/bin/env bash
#
# Post-merge cleanup: fetch origin, checkout the merge base, pull, and delete the
# local branch that was just merged (remote branch already deleted).
# Keeps the local repo clean after merging developments.
#
# Usage:
#   ./scripts/development-workflow/post-merge-cleanup.sh [--repo <name>] [--repo-root <path>] [--base <branch>] [BRANCH]
#
# - No BRANCH: use current branch (run while still on the merged branch).
# - BRANCH: name of the local branch to delete (e.g. feature/my-feature).
#
# Uses `git branch -D` (force delete) because squash/rebase merges (e.g. GitHub
# default) do not have the branch tip in develop's history, so -d would fail.
#
# Issue close: if an issue number is embedded in the branch name it is closed
# directly. When the branch slug contains no issue number (e.g. epic-slug
# branches like feature/model-cost-resilience), the merged PR body/title is
# parsed for GitHub closing keywords (Closes #N, Fixes #N, Resolves #N, etc.)
# and each referenced issue is closed and its tracker status updated to Merged.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root

HUB_REPO_ROOT="$(workflow_repo_root)"
DEVELOP_BRANCH="develop"
TO_DELETE=""
target_repo=""
repo_root="$HUB_REPO_ROOT"
base_branch_override=""

require_option_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "$option requires a value." >&2
    sed -n '2,16p' "$0" >&2
    exit 64
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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
    --base)
      require_option_value "$@"
      base_branch_override="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      if [ -n "$TO_DELETE" ]; then
        echo "Only one branch name may be provided." >&2
        exit 64
      fi
      TO_DELETE="$1"
      shift
      ;;
  esac
done

HUB_REPO_ROOT="$repo_root"
cd "$HUB_REPO_ROOT" || exit 1

if [ -z "$TO_DELETE" ]; then
  TO_DELETE="$(git branch --show-current)"
  if [ -z "$TO_DELETE" ]; then
    echo "Could not determine current branch (detached HEAD?). Pass the branch name to delete." >&2
    exit 2
  fi
fi

CLEANUP_REPO_ROOT="$repo_root"
ACTION_REPOSITORY_KIND="hub_owned"
ACTION_REPOSITORY="$(basename "$repo_root")"
TARGET_GITHUB_REPO=""
mode_context="$(workflow_repository_mode "$repo_root")"
workflow_mode="$(workflow_context_value WORKFLOW_MODE "$mode_context")"
branch_owner_kind="hub"
selected_product_default_branch=""

case "$(branch_prefix "$TO_DELETE")" in
  feature|fix|refactor|hotfix)
    branch_owner_kind="implementation"
    ;;
esac

if [ "$workflow_mode" = "workflow_hub" ] && [ "$branch_owner_kind" = "implementation" ] && [ -z "$target_repo" ]; then
  echo "ERROR: product repository selection is required for implementation branch cleanup in workflow_hub mode; pass --repo <name>." >&2
  exit 64
fi

if [ "$workflow_mode" = "workflow_hub" ] && [ -n "$target_repo" ]; then
  selected_repo_context="$(workflow_validate_repository_context "$target_repo" "$repo_root" --require-local)"
  selected_product_default_branch="$(workflow_context_value TARGET_DEFAULT_BRANCH "$selected_repo_context")"
  if [ -z "$selected_product_default_branch" ]; then
    echo "ERROR: product repository default branch is required for workflow_hub cleanup." >&2
    exit 64
  fi
else
  selected_repo_context=""
fi

if [ "$workflow_mode" = "workflow_hub" ] && [ "$branch_owner_kind" = "implementation" ]; then
  if [ -n "$selected_repo_context" ]; then
    repo_context="$selected_repo_context"
  else
    repo_context="$(workflow_validate_repository_context "$target_repo" "$repo_root" --require-local)"
  fi
  CLEANUP_REPO_ROOT="$(workflow_context_value TARGET_LOCAL_PATH "$repo_context")"
  DEVELOP_BRANCH="$(workflow_context_value TARGET_DEFAULT_BRANCH "$repo_context")"
  if [ -z "$DEVELOP_BRANCH" ]; then
    echo "ERROR: product repository default branch is required for workflow_hub cleanup." >&2
    exit 64
  fi
  ACTION_REPOSITORY_KIND="product_repo_owned"
  ACTION_REPOSITORY="$(workflow_context_value TARGET_REPO_NAME "$repo_context")"
  TARGET_GITHUB_REPO="$(workflow_github_repo_from_context "$repo_context")"
  if [ -z "$CLEANUP_REPO_ROOT" ]; then
    echo "ERROR: product repository local path is required for product repository cleanup in workflow_hub mode." >&2
    exit 64
  fi
fi

case "$TO_DELETE" in
  "$DEVELOP_BRANCH"|"$selected_product_default_branch"|main|master)
    echo "Refusing to delete protected branch '$TO_DELETE'." >&2
    exit 2
    ;;
esac

if [ -n "$base_branch_override" ]; then
  DEVELOP_BRANCH="$base_branch_override"
elif [ "$ACTION_REPOSITORY_KIND" = "hub_owned" ]; then
  cleanup_repo_slug=""
  if ! cleanup_repo_slug="$(repo_slug 2>/dev/null)"; then
    echo "ERROR: could not resolve GitHub repository for merged PR base lookup; pass --base <branch> to override." >&2
    exit 1
  fi
  if ! merged_base="$(
    gh pr list \
      --repo "$cleanup_repo_slug" \
      --state merged \
      --head "$TO_DELETE" \
      --limit 1 \
      --json baseRefName \
      --jq '.[0].baseRefName // empty'
  )"; then
    echo "ERROR: could not query merged PR base for branch '$TO_DELETE'; pass --base <branch> to override." >&2
    exit 1
  fi
  if [ -z "$merged_base" ]; then
    echo "ERROR: could not determine merged PR base for branch '$TO_DELETE'; pass --base <branch> to override." >&2
    exit 1
  fi
  DEVELOP_BRANCH="$merged_base"
fi

case "$TO_DELETE" in
  "$DEVELOP_BRANCH")
    echo "Refusing to delete protected branch '$TO_DELETE'." >&2
    exit 2
    ;;
esac

print_kv ACTION_REPOSITORY_KIND "$ACTION_REPOSITORY_KIND"
print_kv ACTION_REPOSITORY "$ACTION_REPOSITORY"
[ -n "$TARGET_GITHUB_REPO" ] && print_kv TARGET_GITHUB_REPO "$TARGET_GITHUB_REPO"
print_kv CLEANUP_REPO_ROOT "$CLEANUP_REPO_ROOT"
print_kv TRACKER_REPO_ROOT "$HUB_REPO_ROOT"

cd "$CLEANUP_REPO_ROOT" || exit 1

LOCAL_BRANCH_MISSING=0
VERIFIED_MERGED_PR=""
if ! git show-ref --quiet "refs/heads/$TO_DELETE"; then
  merged_pr_lookup_repo="$TARGET_GITHUB_REPO"
  if [ -z "$merged_pr_lookup_repo" ]; then
    if ! merged_pr_lookup_repo="$(repo_slug)"; then
      echo "Local branch '$TO_DELETE' does not exist and merged PR lookup repo could not be resolved." >&2
      exit 2
    fi
  fi
  if ! VERIFIED_MERGED_PR="$(gh pr list \
    --repo "$merged_pr_lookup_repo" \
    --state merged \
    --head "$TO_DELETE" \
    --limit 1 \
    --json number \
    --jq '.[0].number // empty')"; then
    echo "Local branch '$TO_DELETE' does not exist and merged PR lookup failed (gh command failed)." >&2
    exit 2
  fi
  if [ -z "$VERIFIED_MERGED_PR" ]; then
    echo "Local branch '$TO_DELETE' does not exist and no merged PR was found for that branch head." >&2
    exit 2
  fi
  LOCAL_BRANCH_MISSING=1
  echo "Local branch '$TO_DELETE' is already gone; verified merged PR #${VERIFIED_MERGED_PR} — continuing with fetch, base update, and tracker cleanup."
fi

if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Post-merge cleanup: will switch to $DEVELOP_BRANCH in $CLEANUP_REPO_ROOT (local branch '$TO_DELETE' already removed)."
else
  echo "Post-merge cleanup: will switch to $DEVELOP_BRANCH in $CLEANUP_REPO_ROOT, update it, and delete local branch '$TO_DELETE'."
fi
echo ""

echo "Fetching origin..."
# --prune: remove stale remote-tracking refs (e.g. origin/<merged-branch>)
git fetch origin --prune

echo "Checking out $DEVELOP_BRANCH..."
git checkout "$DEVELOP_BRANCH"

echo "Pulling $DEVELOP_BRANCH..."
# Use explicit 'origin <branch>' so this works even when the local branch has no upstream
# tracking set (e.g. integration branches created/pushed without --set-upstream).
# --ff-only: fail cleanly if the branch diverged (e.g. local commits) instead of creating a merge.
git pull --ff-only origin "$DEVELOP_BRANCH"

if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Skipping local branch delete for '$TO_DELETE' (already absent)."
else
echo "Deleting local branch '$TO_DELETE'..."
# Check whether a worktree is still using this branch; if so, remove it first.
# git branch -D fails with "error: cannot delete branch 'X' used by worktree" in that case.
# awk is used instead of grep to parse the structured porcelain output with an exact
# string match — grep -F would match branch names that are prefixes of other branches,
# and grep with a regex anchor would misinterpret metacharacters in branch names.
WORKTREE_PATH=$(git worktree list --porcelain | awk -v branch="branch refs/heads/$TO_DELETE" '
  /^worktree / { wt = substr($0, 10) }
  $0 == branch  { print wt }
' || true)
if [ -n "$WORKTREE_PATH" ]; then
  echo "Worktree '$WORKTREE_PATH' is still using branch '$TO_DELETE'. Removing worktree first..."
  # Proactive unlock: agent processes often leave worktrees locked; unlock is idempotent when not locked.
  git worktree unlock "$WORKTREE_PATH" 2>/dev/null || true
  # Capture stderr so we can detect the locked-worktree condition.
  REMOVE_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1) && REMOVE_RC=0 || REMOVE_RC=$?
  if [ "$REMOVE_RC" -ne 0 ] && echo "$REMOVE_ERR" | grep -q "locked working tree"; then
    # Detect lock reason from git worktree list --porcelain (the "locked" field).
    LOCK_REASON=$(git worktree list --porcelain | grep -A5 "^worktree $WORKTREE_PATH$" | grep "^locked" | sed 's/^locked //' || echo "unknown")
    echo "WARNING: Worktree '$WORKTREE_PATH' is locked (reason: $LOCK_REASON). Force-overriding — if this worktree belongs to an active agent, data may be lost."
    # Primary remediation: unlock then remove.
    RETRY_ERR=""
    RETRY_RC=1
    if git worktree unlock "$WORKTREE_PATH" 2>/dev/null; then
      RETRY_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1) && RETRY_RC=0 || RETRY_RC=$?
    else
      RETRY_ERR="'git worktree unlock' unavailable or failed"
    fi
    if [ "$RETRY_RC" -ne 0 ]; then
      # Fallback: double-force (bypasses lock without requiring unlock subcommand).
      echo "WARNING: ${RETRY_ERR}; using double-force fallback."
      FORCE_ERR=$(git worktree remove "$WORKTREE_PATH" --force --force 2>&1) && FORCE_RC=0 || FORCE_RC=$?
      if [ "$FORCE_RC" -ne 0 ]; then
        echo "Error removing locked worktree '$WORKTREE_PATH': $FORCE_ERR" >&2
        exit 1
      fi
    fi
  elif [ "$REMOVE_RC" -ne 0 ]; then
    echo "Error removing worktree '$WORKTREE_PATH': $REMOVE_ERR" >&2
    exit 1
  fi
  echo "Worktree removed."
fi
# -D: branch is already merged on remote (squash/rebase merges don't leave tip in develop)
git branch -D "$TO_DELETE"
fi

# --- Update tracker status and close associated GitHub issue (if any) ---

# Unified issue-number extraction: covers all branch prefixes in a single pass.
# Sets ISSUE_NUMBER, ISSUE_IDENTIFIER, ISSUE_ID_TYPE, and BRANCH_TYPE.
# ISSUE_IDENTIFIER holds the full extracted identifier (e.g. "42", "lh-97").
# ISSUE_NUMBER holds the numeric part only (used for `gh issue` commands on GitHub).
# ISSUE_ID_TYPE is "numeric" or "team-prefixed".
# All four remain empty if the branch name does not match any known prefix/pattern.
#
# Supported identifier formats:
#   Numeric:      fix/42-slug, feature/123-slug, spec/7-slug, implementation-plan/99-slug
#   Team-prefixed: fix/lh-97-slug, feature/rad-42-slug, implementation-plan/PROJ-101-slug
#                  (pattern: 2–6 alpha chars, dash, digits; case-insensitive)
ISSUE_NUMBER=""
ISSUE_IDENTIFIER=""
ISSUE_ID_TYPE=""
BRANCH_TYPE=""

if [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  ISSUE_IDENTIFIER="$ISSUE_NUMBER"
  ISSUE_ID_TYPE="numeric"
  BRANCH_TYPE="implementation"
elif [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
  ISSUE_IDENTIFIER="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
  ISSUE_ID_TYPE="team-prefixed"
  BRANCH_TYPE="implementation"
elif [[ "$TO_DELETE" =~ ^(spec)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  ISSUE_IDENTIFIER="$ISSUE_NUMBER"
  ISSUE_ID_TYPE="numeric"
  BRANCH_TYPE="spec"
elif [[ "$TO_DELETE" =~ ^(spec)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
  ISSUE_IDENTIFIER="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
  ISSUE_ID_TYPE="team-prefixed"
  BRANCH_TYPE="spec"
elif [[ "$TO_DELETE" =~ ^(implementation-plan)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  ISSUE_IDENTIFIER="$ISSUE_NUMBER"
  ISSUE_ID_TYPE="numeric"
  BRANCH_TYPE="plan"
elif [[ "$TO_DELETE" =~ ^(implementation-plan)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
  ISSUE_IDENTIFIER="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
  ISSUE_ID_TYPE="team-prefixed"
  BRANCH_TYPE="plan"
fi

if [ -n "$ISSUE_IDENTIFIER" ]; then
  cd "$HUB_REPO_ROOT"
  # For team-prefixed identifiers, log the extraction result.
  # All `gh issue` and `update_tracker_status_best_effort` calls use ISSUE_NUMBER
  # (the numeric part) because:
  #   - `gh issue view/close` require a numeric GitHub issue number.
  #   - `update_tracker_status_best_effort` uses `--argjson` to match
  #     `.content.number` (an integer) in the GitHub Projects item list.
  # The full team-prefixed identifier is captured in ISSUE_IDENTIFIER for
  # informational logging; future tracker helpers with native team-prefix support
  # should use ISSUE_IDENTIFIER rather than ISSUE_NUMBER.
  if [ "$ISSUE_ID_TYPE" = "team-prefixed" ]; then
    echo "Detected team-prefixed issue identifier '$ISSUE_IDENTIFIER' in branch '$TO_DELETE' (numeric part: #$ISSUE_NUMBER)."
  fi

  if [ "$BRANCH_TYPE" = "implementation" ]; then
    # Update the tracker status BEFORE closing the issue so that
    # gh project item-list can still find the item (it only returns items
    # whose linked issue is open; once closed the lookup silently fails).
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged"
    # Close the issue when an implementation branch (feature/fix/hotfix/refactor) is merged.
    if ! ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state'); then
      echo "ERROR: could not query issue #$ISSUE_NUMBER (gh command failed)." >&2
      exit 1
    fi
    if [ "$ISSUE_STATE" = "OPEN" ]; then
      # Find the merged PR for this branch.
      merged_pr_repo="$TARGET_GITHUB_REPO"
      if [ -z "$merged_pr_repo" ]; then
        if ! merged_pr_repo="$(repo_slug)"; then
          echo "ERROR: could not resolve GitHub repository for merged PR lookup." >&2
          exit 1
        fi
      fi
      MERGED_PR="$(gh pr list --repo "$merged_pr_repo" --state merged --head "$TO_DELETE" --limit 1 --json number --jq '.[0].number // empty')" || {
        echo "ERROR: could not query merged PRs for branch '$TO_DELETE' in '$merged_pr_repo' (gh command failed)." >&2
        exit 1
      }
      if [ -n "$MERGED_PR" ]; then
        CLOSE_COMMENT="Closed by PR #${MERGED_PR}."
      elif [ -n "$VERIFIED_MERGED_PR" ]; then
        MERGED_PR="$VERIFIED_MERGED_PR"
        CLOSE_COMMENT="Closed by PR #${MERGED_PR}."
      fi
      if [ -n "$MERGED_PR" ]; then
        echo "Closing issue #$ISSUE_NUMBER..."
        if gh issue close "$ISSUE_NUMBER" --comment "$CLOSE_COMMENT"; then
          echo "Reasserting issue #$ISSUE_NUMBER tracker status as Merged after close..."
          update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged" "" "allow-backward"
        else
          echo "Warning: could not close issue #$ISSUE_NUMBER; continuing cleanup." >&2
        fi
      else
        echo "No merged PR found for branch '$TO_DELETE'; leaving issue #$ISSUE_NUMBER open."
      fi
    else
      echo "Issue #$ISSUE_NUMBER is already $ISSUE_STATE, skipping close."
    fi
  elif [ "$BRANCH_TYPE" = "spec" ]; then
    # spec/* branches reference the issue but must not close it — the issue stays
    # open for the next workflow stage (writing the implementation plan).
    echo "Spec branch for issue #$ISSUE_NUMBER merged; issue stays open for the next workflow stage. Updating tracker status to Spec Ready..."
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Spec Ready"
  elif [ "$BRANCH_TYPE" = "plan" ]; then
    # implementation-plan/* branches reference the issue but must not close it —
    # the issue stays open for the next workflow stage (implementation).
    echo "Implementation plan branch for issue #$ISSUE_NUMBER merged; issue stays open for the next workflow stage. Updating tracker status to Plan Ready..."
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Plan Ready"
  fi
else
  # No issue number in branch name — for implementation branches, fall back to
  # parsing the merged PR body/title for GitHub closing keywords
  # (Closes #NNN, Fixes #NNN, Resolves #NNN, etc.) so that epic-slug branches
  # like feature/model-cost-resilience still close their linked issues.
  if [ "$branch_owner_kind" = "implementation" ]; then
    pr_closes_repo="$TARGET_GITHUB_REPO"
    if [ -z "$pr_closes_repo" ]; then
      if ! pr_closes_repo="$(repo_slug 2>/dev/null)"; then
        echo "ERROR: could not resolve GitHub repository for PR-body issue closeout." >&2
        exit 1
      fi
    fi
    if [ -n "$pr_closes_repo" ]; then
      CLOSING_PR="${VERIFIED_MERGED_PR:-}"
      if [ -z "$CLOSING_PR" ]; then
        if ! CLOSING_PR="$(gh pr list --repo "$pr_closes_repo" --state merged --head "$TO_DELETE" --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null)"; then
          echo "ERROR: could not query merged PRs for branch '$TO_DELETE' in '$pr_closes_repo' (gh command failed)." >&2
          exit 1
        fi
      fi
      if [ -n "$CLOSING_PR" ]; then
        if ! PR_BODY="$(gh pr view "$CLOSING_PR" --repo "$pr_closes_repo" --json body,title --jq '(.title // "") + "\n" + (.body // "")' 2>/dev/null)"; then
          echo "ERROR: could not fetch PR #${CLOSING_PR} body from '$pr_closes_repo' (gh command failed)." >&2
          exit 1
        fi
        # GitHub closing keywords (case-insensitive): close/closes/closed, fix/fixes/fixed,
        # resolve/resolves/resolved — optionally followed by "issue" — then #NNN.
        # Require a word boundary before the keyword so substrings like "disclose" or
        # "hotfix" are not treated as closing keywords.
        CLOSES_ISSUES="$(printf '%s' "$PR_BODY" | grep -ioE '(^|[[:space:]])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+' | grep -oE '[0-9]+$' | sort -un || true)"
        if [ -n "$CLOSES_ISSUES" ]; then
          echo "Found closing keyword refs in PR #${CLOSING_PR}: issues $(printf '%s' "$CLOSES_ISSUES" | tr '\n' ' ')"
          cd "$HUB_REPO_ROOT"
          CLOSES_ISSUE_VIEW_FAILURES=0
          while IFS= read -r closes_issue_num; do
            [ -z "$closes_issue_num" ] && continue
            echo "Processing issue #${closes_issue_num} from PR #${CLOSING_PR} closing keywords..."
            if ! CLOSES_ISSUE_STATE="$(gh issue view "$closes_issue_num" --json state --jq '.state' 2>/dev/null)"; then
              echo "Warning: could not query issue #${closes_issue_num}; skipping close and tracker update for this ref." >&2
              CLOSES_ISSUE_VIEW_FAILURES=$((CLOSES_ISSUE_VIEW_FAILURES + 1))
              continue
            fi
            update_tracker_status_best_effort "$closes_issue_num" "Merged"
            if [ "$CLOSES_ISSUE_STATE" = "OPEN" ]; then
              echo "Closing issue #${closes_issue_num}..."
              if gh issue close "$closes_issue_num" --comment "Closed by PR #${CLOSING_PR}."; then
                echo "Reasserting issue #${closes_issue_num} tracker status as Merged after close..."
                update_tracker_status_best_effort "$closes_issue_num" "Merged" "" "allow-backward"
              else
                echo "Warning: could not close issue #${closes_issue_num}; continuing cleanup." >&2
              fi
            else
              echo "Issue #${closes_issue_num} is already ${CLOSES_ISSUE_STATE}, skipping close."
            fi
          done <<< "$CLOSES_ISSUES"
          if [ "$CLOSES_ISSUE_VIEW_FAILURES" -gt 0 ]; then
            echo "ERROR: could not query ${CLOSES_ISSUE_VIEW_FAILURES} issue(s) from PR #${CLOSING_PR} closing refs (gh command failed)." >&2
            exit 1
          fi
        else
          echo "No issue number in branch name '$TO_DELETE' or PR #${CLOSING_PR} body; skipping issue close and tracker update."
        fi
      else
        echo "No issue number in branch name '$TO_DELETE' and no merged PR found; skipping issue close and tracker update."
      fi
    fi
  else
    echo "No issue number detected in branch name '$TO_DELETE', skipping issue close and tracker update."
  fi
fi

echo ""
if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Done. You are on $DEVELOP_BRANCH; local branch '$TO_DELETE' was already removed."
else
  echo "Done. You are on $DEVELOP_BRANCH and '$TO_DELETE' has been removed locally."
fi
