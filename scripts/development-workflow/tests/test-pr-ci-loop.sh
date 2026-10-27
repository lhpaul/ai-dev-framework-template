#!/usr/bin/env bash
# test-pr-ci-loop.sh - CI loop verdict tests.
# covers: scripts/development-workflow/pr-ci-loop.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
#
# Focus: the CI-evidence gate (#1514, #1580). "No failing and no pending
# checks" is not evidence that CI ran — a head can legitimately carry zero
# checks (GitHub builds no merge ref for a CONFLICTING PR, so its
# pull_request workflows never start) or only a subset after a filter change.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="${CI_LOOP_TEST_HELPER:-$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh}"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
# No real repository configuration or service credentials enter the fixtures.
mkdir -p "$TMP_ROOT/repo with spaces"
git init --quiet "$TMP_ROOT/repo with spaces"
printf 'review: {}\n' > "$TMP_ROOT/repo with spaces/.ai-dev-workflow.local.yaml"
cat > "$TMP_ROOT/repo with spaces/.ai-dev-workflow.yaml" <<'CONFIG'
schema_version: 2
review:
  on_draft:
    runner: []
    github: []
  on_ready:
    github: []
issue_tracker:
  provider: none
CONFIG

pass=0
fail=0
# Holds the helper's stderr from the most recent run_ci call. Printed only when
# an assertion fails: the assertions compare the helper's stdout exactly, so
# stderr cannot be folded into the compared value, but discarding it outright
# leaves a failure with no diagnostic beyond the diff.
_last_stderr_file=""

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"; pass=$((pass + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"; fail=$((fail + 1))
    if [ -n "$_last_stderr_file" ] && [ -s "$_last_stderr_file" ]; then
      echo "  helper stderr:"
      sed 's/^/    /' "$_last_stderr_file"
    fi
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
  if [[ "$payload" == *workflow_runs* ]]; then
    payload="$(printf %s "$payload" | jq --arg missing "${MOCK_MISSING_PATH:-0}" '
      .workflow_runs |= map(. + {event: (.event // "pull_request")}
        | if $missing == "1" then . else . + {path: (.path // ".github/workflows/synthetic.yml")} end)')"
  fi
  case "$*" in *) ;; esac
  if [ "$slurped" = "1" ]; then
    if [ "${MOCK_PAGINATED:-0}" = "1" ]; then
      payload="[$payload,$payload]"
    else
      payload="[$payload]"
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
  *"--json headRefOid,baseRefName,state,mergeStateStatus"*)
    emit "{\"headRefOid\":\"${MOCK_CONTEXT_HEAD:-${MOCK_HEAD_SHA:-$head_default}}\",\"baseRefName\":\"${MOCK_BASE:-develop}\",\"state\":\"OPEN\",\"mergeStateStatus\":\"${MOCK_MERGE_STATE:-CLEAN}\"}" ; exit 0 ;;
  *"--json headRefOid"*)
    head="${MOCK_HEAD_SHA:-$head_default}"
    if [ "${MOCK_CHANGE_HEAD:-0}" = 1 ]; then
      if [ -f "$MOCK_HEAD_COUNTER" ]; then head=dddd444000000000000; fi
      touch "$MOCK_HEAD_COUNTER"
    fi
    emit "{\"headRefOid\":\"$head\"}" ; exit 0 ;;
  *"--json statusCheckRollup"*) emit "${MOCK_ROLLUP:-$rollup_default}" ; exit 0 ;;
  *"/contents/.github/workflows/"*)
    [ "${MOCK_CONTENTS_FAIL:-0}" = "1" ] && exit 1
    workflow_default=$'on:\n  pull_request:\n    branches: [develop, main]\n'
    case "$*" in *"/closed.yml?"*) workflow_default=$'on:\n  pull_request:\n    types: [closed]\n' ;; esac
    workflow="${MOCK_WORKFLOW:-$workflow_default}"
    if [ -n "${MOCK_HEAD_DEFINITION:-}" ]; then
      case "$*" in
        *"?ref=${MOCK_HEAD_SHA:-$head_default}"*) workflow="$(cat "$MOCK_HEAD_DEFINITION")" ;;
        *) workflow="$(cat "$MOCK_BASE_DEFINITION")" ;;
      esac
    fi
    [ -z "${MOCK_CONTENTS_LOG:-}" ] || printf '%s\n' "$*" >> "$MOCK_CONTENTS_LOG"
    payload="$(printf %s "$workflow" | base64 | tr -d '\n')"
    emit "{\"encoding\":\"base64\",\"content\":\"$payload\"}" ; exit 0 ;;
  *"/actions/runs"*)
    [ "${MOCK_RUNS_FAIL:-0}" = "1" ] && exit 1
    # Both sides of the evidence comparison hit this endpoint; distinguish
    # them by the head_sha in the query so a test can make them differ.
    if [ -n "${MOCK_CLOSED_RUN_SHA:-}" ]; then
      case "$*" in
        *"head_sha=${MOCK_CLOSED_RUN_SHA}"*) emit '{"workflow_runs":[{"name":"closed-only tracker","path":".github/workflows/closed.yml"}]}' ; exit 0 ;;
      esac
    fi
    if [ -n "${MOCK_EMPTY_RUN_SHA:-}" ]; then
      case "$*" in
        *"head_sha=${MOCK_EMPTY_RUN_SHA}"*) emit '{"workflow_runs":[]}' ; exit 0 ;;
      esac
    fi
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
# Exercise every verdict without third-party Python packages, even when the
# developer machine happens to have PyYAML installed.
python3 -m venv --without-pip "$TMP_ROOT/python"
cat > "$_bin/python3" <<'PYTHON'
#!/usr/bin/env bash
exec env -u PYTHONPATH PYTHONNOUSERSITE=1 "$CI_LOOP_TEST_PYTHON" "$@"
PYTHON
chmod +x "$_bin/python3"
export CI_LOOP_TEST_PYTHON="$TMP_ROOT/python/bin/python3"
run_test "pyyaml_is_unavailable_2037" "absent" "$("$CI_LOOP_TEST_PYTHON" -I -c 'import importlib.util; print("absent" if importlib.util.find_spec("yaml") is None else "present")')"

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
  _last_stderr_file="$TMP_ROOT/last-stderr"
  out="$(env AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/repo with spaces/.ai-dev-workflow.yaml" WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$TMP_ROOT/repo with spaces" PATH="$_bin:$PATH" MOCK_HEAD_COUNTER="$(mktemp "$TMP_ROOT/head.XXXXXX")-calls" "$@" bash "$HELPER" 42 --repo owner/repo --repo-root "$TMP_ROOT/repo with spaces" --poll-interval 1 --max-wait 1 2>"$_last_stderr_file")" || status=$?
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

