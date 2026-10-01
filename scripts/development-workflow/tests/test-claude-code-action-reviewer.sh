#!/usr/bin/env bash
# test-claude-code-action-reviewer.sh — Tests for claude-code-action-reviewer.sh.
#
# Area 1 covers the dispatch-response parser that binds a run to its own
# dispatch by workflow_run_id (#1789, plan D15 Claude dispatch rule); Area 2
# (T2.23) runs the whole companion against a mock gh and proves it polls only
# the returned run id and never searches the run list, so an older run for the
# same PR can never answer this request (this replaces the #806/#808 run-list
# filter tests: the fresh path no longer has that filter). Area 3 (T4.5) covers
# re-wait adoption of a recorded run. Areas 6-8 cover the
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
# D12 request record: the bound run id and the dispatch time.
run_test "1789_D12_fresh_request_ref_is_bound_run" "1" "$(grep -c '^REVIEW_REQUEST_REF=777$' "$_t223_dir/out" || true)"
run_test "1789_D12_fresh_requested_at_is_dispatch_time" "yes" \
  "$( [ "$(grep '^REVIEW_REQUESTED_AT=' "$_t223_dir/out" | cut -d= -f2)" = "$(grep '^INFO: dispatch time (pre-dispatch): ' "$_t223_dir/out" | sed 's/^INFO: dispatch time (pre-dispatch): //')" ] && echo yes || echo no)"

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
  "$(grep -c '^VERDICT: UNAVAILABLE — workflow dispatch failed: .*Unprocessable Entity (HTTP 422)$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_dispatch_rejected_no_polling" "0" "$(_t223_calls 'actions/runs')"
run_test "1789_T2.23_dispatch_not_found_exit_3" "3" "$(_t223_run not_found completed success)"
run_test "1789_T2.23_dispatch_not_found_result" "1" "$(grep -c '^DISPATCH_RESULT=workflow_not_found$' "$_t223_dir/out" || true)"
run_test "1789_T2.23_dispatch_not_found_no_polling" "0" "$(_t223_calls 'actions/runs')"

rm -rf "$_t223_dir"
unset _t223_dir MOCK_T223_LOG
unset -f _t223_run _t223_calls

# ---------------------------------------------------------------------------
# Area 3 (#1789, T4.5): re-wait adoption with --adopt-run-id /
# --adopt-requested-at (plan D11 Claude row). The recorded run 888 is polled
# and nothing is dispatched; a bot review submitted before the recorded
# requested_at is not counted (the review boundary is kept); a completed
# success run 555 for this PR that is not the recorded run (an older-head run)
# is never read, so the result follows run 888 (still running → exit 4, never
# clean); a recorded run whose path or "PR #<n>" does not match, or that
# cannot be read, is not adopted and the companion dispatches.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: re-wait adoption of the recorded run (#1789 T4.5) ==="

_t45_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_t45_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_T45_LOG"
case "$*" in
  "auth status"*) exit 0 ;;
  *"pr view"*"baseRefName"*) echo "develop"; exit 0 ;;
  *"repo view"*"defaultBranchRef"*) echo "main"; exit 0 ;;
  *"/dispatches"*)
    printf '{"workflow_run_id":777}\n'
    exit 0
    ;;
  *"actions/runs?"*|*"actions/runs/555"*|"run view 555 "*)
    printf '{"id":555,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","status":"completed","conclusion":"success"}\n'
    exit 0
    ;;
  *"actions/runs/888"*)
    [ "${MOCK_T45_888_READ:-ok}" = "fail" ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    _concl=null
    [ -n "${MOCK_T45_888_CONCLUSION:-}" ] && _concl="\"${MOCK_T45_888_CONCLUSION}\""
    printf '{"id":888,"name":"%s","path":"%s","status":"%s","conclusion":%s,"html_url":"https://example.invalid/runs/888"}\n' \
      "${MOCK_T45_888_NAME:-Claude Code Review — PR #42}" \
      "${MOCK_T45_888_PATH:-.github/workflows/claude-code-review.yml}" \
      "${MOCK_T45_888_STATUS:-in_progress}" "$_concl"
    exit 0
    ;;
  *"actions/runs/777"*)
    printf '{"id":777,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","status":"in_progress","conclusion":null}\n'
    exit 0
    ;;
  "run view 888 "*"--log"*)
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: true'
    exit 0
    ;;
  *"pulls/42/reviews"*)
    # A CHANGES_REQUESTED bot review at MOCK_T45_REVIEW_AT.
    printf '[{"user":{"login":"claude[bot]"},"state":"CHANGES_REQUESTED","submitted_at":"%s"}]\n' "${MOCK_T45_REVIEW_AT:-2026-01-01T00:00:05Z}"
    exit 0
    ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK_GH
