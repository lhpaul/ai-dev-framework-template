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

if [ "$TO_DELETE" = "$DEVELOP_BRANCH" ]; then
  echo "Refusing to delete '$DEVELOP_BRANCH'." >&2
  exit 2
fi

if ! git show-ref --quiet "refs/heads/$TO_DELETE"; then
  echo "Local branch '$TO_DELETE' does not exist." >&2
  exit 2
fi

echo "Post-merge cleanup: will switch to $DEVELOP_BRANCH, update it, and delete local branch '$TO_DELETE'."
echo ""

echo "Fetching origin..."
git fetch origin

echo "Checking out $DEVELOP_BRANCH..."
git checkout "$DEVELOP_BRANCH"

echo "Pulling $DEVELOP_BRANCH..."
# --ff-only: fail cleanly if develop diverged (e.g. local commits) instead of creating a merge
git pull --ff-only

echo "Deleting local branch '$TO_DELETE'..."
# -D: branch is already merged on remote (squash/rebase merges don't leave tip in develop)
git branch -D "$TO_DELETE"

echo ""
echo "Done. You are on $DEVELOP_BRANCH and '$TO_DELETE' has been removed locally."
