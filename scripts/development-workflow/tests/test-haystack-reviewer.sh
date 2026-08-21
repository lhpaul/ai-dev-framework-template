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
#  10. current-head file-limit skips terminate promptly and fail closed on
#      ambiguous, stale, incomplete, or non-file-limit evidence
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
# The active checkout is the source under test. In a worktree, --show-toplevel
# intentionally resolves to that worktree instead of the main checkout so the
# harness exercises the branch's implementation.
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

HAYSTACK_REVIEWER="$REPO_ROOT/scripts/development-workflow/haystack-reviewer.sh"

if [ ! -f "$HAYSTACK_REVIEWER" ]; then
  echo "ERROR: haystack-reviewer.sh not found at $HAYSTACK_REVIEWER" >&2
  exit 1
fi

REAL_JQ="$(command -v jq)"

# ---------------------------------------------------------------------------
# Temp dir for mock binaries and state files.
# ---------------------------------------------------------------------------
MOCK_BIN="$(mktemp -d)"
NO_TIMEOUT_BIN="$(mktemp -d)"
CALL_LOG="$(mktemp)"
RESPONSE_SEQ_FILE="$(mktemp)"
EXIT_SEQ_FILE="$(mktemp)"
SLEEP_SEQ_FILE="$(mktemp)"
_REVIEWER_OUTPUT_FILE="$(mktemp)"
_REVIEWER_EXIT_FILE="$(mktemp)"

_harness_exit() {
  local status=$?
  rm -rf "$MOCK_BIN" "$NO_TIMEOUT_BIN"
  rm -f "$CALL_LOG" "$RESPONSE_SEQ_FILE" "$EXIT_SEQ_FILE" "$SLEEP_SEQ_FILE" \
        "${_REVIEWER_OUTPUT_FILE:-}" "${_REVIEWER_EXIT_FILE:-}"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

for _cmd in bash env jq mktemp date cat rm wc sed tr sleep; do
  _cmd_path="$(command -v "$_cmd")"
  ln -sf "$_cmd_path" "$NO_TIMEOUT_BIN/$_cmd"
done
unset _cmd _cmd_path

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
  rm -f "$SLEEP_SEQ_FILE"
  SLEEP_SEQ_FILE="$(mktemp)"
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
  # Optional per-call sleep durations, used to exercise background-process
  # timeout cleanup paths without calling the real Haystack CLI.
  if [ -n "${MOCK_HAYSTACK_SLEEPS:-}" ]; then
    printf '%s\n' "$MOCK_HAYSTACK_SLEEPS" > "$SLEEP_SEQ_FILE"
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
if [ -n "${MOCK_SLEEP_SEQ:-}" ] && [ -f "$MOCK_SLEEP_SEQ" ]; then
  total_sleeps=$(wc -l < "$MOCK_SLEEP_SEQ" | tr -d ' ')
  if [ "$total_sleeps" -gt 0 ]; then
    if [ "$call_num" -le "$total_sleeps" ]; then
      sleep_line_num="$call_num"
    else
      sleep_line_num="$total_sleeps"
    fi
    mock_sleep=$(sed -n "${sleep_line_num}p" "$MOCK_SLEEP_SEQ" | tr -d '[:space:]')
    case "$mock_sleep" in
      ''|*[!0-9]*) mock_sleep=0 ;;
    esac
    [ "$mock_sleep" -gt 0 ] && sleep "$mock_sleep"
  fi
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
  _install_gh_check_run_mock
}

