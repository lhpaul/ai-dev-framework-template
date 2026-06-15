#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-risk-classifier.sh --pr <number> [--max-risk <low|medium|high>] [--json]
  ./scripts/development-workflow/run-epic-risk-classifier.sh --input <file> [--max-risk <low|medium|high>] [--json]

Classifies delegated /run-epic PR merge risk. The classifier is read-only: it
does not run reviewers, poll CI, edit labels, update trackers, merge PRs, close
issues, post comments, or delete branches.
EOF
}

pr_number=""
input_file=""
max_risk="low"
json_output=0

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

valid_max_risk() {
  case "$1" in
    low|medium|high) return 0 ;;
    *) return 1 ;;
  esac
}

risk_rank() {
  case "$1" in
    low) echo 1 ;;
    medium) echo 2 ;;
    high) echo 3 ;;
    blocked) echo 99 ;;
    *) echo 99 ;;
  esac
}

json_has_string_array_value() {
  local json="$1"
  local path="$2"
  local value="$3"

  printf '%s\n' "$json" |
    jq -e --arg value "$value" "${path} // [] | index(\$value) != null" >/dev/null
}

json_bool_true() {
  local json="$1"
  local path="$2"

  printf '%s\n' "$json" | jq -e "${path} == true" >/dev/null
}

append_json_array_string() {
  local json="$1"
  local value="$2"

  printf '%s\n' "$json" | jq --arg value "$value" '. + [$value]'
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

  printf '%s\n' "$raw"
}

