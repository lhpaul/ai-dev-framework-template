#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

_HARNESS_MODE_EFFECTIVE=0
if [ "${HARNESS_MODE:-0}" -eq 1 ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _HARNESS_MODE_EFFECTIVE=1
fi

RER_DEFAULT_WINDOW=20

rer_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

rer_usage() {
  cat <<USAGE
Usage:
  reviewer-effectiveness-report.sh --pr <number> [--repo <owner/repo>] [--json]
  reviewer-effectiveness-report.sh [--window <n>] [--repo <owner/repo>] [--json]

Read-only report of reviewer-loop effectiveness from persisted history comments.

Options:
  --pr <number>       Report for one pull request.
  --window <n>        Report over the most recent n pull requests (default: ${RER_DEFAULT_WINDOW}).
  --repo <owner/repo> Repository (defaults to gh's current repository).
  --json              Machine-readable JSON output.
  -h, --help          Show this help.

The default window size is ${RER_DEFAULT_WINDOW}. No configuration file or
environment variable changes it; pass --window to use a different size.
USAGE
}

rer_measure_available() {
  local payload="$1"
  local field="$2"
  printf '%s\n' "$payload" | jq -e --arg f "$field" '
    [ .entries[]? | select(has($f)) ] | length > 0
  ' >/dev/null 2>&1
}

rer_measure7_available() {
  local payload="$1"
  printf '%s\n' "$payload" | jq -e '
    (.entries | last) as $e | ($e != null) and ($e | has("reviewed_heads"))
  ' >/dev/null 2>&1
}

rer_classify_payload() {
  local body="$1"
  local json=""

  if ! printf '%s\n' "$body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
    printf 'no_history\n'
    return 0
  fi
  if ! json="$(printf '%s\n' "$body" | reviewer_loop_history_extract_latest_json)" \
      || [ -z "$json" ]; then
    printf 'unparseable_history\n'
    return 0
  fi
  if ! printf '%s\n' "$json" | jq -e . >/dev/null 2>&1; then
    printf 'unparseable_history\n'
    return 0
  fi
  if ! printf '%s\n' "$json" | jq -e --arg s "$REVIEWER_LOOP_HISTORY_SCHEMA" '
        .schema == $s and (.entries | type) == "array"
        and ((.history_status // "available") == "available")' >/dev/null 2>&1; then
    printf 'history_unavailable\n'
    return 0
  fi
  printf 'included\n'
}

rer_fetch_summary_body() {
  local repo_slug="$1"
  local pr_number="$2"
  local comments_json record body

  if ! comments_json="$(gh api "repos/${repo_slug}/issues/${pr_number}/comments" --paginate 2>/dev/null)"; then
    return 1
  fi
  record="$(printf '%s\n' "$comments_json" | reviewer_loop_history_select_latest_summary_record 2>/dev/null)" || record=""
  body="$(printf '%s\n' "$record" | jq -r '.body // ""' 2>/dev/null)" || body=""
  printf '%s' "$body"
}

rer_compute_measures_json() {
  local payload="$1"
  local m1 m2 m3 m4 m5 m6 m7

  m1="$(printf '%s\n' "$payload" | jq -c '{availability:"computed", value:(.entries | length)}')"

  if rer_measure_available "$payload" "missed_findings"; then
    m2="$(printf '%s\n' "$payload" | jq -c '
      {availability:"computed", value:([.entries[]? | select((.missed_findings | length) > 0)] | length)}
    ')"
    m4="$(printf '%s\n' "$payload" | jq -c '
      {availability:"computed", value:([.entries[]?.missed_findings[]?
        | select(.local_evidence_state == "clean_same_commit")] | length)}
    ')"
    m5="$(printf '%s\n' "$payload" | jq -c '
      {availability:"computed", value:([.entries[]?.missed_findings[]?
        | select(.local_evidence_state == "clean_earlier_commit")] | length)}
    ')"
  else
    m2='{"availability":"not_recorded"}'
    m4='{"availability":"not_recorded"}'
    m5='{"availability":"not_recorded"}'
  fi

  if rer_measure_available "$payload" "blocking_count"; then
    m3="$(printf '%s\n' "$payload" | jq -c '
      {availability:"computed", value:([.entries[]? | select(has("blocking_count")) | .blocking_count] | add // 0)}
    ')"
  else
    m3='{"availability":"not_recorded"}'
  fi

  if rer_measure_available "$payload" "platforms"; then
    m6="$(printf '%s\n' "$payload" | jq -c '
      {availability:"computed", value:([.entries[]? | select(has("platforms")) | select(.platforms | index("codex-github"))] | length)}
    ')"
  else
    m6='{"availability":"not_recorded"}'
  fi

  if rer_measure7_available "$payload"; then
    m7="$(printf '%s\n' "$payload" | jq -c '
      (.entries | last) as $e
      | ($e.reviewed_heads // []) as $heads
      | if ($heads | length) == 0 then
          {availability:"computed", value:"not-reported"}
        elif ([$heads[] | .state] | all(. == "current")) then
          {availability:"computed", value:"current"}
        elif ([$heads[] | .state] | any(. == "not-current")) then
          {availability:"computed", value:"not-current"}
        elif ([$heads[] | .state] | all(. == "not-reported")) then
          {availability:"computed", value:"not-reported"}
        else
          {availability:"computed", value:"not-current"}
        end
    ')"
  else
    m7='{"availability":"not_recorded"}'
  fi

  jq -nc \
    --argjson rounds "$m1" \
    --argjson external_blocking_rounds "$m2" \
    --argjson blocking_findings "$m3" \
    --argjson confirmed_miss_records "$m4" \
    --argjson possible_miss_records "$m5" \
    --argjson codex_github_invocations "$m6" \
    --argjson final_current_head_evidence "$m7" \
    '{
      rounds: $rounds,
      external_blocking_rounds: $external_blocking_rounds,
      blocking_findings: $blocking_findings,
      confirmed_miss_records: $confirmed_miss_records,
      possible_miss_records: $possible_miss_records,
      codex_github_invocations: $codex_github_invocations,
      final_current_head_evidence: $final_current_head_evidence
    }'
}

rer_process_pr() {
  local repo_slug="$1"
  local pr_number="$2"
  local body state json measures

  if ! body="$(rer_fetch_summary_body "$repo_slug" "$pr_number")"; then
    return 1
  fi

  state="$(rer_classify_payload "$body")"
  case "$state" in
    included)
      json="$(printf '%s\n' "$body" | reviewer_loop_history_extract_latest_json)"
      measures="$(rer_compute_measures_json "$json")"
      jq -nc --argjson pr "$pr_number" --arg state "$state" --argjson measures "$measures" \
        '{pr:$pr, state:$state, measures:$measures}'
      ;;
    *)
      jq -nc --argjson pr "$pr_number" --arg state "$state" --arg reason "$state" \
        '{pr:$pr, state:$state, exclusion_reason:$reason}'
      ;;
  esac
}

rer_validate_window() {
  local window="$1"
  case "$window" in
    ''|*[!0-9]*)
      printf 'invalid\n'
      ;;
    0)
      printf 'zero\n'
      ;;
    *)
      printf 'ok\n'
      ;;
  esac
}

rer_list_recent_prs() {
  local repo_slug="$1"
  local limit="$2"
  gh pr list --repo "$repo_slug" --state all --limit "$limit" \
    --json number | jq -r 'sort_by(.number) | reverse | .[].number' 2>/dev/null
}

rer_aggregate_measure() {
  local rows_json="$1"
  local field="$2"
  printf '%s\n' "$rows_json" | jq -c --arg f "$field" '
    [.[] | select(.state == "included") | .measures[$f]
      | select(.availability == "computed")] as $vals
    | if ($vals | length) == 0 then empty else {
        measure: $f,
        included: ($vals | length),
        total: ([$vals[] | .value | if type == "number" then . else 0 end] | add // 0)
      } end
  '
}

rer_aggregate_state_measure() {
  local rows_json="$1"
  local field="$2"
  printf '%s\n' "$rows_json" | jq -c --arg f "$field" '
    [.[] | select(.state == "included") | .measures[$f]
      | select(.availability == "computed")] as $vals
    | if ($vals | length) == 0 then empty else {
        measure: $f,
        included: ($vals | length),
        values: [$vals[] | .value]
      } end
  '
}

rer_strict_checks_json() {
  local rows_json="$1"
  printf '%s\n' "$rows_json" | jq -c '
    def pr_entries:
      [.[] | select(.state == "included") | . as $row
        | ($row._payload.entries // [])[] | . + {_pr: $row.pr}];

    def spec_applied_prs:
      [.[] | select(.state == "included") | select(
        any(._payload.entries[]?; (.strict_spec.state // "") == "applied")
      ) | .pr] | unique;

    def plan_applied_prs($check):
      [.[] | select(.state == "included") | select(
        any(._payload.entries[]?;
          (.strict_plan.state // "") == "applied"
          and ((.strict_plan.applied // []) | index($check)))
      ) | .pr] | unique;

    def spec_fired_prs($check):
      [.[] | select(.state == "included") | select(
        any(._payload.entries[]?;
          (.strict_spec.state // "") == "applied"
          and ((.strict_spec.checks // []) | index($check)))
      ) | .pr] | unique;

    def plan_fired_prs($check):
      [.[] | select(.state == "included") | select(
        any(._payload.entries[]?;
          (.strict_plan.state // "") == "applied"
          and ((.strict_plan.checks // []) | index($check)))
      ) | .pr] | unique;

    [pr_entries[] | .strict_spec.checks[]? // empty] as $spec_checks
    | [pr_entries[] | .strict_plan.applied[]? // empty] as $plan_applied_checks
    | [pr_entries[] | .strict_plan.checks[]? // empty] as $plan_fired_checks
    | ($spec_checks + $plan_applied_checks + $plan_fired_checks | unique) as $all_checks
    | if ($all_checks | length) == 0 then
        null
      else
        {
          checks: (
            [($spec_checks | unique[]) as $c
              | {
                  check: $c,
                  kind: "spec",
                  fired: (spec_fired_prs($c) | length),
                  applied: (spec_applied_prs | length)
                }]
            + [($plan_applied_checks | unique[]) as $c
              | {
                  check: $c,
                  kind: "plan",
                  fired: (plan_fired_prs($c) | length),
                  applied: (plan_applied_prs($c) | length)
                }]
          )
        }
      end
  '
}

rer_render_text() {
  local report_json="$1"
  local window_used requested included excluded

  window_used="$(printf '%s\n' "$report_json" | jq -r '.window_used // empty')"
  requested="$(printf '%s\n' "$report_json" | jq -r '.accounting.requested')"
  included="$(printf '%s\n' "$report_json" | jq -r '.accounting.included')"
  excluded="$(printf '%s\n' "$report_json" | jq -r '.accounting.excluded')"

  printf 'Reviewer effectiveness report\n'
  if [ -n "$window_used" ]; then
    printf 'Window: %s pull requests (requested: %s)\n\n' "$window_used" "$requested"
  fi

  printf '%s\n' "$report_json" | jq -r '
    .rows[] | select(.state == "included") |
    "PR #\(.pr)",
    "  Rounds: \(.measures.rounds.value)",
    (if .measures.external_blocking_rounds.availability == "computed"
      then "  External blocking rounds: \(.measures.external_blocking_rounds.value)"
      else "  External blocking rounds: Not recorded" end),
    (if .measures.blocking_findings.availability == "computed"
      then "  Blocking findings: \(.measures.blocking_findings.value)"
      else "  Blocking findings: Not recorded" end),
    (if .measures.confirmed_miss_records.availability == "computed"
      then "  Confirmed miss records: \(.measures.confirmed_miss_records.value)"
      else "  Confirmed miss records: Not recorded" end),
    (if .measures.possible_miss_records.availability == "computed"
      then "  Possible miss records: \(.measures.possible_miss_records.value)"
      else "  Possible miss records: Not recorded" end),
    (if .measures.codex_github_invocations.availability == "computed"
      then "  codex-github invocations: \(.measures.codex_github_invocations.value)"
      else "  codex-github invocations: Not recorded" end),
    (if .measures.final_current_head_evidence.availability == "computed"
      then "  Final current-head evidence: \(.measures.final_current_head_evidence.value)"
      else "  Final current-head evidence: Not recorded" end),
    ""
  '

  if [ "$included" -gt 0 ] 2>/dev/null; then
    printf 'Aggregates\n'
    for measure in rounds external_blocking_rounds blocking_findings confirmed_miss_records possible_miss_records codex_github_invocations; do
      agg="$(printf '%s\n' "$report_json" | jq -r --arg m "$measure" '
        .aggregates[]? | select(.measure == $m) |
        if .included > 0 then
          "\(.measure): \(.total) (included: \(.included))"
        else empty end
      ')"
      [ -n "$agg" ] && printf '  %s\n' "$agg"
    done
    fche_agg="$(printf '%s\n' "$report_json" | jq -r '
      .aggregates[]? | select(.measure == "final_current_head_evidence") |
      if .included > 0 then
        "final_current_head_evidence: \(.values | join(", ")) (included: \(.included))"
      else empty end
    ')"
    [ -n "$fche_agg" ] && printf '  %s\n' "$fche_agg"
    printf '\n'
  fi

  strict="$(printf '%s\n' "$report_json" | jq -r '
    .strict_checks.checks[]? | "  \(.check) (\(.kind)): \(.fired) / \(.applied)"
  ')"
  if [ -n "$strict" ]; then
    printf 'Strict-check incidence\n%s\n\n' "$strict"
  fi

  printf 'Exclusion accounting\n'
  printf '  Requested: %s\n  Included: %s\n  Excluded: %s\n' "$requested" "$included" "$excluded"
  printf '%s\n' "$report_json" | jq -r '
    .exclusions[]? | "  PR #\(.pr): \(.reason)"
  '
}

rer_build_report() {
  local repo_slug="$1"
  shift
  local -a pr_numbers=("$@")
  local -a rows=()
  local pr body state json row measures
  local rows_json requested included excluded
  local -a aggregates=()
  local strict_checks report agg_json

  requested="${#pr_numbers[@]}"
  for pr in "${pr_numbers[@]}"; do
    if ! body="$(rer_fetch_summary_body "$repo_slug" "$pr")"; then
      rer_fail "failed to fetch reviewer-loop history for PR #${pr}"
    fi
    state="$(rer_classify_payload "$body")"
    case "$state" in
      included)
        json="$(printf '%s\n' "$body" | reviewer_loop_history_extract_latest_json)"
        measures="$(rer_compute_measures_json "$json")"
        row="$(jq -nc --argjson pr "$pr" --arg state "$state" --argjson measures "$measures" --argjson payload "$json" \
          '{pr:$pr, state:$state, measures:$measures, _payload:$payload}')"
        ;;
      *)
        row="$(jq -nc --argjson pr "$pr" --arg state "$state" --arg reason "$state" \
          '{pr:$pr, state:$state, exclusion_reason:$reason}')"
        ;;
    esac
    rows+=("$row")
  done

  rows_json="$(printf '%s\n' "${rows[@]}" | jq -s '.')"
  included="$(printf '%s\n' "$rows_json" | jq '[.[] | select(.state == "included")] | length')"
  excluded="$(printf '%s\n' "$rows_json" | jq '[.[] | select(.state != "included")] | length')"

  if [ "$included" -gt 0 ]; then
    for measure in rounds external_blocking_rounds blocking_findings confirmed_miss_records possible_miss_records codex_github_invocations; do
      agg="$(rer_aggregate_measure "$rows_json" "$measure")"
      [ -n "$agg" ] && aggregates+=("$agg")
    done
    agg="$(rer_aggregate_state_measure "$rows_json" "final_current_head_evidence")"
    [ -n "$agg" ] && aggregates+=("$agg")
  fi

  strict_checks="$(rer_strict_checks_json "$rows_json")"

  if [ "${#aggregates[@]}" -gt 0 ]; then
    agg_json="$(printf '%s\n' "${aggregates[@]}" | jq -s '.')"
  else
    agg_json='[]'
  fi

  report="$(jq -nc \
    --arg repo "$repo_slug" \
    --argjson rows "$rows_json" \
    --argjson requested "$requested" \
    --argjson included "$included" \
    --argjson excluded "$excluded" \
    --argjson aggregates "$agg_json" \
    --argjson strict_checks "${strict_checks:-null}" \
    '{
      repo: $repo,
      accounting: {requested:$requested, included:$included, excluded:$excluded},
      rows: $rows,
      exclusions: [$rows[] | select(.state != "included") | {pr, reason: .exclusion_reason}],
      aggregates: $aggregates
    }
    | if $strict_checks != null then . + {strict_checks: $strict_checks} else . end
    ')"
  printf '%s\n' "$report"
}

rer_main() {
  local pr_number="" window="" repo_slug="" json_output=0
  local window_arg_present=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pr)
        [ "$#" -ge 2 ] || rer_fail "--pr requires a value"
        pr_number="$2"
        shift 2
        ;;
      --window)
        [ "$#" -ge 2 ] || rer_fail "--window requires a value"
        window="$2"
        window_arg_present=1
        shift 2
        ;;
      --repo)
        [ "$#" -ge 2 ] || rer_fail "--repo requires a value"
        repo_slug="$2"
        shift 2
        ;;
      --json) json_output=1; shift ;;
      -h|--help) rer_usage; exit 0 ;;
      *) rer_fail "unknown argument: $1" ;;
    esac
  done

  command -v gh >/dev/null 2>&1 || rer_fail "gh CLI is required"
  command -v jq >/dev/null 2>&1 || rer_fail "jq is required"

  if [ -z "$repo_slug" ]; then
    repo_slug="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" || repo_slug=""
    [ -n "$repo_slug" ] || rer_fail "could not resolve repository; pass --repo owner/repo"
  fi

  if [ -n "$pr_number" ] && { [ "$window_arg_present" -eq 1 ] || [ -n "$window" ]; }; then
    rer_fail "use either --pr or --window, not both"
  fi

  local -a prs=()
  local report window_used="" final_report

  if [ -n "$pr_number" ]; then
    case "$pr_number" in
      ''|*[!0-9]*) rer_fail "--pr must be a positive integer" ;;
    esac
    prs=("$pr_number")
    report="$(rer_build_report "$repo_slug" "${prs[@]}")"
    final_report="$report"
  else
    if [ "$window_arg_present" -eq 0 ]; then
      window="$RER_DEFAULT_WINDOW"
    fi
    case "$(rer_validate_window "$window")" in
      invalid) rer_fail "window size must be a positive whole number; got: ${window}" ;;
      zero) rer_fail "window size must be a positive whole number; got: ${window}" ;;
    esac
    window_used="$window"
    while IFS= read -r n; do
      [ -n "$n" ] && prs+=("$n")
    done < <(rer_list_recent_prs "$repo_slug" "$window")
    if [ "${#prs[@]}" -eq 0 ]; then
      rer_fail "no pull requests found in ${repo_slug}"
    fi
    report="$(rer_build_report "$repo_slug" "${prs[@]}")"
    final_report="$(printf '%s\n' "$report" | jq -c --argjson w "$window_used" '. + {window_used: $w}')"
  fi

  if [ "$json_output" -eq 1 ]; then
    printf '%s\n' "$final_report"
  else
    rer_render_text "$final_report"
  fi
}

if [ "$_HARNESS_MODE_EFFECTIVE" -eq 0 ]; then
  rer_main "$@"
fi