# 4f. A multi-commit push: the penultimate SHA never ran pull_request
#     workflows, but an earlier SHA did. Using `.[-2]` would treat the prior
#     set as empty and fail-open green while the current head is missing a
#     workflow. Walk back to the latest earlier SHA that has runs.
_commits_three='[{"sha":"bbbb222000000000000"},{"sha":"cccc333000000000000"},{"sha":"aaaa111000000000000"}]'
_out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_three" MOCK_EMPTY_RUN_SHA=cccc333000000000000)"
run_test "penultimate_without_runs_still_uses_earlier_evidence" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "penultimate_without_runs_names_missing_workflow" "MISSING_CHECKS=workflow test harnesses" "$(grep '^MISSING_CHECKS=' <<<"$_out" || true)"

# 5. A genuinely failing check is still red (the gate did not displace it).
_fail_rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE"}]}'
_out="$(run_ci MOCK_ROLLUP="$_fail_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_two" MOCK_PR_COMMITS="$_commits_two")"
run_test "failing_check_still_red" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "failing_check_names_it" "FAILING_CHECKS=ShellCheck" "$(grep '^FAILING_CHECKS=' <<<"$_out" || true)"

# 6. Issue #1559: statusCheckRollup keeps superseded runs. The PR #1547 shape —
#    a commit status that failed at 05:26:31 and passed on re-run at 05:28:16,
#    beside a check run with the same history — is green (AC-2), whatever
#    order GitHub lists the entries in.
_superseded_rollup='{"statusCheckRollup":[
  {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"},
  {"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:26:31Z"},
  {"__typename":"CheckRun","name":"ShellCheck","workflowName":"ShellCheck","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-06-01T05:28:16Z"}
]}'
_out="$(run_ci MOCK_ROLLUP="$_superseded_rollup" MOCK_PREV_CHECKS="$_runs_one" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two")"
run_test "superseded_failure_is_green_1559" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "superseded_failure_counts_latest_runs_only_1559" "TOTAL_CHECK_COUNT=2" "$(grep '^TOTAL_CHECK_COUNT=' <<<"$_out" || true)"

