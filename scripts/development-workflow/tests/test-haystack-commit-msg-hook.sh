#!/usr/bin/env bash
# test-haystack-commit-msg-hook.sh - Unit tests for hooks/commit-msg.
#
# Usage: bash scripts/development-workflow/tests/test-haystack-commit-msg-hook.sh
#
# Exit code: 0 if all tests pass, 1 if any test fails.
# covers: hooks/commit-msg

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *)  REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac

HOOK="$REPO_ROOT/hooks/commit-msg"
TMP_DIR="$(mktemp -d)"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_DIR"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

# Downstream repos may gitignore /hooks/ (local git-hook tooling). The suite
# is still selected on a full workflow-tests.yml run, so skip instead of
# failing CI when the hook is not versioned there.
if [ ! -f "$HOOK" ]; then
  echo "SKIP: commit-msg hook not present at $HOOK"
  exit 0
fi
if [ ! -x "$HOOK" ]; then
  echo "ERROR: commit-msg hook not executable at $HOOK" >&2
  exit 1
fi

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
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

repeat_char() {
  local char="$1"
  local count="$2"
  local output=""
  while [ "$count" -gt 0 ]; do
    output="${output}${char}"
    count=$(( count - 1 ))
  done
  printf '%s' "$output"
}

hook_result() {
  local subject="$1"
  local msg_file="$TMP_DIR/message"
  printf '%s\n' "$subject" > "$msg_file"
  hook_file_result "$msg_file"
}

hook_file_result() {
  local msg_file="$1"
  if "$HOOK" "$msg_file" >/dev/null 2>&1; then
    printf 'pass'
  else
    printf 'fail'
  fi
}

run_test "plain_type_passes" "pass" "$(hook_result "docs: update haystack usage")"
run_test "simple_scope_passes" "pass" "$(hook_result "fix(haystack): harden hook guardrails")"
run_test "slash_scope_passes" "pass" "$(hook_result "feat(ui/button): add primary variant")"
run_test "nested_numeric_scope_passes" "pass" "$(hook_result "fix(api/v2): handle versioned route")"
run_test "fixup_prefix_bypasses" "pass" "$(hook_result "fixup! invalid subject")"
run_test "squash_prefix_bypasses" "pass" "$(hook_result "squash! invalid subject")"
run_test "amend_prefix_bypasses" "pass" "$(hook_result "amend! invalid subject")"
run_test "merge_prefix_bypasses" "pass" "$(hook_result "Merge branch 'develop'")"
run_test "revert_prefix_bypasses" "pass" "$(hook_result "Revert \"docs: update haystack usage\"")"
run_test "unquoted_revert_prefix_bypasses" "pass" "$(hook_result "Revert docs: update haystack usage")"

run_test "missing_type_fails" "fail" "$(hook_result "update haystack usage")"
run_test "unknown_type_fails" "fail" "$(hook_result "feature: add hook guardrail")"
run_test "empty_description_fails" "fail" "$(hook_result "docs: ")"
run_test "leading_space_fails" "fail" "$(hook_result " docs: update haystack usage")"

missing_msg_file="$TMP_DIR/does-not-exist"
empty_msg_file="$TMP_DIR/empty-message"
comment_only_msg_file="$TMP_DIR/comment-only-message"
: > "$empty_msg_file"
printf '%s\n\n%s\n' "# commit message comment" "   # another comment" > "$comment_only_msg_file"
run_test "missing_message_file_fails" "fail" "$(hook_file_result "$missing_msg_file")"
run_test "empty_message_file_fails" "fail" "$(hook_file_result "$empty_msg_file")"
run_test "comment_only_message_file_fails" "fail" "$(hook_file_result "$comment_only_msg_file")"

boundary_description="$(repeat_char a 66)"
over_limit_description="$(repeat_char a 67)"
run_test "subject_72_chars_passes" "pass" "$(hook_result "docs: ${boundary_description}")"
run_test "subject_73_chars_fails" "fail" "$(hook_result "docs: ${over_limit_description}")"

echo ""
echo "Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
