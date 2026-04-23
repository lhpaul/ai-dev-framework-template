#!/usr/bin/env bash
#
# Post-merge cleanup for a release branch:
# - verifies release PRs to main and develop are both merged
# - deletes remote release branch (if present)
# - deletes local release branch (switching away first if needed)
# - optionally transitions explicit issue numbers from merged -> released
#
# Usage:
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh <version|release-branch> [--issue N]... [--issues N,N,...] [--best-effort]
#
# Examples:
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh 1.2.3
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --issue 232 --issue 240
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issues 232,240
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issues 232,240 --best-effort
#
# Exit codes when --issues is supplied (unless --best-effort is passed):
#   0  All supplied issues had updated==1 per issue (or no issues supplied)
#   1  updated==0 after processing all issues, or at least one hard failure occurred
#
# Output (when --issues is supplied):
#   Emits structured key/value summary line:  UPDATED=N SKIPPED=N FAILED=N
#
# Env overrides:
#   GITHUB_PROJECT_STATUS_MERGED   (default: Merged)
#   GITHUB_PROJECT_STATUS_RELEASED (default: Released)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root
require_gh

MERGED_LABEL="${GITHUB_PROJECT_STATUS_MERGED:-Merged}"
RELEASED_LABEL="${GITHUB_PROJECT_STATUS_RELEASED:-Released}"
RELEASE_INPUT=""
BEST_EFFORT=false
declare -a ISSUE_NUMBERS=()

usage() {
  echo "Usage: $0 <version|release-branch> [--issue N]... [--issues N,N,...] [--best-effort]" >&2
}

