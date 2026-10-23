#!/usr/bin/env bash
#
# Reconcile delivered integration-branch sub-items after a graduation PR merges.
#
# Usage:
#   ./scripts/development-workflow/graduation-closeout.sh --slug <slug> --graduation-pr <number> --epic <epic-id> [--base <branch>] [--exclude-issue <number>]... [--defer-epic-close] [--dry-run]
#
#   --epic  GitHub issue number when issue_tracker.provider is github_projects
#           or github_issues. With provider linear, must be a native Linear ID
#           with team prefix (e.g. LEA-326). A bare number with linear fails
#           closed (no GitHub mutation from the numeric suffix).
#
#   --base defaults to 'develop'. Override when the graduation PR targets a
#           parent integration branch instead of develop — e.g. a nested wave
#           branch develop-ventas-e3b graduating into a module branch
#           develop-sales-module. Must be 'develop' or a 'develop-*'
#           integration branch; an arbitrary feature/fix branch is rejected
#           up front regardless of what the graduation PR actually targets.
#
#   --dry-run  Print every external mutation (gh issue close/edit/comment,
#           label edits, tracker status updates / deferred actions) with a
#           DRY_RUN would: prefix and apply none of them.
#
# Env overrides:
#   GRADUATION_BASE                  Same as --base; --base takes precedence.
#   GITHUB_PROJECT_STATUS_GRADUATED  Terminal status for graduated work.
#   GITHUB_PROJECT_STATUS_MERGED     Fallback terminal status.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=./workflow-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/workflow-lib.sh"
# shellcheck source=./graduation-closeout-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/graduation-closeout-lib.sh"
# shellcheck source=./closing-keyword-lib.sh
# shellcheck disable=SC1091
. "$SCRIPT_DIR/closing-keyword-lib.sh"

SLUG=""
GRADUATION_PR=""
EPIC_ISSUE=""
DEFER_EPIC_CLOSE=0
DRY_RUN=0
declare -a EXCLUDED_ISSUES=()
GRADUATION_BASE="${GRADUATION_BASE:-develop}"
TRACKER_PROVIDER=""

usage() {
  cat >&2 <<'EOF'
Usage:
  graduation-closeout.sh --slug <slug> --graduation-pr <number> --epic <epic-id> [--base <branch>] [--exclude-issue <number>]... [--defer-epic-close] [--dry-run]

  --epic  GitHub issue number (github_projects / github_issues). With
          issue_tracker.provider=linear, a native Linear ID (e.g. LEA-326).
  --base  Expected graduation PR base branch (default: develop). Override
          for nested graduation into a parent integration branch, e.g.
          --base develop-sales-module. Must be 'develop' or 'develop-*'.
  --dry-run  Print planned external mutations and apply none of them.
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

# Native Linear issue identifier with team prefix (e.g. LEA-326).
is_linear_issue_id() {
  [[ "$1" =~ ^[A-Z][A-Z0-9_]*-[0-9]+$ ]]
}

is_valid_slug() {
  case "$1" in
    ''|*[^a-zA-Z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_valid_graduation_base() {
  # A "real check" per issue #1513: reject an arbitrary feature/fix branch
  # up front, independent of what the graduation PR actually targets.
  # Graduation always lands on develop itself or on another develop-*
  # integration branch (nested graduation).
  case "$1" in
    develop) return 0 ;;
    develop-*) is_valid_slug "${1#develop-}" ;;
    *) return 1 ;;
  esac
}

# Print every external mutation before apply; dry-run prints and skips apply.
announce_mutation() {
  local description="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY_RUN would: %s\n' "$description"
    return 1
  fi
  printf 'MUTATION: %s\n' "$description"
  return 0
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
    --base)
      require_value "$@"
      GRADUATION_BASE="$2"
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
    --dry-run)
      DRY_RUN=1
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
if ! is_valid_graduation_base "$GRADUATION_BASE"; then
  echo "ERROR: --base must be 'develop' or a 'develop-*' integration branch (got '${GRADUATION_BASE}')." >&2
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

