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
    if [ "${MOCK_GH_MODE:-ok}" = "auth-fail" ]; then
      exit 1
    fi
    exit 0
    ;;
  pr\ view\ 42\ --json*)
    if [ "${MOCK_GH_MODE:-ok}" = "view-fail" ]; then
      exit 1
    fi
    if [ "${MOCK_GH_MODE:-ok}" = "view-empty" ]; then
      exit 0
    fi
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
    if [ "${MOCK_GH_MODE:-ok}" = "diff-fail" ]; then
      exit 1
    fi
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
run_fails_contains "rejects_flag_as_pr_value" "--pr requires a value" "$CLASSIFIER" --pr --json
run_fails_contains "rejects_flag_as_input_value" "--input requires a value" "$CLASSIFIER" --input --json
run_fails_contains "rejects_flag_as_max_risk_value" "--max-risk requires a value" "$CLASSIFIER" --input "$TMP_ROOT/missing.json" --max-risk --json
run_fails_contains "rejects_invalid_max_risk" "--max-risk must be one of low, medium, or high" "$CLASSIFIER" --input "$TMP_ROOT/missing.json" --max-risk blocked
run_fails_contains "rejects_missing_fixture" "input file not found" "$CLASSIFIER" --input "$TMP_ROOT/missing.json"
printf '{not-json\n' > "$TMP_ROOT/malformed.json"
run_fails_contains "rejects_malformed_fixture" "not valid JSON" "$CLASSIFIER" --input "$TMP_ROOT/malformed.json"
: > "$TMP_ROOT/empty.json"
run_fails_contains "rejects_empty_fixture" "input file is empty" "$CLASSIFIER" --input "$TMP_ROOT/empty.json"
printf ' \n\t\n' > "$TMP_ROOT/whitespace.json"
run_fails_contains "rejects_whitespace_fixture" "not valid JSON" "$CLASSIFIER" --input "$TMP_ROOT/whitespace.json"

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
run_test "json_output_shape_stable" "yes" "$(
  printf '%s\n' "$low_output" |
    jq -e '
      has("pr_number") and
      has("risk") and
      has("max_risk") and
      has("merge_permitted") and
      has("gate_reason") and
      (.reasons | type == "array") and
      (.blockers | type == "array") and
      has("why_safe_to_merge") and
      has("read_only_guarantee")
    ' >/dev/null && echo yes || echo no
)"

