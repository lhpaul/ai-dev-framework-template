#!/usr/bin/env bash
# Dispatch tests for the CodeRabbit CLI pr-review-loop platform.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

actual="$(bot_login_for_platform coderabbit-cli)"
run_test "bot_login_for_platform_coderabbit_cli_empty" "" "$actual"

actual="$(bot_login_for_platform coderabbit)"
run_test "bot_login_for_platform_coderabbit_app_unchanged" "coderabbitai" "$actual"

_coderabbit_cli_dispatch_called=0
_coderabbit_app_dispatch_called=0
run_coderabbit_cli_review() {
  _coderabbit_cli_dispatch_called=1
  print_kv RESULT skipped
  print_kv REASON unavailable
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
}
run_coderabbit_review() {
  _coderabbit_app_dispatch_called=1
  print_kv RESULT clean
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
}

run_platform_review "coderabbit-cli" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_coderabbit_cli" "1" "$_coderabbit_cli_dispatch_called"
run_test "run_platform_review_does_not_call_app_for_cli" "0" "$_coderabbit_app_dispatch_called"

_coderabbit_cli_dispatch_called=0
_coderabbit_app_dispatch_called=0
run_platform_review "coderabbit" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_coderabbit_app" "1" "$_coderabbit_app_dispatch_called"
run_test "run_platform_review_does_not_call_cli_for_app" "0" "$_coderabbit_cli_dispatch_called"

unset -f run_coderabbit_cli_review run_coderabbit_review

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"