# 6b. The reverse history — passed, then genuinely failed on the current run —
#     is still red and names the check (AC-3).
_current_failure_rollup='{"statusCheckRollup":[
  {"__typename":"StatusContext","context":"policy","state":"FAILURE","startedAt":"2026-06-01T05:28:16Z"},
  {"__typename":"StatusContext","context":"policy","state":"SUCCESS","startedAt":"2026-06-01T05:26:31Z"}
]}'
_out="$(run_ci MOCK_ROLLUP="$_current_failure_rollup" MOCK_PREV_CHECKS="$_runs_one" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two")"
run_test "current_failure_still_red_1559" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"
run_test "current_failure_named_1559" "FAILING_CHECKS=policy" "$(grep '^FAILING_CHECKS=' <<<"$_out" || true)"

# 7. Issue #1964: closed-only tracker runs on a prior implementation commit
# do not belong to open release/main or backport/develop readiness.
_tracker_prior='{"workflow_runs":[{"name":"ShellCheck"},{"name":"Update tracker status on PR merge"}]}'
_closed_workflow=$'name: Update tracker status on PR merge\non:\n  pull_request:\n    types: [closed]\n    branches: [develop]\njobs:\n  tracker:\n    if: github.event.pull_request.merged == true\n'
for _base in main develop; do
  _out="$(run_ci MOCK_BASE="$_base" MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_tracker_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_WORKFLOW="$_closed_workflow")"
  run_test "closed_only_tracker_${_base}_green_1964" "RESULT=green" "$(grep ^RESULT= <<<"$_out" || true)"
  run_test "closed_only_tracker_${_base}_exit_1964" "---STATUS=0" "$(grep ^---STATUS= <<<"$_out" || true)"
  run_test "closed_only_tracker_${_base}_evidence_1964" "CI_EVIDENCE=present" "$(grep ^CI_EVIDENCE= <<<"$_out" || true)"
done
# A planted applicable expectation must block; removing only the pre-merge
# activity makes the same prior run inapplicable and restores green above.
for _workflow in \
  $'on:\n  pull_request:\n    types: [closed, synchronize]\n    branches: [develop, main]\n' \
  $'on:\n  pull_request:\n    types: [closed]\n  push:\n' \
  $'on:\n  pull_request_target:\n    branches: ["release/**", develop]\n'; do
  _out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_tracker_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_WORKFLOW="$_workflow")"
  run_test "applicable_missing_workflow_blocks_1964" "RESULT=red" "$(grep ^RESULT= <<<"$_out" || true)"
  run_test "applicable_missing_workflow_named_1964" "MISSING_CHECKS=Update tracker status on PR merge" "$(grep ^MISSING_CHECKS= <<<"$_out" || true)"
done
# Event/base applicability, independent of workflow names.
for _workflow in \
  $'on:\n  pull_request:\n    types: [closed]\n' \
  $'on:\n  pull_request:\n    branches: [develop]\n' \
  $'on:\n  pull_request:\n    branches-ignore: [main]\n'; do
  _out="$(run_ci MOCK_BASE=main MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_WORKFLOW="$_workflow")"
  run_test "proven_inapplicability_green_1964" "RESULT=green" "$(grep ^RESULT= <<<"$_out" || true)"