test_script_fixture="$(write_fixture test-script '{
  "pr_number": 1,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["scripts/development-workflow/tests/test-run-epic-risk-classifier.sh"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
test_script_output="$(classify_fixture "$test_script_fixture" low)"
run_test "classifies_workflow_test_script_low" "low" "$(printf '%s\n' "$test_script_output" | jq -r '.risk')"

boundary_fixture="$(write_fixture boundary-risk '{
  "pr_number": 1,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/authenticate-button.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
boundary_output="$(classify_fixture "$boundary_fixture" low)"
run_test "auth_substring_not_high_risk" "low" "$(printf '%s\n' "$boundary_output" | jq -r '.risk')"

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

incomplete_success_fixture="$(write_fixture incomplete-success '{
  "pr_number": 6,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "IN_PROGRESS", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
incomplete_success_output="$(classify_fixture "$incomplete_success_fixture" high)"
run_test "incomplete_success_check_blocks" "blocked" "$(printf '%s\n' "$incomplete_success_output" | jq -r '.risk')"

implementation_plan_skipped_fixture="$(write_fixture implementation-plan-skipped '{
  "pr_number": 7,
  "head": "implementation-plan/955-run-epic-skipped-regression-checks",
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [
    {"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"},
    {"name": "E2E regression (placeholder)", "status": "COMPLETED", "conclusion": "SKIPPED"}
  ],
  "changed_files": ["docs/specs/developments/2026-06-15_run-epic-skipped-regression-checks/2_run-epic-skipped-regression-checks_implementation-plan.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
implementation_plan_skipped_output="$(classify_fixture "$implementation_plan_skipped_fixture" low)"
run_test "implementation_plan_skipped_regression_check_allowed" "low" "$(printf '%s\n' "$implementation_plan_skipped_output" | jq -r '.risk')"
run_test "implementation_plan_skipped_regression_merge_permitted" "true" "$(printf '%s\n' "$implementation_plan_skipped_output" | jq -r '.merge_permitted')"

spec_neutral_fixture="$(write_fixture spec-neutral '{
  "pr_number": 7,
  "head": "spec/955-run-epic-skipped-regression-checks",
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [
    {"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"},
    {"name": "E2E regression (placeholder)", "status": "COMPLETED", "conclusion": "NEUTRAL"}
  ],
  "changed_files": ["docs/specs/developments/2026-06-15_run-epic-skipped-regression-checks/1_run-epic-skipped-regression-checks_specs.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
spec_neutral_output="$(classify_fixture "$spec_neutral_fixture" low)"
run_test "spec_neutral_regression_check_allowed" "low" "$(printf '%s\n' "$spec_neutral_output" | jq -r '.risk')"
run_test "spec_neutral_regression_merge_permitted" "true" "$(printf '%s\n' "$spec_neutral_output" | jq -r '.merge_permitted')"

for terminal_conclusion in FAILURE CANCELLED TIMED_OUT ACTION_REQUIRED STARTUP_FAILURE ""; do
  fixture_suffix="${terminal_conclusion:-missing}"
  terminal_fixture="$(write_fixture "terminal-${fixture_suffix}" "{
    \"pr_number\": 7,
    \"merge_state\": \"CLEAN\",
    \"labels\": [\"ready-for-human-review\"],
    \"status_checks\": [{\"name\": \"guard\", \"status\": \"COMPLETED\", \"conclusion\": \"${terminal_conclusion}\"}],
    \"changed_files\": [\"docs/README.md\"],
    \"reviewer\": {\"status\": \"clean\", \"blocking_count\": 0, \"unresolved_blocking_threads\": 0}
  }")"
  terminal_output="$(classify_fixture "$terminal_fixture" high)"
  run_test "completed_${fixture_suffix}_check_blocks" "blocked" "$(printf '%s\n' "$terminal_output" | jq -r '.risk')"
done

for pending_state in IN_PROGRESS QUEUED PENDING EXPECTED; do
  pending_fixture="$(write_fixture "pending-${pending_state}" "{
    \"pr_number\": 7,
    \"merge_state\": \"CLEAN\",
    \"labels\": [\"ready-for-human-review\"],
    \"status_checks\": [{\"name\": \"guard\", \"status\": \"${pending_state}\", \"conclusion\": \"SUCCESS\"}],
    \"changed_files\": [\"docs/README.md\"],
    \"reviewer\": {\"status\": \"clean\", \"blocking_count\": 0, \"unresolved_blocking_threads\": 0}
  }")"
  pending_output="$(classify_fixture "$pending_fixture" high)"
  run_test "${pending_state}_check_blocks" "blocked" "$(printf '%s\n' "$pending_output" | jq -r '.risk')"
done

dedupe_checks_fixture="$(write_fixture dedupe-checks '{
  "pr_number": 8,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [
    {"name": "guard", "status": "COMPLETED", "conclusion": "FAILURE", "completed_at": "2026-06-12T10:00:00Z"},
    {"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS", "completed_at": "2026-06-12T10:05:00Z"}
  ],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
dedupe_checks_output="$(classify_fixture "$dedupe_checks_fixture" low)"
run_test "stale_check_failure_deduped_by_latest_success" "low" "$(printf '%s\n' "$dedupe_checks_output" | jq -r '.risk')"
run_test "stale_check_failure_does_not_block" "true" "$(printf '%s\n' "$dedupe_checks_output" | jq -r '.merge_permitted')"

mixed_timestamp_fixture="$(write_fixture mixed-timestamp-checks '{
  "pr_number": 8,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [
    {"name": "guard", "status": "COMPLETED", "conclusion": "FAILURE", "completed_at": "2026-06-12T10:00:00Z"},
    {"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}
  ],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
mixed_timestamp_output="$(classify_fixture "$mixed_timestamp_fixture" low)"
run_test "mixed_timestamp_checks_use_latest_input_entry" "low" "$(printf '%s\n' "$mixed_timestamp_output" | jq -r '.risk')"
run_test "mixed_timestamp_checks_merge_permitted" "true" "$(printf '%s\n' "$mixed_timestamp_output" | jq -r '.merge_permitted')"

reviewer_available_fixture="$(write_fixture reviewer-available '{
  "pr_number": 9,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
reviewer_available_output="$(classify_fixture "$reviewer_available_fixture" low)"
run_test "reviewer_clean_zero_threads_allowed" "low" "$(printf '%s\n' "$reviewer_available_output" | jq -r '.risk')"
run_test "reviewer_clean_zero_threads_merge_permitted" "true" "$(printf '%s\n' "$reviewer_available_output" | jq -r '.merge_permitted')"

reviewer_unavailable_fixture="$(write_fixture reviewer-unavailable '{
  "pr_number": 10,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "unavailable", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
reviewer_unavailable_output="$(classify_fixture "$reviewer_unavailable_fixture" low)"
run_test "reviewer_unavailable_blocks" "blocked" "$(printf '%s\n' "$reviewer_unavailable_output" | jq -r '.risk')"

one_thread_fixture="$(write_fixture one-thread '{
  "pr_number": 11,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 1}
}')"
one_thread_output="$(classify_fixture "$one_thread_fixture" low)"
run_test "one_unresolved_blocking_thread_blocks" "blocked" "$(printf '%s\n' "$one_thread_output" | jq -r '.risk')"

for blocker_flag in ambiguous_tracker_state unclear_base_branch missing_credentials destructive_action_required force_push_required; do
  blocker_fixture="$(write_fixture "blocker-${blocker_flag}" "{
    \"pr_number\": 12,
    \"merge_state\": \"CLEAN\",
    \"labels\": [\"ready-for-human-review\"],
    \"status_checks\": [{\"name\": \"guard\", \"status\": \"COMPLETED\", \"conclusion\": \"SUCCESS\"}],
    \"changed_files\": [\"docs/README.md\"],
    \"reviewer\": {\"status\": \"clean\", \"blocking_count\": 0, \"unresolved_blocking_threads\": 0},
    \"${blocker_flag}\": true
  }")"
  blocker_output="$(classify_fixture "$blocker_fixture" high)"
  run_test "${blocker_flag}_blocks" "blocked" "$(printf '%s\n' "$blocker_output" | jq -r '.risk')"
done

needs_setup_fixture="$(write_fixture needs-setup '{
  "pr_number": 13,
  "merge_state": "CLEAN",
  "labels": ["ready-for-human-review", "needs-setup"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
needs_setup_output="$(classify_fixture "$needs_setup_fixture" high)"
run_test "needs_setup_label_blocks" "blocked" "$(printf '%s\n' "$needs_setup_output" | jq -r '.risk')"

dirty_merge_fixture="$(write_fixture dirty-merge '{
  "pr_number": 14,
  "merge_state": "DIRTY",
  "labels": ["ready-for-human-review"],
  "status_checks": [{"name": "guard", "status": "COMPLETED", "conclusion": "SUCCESS"}],
  "changed_files": ["docs/README.md"],
  "reviewer": {"status": "clean", "blocking_count": 0, "unresolved_blocking_threads": 0}
}')"
dirty_merge_output="$(classify_fixture "$dirty_merge_fixture" high)"
run_test "dirty_merge_state_blocks" "blocked" "$(printf '%s\n' "$dirty_merge_output" | jq -r '.risk')"

threshold_output="$(classify_fixture "$medium_fixture" low)"
run_test "max_risk_gate_blocks_excess_risk" "false" "$(printf '%s\n' "$threshold_output" | jq -r '.merge_permitted')"
run_test "max_risk_gate_reason" "yes" "$(printf '%s\n' "$threshold_output" | jq -e '.gate_reason | test("exceeds max risk")' >/dev/null && echo yes || echo no)"

live_output="$("$CLASSIFIER" --pr 42 --max-risk low --json)"
run_test "live_pr_path_read_only_classifies" "low" "$(printf '%s\n' "$live_output" | jq -r '.risk')"
run_test "live_pr_path_merge_permitted" "true" "$(printf '%s\n' "$live_output" | jq -r '.merge_permitted')"
run_test "json_read_only_guarantee" "yes" "$(printf '%s\n' "$live_output" | jq -e '.read_only_guarantee | test("No tracker status")' >/dev/null && echo yes || echo no)"
run_fails_contains "live_pr_view_failure_errors" "failed to read PR #42" env MOCK_GH_MODE=view-fail "$CLASSIFIER" --pr 42 --json
run_fails_contains "live_pr_empty_response_errors" "empty PR response for #42" env MOCK_GH_MODE=view-empty "$CLASSIFIER" --pr 42 --json
run_fails_contains "live_pr_diff_failure_errors" "failed to read changed files for PR #42" env MOCK_GH_MODE=diff-fail "$CLASSIFIER" --pr 42 --json

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