_install_gh_check_run_mock() {
  cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"repos/owner/repo/pulls/123"*"--jq .head.sha"*)
    printf '%s\n' "${MOCK_GH_HEAD_SHA:-abc123sha}"
    exit 0
    ;;
  *"repos/owner/repo/commits/"*"/check-runs"*)
    if [ "${MOCK_GH_CHECK_RUNS_FAIL:-0}" = "1" ]; then
      exit 1
    fi
    _mock_haystack_calls=0
    if [ -n "${MOCK_CALL_LOG:-}" ] && [ -f "$MOCK_CALL_LOG" ]; then
      _mock_haystack_calls=$(wc -l < "$MOCK_CALL_LOG" | tr -d ' ')
    fi
    case "$*" in
      *"repos/owner/repo/commits/${MOCK_GH_CHECK_RUNS_HEAD_SHA:-${MOCK_GH_HEAD_SHA:-abc123sha}}/check-runs"*)
        ;;
      *)
        printf '{"check_runs":[]}\n'
        exit 0
        ;;
    esac
    if [ "$_mock_haystack_calls" -gt 0 ] && [ -n "${MOCK_GH_CHECK_RUNS_AFTER_TRIAGE:-}" ]; then
      printf '%s\n' "$MOCK_GH_CHECK_RUNS_AFTER_TRIAGE"
    elif [ -n "${MOCK_GH_CHECK_RUNS:-}" ]; then
      printf '%s\n' "$MOCK_GH_CHECK_RUNS"
    else
      printf '{"check_runs":[]}\n'
    fi
    exit 0
    ;;
  *)
    printf 'unexpected gh invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
MOCK_GH
  chmod +x "$MOCK_BIN/gh"
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
  local reviewer_path="${TEST_REVIEWER_PATH:-$MOCK_BIN:$PATH}"
  rm -f "$_REVIEWER_OUTPUT_FILE" "$_REVIEWER_EXIT_FILE"
  set +e
  HAYSTACK_REVIEWER_TIMEOUT="$timeout" \
  HAYSTACK_POLL_INTERVAL="$poll_interval" \
  HAYSTACK_PR_STATUS_CHECK="${TEST_HAYSTACK_PR_STATUS_CHECK:-0}" \
  MOCK_CALL_LOG="$CALL_LOG" \
  MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  MOCK_SLEEP_SEQ="$SLEEP_SEQ_FILE" \
  PATH="$reviewer_path" \
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
_HAYSTACK_BIN_DIR=""
if _HAYSTACK_PATH="$(command -v haystack 2>/dev/null)"; then
  _HAYSTACK_BIN_DIR="$(dirname "$_HAYSTACK_PATH")"
fi
if [ -n "$_HAYSTACK_BIN_DIR" ]; then
  _SAFE_PATH="$(echo "$PATH" | tr ':' '\n' | grep -v -F -x "$_HAYSTACK_BIN_DIR" | tr '\n' ':' | sed 's/:$//')"
else
  _SAFE_PATH="$PATH"
fi
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

# Test 5.3: Rules violation mirror finding stays advisory-only.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"Mirror drift needs review","detail":"Claude/Cursor workflow bodies differ; front matter differs only"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)

run_test "rules_violation_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "rules_violation_suggestion_count" "SUGGESTION_COUNT=1" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "rules_violation_blocking_zero" "BLOCKING_COUNT=0" "$(echo "$output" | grep '^BLOCKING_COUNT=')"

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

# Test 7.4: non-numeric timeout exits before pr-status arithmetic.
set +e
MOCK_CALL_LOG="$CALL_LOG" MOCK_RESPONSE_SEQ="$RESPONSE_SEQ_FILE" \
  MOCK_EXIT_SEQ="$EXIT_SEQ_FILE" \
  PATH="$MOCK_BIN:$PATH" \
  bash "$HAYSTACK_REVIEWER" "123" "owner" "repo" --timeout "abc" 2>/dev/null