chmod +x "$_t45_dir/gh"
MOCK_T45_LOG="$_t45_dir/calls.log"
export MOCK_T45_LOG

# _t45_run [extra args...]: runs the companion with the given adoption args;
# prints the exit code. MOCK_T45_* in the caller's environment shape the mock.
_t45_run() {
  local status=0
  : > "$MOCK_T45_LOG"
  PATH="$_t45_dir:$PATH" bash "$REVIEWER_SCRIPT" 42 owner repo \
    --max-wait 2 --poll-interval 1 "$@" >"$_t45_dir/out" 2>"$_t45_dir/err" || status=$?
  printf '%s\n' "$status"
}
_t45_calls() { grep -c -- "$1" "$MOCK_T45_LOG" || true; }
_t45_adopt=(--adopt-run-id 888 --adopt-requested-at 2026-01-01T00:00:10Z)

# The recorded run is still running → exit 4; nothing dispatched; only run 888
# polled; the other completed run 555 and the run list are never read.
run_test "1789_T4.5_adopted_running_exit_4" "4" "$(_t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_adopted_no_dispatch" "0" "$(_t45_calls '/dispatches')"
run_test "1789_T4.5_adopted_polls_recorded_run" "yes" \
  "$( [ "$(_t45_calls 'actions/runs/888')" -ge 2 ] && echo yes || echo no)"
run_test "1789_T4.5_adopted_other_run_never_read" "0" "$(_t45_calls 'actions/runs?\|actions/runs/555\|run view 555\|actions/runs/777')"
run_test "1789_T4.5_adopted_dispatch_result" "1" "$(grep -c '^DISPATCH_RESULT=adopted$' "$_t45_dir/out" || true)"
run_test "1789_T4.5_adopted_request_keys_carried_forward" "REVIEW_REQUESTED_AT=2026-01-01T00:00:10Z|REVIEW_REQUEST_REF=888" \
  "$(grep '^REVIEW_REQUESTED_AT=' "$_t45_dir/out")|$(grep '^REVIEW_REQUEST_REF=' "$_t45_dir/out")"

# The recorded run completed success; the only CHANGES_REQUESTED bot review was
# submitted before the recorded requested_at → not counted → exit 0.
run_test "1789_T4.5_boundary_kept_review_before_request_not_counted" "0" \
  "$(MOCK_T45_888_STATUS=completed MOCK_T45_888_CONCLUSION=success MOCK_T45_REVIEW_AT=2026-01-01T00:00:05Z _t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_boundary_kept_no_dispatch" "0" "$(_t45_calls '/dispatches')"
# The same review submitted after the recorded requested_at counts → exit 1.
run_test "1789_T4.5_review_after_request_counted" "1" \
  "$(MOCK_T45_888_STATUS=completed MOCK_T45_888_CONCLUSION=success MOCK_T45_REVIEW_AT=2026-01-01T00:00:20Z _t45_run "${_t45_adopt[@]}")"

# A recorded run from another workflow file is not adopted: WARN, dispatch.
run_test "1789_T4.5_path_mismatch_dispatches_exit_4" "4" \
  "$(MOCK_T45_888_PATH=.github/workflows/other.yml _t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_path_mismatch_dispatched" "1" "$(_t45_calls '/dispatches')"
run_test "1789_T4.5_path_mismatch_warns" "1" "$(grep -c "^WARN: recorded Claude Code Action run 888 is not a 'claude-code-review.yml' run" "$_t45_dir/err" || true)"
run_test "1789_T4.5_path_mismatch_binds_new_run" "1" "$(grep -c '^REVIEW_REQUEST_REF=777$' "$_t45_dir/out" || true)"
# GitHub may return a ref-qualified path (<file>@<ref>): still the same
# workflow file, so it is adopted without a duplicate dispatch.
for _t45_ref in '@main' '@refs/heads/main'; do
  _t45_tag="${_t45_ref//[^a-z]/_}"
  run_test "1789_T4.5_path_ref_${_t45_tag}_adopted_exit_4" "4" \
    "$(MOCK_T45_888_PATH=".github/workflows/claude-code-review.yml${_t45_ref}" _t45_run "${_t45_adopt[@]}")"
  run_test "1789_T4.5_path_ref_${_t45_tag}_no_dispatch" "0" "$(_t45_calls '/dispatches')"
  run_test "1789_T4.5_path_ref_${_t45_tag}_dispatch_result" "1" "$(grep -c '^DISPATCH_RESULT=adopted$' "$_t45_dir/out" || true)"