done
# A newest earlier SHA carrying only a closed-only run must not conceal a
# genuinely applicable missing workflow on an older head.
_out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_three" MOCK_CLOSED_RUN_SHA=cccc333000000000000)"
run_test "closed_only_earlier_head_does_not_conceal_missing_check_1964" "MISSING_CHECKS=workflow test harnesses" "$(grep ^MISSING_CHECKS= <<<"$_out" || true)"
for _failure in MOCK_CONTENTS_FAIL=1 MOCK_MISSING_PATH=1 \
  MOCK_WORKFLOW=invalid MOCK_WORKFLOW='   ' \
  MOCK_WORKFLOW=$'on:\n  pull_request:\n    types: [synchronize]\n    types: [closed]\n' \
  MOCK_WORKFLOW=$'on:\n  pull_request:\n    types: [closed]\n    branches: invalid\n' MOCK_CONTEXT_HEAD=dddd444000000000000 MOCK_MERGE_STATE=DIRTY MOCK_CHANGE_HEAD=1; do
  _out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_tracker_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" "$_failure")"
  run_test "unreadable_or_changed_evidence_red_1964_${_failure%%=*}" "RESULT=red" "$(grep ^RESULT= <<<"$_out" || true)"
  run_test "unreadable_or_changed_evidence_reason_1964_${_failure%%=*}" "REASON=ci_evidence_lookup_failed" "$(grep ^REASON= <<<"$_out" || true)"
done
# Target-event definitions can differ between the authoritative branch and
# PR HEAD. Retain the expectation, without trusting either a closed-only head
# edit or deletion of its target trigger. Both definition routes are fabricated.
cat > "$TMP_ROOT/base-workflow.yml" <<'YAML'
on:
  pull_request_target:
    types: [synchronize]
    branches: [develop, main]
YAML
_target_prior='{"workflow_runs":[{"name":"ShellCheck","event":"pull_request"},{"name":"target policy","event":"pull_request_target","path":".github/workflows/target.yml"}]}'
for _head_definition in \
  $'on:\n  pull_request_target:\n    types: [closed]\n' \
  $'on:\n  pull_request:\n    types: [closed]\n'; do
  printf '%s\n' "$_head_definition" > "$TMP_ROOT/head-workflow.yml"
  _out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_target_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_HEAD_DEFINITION="$TMP_ROOT/head-workflow.yml" MOCK_BASE_DEFINITION="$TMP_ROOT/base-workflow.yml" MOCK_CONTENTS_LOG="$TMP_ROOT/target-definition-reads")"
  run_test "divergent_target_definition_red_1964" "RESULT=red" "$(grep ^RESULT= <<<"$_out" || true)"
  run_test "divergent_target_definition_named_1964" "MISSING_CHECKS=target policy" "$(grep ^MISSING_CHECKS= <<<"$_out" || true)"
  run_test "divergent_target_definition_exit_1964" "---STATUS=1" "$(grep ^---STATUS= <<<"$_out" || true)"
  run_test "target_definition_not_trusted_from_head_1964" "absent" "$(if [ -e "$TMP_ROOT/target-definition-reads" ]; then echo present; else echo absent; fi)"
done
# The trigger reader must tolerate ordinary job shell blocks without parsing
# their shell text as YAML, and support quoted/scalar/flow trigger spellings.
for _workflow in \
  $'---\nname: Synthetic workflow\n"on": # trigger comment\n  pull_request:\n    types:\n      - closed\njobs:\n  synthetic:\n    steps:\n      - run: |\n          echo "on: [push]"\n          echo "types: [synchronize]"\n' \
  "'on': {pull_request: {types: [closed]}}"; do
  _out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_tracker_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_WORKFLOW="$_workflow")"
  run_test "closed_only_yaml_forms_without_pyyaml_2037" "RESULT=green" "$(grep ^RESULT= <<<"$_out" || true)"
done
for _workflow in 'on: pull_request' 'on: [pull_request]' \
  $'on:\n  pull_request:\n    branches: ["release/**"]\n' \
  $'on:\n  pull_request:\n    branches-ignore: ["develop*"]\n'; do
  _out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_tracker_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_WORKFLOW="$_workflow")"
  run_test "applicable_or_unknown_triggers_stay_expected_2037" "MISSING_CHECKS=Update tracker status on PR merge" "$(grep ^MISSING_CHECKS= <<<"$_out" || true)"
