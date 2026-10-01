#!/usr/bin/env bash
# test-claude-code-action-reviewer.sh — Tests for claude-code-action-reviewer.sh.
#
# Area 1 covers the dispatch-response parser that binds a run to its own
# dispatch by workflow_run_id (#1789, plan D15 Claude dispatch rule); Area 2
# (T2.23) runs the whole companion against a mock gh and proves it polls only
# the returned run id and never searches the run list, so an older run for the
# same PR can never answer this request (this replaces the #806/#808 run-list
# filter tests: the fresh path no longer has that filter). Areas 6-8 cover the
# date fallback, the Actions log verification, and the workflow prompt; Area 9
# covers the exit codes for a run that never completes (4) or fails (2).
#
# Usage: bash scripts/development-workflow/tests/test-claude-code-action-reviewer.sh
# Requires: bash, jq
# Exit code: 0 if all tests pass, 1 if any test fails.

set -euo pipefail

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

REVIEWER_SCRIPT="scripts/development-workflow/claude-code-action-reviewer.sh"
# shellcheck disable=SC2034 # Consumed by the sourced reviewer script.
CLAUDE_CODE_ACTION_REVIEWER_LIBRARY_MODE=1
# shellcheck source=scripts/development-workflow/claude-code-action-reviewer.sh
source "$REVIEWER_SCRIPT"
unset CLAUDE_CODE_ACTION_REVIEWER_LIBRARY_MODE

# ---------------------------------------------------------------------------
# Area 1 (#1789, plan D15 Claude dispatch rule): the dispatch-response parser.
# The run is bound to this request only by the integer workflow_run_id GitHub
# returns for a dispatch sent with return_run_details=true. Every other body —
# empty (HTTP 204), not JSON, not an object, a string or fractional id, zero,
# negative, or several JSON values — yields nothing, which the companion turns
# into exit 3 (unavailable).
#
# This replaces the former Areas 1-5, which copied the run-list jq filter
# (POLL_AFTER_TIME window, "PR #<n>" run-name scoping, newest created_at). The
# fresh path no longer has that filter: it never reads the run list.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: dispatch response workflow_run_id (#1789 D15) ==="

_resp_tmp="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; exit 1; }
_parse_resp() {
  printf '%s' "$1" > "$_resp_tmp"
  claude_code_action_dispatch_run_id "$_resp_tmp"
}
run_test "dispatch_run_id_integer" "777" \
  "$(_parse_resp '{"workflow_run_id":777,"run_url":"https://api.github.com/repos/o/r/actions/runs/777","html_url":"https://github.com/o/r/actions/runs/777"}')"
run_test "dispatch_run_id_large_integer" "23456789012" "$(_parse_resp '{"workflow_run_id":23456789012}')"
run_test "dispatch_run_id_empty_204_body" "" "$(_parse_resp '')"
run_test "dispatch_run_id_missing_key" "" "$(_parse_resp '{"run_url":"https://x"}')"
run_test "dispatch_run_id_null" "" "$(_parse_resp '{"workflow_run_id":null}')"
run_test "dispatch_run_id_string_rejected" "" "$(_parse_resp '{"workflow_run_id":"777"}')"
run_test "dispatch_run_id_fraction_rejected" "" "$(_parse_resp '{"workflow_run_id":7.5}')"
run_test "dispatch_run_id_zero_rejected" "" "$(_parse_resp '{"workflow_run_id":0}')"
run_test "dispatch_run_id_negative_rejected" "" "$(_parse_resp '{"workflow_run_id":-3}')"
run_test "dispatch_run_id_not_json" "" "$(_parse_resp 'HTTP/2.0 204 No Content')"
run_test "dispatch_run_id_array_body" "" "$(_parse_resp '[{"workflow_run_id":777}]')"
run_test "dispatch_run_id_two_values_rejected" "" "$(_parse_resp '{"workflow_run_id":1}{"workflow_run_id":2}')"
run_test "dispatch_run_id_missing_file" "" "$(claude_code_action_dispatch_run_id "$_resp_tmp.absent")"
rm -f "$_resp_tmp"
unset _resp_tmp
unset -f _parse_resp

