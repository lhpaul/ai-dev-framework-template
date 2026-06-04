#!/usr/bin/env bash
# test-haystack-reviewer.sh — Unit tests for haystack-reviewer.sh
#
# Exercises the poll-retry logic introduced in issue #795:
#   1. status=pending retry loop — script retries when triage returns pending
#   2. pending_timeout exit — REASON=pending_timeout when budget exhausted on pending
#   3. Distinct REASON values — unavailable vs. timeout vs. pending_timeout
#   4. status=none still maps to REASON=unavailable (permanent unavailability)
#   5. status=completed (no status field) proceeds to findings parsing
#   6. HAYSTACK_POLL_INTERVAL env var controls retry cadence
#   7. argument validation
#   8. non-zero exit + valid JSON recovery (issue #800):
#      - non-zero exit + valid completed JSON → findings parsed (not UNAVAILABLE)
#      - non-zero exit + status=pending JSON → poll-retry (not UNAVAILABLE)
#      - non-zero exit + status=none JSON → UNAVAILABLE (correct)
#      - non-zero exit + empty stdout → UNAVAILABLE (correct)
#      - non-zero exit + invalid JSON stdout → UNAVAILABLE (correct)
#   9. status=error / incomplete-synthesis never yields clean (issue #800 fix round 2):
#      - status=error then completed-with-findings → findings surfaced (not clean)
#      - status=error persisting until timeout → REASON=pending_timeout (not clean)
#      - completed-with-0-findings → clean (the ONLY path that may yield clean)
#      - status=error then completed-0-findings → clean (retry succeeds, result is genuinely empty)
#
# Usage: bash scripts/development-workflow/tests/test-haystack-reviewer.sh
# No external tooling required beyond bash and jq (jq is used to validate JSON
# in haystack-reviewer.sh; mock haystack commands return controlled JSON).
#
# Exit code: 0 if all tests pass, 1 if any test fails.

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate repository root (works inside worktrees and normal checkouts).
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# Use --git-common-dir (not --show-toplevel) so this resolves correctly even
# when the harness is run inside a git worktree (--show-toplevel returns the
# worktree path, not the main repo root).
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)"

HAYSTACK_REVIEWER="$REPO_ROOT/scripts/development-workflow/haystack-reviewer.sh"

if [ ! -f "$HAYSTACK_REVIEWER" ]; then
  echo "ERROR: haystack-reviewer.sh not found at $HAYSTACK_REVIEWER" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Temp dir for mock binaries and state files.
# ---------------------------------------------------------------------------
MOCK_BIN="$(mktemp -d)"
CALL_LOG="$(mktemp)"
RESPONSE_SEQ_FILE="$(mktemp)"
EXIT_SEQ_FILE="$(mktemp)"
_REVIEWER_OUTPUT_FILE="$(mktemp)"
_REVIEWER_EXIT_FILE="$(mktemp)"