normalize_release_branch() {
  local value="$1"
  value="${value#refs/heads/}"
  case "$value" in
    release/v*) printf '%s\n' "$value" ;;
    release/*) printf 'release/v%s\n' "${value#release/}" ;;
    v*) printf 'release/%s\n' "$value" ;;
    *) printf 'release/v%s\n' "$value" ;;
  esac
}

parse_issue_csv() {
  local csv="$1"
  local old_ifs="$IFS"
  local part
  IFS=','
  # shellcheck disable=SC2086
  for part in $csv; do
    part="${part//[[:space:]]/}"
    [ -z "$part" ] && continue
    if [[ ! "$part" =~ ^[0-9]+$ ]]; then
      echo "Invalid issue number '$part' in --issues list." >&2
      exit 2
    fi
    ISSUE_NUMBERS+=("$part")
  done
  IFS="$old_ifs"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "Invalid issue number for --issue: $2" >&2
        exit 2
      fi
      ISSUE_NUMBERS+=("$2")
      shift 2
      ;;
    --issues)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      parse_issue_csv "$2"
      shift 2
      ;;
    --best-effort)
      BEST_EFFORT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [ -n "$RELEASE_INPUT" ]; then
        echo "Unexpected extra positional argument: $1" >&2
        usage
        exit 2
      fi
      RELEASE_INPUT="$1"
      shift
      ;;
  esac
done

if [ -z "$RELEASE_INPUT" ]; then
  usage
  exit 2
fi

RELEASE_BRANCH="$(normalize_release_branch "$RELEASE_INPUT")"
echo "Release branch: $RELEASE_BRANCH"

echo "Verifying merged PRs for release branch..."
MAIN_PR=$(gh pr list --state merged --head "$RELEASE_BRANCH" --base main --json number --jq '.[0].number // empty')
DEVELOP_PR=$(gh pr list --state merged --head "$RELEASE_BRANCH" --base develop --json number --jq '.[0].number // empty')
OPEN_MAIN_PR=$(gh pr list --state open --head "$RELEASE_BRANCH" --base main --json number --jq '.[0].number // empty')
OPEN_DEVELOP_PR=$(gh pr list --state open --head "$RELEASE_BRANCH" --base develop --json number --jq '.[0].number // empty')

if [ -n "$OPEN_MAIN_PR" ] || [ -n "$OPEN_DEVELOP_PR" ]; then
  echo "Release PRs are still open (main: ${OPEN_MAIN_PR:-none}, develop: ${OPEN_DEVELOP_PR:-none})."
  echo "Do not run post-merge cleanup until both PRs are merged." >&2
  exit 1
fi

if [ -z "$MAIN_PR" ] || [ -z "$DEVELOP_PR" ]; then
  echo "Both merged PRs are required before cleanup." >&2
  echo "Detected merged PRs - main: ${MAIN_PR:-none}, develop: ${DEVELOP_PR:-none}" >&2
  exit 1
fi

echo "Merged PRs verified (main #$MAIN_PR, develop #$DEVELOP_PR)."

echo "Fetching origin refs..."
git fetch origin --prune

if git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
  echo "Deleting remote branch '$RELEASE_BRANCH'..."
  git push origin --delete "$RELEASE_BRANCH"
else
  echo "Remote branch '$RELEASE_BRANCH' is already absent; skipping remote delete."
fi

if git show-ref --quiet "refs/heads/$RELEASE_BRANCH"; then
  CURRENT_BRANCH="$(git branch --show-current)"
  if [ "$CURRENT_BRANCH" = "$RELEASE_BRANCH" ]; then
    echo "Local branch '$RELEASE_BRANCH' is currently checked out; switching to develop first..."
    git switch develop
  fi

  echo "Deleting local branch '$RELEASE_BRANCH'..."
  # -D is intentional: squash/rebase merges often make -d fail despite merged PRs.
  if ! git branch -D "$RELEASE_BRANCH"; then
    echo "Could not delete local branch '$RELEASE_BRANCH' cleanly." >&2
    echo "If it is checked out elsewhere, switch away in that worktree and retry." >&2
    exit 1
  fi
else
  echo "Local branch '$RELEASE_BRANCH' is already absent; skipping local delete."
fi

if [ "${#ISSUE_NUMBERS[@]}" -eq 0 ]; then
  echo "No issues supplied; skipping tracker release transitions."
  echo "Release post-merge cleanup complete."
  exit 0
fi

echo "Transitioning scoped issues from '$MERGED_LABEL' to '$RELEASED_LABEL'..."
TRACKER_UPDATED=0
TRACKER_SKIPPED=0
TRACKER_FAILED=0

for issue in "${ISSUE_NUMBERS[@]}"; do
  ISSUE_STATE=$(gh issue view "$issue" --json state --jq '.state' 2>/dev/null || true)
  if [ -z "$ISSUE_STATE" ]; then
    echo "Warning: could not read issue #$issue; skipping tracker update."
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
    continue
  fi
  # Capture output from the best-effort helper to classify the outcome.
  # The helper always exits 0; we distinguish outcomes by its stdout:
  #   "Updating tracker status..."  (followed by successful GraphQL JSON) -> updated
  #   "Warning: ... skipping ..."                                          -> skipped
  #   "Warning: GraphQL mutation failed ..."                               -> failed
  TRACKER_OUT=$(update_tracker_status_best_effort "$issue" "$RELEASED_LABEL" "$MERGED_LABEL" 2>&1)
  echo "$TRACKER_OUT"
  if echo "$TRACKER_OUT" | grep -q "^Updating tracker status"; then
    if echo "$TRACKER_OUT" | grep -q "Warning: GraphQL mutation failed"; then
      TRACKER_FAILED=$((TRACKER_FAILED + 1))
    else
      TRACKER_UPDATED=$((TRACKER_UPDATED + 1))
    fi
  elif echo "$TRACKER_OUT" | grep -q "Warning:"; then
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
  else
    # Unexpected output pattern — treat conservatively as a skip
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
  fi
done

echo "UPDATED=$TRACKER_UPDATED SKIPPED=$TRACKER_SKIPPED FAILED=$TRACKER_FAILED"

if [ "$BEST_EFFORT" = "true" ]; then
  echo "Release post-merge cleanup complete."
  exit 0
fi

if [ "$TRACKER_FAILED" -gt 0 ]; then
  echo "Error: $TRACKER_FAILED tracker transition(s) failed for release $RELEASE_BRANCH." >&2
  echo "Pass --best-effort to suppress this error and exit 0 regardless of transition outcomes." >&2
  exit 1
fi

if [ "$TRACKER_UPDATED" -eq 0 ]; then
  echo "Error: no tracker transitions succeeded (UPDATED=0) for release $RELEASE_BRANCH." >&2
  echo "Pass --best-effort to suppress this error and exit 0 regardless of transition outcomes." >&2
  exit 1
fi

echo "Release post-merge cleanup complete."