ec=$?
set -e
run_test "non_numeric_timeout_exit_code" "3" "$ec"

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
run_test "policy_needs_review_disposition" "POLICY_DISPOSITION=policy-human-review" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_needs_review_analysis_status" "POLICY_ANALYSIS_STATUS=ready" "$(echo "$output" | grep '^POLICY_ANALYSIS_STATUS=')"
run_test "policy_needs_review_bucket" "POLICY_BUCKET=needs-assignment" "$(echo "$output" | grep '^POLICY_BUCKET=')"
run_test "policy_needs_review_rating" "POLICY_RATING=5" "$(echo "$output" | grep '^POLICY_RATING=')"
run_test "policy_needs_review_has_reviewer" "POLICY_HAS_REVIEWER=false" "$(echo "$output" | grep '^POLICY_HAS_REVIEWER=')"
run_test "policy_needs_review_needs_human" "POLICY_NEEDS_HUMAN=true" "$(echo "$output" | grep '^POLICY_NEEDS_HUMAN=')"
run_test "policy_needs_review_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_needs_review_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_needs_review_comment_count" "COMMENT_COUNT=0" "$(echo "$output" | grep '^COMMENT_COUNT=')"
run_test "policy_needs_review_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.2: invalid pr-status JSON does not block or emit policy metadata.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
not-json'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_invalid_json_result_stays_clean" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_invalid_json_unavailable" "POLICY_STATUS_AVAILABLE=0" "$(echo "$output" | grep '^POLICY_STATUS_AVAILABLE=')"
run_test "policy_invalid_json_not_required" "POLICY_REVIEW_REQUIRED=0" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_invalid_json_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_invalid_json_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.3: non-zero pr-status exit does not hide clean triage findings.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"needs-review","needsHumanReview":true}}'
MOCK_HAYSTACK_EXITS='0
1'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_nonzero_exit_result_stays_clean" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_nonzero_exit_unavailable" "POLICY_STATUS_AVAILABLE=0" "$(echo "$output" | grep '^POLICY_STATUS_AVAILABLE=')"
run_test "policy_nonzero_exit_not_required" "POLICY_REVIEW_REQUIRED=0" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_nonzero_exit_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_nonzero_exit_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.4: policy field parse failure fails closed.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisStatus":"ready","analysisVerdict":"needs-review","needsHumanReview":true}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits
cat > "$MOCK_BIN/jq" <<MOCK_JQ
#!/usr/bin/env bash
for arg in "\$@"; do
  case "\$arg" in
    *analysisStatus*) exit 42 ;;
  esac
