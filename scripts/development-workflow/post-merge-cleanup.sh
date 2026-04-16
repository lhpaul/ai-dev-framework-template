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
# The grep pipeline exits 1 when no worktree uses the branch; the '|| true' prevents set -e from
# aborting the script in the common case where no worktree holds the branch.
WORKTREE_PATH=$(git worktree list --porcelain | grep -B2 "branch refs/heads/$TO_DELETE$" | grep "^worktree " | sed 's/^worktree //' || true)
if [ -n "$WORKTREE_PATH" ]; then
  echo "Worktree '$WORKTREE_PATH' is still using branch '$TO_DELETE'. Removing worktree first..."
  git worktree remove "$WORKTREE_PATH" --force
  echo "Worktree removed."
fi
# -D: branch is already merged on remote (squash/rebase merges don't leave tip in develop)
git branch -D "$TO_DELETE"

# --- Close associated GitHub issue (if any) ---
# Extract issue number from branch name patterns like fix/123-slug or fix/123 (slug optional per conventions)
ISSUE_NUMBER=""
if [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
fi

if [ -n "$ISSUE_NUMBER" ]; then
  if ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state' 2>/dev/null); then
    if [ "$ISSUE_STATE" = "OPEN" ]; then
      # Find the merged PR for this branch
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
else
  echo "No issue number detected in branch name '$TO_DELETE', skipping issue close."
fi

echo ""
echo "Done. You are on $DEVELOP_BRANCH and '$TO_DELETE' has been removed locally."