done
# A ref-qualified path of another workflow file, or a lookalike file name, is
# not adopted.
run_test "1789_T4.5_path_other_ref_dispatches_exit_4" "4" \
  "$(MOCK_T45_888_PATH=.github/workflows/other.yml@main _t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_path_other_ref_dispatched" "1" "$(_t45_calls '/dispatches')"
run_test "1789_T4.5_path_bak_dispatches_exit_4" "4" \
  "$(MOCK_T45_888_PATH=.github/workflows/claude-code-review.yml.bak _t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_path_bak_dispatched" "1" "$(_t45_calls '/dispatches')"
unset _t45_ref _t45_tag
# A recorded run named for another PR is not adopted.
run_test "1789_T4.5_pr_mismatch_dispatches_exit_4" "4" \
  "$(MOCK_T45_888_NAME='Claude Code Review — PR #421' _t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_pr_mismatch_dispatched" "1" "$(_t45_calls '/dispatches')"
run_test "1789_T4.5_pr_mismatch_warns" "1" "$(grep -c '^WARN: recorded Claude Code Action run 888 is not named for PR #42' "$_t45_dir/err" || true)"
# A recorded run that cannot be read is not adopted.
run_test "1789_T4.5_unreadable_dispatches_exit_4" "4" "$(MOCK_T45_888_READ=fail _t45_run "${_t45_adopt[@]}")"
run_test "1789_T4.5_unreadable_dispatched" "1" "$(_t45_calls '/dispatches')"
# The two flags come together; malformed values are argument errors (exit 2).
run_test "1789_T4.5_run_id_alone_exit_2" "2" "$(_t45_run --adopt-run-id 888)"
run_test "1789_T4.5_requested_at_alone_exit_2" "2" "$(_t45_run --adopt-requested-at 2026-01-01T00:00:10Z)"
run_test "1789_T4.5_bad_run_id_exit_2" "2" "$(_t45_run --adopt-run-id abc --adopt-requested-at 2026-01-01T00:00:10Z)"
run_test "1789_T4.5_bad_requested_at_exit_2" "2" "$(_t45_run --adopt-run-id 888 --adopt-requested-at yesterday)"
run_test "1789_T4.5_argument_errors_call_nothing" "0" "$(_t45_calls '.')"

rm -rf "$_t45_dir"
unset _t45_dir MOCK_T45_LOG _t45_adopt
unset -f _t45_run _t45_calls

# ---------------------------------------------------------------------------
# Area 4 (#1789, T2.19): --head-sha binds counted reviews to the loop head
# (plan D15 claude-code-action row). The bound run completes success; the only
# bot review is a CHANGES_REQUESTED review submitted after DISPATCH_TIME. With
# --head-sha H1 it counts only when its commit_id is H1 (GitHub fixes a
# review's commit_id at submission); a review on H0 is another revision's
# verdict and is not counted, so the run is clean. Without --head-sha today's
# time-bounded count is kept.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: --head-sha review binding (#1789 T2.19) ==="

_t219_h1="1789abcdef000000000000000000000000000001"
_t219_h0="1789abcdef000000000000000000000000000000"
_t219_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_t219_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_T219_LOG"
case "$*" in
  "auth status"*) exit 0 ;;
  *"pr view"*"baseRefName"*) echo "develop"; exit 0 ;;
  *"repo view"*"defaultBranchRef"*) echo "main"; exit 0 ;;
  *"actions/runs/888"*)
    printf '{"id":888,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","status":"completed","conclusion":"success","html_url":"https://example.invalid/runs/888"}\n'
    exit 0
    ;;
  "run view 888 "*"--log"*)
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: true'
    exit 0
    ;;
  *"pulls/42/reviews"*)
    printf '[{"user":{"login":"claude[bot]"},"state":"CHANGES_REQUESTED","submitted_at":"2026-01-01T00:00:20Z","commit_id":"%s"}]\n' "$MOCK_T219_REVIEW_COMMIT"
    exit 0
    ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK_GH
chmod +x "$_t219_dir/gh"
MOCK_T219_LOG="$_t219_dir/calls.log"
export MOCK_T219_LOG