done
exec "$REAL_JQ" "\$@"
MOCK_JQ
chmod +x "$MOCK_BIN/jq"

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_parse_failure_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_parse_failure_reason" "REASON=policy_status_parse_failed" "$(echo "$output" | grep '^REASON=')"
run_test "policy_parse_failure_blocking_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "policy_parse_failure_comment_count" "COMMENT_COUNT=1" "$(echo "$output" | grep '^COMMENT_COUNT=')"
run_test "policy_parse_failure_exit_code" "1" "$ec"
rm -f "$MOCK_BIN/jq"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.5: disabled pr-status checks do not call policy status.
TEST_HAYSTACK_PR_STATUS_CHECK=0
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"needs-review","needsHumanReview":true}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_disabled_result_stays_clean" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_disabled_single_triage_call" "1" "$calls"
run_test "policy_disabled_unavailable" "POLICY_STATUS_AVAILABLE=0" "$(echo "$output" | grep '^POLICY_STATUS_AVAILABLE=')"
run_test "policy_disabled_not_required" "POLICY_REVIEW_REQUIRED=0" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_disabled_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_disabled_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.6: needsHumanReview=true triggers policy review even if verdict passes.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"pass","needsHumanReview":true}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_needs_human_pass_required" "POLICY_REVIEW_REQUIRED=1" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_needs_human_pass_disposition" "POLICY_DISPOSITION=policy-human-review" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_needs_human_pass_needs_human" "POLICY_NEEDS_HUMAN=true" "$(echo "$output" | grep '^POLICY_NEEDS_HUMAN=')"
run_test "policy_needs_human_pass_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_needs_human_pass_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_needs_human_pass_comment_count" "COMMENT_COUNT=0" "$(echo "$output" | grep '^COMMENT_COUNT=')"
run_test "policy_needs_human_pass_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.7: analysisVerdict=needs-review triggers even without needsHumanReview.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"created-by-you","inputs":{"analysisVerdict":"needs-review","needsHumanReview":false}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_verdict_only_required" "POLICY_REVIEW_REQUIRED=1" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_verdict_only_disposition" "POLICY_DISPOSITION=policy-human-review" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_verdict_only_needs_human" "POLICY_NEEDS_HUMAN=false" "$(echo "$output" | grep '^POLICY_NEEDS_HUMAN=')"
run_test "policy_verdict_only_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_verdict_only_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_verdict_only_comment_count" "COMMENT_COUNT=0" "$(echo "$output" | grep '^COMMENT_COUNT=')"
run_test "policy_verdict_only_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.8: other non-pass verdicts also trigger policy review.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"needs-changes","needsHumanReview":false}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_needs_changes_required" "POLICY_REVIEW_REQUIRED=1" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_needs_changes_disposition" "POLICY_DISPOSITION=policy-human-review" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_needs_changes_verdict" "POLICY_VERDICT=needs-changes" "$(echo "$output" | grep '^POLICY_VERDICT=')"
run_test "policy_needs_changes_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_needs_changes_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_needs_changes_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.9: clean policy verdicts remain non-advisory.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"created-by-you","inputs":{"analysisVerdict":"pass","needsHumanReview":false}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_pass_not_required" "POLICY_REVIEW_REQUIRED=0" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_pass_disposition" "POLICY_DISPOSITION=good-to-merge" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_pass_needs_human" "POLICY_NEEDS_HUMAN=false" "$(echo "$output" | grep '^POLICY_NEEDS_HUMAN=')"
run_test "policy_pass_suggestion_count" "SUGGESTION_COUNT=0" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_pass_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.10: advisory findings with clean policy status are identified separately.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"Nitpick","detail":""}]}
{"bucket":"good-to-merge","inputs":{"analysisVerdict":"pass","needsHumanReview":false,"haystackRating":4,"hasReviewer":true}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_advisory_result_stays_clean" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_advisory_disposition" "POLICY_DISPOSITION=advisory-only" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_advisory_suggestion_count" "SUGGESTION_COUNT=1" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "policy_advisory_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.11: blocking findings override policy metadata disposition.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Logic error","summary":"Bad logic","detail":""}]}
{"bucket":"needs-assignment","inputs":{"analysisStatus":"ready","analysisVerdict":"needs-review","needsHumanReview":true,"haystackRating":2,"hasReviewer":false}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_blocking_result_needs_fixes" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_blocking_disposition" "POLICY_DISPOSITION=blocking" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_blocking_blocking_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "policy_blocking_exit_code" "1" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.12: legacy top-level pr-status keys are parsed as policy metadata.
TEST_HAYSTACK_PR_STATUS_CHECK=1
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","analysisVerdict":"needs-review","needsHumanReview":true,"haystackRating":4,"hasReviewer":false}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_top_level_required" "POLICY_REVIEW_REQUIRED=1" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_top_level_disposition" "POLICY_DISPOSITION=policy-human-review" "$(echo "$output" | grep '^POLICY_DISPOSITION=')"
run_test "policy_top_level_bucket" "POLICY_BUCKET=needs-assignment" "$(echo "$output" | grep '^POLICY_BUCKET=')"
run_test "policy_top_level_verdict" "POLICY_VERDICT=needs-review" "$(echo "$output" | grep '^POLICY_VERDICT=')"
run_test "policy_top_level_rating" "POLICY_RATING=4" "$(echo "$output" | grep '^POLICY_RATING=')"
run_test "policy_top_level_has_reviewer" "POLICY_HAS_REVIEWER=false" "$(echo "$output" | grep '^POLICY_HAS_REVIEWER=')"
run_test "policy_top_level_needs_human" "POLICY_NEEDS_HUMAN=true" "$(echo "$output" | grep '^POLICY_NEEDS_HUMAN=')"
run_test "policy_top_level_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_top_level_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK

# Test 10.13: no-timeout fallback still reads pr-status policy metadata.
TEST_HAYSTACK_PR_STATUS_CHECK=1
TEST_REVIEWER_PATH="$MOCK_BIN:$NO_TIMEOUT_BIN"
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"needs-review","needsHumanReview":true,"haystackRating":5,"hasReviewer":false}}'
MOCK_HAYSTACK_EXITS='0
0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_no_timeout_fallback_calls_triage_and_status" "2" "$calls"
run_test "policy_no_timeout_fallback_available" "POLICY_STATUS_AVAILABLE=1" "$(echo "$output" | grep '^POLICY_STATUS_AVAILABLE=')"
run_test "policy_no_timeout_fallback_required" "POLICY_REVIEW_REQUIRED=1" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_no_timeout_fallback_display" "DISPLAY_RESULT=needs-review: policy" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "policy_no_timeout_fallback_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK TEST_REVIEWER_PATH

