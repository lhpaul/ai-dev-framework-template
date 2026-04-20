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
  # Capture stderr so we can detect the locked-worktree condition.
  REMOVE_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1) && REMOVE_RC=0 || REMOVE_RC=$?
  if [ $REMOVE_RC -ne 0 ] && echo "$REMOVE_ERR" | grep -q "locked working tree"; then
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
  elif [ $REMOVE_RC -ne 0 ]; then
    echo "Error removing worktree '$WORKTREE_PATH': $REMOVE_ERR" >&2
    exit 1
  fi
  echo "Worktree removed."
fi
# -D: branch is already merged on remote (squash/rebase merges don't leave tip in develop)
git branch -D "$TO_DELETE"

# --- Update tracker status and close associated GitHub issue (if any) ---
# update_tracker_status <issue_number> <status_label>
#
# Best-effort: logs a warning and returns 0 on any failure so that git cleanup
# always completes regardless of GitHub Projects API availability.
#
# Requires GITHUB_PROJECT_NUMBER (and optionally GITHUB_PROJECT_OWNER) to be set
# in the environment. Falls back to querying the repo owner via 'gh repo view'.
#
# Every `gh`/`jq` pipeline is wrapped with `|| true` so that, under
# `set -euo pipefail`, a failed API call (auth missing, rate-limit, project not
# found, etc.) produces an empty string the `[ -z ... ]` guard can detect and
# handle — rather than aborting the entire script.
update_tracker_status() {
  local issue_number="$1"
  local status_label="$2"
  local owner project_number project_id field_json field_id option_id item_id

  # Resolve owner and project number. The `|| true` guard on the `gh repo view`
  # fallback is mandatory: under `set -euo pipefail`, a failed command
  # substitution in a parameter expansion default would propagate non-zero and
  # abort the script before the `[ -z "$owner" ]` guard below can emit the
  # warning and return 0.
  owner="${GITHUB_PROJECT_OWNER:-$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)}"
  project_number="${GITHUB_PROJECT_NUMBER:-}"
  if [ -z "$owner" ] || [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_OWNER or GITHUB_PROJECT_NUMBER not set; skipping tracker status update."
    return 0
  fi

  project_id=$(gh project view "$project_number" --owner "$owner" --format json 2>/dev/null | jq -r '.id // empty' || true)
  if [ -z "$project_id" ]; then
    echo "Warning: could not resolve project ID for project #${project_number}; skipping tracker status update."
    return 0
  fi

  # Resolve Status field ID and option ID for the requested label.
  field_json=$(gh project field-list "$project_number" --owner "$owner" --format json 2>/dev/null || true)
  field_id=$(printf '%s' "$field_json" | jq -r '.fields[] | select(.name == "Status") | .id // empty' || true)
  option_id=$(printf '%s' "$field_json" | jq -r --arg label "$status_label" '.fields[] | select(.name == "Status") | .options[] | select(.name == $label) | .id // empty' || true)
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "Warning: could not resolve Status field or option '${status_label}'; skipping tracker status update."
    return 0
  fi

  # Resolve project item ID for the issue.
  item_id=$(gh project item-list "$project_number" --owner "$owner" --format json 2>/dev/null \
    | jq -r --argjson num "$issue_number" '.items[] | select(.content.number == $num) | .id // empty' || true)
  if [ -z "$item_id" ]; then
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker status update."
    return 0
  fi

  echo "Updating tracker status for issue #${issue_number} to '${status_label}'..."
  gh api graphql -f query="
    mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"${project_id}\"
        itemId: \"${item_id}\"
        fieldId: \"${field_id}\"
        value: { singleSelectOptionId: \"${option_id}\" }
      }) {
        projectV2Item { id }
      }
    }
  " 2>/dev/null || echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker status not updated."
}

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
    update_tracker_status "$ISSUE_NUMBER" "Merged"
  elif [ "$BRANCH_TYPE" = "spec" ]; then
    # spec/* branches reference the issue but must not close it — the issue stays
    # open for the next workflow stage (writing the implementation plan).
    echo "Plan/spec branch for issue #$ISSUE_NUMBER merged; issue stays open for the next workflow stage. Updating tracker status to Spec Ready..."
    update_tracker_status "$ISSUE_NUMBER" "Spec Ready"
  elif [ "$BRANCH_TYPE" = "plan" ]; then
    # implementation-plan/* branches reference the issue but must not close it —
    # the issue stays open for the next workflow stage (implementation).
    echo "Plan/spec branch for issue #$ISSUE_NUMBER merged; issue stays open for the next workflow stage. Updating tracker status to Plan Ready..."
    update_tracker_status "$ISSUE_NUMBER" "Plan Ready"
  fi
else
  echo "No issue number detected in branch name '$TO_DELETE', skipping issue close and tracker update."
fi

echo ""
echo "Done. You are on $DEVELOP_BRANCH and '$TO_DELETE' has been removed locally."
