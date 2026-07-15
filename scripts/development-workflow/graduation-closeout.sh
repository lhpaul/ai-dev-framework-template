#!/usr/bin/env bash
#
# Reconcile delivered integration-branch sub-items after a graduation PR merges.
#
# Usage:
#   ./scripts/development-workflow/graduation-closeout.sh --slug <slug> --graduation-pr <number> --epic <issue-number> [--exclude-issue <number>]... [--defer-epic-close]
#
# Env overrides:
#   GITHUB_PROJECT_STATUS_GRADUATED  Terminal status for graduated work.
#   GITHUB_PROJECT_STATUS_MERGED     Fallback terminal status.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./workflow-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/workflow-lib.sh"

SLUG=""
GRADUATION_PR=""
EPIC_ISSUE=""
DEFER_EPIC_CLOSE=0
declare -a EXCLUDED_ISSUES=()

usage() {
  cat >&2 <<'EOF'
Usage:
  graduation-closeout.sh --slug <slug> --graduation-pr <number> --epic <issue-number> [--exclude-issue <number>]... [--defer-epic-close]
EOF
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage
    exit 64
  fi
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

is_valid_slug() {
  case "$1" in
    ''|*[^a-zA-Z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slug)
      require_value "$@"
      SLUG="$2"
      shift 2
      ;;
    --graduation-pr)
      require_value "$@"
      GRADUATION_PR="$2"
      shift 2
      ;;
    --epic)
      require_value "$@"
      EPIC_ISSUE="$2"
      shift 2
      ;;
    --exclude-issue)
      require_value "$@"
      EXCLUDED_ISSUES+=("$2")
      shift 2
      ;;
    --defer-epic-close)
      DEFER_EPIC_CLOSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if ! is_valid_slug "$SLUG"; then
  echo "ERROR: --slug must be non-empty and contain only letters, numbers, dot, underscore, or hyphen." >&2
  exit 64
fi
if ! is_positive_int "$GRADUATION_PR"; then
  echo "ERROR: --graduation-pr must be a positive integer." >&2
  exit 64
fi
if ! is_positive_int "$EPIC_ISSUE"; then
  echo "ERROR: --epic must be a positive integer." >&2
  exit 64
fi
for excluded in ${EXCLUDED_ISSUES[@]+"${EXCLUDED_ISSUES[@]}"}; do
  if ! is_positive_int "$excluded"; then
    echo "ERROR: --exclude-issue must be a positive integer." >&2
    exit 64
  fi
done

cd_workflow_repo_root
require_gh

REPO_SLUG="$(repo_slug)"
REPO_OWNER="${REPO_SLUG%%/*}"
REPO_NAME="${REPO_SLUG#*/}"
INTEGRATION_BRANCH="develop-${SLUG}"
INTEGRATION_LABEL="integration-branch:${SLUG}"
TERMINAL_STATUS="${GITHUB_PROJECT_STATUS_GRADUATED:-${GITHUB_PROJECT_STATUS_MERGED:-Merged}}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CANDIDATES_FILE="$TMP_DIR/candidates.tsv"
UNIQUE_ISSUES_FILE="$TMP_DIR/issues.txt"
CLOSED_FILE="$TMP_DIR/closed.tsv"
ALREADY_FILE="$TMP_DIR/already-terminal.tsv"
SKIPPED_FILE="$TMP_DIR/skipped-optional.tsv"
FAILED_FILE="$TMP_DIR/failed.tsv"
: > "$CANDIDATES_FILE"
: > "$CLOSED_FILE"
: > "$ALREADY_FILE"
: > "$SKIPPED_FILE"
: > "$FAILED_FILE"

append_candidate() {
  local issue="$1"
  local source="$2"
  if is_positive_int "$issue"; then
    printf '%s\t%s\n' "$issue" "$source" >> "$CANDIDATES_FILE"
  fi
}

is_excluded_issue() {
  local issue="$1"
  local excluded
  for excluded in ${EXCLUDED_ISSUES[@]+"${EXCLUDED_ISSUES[@]}"}; do
    if [ "$excluded" = "$issue" ]; then
      return 0
    fi
  done
  return 1
}

is_skip_label() {
  local labels_csv="$1"
  local old_ifs="$IFS"
  local label normalized
  IFS=','
  # shellcheck disable=SC2086
  for label in $labels_csv; do
    normalized="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      optional|deferred|cancelled|excluded-from-graduation|exclude-from-graduation)
        IFS="$old_ifs"
        return 0
        ;;
    esac
  done
  IFS="$old_ifs"
  return 1
}

is_closeout_terminal_status() {
  local status="$1"
  if [ "$status" = "$TERMINAL_STATUS" ]; then
    return 0
  fi
  case "$status" in
    Done|Merged|Released|Cancelled) return 0 ;;
    *) ;;
  esac
  is_terminal_tracker_status "$status"
}