# Test 10.14: no-timeout fallback terminates a hung pr-status subprocess.
#
# Budget sizing (issue #1537). This is the only test in this suite that
# asserts a SUCCESS outcome while deliberately starving a subprocess. Every
# other short-budget test here expects pending_timeout, so it reaches its
# expectation whether or not the budget is tight; this one does not.
#
# It previously ran with HAYSTACK_REVIEWER_TIMEOUT=3. haystack-reviewer.sh
# derives the per-call triage timeout as half the remaining budget, so the
# first (fast) triage call got a 1-second allowance, polled at 1-second
# granularity. Forking the mock CLI plus jq exceeds that under CPU
# contention: the triage call was killed, the 3s budget then expired, and all
# five assertions below failed together with calls=0 and REASON=
# pending_timeout. That is the 205-passed/5-failed signature reported on the
# issue — green in isolation, red when run alongside other work, which is
# precisely the failure mode a batched CI run would introduce.
#
# Reproduced deterministically at load average ~42 on an 11-core machine, and
# fixed by widening the absolute margin while preserving the ratio the test
# depends on. The budget must stay BELOW the hung call's duration (otherwise
# the subprocess is never terminated and the test asserts nothing) and far
# ABOVE the cost of forking the mock (otherwise an unrelated slow moment
# fails it). 12s against a 30s hang satisfies both, giving the first triage
# call 6s where it had 1s.
TEST_HAYSTACK_PR_STATUS_CHECK=1
TEST_REVIEWER_PATH="$MOCK_BIN:$NO_TIMEOUT_BIN"
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"needs-review","needsHumanReview":true}}'
MOCK_HAYSTACK_EXITS='0
0'
MOCK_HAYSTACK_SLEEPS='0
30'
_install_mock_with_exits

output=$(_run_reviewer 12 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "policy_no_timeout_hung_status_called" "2" "$calls"
run_test "policy_no_timeout_hung_status_unavailable" "POLICY_STATUS_AVAILABLE=0" "$(echo "$output" | grep '^POLICY_STATUS_AVAILABLE=')"
run_test "policy_no_timeout_hung_status_not_required" "POLICY_REVIEW_REQUIRED=0" "$(echo "$output" | grep '^POLICY_REVIEW_REQUIRED=')"
run_test "policy_no_timeout_hung_status_result_clean" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_no_timeout_hung_status_exit_code" "0" "$ec"
unset TEST_HAYSTACK_PR_STATUS_CHECK TEST_REVIEWER_PATH MOCK_HAYSTACK_SLEEPS

# ---------------------------------------------------------------------------
# Area 11: triage HTTP 401/403 auth errors fail fast (#1035)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 11: triage HTTP 401/403 auth errors ==="

MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"error","message":"HTTP 403"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "http_403_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "http_403_reason" "REASON=forbidden" "$(echo "$output" | grep '^REASON=')"
run_test "http_403_exit_code" "3" "$ec"
run_test "http_403_single_call" "1" "$calls"

MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"error","message":"HTTP 401"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
calls=$(_call_count)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "http_401_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "http_401_reason" "REASON=unauthorized" "$(echo "$output" | grep '^REASON=')"
run_test "http_401_exit_code" "3" "$ec"
run_test "http_401_single_call" "1" "$calls"

# ---------------------------------------------------------------------------
# Area 12: GitHub App check-run fallback
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 12: GitHub App check-run fallback ==="

_check_summary_blocking="$(cat <<'SUMMARY_BLOCKING'
**Verdict:** `has-issues`
**Rating:** `3/5`
**Findings:** 3

**[Logic error]** - Sticky fingerprint mismatch can delay escalation.
**[Rules violation]** - Config invariants are not validated.
**[Weak test coverage]** - Remediation branch selection lacks coverage.
SUMMARY_BLOCKING
)"
MOCK_GH_CHECK_RUNS="$(
  jq -n --arg summary "$_check_summary_blocking" '{
    check_runs: [
      {
        name: "Haystack / Review",
        status: "completed",
        conclusion: "failure",
        details_url: "https://haystackeditor.com/review/owner/repo/123",
        started_at: "2026-07-12T15:26:22Z",
        output: {title: "Haystack found 3 issues", summary: $summary}
      }
    ]
  }'
)"
export MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits
_install_gh_check_run_mock

