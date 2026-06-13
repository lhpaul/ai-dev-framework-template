#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

PR_MARKER="<!-- run-epic:pr-disposition -->"
EPIC_MARKER="<!-- run-epic:epic-ledger -->"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <file>
  ./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <file> --pr <number>
  ./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <file>
  ./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <file> --epic <number>

Renders or applies stable /run-epic audit comments. Apply mode updates an
existing marker comment or creates one when no marker exists.
EOF
}

command="${1:-}"
[ "$#" -gt 0 ] && shift || true
input_file=""
pr_number=""
epic_number=""

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
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

load_input_json() {
  local file="$1"
  if [ ! -f "$file" ]; then
    error_exit "input file not found: $file"
  fi
  if [ ! -s "$file" ]; then
    error_exit "input file is empty: $file"
  fi
  jq -c '.' "$file" 2>/dev/null || error_exit "input file is not valid JSON: $file"
}

redact_text() {
  sed -E \
    -e 's#gh[pousr]_[A-Za-z0-9_]+#[REDACTED_TOKEN]#g' \
    -e 's#Bearer[[:space:]]+[A-Za-z0-9._=-]+#Bearer [REDACTED]#g' \
    -e 's#Authorization:[[:space:]]*[^[:space:]]+#Authorization: [REDACTED]#g' \
    -e 's#/Users/[^[:space:]|)]+#[REDACTED_LOCAL_PATH]#g' \
    -e 's#/tmp/[^[:space:]|)]+#[REDACTED_LOCAL_PATH]#g'
}

table_cell_filter='
  def cell:
    tostring
    | gsub("\\|"; "\\\\|")
    | gsub("\\r?\\n"; "<br>")
    | gsub("\\t"; " ");
'

