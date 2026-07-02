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

for _cmd in bash env jq mktemp date cat rm wc sed tr sleep python3 dirname; do
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

_run_reviewer_with_config() {
  # Runs haystack-reviewer.sh against a temporary workflow config root without
  # setting timeout/poll env vars, so repository config values are observable.
  local config_root="$1"
  local reviewer_path="${TEST_REVIEWER_PATH:-$MOCK_BIN:$PATH}"
  rm -f "$_REVIEWER_OUTPUT_FILE" "$_REVIEWER_EXIT_FILE"
  set +e
  HAYSTACK_WORKFLOW_REPO_ROOT="$config_root" \
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

_kv_value() {
  local key="$1" output="$2"
  printf '%s\n' "$output" | sed -n "s/^${key}=//p" | head -n 1
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
# Area 5b: structured finding output
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5b: structured finding output ==="

# Test 5b.1: empty findings still emit parseable empty arrays.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"

run_test "structured_empty_advisory_array" "0" "$(printf '%s\n' "$advisory_json" | jq 'length')"
run_test "structured_empty_blocking_array" "0" "$(printf '%s\n' "$blocking_json" | jq 'length')"

# Test 5b.2: multiple advisories preserve one entry per finding and ordering.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"First advisory","detail":"One","agentFixPrompt":"Fix one"},{"category":"Rules violation","summary":"Second advisory","detail":"Two"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "structured_multi_advisory_count" "2" "$(printf '%s\n' "$advisory_json" | jq 'length')"
run_test "structured_multi_advisory_order" "First advisory|Second advisory" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].summary + "|" + .[1].summary')"
run_test "structured_multi_advisory_fix_hint" "Fix one" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].fix_hint')"

# Test 5b.3: mixed blocking/advisory payload partitions findings and counts.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Logic error","summary":"Bad logic","detail":"Fix it"},{"category":"Minor","summary":"Small note","detail":"Optional"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"

run_test "structured_mixed_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "structured_mixed_advisory_count" "1" "$(printf '%s\n' "$advisory_json" | jq 'length')"
run_test "structured_mixed_blocking_count" "1" "$(printf '%s\n' "$blocking_json" | jq 'length')"
run_test "structured_mixed_blocking_category" "Logic error" "$(printf '%s\n' "$blocking_json" | jq -r '.[0].category')"

# Test 5b.4: missing category safe-fails to blocking with __UNKNOWN__.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"summary":"No category","detail":"Missing category"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"

run_test "structured_missing_category_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "structured_missing_category_value" "__UNKNOWN__" "$(printf '%s\n' "$blocking_json" | jq -r '.[0].category')"

# Test 5b.5: unrecognized category safe-fails to blocking.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Unexpected severity","summary":"Unknown","detail":"Unknown"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"

run_test "structured_unknown_category_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "structured_unknown_category_value" "Unexpected severity" "$(printf '%s\n' "$blocking_json" | jq -r '.[0].category')"

# Test 5b.6: Major is advisory by default and blocking when opted in.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":3,"findings":[{"category":"Major","summary":"Major note","detail":"Policy"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
run_test "structured_major_default_advisory" "1" "$(printf '%s\n' "$advisory_json" | jq 'length')"

_reset_mocks
_install_haystack_mock
output=$(HAYSTACK_MAJOR_IS_BLOCKING=1 _run_reviewer 10 1)
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"
run_test "structured_major_opt_in_blocking" "1" "$(printf '%s\n' "$blocking_json" | jq 'length')"

major_config_root="$MOCK_BIN/major-config-root"
mkdir -p "$major_config_root"
cat > "$major_config_root/.ai-dev-workflow.yaml" <<'YAML'
review:
  haystack:
    major_is_blocking: true
    timeout_sec: 10
    poll_interval_sec: 1
YAML
_reset_mocks
_install_haystack_mock
output=$(_run_reviewer_with_config "$major_config_root")
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"
run_test "structured_major_config_blocking" "1" "$(printf '%s\n' "$blocking_json" | jq 'length')"

_reset_mocks
_install_haystack_mock
output=$(HAYSTACK_MAJOR_IS_BLOCKING=0 _run_reviewer_with_config "$major_config_root")
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
run_test "structured_major_env_overrides_config" "1" "$(printf '%s\n' "$advisory_json" | jq 'length')"