# ---------------------------------------------------------------------------
# Area 2 (#1789, T2.23): regression — an older completed Claude run inside the
# old dispatch window. The runs list holds a completed success run for this PR
# created 5 s before the dispatch (inside the removed 10 s window) and no
# blocking review; the dispatch response returns workflow_run_id 777, a
# different run that stays in_progress. The companion polls only run 777, never
# reads the run list, and exits 4 at the budget, never 0. Variants: run 777
# completes success → exit 0; an empty 204 dispatch body → exit 3 with the D15
# message and no polling; a dispatch the API rejects → exit 3, no polling.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: dispatch-response run binding (#1789 T2.23) ==="

_t223_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_t223_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_T223_LOG"
case "$*" in
  "auth status"*) exit 0 ;;
  *"pr view"*"baseRefName"*) echo "develop"; exit 0 ;;
  *"repo view"*"defaultBranchRef"*) echo "main"; exit 0 ;;
  *"/dispatches"*)
    case "${MOCK_T223_DISPATCH:-id}" in
      id) printf '{"workflow_run_id":777,"run_url":"https://api.github.com/repos/owner/repo/actions/runs/777","html_url":"https://github.com/owner/repo/actions/runs/777"}\n' ;;
      empty) : ;;
      string_id) printf '{"workflow_run_id":"777"}\n' ;;
      rejected) echo "gh: Unprocessable Entity (HTTP 422)" >&2; exit 1 ;;
      not_found) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    esac
    exit 0
    ;;
  *"actions/runs?event="*)
    # The older completed success run for this PR, created 5 s before the
    # dispatch: the old time-window search would have selected it.
    _created="$(date -u -r "$(( $(date -u +%s) - 5 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( $(date -u +%s) - 5 ))" +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"workflow_runs":[{"id":555,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","created_at":"%s","status":"completed","conclusion":"success","html_url":"https://example.invalid/runs/555"}]}\n' "$_created"
    exit 0
    ;;
  *"actions/runs/777"*)
    _concl=null
    [ -n "${MOCK_T223_RUN_CONCLUSION:-}" ] && _concl="\"${MOCK_T223_RUN_CONCLUSION}\""
    printf '{"id":777,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","status":"%s","conclusion":%s,"html_url":"https://example.invalid/runs/777"}\n' \
      "${MOCK_T223_RUN_STATUS:-in_progress}" "$_concl"
    exit 0
    ;;
  "run view 777 "*"--log"*)
    echo 'Claude Code Action review	UNKNOWN STEP	Context prompt: /code-review:code-review owner/repo/pull/42'
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: true'
    exit 0
    ;;
  "run view 555 "*)
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: true'
    exit 0
    ;;
  *"pulls/42/reviews"*) echo '[]'; exit 0 ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK_GH
chmod +x "$_t223_dir/gh"
MOCK_T223_LOG="$_t223_dir/calls.log"
export MOCK_T223_LOG

# _t223_run <dispatch-mode> <run-status> [run-conclusion]: prints the exit code.
_t223_run() {
  local status=0
  : > "$MOCK_T223_LOG"
  MOCK_T223_DISPATCH="$1" MOCK_T223_RUN_STATUS="$2" MOCK_T223_RUN_CONCLUSION="${3:-}" \
    PATH="$_t223_dir:$PATH" bash "$REVIEWER_SCRIPT" 42 owner repo \
    --max-wait 2 --poll-interval 1 >"$_t223_dir/out" 2>"$_t223_dir/err" || status=$?
  printf '%s\n' "$status"
}
_t223_calls() { grep -c -- "$1" "$MOCK_T223_LOG" || true; }

# In-progress dispatched run, older completed success run in the list → exit 4.
run_test "1789_T2.23_in_progress_run_exit_4" "4" "$(_t223_run id in_progress)"
run_test "1789_T2.23_in_progress_verdict_no_verdict_yet" "1" \
  "$(grep -c '^VERDICT: NO_VERDICT_YET' "$_t223_dir/out" || true)"
