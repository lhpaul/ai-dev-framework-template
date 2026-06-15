#!/usr/bin/env bash
#
# Post-merge cleanup for a release branch:
# - verifies release PRs to main and develop are both merged
# - deletes remote release branch (if present)
# - deletes local release branch (switching away first if needed)
# - stamps scoped issue numbers with the release version
# - transitions scoped issue numbers from merged -> released, or emits a
#   fail-closed tracker handoff when shell automation cannot complete them
#
# Usage:
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh <version|release-branch> [--from-changelog] [--issue N]... [--issues N,N,...] [--best-effort]
#
# Examples:
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh 1.2.3
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --issue 232 --issue 240
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issues 232,240
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --from-changelog
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issues 232,240 --best-effort
#
# Exit codes for tracker cleanup (unless --best-effort is passed):
#   0  At least one issue was updated (or already in Released status) and no hard failures
#      occurred. Issues already in Released status count as success.
#   1  updated==0 after processing all issues, or at least one hard failure occurred
#
# Output (when --issues is supplied):
#   Emits structured key/value summary line:
#   STAMPED=N STAMP_SKIPPED=N STAMP_FAILED=N UPDATED=N SKIPPED=N FAILED=N
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

# Detect tracker provider early so that issue-ID validation can accept
# Linear-style identifiers (e.g. LH-57) when the provider is "linear".
TRACKER_PROVIDER="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"

MERGED_LABEL="${GITHUB_PROJECT_STATUS_MERGED:-Merged}"
RELEASED_LABEL="${GITHUB_PROJECT_STATUS_RELEASED:-Released}"
RELEASE_INPUT=""
BEST_EFFORT=false
FROM_CHANGELOG=false
declare -a ISSUE_NUMBERS=()

usage() {
  echo "Usage: $0 <version|release-branch> [--from-changelog] [--issue N]... [--issues N,N,...] [--best-effort]" >&2
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

# Returns 0 (true) if the token is a valid issue identifier for the current
# tracker provider, 1 (false) otherwise.
#   - Numeric-only IDs are accepted for any provider.
#   - Linear-style alphanumeric IDs (e.g. LH-57, PROJ-123) are accepted when
#     TRACKER_PROVIDER is "linear".
is_valid_issue_token() {
  local token="$1"
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  if [[ "$TRACKER_PROVIDER" = "linear" && "$token" =~ ^[A-Za-z][A-Za-z0-9_]*-[0-9]+$ ]]; then
    return 0
  fi
  return 1
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
    if ! is_valid_issue_token "$part"; then
      echo "Invalid issue number '$part' in --issues list." >&2
      exit 2
    fi
    ISSUE_NUMBERS+=("$part")
  done
  IFS="$old_ifs"
}

append_issues_from_changelog() {
  local version="$1"
  local changelog_path="${CHANGELOG_PATH:-CHANGELOG.md}"
  local extracted

  if [ ! -f "$changelog_path" ]; then
    echo "Could not find changelog at '$changelog_path' for --from-changelog." >&2
    return 1
  fi

  if ! extracted="$(python3 - "$version" "$changelog_path" "$TRACKER_PROVIDER" <<'PY'
import re
import sys
from pathlib import Path

version = sys.argv[1]
if version.startswith("v"):
    version = version[1:]
path = Path(sys.argv[2])
provider = sys.argv[3]
text = path.read_text(encoding="utf-8")

heading = re.compile(rf"^## \[(?:v?{re.escape(version)})\].*$", re.MULTILINE)
match = heading.search(text)
if not match:
    print(f"CHANGELOG_VERSION_NOT_FOUND version=v{version}", file=sys.stderr)
    sys.exit(1)

next_heading = re.search(r"^## \[", text[match.end():], re.MULTILINE)
section_end = match.end() + next_heading.start() if next_heading else len(text)
section = text[match.end():section_end]

seen = set()
issues = []

def add(value: str) -> None:
    if value not in seen:
        seen.add(value)
        issues.append(value)

if provider == "linear":
    range_re = re.compile(r"\b([A-Z][A-Z0-9_]*-)(\d+)\s*[\u2013-]\s*(?:[A-Z][A-Z0-9_]*-)?(\d+)\b")
    for item in range_re.finditer(section):
        prefix = item.group(1)
        start = int(item.group(2))
        end = int(item.group(3))
        if end < start:
            start, end = end, start
        for number in range(start, end + 1):
            add(f"{prefix}{number}")

    for item in re.finditer(r"\b[A-Z][A-Z0-9_]*-\d+\b", section):
        add(item.group(0))
else:
    for item in re.finditer(r"(?<![\w-])#([1-9][0-9]*)\b", section):
        add(item.group(1))

if not issues:
    print(f"CHANGELOG_NO_ISSUES_FOUND version=v{version}", file=sys.stderr)
    sys.exit(1)

print("\n".join(issues))
PY
  )"; then
    return 1
  fi

  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    if ! is_valid_issue_token "$issue"; then
      echo "Invalid issue token '$issue' extracted from CHANGELOG." >&2
      return 1
    fi
    ISSUE_NUMBERS+=("$issue")
  done <<< "$extracted"
}