done
for _workflow in \
  $'on: {pull_request: {types: [synchronize], types: [closed]}}\n' \
  $'on: [push]\n"on": {pull_request: {types: [closed]}}\n' \
  $'on:\n  pull_request: &activity\n    types: [closed]\n' \
  $'on:\n  pull_request:\n    types: [closed]\n<<: *other_triggers\n' \
  $'jobs:\n  build:\n    name: "hello\non:\n  pull_request:\n    types: [closed]\nenv: end"\n' \
  $'name: [unfinished,\n  continuation]\non:\n  pull_request:\n    types: [closed]\n' \
  $'name: "unfinished\non:\n  pull_request:\n    types: [closed]\n'; do
  _out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_tracker_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_WORKFLOW="$_workflow")"
  run_test "ambiguous_trigger_definition_fails_closed_2037" "REASON=ci_evidence_lookup_failed" "$(grep ^REASON= <<<"$_out" || true)"
done
# Even unreadable head contents cannot drop a target-event expectation.
_out="$(run_ci MOCK_ROLLUP="$_subset_rollup" MOCK_PREV_CHECKS="$_target_prior" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two" MOCK_CONTENTS_FAIL=1)"
run_test "target_without_head_definition_still_expected_1964" "MISSING_CHECKS=target policy" "$(grep ^MISSING_CHECKS= <<<"$_out" || true)"

_pending_rollup='{"statusCheckRollup":[{"__typename":"CheckRun","name":"ShellCheck","status":"IN_PROGRESS","conclusion":null}]}'
_out="$(run_ci MOCK_ROLLUP="$_pending_rollup" MOCK_WORKFLOW="$_closed_workflow")"
run_test "pending_checks_still_timeout_1964" "RESULT=timeout" "$(grep ^RESULT= <<<"$_out" || true)"

# Exercise the shared predicate boundary without service data. Empty/whitespace,
# absent, array and false fields are conservative non-exclusions.
_predicate_matrix_1970="$(
  source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"
  jq -n "$CONFIGURED_REVIEWER_CHECK_JQ"'
    def record: {__typename:"CheckRun",name:"PR-Agent review"};
    [ (["QUEUED","IN_PROGRESS","WAITING","REQUESTED","PENDING","EXPECTED"][] as $s
        | [null, ""][] as $c
        | record + {status:$s,conclusion:$c} | configured_reviewer_check(["PR-Agent review"])),
      (["SUCCESS","FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE","NEUTRAL","SKIPPED"][] as $c
        | record + {status:"COMPLETED",conclusion:$c} | configured_reviewer_check(["PR-Agent review"]))
    ] | all'
)"
run_test "recognized_reviewer_shapes_1970" true "$_predicate_matrix_1970"
_predicate_negative_1970="$(
  source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"
  jq -n "$CONFIGURED_REVIEWER_CHECK_JQ"'
    [ {}, {__typename:"CheckRun", name:"PR-Agent review", status:" "},
      {__typename:"CheckRun", name:"PR-Agent review", status:"IN_PROGRESS", conclusion:false},
      {__typename:"CheckRun", name:"PR-Agent review", status:["COMPLETED"], conclusion:"SUCCESS"},
      {__typename:"CheckRun", name:"PR-Agent review", status:"COMPLETED", conclusion:["SUCCESS"]},
      {__typename:"CheckRun", name:"PR-Agent review", status:"COMPLETED", conclusion:"SUCCESS", state:"FAILURE"}
    ] | map(configured_reviewer_check(["PR-Agent review"])) | any'
)"
run_test "malformed_reviewer_shapes_1970" false "$_predicate_negative_1970"

# #1970: effective draft reviewer owns exactly one check; the local reviewer
# publishes a ledger, not a GitHub check run.
cat > "$TMP_ROOT/repo with spaces/.ai-dev-workflow.yaml" <<'CONFIG'
schema_version: 2
review:
  on_draft:
    runner: []
    github: [pr-agent]
  on_ready:
    github: [local-ai-reviewer]
issue_tracker:
  provider: none