# _t219_run <review_commit_id> [extra args...]: prints the exit code.
_t219_run() {
  local status=0 commit="$1"
  shift
  : > "$MOCK_T219_LOG"
  MOCK_T219_REVIEW_COMMIT="$commit" PATH="$_t219_dir:$PATH" bash "$REVIEWER_SCRIPT" 42 owner repo \
    --max-wait 2 --poll-interval 1 --adopt-run-id 888 --adopt-requested-at 2026-01-01T00:00:10Z \
    "$@" >"$_t219_dir/out" 2>"$_t219_dir/err" || status=$?
  printf '%s\n' "$status"
}

run_test "1789_T2.19_other_revision_review_not_counted_clean" "0" "$(_t219_run "$_t219_h0" --head-sha "$_t219_h1")"
run_test "1789_T2.19_other_revision_review_verdict_approved" "1" "$(grep -c '^VERDICT: APPROVED' "$_t219_dir/out" || true)"
run_test "1789_T2.19_bound_review_counted_needs_revision" "1" "$(_t219_run "$_t219_h1" --head-sha "$_t219_h1")"
run_test "1789_T2.19_bound_review_case_insensitive" "1" \
  "$(_t219_run "$_t219_h1" --head-sha "$(printf '%s' "$_t219_h1" | tr 'a-f' 'A-F')")"
run_test "1789_T2.19_without_head_sha_keeps_time_count" "1" "$(_t219_run "$_t219_h0")"
run_test "1789_T2.19_review_without_commit_id_not_counted" "0" "$(_t219_run "" --head-sha "$_t219_h1")"
run_test "1789_T2.19_short_head_sha_exit_2" "2" "$(_t219_run "$_t219_h1" --head-sha 1789abc)"
run_test "1789_T2.19_short_head_sha_calls_nothing" "0" "$(grep -c . "$MOCK_T219_LOG" || true)"
run_test "1789_T2.19_head_sha_requires_value_exit_2" "2" "$(_t219_run "$_t219_h1" --head-sha)"
run_test "1789_T2.19_usage_names_head_sha" "1" "$(grep -c '\[--head-sha <sha>\]' "$REVIEWER_SCRIPT" || true)"

rm -rf "$_t219_dir"
unset _t219_dir MOCK_T219_LOG _t219_h0 _t219_h1
unset -f _t219_run

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

_cca_usage="$(sed -n '1,/^set -euo pipefail$/p' "$REVIEWER_SCRIPT")"
run_test "1789_header_documents_exit_4" "1" \
  "$(grep -c '^#   4 — NO_VERDICT_YET' <<<"$_cca_usage" || true)"

unset MOCK_CCA_RUN_STATUS MOCK_CCA_RUN_CONCLUSION _cca_usage
rm -rf "$_cca_mock_dir"
unset _cca_mock_dir

# ---------------------------------------------------------------------------
# Area 10 (#1789, spec BR 2): a failed read of the bound run during polling.
# Only positive evidence makes a reviewer failed: a 401/403 permission refusal
# or a 404 for the bound run id is exit 3 (UNAVAILABLE), never exit 4; a rate
# limit (also HTTP 403) and a transient 5xx keep polling; a run that could not
# be read on any poll within the budget fails closed (exit 3); a transient 502
# followed by a completed run gives the normal verdict.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10: polling read failures are not No verdict yet (#1789 BR 2) ==="

_pf_dir="$(mktemp -d)" || { echo "ERROR: mktemp -d failed" >&2; exit 1; }
cat > "$_pf_dir/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  *"pr view"*"baseRefName"*) echo "develop"; exit 0 ;;
  *"repo view"*"defaultBranchRef"*) echo "main"; exit 0 ;;
  *"/dispatches"*) printf '{"workflow_run_id":931}\n'; exit 0 ;;
  *"actions/runs/931"*)
    _n=0
    [ -f "$MOCK_PF_COUNT" ] && _n="$(cat "$MOCK_PF_COUNT")"
    _n=$((_n + 1)); printf '%s' "$_n" > "$MOCK_PF_COUNT"
    _ok='{"id":931,"name":"Claude Code Review — PR #42","path":".github/workflows/claude-code-review.yml","status":"completed","conclusion":"success","html_url":"https://example.invalid/runs/931"}'
    case "$MOCK_PF_MODE" in
      denied403) echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1 ;;
      denied401) echo "gh: Bad credentials (HTTP 401)" >&2; exit 1 ;;
      notfound) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      ratelimit) echo "gh: API rate limit exceeded for user (HTTP 403)" >&2; exit 1 ;;
      always502) echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1 ;;
      flaky)
        if [ "$_n" -eq 1 ]; then echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1; fi
        printf '%s\n' "$_ok"; exit 0 ;;
      ratelimit_then_inprogress)
        if [ "$_n" -eq 1 ]; then echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1; fi
        printf '{"id":931,"status":"in_progress","conclusion":null,"html_url":"https://example.invalid/runs/931"}\n'; exit 0 ;;
    esac
    ;;
  "run view 931 "*"--log"*)
    echo 'Claude Code Action review	UNKNOWN STEP	Context prompt: /code-review:code-review owner/repo/pull/42'
    echo 'Claude Code Action review	UNKNOWN STEP	Trigger result: true'
    exit 0
    ;;
  *"pulls/42/reviews"*) echo '[]'; exit 0 ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
