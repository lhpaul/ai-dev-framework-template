#!/usr/bin/env bash
# test-run-epic-risk-classifier.sh - Unit tests for delegated PR risk classification.
#
# Usage: bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/development-workflow/run-epic-risk-classifier.sh"

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

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"

case "$*" in
  auth\ status)
    exit 0
    ;;
  pr\ view\ 42\ --json*)
    cat <<'JSON'
{
  "number": 42,
  "title": "Live low risk",
  "baseRefName": "develop-delegated-epic-orchestration",
  "headRefName": "docs/live-low",
  "mergeStateStatus": "CLEAN",
  "isDraft": false,
  "reviewDecision": "APPROVED",
  "labels": [{"name": "ready-for-human-review"}],
  "statusCheckRollup": [
    {"__typename": "CheckRun", "name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"},
    {"__typename": "StatusContext", "context": "Reviewer-loop completion guard (#42)", "state": "SUCCESS"}
  ]
}
JSON
    ;;
  pr\ diff\ 42\ --name-only)
    printf '%s\n' 'docs/workflow/development-workflow/protocols/95-run-epic-protocol.md'
    ;;
  issue\ edit*|pr\ create*|pr\ merge*|project\ item-edit*|project\ item-add*|pr\ comment*|pr\ close*|pr\ edit*)
    printf 'mutating gh command was called: gh %s\n' "$*" >&2
    exit 99
    ;;
  *'mutation'*)
    printf 'mutating GraphQL operation was called: gh %s\n' "$*" >&2
    exit 99
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"

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

classify_fixture() {
  "$CLASSIFIER" --input "$1" --max-risk "${2:-low}" --json
}

echo ""
echo "=== Run epic risk classifier ==="

run_fails_contains "requires_one_pr_source" "pass exactly one of --pr or --input" "$CLASSIFIER"
run_fails_contains "rejects_conflicting_pr_sources" "not both" "$CLASSIFIER" --pr 1 --input "$TMP_ROOT/missing.json"
run_fails_contains "rejects_invalid_pr_number" "--pr must be a positive integer" "$CLASSIFIER" --pr nope
run_fails_contains "rejects_invalid_max_risk" "--max-risk must be one of low, medium, or high" "$CLASSIFIER" --input "$TMP_ROOT/missing.json" --max-risk blocked
run_fails_contains "rejects_missing_fixture" "input file not found" "$CLASSIFIER" --input "$TMP_ROOT/missing.json"
printf '{not-json\n' > "$TMP_ROOT/malformed.json"
run_fails_contains "rejects_malformed_fixture" "not valid JSON" "$CLASSIFIER" --input "$TMP_ROOT/malformed.json"

low_fixture="$(write_fixture low '{
  "pr_number": 1,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/testing/workflow/919-pr-risk-classification.smoke-test.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
low_output="$(classify_fixture "$low_fixture" low)"
run_test "classifies_low_docs_and_tests" "low" "$(printf '%s\n' "$low_output" | jq -r '.risk')"
run_test "low_merge_permitted" "true" "$(printf '%s\n' "$low_output" | jq -r '.merge_permitted')"
run_test "json_output_has_reasons" "yes" "$(printf '%s\n' "$low_output" | jq -e '.reasons | length > 0' >/dev/null && echo yes || echo no)"

medium_fixture="$(write_fixture medium '{
  "pr_number": 2,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["scripts/development-workflow/run-epic-risk-classifier.sh"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0},
  "why_safe_to_merge": {
    "scope": "single read-only classifier helper",
    "tests": "fixture tests cover risk classes",
    "reviewer_outcome": "reviewer loop clean",
    "ci_outcome": "CI green",
    "rollback_or_cleanup_risk": "remove helper and docs if needed"
  }
}')"
medium_output="$(classify_fixture "$medium_fixture" medium)"
run_test "classifies_medium_workflow_script_with_evidence" "medium" "$(printf '%s\n' "$medium_output" | jq -r '.risk')"
run_test "medium_merge_permitted_with_medium_threshold" "true" "$(printf '%s\n' "$medium_output" | jq -r '.merge_permitted')"
run_test "medium_has_why_safe" "single read-only classifier helper" "$(printf '%s\n' "$medium_output" | jq -r '.why_safe_to_merge.scope')"