run_test "1789_T2.23_run_list_never_read" "0" "$(_t223_calls 'actions/runs?event=')"
run_test "1789_T2.23_older_run_never_read" "0" "$(_t223_calls 'actions/runs/555\|run view 555')"
run_test "1789_T2.23_polls_returned_id" "yes" \
  "$( [ "$(_t223_calls 'actions/runs/777')" -ge 1 ] && echo yes || echo no)"
# Every "found run" line names the bound id (smoke runbook Step 8 reads these).
run_test "1789_T2.23_found_run_lines_name_bound_id" "yes" \
  "$( [ "$(grep -c 'found run — id=' "$_t223_dir/out" || true)" -ge 1 ] \
      && [ "$(grep 'found run — id=' "$_t223_dir/out" | grep -vc 'found run — id=777 ' || true)" -eq 0 ] \
      && echo yes || echo no)"
run_test "1789_T2.23_dispatch_requests_run_details" "1" \
  "$(grep '/dispatches' "$MOCK_T223_LOG" | grep -c -- '--field return_run_details=true' || true)"
run_test "1789_T2.23_dispatch_result_accepted" "1" "$(grep -c '^DISPATCH_RESULT=accepted$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_dispatch_run_id_printed" "1" "$(grep -c '^DISPATCH_WORKFLOW_RUN_ID=777$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_no_poll_after_time" "0" "$(grep -c 'POLL_AFTER_TIME\|poll filter time' "$REVIEWER_SCRIPT" "$_t223_dir/out" | awk -F: '{s+=$NF} END{print s+0}')"

# Variant: the returned run completes success → exit 0.
run_test "1789_T2.23_returned_run_success_exit_0" "0" "$(_t223_run id completed success)"
run_test "1789_T2.23_returned_run_success_verdict" "1" \
  "$(grep -c '^VERDICT: APPROVED' "$_t223_dir/out" || true)"
run_test "1789_T2.23_returned_run_success_log_of_bound_run" "1" "$(_t223_calls 'run view 777 ')"
run_test "1789_T2.23_returned_run_success_no_list_read" "0" "$(_t223_calls 'actions/runs?event=')"

# Variant: the returned run completes failure → exit 2 (failure, never clean).
run_test "1789_T2.23_returned_run_failure_exit_2" "2" "$(_t223_run id completed failure)"

# Variant: an empty 204 dispatch body → exit 3 with the D15 message, no polling.
run_test "1789_T2.23_empty_204_exit_3" "3" "$(_t223_run empty completed success)"
run_test "1789_T2.23_empty_204_d15_message" "1" \
  "$(grep -c '^VERDICT: UNAVAILABLE — dispatch response carried no workflow_run_id; the run cannot be bound to this request$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_empty_204_dispatch_result" "1" "$(grep -c '^DISPATCH_RESULT=no_workflow_run_id$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_empty_204_no_polling" "0" "$(_t223_calls 'actions/runs')"

# Variant: a 2xx body whose workflow_run_id is not an integer → exit 3, no polling.
run_test "1789_T2.23_string_id_exit_3" "3" "$(_t223_run string_id completed success)"
run_test "1789_T2.23_string_id_no_polling" "0" "$(_t223_calls 'actions/runs')"

# Variant (deferred note d): a dispatch the API rejects → exit 3 unavailable
# with a rejected / workflow_not_found reason, no polling, never a pass.
run_test "1789_T2.23_dispatch_rejected_exit_3" "3" "$(_t223_run rejected completed success)"
run_test "1789_T2.23_dispatch_rejected_result" "1" "$(grep -c '^DISPATCH_RESULT=rejected$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_dispatch_rejected_verdict" "1" \
  "$(grep -c '^VERDICT: UNAVAILABLE — workflow dispatch failed: gh: Unprocessable Entity (HTTP 422)$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_dispatch_rejected_no_polling" "0" "$(_t223_calls 'actions/runs')"