MOCK_GH
chmod +x "$_pf_dir/gh"
MOCK_PF_COUNT="$_pf_dir/count"
export MOCK_PF_COUNT

_pf_run() {
  local status=0
  rm -f "$MOCK_PF_COUNT"
  MOCK_PF_MODE="$1" PATH="$_pf_dir:$PATH" bash "$REVIEWER_SCRIPT" 42 owner repo \
    --max-wait 3 --poll-interval 1 >"$_pf_dir/out" 2>"$_pf_dir/err" || status=$?
  printf '%s\n' "$status"
}
_pf_out() { grep -c -- "$1" "$_pf_dir/out" || true; }

run_test "1789_poll_403_exit_3" "3" "$(_pf_run denied403)"
run_test "1789_poll_403_verdict_unavailable" "1" "$(_pf_out '^VERDICT: UNAVAILABLE')"
run_test "1789_poll_403_no_no_verdict_yet" "0" "$(_pf_out '^VERDICT: NO_VERDICT_YET')"
run_test "1789_poll_403_stops_at_first_read" "1" "$(cat "$MOCK_PF_COUNT")"
run_test "1789_poll_401_exit_3" "3" "$(_pf_run denied401)"
run_test "1789_poll_401_verdict_unavailable" "1" "$(_pf_out '^VERDICT: UNAVAILABLE')"
run_test "1789_poll_404_bound_run_exit_3" "3" "$(_pf_run notfound)"
run_test "1789_poll_404_result_run_not_found" "1" "$(_pf_out '^POLL_RESULT=run_not_found')"
run_test "1789_poll_always_502_fails_closed_exit_3" "3" "$(_pf_run always502)"
run_test "1789_poll_always_502_result_run_unreadable" "1" "$(_pf_out '^POLL_RESULT=run_unreadable')"
run_test "1789_poll_always_502_no_no_verdict_yet" "0" "$(_pf_out '^VERDICT: NO_VERDICT_YET')"
run_test "1789_poll_always_rate_limit_fails_closed_exit_3" "3" "$(_pf_run ratelimit)"
run_test "1789_poll_rate_limit_keeps_polling" "yes" \
  "$([ "$(cat "$MOCK_PF_COUNT")" -gt 1 ] && echo yes || echo no)"
run_test "1789_poll_rate_limit_then_in_progress_exit_4" "4" "$(_pf_run ratelimit_then_inprogress)"
run_test "1789_poll_transient_502_then_success_exit_0" "0" "$(_pf_run flaky)"
run_test "1789_poll_transient_502_then_success_verdict" "1" "$(_pf_out '^VERDICT: APPROVED')"

# The classifier itself.
run_test "1789_classify_403_denied" "denied" "$(claude_code_action_classify_poll_error 'gh: Forbidden (HTTP 403)')"
run_test "1789_classify_401_denied" "denied" "$(claude_code_action_classify_poll_error 'gh: Unauthorized (HTTP 401)')"
run_test "1789_classify_404_gone" "gone" "$(claude_code_action_classify_poll_error 'gh: Not Found (HTTP 404)')"
run_test "1789_classify_403_rate_limit_transient" "transient" \
  "$(claude_code_action_classify_poll_error 'gh: API rate limit exceeded (HTTP 403)')"
run_test "1789_classify_secondary_rate_limit_transient" "transient" \
  "$(claude_code_action_classify_poll_error 'You have exceeded a secondary rate limit (HTTP 403)')"
run_test "1789_classify_502_transient" "transient" "$(claude_code_action_classify_poll_error 'gh: Bad Gateway (HTTP 502)')"
run_test "1789_classify_empty_transient" "transient" "$(claude_code_action_classify_poll_error '')"

unset MOCK_PF_COUNT
rm -rf "$_pf_dir"
unset _pf_dir

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