live_pr_state() {
  local number="$1"
  local pr_json files_json

  require_gh

  if ! pr_json="$(gh pr view "$number" \
    --json number,title,baseRefName,headRefName,mergeStateStatus,labels,statusCheckRollup,reviewDecision,isDraft 2>/dev/null)"; then
    error_exit "failed to read PR #$number"
  fi
  if [ -z "$pr_json" ]; then
    error_exit "empty PR response for #$number"
  fi
  if ! files_json="$(gh pr diff "$number" --name-only 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')"; then
    error_exit "failed to read changed files for PR #$number"
  fi

  printf '%s\n' "$pr_json" | jq --argjson files "$files_json" '{
    pr_number: .number,
    title: .title,
    base: .baseRefName,
    head: .headRefName,
    merge_state: .mergeStateStatus,
    is_draft: .isDraft,
    labels: [.labels[]?.name],
    review_decision: (.reviewDecision // ""),
    status_checks: [
      .statusCheckRollup[]? |
      if .__typename == "CheckRun" then
        {
          name: .name,
          status: (.status // ""),
          conclusion: (.conclusion // ""),
          completed_at: (.completedAt // .startedAt // "")
        }
      else
        {
          name: .context,
          status: (if (.state // "") == "SUCCESS" then "COMPLETED" else (.state // "") end),
          conclusion: (.state // ""),
          completed_at: (.startedAt // "")
        }
      end
    ],
    changed_files: $files
  }'
}

check_status_is_success() {
  local status="$1"
  local conclusion="$2"

  case "${status}:${conclusion}" in
    COMPLETED:SUCCESS|completed:success) return 0 ;;
    *) return 1 ;;
  esac
}

collect_check_blockers() {
  local state_json="$1"
  local blockers='[]'
  local checks_json check_count
  local encoded decoded status conclusion name

  if ! checks_json="$(printf '%s\n' "$state_json" | jq -c '
    [.status_checks[]?, .required_checks[]?, .checks[]?]
    | to_entries
    | map(.value + {
        __run_epic_idx: .key,
        __run_epic_name: (.value.name // .value.context // "unnamed check"),
        __run_epic_timestamp: (.value.completed_at // .value.completedAt // .value.startedAt // "")
      })
    | sort_by(.__run_epic_name, .__run_epic_idx)
    | group_by(.__run_epic_name)
    | map(
        if length == 1 then .[0]
        elif all(.__run_epic_timestamp != "") then max_by(.__run_epic_timestamp)
        else max_by(.__run_epic_idx)
        end
        | del(.__run_epic_idx, .__run_epic_name, .__run_epic_timestamp)
      )
  ')"; then
    error_exit "failed to normalize required CI checks"
  fi

  check_count="$(printf '%s\n' "$checks_json" | jq 'length')"
  if [ "$check_count" -eq 0 ]; then
    append_json_array_string "$blockers" "required CI state is missing or unavailable"
    return
  fi

  while IFS= read -r encoded; do
    [ -n "$encoded" ] || continue
    if ! decoded="$(printf '%s' "$encoded" | base64_decode)"; then
      error_exit "failed to decode required CI check state"
    fi
    if ! status="$(printf '%s\n' "$decoded" | jq -r '.status // .state // ""')"; then
      error_exit "failed to parse required CI check status"
    fi
    if ! conclusion="$(printf '%s\n' "$decoded" | jq -r '.conclusion // .state // ""')"; then
      error_exit "failed to parse required CI check conclusion"
    fi
    if ! name="$(printf '%s\n' "$decoded" | jq -r '.name // .context // "unnamed check"')"; then
      error_exit "failed to parse required CI check name"
    fi
    if [ -z "$status" ] && [ -z "$conclusion" ]; then
      blockers="$(append_json_array_string "$blockers" "required CI state is missing or ambiguous: ${name}")"
      continue
    fi
    if ! check_status_is_success "$status" "$conclusion"; then
      blockers="$(append_json_array_string "$blockers" "required CI is not successful: ${name}")"
    fi
  done < <(printf '%s\n' "$checks_json" | jq -r '.[] | @base64')

  printf '%s\n' "$blockers"
}

base64_decode() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

changed_file_risk() {
  local state_json="$1"
  local risk="low"
  local reasons='[]'
  local file reason_count

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in
      .github/workflows/*|*release*|*branch-deletion*|*delete-branch*|\
      auth/*|*/auth/*|*/auth|\
      authentication/*|*/authentication/*|*/authentication|\
      secret/*|*/secret/*|*/secret|\
      secrets/*|*/secrets/*|*/secrets|\
      credential/*|*/credential/*|*/credential|\
      credentials/*|*/credentials/*|*/credentials|\
      permission/*|*/permission/*|*/permission|\
      permissions/*|*/permissions/*|*/permissions)
        risk="high"
        reasons="$(append_json_array_string "$reasons" "sensitive or broad file category: ${file}")"
        ;;
      scripts/development-workflow/tests/*|test/*|tests/*)
        if [ "$risk" = "low" ]; then
          reasons="$(append_json_array_string "$reasons" "low-risk docs or tests change: ${file}")"
        fi
        ;;
      scripts/development-workflow/*.sh)
        if [ "$risk" != "high" ]; then
          risk="medium"
        fi
        reasons="$(append_json_array_string "$reasons" "workflow script or harness change: ${file}")"
        ;;
      docs/workflow/development-workflow/protocols/*|.agents/skills/run-epic/*|.claude/commands/run-epic.md|.cursor/commands/run-epic.md)
        if [ "$risk" = "low" ]; then
          reasons="$(append_json_array_string "$reasons" "workflow guidance change: ${file}")"
        fi
        ;;
      docs/*|*.md)
        if [ "$risk" = "low" ]; then
          reasons="$(append_json_array_string "$reasons" "low-risk docs or tests change: ${file}")"
        fi
        ;;
      *)
        if [ "$risk" != "high" ]; then
          risk="medium"
        fi
        reasons="$(append_json_array_string "$reasons" "uncategorized implementation file: ${file}")"
        ;;
    esac
  done < <(printf '%s\n' "$state_json" | jq -r '.changed_files[]?')

  if ! reason_count="$(printf '%s\n' "$reasons" | jq -e 'length')"; then
    reason_count=0
  fi
  if [ "$reason_count" -eq 0 ]; then
    reasons="$(append_json_array_string "$reasons" "changed-file evidence is missing")"
    risk="high"
  fi

  jq -n --arg risk "$risk" --argjson reasons "$reasons" \
    '{risk: $risk, reasons: $reasons}'
}

why_safe_complete() {
  local state_json="$1"

  printf '%s\n' "$state_json" | jq -e '
    .why_safe_to_merge as $why |
    ($why | type) == "object" and
    (($why.scope // "" | gsub("\\s"; "") | length) > 0) and
    (($why.tests // "" | gsub("\\s"; "") | length) > 0) and
    (($why.reviewer_outcome // "" | gsub("\\s"; "") | length) > 0) and
    (($why.ci_outcome // "" | gsub("\\s"; "") | length) > 0) and
    (($why.rollback_or_cleanup_risk // "" | gsub("\\s"; "") | length) > 0)
  ' >/dev/null
}

classify_state() {
  local state_json="$1"
  local blockers='[]'
  local reasons='[]'
  local file_result file_risk file_reasons
  local assigned_risk merge_permitted max_rank risk_rank_value

  if json_has_string_array_value "$state_json" '.labels' "needs-setup"; then
    blockers="$(append_json_array_string "$blockers" "needs-setup label is present")"
  fi
  if json_bool_true "$state_json" '.force_push_required'; then
    blockers="$(append_json_array_string "$blockers" "force-push is required")"
  fi
  if json_bool_true "$state_json" '.destructive_action_required'; then
    blockers="$(append_json_array_string "$blockers" "destructive action is required")"
  fi
  if json_bool_true "$state_json" '.missing_credentials'; then
    blockers="$(append_json_array_string "$blockers" "required credentials are missing")"
  fi
  if json_bool_true "$state_json" '.ambiguous_tracker_state'; then
    blockers="$(append_json_array_string "$blockers" "tracker state is ambiguous")"
  fi
  if json_bool_true "$state_json" '.unclear_base_branch'; then
    blockers="$(append_json_array_string "$blockers" "target or base branch is unclear")"
  fi
  if json_bool_true "$state_json" '.is_draft'; then
    blockers="$(append_json_array_string "$blockers" "PR is still draft")"
  fi

  case "$(printf '%s\n' "$state_json" | jq -r '.merge_state // .mergeStateStatus // ""')" in
    CLEAN|clean)
      ;;
    "")
      blockers="$(append_json_array_string "$blockers" "merge state is missing")"
      ;;
    *)
      blockers="$(append_json_array_string "$blockers" "merge state is not clean")"
      ;;
  esac

  case "$(printf '%s\n' "$state_json" | jq -r '.reviewer.status // .reviewer_status // ""')" in
    failed|failure|blocking)
      blockers="$(append_json_array_string "$blockers" "configured reviewer reported failure")"
      ;;
    unavailable)
      blockers="$(append_json_array_string "$blockers" "configured reviewer state is unavailable")"
      ;;
  esac

  if [ "$(printf '%s\n' "$state_json" | jq -r '(.reviewer.blocking_count // .blocking_count // 0)')" -gt 0 ]; then
    blockers="$(append_json_array_string "$blockers" "configured reviewer has blocking findings")"
  fi
  if [ "$(printf '%s\n' "$state_json" | jq -r '(.reviewer.unresolved_blocking_threads // .unresolved_blocking_threads // 0)')" -gt 0 ]; then
    blockers="$(append_json_array_string "$blockers" "unresolved blocking review threads remain")"
  fi

  if ! check_blockers="$(collect_check_blockers "$state_json")"; then
    error_exit "collect_check_blockers failed"
  fi
  if ! printf '%s\n' "$check_blockers" | jq -e 'type == "array"' >/dev/null; then
    error_exit "collect_check_blockers returned invalid JSON"
  fi
  blockers="$(jq -n --argjson a "$blockers" --argjson b "$check_blockers" '$a + $b')"

  if [ "$(printf '%s\n' "$blockers" | jq 'length')" -gt 0 ]; then
    assigned_risk="blocked"
    reasons="$blockers"
  else
    if ! file_result="$(changed_file_risk "$state_json")"; then
      error_exit "changed_file_risk failed"
    fi
    if ! printf '%s\n' "$file_result" | jq -e 'type == "object" and (.reasons | type == "array")' >/dev/null; then
      error_exit "changed_file_risk returned invalid JSON"
    fi
    file_risk="$(printf '%s\n' "$file_result" | jq -r '.risk')"
    file_reasons="$(printf '%s\n' "$file_result" | jq -c '.reasons')"
    assigned_risk="$file_risk"
    reasons="$file_reasons"

    if [ "$assigned_risk" = "medium" ] && ! why_safe_complete "$state_json"; then
      assigned_risk="blocked"
      blockers="$(append_json_array_string "$blockers" "medium-risk PR is missing complete why_safe_to_merge evidence")"
      reasons="$(jq -n --argjson a "$reasons" --argjson b "$blockers" '$a + $b')"
    fi
  fi

  max_rank="$(risk_rank "$max_risk")"
  risk_rank_value="$(risk_rank "$assigned_risk")"
  merge_permitted="false"
  if [ "$assigned_risk" != "blocked" ] && [ "$risk_rank_value" -le "$max_rank" ]; then
    merge_permitted="true"
  fi

  local gate_reason=""
  if [ "$assigned_risk" = "blocked" ]; then
    gate_reason="blocked risk is never mergeable"
  elif [ "$risk_rank_value" -gt "$max_rank" ]; then
    gate_reason="assigned risk ${assigned_risk} exceeds max risk ${max_risk}"
  else
    gate_reason="assigned risk ${assigned_risk} is within max risk ${max_risk}"
  fi

  printf '%s\n' "$state_json" | jq \
    --arg risk "$assigned_risk" \
    --arg maxRisk "$max_risk" \
    --argjson mergePermitted "$merge_permitted" \
    --arg gateReason "$gate_reason" \
    --argjson reasons "$reasons" \
    --argjson blockers "$blockers" \
    '{
      pr_number: (.pr_number // .number // null),
      title: (.title // null),
      risk: $risk,
      max_risk: $maxRisk,
      merge_permitted: $mergePermitted,
      gate_reason: $gateReason,
      reasons: $reasons,
      blockers: $blockers,
      why_safe_to_merge: (.why_safe_to_merge // null),
      read_only_guarantee: "No tracker status updates, labels, comments, reviewer-loop runs, CI polling, merges, issue closure, or branch deletion were performed."
    }'
}

print_text_result() {
  local result_json="$1"

  printf 'PR Risk Classification\n'
  printf 'Risk: %s\n' "$(printf '%s\n' "$result_json" | jq -r '.risk')"
  printf 'Max risk: %s\n' "$(printf '%s\n' "$result_json" | jq -r '.max_risk')"
  printf 'Merge permitted: %s\n' "$(printf '%s\n' "$result_json" | jq -r '.merge_permitted')"
  printf 'Gate reason: %s\n' "$(printf '%s\n' "$result_json" | jq -r '.gate_reason')"
  printf 'Reasons:\n'
  printf '%s\n' "$result_json" | jq -r '.reasons[]? | "- " + .'
  if [ "$(printf '%s\n' "$result_json" | jq '.blockers | length')" -gt 0 ]; then
    printf 'Blockers:\n'
    printf '%s\n' "$result_json" | jq -r '.blockers[]? | "- " + .'
  fi
  if printf '%s\n' "$result_json" | jq -e '.why_safe_to_merge != null' >/dev/null; then
    printf 'Why safe to merge:\n'
    printf '%s\n' "$result_json" | jq -r '
      .why_safe_to_merge |
      "- Scope: " + (.scope // "") + "\n" +
      "- Tests: " + (.tests // "") + "\n" +
      "- Reviewer outcome: " + (.reviewer_outcome // "") + "\n" +
      "- CI outcome: " + (.ci_outcome // "") + "\n" +
      "- Rollback or cleanup risk: " + (.rollback_or_cleanup_risk // "")
    '
  fi
  printf 'Read-only guarantee: %s\n' "$(printf '%s\n' "$result_json" | jq -r '.read_only_guarantee')"
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
    --max-risk)
      require_value "$@"
      max_risk="$2"
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
  echo "ERROR: pass exactly one of --pr or --input, not both." >&2
  exit 64
fi
if [ -z "$pr_number" ] && [ -z "$input_file" ]; then
  echo "ERROR: pass exactly one of --pr or --input." >&2
  exit 64
fi
if [ -n "$pr_number" ] && ! is_positive_int "$pr_number"; then
  echo "ERROR: --pr must be a positive integer." >&2
  exit 64
fi
if ! valid_max_risk "$max_risk"; then
  echo "ERROR: --max-risk must be one of low, medium, or high." >&2
  exit 64
fi

state_json=""
if [ -n "$input_file" ]; then
  state_json="$(normalize_fixture "$input_file")"
else
  state_json="$(live_pr_state "$pr_number")"
fi

result_json="$(classify_state "$state_json")"
if [ "$json_output" -eq 1 ]; then
  printf '%s\n' "$result_json" | jq '.'
else
  print_text_result "$result_json"
fi