# Resolve tracker provider after repo root is known (same pattern as #1930).
TRACKER_PROVIDER_RAW=""
TRACKER_PROVIDER_RAW="$(workflow_graduation_closeout_tracker_provider_raw "$(pwd)")" || exit $?
TRACKER_PROVIDER="$(workflow_normalize_issue_tracker_provider "$TRACKER_PROVIDER_RAW")"
case "$TRACKER_PROVIDER" in
  linear) ;;
  github_projects|github_issues|'')
    # Empty / unset keeps historical GitHub Projects closeout behavior.
    TRACKER_PROVIDER="${TRACKER_PROVIDER:-github_projects}"
    ;;
  none)
    TRACKER_PROVIDER="github_projects"
    ;;
  *)
    printf 'configuration: configuration validation error; key=issue_tracker.provider\n' >&2
    exit 64
    ;;
esac

# Shared parser (workflow_config_provider) must also see linear — the tracker
# bridge uses that path. A commented `issue_tracker:` header can make the
# closeout-local reader say linear while the bridge still defaults to
# github_projects; fail closed before any mutation.
if [ "$TRACKER_PROVIDER" = "linear" ]; then
  SHARED_TRACKER_PROVIDER="$(workflow_normalize_issue_tracker_provider "$(workflow_config_provider issue_tracker "$(pwd)/.ai-dev-workflow.yaml")")"
  if [ "$SHARED_TRACKER_PROVIDER" != "linear" ]; then
    echo "ERROR: issue_tracker.provider is linear but the tracker bridge cannot read it (commented section header?). Remove the trailing comment from the 'issue_tracker:' line in .ai-dev-workflow.yaml and rerun." >&2
    exit 64
  fi
fi

if [ "$TRACKER_PROVIDER" = "linear" ]; then
  if ! is_linear_issue_id "$EPIC_ISSUE"; then
    echo "ERROR: with issue_tracker.provider=linear, --epic must be a native Linear ID with team prefix (e.g. LEA-326), not a bare number. Refusing to mutate GitHub issues from a numeric suffix." >&2
    exit 64
  fi
else
  if ! is_positive_int "$EPIC_ISSUE"; then
    echo "ERROR: --epic must be a positive integer." >&2
    exit 64
  fi
fi

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
  local before after update_out update_rc
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    # Linear transitions are deferred to the native bridge. Success requires an
    # observed TRACKER_ACTION_REQUIRED= line for this issue — a silent skip
    # (e.g. merge-session binding failure that returns 0 with empty stdout)
    # must not report EPIC_RESULT=closed.
    if ! announce_mutation "update_tracker_status ${issue} → ${TERMINAL_STATUS} (linear deferred)"; then
      return 0
    fi
    update_rc=0
    update_out="$(update_tracker_status_best_effort "$issue" "$TERMINAL_STATUS" "" "allow-backward")" || update_rc=$?
    printf '%s\n' "$update_out"
    if [ "$update_rc" -ne 0 ]; then
      echo "ERROR: Linear tracker update for ${issue} → ${TERMINAL_STATUS} failed (exit ${update_rc}); no deferred action observed." >&2
      return 1
    fi
    case "$update_out" in
      *TRACKER_ACTION_REQUIRED=*"issue=${issue}"*) return 0 ;;
    esac
    echo "ERROR: Linear tracker update for ${issue} → ${TERMINAL_STATUS} returned success without emitting TRACKER_ACTION_REQUIRED= for that issue; refusing to report closed." >&2
    return 1
  fi
  before="$(tracker_status_for_issue "$issue")"
  if is_closeout_terminal_status "$before"; then
    return 0
  fi
  if ! announce_mutation "update_tracker_status #${issue} → ${TERMINAL_STATUS}"; then
    return 0
  fi
  update_tracker_status_best_effort "$issue" "$TERMINAL_STATUS" "" "allow-backward" >/dev/null
  after="$(tracker_status_for_issue "$issue")"
  is_closeout_terminal_status "$after"
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
  if [ "$base_ref" != "$GRADUATION_BASE" ]; then
    echo "ERROR: graduation PR #${GRADUATION_PR} base is '${base_ref:-unknown}', expected '${GRADUATION_BASE}'." >&2
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
  # GitHub Projects / GitHub Issues path only. For each merged PR, render
  # title and body separately via GitHub GFM (`gh api markdown`), extract
  # visible text outside <pre>/<code>, then scan with shared
  # closing_keyword_live_refs. Title and body stay independent documents.
  # Fail closed per PR: any render/extract failure contributes no text-derived
  # refs for that PR (never fall back to raw markdown). Cross-repo
  # owner/repo#N never matches the shared keyword pattern. Linear must not
  # call this — see discover_linear_merged_pr_issue_refs.
  local prs_json context
  context="${REPO_OWNER}/${REPO_NAME}"
  if ! prs_json="$(gh pr list --state merged --base "$INTEGRATION_BRANCH" --limit 1000 --json number,title,body 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$prs_json" | python3 -c '
