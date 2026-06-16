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

# detect_omitted_merged_items <version>
#
# Queries GitHub Projects for closed issues with "Merged" project status that
# were closed in the release window (between the previous release tag and the
# current release tag). Compares the found issues against ISSUE_NUMBERS[] (the
# changelog-derived scope). Reports any omitted issues and auto-adds confirmed
# shipped items (those with a merged PR referencing them) to ISSUE_NUMBERS[].
# Parent epics (issues with no merged PR referencing them in the window) are
# reported but emit TRACKER_INCOMPLETE rather than being auto-added.
#
# Skips silently when:
#   - TRACKER_PROVIDER is not github_projects
#   - GITHUB_PROJECT_NUMBER is not configured
#   - the current or previous release tag cannot be resolved
#   - the GitHub Projects item-list API call fails
detect_omitted_merged_items() {
  local version="$1"
  local provider project_number owner repo_owner repo_name repo_slug
  local current_tag_date prev_tag_name prev_tag_date project_items merged_items
  local known_scope_arg issue_num issue_closed_at in_window referencing_pr
  local entry iss detail total_omitted epic_nums
  local omitted_epics omitted_shipped
  omitted_epics=""
  omitted_shipped=""

  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$provider" != "github_projects" ]; then
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set; skipping omitted-merged-items detection." >&2
    return 0
  fi
  case "$project_number" in
    *[!0-9]*)
      echo "Warning: project number '${project_number}' is not numeric; skipping omitted-merged-items detection." >&2
      return 0
      ;;
  esac

  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    echo "Warning: could not resolve GitHub repository; skipping omitted-merged-items detection." >&2
    return 0
  fi
  repo_slug="${repo_owner}/${repo_name}"

  owner="$(workflow_resolve_github_project_owner 2>/dev/null)" || true
  if [ -z "$owner" ]; then
    owner="$repo_owner"
  fi

  # Resolve the current release tag date.
  current_tag_date="$(gh api "repos/${repo_slug}/releases/tags/${version}" \
      --jq '.published_at // .created_at // empty' 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty triggers git-tag fallback below
  if [ -z "$current_tag_date" ]; then
    # Fallback: resolve via git tag annotation.
    current_tag_date="$(git log -1 --format="%aI" "refs/tags/${version}" 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort fallback; empty causes early return
  fi
  if [ -z "$current_tag_date" ]; then
    echo "Warning: could not resolve release tag date for '${version}'; skipping omitted-merged-items detection." >&2
    return 0
  fi

  # Resolve the previous release tag name (latest semver tag before current one).
  # Capture the tag list, write to a temp file, then read it in Python (cannot
  # combine a pipe and a heredoc for the same process).
  local all_tags=""
  all_tags="$(gh api "repos/${repo_slug}/tags?per_page=100" --paginate \
      --jq '[.[] | select(.name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+"))] | .[].name' \
      2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty list causes all items to qualify (safe lower bound)
  prev_tag_name=""
  if [ -n "$all_tags" ]; then
    local tags_tmp=""
    if ! tags_tmp="$(mktemp "${TMPDIR:-/tmp}/release-tags.XXXXXX")"; then
      echo "Warning: could not create temp file for tag list; skipping previous-tag resolution." >&2
      tags_tmp=""
    fi
    if [ -n "$tags_tmp" ]; then
      printf '%s\n' "$all_tags" > "$tags_tmp"
      prev_tag_name="$(python3 - "$version" "$tags_tmp" <<'PY'
import sys
import re

current   = sys.argv[1].lstrip("v")
tags_file = sys.argv[2]

with open(tags_file, encoding="utf-8") as fh:
    lines = [l.strip() for l in fh.read().splitlines() if l.strip()]

def parse(v):
    v = v.lstrip("v")
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", v)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())

current_tuple = parse(current)
if current_tuple is None:
    sys.exit(1)

candidates = []
for tag in lines:
    t = parse(tag)
    if t and t < current_tuple:
        candidates.append((t, tag))

if not candidates:
    sys.exit(0)