output=$(_run_reviewer 1 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "check_run_fallback_blocking_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "check_run_fallback_blocking_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "check_run_fallback_suggestion_count" "SUGGESTION_COUNT=2" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "check_run_fallback_conclusion" "CHECK_RUN_CONCLUSION=failure" "$(echo "$output" | grep '^CHECK_RUN_CONCLUSION=')"
run_test "check_run_fallback_blocking_exit_code" "1" "$ec"

_check_summary_advisory="$(cat <<'SUMMARY_ADVISORY'
**Verdict:** `has-issues`
**Rating:** `4/5`
**Findings:** 2

- **[Rules violation]** - Changelog placement needs review.
- **[Weak test coverage]** - Add focused coverage.
SUMMARY_ADVISORY
)"
MOCK_GH_CHECK_RUNS="$(
  jq -n --arg summary "$_check_summary_advisory" '{
    check_runs: [
      {
        name: "Haystack / Review",
        status: "completed",
        conclusion: "failure",
        details_url: "https://haystackeditor.com/review/owner/repo/123",
        started_at: "2026-07-12T15:26:22Z",
        output: {title: "Haystack found 2 issues", summary: $summary}
      }
    ]
  }'
)"
export MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits
_install_gh_check_run_mock

output=$(_run_reviewer 1 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "check_run_fallback_advisory_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "check_run_fallback_advisory_blocking_zero" "BLOCKING_COUNT=0" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "check_run_fallback_advisory_suggestions" "SUGGESTION_COUNT=2" "$(echo "$output" | grep '^SUGGESTION_COUNT=')"
run_test "check_run_fallback_advisory_exit_code" "0" "$ec"

_check_summary_custom='**Verdict:** `pass`
**Rating:** `5/5`
**Findings:** 0'
MOCK_GH_CHECK_RUNS="$(
  jq -n --arg summary "$_check_summary_custom" '[
    {
      check_runs: [
        {
          name: "Unrelated Check",
          status: "completed",
          conclusion: "failure",
          started_at: "2026-07-12T15:25:22Z"
        }
      ]
    },
    {
      check_runs: [
        {
          name: "Custom Haystack Review",
          status: "completed",
          conclusion: "success",
          details_url: "https://haystackeditor.com/review/owner/repo/123",
          started_at: "2026-07-12T15:26:22Z",
          output: {title: "Haystack passed", summary: $summary}
        }
      ]
    }
  ]'
)"
export MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits
_install_gh_check_run_mock

output=$(HAYSTACK_CHECK_NAME="Custom Haystack Review" _run_reviewer 1 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "check_run_fallback_custom_paginated_name_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "check_run_fallback_custom_paginated_name_conclusion" "CHECK_RUN_CONCLUSION=success" "$(echo "$output" | grep '^CHECK_RUN_CONCLUSION=')"
run_test "check_run_fallback_custom_paginated_name_exit_code" "0" "$ec"

MOCK_GH_CHECK_RUNS="$(
  jq -n '{
    check_runs: [
      {
        name: "Haystack / Review",
        status: "completed",
        conclusion: "failure",
        details_url: "https://haystackeditor.com/review/owner/repo/123",
        started_at: "2026-07-12T15:26:22Z",
        output: {title: "Haystack found issues", summary: "Haystack found issues but did not expose structured category output."}
      }
    ]
  }'
)"
export MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits
_install_gh_check_run_mock