tracker_status_for_issue() {
  local issue="$1"
  get_tracker_status_for_issue "$issue" | awk '
    /^TRACKER_ACTION_REQUIRED=/ { next }
    { value=$0 }
    END { print value }
  '
}

ensure_terminal_tracker_status() {
  local issue="$1"
  local before after
  before="$(tracker_status_for_issue "$issue")"
  if is_closeout_terminal_status "$before"; then
    return 0
  fi
  update_tracker_status_best_effort "$issue" "$TERMINAL_STATUS" "" "allow-backward" >/dev/null
  after="$(tracker_status_for_issue "$issue")"
  is_closeout_terminal_status "$after"
}

extract_closing_issue_numbers() {
  grep -ioE '(^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+' \
    | grep -oE '[0-9]+$' \
    | sort -un || true
}

validate_graduation_pr() {
  local pr_json parsed state merged_at base_ref head_ref
  if ! pr_json="$(gh pr view "$GRADUATION_PR" --json number,state,mergedAt,baseRefName,headRefName 2>/dev/null)"; then
    echo "ERROR: could not read graduation PR #${GRADUATION_PR}." >&2
    exit 1
  fi
  if ! parsed="$(printf '%s' "$pr_json" | python3 -c '
import json, sys
try:
    pr = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print(pr.get("state") or "")
print(pr.get("mergedAt") or "")
print(pr.get("baseRefName") or "")
print(pr.get("headRefName") or "")
')"; then
    echo "ERROR: could not parse graduation PR #${GRADUATION_PR}." >&2
    exit 1
  fi
  state="$(printf '%s\n' "$parsed" | sed -n '1p')"
  merged_at="$(printf '%s\n' "$parsed" | sed -n '2p')"
  base_ref="$(printf '%s\n' "$parsed" | sed -n '3p')"
  head_ref="$(printf '%s\n' "$parsed" | sed -n '4p')"
  if [ "$head_ref" != "$INTEGRATION_BRANCH" ]; then
    echo "ERROR: graduation PR #${GRADUATION_PR} head is '${head_ref:-unknown}', expected '${INTEGRATION_BRANCH}'." >&2
    exit 1
  fi
  if [ "$base_ref" != "develop" ]; then
    echo "ERROR: graduation PR #${GRADUATION_PR} base is '${base_ref:-unknown}', expected 'develop'." >&2
    exit 1
  fi
  if [ "$state" != "MERGED" ] && [ -z "$merged_at" ]; then
    echo "ERROR: graduation PR #${GRADUATION_PR} has not merged yet; closeout is post-merge only." >&2
    exit 1
  fi
}

