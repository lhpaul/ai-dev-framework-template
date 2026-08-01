#!/usr/bin/env bash
# test-multi-repo-release-assurance.sh - #1359 assurance harness tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/multi-repo-release-assurance.sh"
FIXTURE_HELPER="$REPO_ROOT/scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh"

for tool in jq python3 git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SETUP_ERROR=$tool is required" >&2
    exit 2
  fi
done

TMP_ROOT="$(mktemp -d)"
TMP_ROOT="$(CDPATH='' cd -- "$TMP_ROOT" && pwd -P)"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  exit "$status"
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

run_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo ""
echo "=== Multi-repository release assurance ==="

fixture_json="$TMP_ROOT/fixtures.json"
bash "$FIXTURE_HELPER" --output-dir "$TMP_ROOT/fixtures" --json > "$fixture_json"

VALID_FIXTURE="$(jq -r '.fixtures.valid' "$fixture_json")"
BLOCKED_FIXTURE="$(jq -r '.fixtures.blocked' "$fixture_json")"
RETRYABLE_FIXTURE="$(jq -r '.fixtures.retryable' "$fixture_json")"
HISTORY_MUTATION_FIXTURE="$(jq -r '.fixtures.history_mutation' "$fixture_json")"
REPEATED_SIDE_EFFECT_FIXTURE="$(jq -r '.fixtures.repeated_side_effect' "$fixture_json")"
MISSING_EVIDENCE_FIXTURE="$(jq -r '.fixtures.missing_evidence' "$fixture_json")"

"$HELPER" --fixture-dir "$VALID_FIXTURE" --json > "$TMP_ROOT/valid.json"
run_test "valid_schema" "multi_repo_release_assurance.v1" "$(jq -r '.schema_version' "$TMP_ROOT/valid.json")"
run_test "valid_adoption_status" "validated" "$(jq -r '.adoption_status' "$TMP_ROOT/valid.json")"
run_test "valid_scenario_count" "8" "$(jq -r '.scenario_results | length' "$TMP_ROOT/valid.json")"
run_test "valid_hub_history_unchanged" "true" "$(jq -r '.historical_no_rewrite[] | select(.owner == "hub") | .unchanged' "$TMP_ROOT/valid.json")"
run_test "valid_product_history_unchanged" "true" "$(jq -r '.historical_no_rewrite[] | select(.owner == "product") | .unchanged' "$TMP_ROOT/valid.json")"
run_test "valid_skipped_has_rationale" "true" "$(jq -r '[.scenario_results[] | select(.outcome == "skipped" and (.rationale | length > 0))] | length == 1' "$TMP_ROOT/valid.json")"
run_test "valid_rerun_has_step_identity" "cleanup" "$(jq -r '.scenario_results[] | select(.name == "reruns") | .step_id' "$TMP_ROOT/valid.json")"

"$HELPER" --fixture-dir "$BLOCKED_FIXTURE" --json > "$TMP_ROOT/blocked.json"
run_test "blocked_adoption_status" "blocked" "$(jq -r '.adoption_status' "$TMP_ROOT/blocked.json")"
run_contains "blocked_owner_action" "fix product release contract owner" "$(cat "$TMP_ROOT/blocked.json")"

"$HELPER" --fixture-dir "$RETRYABLE_FIXTURE" --json > "$TMP_ROOT/retryable.json"
run_test "retryable_adoption_status" "blocked" "$(jq -r '.adoption_status' "$TMP_ROOT/retryable.json")"
run_test "retryable_outcome" "retryable" "$(jq -r '.scenario_results[] | select(.name == "reruns") | .outcome' "$TMP_ROOT/retryable.json")"
run_contains "retryable_action" "current run id" "$(cat "$TMP_ROOT/retryable.json")"

"$HELPER" --fixture-dir "$HISTORY_MUTATION_FIXTURE" --json > "$TMP_ROOT/history-mutation.json"
run_test "history_mutation_blocks" "blocked" "$(jq -r '.adoption_status' "$TMP_ROOT/history-mutation.json")"
run_test "history_mutation_product_changed" "false" "$(jq -r '.historical_no_rewrite[] | select(.owner == "product") | .unchanged' "$TMP_ROOT/history-mutation.json")"
run_contains "history_mutation_action" "restore historical baseline" "$(cat "$TMP_ROOT/history-mutation.json")"

"$HELPER" --fixture-dir "$REPEATED_SIDE_EFFECT_FIXTURE" --json > "$TMP_ROOT/repeated-side-effect.json"
run_test "repeated_side_effect_blocks" "blocked" "$(jq -r '.adoption_status' "$TMP_ROOT/repeated-side-effect.json")"
run_test "repeated_side_effect_forces_fail" "fail" "$(jq -r '.scenario_results[] | select(.name == "reruns") | .outcome' "$TMP_ROOT/repeated-side-effect.json")"
run_contains "repeated_side_effect_action" "idempotency" "$(cat "$TMP_ROOT/repeated-side-effect.json")"

"$HELPER" --fixture-dir "$MISSING_EVIDENCE_FIXTURE" --json > "$TMP_ROOT/missing-evidence.json"
run_test "missing_evidence_blocks" "blocked" "$(jq -r '.adoption_status' "$TMP_ROOT/missing-evidence.json")"
run_test "missing_evidence_forces_fail" "fail" "$(jq -r '.scenario_results[] | select(.name == "component_routing") | .outcome' "$TMP_ROOT/missing-evidence.json")"
run_test "missing_evidence_requires_supersedes" "true" "$(jq -r '.scenario_results[] | select(.name == "reruns") | (.missing_evidence | index("supersedes") != null)' "$TMP_ROOT/missing-evidence.json")"
run_contains "missing_evidence_action" "provide required evidence before adoption" "$(cat "$TMP_ROOT/missing-evidence.json")"

"$HELPER" --fixture-dir "$VALID_FIXTURE" > "$TMP_ROOT/valid.env"
run_contains "shell_output_status" "ADOPTION_STATUS=validated" "$(cat "$TMP_ROOT/valid.env")"
run_contains "shell_output_history" "HISTORICAL_NO_REWRITE=True" "$(cat "$TMP_ROOT/valid.env")"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi

echo "All multi-repository release assurance tests passed ($PASS_COUNT assertions)."