output=$(_run_reviewer 1 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "check_run_fallback_unparseable_failure_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "check_run_fallback_unparseable_failure_blocking" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "check_run_fallback_unparseable_failure_exit_code" "1" "$ec"

MOCK_GH_CHECK_RUNS='not-json'
export MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits
_install_gh_check_run_mock

output=$(_run_reviewer 1 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "check_run_fallback_malformed_json_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "check_run_fallback_malformed_json_reason" "REASON=pending_timeout" "$(echo "$output" | grep '^REASON=')"
run_test "check_run_fallback_malformed_json_exit_code" "2" "$ec"

MOCK_GH_CHECK_RUNS="$(
  jq -n '{
    check_runs: [
      {
        name: "Haystack / Review",
        status: "in_progress",
        conclusion: null,
        started_at: "2026-07-12T15:26:22Z"
      }
    ]
  }'
)"
export MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits
_install_gh_check_run_mock

output=$(_run_reviewer 1 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")

run_test "check_run_fallback_pending_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "check_run_fallback_pending_reason" "REASON=pending_check_run" "$(echo "$output" | grep '^REASON=')"
run_test "check_run_fallback_pending_exit_code" "2" "$ec"

unset MOCK_GH_CHECK_RUNS _check_summary_blocking _check_summary_advisory _check_summary_custom

# ---------------------------------------------------------------------------
# Area 13: current-head Haystack analysis file-limit skip (#1311)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 13: current-head analysis file-limit skip ==="

_file_limit_check_run="$(
  jq -n '{
    check_runs: [
      {
        name: "Haystack / Review",
        status: "completed",
        conclusion: "action_required",
        details_url: "https://haystackeditor.com/review/owner/repo/123",
        started_at: "2026-07-23T14:00:00Z",
        completed_at: "2026-07-23T14:00:02Z",
        output: {
          title: "PR exceeds the Haystack analysis limit",
          summary: "This pull request has 168 changed files, which exceeds the Haystack analysis limit of 100 files."
        }
      }
    ]
  }'
)"
MOCK_GH_CHECK_RUNS="$_file_limit_check_run"
export MOCK_GH_CHECK_RUNS
unset MOCK_GH_CHECK_RUNS_AFTER_TRIAGE
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")
calls=$(_call_count)

run_test "file_limit_skip_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "file_limit_skip_reason" "REASON=analysis_skipped_file_limit" "$(echo "$output" | grep '^REASON=')"
run_test "file_limit_skip_display" "DISPLAY_RESULT=skipped (analysis file limit)" "$(echo "$output" | grep '^DISPLAY_RESULT=')"
run_test "file_limit_skip_counts" "0,0,0" "$(printf '%s,%s,%s' \
  "$(echo "$output" | grep '^BLOCKING_COUNT=' | cut -d= -f2)" \
  "$(echo "$output" | grep '^SUGGESTION_COUNT=' | cut -d= -f2)" \
  "$(echo "$output" | grep '^COMMENT_COUNT=' | cut -d= -f2)")"
run_test "file_limit_skip_metadata" "completed,action_required" "$(printf '%s,%s' \
  "$(echo "$output" | grep '^CHECK_RUN_STATUS=' | cut -d= -f2)" \
  "$(echo "$output" | grep '^CHECK_RUN_CONCLUSION=' | cut -d= -f2)")"
run_test "file_limit_skip_exit_code" "3" "$ec"
run_test "file_limit_skip_avoids_triage" "0" "$calls"

# Equivalent case, whitespace, possessive, and hyphen variants remain
# authoritative when the completed current-head check carries them.
MOCK_GH_CHECK_RUNS="$(
  jq -n '{
    check_runs: [
      {
        name: "Haystack / Review",
        status: "COMPLETED",
        conclusion: "action_required",
        started_at: "2026-07-23T14:00:00Z",
        output: {
          title: "Analysis Skipped",
          summary: "This PR is OVER   Haystack\u0027s FILE-LIMIT."
        }
      }
    ]
  }'
)"
export MOCK_GH_CHECK_RUNS
_install_mock_with_exits

output=$(_run_reviewer 30 1)
run_test "file_limit_skip_normalized_variant" "REASON=analysis_skipped_file_limit" "$(echo "$output" | grep '^REASON=')"