# Test 5b.7: optional source fields follow documented fallbacks.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"Source path","detail":"","source":{"path":"a.sh","line":7}},{"category":"Minor","summary":"Source file","detail":"","source":{"file":"b.sh","startLine":"8"}},{"category":"Minor","summary":"Top path","detail":"","path":"c.sh","line":"9"},{"category":"Minor","summary":"Top file","detail":"","file":"d.sh","startLine":10}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "structured_source_path_fallbacks" "a.sh:7|b.sh:8|c.sh:9|d.sh:10" "$(printf '%s\n' "$advisory_json" | jq -r 'map(.path + ":" + (.line | tostring)) | join("|")')"

# Test 5b.8: missing source omits optional fields without parse failure.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"No source","detail":"No source","source":null}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "structured_missing_source_no_path" "false" "$(printf '%s\n' "$advisory_json" | jq '.[0] | has("path")')"
run_test "structured_missing_source_no_line" "false" "$(printf '%s\n' "$advisory_json" | jq '.[0] | has("line")')"

# Test 5b.9: escaping remains valid JSON on one key-value output line.
# shellcheck disable=SC2016  # Fixture intentionally keeps literal $PATH in mocked Haystack output.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"Quote \" pipe | equals = slash \\ test","detail":"Line one\nLine two","agentFixPrompt":"Use $PATH && echo ok"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_line="$(printf '%s\n' "$output" | grep '^ADVISORY_FINDINGS_JSON=')"
advisory_json="${advisory_line#ADVISORY_FINDINGS_JSON=}"

run_test "structured_escaped_single_line" "1" "$(printf '%s\n' "$advisory_line" | wc -l | tr -d ' ')"
run_test "structured_escaped_detail" "Line one|Line two" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].detail | gsub("\\n"; "|")')"
# shellcheck disable=SC2016  # Expected value intentionally contains literal $PATH.
run_test "structured_escaped_fix_hint" 'Use $PATH && echo ok' "$(printf '%s\n' "$advisory_json" | jq -r '.[0].fix_hint')"

# Test 5b.10: Haystack message-only findings still populate text fields.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","message":"Message-only finding"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "structured_message_fallback_summary" "Message-only finding" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].summary')"
run_test "structured_message_fallback_detail" "Message-only finding" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].detail')"

# Test 5b.11: invalid line values are omitted.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Minor","summary":"Negative","detail":"","source":{"path":"negative.sh","line":-1}},{"category":"Minor","summary":"Zero","detail":"","source":{"path":"zero.sh","line":"0"}},{"category":"Minor","summary":"Decimal","detail":"","source":{"path":"decimal.sh","line":2.5}}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "structured_invalid_lines_omitted" "0" "$(printf '%s\n' "$advisory_json" | jq '[.[] | select(has("line"))] | length')"

# ---------------------------------------------------------------------------
# Area 5c: known false-positive catalog
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 5c: known false-positive catalog ==="

# Test 5c.1: CHANGELOG structure false positives are dispositioned.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"keep-changelog-unreleased-structure-canonical flagged CHANGELOG structure","detail":"CHANGELOG entry appears outside [Unreleased] in the diff","path":"CHANGELOG.md"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "known_fp_changelog_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_changelog_disposition" "known-false-positive" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition')"
run_test "known_fp_changelog_rule" "changelog-keep-changelog-unreleased-structure" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition_rule')"

# Test 5c.2: hotfix backport CHANGELOG false positives are dispositioned.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"hotfix backport changed CHANGELOG [Unreleased] structure","detail":"Backport diff appears to remove [Unreleased] content","source":{"path":"CHANGELOG.md","line":7}}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "known_fp_hotfix_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_hotfix_disposition" "known-false-positive" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition')"
run_test "known_fp_hotfix_rule" "hotfix-backport-changelog-structure" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition_rule')"

# Test 5c.3: stale mirror guidance false positives are dispositioned.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"Mirror guidance needs review for Claude and Cursor agent surfaces","detail":"Only tool-specific front matter and absent .cursor/skills surface differ"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "known_fp_mirror_disposition" "known-false-positive" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition')"
run_test "known_fp_mirror_rule" "agent-doc-mirror-guidance-stale-advisory" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition_rule')"

