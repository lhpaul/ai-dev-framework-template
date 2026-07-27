#!/usr/bin/env bash
# test-validate-workflow-branch-name.sh - focused convention coverage.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/development-workflow/validate-workflow-branch-name.sh"
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected '%s', got '%s'\n" "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1" expected="$2" actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected output to contain '%s'\n" "$name" "$expected"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

validator_output() {
  local status output
  set +e
  output="$("$VALIDATOR" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

body() {
  tail -n +2 <<< "$1"
}

status_code() {
  head -n 1 <<< "$1"
}

for branch in \
  spec/1858-safe-name \
  implementation-plan/1858-safe-name \
  feature/1858-safe-name \
  fix/1858-safe-name \
  refactor/1858-safe-name \
  hotfix/1858-safe-name \
  backport/hotfix/1858-safe-name \
  feature/ENG-1858-safe-name \
  feature/1-a \
  feature/999999999999999999999999-safe-name; do
  out="$(validator_output "$branch")"
  run_test "accepts_valid_branch" "0" "$(status_code "$out")"
  run_contains "reports_valid_branch" "VALID_WORKFLOW_BRANCH=$branch" "$(body "$out")"
done

for unsafe_branch in \
  'fix/#1858-safe-name' \
  'fix/1858?safe-name' \
  'fix/1858^safe-name' \
  'fix/1858~safe-name' \
  'fix/1858:safe-name' \
  $'fix/1858\\safe-name' \
  'fix/1858 safe-name' \
  'fix/1858##safe-name'; do
  out="$(validator_output "$unsafe_branch")"
  run_test "rejects_unsafe_branch" "2" "$(status_code "$out")"
  run_contains "unsafe_branch_explains_convention" "violates the branch convention" "$(body "$out")"
  run_contains "unsafe_branch_suggests_correction" "fix/1858-slug" "$(body "$out")"
done

out="$(validator_output "")"
run_test "empty_input_rejected" "2" "$(status_code "$out")"
run_contains "empty_input_explains_format" "accepted prefix" "$(body "$out")"

out="$(validator_output '   ')"
run_test "whitespace_only_input_rejected" "2" "$(status_code "$out")"
run_contains "whitespace_only_input_names_unsafe_characters" "Unsafe characters" "$(body "$out")"

out="$(validator_output chore/1858-safe-name)"
run_test "unsupported_prefix_rejected" "2" "$(status_code "$out")"
run_contains "unsupported_prefix_explains_format" "accepted prefix" "$(body "$out")"

printf '\nResults: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