dedupe_issue_numbers() {
  local deduped
  if [ "${#ISSUE_NUMBERS[@]}" -eq 0 ]; then
    return 0
  fi

  if ! deduped="$(python3 - "${ISSUE_NUMBERS[@]}" <<'PY'
import sys

seen = set()
for issue in sys.argv[1:]:
    if issue and issue not in seen:
        seen.add(issue)
        print(issue)
PY
  )"; then
    echo "Could not deduplicate issue scope." >&2
    return 1
  fi

  ISSUE_NUMBERS=()
  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    ISSUE_NUMBERS+=("$issue")
  done <<< "$deduped"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      if ! is_valid_issue_token "$2"; then
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
    --from-changelog)
      FROM_CHANGELOG=true
      shift
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
RELEASE_VERSION="${RELEASE_BRANCH#release/}"
echo "Release branch: $RELEASE_BRANCH"
echo "Release version: $RELEASE_VERSION"

if [ "$FROM_CHANGELOG" = "true" ]; then
  if ! append_issues_from_changelog "$RELEASE_VERSION"; then
    echo "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable"
    if [ "$BEST_EFFORT" != "true" ]; then
      exit 1
    fi
  fi
fi

dedupe_issue_numbers

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
  echo "TRACKER_INCOMPLETE=1 REASON=no_issue_scope"
  echo "No issues supplied; release tracker transitions are incomplete."
  echo "Rerun with --from-changelog or explicit --issue/--issues after confirming the shipped issue scope."
  if [ "$BEST_EFFORT" != "true" ]; then
    echo "Pass --best-effort to keep branch cleanup as the only completed action and exit 0." >&2
    exit 1
  fi
  echo "Release post-merge cleanup complete."
  exit 0
fi

# Linear status transitions cannot be performed automatically by this script
# (they require MCP/API access). Emit per-issue manual action guidance and
# exit cleanly rather than silently skipping or failing with UPDATED=0.
if [ "$TRACKER_PROVIDER" = "linear" ]; then
  echo "Recording release stamp guidance for Linear issue(s)..."
  LINEAR_STAMPED=0
  LINEAR_STAMP_SKIPPED=0
  LINEAR_STAMP_FAILED=0
  for issue in "${ISSUE_NUMBERS[@]}"; do
    if ! STAMP_OUT="$(record_release_for_issue_best_effort "$issue" "$RELEASE_VERSION")"; then
      echo "Warning: release-stamp helper failed for issue #$issue; counting as stamp failure."
      STAMP_OUT="RELEASE_STAMP_FAILED issue=${issue} version=${RELEASE_VERSION} provider=${TRACKER_PROVIDER:-unknown} reason=helper_failed"
    fi
    echo "$STAMP_OUT"
    if echo "$STAMP_OUT" | grep -q "^RELEASE_STAMPED "; then
      LINEAR_STAMPED=$((LINEAR_STAMPED + 1))
    elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_FAILED "; then
      LINEAR_STAMP_FAILED=$((LINEAR_STAMP_FAILED + 1))
    elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_SKIPPED "; then
      LINEAR_STAMP_SKIPPED=$((LINEAR_STAMP_SKIPPED + 1))
    else
      echo "Warning: unrecognized release-stamp output for issue #$issue; counting as stamp failure."
      LINEAR_STAMP_FAILED=$((LINEAR_STAMP_FAILED + 1))
    fi
  done
  echo "Linear tracker detected: automatic '$MERGED_LABEL' -> '$RELEASED_LABEL' transitions are not supported by this script."
  echo "Manually transition the following issue(s) to '$RELEASED_LABEL' in Linear (via MCP server or API):"
  for issue in "${ISSUE_NUMBERS[@]}"; do
    echo "  - Issue $issue: set status to '$RELEASED_LABEL'"
  done
  echo "TRACKER_ACTION=linear_mcp_or_api_required"
  echo "TRACKER_INCOMPLETE=1 REASON=linear_status_transition_required"
  echo "TRACKER_ISSUES=$(IFS=,; printf '%s' "${ISSUE_NUMBERS[*]}")"
  echo "See docs/workflow/development-workflow/integrations/linear.md for guidance."
  echo "STAMPED=$LINEAR_STAMPED STAMP_SKIPPED=$LINEAR_STAMP_SKIPPED STAMP_FAILED=$LINEAR_STAMP_FAILED UPDATED=0 SKIPPED=0 FAILED=0"
  if [ "$BEST_EFFORT" != "true" ]; then
    echo "Release tracker transitions are incomplete until Linear issues are moved to '$RELEASED_LABEL'." >&2
    echo "Pass --best-effort only when a human explicitly accepts completing tracker transitions outside this script." >&2
    exit 1
  fi
  echo "Release post-merge cleanup complete."
  exit 0
fi