# Test 5c.4: unrelated Rules violation keeps existing advisory classification without disposition.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"Workflow contract drift","detail":"A real protocol step is missing from a mirrored command file","path":"docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "known_fp_negative_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_negative_no_disposition" "false" "$(printf '%s\n' "$advisory_json" | jq '.[0] | has("disposition")')"

# Test 5c.5: unknown categories retain safe-fail blocking behavior.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":2,"findings":[{"category":"Unexpected severity","summary":"keep-changelog-unreleased-structure-canonical flagged CHANGELOG structure","detail":"CHANGELOG entry appears outside [Unreleased]","path":"CHANGELOG.md"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"

run_test "known_fp_unknown_category_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_unknown_category_blocking" "1" "$(printf '%s\n' "$blocking_json" | jq 'length')"
run_test "known_fp_unknown_category_no_disposition" "false" "$(printf '%s\n' "$blocking_json" | jq '.[0] | has("disposition")')"

# Test 5c.6: multiple findings are classified independently.
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"keep-changelog-unreleased-structure-canonical flagged CHANGELOG structure","detail":"CHANGELOG entry appears outside [Unreleased]","path":"CHANGELOG.md"},{"category":"Minor","summary":"Unrelated note","detail":"Optional cleanup"}]}'
_reset_mocks
_install_haystack_mock

output=$(_run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"

run_test "known_fp_multi_count" "2" "$(printf '%s\n' "$advisory_json" | jq 'length')"
run_test "known_fp_multi_first_disposition" "known-false-positive" "$(printf '%s\n' "$advisory_json" | jq -r '.[0].disposition')"
run_test "known_fp_multi_second_no_disposition" "false" "$(printf '%s\n' "$advisory_json" | jq '.[1] | has("disposition")')"

# Test 5c.7: malformed catalog override preserves original classification.
bad_catalog_file="$(mktemp)"
printf '{not-json\n' > "$bad_catalog_file"
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"keep-changelog-unreleased-structure-canonical flagged CHANGELOG structure","detail":"CHANGELOG entry appears outside [Unreleased]","path":"CHANGELOG.md"}]}'
_reset_mocks
_install_haystack_mock

output=$(HAYSTACK_FALSE_POSITIVES_FILE="$bad_catalog_file" _run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
rm -f "$bad_catalog_file"

run_test "known_fp_bad_catalog_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_bad_catalog_no_disposition" "false" "$(printf '%s\n' "$advisory_json" | jq '.[0] | has("disposition")')"

# Test 5c.8: category-only catalog rules are invalid and preserve original classification.
category_only_catalog_file="$(mktemp)"
printf '[{"id":"category-only","category":"Rules violation","rationale":"Too broad"}]\n' > "$category_only_catalog_file"
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"Any rules violation","detail":"No catalog evidence predicate should match this"}]}'
_reset_mocks
_install_haystack_mock

