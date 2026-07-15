#!/usr/bin/env bash
# test-check-documentation-stage-alignment.sh - Unit tests for documentation-stage PR alignment.
#
# Usage: bash scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/development-workflow/check-documentation-stage-alignment.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/gh-calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

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
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

write_fixture() {
  local name="$1"
  local content="$2"
  local path="$TMP_ROOT/${name}.json"
  printf '%s\n' "$content" > "$path"
  printf '%s\n' "$path"
}

run_checker_json() {
  "$CHECKER" --input "$1" --json
}

run_checker_expect_status() {
  local expected_status="$1"
  shift
  local output status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne "$expected_status" ]; then
    printf 'EXPECTED_STATUS=%s\nACTUAL_STATUS=%s\n%s\n' "$expected_status" "$status" "$output"
    return 1
  fi
  printf '%s\n' "$output"
}

echo ""
echo "=== Documentation-stage alignment checker ==="

run_fails_contains "requires_one_pr_source" "Pass exactly one of --pr or --input" "$CHECKER"
run_fails_contains "rejects_conflicting_sources" "not both" "$CHECKER" --pr 1 --input "$TMP_ROOT/missing.json"
run_fails_contains "rejects_invalid_pr_number" "--pr must be a positive integer" "$CHECKER" --pr nope
run_fails_contains "rejects_flag_as_pr_value" "--pr requires a value" "$CHECKER" --pr --json
run_fails_contains "rejects_flag_as_input_value" "--input requires a value" "$CHECKER" --input --json
run_fails_contains "rejects_missing_fixture" "input file not found" "$CHECKER" --input "$TMP_ROOT/missing.json"
printf '{not-json\n' > "$TMP_ROOT/malformed.json"
run_fails_contains "rejects_malformed_fixture" "not valid JSON" "$CHECKER" --input "$TMP_ROOT/malformed.json"
: > "$TMP_ROOT/empty.json"
run_fails_contains "rejects_empty_fixture" "input file is empty" "$CHECKER" --input "$TMP_ROOT/empty.json"

spec_ok_fixture="$(write_fixture spec-ok '{
  "head": "spec/1206-block-implementation-code-in-plan-prs",
  "changed_files": [
    "docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/1_1206-block-implementation-code-in-plan-prs_specs.md"
  ]
}')"
spec_ok_output="$(run_checker_json "$spec_ok_fixture")"
run_test "spec_branch_allows_spec_doc" "aligned" "$(printf '%s\n' "$spec_ok_output" | jq -r '.result')"
run_test "spec_branch_reports_spec_stage" "spec" "$(printf '%s\n' "$spec_ok_output" | jq -r '.stage')"

plan_ok_fixture="$(write_fixture plan-ok '{
  "headRefName": "implementation-plan/1206-block-implementation-code-in-plan-prs",
  "files": [
    {"path": "docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/2_1206-block-implementation-code-in-plan-prs_implementation-plan.md"},
    {"path": "docs/testing/workflow/1206-block-implementation-code-in-plan-prs.smoke-test.md"}
  ]
}')"
plan_ok_output="$(run_checker_json "$plan_ok_fixture")"
run_test "plan_branch_allows_plan_doc_and_runbook" "aligned" "$(printf '%s\n' "$plan_ok_output" | jq -r '.result')"
run_test "plan_branch_reports_plan_stage" "plan" "$(printf '%s\n' "$plan_ok_output" | jq -r '.stage')"

feature_fixture="$(write_fixture feature '{
  "head": "feature/1206-block-implementation-code-in-plan-prs",
  "changed_files": ["src/components/PlanView.tsx"]
}')"
feature_output="$(run_checker_json "$feature_fixture")"
run_test "implementation_branch_not_applicable" "not_applicable" "$(printf '%s\n' "$feature_output" | jq -r '.result')"