run_test "1789_T2.23_dispatch_not_found_exit_3" "3" "$(_t223_run not_found completed success)"
run_test "1789_T2.23_dispatch_not_found_result" "1" "$(grep -c '^DISPATCH_RESULT=workflow_not_found$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_dispatch_not_found_no_polling" "0" "$(_t223_calls 'actions/runs')"

rm -rf "$_t223_dir"
unset _t223_dir MOCK_T223_LOG
unset -f _t223_run _t223_calls

# ---------------------------------------------------------------------------
# Area 6: epoch→ISO8601 conversion fallback
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6: epoch→ISO8601 conversion fallback ==="

_date_mock_dir="$(mktemp -d)"
cat > "$_date_mock_dir/date" <<'MOCK_DATE'
#!/usr/bin/env bash
exit 1
MOCK_DATE
chmod +x "$_date_mock_dir/date"

_epoch_to_iso_with_python_fallback() {
  local epoch="$1"
  PATH="$_date_mock_dir:$PATH" date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    PATH="$_date_mock_dir:$PATH" date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
    python3 -c "import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$epoch"
}

_iso="$(_epoch_to_iso_with_python_fallback 1700000000)"
run_test "python_fallback_epoch_to_iso" "2023-11-14T22:13:20Z" "$_iso"
rm -rf "$_date_mock_dir"
unset _date_mock_dir _iso

# ---------------------------------------------------------------------------
# Area 7: Claude Code Action log execution verification
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 7: action log execution verification ==="

_log_tmp="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; exit 1; }
cat > "$_log_tmp" <<'LOG'
Claude Code Action review	UNKNOWN STEP	Context prompt: NO PROMPT
Claude Code Action review	UNKNOWN STEP	Trigger result: false
Claude Code Action review	UNKNOWN STEP	No trigger found, skipping remaining steps
LOG
_status=0
_classification="$(classify_claude_code_action_log "$_log_tmp")" || _status=$?
run_test "noop_log_is_not_clean_status" "1" "$_status"
run_test "noop_log_is_classified_noop" "noop" "$_classification"
rm -f "$_log_tmp"
unset _log_tmp _status _classification

_log_tmp="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; exit 1; }
cat > "$_log_tmp" <<'LOG'
Claude Code Action review	UNKNOWN STEP	Context prompt: /code-review:code-review lhpaul/ai-dev-framework-template/pull/866
Claude Code Action review	UNKNOWN STEP	Trigger result: true
LOG
_status=0
_classification="$(classify_claude_code_action_log "$_log_tmp")" || _status=$?
run_test "executed_log_is_clean_status" "0" "$_status"
run_test "executed_log_is_classified_ran" "ran" "$_classification"
rm -f "$_log_tmp"
unset _log_tmp _status _classification

_log_tmp="$(mktemp)" || { echo "ERROR: mktemp failed" >&2; exit 1; }
cat > "$_log_tmp" <<'LOG'
Claude Code Action review	UNKNOWN STEP	Mode: agent
Claude Code Action review	UNKNOWN STEP	App token successfully obtained
LOG
_status=0
_classification="$(classify_claude_code_action_log "$_log_tmp")" || _status=$?
run_test "unknown_log_is_not_clean_status" "2" "$_status"
run_test "unknown_log_is_classified_unknown" "unknown" "$_classification"
rm -f "$_log_tmp"
unset _log_tmp _status _classification

_status=0
_output="$(verify_claude_code_action_run_log "" "owner" "repo" 2>&1)" || _status=$?
run_test "missing_run_id_returns_unavailable" "3" "$_status"
case "$_output" in
  *"no run id was available"*) _message_found=1 ;;
  *) _message_found=0 ;;
esac
run_test "missing_run_id_message" "1" "$_message_found"
unset _status _output _message_found

_gh_mock_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_gh_mock_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
echo "mock gh failure" >&2
exit 1
MOCK_GH
chmod +x "$_gh_mock_dir/gh"
_old_path="$PATH"
PATH="$_gh_mock_dir:$PATH"
_status=0
_output="$(verify_claude_code_action_run_log "123" "owner" "repo" 2>&1)" || _status=$?
PATH="$_old_path"
run_test "gh_run_view_failure_returns_unavailable" "3" "$_status"
case "$_output" in
  *"log verification failed"*) _message_found=1 ;;
  *) _message_found=0 ;;