output=$(HAYSTACK_FALSE_POSITIVES_FILE="$category_only_catalog_file" _run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
rm -f "$category_only_catalog_file"

run_test "known_fp_category_only_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_category_only_no_disposition" "false" "$(printf '%s\n' "$advisory_json" | jq '.[0] | has("disposition")')"

# Test 5c.9: invalid regex catalog rules are invalid and preserve original classification.
invalid_regex_catalog_file="$(mktemp)"
printf '[{"id":"invalid-regex","category":"Rules violation","rationale":"Bad regex","text_patterns":["["]}]\n' > "$invalid_regex_catalog_file"
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":4,"findings":[{"category":"Rules violation","summary":"Any rules violation","detail":"Invalid regex must not abort matching"}]}'
_reset_mocks
_install_haystack_mock

output=$(HAYSTACK_FALSE_POSITIVES_FILE="$invalid_regex_catalog_file" _run_reviewer 10 1)
advisory_json="$(_kv_value ADVISORY_FINDINGS_JSON "$output")"
rm -f "$invalid_regex_catalog_file"

run_test "known_fp_invalid_regex_result" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"
run_test "known_fp_invalid_regex_no_disposition" "false" "$(printf '%s\n' "$advisory_json" | jq '.[0] | has("disposition")')"

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
# Area 6b: review.haystack config defaults and stop rules
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 6b: review.haystack config defaults and stop rules ==="

config_root="$MOCK_BIN/config-root"
mkdir -p "$config_root"
cat > "$config_root/.ai-dev-workflow.yaml" <<'YAML'
review:
  haystack:
    poll_interval_sec: 1
    timeout_sec: 30
    stop_rule:
      max_triage_rounds: 1
YAML
MOCK_HAYSTACK_OUTPUTS='{"status":"pending"}
{"status":"pending"}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock
output=$(_run_reviewer_with_config "$config_root")
calls=$(_call_count)
run_test "config_max_triage_rounds_reason" "max_triage_rounds" "$(_kv_value REASON "$output")"
run_test "config_max_triage_rounds_call_count" "1" "$calls"

cat > "$config_root/.ai-dev-workflow.yaml" <<'YAML'
review:
  haystack:
    poll_interval_sec: 1
    timeout_sec: 30
    stop_rule:
      no_progress_cycles: 1
YAML
MOCK_HAYSTACK_OUTPUTS='{"status":"pending","message":"still working","findings":[]}
{"status":"pending","message":"still working","findings":[]}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock
output=$(_run_reviewer_with_config "$config_root")
calls=$(_call_count)
run_test "config_no_progress_cycles_reason" "no_progress_cycles" "$(_kv_value REASON "$output")"
run_test "config_no_progress_cycles_call_count" "2" "$calls"

cat > "$config_root/.ai-dev-workflow.yaml" <<'YAML'
review:
  haystack:
    poll_interval_sec: 1
    timeout_sec: 30
    stop_rule:
      max_triage_rounds: 3
      no_progress_cycles: 1
YAML
MOCK_HAYSTACK_OUTPUTS='{"status":"pending","message":"still working","findings":[]}
{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}'
_reset_mocks
_install_haystack_mock
output=$(_run_reviewer_with_config "$config_root")
run_test "config_completion_before_stop_rules" "RESULT=clean" "$(echo "$output" | grep '^RESULT=')"

invalid_config_root="$MOCK_BIN/invalid-config-root"
mkdir -p "$invalid_config_root"
cat > "$invalid_config_root/.ai-dev-workflow.yaml" <<'YAML'
review:
  haystack:
    poll_interval_sec: 0
YAML
_reset_mocks
_install_haystack_mock
output=$(_run_reviewer_with_config "$invalid_config_root")
run_test "config_invalid_reason" "invalid_config" "$(_kv_value REASON "$output")"
run_test "config_invalid_exit_code" "3" "$(_run_reviewer_exit_code)"

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
blocking_json="$(_kv_value BLOCKING_FINDINGS_JSON "$output")"

run_test "policy_parse_failure_result" "RESULT=needs_fixes" "$(echo "$output" | grep '^RESULT=')"
run_test "policy_parse_failure_reason" "REASON=policy_status_parse_failed" "$(echo "$output" | grep '^REASON=')"
run_test "policy_parse_failure_blocking_count" "BLOCKING_COUNT=1" "$(echo "$output" | grep '^BLOCKING_COUNT=')"
run_test "policy_parse_failure_comment_count" "COMMENT_COUNT=1" "$(echo "$output" | grep '^COMMENT_COUNT=')"
run_test "policy_parse_failure_blocking_json_count" "1" "$(printf '%s\n' "$blocking_json" | jq 'length')"
run_test "policy_parse_failure_blocking_json_category" "Policy status parse failed" "$(printf '%s\n' "$blocking_json" | jq -r '.[0].category')"
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
TEST_HAYSTACK_PR_STATUS_CHECK=1
TEST_REVIEWER_PATH="$MOCK_BIN:$NO_TIMEOUT_BIN"
MOCK_HAYSTACK_OUTPUTS='{"owner":"owner","repo":"repo","prNumber":123,"rating":5,"findings":[]}
{"bucket":"needs-assignment","inputs":{"analysisVerdict":"needs-review","needsHumanReview":true}}'
MOCK_HAYSTACK_EXITS='0
0'
MOCK_HAYSTACK_SLEEPS='0
2'
_install_mock_with_exits

output=$(_run_reviewer 1 1)
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