echo "Transitioning scoped issues from '$MERGED_LABEL' to '$RELEASED_LABEL'..."
RELEASE_STAMPED=0
RELEASE_STAMP_SKIPPED=0
RELEASE_STAMP_FAILED=0
TRACKER_UPDATED=0
TRACKER_SKIPPED=0
TRACKER_FAILED=0

for issue in "${ISSUE_NUMBERS[@]}"; do
  if ! STAMP_OUT="$(record_release_for_issue_best_effort "$issue" "$RELEASE_VERSION")"; then
    echo "Warning: release-stamp helper failed for issue #$issue; counting as stamp failure."
    STAMP_OUT="RELEASE_STAMP_FAILED issue=${issue} version=${RELEASE_VERSION} provider=${TRACKER_PROVIDER:-unknown} reason=helper_failed"
  fi
  echo "$STAMP_OUT"
  if echo "$STAMP_OUT" | grep -q "^RELEASE_STAMPED "; then
    RELEASE_STAMPED=$((RELEASE_STAMPED + 1))
  elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_FAILED "; then
    RELEASE_STAMP_FAILED=$((RELEASE_STAMP_FAILED + 1))
  elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_SKIPPED "; then
    RELEASE_STAMP_SKIPPED=$((RELEASE_STAMP_SKIPPED + 1))
  else
    echo "Warning: unrecognized release-stamp output for issue #$issue; counting as stamp failure."
    RELEASE_STAMP_FAILED=$((RELEASE_STAMP_FAILED + 1))
  fi

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
  # When the issue is already in the target status (set by GitHub project automation
  # before this script runs), the helper emits a "does not match required source
  # status" message because the current status is already 'Released' (not 'Merged').
  # Treat that as a no-op success so that UPDATED=0 only signals a real failure.
  TRACKER_OUT=$(update_tracker_status_best_effort "$issue" "$RELEASED_LABEL" "$MERGED_LABEL" 2>&1)
  echo "$TRACKER_OUT"
  if echo "$TRACKER_OUT" | grep -q "^Updating tracker status"; then
    if echo "$TRACKER_OUT" | grep -q "Warning: GraphQL mutation failed"; then
      TRACKER_FAILED=$((TRACKER_FAILED + 1))
    else
      TRACKER_UPDATED=$((TRACKER_UPDATED + 1))
    fi
  elif echo "$TRACKER_OUT" | grep -q "current status '${RELEASED_LABEL}'"; then
    # Issue is already in the target Released status (set by GitHub project automation).
    # This is a no-op success — not a failure or a skip that warrants an error exit.
    echo "Issue #$issue is already in '$RELEASED_LABEL' status; counting as success."
    TRACKER_UPDATED=$((TRACKER_UPDATED + 1))
  elif echo "$TRACKER_OUT" | grep -q "Warning:"; then
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
  else
    # Unexpected output pattern — treat conservatively as a skip
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
  fi
done

echo "STAMPED=$RELEASE_STAMPED STAMP_SKIPPED=$RELEASE_STAMP_SKIPPED STAMP_FAILED=$RELEASE_STAMP_FAILED UPDATED=$TRACKER_UPDATED SKIPPED=$TRACKER_SKIPPED FAILED=$TRACKER_FAILED"

if [ "$BEST_EFFORT" != "true" ]; then
  if [ "$TRACKER_FAILED" -gt 0 ]; then
    echo "Error: $TRACKER_FAILED tracker transition(s) failed for release $RELEASE_BRANCH." >&2
    echo "Pass --best-effort to suppress this error and exit 0 regardless of transition outcomes." >&2
    exit 1
  fi

  if [ "$TRACKER_UPDATED" -eq 0 ]; then
    case "$TRACKER_PROVIDER" in
      github_projects|github-projects|github_issues|github-issues)
        ;;
      *)
        echo "No shell-supported tracker transitions ran for provider '${TRACKER_PROVIDER:-none}'; release-stamp handling completed."
        echo "Release post-merge cleanup complete."
        exit 0
        ;;
    esac
    if [ "$RELEASE_STAMPED" -gt 0 ] && [ "$TRACKER_SKIPPED" -gt 0 ] && [ "$TRACKER_FAILED" -eq 0 ]; then
      echo "Release stamping succeeded, but tracker status transitions were skipped; treating cleanup as successful because no transition failed."
    else
      echo "Error: no tracker transitions succeeded (UPDATED=0) for release $RELEASE_BRANCH." >&2
      echo "Pass --best-effort to suppress this error and exit 0 regardless of transition outcomes." >&2
      exit 1
    fi
  fi
fi

if [ "$RELEASE_STAMPED" -gt 0 ]; then
  if ! finalize_release_marker_best_effort "$RELEASE_VERSION"; then
    if [ "$BEST_EFFORT" != "true" ]; then
      echo "Error: release marker finalization failed for $RELEASE_VERSION." >&2
      echo "Pass --best-effort to suppress this error and exit 0 regardless of finalization outcomes." >&2
      exit 1
    fi
    echo "Warning: release marker finalization failed for $RELEASE_VERSION; continuing because --best-effort was passed." >&2
  fi
fi

echo "Release post-merge cleanup complete."
