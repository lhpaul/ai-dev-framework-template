#!/usr/bin/env bash
# test-run-advisory-checks.sh - coverage for run-advisory-checks.sh (#1572).
#
# The shipped script is a no-op extension point for pr-review-loop.sh: it must
# require a PR number, print nothing and never fail the reviewer loop. The
# caller contract (stdout is advisory text, stderr is ignored, exit status never
# changes the result) is exercised through the real call shape used by
# pr-review-loop.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/development-workflow/run-advisory-checks.sh"
PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# run_script <args...> - sets STDOUT, STDERR and CODE separately.
run_script() {
  local err_file
  err_file="$(mktemp)"
  set +e
  STDOUT="$(bash "$SCRIPT_UNDER_TEST" "$@" 2>"$err_file")"
  CODE=$?
  set -e
  STDERR="$(cat "$err_file")"
  rm -f "$err_file"
}

run_script 1572
if [ "$CODE" -eq 0 ]; then pass "PR number exits 0"; else fail "PR number exits 0 (exit=$CODE)"; fi
if [ -z "$STDOUT" ]; then pass "default body prints no advisory output"; else fail "default body prints no advisory output"; fi
if [ -z "$STDERR" ]; then pass "default body prints nothing to stderr"; else fail "default body prints nothing to stderr"; fi

run_script
if [ "$CODE" -ne 0 ]; then pass "missing PR number fails"; else fail "missing PR number fails"; fi
if grep -Fq "Usage:" <<<"$STDERR"; then pass "missing PR number prints usage on stderr"; else fail "missing PR number prints usage on stderr"; fi
if [ -z "$STDOUT" ]; then pass "missing PR number prints nothing on stdout"; else fail "missing PR number prints nothing on stdout"; fi

run_script ""
if [ "$CODE" -ne 0 ]; then pass "empty PR number fails"; else fail "empty PR number fails"; fi

# Caller contract: pr-review-loop.sh runs the script with stderr discarded and
# its exit status ignored, so a failing invocation must not change the loop.
caller_output="$(bash "$SCRIPT_UNDER_TEST" 1572 2>/dev/null || true)"
if [ -z "$caller_output" ]; then pass "caller-shaped invocation yields empty advisory section"; else fail "caller-shaped invocation yields empty advisory section"; fi

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