best = sorted(candidates, reverse=True)[0][1]
print(best)
PY
      )" || true
      rm -f "$tags_tmp"
    fi
  fi

  if [ -z "$prev_tag_name" ]; then
    # No previous tag found: use epoch as the lower bound so all closed items qualify.
    prev_tag_date="1970-01-01T00:00:00Z"
  else
    # Resolve the date for the previous tag.
    prev_tag_date="$(gh api "repos/${repo_slug}/releases/tags/${prev_tag_name}" \
        --jq '.published_at // .created_at // empty' 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty triggers git-tag fallback below
    if [ -z "$prev_tag_date" ]; then
      prev_tag_date="$(git log -1 --format="%aI" "refs/tags/${prev_tag_name}" 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort fallback; empty causes epoch lower bound
    fi
    if [ -z "$prev_tag_date" ]; then
      echo "Warning: could not resolve date for previous tag '${prev_tag_name}'; using epoch as lower bound." >&2
      prev_tag_date="1970-01-01T00:00:00Z"
    fi
  fi

  # Fetch all project items via GraphQL pagination.
  # gh project item-list caps at a fixed --limit (max 2000) and silently
  # truncates larger projects.  The GraphQL API supports cursor-based
  # pagination and can retrieve every item regardless of project size.
  #
  # The accumulated JSON is shaped to match the {"items":[...]} format that
  # the Python parser below expects, so no changes are needed downstream.
  local gql_project_id
  gql_project_id="$(workflow_github_project_id "$owner" "$project_number" 2>/dev/null || true)"
  if [ -z "$gql_project_id" ]; then
    echo "Warning: could not resolve GitHub Projects ID for project #${project_number}; skipping omitted-merged-items detection." >&2
    return 0
  fi
  # shellcheck disable=SC2016 # GraphQL variables are not Bash variables.
  local _gql_items_query='query($projectId:ID!,$after:String){node(id:$projectId){...on ProjectV2{items(first:100,after:$after){nodes{type content{__typename ...on Issue{number}...on PullRequest{number}}status:fieldValueByName(name:"Status"){...on ProjectV2ItemFieldSingleSelectValue{name}}}pageInfo{hasNextPage endCursor}}}}}'
  local gql_cursor="" gql_has_next="true" gql_page=0 gql_max_pages=500
  local gql_resp_tmp gql_parse_out all_gql_nodes="[]"
  project_items=""
  while [ "$gql_has_next" = "true" ] && [ "$gql_page" -lt "$gql_max_pages" ]; do
    gql_page=$(( gql_page + 1 ))
    local gql_args=( api graphql -f "projectId=${gql_project_id}" -f "query=${_gql_items_query}" )
    if [ -n "$gql_cursor" ]; then
      gql_args+=( -f "after=${gql_cursor}" )
    fi
    if ! gql_resp_tmp="$(mktemp "${TMPDIR:-/tmp}/release-gql-items.XXXXXX")"; then
      echo "Warning: could not create temp file for GQL response; skipping omitted-merged-items detection." >&2
      return 0
    fi
    if ! gh "${gql_args[@]}" > "$gql_resp_tmp" 2>/dev/null; then
      rm -f "$gql_resp_tmp"
      echo "Warning: GraphQL project item fetch failed (page ${gql_page}); skipping omitted-merged-items detection." >&2
      return 0
    fi
    gql_parse_out="$(python3 - "$gql_resp_tmp" "$all_gql_nodes" <<PY
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

node      = ((data.get("data") or {}).get("node") or {})
items_obj = node.get("items") or {}
nodes     = items_obj.get("nodes") or []
pi        = items_obj.get("pageInfo") or {}

out = []
for n in nodes:
    sf = n.get("status") or {}
    sname = sf.get("name", "") if isinstance(sf, dict) else ""
    ct = n.get("content") or {}
    out.append({
        "type":    (n.get("type") or ""),
        "content": {"number": ct.get("number")},
        "status":  sname,
    })

try:
    acc = json.loads(sys.argv[2])
except Exception:
    acc = []
acc.extend(out)

has_next   = "true"  if pi.get("hasNextPage") else "false"
end_cursor = pi.get("endCursor") or ""

print(json.dumps(acc))
print(has_next)
print(end_cursor)
PY
    )" || true
    rm -f "$gql_resp_tmp"
    if [ -z "$gql_parse_out" ]; then
      echo "Warning: could not parse GraphQL project items (page ${gql_page}); skipping omitted-merged-items detection." >&2
      return 0
    fi
    all_gql_nodes="$(printf '%s\n' "$gql_parse_out" | sed -n '1p')"
    gql_has_next="$(printf '%s\n' "$gql_parse_out" | sed -n '2p')"
    gql_cursor="$(printf '%s\n' "$gql_parse_out" | sed -n '3p')"
  done
  project_items="{\"items\":${all_gql_nodes}}"

  # Build a newline-separated list of issue numbers that have "Merged" project
  # status, are GitHub Issues (not PRs or drafts), and are not already in the
  # changelog-derived scope.
  known_scope_arg=""
  if [ "${#ISSUE_NUMBERS[@]}" -gt 0 ]; then
    known_scope_arg="$(IFS=,; printf '%s' "${ISSUE_NUMBERS[*]}")"
  fi

  # Extract omitted issue numbers from project_items using a temp file to avoid
  # the pipe-plus-heredoc conflict (cannot use both | and <<'PY' for the same process).
  local items_tmp=""
  if ! items_tmp="$(mktemp "${TMPDIR:-/tmp}/release-project-items.XXXXXX")"; then
    echo "Warning: could not create temp file for project items; skipping omitted-merged-items detection." >&2
    return 0
  fi
  printf '%s' "$project_items" > "$items_tmp"
  if ! merged_items="$(python3 - "$known_scope_arg" "$MERGED_LABEL" "$items_tmp" <<'PY'
