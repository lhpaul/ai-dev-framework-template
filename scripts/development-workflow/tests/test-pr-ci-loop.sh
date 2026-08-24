#!/usr/bin/env bash
# test-pr-ci-loop.sh - CI loop verdict tests.
# covers: scripts/development-workflow/pr-ci-loop.sh
#
# Focus: the CI-evidence gate (#1514, #1580). "No failing and no pending
# checks" is not evidence that CI ran — a head can legitimately carry zero
# checks (GitHub builds no merge ref for a CONFLICTING PR, so its
# pull_request workflows never start) or only a subset after a filter change.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass=0
fail=0
run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"; pass=$((pass + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"; fail=$((fail + 1))
  fi
}

# make_gh <dir> — a gh stub driven by env vars:
#   MOCK_ROLLUP        statusCheckRollup JSON
#   MOCK_PREV_CHECKS   workflow_runs payload for the previous head
#                       ({"workflow_runs":[{"name":...}, ...]})
#   MOCK_PR_COMMITS    commit SHAs for the PR (JSON array)
make_gh() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/gh" <<'GH'
#!/usr/bin/env bash
# Defaults are plain variables: a ${VAR:-{...}} default containing braces does
# not survive bash parameter expansion and silently yields invalid JSON.
head_default='aaaa111000000000000'
rollup_default='{"statusCheckRollup":[]}'
runs_default='{"workflow_runs":[]}'
commits_default='[]'
runs_default='{"workflow_runs":[]}'
# The real gh applies --jq locally; a stub that ignores it hands the caller a
# raw payload where it expects a filtered scalar. Apply the filter for real.
jq_filter=""
slurped=0
case "$*" in *--slurp*) slurped=1 ;; esac
prev=""
for arg in "$@"; do
  [ "$prev" = "--jq" ] && jq_filter="$arg"
  prev="$arg"
done
# With --slurp, gh wraps each page's payload in an outer array; the filters
# under test index through that wrapper, so the stub must mimic it. Setting
# MOCK_PAGINATED=1 returns two identical pages, which is how a per-page --jq
# bug shows up (duplicate/multiple results) versus a correct aggregate.
emit() {
  local payload="$1"
  case "$*" in *) ;; esac
  if [ "$slurped" = "1" ]; then
    if [ "${MOCK_PAGINATED:-0}" = "1" ]; then
      payload="[$1,$1]"
    else
      payload="[$1]"
    fi
  fi
  if [ -n "$jq_filter" ]; then
    printf '%s\n' "$payload" | jq -r "$jq_filter"
  else
    printf '%s\n' "$payload"
  fi
}
case "$*" in
  *"auth status"*) exit 0 ;;
  *"--json headRefOid"*) emit "{\"headRefOid\":\"${MOCK_HEAD_SHA:-$head_default}\"}" ; exit 0 ;;
  *"--json statusCheckRollup"*) emit "${MOCK_ROLLUP:-$rollup_default}" ; exit 0 ;;
  *"/actions/runs"*)
    [ "${MOCK_RUNS_FAIL:-0}" = "1" ] && exit 1
    # Both sides of the evidence comparison hit this endpoint; distinguish
    # them by the head_sha in the query so a test can make them differ.
    case "$*" in
      *"head_sha=${MOCK_HEAD_SHA:-$head_default}"*) emit "${MOCK_CURRENT_RUNS:-$runs_default}" ;;
      *) emit "${MOCK_PREV_CHECKS:-$runs_default}" ;;
    esac
    exit 0 ;;
  *"/commits"*) emit "${MOCK_PR_COMMITS:-$commits_default}" ; exit 0 ;;
  *"/reviews"*|*"/comments"*) emit '[]' ; exit 0 ;;
  *) emit '{}' ; exit 0 ;;
esac
GH
  chmod +x "$dir/gh"
}

_bin="$TMP_ROOT/bin"
make_gh "$_bin"

_success_rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"workflow test harnesses","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"}]}'
_subset_rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"}]}'
_prev_two='{"workflow_runs":[{"name":"workflow test harnesses"},{"name":"ShellCheck"}]}'
_commits_two='[{"sha":"bbbb222000000000000"},{"sha":"aaaa111000000000000"}]'

# A matrix workflow (e.g. workflow-tests.yml) reports one job per selected
# suite under a single workflowName; the previous head ran two suite leaves
# plus the workflow's own aggregator/select jobs, all under "workflow test
# harnesses". The current head selected a *different, smaller* set of leaves
# (legitimate — the diff narrowed) but the same workflow, still green.
_matrix_prev='{"workflow_runs":[{"name":"workflow test harnesses"}]}'
_matrix_current_rollup='{"statusCheckRollup":[
  {"__typename":"CheckRun","name":"select suites","workflowName":"workflow test harnesses","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"CheckRun","name":"scripts/development-workflow/tests/test-only-this-suite-now.sh","workflowName":"workflow test harnesses","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"CheckRun","name":"workflow test harnesses","workflowName":"workflow test harnesses","status":"COMPLETED","conclusion":"SUCCESS"}
]}'

_runs_two='{"workflow_runs":[{"name":"workflow test harnesses"},{"name":"ShellCheck"}]}'
_runs_one='{"workflow_runs":[{"name":"ShellCheck"}]}'
_runs_matrix='{"workflow_runs":[{"name":"workflow test harnesses"}]}'