spec_bad_fixture="$(write_fixture spec-bad '{
  "head": "spec/1206-block-implementation-code-in-plan-prs",
  "changed_files": [
    "docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/1_1206-block-implementation-code-in-plan-prs_specs.md",
    "src/components/PlanView.tsx"
  ]
}')"
spec_bad_output="$(run_checker_expect_status 8 "$CHECKER" --input "$spec_bad_fixture" --json)"
run_test "spec_branch_blocks_source_file" "mismatch" "$(printf '%s\n' "$spec_bad_output" | jq -r '.result')"
run_test "spec_branch_reports_unexpected_file" "src/components/PlanView.tsx" "$(printf '%s\n' "$spec_bad_output" | jq -r '.unexpected_files[0]')"

plan_bad_fixture="$(write_fixture plan-bad '{
  "head": "implementation-plan/1206-block-implementation-code-in-plan-prs",
  "changed_files": [
    "docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/2_1206-block-implementation-code-in-plan-prs_implementation-plan.md",
    "src/example.ts",
    "supabase/migrations/20260714000000_example.sql"
  ]
}')"
plan_bad_output="$(run_checker_expect_status 8 "$CHECKER" --input "$plan_bad_fixture" --json)"
run_test "plan_branch_blocks_migration_and_source_file" "2" "$(printf '%s\n' "$plan_bad_output" | jq -r '.unexpected_files | length')"
run_test "plan_branch_keeps_source_order" "src/example.ts" "$(printf '%s\n' "$plan_bad_output" | jq -r '.unexpected_files[0]')"

empty_fixture="$(write_fixture empty-diff '{
  "head": "implementation-plan/1206-block-implementation-code-in-plan-prs",
  "changed_files": []
}')"
empty_output="$(run_checker_expect_status 8 "$CHECKER" --input "$empty_fixture" --json)"
run_test "documentation_stage_empty_diff_blocks_readiness" "no stage artifact changed" "$(printf '%s\n' "$empty_output" | jq -r '.reason')"

diff_error_fixture="$(write_fixture diff-error '{
  "head": "spec/1206-block-implementation-code-in-plan-prs",
  "diff_error": true
}')"
diff_error_output="$(run_checker_expect_status 2 "$CHECKER" --input "$diff_error_fixture" --json || true)"
run_test "diff_read_failure_exits_infrastructure_error" "true" "$(printf '%s\n' "$diff_error_output" | grep -Fq 'fixture indicates changed-file read failure' && echo true || echo false)"

run_test "warning_comment_uses_stable_marker" "<!-- documentation-stage-alignment -->" "$(printf '%s\n' "$plan_bad_output" | jq -r '.warning_marker')"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"

case "$*" in
  auth\ status)
    exit 0
    ;;
  pr\ view\ 42\ --json\ number,headRefName,baseRefName,title)
    cat <<'JSON'
{"number":42,"headRefName":"implementation-plan/1206-block-implementation-code-in-plan-prs","baseRefName":"develop","title":"Plan with code"}
JSON
    ;;
  pr\ diff\ 42\ --name-only)
    printf '%s\n' \
      'docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/2_1206-block-implementation-code-in-plan-prs_implementation-plan.md' \
      'src/example.ts'
    ;;
  repo\ view\ --json\ nameWithOwner\ --jq\ .nameWithOwner)
    printf '%s\n' 'example/repo'
    ;;
  api\ repos/example/repo/issues/42/comments\ --paginate\ --slurp)
    cat <<'JSON'
[[{"id":99,"body":"<!-- documentation-stage-alignment -->\nold warning"}]]
JSON
    ;;
  api\ -X\ PATCH\ repos/example/repo/issues/comments/99\ -f\ body=*)
    exit 0
    ;;
  pr\ comment*)
    printf 'expected update, not new comment: gh %s\n' "$*" >&2
    exit 99
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
MOCK_PATH_ORIGINAL="$PATH"
export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"
live_output="$(run_checker_expect_status 8 "$CHECKER" --pr 42 --json)"
export PATH="$MOCK_PATH_ORIGINAL"
run_test "warning_comment_updates_existing_marker" "true" "$(grep -Fq 'api -X PATCH repos/example/repo/issues/comments/99 -f body=' "$CALL_LOG" && echo true || echo false)"
run_test "live_mode_reports_mismatch" "mismatch" "$(printf '%s\n' "$live_output" | jq -r '.result')"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