import json
import sys

known_scope   = set(sys.argv[1].split(",")) if sys.argv[1] else set()
merged_status = sys.argv[2]
items_file    = sys.argv[3]

try:
    with open(items_file, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as e:
    print("JSON_PARSE_ERROR: " + str(e), file=sys.stderr)
    sys.exit(2)

items = data.get("items") or []

omitted = []
for item in items:
    status = (item.get("status") or "").strip()
    if status != merged_status:
        continue
    content = item.get("content") or {}
    if not content:
        continue
    # Only GitHub Issues (not PRs): the CLI sets type="ISSUE" for issues
    item_type = (item.get("type") or "").strip().upper()
    if item_type and item_type not in ("ISSUE", ""):
        continue
    issue_number = str(content.get("number") or "").strip()
    if not issue_number:
        continue
    if issue_number in known_scope:
        continue
    omitted.append(issue_number)

print("\n".join(omitted))
PY
  )"; then
    rm -f "$items_tmp"
    echo "Warning: could not parse GitHub Projects items; skipping omitted-merged-items detection." >&2
    return 0
  fi
  rm -f "$items_tmp"

  if [ -z "$merged_items" ]; then
    echo "Omitted-merged-items check: no additional Merged items found outside changelog scope."
    return 0
  fi

  # For each candidate item, verify it was closed in the release window, then
  # classify as parent epic (no merged PR referencing it) or regular shipped item.
  # Use newline-delimited strings (bash 3.2 compatible; no associative arrays).
  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] && continue

    # Fetch the issue close date.
    issue_closed_at="$(gh api "repos/${repo_slug}/issues/${issue_num}" \
        --jq '.closed_at // empty' 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty routes issue to manual-review bucket

    if [ -z "$issue_closed_at" ]; then
      # Can't determine close date; report for manual review.
      omitted_epics="${omitted_epics}${issue_num}:unknown_close_date
"
      continue
    fi

    # Check if issue was closed inside the release window.
    in_window="$(python3 - "$issue_closed_at" "$prev_tag_date" "$current_tag_date" <<'PY'
import sys
from datetime import datetime, timezone

def parse_dt(s):
    # Normalise the string: strip a trailing Z (UTC) so fromisoformat
    # accepts it on Python before 3.11 (which does not handle Z natively).
    s = s.rstrip("Z")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        # No offset present - treat as UTC (e.g. after stripping the Z).
        # Return a naive UTC datetime so all comparisons stay in the same
        # coordinate; mixing aware and naive raises TypeError in Python 3.
        return dt
    # Offset present (positive OR negative): convert to UTC, then strip
    # tzinfo so the result is a naive UTC datetime, matching the branch above.
    return dt.astimezone(timezone.utc).replace(tzinfo=None)

try:
    closed = parse_dt(sys.argv[1])
    after  = parse_dt(sys.argv[2])
    before = parse_dt(sys.argv[3])
    print("yes" if after < closed <= before else "no")
except Exception:
    print("no")
PY
    )" || true

    if [ "$in_window" != "yes" ]; then
      continue
    fi

    # Check whether a merged PR in the repository references this issue.
    # gh pr list --search uses full-text matching and can return false
    # positives: searching for #12 can match PRs referencing #123, #1234, etc.
    # Instead, use the GraphQL timeline API which records exact cross-references
    # (CrossReferencedEvent) and PR-closed events (ClosedEvent), so only PRs
    # that truly reference this specific issue number are returned.
    # The query is inlined as a single-line variable to avoid <<'PY' heredoc
    # quoting issues in bash 3.2 when the query spans multiple lines.
    # shellcheck disable=SC2016 # GraphQL variables are not Bash variables.
    local _gql_tl_query='query($owner:String!,$repo:String!,$num:Int!,$after:String){repository(owner:$owner,name:$repo){issue(number:$num){timelineItems(first:100,after:$after,itemTypes:[CROSS_REFERENCED_EVENT,CLOSED_EVENT]){nodes{__typename ...on CrossReferencedEvent{source{__typename ...on PullRequest{number merged}}}...on ClosedEvent{closer{__typename ...on PullRequest{number merged}}}}pageInfo{hasNextPage endCursor}}}}}'
    local gql_pr_cursor="" gql_pr_has_next="true" gql_pr_page=0 gql_pr_max=20
    referencing_pr=""
    while [ "$gql_pr_has_next" = "true" ] && [ "$gql_pr_page" -lt "$gql_pr_max" ] && [ -z "$referencing_pr" ]; do
      gql_pr_page=$(( gql_pr_page + 1 ))
      local gql_pr_args=( api graphql
          -f "owner=${repo_owner}"
          -f "repo=${repo_name}"
          -F "num=${issue_num}"
          -f "query=${_gql_tl_query}" )
      if [ -n "$gql_pr_cursor" ]; then
        gql_pr_args+=( -f "after=${gql_pr_cursor}" )
      fi
      local gql_pr_tmp=""
      if ! gql_pr_tmp="$(mktemp "${TMPDIR:-/tmp}/release-gql-tl.XXXXXX")"; then
        break
      fi
      if ! gh "${gql_pr_args[@]}" > "$gql_pr_tmp" 2>/dev/null; then
        rm -f "$gql_pr_tmp"
        break
      fi
      local gql_pr_parse_out=""
      gql_pr_parse_out="$(python3 - "$gql_pr_tmp" <<PY
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