run_ci() {
  local out status=0
  out="$(env PATH="$_bin:$PATH" "$@" bash "$HELPER" 42 --repo owner/repo --poll-interval 1 --max-wait 1 2>/dev/null)" || status=$?
  printf '%s\n---STATUS=%s\n' "$out" "$status"
}

# 1. Same check set as the previous head → green.
_out="$(run_ci MOCK_ROLLUP="$_success_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_two" MOCK_PR_COMMITS="$_commits_two")"
run_test "full_check_set_is_green" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "green_reports_head_sha" "HEAD_SHA=aaaa111000000000000" "$(grep '^HEAD_SHA=' <<<"$_out" || true)"
run_test "green_reports_ci_evidence_present" "CI_EVIDENCE=present" "$(grep '^CI_EVIDENCE=' <<<"$_out" || true)"

# 2. A workflow that ran on the previous head is absent now → red, named.
#    This is the PR #1577 shape: a conflicting PR whose pull_request workflows
#    never started, leaving a passing subset that used to read as green.
_out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two")"
run_test "missing_workflow_is_red" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "missing_workflow_reason" "REASON=expected_checks_missing" "$(grep '^REASON=' <<<"$_out" || true)"
run_test "missing_workflow_is_named" "MISSING_CHECKS=workflow test harnesses" "$(grep '^MISSING_CHECKS=' <<<"$_out" || true)"

# 3. Zero checks with no previous head → green (unchanged) but evidence=none,
#    so the readiness gate can refuse rather than label on absence.
_out="$(run_ci MOCK_ROLLUP='{"statusCheckRollup":[]}' MOCK_PR_COMMITS='[]')"
run_test "no_checks_still_green" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "no_checks_reports_evidence_none" "CI_EVIDENCE=none" "$(grep '^CI_EVIDENCE=' <<<"$_out" || true)"

# 4. The gate is skippable for callers that know better, and does not fire when
#    the previous head ran nothing.
_out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" CI_LOOP_SKIP_EVIDENCE_GATE=1)"
run_test "evidence_gate_is_skippable" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"
_out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS='{"workflow_runs":[]}' MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two")"
run_test "no_previous_checks_does_not_fire" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"

# 4b. A matrix workflow's selected suite set narrows on the current head
#     (select-test-suites.sh legitimately picked fewer/different leaves) but
#     the same workflow ran and passed — must stay green, not read as a
#     missing check. Comparing at check-run granularity (pre-fix behavior)
#     would have reported the previous head's leaf name as MISSING_CHECKS
#     and gone red; workflow-level comparison must not.
_out="$(run_ci MOCK_ROLLUP="$_matrix_current_rollup" MOCK_PREV_CHECKS="$_runs_matrix" MOCK_CURRENT_RUNS="$_runs_matrix" MOCK_PR_COMMITS="$_commits_two")"
run_test "matrix_suite_churn_stays_green" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"

# 4c. Both sides read from actions/runs, so plain commit statuses and matrix
#     leaves in the rollup (which have no workflow-run counterpart) can never
#     be mistaken for a missing workflow (pr-agent on PR #1588).
_status_rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","context":"CodeRabbit","state":"SUCCESS"}]}'
_out="$(run_ci MOCK_ROLLUP="$_status_rollup" MOCK_PREV_CHECKS="$_runs_one" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two")"
run_test "commit_statuses_are_not_missing_workflows" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"

# 4d. A failed evidence lookup is not "no expectation": the gate fails closed
#     rather than letting its own error produce a green verdict (CodeRabbit on
#     PR #1588). MOCK_RUNS_FAIL makes actions/runs exit non-zero.
_out="$(run_ci MOCK_ROLLUP="$_success_rollup" MOCK_PR_COMMITS="$_commits_two" MOCK_RUNS_FAIL=1)"
run_test "evidence_lookup_failure_is_red" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "evidence_lookup_failure_reason" "REASON=ci_evidence_lookup_failed" "$(grep '^REASON=' <<<"$_out" || true)"
run_test "evidence_lookup_failure_marks_unknown" "CI_EVIDENCE=unknown" "$(grep '^CI_EVIDENCE=' <<<"$_out" || true)"
_out="$(run_ci MOCK_ROLLUP="$_success_rollup" MOCK_PR_COMMITS="$_commits_two" MOCK_RUNS_FAIL=1 CI_LOOP_SKIP_EVIDENCE_GATE=1)"
run_test "skip_flag_bypasses_lookup_failure" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"

# 4e. Paginated responses must be reduced before comparison: with --paginate
#     but no --slurp, `--jq` runs per page and emits one result per page.
_out="$(run_ci MOCK_ROLLUP="$_success_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_two" MOCK_PR_COMMITS="$_commits_two" MOCK_PAGINATED=1)"
run_test "paginated_lookup_still_green" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"

# 5. A genuinely failing check is still red (the gate did not displace it).
_fail_rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE"}]}'
_out="$(run_ci MOCK_ROLLUP="$_fail_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_two" MOCK_PR_COMMITS="$_commits_two")"
run_test "failing_check_still_red" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "failing_check_names_it" "FAILING_CHECKS=ShellCheck" "$(grep '^FAILING_CHECKS=' <<<"$_out" || true)"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
