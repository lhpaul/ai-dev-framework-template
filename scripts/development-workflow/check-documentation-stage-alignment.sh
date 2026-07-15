#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

COMMENT_MARKER="<!-- documentation-stage-alignment -->"
MISMATCH_EXIT=8
INFRASTRUCTURE_EXIT=10

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/check-documentation-stage-alignment.sh --pr <number> [--json]
  ./scripts/development-workflow/check-documentation-stage-alignment.sh --input <file> [--json]

Checks whether spec/* and implementation-plan/* PRs contain only the expected
documentation-stage artifacts before ready-for-human-review is applied.
EOF
}

pr_number=""
input_file=""
json_output=0

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

infrastructure_exit() {
  echo "ERROR: $*" >&2
  exit "$INFRASTRUCTURE_EXIT"
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

normalize_fixture() {
  local file="$1"
  local raw

  if [ ! -f "$file" ]; then
    error_exit "input file not found: $file"
  fi
  if [ ! -s "$file" ]; then
    error_exit "input file is empty: $file"
  fi
  if ! raw="$(jq -c '.' "$file" 2>/dev/null)"; then
    error_exit "input file is not valid JSON: $file"
  fi
  if [ -z "$raw" ]; then
    error_exit "input file is not valid JSON: $file"
  fi

  printf '%s\n' "$raw"
}

live_pr_state() {
  local number="$1"
  local repo pr_json files_output files_json file_count

  if ! gh_available; then
    infrastructure_exit "GitHub CLI authentication is required for this script"
  fi
  if ! repo="$(repo_slug)"; then
    infrastructure_exit "failed to determine GitHub repository"
  fi

  if ! pr_json="$(gh pr view "$number" --repo "$repo" --json number,headRefName,baseRefName,title 2>/dev/null)"; then
    infrastructure_exit "failed to read PR #$number"
  fi
  if [ -z "$pr_json" ]; then
    infrastructure_exit "empty PR response for #$number"
  fi
  if ! files_output="$(gh pr diff "$number" --repo "$repo" --name-only 2>/dev/null)"; then
    infrastructure_exit "failed to read changed files for PR #$number"
  fi
  file_count="$(printf '%s\n' "$files_output" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$file_count" -gt 1000 ]; then
    infrastructure_exit "changed file list exceeds documentation-stage alignment limit of 1000 files"
  fi
  if ! files_json="$(printf '%s\n' "$files_output" | jq -R -s -c 'split("\n") | map(select(length > 0))')"; then
    infrastructure_exit "failed to normalize changed files for PR #$number"
  fi

  if ! printf '%s\n' "$pr_json" | jq --argjson files "$files_json" '{
    pr_number: .number,
    title: (.title // ""),
    head: .headRefName,
    base: .baseRefName,
    changed_files: $files
  }'; then
    infrastructure_exit "failed to normalize PR metadata for #$number"
  fi
}

stage_for_head() {
  case "$1" in
    spec/*) echo "spec" ;;
    implementation-plan/*) echo "plan" ;;
    *) echo "not_applicable" ;;
  esac
}

path_allowed_for_stage() {
  local stage="$1"
  local path="$2"

  case "$stage" in
    spec)
      [[ "$path" =~ ^docs/specs/developments/.+/1_.+_specs(\.doc)?\.md$ ]]
      ;;
    plan)
      [[ "$path" =~ ^docs/specs/developments/.+/2_.+_implementation-plan(\.doc)?\.md$ ]] ||
        [[ "$path" =~ ^docs/testing/.+\.smoke-test\.md$ ]]
      ;;
    *)
      return 1
      ;;
  esac
}

base64_decode() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

classify_state() {
  local state_json="$1"
  local head stage changed_count unexpected_json result aligned reason

  if [ "$(printf '%s\n' "$state_json" | jq -r '.diff_error // false')" = "true" ]; then
    infrastructure_exit "fixture indicates changed-file read failure"
  fi

  head="$(printf '%s\n' "$state_json" | jq -r '.head // .headRefName // ""')"
  stage="$(stage_for_head "$head")"

  if [ "$stage" = "not_applicable" ]; then
    jq -n \
      --arg stage "$stage" \
      --arg head "$head" \
      --arg result "not_applicable" \
      --arg marker "$COMMENT_MARKER" \
      '{stage: $stage, head: $head, result: $result, aligned: true, unexpected_files: [], warning_marker: $marker}'
    return 0
  fi

  changed_count="$(printf '%s\n' "$state_json" | jq '[.changed_files[]?, .files[]?.path?] | length')"
  unexpected_json='[]'

  if [ "$changed_count" -eq 0 ]; then
    aligned=false
    result="mismatch"
    reason="no stage artifact changed"
  else
    local encoded path
    while IFS= read -r encoded; do
      [ -z "$encoded" ] && continue
      path="$(printf '%s' "$encoded" | base64_decode)"
      if ! path_allowed_for_stage "$stage" "$path"; then
        unexpected_json="$(printf '%s\n' "$unexpected_json" | jq --arg path "$path" '. + [$path]')"
      fi
    done <<EOF
$(printf '%s\n' "$state_json" | jq -r '[.changed_files[]?, .files[]?.path?] | .[] | @base64')
EOF
    if [ "$(printf '%s\n' "$unexpected_json" | jq 'length')" -gt 0 ]; then
      aligned=false
      result="mismatch"
      reason="unexpected implementation or non-stage files changed"
    else
      aligned=true
      result="aligned"
      reason="all changed files match the documentation-stage allowlist"
    fi
  fi

  jq -n \
    --arg stage "$stage" \
    --arg head "$head" \
    --arg result "$result" \
    --arg reason "$reason" \
    --arg marker "$COMMENT_MARKER" \
    --argjson aligned "$aligned" \
    --argjson unexpected "$unexpected_json" \
    '{stage: $stage, head: $head, result: $result, aligned: $aligned, reason: $reason, unexpected_files: $unexpected, warning_marker: $marker}'
}

warning_body() {
  local result_json="$1"

  printf '%s\n' "$result_json" | jq -r --arg marker "$COMMENT_MARKER" '
    $marker + "\n" +
    "### Documentation-stage alignment mismatch\n\n" +
    "This PR is on " + .head + ", so Protocol 91 Step 8a blocks ready-for-human-review until the diff contains only expected " + .stage + "-stage artifacts or the mismatch is escalated.\n\n" +
    "**Reason:** " + .reason + "\n\n" +
    (if (.unexpected_files | length) > 0 then
      "**Unexpected files:**\n" + (.unexpected_files | map("- " + .) | join("\n")) + "\n"
    else
      "**Unexpected files:** none; no stage artifact was found in the PR diff.\n"
    end) +
    "\n_Posted automatically by check-documentation-stage-alignment.sh._"
  '
}

post_or_update_warning() {
  local number="$1"
  local result_json="$2"
  local repo comments existing_id body

  body="$(warning_body "$result_json")"
  if ! repo="$(repo_slug)"; then
    echo "ERROR: failed to determine GitHub repository" >&2
    return "$INFRASTRUCTURE_EXIT"
  fi
  if ! comments="$(gh api "repos/${repo}/issues/${number}/comments" --paginate --slurp 2>/dev/null)"; then
    echo "ERROR: failed to read PR comments for #$number" >&2
    return "$INFRASTRUCTURE_EXIT"
  fi
  if ! existing_id="$(printf '%s\n' "$comments" |
    jq -r --arg marker "$COMMENT_MARKER" '[.[][] | select((.body // "") | contains($marker))][-1].id // ""')"; then
    echo "ERROR: failed to parse PR comments for #$number" >&2
    return "$INFRASTRUCTURE_EXIT"
  fi

  if [ -n "$existing_id" ]; then
    if ! gh api -X PATCH "repos/${repo}/issues/comments/${existing_id}" -f body="$body" >/dev/null; then
      echo "ERROR: failed to update documentation-stage warning comment for PR #$number" >&2
      return "$INFRASTRUCTURE_EXIT"
    fi
  else
    if ! gh pr comment "$number" --repo "$repo" --body "$body" >/dev/null; then
      echo "ERROR: failed to post documentation-stage warning comment for PR #$number" >&2
      return "$INFRASTRUCTURE_EXIT"
    fi
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      require_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --input)
      require_value "$@"
      input_file="$2"
      shift 2
      ;;
    --json)
      json_output=1
      shift
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

if [ -n "$pr_number" ] && [ -n "$input_file" ]; then
  echo "Pass --pr or --input, not both." >&2
  exit 64
fi
if [ -z "$pr_number" ] && [ -z "$input_file" ]; then
  echo "Pass exactly one of --pr or --input." >&2
  exit 64
fi
if [ -n "$pr_number" ] && ! is_positive_int "$pr_number"; then
  echo "--pr must be a positive integer." >&2
  exit 64
fi

state_json=""
if [ -n "$input_file" ]; then
  set +e
  state_json="$(normalize_fixture "$input_file")"
  state_status=$?
  set -e
else
  set +e
  state_json="$(live_pr_state "$pr_number")"
  state_status=$?
  set -e
fi
if [ "$state_status" -ne 0 ]; then
  exit "$state_status"
fi

set +e
result_json="$(classify_state "$state_json")"
result_status=$?
set -e
if [ "$result_status" -ne 0 ]; then
  exit "$result_status"
fi

if [ "$(printf '%s\n' "$result_json" | jq -r '.result')" = "mismatch" ] && [ -n "$pr_number" ]; then
  if ! post_or_update_warning "$pr_number" "$result_json"; then
    echo "WARNING: documentation-stage mismatch detected, but the warning comment could not be posted or updated. Readiness remains blocked with exit $MISMATCH_EXIT." >&2
  fi
fi

if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$result_json"
else
  printf 'DOCUMENTATION_STAGE_ALIGNMENT=%s\n' "$(printf '%s\n' "$result_json" | jq -r '.result')"
  printf 'STAGE=%s\n' "$(printf '%s\n' "$result_json" | jq -r '.stage')"
  printf 'REASON=%s\n' "$(printf '%s\n' "$result_json" | jq -r '.reason // ""')"
  printf '%s\n' "$result_json" | jq -r '.unexpected_files[]? | "UNEXPECTED_FILE=" + .'
fi

if [ "$(printf '%s\n' "$result_json" | jq -r '.result')" = "mismatch" ]; then
  exit "$MISMATCH_EXIT"
fi