esac
run_test "gh_run_view_failure_message" "1" "$_message_found"
rm -rf "$_gh_mock_dir"
unset _gh_mock_dir _old_path _status _output _message_found

_gh_mock_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_gh_mock_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$3" in
  200)
    echo 'Claude Code Action review	UNKNOWN STEP	Context prompt: /code-review:code-review owner/repo/pull/1'
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: true'
    ;;
  201)
    echo 'Claude Code Action review	UNKNOWN STEP	Context prompt: NO PROMPT'
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: false'
    ;;
  202)
    echo 'Claude Code Action review	UNKNOWN STEP	Mode: agent'
    echo 'Claude Code Action review	UNKNOWN STEP	App token successfully obtained'
    ;;
  *)
    echo "unexpected run id: $3" >&2
    exit 1
    ;;
esac
MOCK_GH
chmod +x "$_gh_mock_dir/gh"
_old_path="$PATH"
PATH="$_gh_mock_dir:$PATH"

_status=0
_output="$(verify_claude_code_action_run_log "200" "owner" "repo" 2>&1)" || _status=$?
run_test "verify_run_log_executed_returns_clean" "0" "$_status"
case "$_output" in
  *"log verification passed (ran)"*) _message_found=1 ;;
  *) _message_found=0 ;;
esac
run_test "verify_run_log_executed_message" "1" "$_message_found"
unset _status _output _message_found

_status=0
_output="$(verify_claude_code_action_run_log "201" "owner" "repo" 2>&1)" || _status=$?
run_test "verify_run_log_noop_returns_unavailable" "3" "$_status"
case "$_output" in
  *"without executing a review (noop)"*) _message_found=1 ;;
  *) _message_found=0 ;;
esac
run_test "verify_run_log_noop_message" "1" "$_message_found"
unset _status _output _message_found

_status=0
_output="$(verify_claude_code_action_run_log "202" "owner" "repo" 2>&1)" || _status=$?
PATH="$_old_path"
run_test "verify_run_log_unknown_returns_unavailable" "3" "$_status"
case "$_output" in
  *"did not contain a positive execution marker (unknown)"*) _message_found=1 ;;
  *) _message_found=0 ;;
esac
run_test "verify_run_log_unknown_message" "1" "$_message_found"
rm -rf "$_gh_mock_dir"
unset _gh_mock_dir _old_path _status _output _message_found

_mktemp_mock_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_mktemp_mock_dir/mktemp" <<'MOCK_MKTEMP'
#!/usr/bin/env bash
echo "mktemp unavailable" >&2
exit 1
MOCK_MKTEMP
chmod +x "$_mktemp_mock_dir/mktemp"
_old_path="$PATH"
PATH="$_mktemp_mock_dir:$PATH"
_status=0
_output="$(verify_claude_code_action_run_log "203" "owner" "repo" 2>&1)" || _status=$?
PATH="$_old_path"
run_test "verify_run_log_mktemp_failure_returns_unavailable" "3" "$_status"
case "$_output" in
  *"could not create temp file"*) _message_found=1 ;;
  *) _message_found=0 ;;
esac
run_test "verify_run_log_mktemp_failure_message" "1" "$_message_found"
rm -rf "$_mktemp_mock_dir"
unset _mktemp_mock_dir _old_path _status _output _message_found

# ---------------------------------------------------------------------------
# Area 8: workflow automation prompt configuration
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 8: workflow prompt configuration ==="

_workflow_file=".github/workflows/claude-code-review.yml"
if [ -f "$_workflow_file" ]; then
  # shellcheck disable=SC2016 # Literal GitHub expression expected in workflow YAML.
  if grep -q 'prompt: "/code-review:code-review ${{ github.repository }}/pull/${{ inputs.pr_number }}"' "$_workflow_file"; then
    _has_prompt=1
  else
    _has_prompt=0
  fi
  run_test "workflow_has_explicit_code_review_prompt" "1" "$_has_prompt"

  if grep -q 'plugins: "code-review@claude-code-plugins"' "$_workflow_file"; then
    _has_plugin=1
  else
    _has_plugin=0
  fi
  run_test "workflow_has_code_review_plugin" "1" "$_has_plugin"