# Same-head reruns remain terminal and do not enter the polling loop.
MOCK_GH_CHECK_RUNS="$_file_limit_check_run"
export MOCK_GH_CHECK_RUNS
_install_mock_with_exits
output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")
calls=$(_call_count)
run_test "file_limit_skip_rerun_reason" "REASON=analysis_skipped_file_limit" "$(echo "$output" | grep '^REASON=')"
run_test "file_limit_skip_rerun_exit_code" "3" "$ec"
run_test "file_limit_skip_rerun_avoids_triage" "0" "$calls"

# A skip that appears during a transient triage call is observed before sleep
# or a second triage observation.
MOCK_GH_CHECK_RUNS="$(jq -n '{check_runs: []}')"
MOCK_GH_CHECK_RUNS_AFTER_TRIAGE="$_file_limit_check_run"
export MOCK_GH_CHECK_RUNS MOCK_GH_CHECK_RUNS_AFTER_TRIAGE
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
ec=$(cat "$_REVIEWER_EXIT_FILE")
calls=$(_call_count)
run_test "file_limit_skip_after_transient_result" "RESULT=skipped" "$(echo "$output" | grep '^RESULT=')"
run_test "file_limit_skip_after_transient_reason" "REASON=analysis_skipped_file_limit" "$(echo "$output" | grep '^REASON=')"
run_test "file_limit_skip_after_transient_exit_code" "3" "$ec"
run_test "file_limit_skip_after_transient_single_triage" "1" "$calls"

_assert_file_limit_lookalike_rejected() {
  local name="$1"
  local status="$2"
  local title="$3"
  local summary="$4"

  MOCK_GH_CHECK_RUNS="$(
    jq -n \
      --arg status "$status" \
      --arg title "$title" \
      --arg summary "$summary" \
      '{
        check_runs: [
          {
            name: "Haystack / Review",
            status: $status,
            conclusion: "action_required",
            started_at: "2026-07-23T14:00:00Z",
            output: {title: $title, summary: $summary}
          }
        ]
      }'
  )"
  export MOCK_GH_CHECK_RUNS
  unset MOCK_GH_CHECK_RUNS_AFTER_TRIAGE
  MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
  MOCK_HAYSTACK_EXITS='0'
  _install_mock_with_exits

  output=$(_run_reviewer 30 1)
  run_test "$name" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
}

_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_generic_action_required" \
  "completed" \
  "Review requires action" \
  "A reviewer must inspect this pull request."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_generic_analysis_skipped" \
  "completed" \
  "Analysis Skipped" \
  "Haystack did not analyze this pull request."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_numeric_count_only" \
  "completed" \
  "Analysis Skipped" \
  "This pull request changes 168 files."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_time_limit" \
  "completed" \
  "Analysis exceeded the time limit" \
  "Haystack analysis exceeded its time limit."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_recover_substring" \
  "completed" \
  "Recover Haystack analysis limit metadata" \
  "The reviewer recovered Haystack analysis limit metadata."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_hover_substring" \
  "completed" \
  "Hover Haystack file limit help" \
  "Hover Haystack file limit help to inspect the policy."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_discover_over_substring" \
  "completed" \
  "Discover the limit documentation" \
  "Discover the limit before changing the Haystack analysis limit."
_assert_file_limit_lookalike_rejected \
  "file_limit_rejects_incomplete_check" \
  "in_progress" \
  "PR exceeds the Haystack analysis limit" \
  "This pull request exceeds the Haystack file limit."

MOCK_GH_HEAD_SHA="current-head-sha"
MOCK_GH_CHECK_RUNS_HEAD_SHA="prior-head-sha"
MOCK_GH_CHECK_RUNS="$_file_limit_check_run"
export MOCK_GH_HEAD_SHA MOCK_GH_CHECK_RUNS_HEAD_SHA MOCK_GH_CHECK_RUNS
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
MOCK_HAYSTACK_EXITS='0'
_install_mock_with_exits

output=$(_run_reviewer 30 1)
run_test "file_limit_rejects_prior_head_check" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"

unset MOCK_GH_CHECK_RUNS MOCK_GH_CHECK_RUNS_AFTER_TRIAGE
unset MOCK_GH_HEAD_SHA MOCK_GH_CHECK_RUNS_HEAD_SHA
unset _file_limit_check_run
unset -f _assert_file_limit_lookalike_rejected

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