_harness_exit() {
  local status=$?
  rm -rf "$MOCK_BIN"
  rm -f "$CALL_LOG" "$RESPONSE_SEQ_FILE" "$EXIT_SEQ_FILE" \
        "${_REVIEWER_OUTPUT_FILE:-}" "${_REVIEWER_EXIT_FILE:-}"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

# ---------------------------------------------------------------------------
# Test framework — minimal pass/fail counter and assertion helper.
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# Mock helpers
#
# Each test installs a mock `haystack` binary into MOCK_BIN that is prepended
# to PATH. The mock reads MOCK_HAYSTACK_OUTPUTS (a file containing one JSON
# payload per line, in order of calls) and returns the next payload each time
# it is invoked. When the payload sequence is exhausted, it returns the last
# entry again to handle over-polling gracefully.
#
# MOCK_HAYSTACK_EXIT_SEQ controls exit codes in the same line order as outputs;
# defaults to "0" for every call.
# ---------------------------------------------------------------------------

_reset_mocks() {
  rm -f "$CALL_LOG"
  CALL_LOG="$(mktemp)"
  rm -f "$RESPONSE_SEQ_FILE"
  RESPONSE_SEQ_FILE="$(mktemp)"
  rm -f "$EXIT_SEQ_FILE"
  EXIT_SEQ_FILE="$(mktemp)"
  # Write the current MOCK_HAYSTACK_OUTPUTS lines (one JSON per line) to the
  # sequence file consumed by the mock binary.
  if [ -n "${MOCK_HAYSTACK_OUTPUTS:-}" ]; then
    printf '%s\n' "$MOCK_HAYSTACK_OUTPUTS" > "$RESPONSE_SEQ_FILE"
  fi
  # Write the current MOCK_HAYSTACK_EXITS lines (one exit code per line) to the
  # exit-code sequence file consumed by the mock binary.
  if [ -n "${MOCK_HAYSTACK_EXITS:-}" ]; then
    printf '%s\n' "$MOCK_HAYSTACK_EXITS" > "$EXIT_SEQ_FILE"
  fi
}

_install_haystack_mock() {
  # Create the mock haystack binary. It reads from RESPONSE_SEQ_FILE,
  # EXIT_SEQ_FILE, and CALL_LOG path from environment variables exported before
  # calling the script.
  #
  # MOCK_HAYSTACK_EXITS (optional): one exit code per line in the same order as
  # MOCK_HAYSTACK_OUTPUTS.  Defaults to 0 for every call if unset or exhausted.
  cat > "$MOCK_BIN/haystack" <<'MOCK_HAYSTACK'
#!/usr/bin/env bash
# Append call counter to log.
echo "call" >> "$MOCK_CALL_LOG"

# Read the next response from the sequence file (one JSON per line).
call_num=$(wc -l < "$MOCK_CALL_LOG" | tr -d ' ')
total_lines=$(wc -l < "$MOCK_RESPONSE_SEQ" | tr -d ' ')
if [ "$total_lines" -eq 0 ]; then
  # No responses configured — return empty (triggers UNAVAILABLE).
  exit 0
fi
if [ "$call_num" -le "$total_lines" ]; then
  line_num="$call_num"
else
  line_num="$total_lines"  # repeat last entry
fi
response=$(sed -n "${line_num}p" "$MOCK_RESPONSE_SEQ")
printf '%s\n' "$response"

# Read the corresponding exit code from EXIT_SEQ_FILE (defaults to 0).
mock_exit=0
if [ -n "${MOCK_EXIT_SEQ:-}" ] && [ -f "$MOCK_EXIT_SEQ" ]; then
  total_exits=$(wc -l < "$MOCK_EXIT_SEQ" | tr -d ' ')
  if [ "$total_exits" -gt 0 ]; then
    if [ "$call_num" -le "$total_exits" ]; then
      exit_line_num="$call_num"
    else
      exit_line_num="$total_exits"
    fi
    mock_exit=$(sed -n "${exit_line_num}p" "$MOCK_EXIT_SEQ" | tr -d '[:space:]')
    case "$mock_exit" in
      ''|*[!0-9]*) mock_exit=0 ;;
    esac
  fi
fi
exit "$mock_exit"
MOCK_HAYSTACK
  chmod +x "$MOCK_BIN/haystack"
}

_call_count() {
  # Returns number of times the mock haystack was called.
  if [ ! -f "$CALL_LOG" ]; then echo "0"; return; fi
  wc -l < "$CALL_LOG" | tr -d ' '
}

_run_reviewer() {
  # Runs haystack-reviewer.sh, captures stdout to _REVIEWER_OUTPUT_FILE and
  # exit code to _REVIEWER_EXIT_FILE. Never fails the calling shell.
  local timeout="${1:-30}"
  local poll_interval="${2:-1}"
  rm -f "$_REVIEWER_OUTPUT_FILE" "$_REVIEWER_EXIT_FILE"
  set +e
  HAYSTACK_REVIEWER_TIMEOUT="$timeout" \
  HAYSTACK_POLL_INTERVAL="$poll_interval" \
  HAYSTACK_PR_STATUS_CHECK="${TEST_HAYSTACK_PR_STATUS_CHECK:-0}" \
  MOCK_CALL_LOG="$CALL_LOG" \
  MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$MOCK_BIN:$PATH" \
    bash "$HAYSTACK_REVIEWER" "123" "owner" "repo" \
    >"$_REVIEWER_OUTPUT_FILE" 2>/dev/null
  echo $? > "$_REVIEWER_EXIT_FILE"
  set -e
  cat "$_REVIEWER_OUTPUT_FILE"
}