CONFIG
for _state in 'IN_PROGRESS null' 'COMPLETED "FAILURE"'; do
  read -r _status _conclusion <<< "$_state"
  _reviewer=$(jq -nc --arg s "$_status" --argjson c "$_conclusion" '{__typename:"CheckRun",name:"PR-Agent review",status:$s,conclusion:$c}')
  _release_rollup=$(jq --argjson r "$_reviewer" '.statusCheckRollup += [$r]' <<< "$_success_rollup")
  _out="$(run_ci MOCK_ROLLUP="$_release_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_two" MOCK_PR_COMMITS="$_commits_two")"
  run_test "release_reviewer_${_status}_green_1970" "RESULT=green" "$(grep '^RESULT=' <<<"$_out" || true)"
  run_test "release_reviewer_${_status}_count_1970" "REVIEWER_CHECK_COUNT=1" "$(grep '^REVIEWER_CHECK_COUNT=' <<<"$_out" || true)"
done

# Same-name malformed records, lookalikes, and ordinary CI retain their
# original verdict classification and never enter reviewer projections.
for _mutation in 'del(.__typename)' '.__typename = "Unknown"' '.status = "UNKNOWN"' '.status = "IN_PROGRESS"' '.conclusion = "UNKNOWN"' '.name = "PR-Agent review extra"' '.status = ["COMPLETED"]' '.conclusion = ["FAILURE"]' '.status = "IN_PROGRESS" | .conclusion = false' '.conclusion = "SUCCESS" | .state = "FAILURE"'; do
  _bad=$(jq "$_mutation" <<< "$_reviewer")
  _rollup=$(jq --argjson r "$_bad" '.statusCheckRollup += [$r]' <<< "$_success_rollup")
  _out="$(run_ci MOCK_ROLLUP="$_rollup" MOCK_PR_COMMITS='[]')"
  run_test "malformed_not_projected_1970_${_mutation}" "REVIEWER_CHECK_COUNT=0" "$(grep '^REVIEWER_CHECK_COUNT=' <<<"$_out" || true)"
  if [ "$_mutation" = '.status = ["COMPLETED"]' ]; then
    # The existing rollup normalizer rejects this structural type error before
    # any reviewer projection. Preserve that parse refusal instead of a count.
    run_test "malformed_status_parse_refusal_1970" "REASON=check_json_parse_failed" "$(grep '^REASON=' <<<"$_out" || true)"
  else
    run_test "malformed_retained_in_ci_1970_${_mutation}" "TOTAL_CHECK_COUNT=3" "$(grep '^TOTAL_CHECK_COUNT=' <<<"$_out" || true)"
  fi
done
for _ordinary in FAILURE PENDING; do
  _rollup=$(jq --arg c "$_ordinary" --argjson r "$_reviewer" '.statusCheckRollup += [$r] | .statusCheckRollup[0] += (if $c == "PENDING" then {status:"IN_PROGRESS",conclusion:null} else {conclusion:$c} end)' <<< "$_success_rollup")
  _out="$(run_ci MOCK_ROLLUP="$_rollup" MOCK_PR_COMMITS='[]')"
  _expected=red
  [ "$_ordinary" != PENDING ] || _expected=timeout
  run_test "ordinary_${_ordinary}_blocks_reviewer_exemption_1970" "RESULT=$_expected" "$(grep '^RESULT=' <<<"$_out" || true)"
done
_out="$(run_ci MOCK_ROLLUP="$_release_rollup" MOCK_PREV_CHECKS="$_runs_two" MOCK_CURRENT_RUNS="$_runs_one" MOCK_PR_COMMITS="$_commits_two")"
run_test "missing_workflow_blocks_reviewer_exemption_1970" "REASON=expected_checks_missing" "$(grep '^REASON=' <<<"$_out" || true)"
# Remove only the configured draft reviewer; its failed check must block.
sed 's/github: \[pr-agent\]/github: []/' "$TMP_ROOT/repo with spaces/.ai-dev-workflow.yaml" > "$TMP_ROOT/unconfigured.yaml"
mv "$TMP_ROOT/unconfigured.yaml" "$TMP_ROOT/repo with spaces/.ai-dev-workflow.yaml"
_out="$(run_ci MOCK_ROLLUP="$_release_rollup" MOCK_PR_COMMITS='[]')"
run_test "unconfigured_reviewer_blocks_1970" "RESULT=red" "$(grep '^RESULT=' <<<"$_out" || true)"

printf '\nResults: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