discover_native_subissues() {
  local after=""
  local has_next="true"
  local response
  local -a graphql_args

  while [ "$has_next" = "true" ]; do
    graphql_args=(
      gh api graphql
      -F owner="$REPO_OWNER"
      -F repo="$REPO_NAME"
      -F number="$EPIC_ISSUE"
    )
    if [ -n "$after" ]; then
      graphql_args+=(-f after="$after")
    fi
    # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub.
    graphql_args+=(
      -f query='
        query($owner: String!, $repo: String!, $number: Int!, $after: String) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              subIssues(first: 100, after: $after) {
                nodes {
                  number
                  title
                  state
                  labels(first: 50) { nodes { name } }
                }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      '
    )
    if ! response="$("${graphql_args[@]}" 2>/dev/null)"; then
      return 1
    fi
    if [ -z "$response" ]; then
      return 1
    fi
    printf '%s' "$response" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
issue = (((data.get("data") or {}).get("repository") or {}).get("issue") or {})
subissues = issue.get("subIssues") or {}
for node in subissues.get("nodes") or []:
    number = node.get("number")
    if number:
        print(number)
page = subissues.get("pageInfo") or {}
print("HAS_NEXT=" + ("true" if page.get("hasNextPage") else "false"), file=sys.stderr)
print("END_CURSOR=" + (page.get("endCursor") or ""), file=sys.stderr)
' > "$TMP_DIR/native-page.out" 2> "$TMP_DIR/native-page.meta" || return 1
    while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      append_candidate "$issue" "native-subissue"
    done < "$TMP_DIR/native-page.out"
    has_next="$(awk -F= '/^HAS_NEXT=/{print $2}' "$TMP_DIR/native-page.meta")"
    after="$(awk -F= '/^END_CURSOR=/{print $2}' "$TMP_DIR/native-page.meta")"
    if [ -z "$has_next" ]; then
      has_next="false"
    fi
  done
  return 0
}

discover_label_subitems() {
  local output
  if ! output="$(gh issue list --label "$INTEGRATION_LABEL" --state all --limit 1000 --json number,title,state,labels --jq '.[] | .number' 2>/dev/null)"; then
    return 1
  fi
  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    append_candidate "$issue" "label:${INTEGRATION_LABEL}"
  done <<< "$output"
}

discover_closing_keyword_refs() {
  local prs_json
  if ! prs_json="$(gh pr list --state merged --base "$INTEGRATION_BRANCH" --limit 1000 --json number,title,body 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$prs_json" | python3 -c '
import json, sys
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for pr in prs or []:
    number = pr.get("number")
    text = ((pr.get("title") or "") + "\n" + (pr.get("body") or "")).replace("\t", " ")
    if number:
        print(f"PR\t{number}\t{text.replace(chr(10), chr(30))}")
' > "$TMP_DIR/merged-prs.tsv"
  while IFS="$(printf '\t')" read -r marker pr_number text; do
    [ "$marker" = "PR" ] || continue
    printf '%s' "$text" | tr "$(printf '\036')" '\n' | extract_closing_issue_numbers > "$TMP_DIR/pr-${pr_number}-issues.txt"
    while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      append_candidate "$issue" "pr:${pr_number}"
    done < "$TMP_DIR/pr-${pr_number}-issues.txt"
  done < "$TMP_DIR/merged-prs.tsv"
}

issue_source_summary() {
  local issue="$1"
  awk -F '\t' -v issue="$issue" '$1 == issue { print $2 }' "$CANDIDATES_FILE" \
    | sort -u \
    | paste -sd ',' -
}

issue_details_tsv() {
  local issue="$1"
  gh issue view "$issue" --json number,title,state,labels 2>/dev/null | python3 -c '
import json, sys
try:
    item = json.load(sys.stdin)
except Exception:
    sys.exit(1)
labels = ",".join((label.get("name") or "") for label in (item.get("labels") or []))
print("{}\t{}\t{}\t{}".format(
    item.get("number") or "",
    (item.get("title") or "").replace("\t", " "),
    item.get("state") or "",
    labels,
))
'
}

record_result() {
  local file="$1"
  local issue="$2"
  local title="$3"
  local source="$4"
  local reason="$5"
  printf '#%s\t%s\t%s\t%s\n' "$issue" "$title" "$source" "$reason" >> "$file"
}

close_issue_with_comment() {
  local issue="$1"
  local kind="$2"
  local comment
  comment="${kind} delivered via graduation PR #${GRADUATION_PR} from \`${INTEGRATION_BRANCH}\` to \`develop\`. Tracker status reconciled by graduation closeout."
  gh issue close "$issue" --comment "$comment" >/dev/null
}

process_delivered_issue() {
  local issue="$1"
  local details title state labels source status
  if ! details="$(issue_details_tsv "$issue")"; then
    record_result "$FAILED_FILE" "$issue" "(unknown)" "$(issue_source_summary "$issue")" "could_not_read_issue"
    return
  fi
  IFS="$(printf '\t')" read -r _ title state labels <<< "$details"
  source="$(issue_source_summary "$issue")"
  status="$(tracker_status_for_issue "$issue")"

  if is_excluded_issue "$issue" || is_skip_label "$labels"; then
    record_result "$SKIPPED_FILE" "$issue" "$title" "$source" "requires_human_disposition"
    return
  fi

  if [ "$state" != "OPEN" ] && is_closeout_terminal_status "$status"; then
    record_result "$ALREADY_FILE" "$issue" "$title" "$source" "already_terminal"
    return
  fi

  if [ "$state" = "OPEN" ]; then
    if ! close_issue_with_comment "$issue" "Sub-item"; then
      record_result "$FAILED_FILE" "$issue" "$title" "$source" "issue_close_failed"
      return
    fi
  fi

  if ! ensure_terminal_tracker_status "$issue"; then
    record_result "$FAILED_FILE" "$issue" "$title" "$source" "tracker_status_update_failed"
    return
  fi

  record_result "$CLOSED_FILE" "$issue" "$title" "$source" "delivered_terminal"
}

process_epic() {
  local failed_count="$1"
  local details title state status
  if [ "$DEFER_EPIC_CLOSE" -eq 1 ]; then
    printf 'EPIC_RESULT=deferred\n'
    printf 'EPIC_REASON=operator_deferred\n'
    return 0
  fi
  if [ "$failed_count" -gt 0 ]; then
    printf 'EPIC_RESULT=held\n'
    printf 'EPIC_REASON=delivered_subitem_failures\n'
    return 1
  fi
  if ! details="$(issue_details_tsv "$EPIC_ISSUE")"; then
    printf 'EPIC_RESULT=failed\n'
    printf 'EPIC_REASON=could_not_read_epic\n'
    return 1
  fi
  IFS="$(printf '\t')" read -r _ title state _ <<< "$details"
  status="$(tracker_status_for_issue "$EPIC_ISSUE")"
  if [ "$state" != "OPEN" ] && is_closeout_terminal_status "$status"; then
    printf 'EPIC_RESULT=already_terminal\n'
    return 0
  fi
  if [ "$state" = "OPEN" ]; then
    if ! close_issue_with_comment "$EPIC_ISSUE" "Epic"; then
      printf 'EPIC_RESULT=failed\n'
      printf 'EPIC_REASON=issue_close_failed\n'
      return 1
    fi
  fi
  if ! ensure_terminal_tracker_status "$EPIC_ISSUE"; then
    printf 'EPIC_RESULT=failed\n'
    printf 'EPIC_REASON=tracker_status_update_failed\n'
    return 1
  fi
  printf 'EPIC_RESULT=closed\n'
  return 0
}

count_file_lines() {
  wc -l < "$1" | tr -d ' '
}

print_section() {
  local name="$1"
  local file="$2"
  echo "${name}:"
  if [ -s "$file" ]; then
    sed 's/^/  /' "$file"
  else
    echo "  (none)"
  fi
}

validate_graduation_pr

if ! discover_native_subissues; then
  echo "Warning: native sub-issue discovery failed for epic #${EPIC_ISSUE}; using label fallback only." >&2
fi
if [ ! -s "$CANDIDATES_FILE" ]; then
  if ! discover_label_subitems; then
    echo "Warning: label fallback discovery failed for ${INTEGRATION_LABEL}." >&2
    record_result "$FAILED_FILE" "discovery" "Candidate discovery" "label:${INTEGRATION_LABEL}" "label_fallback_failed"
  fi
else
  # Still include label-discovered legacy items when native sub-issues exist.
  if ! discover_label_subitems; then
    echo "Warning: label fallback discovery failed for ${INTEGRATION_LABEL}." >&2
    record_result "$FAILED_FILE" "discovery" "Candidate discovery" "label:${INTEGRATION_LABEL}" "label_fallback_failed"
  fi
fi
if ! discover_closing_keyword_refs; then
  echo "Warning: could not read merged PR closing-keyword references for ${INTEGRATION_BRANCH}." >&2
  record_result "$FAILED_FILE" "discovery" "Candidate discovery" "pr:${INTEGRATION_BRANCH}" "merged_pr_discovery_failed"
fi
if [ ! -s "$CANDIDATES_FILE" ]; then
  record_result "$FAILED_FILE" "discovery" "Candidate discovery" "native-subissue,label:${INTEGRATION_LABEL},pr:${INTEGRATION_BRANCH}" "no_delivered_subitems_discovered"
fi

cut -f1 "$CANDIDATES_FILE" | sort -n -u > "$UNIQUE_ISSUES_FILE"

while IFS= read -r issue; do
  [ -z "$issue" ] && continue
  if [ "$issue" = "$EPIC_ISSUE" ]; then
    continue
  fi
  process_delivered_issue "$issue"
done < "$UNIQUE_ISSUES_FILE"

CLOSED_COUNT="$(count_file_lines "$CLOSED_FILE")"
ALREADY_TERMINAL_COUNT="$(count_file_lines "$ALREADY_FILE")"
SKIPPED_OPTIONAL_COUNT="$(count_file_lines "$SKIPPED_FILE")"
FAILED_COUNT="$(count_file_lines "$FAILED_FILE")"

EPIC_OUTPUT="$TMP_DIR/epic.out"
EPIC_STATUS=0
process_epic "$FAILED_COUNT" > "$EPIC_OUTPUT" || EPIC_STATUS=$?

echo "GRADUATION_CLOSEOUT_RESULT=$([ "$FAILED_COUNT" -eq 0 ] && [ "$EPIC_STATUS" -eq 0 ] && echo pass || echo failed)"
echo "SLUG=$SLUG"
echo "INTEGRATION_BRANCH=$INTEGRATION_BRANCH"
echo "GRADUATION_PR=$GRADUATION_PR"
echo "EPIC_ISSUE=$EPIC_ISSUE"
cat "$EPIC_OUTPUT"
echo "TERMINAL_STATUS=$TERMINAL_STATUS"
echo "CLOSED_COUNT=$CLOSED_COUNT"
echo "ALREADY_TERMINAL_COUNT=$ALREADY_TERMINAL_COUNT"
echo "SKIPPED_OPTIONAL_COUNT=$SKIPPED_OPTIONAL_COUNT"
echo "FAILED_COUNT=$FAILED_COUNT"
print_section "closed" "$CLOSED_FILE"
print_section "already_terminal" "$ALREADY_FILE"
print_section "skipped_optional" "$SKIPPED_FILE"
print_section "failed" "$FAILED_FILE"

if [ "$FAILED_COUNT" -gt 0 ] || [ "$EPIC_STATUS" -ne 0 ]; then
  exit 1
fi