_run_reviewer_exit_code() {
  # Returns the exit code from the most recent _run_reviewer call, or runs
  # a fresh invocation if called standalone.
  if [ -s "$_REVIEWER_EXIT_FILE" ]; then
    cat "$_REVIEWER_EXIT_FILE"
  else
    local timeout="${1:-30}"
    local poll_interval="${2:-1}"
    set +e
    HAYSTACK_REVIEWER_TIMEOUT="$timeout" \
    HAYSTACK_POLL_INTERVAL="$poll_interval" \
    HAYSTACK_PR_STATUS_CHECK="${TEST_HAYSTACK_PR_STATUS_CHECK:-0}" \
    MOCK_CALL_LOG="$CALL_LOG" \
    MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
    MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
    PATH="$MOCK_BIN:$PATH" \
      bash "$HAYSTACK_REVIEWER" "123" "owner" "repo" >/dev/null 2>/dev/null
    echo $?
    set -e
  fi
}

# ---------------------------------------------------------------------------
# Area 1: status=pending triggers poll-retry loop
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 1: status=pending poll-retry loop ==="

# Test 1.1: single pending then completed — script retries and returns clean.
# Response sequence: pending, then completed with no findings.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 30 1)
calls=$(_call_count)

run_test "pending_then_complete_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "pending_then_complete_retry_count" "2" "$calls"

# Test 1.2: two pending responses then completed — script retries twice.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"status":"pending"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 60 1)
calls=$(_call_count)

run_test "two_pending_then_complete_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "two_pending_then_complete_retry_count" "3" "$calls"

# Test 1.3: pending then completed with a blocking finding — RESULT=needs_fixes.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Logic error","summary":"Null dereference","detail":""}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 30 1)

run_test "pending_then_blocking_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "pending_then_blocking_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

# ---------------------------------------------------------------------------
# Area 2: pending_timeout — budget exhausted while status is still pending
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 2: pending_timeout exit ==="

# Test 2.1: all responses are pending — budget exhausted; REASON=pending_timeout.
# Use timeout=2, poll_interval=1 so the loop gets 2 iterations max.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"status":"pending"}
{"status":"pending"}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 2 1)

run_test "all_pending_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "all_pending_reason" "REASON=pending_timeout" "$(echo "$output" | grep '^REASON=')"
run_test "all_pending_blocking_count" "BLOCKING_COUNT=0" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

# Test 2.2: pending_timeout exit code is 2.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}'
_reset_mocks
_install_haystack_mock

rm -f "$_REVIEWER_EXIT_FILE"
_run_reviewer 1 1 >/dev/null
ec=$(cat "$_REVIEWER_EXIT_FILE")
run_test "pending_timeout_exit_code" "2" "$ec"

# ---------------------------------------------------------------------------
# Area 3: REASON values are distinct
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 3: distinct REASON values ==="

# Test 3.1: CLI not installed → REASON=unavailable, exit 3.
# Strategy: install a mock haystack that exits non-zero (simulating auth failure
# or CLI not found — the availability check in haystack-reviewer.sh runs
# `command -v haystack`, which will find the mock, but then the first triage
# call exits non-zero, triggering the UNAVAILABLE path).
# To precisely test the "command -v" unavailability path, we need PATH to have
# no haystack binary at all. We do this by using a private path that contains
# only a jq binary (haystack-reviewer.sh checks for jq separately).
_ISOLATED_BIN="$(mktemp -d)"
# Copy (or link) jq into the isolated bin so jq checks pass.
if command -v jq >/dev/null 2>&1; then
  JQ_PATH="$(command -v jq)"
  cp "$JQ_PATH" "$_ISOLATED_BIN/jq"