import json, sys
RS = chr(30)  # record newline
US = chr(31)  # record tab (must survive TSV; GFM cares about real tabs)
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for pr in prs or []:
    number = pr.get("number")
    if not number:
        continue
    title = (pr.get("title") or "").replace("\t", US).replace("\n", RS)
    body = (pr.get("body") or "").replace("\t", US).replace("\n", RS)
    print("%s\t%s\t%s" % (number, title, body))
' > "$TMP_DIR/merged-prs.tsv"
  while IFS="$(printf '\t')" read -r pr_number title_enc body_enc; do
    [ -n "$pr_number" ] || continue
    local title body title_refs body_refs
    # Preserve trailing newlines: $(...) strips them; append a sentinel.
    # Map RS→newline and US→tab so GFM sees real indentation.
    title="$(printf '%s' "$title_enc" | tr "$(printf '\036\037')" "$(printf '\n\t')"; printf x)"
    title="${title%x}"
    body="$(printf '%s' "$body_enc" | tr "$(printf '\036\037')" "$(printf '\n\t')"; printf x)"
    body="${body%x}"
    : > "$TMP_DIR/pr-${pr_number}-issues.txt"
    local need_title=0 need_body=0
    if printf '%s' "$title" | graduation_closeout_raw_has_closing_keyword_candidate; then
      need_title=1
    fi
    if printf '%s' "$body" | graduation_closeout_raw_has_closing_keyword_candidate; then
      need_body=1
    fi
    if [ "$need_title" -eq 0 ] && [ "$need_body" -eq 0 ]; then
      continue
    fi
    if [ "$need_title" -eq 1 ]; then
      if ! title_refs="$(printf '%s' "$title" | graduation_closeout_github_live_refs_from_markdown "$context")"; then
        echo "CLOSEOUT_TEXT_REFS_UNAVAILABLE pr=${pr_number} reason=gfm_render_or_extract_failed" >&2
        continue
      fi
    else
      title_refs=""
    fi
    if [ "$need_body" -eq 1 ]; then
      if ! body_refs="$(printf '%s' "$body" | graduation_closeout_github_live_refs_from_markdown "$context")"; then
        echo "CLOSEOUT_TEXT_REFS_UNAVAILABLE pr=${pr_number} reason=gfm_render_or_extract_failed" >&2
        continue
      fi
    else
      body_refs=""
    fi
    {
      printf '%s\n' "$title_refs"
      printf '%s\n' "$body_refs"
    } | sed '/^$/d' > "$TMP_DIR/pr-${pr_number}-issues.txt"
    while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      append_candidate "$issue" "pr:${pr_number}"
    done < "$TMP_DIR/pr-${pr_number}-issues.txt"
  done < "$TMP_DIR/merged-prs.tsv"
}