render_pr_disposition() {
  local json="$1"
  local missing

  missing="$(printf '%s\n' "$json" | jq -r '
    [
      ["scope_source", .scope_source],
      ["item.number", .item.number],
      ["item.title", .item.title],
      ["pr.number", .pr.number],
      ["pr.head_sha", .pr.head_sha],
      ["reviewer.result", .reviewer.result],
      ["risk.level", .risk.level],
      ["merge_authority", .merge_authority],
      ["final_decision", .final_decision]
    ]
    | map(select(.[1] == null or (.[1] | tostring | length == 0)) | .[0])
    | join(", ")
  ')"
  if [ -n "$missing" ]; then
    error_exit "missing required PR disposition fields: $missing"
  fi

  {
    printf '%s\n' "$PR_MARKER"
    printf '## /run-epic PR Disposition\n\n'
    printf '%s\n' "$json" | jq -r '
      "- Scope source: " + (.scope_source | tostring),
      "- Item: #" + (.item.number | tostring) + " - " + (.item.title | tostring),
      "- PR: #" + (.pr.number | tostring),
      "- Reviewed head SHA: `" + (.pr.head_sha | tostring) + "`",
      "- Reviewer result: " + (.reviewer.result | tostring),
      "- Blocking findings: " + ((.reviewer.blocking_count // 0) | tostring),
      "- Advisory findings: " + ((.reviewer.advisory_count // 0) | tostring),
      "- Risk: " + (.risk.level | tostring),
      "- Merge authority: " + (.merge_authority | tostring),
      "- Final decision: " + (.final_decision | tostring)
    '
    printf '\n### Risk Reasons\n\n'
    printf '%s\n' "$json" | jq -r '(.risk.reasons // [])[]? | "- " + (.|tostring)'
    printf '\n### Advisory Decisions\n\n'
    if [ "$(printf '%s\n' "$json" | jq '(.advisories // []) | length')" -eq 0 ]; then
      printf 'None.\n'
    else
      printf '| Source | Category | Decision | Rationale |\n'
      printf '| --- | --- | --- | --- |\n'
      printf '%s\n' "$json" | jq -r "$table_cell_filter"'
        (.advisories // [])[] |
        "| " + ((.source // "") | cell) +
        " | " + ((.category // "") | cell) +
        " | " + ((.decision // "") | cell) +
        " | " + ((.rationale // "") | cell) + " |"
      '
    fi
    printf '\n### Verification Evidence\n\n'
    printf '%s\n' "$json" | jq -r '
      (.verification // {}) as $v |
      "- Labels: " + (($v.labels // []) | join(", ")),
      "- CI result: " + (($v.ci_result // "unknown") | tostring),
      "- Reviewer summary present: " + (($v.reviewer_summary_present // false) | tostring),
      "- Unresolved thread count: " + (($v.unresolved_thread_count // "unknown") | tostring),
      "- PR merge state: " + (($v.merge_state // "unknown") | tostring),
      "- Issue state: " + (($v.issue_state // "unknown") | tostring),
      "- Project status: " + (($v.project_status // "unknown") | tostring)
    '
    printf '\n### Protocol Deviations\n\n'
    if [ "$(printf '%s\n' "$json" | jq '(.protocol_deviations // []) | length')" -eq 0 ]; then
      printf 'None.\n'
    else
      printf '| Action | Impact | Mitigation |\n'
      printf '| --- | --- | --- |\n'
      printf '%s\n' "$json" | jq -r "$table_cell_filter"'
        (.protocol_deviations // [])[] |
        "| " + ((.action // "") | cell) +
        " | " + ((.impact // "") | cell) +
        " | " + ((.mitigation // "") | cell) + " |"
      '
    fi
  } | redact_text
}

validate_advisories() {
  local json="$1"
  local invalid
  invalid="$(printf '%s\n' "$json" | jq -r '
    (.advisories // [])
    | map(select((.decision // "") != "fixed" and ((.rationale // "") | gsub("\\s"; "") | length == 0)))
    | length
  ')"
  if [ "$invalid" -gt 0 ]; then
    error_exit "non-fixed advisory decisions require rationale"
  fi
}

render_epic_ledger() {
  local json="$1"

  if printf '%s\n' "$json" | jq -e '.epic_not_applicable == true' >/dev/null; then
    {
      printf '%s\n' "$EPIC_MARKER"
      printf '## /run-epic Epic Ledger\n\n'
      printf 'Not applicable: this run used an explicit item list with no parent epic.\n'
    }
    return
  fi

  if ! printf '%s\n' "$json" | jq -e '.epic.number and (.items | type == "array")' >/dev/null; then
    error_exit "missing required epic ledger fields"
  fi

  {
    printf '%s\n' "$EPIC_MARKER"
    printf '## /run-epic Epic Ledger\n\n'
    printf '%s\n\n' "$(printf '%s\n' "$json" | jq -r '"Epic: #" + (.epic.number | tostring) + " - " + (.epic.title // "")')"
    printf '| Issue | PR | Tracker status | Risk | Review | Decision | Merge / cleanup | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
    printf '%s\n' "$json" | jq -r "$table_cell_filter"'
      .items[] |
      "| #" + (.issue_number | tostring) + " " + ((.title // "") | cell) +
      " | " + (if .pr_number then "#" + (.pr_number | tostring) else "-" end) +
      " | " + ((.tracker_status // "") | cell) +
      " | " + ((.risk_level // "") | cell) +
      " | " + ((.review_result // "") | cell) +
      " | " + ((.decision // "") | cell) +
      " | " + ((.merge_cleanup // "") | cell) +
      " | " + ((.notes // "") | cell) + " |"
    '
  } | redact_text
}

find_marker_comment_id() {
  local target="$1"
  local marker="$2"
  local repo comments

  repo="$(repo_slug)"
  if ! comments="$(gh api --paginate --slurp "repos/${repo}/issues/${target}/comments" 2>/dev/null)"; then
    error_exit "failed to read comments for issue/PR #$target"
  fi
  printf '%s\n' "$comments" |
    jq -r --arg marker "$marker" '[.[][]? | select((.body // "") | contains($marker))][0].id // empty'
}

apply_comment() {
  local target="$1"
  local marker="$2"
  local body="$3"
  local repo comment_id

  require_gh
  repo="$(repo_slug)"
  comment_id="$(find_marker_comment_id "$target" "$marker")"
  if [ -n "$comment_id" ]; then
    jq -n --arg body "$body" '{body: $body}' |
      gh api -X PATCH "repos/${repo}/issues/comments/${comment_id}" --input - >/dev/null
    printf 'UPDATED_COMMENT_ID=%s\n' "$comment_id"
  else
    jq -n --arg body "$body" '{body: $body}' |
      gh api -X POST "repos/${repo}/issues/${target}/comments" --input - >/dev/null
    printf 'CREATED_COMMENT=1\n'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input)
      require_value "$@"
      input_file="$2"
      shift 2
      ;;
    --pr)
      require_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --epic)
      require_value "$@"
      epic_number="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$command" in
  render-pr-disposition|apply-pr-disposition|render-epic-ledger|apply-epic-ledger)
    ;;
  *)
    echo "ERROR: unknown or missing subcommand." >&2
    usage >&2
    exit 64
    ;;
esac

[ -n "$input_file" ] || error_exit "--input is required"
input_json="$(load_input_json "$input_file")"

case "$command" in
  render-pr-disposition)
    validate_advisories "$input_json"
    render_pr_disposition "$input_json"
    ;;
  apply-pr-disposition)
    if [ -z "$pr_number" ] || ! is_positive_int "$pr_number"; then
      error_exit "--pr must be a positive integer"
    fi
    validate_advisories "$input_json"
    body="$(render_pr_disposition "$input_json")"
    apply_comment "$pr_number" "$PR_MARKER" "$body"
    ;;
  render-epic-ledger)
    render_epic_ledger "$input_json"
    ;;
  apply-epic-ledger)
    if [ -z "$epic_number" ] || ! is_positive_int "$epic_number"; then
      error_exit "--epic must be a positive integer"
    fi
    body="$(render_epic_ledger "$input_json")"
    apply_comment "$epic_number" "$EPIC_MARKER" "$body"
    ;;
esac