fi
# bash itself must be resolvable; we expose only the full PATH minus any haystack.
# Use the system PATH but exclude the directory containing the real haystack.
_SAFE_PATH="$(echo "$PATH" | tr ':' '\n' | grep -v "$(dirname "$(command -v haystack 2>/dev/null || true)")" | tr '\n' ':' | sed 's/:$//')"
_SAFE_PATH="$_ISOLATED_BIN:$_SAFE_PATH"

set +e
output=$(HAYSTACK_REVIEWER_TIMEOUT=5 HAYSTACK_POLL_INTERVAL=1 \
  MOCK_CALL_LOG="$CALL_LOG" MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$_SAFE_PATH" \
  bash "$HAYSTACK_REVIEWER" "123" "owner" "repo" 2>/dev/null)
ec=$?
set -e
rm -rf "$_ISOLATED_BIN"

run_test "cli_not_installed_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "cli_not_installed_reason" "REASON=unavailable" "$(echo "$output" | grep '^REASON=')"
run_test "cli_not_installed_exit_code" "3" "$ec"

# Reinstall mock for subsequent tests.
_install_haystack_mock

# Test 3.2: status=none → REASON=unavailable (permanent — no analysis submitted).
MOCK_HAYSTACK_OUTPUTS='{"status":"none"}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "status_none_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "status_none_reason" "REASON=unavailable" "$(echo "$output" | grep '^REASON=')"

# Test 3.3: pending_timeout has REASON=pending_timeout (not unavailable).
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 1 1)

run_test "pending_timeout_reason_distinct" "REASON=pending_timeout" "$(echo "$output" | grep '^REASON=')"

# ---------------------------------------------------------------------------
# Area 4: status=none is still UNAVAILABLE (permanent — not a retry candidate)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 4: status=none is UNAVAILABLE (no retry) ==="

MOCK_HAYSTACK_OUTPUTS='{"status":"none"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
calls=$(_call_count)

run_test "status_none_no_retry_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "status_none_no_retry_reason" "REASON=unavailable" "$(echo "$output" | grep '^REASON=')"
# Script must exit after the first call (no retry for none).
run_test "status_none_only_one_call" "1" "$calls"

# ---------------------------------------------------------------------------
# Area 5: completed analysis (no status field or non-pending status) — no retry
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5: completed analysis proceeds without retry ==="

# Test 5.1: no status field — treated as completed, findings parsed.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
calls=$(_call_count)

run_test "no_status_field_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "no_status_field_single_call" "1" "$calls"

# Test 5.2: completed with advisory finding only — RESULT=clean, SUGGESTION_COUNT=1.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"Nitpick","detail":""}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)

run_test "advisory_only_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "advisory_only_suggestion_count" "SUGGESTION_COUNT=1" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "advisory_only_blocking_zero" "BLOCKING_COUNT=0" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

# ---------------------------------------------------------------------------
# Area 6: HAYSTACK_POLL_INTERVAL controls retry cadence (env var)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6: HAYSTACK_POLL_INTERVAL env var ==="

