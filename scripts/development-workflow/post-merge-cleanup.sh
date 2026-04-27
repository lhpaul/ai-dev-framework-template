#!/usr/bin/env bash
#
# Post-merge cleanup: fetch origin, checkout develop, pull, and delete the
# local branch that was just merged (remote branch already deleted).
# Keeps the local repo clean after merging developments.
#
# Usage:
#   ./scripts/development-workflow/post-merge-cleanup.sh [BRANCH]
#
# - No BRANCH: use current branch (run while still on the merged branch).
# - BRANCH: name of the local branch to delete (e.g. feature/my-feature).
#
# Uses `git branch -D` (force delete) because squash/rebase merges (e.g. GitHub
# default) do not have the branch tip in develop's history, so -d would fail.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root

DEVELOP_BRANCH="develop"
TO_DELETE=""

if [ $# -ge 1 ]; then
  TO_DELETE="$1"
else
  TO_DELETE="$(git branch --show-current)"
  if [ -z "$TO_DELETE" ]; then
    echo "Could not determine current branch (detached HEAD?). Pass the branch name to delete." >&2
    exit 2
  fi
  if [ "$TO_DELETE" = "$DEVELOP_BRANCH" ]; then
    echo "You are on '$DEVELOP_BRANCH'. Pass the merged branch name to delete, e.g. feature/my-feature." >&2
    exit 2
  fi
fi

case "$TO_DELETE" in
  "$DEVELOP_BRANCH"|main|master)
    echo "Refusing to delete protected branch '$TO_DELETE'." >&2
    exit 2
    ;;
esac

if ! git show-ref --quiet "refs/heads/$TO_DELETE"; then
  echo "Local branch '$TO_DELETE' does not exist." >&2
  exit 2
fi

echo "Post-merge cleanup: will switch to $DEVELOP_BRANCH, update it, and delete local branch '$TO_DELETE'."
echo ""

echo "Fetching origin..."
# --prune: remove stale remote-tracking refs (e.g. origin/<merged-branch>)
git fetch origin --prune

echo "Checking out $DEVELOP_BRANCH..."
git checkout "$DEVELOP_BRANCH"

echo "Pulling $DEVELOP_BRANCH..."
# --ff-only: fail cleanly if develop diverged (e.g. local commits) instead of creating a merge
git pull --ff-only

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

# --- Update tracker status and close associated GitHub issue (if any) ---

# Unified issue-number extraction: covers all branch prefixes in a single pass.
# Sets ISSUE_NUMBER and BRANCH_TYPE; both remain empty if the branch name does
# not match any known prefix/number pattern.
ISSUE_NUMBER=""
BRANCH_TYPE=""
if [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  BRANCH_TYPE="implementation"
elif [[ "$TO_DELETE" =~ ^(spec)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  BRANCH_TYPE="spec"
elif [[ "$TO_DELETE" =~ ^(implementation-plan)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  BRANCH_TYPE="plan"
fi

if [ -n "$ISSUE_NUMBER" ]; then
  if [ "$BRANCH_TYPE" = "implementation" ]; then
    # Close the issue when an implementation branch (feature/fix/hotfix/refactor) is merged.
    if ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state' 2>/dev/null); then
      if [ "$ISSUE_STATE" = "OPEN" ]; then
        # Find the merged PR for this branch.
        if MERGED_PR=$(gh pr list --state merged --head "$TO_DELETE" --json number --jq '.[0].number // empty' 2>/dev/null); then
          : # gh succeeded; MERGED_PR may still be empty if no matching PR exists
        else
          echo "Warning: could not query merged PRs for branch '$TO_DELETE' (gh command failed). Leaving issue #$ISSUE_NUMBER open."
          MERGED_PR=""
        fi
        if [ -n "$MERGED_PR" ]; then
          CLOSE_COMMENT="Closed by PR #${MERGED_PR}."
          echo "Closing issue #$ISSUE_NUMBER..."
          gh issue close "$ISSUE_NUMBER" --comment "$CLOSE_COMMENT" 2>/dev/null || echo "Warning: could not close issue #$ISSUE_NUMBER"
        else
          echo "No merged PR found for branch '$TO_DELETE'; leaving issue #$ISSUE_NUMBER open."
        fi
      else
        echo "Issue #$ISSUE_NUMBER is already $ISSUE_STATE, skipping close."
      fi
    else
      echo "Warning: could not query issue #$ISSUE_NUMBER (gh command failed). Skipping issue close."
    fi
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged"
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
  echo "No issue number detected in branch name '$TO_DELETE', skipping issue close and tracker update."
fi

echo ""
echo "Done. You are on $DEVELOP_BRANCH and '$TO_DELETE' has been removed locally."