discover_linear_merged_pr_issue_refs() {
  # Linear path: mutate GitHub issues ONLY via same-repo structured
  # closingIssuesReferences. Text-only closing keywords (plain, fenced,
  # indented, etc.) are reported and skipped — never mutation candidates.
  # Integration-branch PRs often leave structured refs empty; that means no
  # GitHub issue is closed (safe by design).
  local prs_json
  if ! prs_json="$(gh pr list --state merged --base "$INTEGRATION_BRANCH" --limit 1000 --json number,title,body,closingIssuesReferences 2>/dev/null)"; then
    return 1
  fi
  printf '%s' "$prs_json" | python3 -c '
import json, re, sys

RS = chr(30)
expected = (sys.argv[1] or "").strip().lower()
try:
    prs = json.load(sys.stdin)
except Exception:
    sys.exit(1)

def ref_repo(ref):
    repo = ((ref.get("repository") or {}).get("nameWithOwner") or "").strip()
    if repo:
        return repo
    url = (ref.get("url") or "").strip()
    match = re.match(r"https?://github\.com/([^/]+/[^/]+)/issues/\d+", url, re.I)
    if match:
        return match.group(1)
    return ""

keyword_re = re.compile(
    r"(^|[^A-Za-z0-9_])(close[sd]?|fix(?:es|ed)?|resolve[sd]?)\s+(?:issue\s+)?#(\d+)",
    re.I,
)

for pr in prs or []:
    pr_number = pr.get("number")
    if not pr_number:
        continue
    accepted = set()
    for ref in pr.get("closingIssuesReferences") or []:
        issue = ref.get("number")
        if not issue:
            continue
        repo = ref_repo(ref)
        if not repo:
            print(
                "FOREIGN_CLOSING_REF\t{}\t{}\t(missing repository identity)".format(
                    pr_number, issue
                ),
                file=sys.stderr,
            )
            continue
        if repo.lower() != expected:
            print(
                "FOREIGN_CLOSING_REF\t{}\t{}\t{}".format(pr_number, issue, repo),
                file=sys.stderr,
            )
            continue
        accepted.add(int(issue))
        print("STRUCTURED\t{}\t{}".format(pr_number, issue))
    title = pr.get("title") or ""
    body = pr.get("body") or ""
    text = title + "\n" + body
    # Reporting-only scan of raw text (including fences/indent). Never mutate.
    for match in keyword_re.finditer(text):
        issue = int(match.group(3))
        if issue in accepted:
            continue
        print("TEXT_ONLY\t{}\t{}".format(pr_number, issue))
' "$REPO_SLUG" > "$TMP_DIR/linear-pr-discovery.tsv" 2> "$TMP_DIR/structured-closing-refs.err" || return 1
  if [ -s "$TMP_DIR/structured-closing-refs.err" ]; then
    while IFS="$(printf '\t')" read -r marker pr_number issue repo_or_reason; do
      [ "$marker" = "FOREIGN_CLOSING_REF" ] || continue
      echo "Warning: skipping foreign closingIssuesReferences from PR #${pr_number}: #${issue} in ${repo_or_reason} (local repo is ${REPO_SLUG})." >&2
    done < "$TMP_DIR/structured-closing-refs.err"
  fi
  while IFS="$(printf '\t')" read -r kind pr_number payload; do
    [ -n "$kind" ] || continue
    case "$kind" in
      STRUCTURED)
        [ -z "$payload" ] && continue
        append_candidate "$payload" "pr:${pr_number}:closingIssuesReferences"
        ;;
      TEXT_ONLY)
        [ -z "$payload" ] && continue
        printf 'LINEAR_GITHUB_REF_SKIPPED issue=%s reason=not_structurally_linked pr=%s\n' \
          "$payload" "$pr_number"
        ;;
    esac
  done < "$TMP_DIR/linear-pr-discovery.tsv"
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
  comment="${kind} delivered via graduation PR #${GRADUATION_PR} from \`${INTEGRATION_BRANCH}\` to \`${GRADUATION_BASE}\`. Tracker status reconciled by graduation closeout."
  if ! announce_mutation "gh issue close #${issue} --comment (${kind})"; then
    return 0
  fi
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

  if is_excluded_issue "$issue" || is_skip_label "$labels"; then
    record_result "$SKIPPED_FILE" "$issue" "$title" "$source" "requires_human_disposition"
    return
  fi

  # Linear tracker: GitHub candidates here are only PR-linked issues. Close the
  # GitHub issue when open, but never send the GitHub number through the Linear
  # bridge (numeric suffix is not a Linear ID).
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    if [ "$state" != "OPEN" ]; then
      record_result "$ALREADY_FILE" "$issue" "$title" "$source" "already_terminal"
      return
    fi
    if ! close_issue_with_comment "$issue" "Sub-item"; then
      record_result "$FAILED_FILE" "$issue" "$title" "$source" "issue_close_failed"
      return
    fi
    record_result "$CLOSED_FILE" "$issue" "$title" "$source" "delivered_terminal"
    return
  fi

  status="$(tracker_status_for_issue "$issue")"

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