medium_missing_fixture="$(write_fixture medium-missing '{
  "pr_number": 3,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["scripts/development-workflow/run-epic-risk-classifier.sh"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0},
  "why_safe_to_merge": {
    "scope": "single helper",
    "tests": "fixture tests",
    "reviewer_outcome": "clean",
    "ci_outcome": "",
    "rollback_or_cleanup_risk": "low"
  }
}')"
medium_missing_output="$(classify_fixture "$medium_missing_fixture" medium)"
run_test "blocks_medium_without_evidence" "blocked" "$(printf '%s\n' "$medium_missing_output" | jq -r '.risk')"
run_test "missing_evidence_blocks_merge" "false" "$(printf '%s\n' "$medium_missing_output" | jq -r '.merge_permitted')"

high_fixture="$(write_fixture high '{
  "pr_number": 4,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": [".github/workflows/release.yml", "scripts/development-workflow/auth-token-helper.sh"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
high_output="$(classify_fixture "$high_fixture" high)"
run_test "classifies_high_sensitive_scope" "high" "$(printf '%s\n' "$high_output" | jq -r '.risk')"
run_test "high_merge_permitted_with_high_threshold" "true" "$(printf '%s\n' "$high_output" | jq -r '.merge_permitted')"

blocked_fixture="$(write_fixture blocked '{
  "pr_number": 5,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review", "needs-setup"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "FAILURE"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "failed", "blocking_count": 1, "unresolved_blocking_threads": 1},
  "missing_credentials": true,
  "ambiguous_tracker_state": true,
  "unclear_base_branch": true,
  "force_push_required": true,
  "destructive_action_required": true
}')"
blocked_output="$(classify_fixture "$blocked_fixture" high)"
run_test "hard_blockers_take_precedence" "blocked" "$(printf '%s\n' "$blocked_output" | jq -r '.risk')"
run_test "blocked_not_mergeable" "false" "$(printf '%s\n' "$blocked_output" | jq -r '.merge_permitted')"
run_test "hard_blocker_count" "yes" "$(printf '%s\n' "$blocked_output" | jq -e '.blockers | length >= 8' >/dev/null && echo yes || echo no)"

missing_check_fixture="$(write_fixture missing-check '{
  "pr_number": 6,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
missing_check_output="$(classify_fixture "$missing_check_fixture" high)"
run_test "missing_check_state_blocks" "blocked" "$(printf '%s\n' "$missing_check_output" | jq -r '.risk')"
run_test "missing_check_state_reason_clear" "yes" "$(printf '%s\n' "$missing_check_output" | jq -e '.blockers[] | select(test("missing or ambiguous"))' >/dev/null && echo yes || echo no)"

threshold_output="$(classify_fixture "$medium_fixture" low)"
run_test "max_risk_gate_blocks_excess_risk" "false" "$(printf '%s\n' "$threshold_output" | jq -r '.merge_permitted')"
run_test "max_risk_gate_reason" "yes" "$(printf '%s\n' "$threshold_output" | jq -e '.gate_reason | test("exceeds max risk")' >/dev/null && echo yes || echo no)"

live_output="$("$CLASSIFIER" --pr 42 --max-risk low --json)"
run_test "live_pr_path_read_only_classifies" "low" "$(printf '%s\n' "$live_output" | jq -r '.risk')"
run_test "live_pr_path_merge_permitted" "true" "$(printf '%s\n' "$live_output" | jq -r '.merge_permitted')"
run_test "json_read_only_guarantee" "yes" "$(printf '%s\n' "$live_output" | jq -e '.read_only_guarantee | test("No tracker status")' >/dev/null && echo yes || echo no)"

run_test "no_mutating_gh_commands" "no" "$(
  grep -Eq '(^issue edit|^pr create|^pr merge|^project item-edit|^project item-add|^pr comment|^pr close|^pr edit|mutation)' "$CALL_LOG" && echo yes || echo no
)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