else
  echo "INFO: optional Claude Code Action workflow not present; skipping workflow prompt assertions"
fi
unset _workflow_file _has_prompt _has_plugin

# ---------------------------------------------------------------------------
# Area 9 (#1789, plan D8 Claude row, T2.8): companion exit codes for a run
# that never completes within the budget (exit 4, No verdict yet) and a run
# that completed with a non-success conclusion (exit 2, failure).
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 9: no verdict yet vs failed run exit codes (#1789) ==="

_cca_mock_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_cca_mock_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  *"pr view"*"baseRefName"*) echo "develop"; exit 0 ;;
  *"repo view"*"defaultBranchRef"*) echo "main"; exit 0 ;;
  # #1789 D15: every mock dispatch returns a workflow_run_id body.
  *"/dispatches"*) printf '{"workflow_run_id":901}\n'; exit 0 ;;
  *"actions/runs/901"*)
    conclusion_json=null
    [ -n "${MOCK_CCA_RUN_CONCLUSION:-}" ] && conclusion_json="\"${MOCK_CCA_RUN_CONCLUSION}\""
    printf '{"id":901,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","created_at":"2999-01-01T00:00:00Z","status":"%s","conclusion":%s,"html_url":"https://example.invalid/runs/901"}\n' \
      "${MOCK_CCA_RUN_STATUS:-in_progress}" "$conclusion_json"
    exit 0
    ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK_GH
chmod +x "$_cca_mock_dir/gh"

_cca_run() {
  local status=0
  PATH="$_cca_mock_dir:$PATH" bash "$REVIEWER_SCRIPT" 42 owner repo \
    --max-wait 2 --poll-interval 1 >"$_cca_mock_dir/out" 2>"$_cca_mock_dir/err" || status=$?
  printf '%s\n' "$status"
}

MOCK_CCA_RUN_STATUS=in_progress MOCK_CCA_RUN_CONCLUSION=""
export MOCK_CCA_RUN_STATUS MOCK_CCA_RUN_CONCLUSION
run_test "1789_run_not_completed_exit_4" "4" "$(_cca_run)"
run_test "1789_run_not_completed_verdict" "1" \
  "$(grep -c '^VERDICT: NO_VERDICT_YET' "$_cca_mock_dir/out" || true)"

MOCK_CCA_RUN_STATUS=completed MOCK_CCA_RUN_CONCLUSION=failure
export MOCK_CCA_RUN_STATUS MOCK_CCA_RUN_CONCLUSION
run_test "1789_run_completed_failure_exit_2" "2" "$(_cca_run)"
run_test "1789_run_completed_failure_verdict" "1" \
  "$(grep -c "^VERDICT: FAILED — run completed with conclusion 'failure'" "$_cca_mock_dir/out" || true)"

MOCK_CCA_RUN_STATUS=completed MOCK_CCA_RUN_CONCLUSION=timed_out
export MOCK_CCA_RUN_STATUS MOCK_CCA_RUN_CONCLUSION
run_test "1789_run_completed_timed_out_exit_2" "2" "$(_cca_run)"

MOCK_CCA_RUN_STATUS=completed MOCK_CCA_RUN_CONCLUSION=""
export MOCK_CCA_RUN_STATUS MOCK_CCA_RUN_CONCLUSION
run_test "1789_run_completed_without_conclusion_exit_2" "2" "$(_cca_run)"

_cca_usage="$(sed -n '1,45p' "$REVIEWER_SCRIPT")"
run_test "1789_header_documents_exit_4" "1" \
  "$(grep -c '^#   4 — NO_VERDICT_YET' <<<"$_cca_usage" || true)"

unset MOCK_CCA_RUN_STATUS MOCK_CCA_RUN_CONCLUSION _cca_usage
rm -rf "$_cca_mock_dir"
unset _cca_mock_dir

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