ensure_defer_epic_close_label() {
  # Durable automation signal shared with merge-time closeout fallback (AC4).
  # Linear epics are not GitHub issues — never derive a GH number from LEA-N.
  local labels_csv has_label old_ifs label normalized
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    if ! announce_mutation "defer-epic-close signal for Linear epic ${EPIC_ISSUE} (no GitHub label mutation)"; then
      printf 'DEFER_LABEL=dry_run\n'
      return 0
    fi
    printf 'DEFER_LABEL=linear_bridge_deferred\n'
    return 0
  fi
  if ! labels_csv="$(gh issue view "$EPIC_ISSUE" --json labels --jq '[.labels[].name] | join(",")' 2>/dev/null)"; then
    echo "ERROR: could not read labels on epic #${EPIC_ISSUE} to ensure defer-epic-close." >&2
    return 1
  fi
  has_label=0
  if [ -n "$labels_csv" ]; then
    old_ifs="$IFS"
    IFS=','
    # shellcheck disable=SC2086
    for label in $labels_csv; do
      normalized="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
      if [ "$normalized" = "defer-epic-close" ]; then
        has_label=1
        break
      fi
    done
    IFS="$old_ifs"
  fi
  if [ "$has_label" -eq 1 ]; then
    printf 'DEFER_LABEL=already_present\n'
    return 0
  fi
  if ! announce_mutation "gh issue edit #${EPIC_ISSUE} --add-label defer-epic-close"; then
    printf 'DEFER_LABEL=dry_run\n'
    return 0
  fi
  if gh issue edit "$EPIC_ISSUE" --add-label "defer-epic-close" >/dev/null 2>&1; then
    printf 'DEFER_LABEL=added\n'
    return 0
  fi
  # Label may not exist in the repository yet — create then retry once.
  if ! announce_mutation "gh label create defer-epic-close + gh issue edit #${EPIC_ISSUE} --add-label"; then
    printf 'DEFER_LABEL=dry_run\n'
    return 0
  fi
  if gh label create "defer-epic-close" \
      --description "Operator deferred epic close after graduation; merge-time automation must honor this." \
      --color "FBCA04" >/dev/null 2>&1 \
    && gh issue edit "$EPIC_ISSUE" --add-label "defer-epic-close" >/dev/null 2>&1; then
    printf 'DEFER_LABEL=added\n'
    return 0
  fi
  echo "ERROR: --defer-epic-close requires durable label defer-epic-close on epic #${EPIC_ISSUE}, but the label could not be applied." >&2
  return 1
}

process_epic() {
  local failed_count="$1"
  local details title state status
  if [ "$DEFER_EPIC_CLOSE" -eq 1 ]; then
    if ! ensure_defer_epic_close_label; then
      printf 'EPIC_RESULT=failed\n'
      printf 'EPIC_REASON=defer_label_ensure_failed\n'
      return 1
    fi
    printf 'EPIC_RESULT=deferred\n'
    printf 'EPIC_REASON=operator_deferred\n'
    return 0
  fi
  if [ "$failed_count" -gt 0 ]; then
    printf 'EPIC_RESULT=held\n'
    printf 'EPIC_REASON=delivered_subitem_failures\n'
    return 1
  fi

  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    # Never gh issue view/close the Linear ID's numeric suffix.
    if ! ensure_terminal_tracker_status "$EPIC_ISSUE"; then
      printf 'EPIC_RESULT=failed\n'
      printf 'EPIC_REASON=tracker_status_update_failed\n'
      return 1
    fi
    printf 'EPIC_RESULT=closed\n'
    printf 'EPIC_CLOSE_MODE=linear_deferred\n'
    return 0
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

if [ "$TRACKER_PROVIDER" = "linear" ]; then
  # Linear sub-items are not GitHub subIssues. Never query subIssues with the
  # Linear ID or its numeric suffix. Mutate GitHub issues only via same-repo
  # structured closingIssuesReferences; text-only keywords are reported/skipped.
  echo "TRACKER_PROVIDER=linear — skipping GitHub subIssues and label fallback; discovering same-repo structured closingIssuesReferences only."
  if ! discover_linear_merged_pr_issue_refs; then
    echo "Warning: could not read structured closingIssuesReferences for merged PRs targeting ${INTEGRATION_BRANCH}." >&2
    record_result "$FAILED_FILE" "discovery" "Candidate discovery" "pr:${INTEGRATION_BRANCH}" "merged_pr_discovery_failed"
  fi
  if [ ! -s "$CANDIDATES_FILE" ] && [ ! -s "$FAILED_FILE" ]; then
    echo "Note: no structured same-repo GitHub closing refs discovered; proceeding with Linear epic closeout only."
  fi
else
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
fi

cut -f1 "$CANDIDATES_FILE" | sort -n -u > "$UNIQUE_ISSUES_FILE"

while IFS= read -r issue; do
  [ -z "$issue" ] && continue
  if [ "$TRACKER_PROVIDER" != "linear" ] && [ "$issue" = "$EPIC_ISSUE" ]; then
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
echo "GRADUATION_BASE=$GRADUATION_BASE"
echo "GRADUATION_PR=$GRADUATION_PR"
echo "EPIC_ISSUE=$EPIC_ISSUE"
echo "TRACKER_PROVIDER=$TRACKER_PROVIDER"
echo "DRY_RUN=$DRY_RUN"
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