issue    = ((data.get("data") or {}).get("repository") or {}).get("issue") or {}
tl       = issue.get("timelineItems") or {}
nodes    = tl.get("nodes") or []
pi       = tl.get("pageInfo") or {}
found_pr = None

for n in nodes:
    t = n.get("__typename") or ""
    if t == "CrossReferencedEvent":
        src = n.get("source") or {}
        if src.get("__typename") == "PullRequest" and src.get("merged"):
            found_pr = src.get("number")
            break
    elif t == "ClosedEvent":
        closer = n.get("closer") or {}
        if closer.get("__typename") == "PullRequest" and closer.get("merged"):
            found_pr = closer.get("number")
            break

has_next   = "true"  if pi.get("hasNextPage") else "false"
end_cursor = pi.get("endCursor") or ""

print(str(found_pr) if found_pr is not None else "")
print(has_next)
print(end_cursor)
PY
      )" || true
      rm -f "$gql_pr_tmp"
      if [ -z "$gql_pr_parse_out" ]; then
        break
      fi
      referencing_pr="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '1p')"
      gql_pr_has_next="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '2p')"
      gql_pr_cursor="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '3p')"
    done

    if [ -n "$referencing_pr" ]; then
      omitted_shipped="${omitted_shipped}${issue_num}:pr_${referencing_pr}
"
    else
      omitted_epics="${omitted_epics}${issue_num}:no_merged_pr
"
    fi
  done <<< "$merged_items"

  # Count omitted items (trim trailing newlines before counting).
  local count_shipped=0 count_epics=0
  if [ -n "$omitted_shipped" ]; then
    count_shipped="$(printf '%s' "$omitted_shipped" | grep -c . || true)"
  fi
  if [ -n "$omitted_epics" ]; then
    count_epics="$(printf '%s' "$omitted_epics" | grep -c . || true)"
  fi
  total_omitted=$(( count_shipped + count_epics ))

  if [ "$total_omitted" -eq 0 ]; then
    echo "Omitted-merged-items check: no additional Merged items found in release window outside changelog scope."
    return 0
  fi

  echo "OMITTED_MERGED_ITEMS_DETECTED count=${total_omitted}"
  if [ "$count_shipped" -gt 0 ]; then
    echo "  Regular shipped items (will be auto-added to release scope):"
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      iss="${entry%%:*}"
      detail="${entry#*:}"
      pr_num="${detail#pr_}"
      echo "    #${iss} (merged PR #${pr_num})"
      ISSUE_NUMBERS+=("$iss")
    done <<< "$omitted_shipped"
  fi
  if [ "$count_epics" -gt 0 ]; then
    echo "  Likely parent epics or items without a merged PR (not auto-added):"
    epic_nums=""
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      iss="${entry%%:*}"
      detail="${entry#*:}"
      case "$detail" in
        no_merged_pr)       echo "    #${iss} (likely parent epic — no merged PR referencing this issue in release window)" ;;
        unknown_close_date) echo "    #${iss} (could not determine close date — manual review required)" ;;
        *)                  echo "    #${iss} (${detail})" ;;
      esac
      epic_nums="${epic_nums}${iss},"
    done <<< "$omitted_epics"
    epic_nums="${epic_nums%,}"
    echo "TRACKER_INCOMPLETE=1 REASON=omitted_parent_epics ISSUES=${epic_nums}"
  fi
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

if [ "$FROM_CHANGELOG" = "true" ]; then
  detect_omitted_merged_items "$RELEASE_VERSION"
  dedupe_issue_numbers
fi

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