# Test 6.1: HAYSTACK_POLL_INTERVAL=0 is rejected (must be >= 1).
set +e
output=$(HAYSTACK_REVIEWER_TIMEOUT=10 HAYSTACK_POLL_INTERVAL=0 \
  MOCK_CALL_LOG="$CALL_LOG" MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$HAYSTACK_REVIEWER" "123" "owner" "repo" 2>&1)
ec=$?
set -e

run_test "poll_interval_zero_exit_code" "3" "$ec"
# Error message should appear in stderr (captured via 2>&1 here).
if echo "$output" | grep -q "HAYSTACK_POLL_INTERVAL"; then
  run_test "poll_interval_zero_error_message" "yes" "yes"
else
  run_test "poll_interval_zero_error_message" "yes" "no"
fi

# Test 6.2: custom HAYSTACK_POLL_INTERVAL is respected — poll once at pending,
# then complete. With poll_interval=1 the script should succeed within budget.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 30 1)
calls=$(_call_count)

run_test "custom_poll_interval_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "custom_poll_interval_call_count" "2" "$calls"

# ---------------------------------------------------------------------------
# Area 7: argument validation still works after refactor
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 7: argument validation ==="

_reset_mocks
_install_haystack_mock

# Test 7.1: missing arguments → exit 3.
set +e
MOCK_CALL_LOG="$CALL_LOG" MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$HAYSTACK_REVIEWER" 2>/dev/null
ec=$?
set -e
run_test "missing_args_exit_code" "3" "$ec"

# Test 7.2: invalid PR number → exit 3.
set +e
MOCK_CALL_LOG="$CALL_LOG" MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$HAYSTACK_REVIEWER" "abc" "owner" "repo" 2>/dev/null
ec=$?
set -e
run_test "invalid_pr_number_exit_code" "3" "$ec"

# Test 7.3: zero PR number → exit 3.
set +e
MOCK_CALL_LOG="$CALL_LOG" MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$HAYSTACK_REVIEWER" "0" "owner" "repo" 2>/dev/null
ec=$?
set -e
run_test "zero_pr_number_exit_code" "3" "$ec"

# ---------------------------------------------------------------------------
# Area 8: non-zero exit + valid JSON recovery (issue #800)
#
# Some versions of the haystack CLI return a non-zero exit code even when
# stdout contains a valid completed analysis or a status=pending response.
# The fix (issue #800) inspects stdout before treating a non-zero exit as
# UNAVAILABLE.  This area exercises each sub-case of the recovery logic.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 8: non-zero exit + valid JSON recovery (issue #800) ==="

# Helper: _install_haystack_mock_with_exits installs the mock using
# MOCK_HAYSTACK_OUTPUTS (JSON lines) and MOCK_HAYSTACK_EXITS (exit code lines).
_install_mock_with_exits() {
  _reset_mocks
  # EXIT_SEQ_FILE was written by _reset_mocks via MOCK_HAYSTACK_EXITS.
  _install_haystack_mock
}

# Test 8.1: non-zero exit (1) + valid completed JSON with no findings
# → RESULT=clean, exit 0 (not UNAVAILABLE).
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
MOCK_HAYSTACK_EXITS='1'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_completed_json_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_completed_json_exit_code" "0" "$ec"
run_test "nonzero_exit_completed_json_blocking_zero" "BLOCKING_COUNT=0" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

# Test 8.2: non-zero exit (1) + valid completed JSON WITH blocking finding
# → RESULT=needs_fixes, exit 1 (not UNAVAILABLE).
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Logic error","summary":"Null dereference","detail":""}]}'
MOCK_HAYSTACK_EXITS='1'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_blocking_finding_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_blocking_finding_exit_code" "1" "$ec"
run_test "nonzero_exit_blocking_finding_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

# Test 8.3: non-zero exit (1) + status=pending JSON
# → poll-retry (not UNAVAILABLE); second call returns completed JSON.
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
MOCK_HAYSTACK_EXITS='1
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_pending_retries" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_pending_call_count" "2" "$calls"
run_test "nonzero_exit_pending_exit_code" "0" "$ec"

# Test 8.4: non-zero exit (1) + status=none JSON
# → UNAVAILABLE (permanent — no analysis submitted), exit 3.
MOCK_HAYSTACK_OUTPUTS='{"status":"none"}'
MOCK_HAYSTACK_EXITS='1'
_install_mock_with_exits

output=$(_run_reviewer 10 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_status_none_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_status_none_reason" "REASON=unavailable" "$(echo "$output" | grep '^REASON=')"
run_test "nonzero_exit_status_none_exit_code" "3" "$ec"

# Test 8.5: non-zero exit (1) + EMPTY stdout
# → UNAVAILABLE (genuinely unavailable), exit 3.
MOCK_HAYSTACK_OUTPUTS=''
MOCK_HAYSTACK_EXITS='1'
_install_mock_with_exits

output=$(_run_reviewer 10 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_empty_stdout_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_empty_stdout_reason" "REASON=unavailable" "$(echo "$output" | grep '^REASON=')"
run_test "nonzero_exit_empty_stdout_exit_code" "3" "$ec"

# Test 8.6: non-zero exit (1) + INVALID JSON stdout
# → UNAVAILABLE (genuinely unavailable), exit 3.
MOCK_HAYSTACK_OUTPUTS='this is not JSON at all'
MOCK_HAYSTACK_EXITS='1'
_install_mock_with_exits

output=$(_run_reviewer 10 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_invalid_json_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_invalid_json_reason" "REASON=unavailable" "$(echo "$output" | grep '^REASON=')"
run_test "nonzero_exit_invalid_json_exit_code" "3" "$ec"

# Test 8.7: zero exit + completed JSON (existing behaviour unchanged)
# → RESULT=clean, exit 0.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "zero_exit_completed_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "zero_exit_completed_exit_code" "0" "$ec"

# ---------------------------------------------------------------------------
# Area 9: status=error / incomplete-synthesis must never yield clean
#         (issue #800 fix round 2 — Batch 71 false-clean regression)
#
# Empirical signal (confirmed 2026-06-02): a genuinely completed analysis has
# NO "status" field in its JSON payload (.status // empty returns "").
# Any non-empty, non-"none" status value (including "error") means the analysis
# is still synthesizing and must be treated as transient — poll-retry, NOT clean.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 9: status=error / incomplete synthesis must never yield clean ==="

# Test 9.1: status=error then completed-with-blocking-finding on retry
# → RESULT=needs_fixes, BLOCKING_COUNT=1.  Confirms error is transient, not terminal.
MOCK_HAYSTACK_OUTPUTS='{"status":"error"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Logic error","summary":"Null dereference","detail":""}]}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "status_error_then_findings_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "status_error_then_findings_blocking_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "status_error_then_findings_exit_code" "1" "$ec"
run_test "status_error_then_findings_retried" "2" "$calls"

# Test 9.2: status=error persisting until timeout
# → RESULT=skipped REASON=pending_timeout (NOT clean, NOT 0-finding clean).
MOCK_HAYSTACK_OUTPUTS='{"status":"error"}
{"status":"error"}
{"status":"error"}'
MOCK_HAYSTACK_EXITS='0
0
0'
_install_mock_with_exits

output=$(_run_reviewer 2 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "status_error_timeout_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "status_error_timeout_reason" "REASON=pending_timeout" "$(echo "$output" | grep '^REASON=')"
run_test "status_error_timeout_exit_code" "2" "$ec"
run_test "status_error_timeout_blocking_zero" "BLOCKING_COUNT=0" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

# Test 9.3: completed-with-0-findings → clean.
# This is the ONLY path that may yield RESULT=clean (no status field + empty findings).
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "completed_zero_findings_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "completed_zero_findings_exit_code" "0" "$ec"
run_test "completed_zero_findings_single_call" "1" "$calls"

# Test 9.4: status=error then completed-with-0-findings → clean.
# Confirms that after transient error, a genuine 0-finding result IS clean.
MOCK_HAYSTACK_OUTPUTS='{"status":"error"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "status_error_then_zero_findings_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "status_error_then_zero_findings_exit_code" "0" "$ec"
run_test "status_error_then_zero_findings_retried" "2" "$calls"

# Test 9.5: non-zero exit + status=error then completed-with-blocking-finding
# → RESULT=needs_fixes (non-zero exit + transient status → still retries).
MOCK_HAYSTACK_OUTPUTS='{"status":"error"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Logic error","summary":"Bad logic","detail":""}]}'
MOCK_HAYSTACK_EXITS='1
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "nonzero_exit_status_error_then_findings_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "nonzero_exit_status_error_then_findings_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "nonzero_exit_status_error_then_findings_retried" "2" "$calls"

# ---------------------------------------------------------------------------
# Area 10: pr-status policy verdict is surfaced as advisory metadata (#818)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 10: pr-status policy verdict metadata ==="

TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisStatus":"ready","analysisVerdict":"needs-review","needsHumanReview":true,"haystackRating":5,"hasReviewer":false}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_needs_review_result_stays_clean" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_needs_review_required" "POLICY_REVIEW_REQUIRED=1" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_needs_review_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_needs_review_suggestion_count" "SUGGESTION_COUNT=1" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_needs_review_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "────────────────────────────────────────────────────────────"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "────────────────────────────────────────────────────────────"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
