#!/usr/bin/env bash
# test-component-release-evidence.sh - component release evidence tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
TARGET_HELPER="$REPO_ROOT/scripts/development-workflow/component-release-target.sh"
EVIDENCE_HELPER="$REPO_ROOT/scripts/development-workflow/component-release-evidence.sh"
MILESTONE_HELPER="$REPO_ROOT/scripts/development-workflow/component-milestone-reconciliation.sh"
FIXTURE_HELPER="$REPO_ROOT/scripts/development-workflow/tests/setup-component-release-fixture.sh"

TMP_ROOT="$(mktemp -d)"
TMP_ROOT="$(CDPATH='' cd -- "$TMP_ROOT" && pwd -P)"

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

run_fails_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output="" status=0
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

echo ""
echo "=== Component release evidence ==="

fixture_json="$(bash "$FIXTURE_HELPER" --work-dir "$TMP_ROOT/fixtures" --json)"
hub_repo="$(jq -r '.workflow_hub.path // .hub_repo' <<< "$fixture_json")"
target_file="$TMP_ROOT/target.json"
binding_file="$TMP_ROOT/binding.json"
evidence_file="$TMP_ROOT/evidence.json"

bash "$TARGET_HELPER" --repo-root "$hub_repo" --repo mobile-app --json > "$target_file"
cp "$target_file" "$binding_file"

evidence_json="$(bash "$EVIDENCE_HELPER" \
  --target-file "$target_file" \
  --binding-file "$binding_file" \
  --release-branch mobile-app/release/v1.18.0 \
  --release-outcome completed \
  --ci-outcome passed \
  --deployment-outcome recorded \
  --cleanup-outcome complete \
  --hub-tracker-ref "#1356" \
  --output "$evidence_file" \
  --json)"

run_test "evidence_schema" "component_release_evidence.v1" "$(jq -r '.schema_version' <<< "$evidence_json")"
run_test "evidence_target_outcome" "component_release_routed" "$(jq -r '.target_binding.routing_outcome' <<< "$evidence_json")"
run_test "evidence_top_level_outcome" "component_release_routed" "$(jq -r '.routing_outcome' <<< "$evidence_json")"
run_test "evidence_top_level_identity" "example/mobile-app" "$(jq -r '.canonical_repository_identity' <<< "$evidence_json")"
run_test "evidence_release_branch" "mobile-app/release/v1.18.0" "$(jq -r '.release_branch' <<< "$evidence_json")"
run_test "evidence_release_outcome" "completed" "$(jq -r '.release_outcome' <<< "$evidence_json")"
run_test "evidence_ci_outcome" "passed" "$(jq -r '.ci_outcome' <<< "$evidence_json")"
run_test "evidence_cleanup_outcome" "complete" "$(jq -r '.cleanup_outcome' <<< "$evidence_json")"
run_test "evidence_written" "component_release_evidence.v1" "$(jq -r '.schema_version' "$evidence_file")"

mismatch_file="$TMP_ROOT/mismatch.json"
jq '.contract_revision = "sha256:mismatch"' "$binding_file" > "$mismatch_file"
run_fails_contains \
  "evidence_rejects_contract_revision_mismatch" \
  "Evidence binding mismatch for .contract_revision" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$target_file" \
    --binding-file "$mismatch_file" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

owner_mismatch="$TMP_ROOT/owner-mismatch.json"
jq '.artifact_owners.release = "hub_repository"' "$binding_file" > "$owner_mismatch"
run_fails_contains \
  "evidence_rejects_owner_mismatch" \
  "Evidence binding mismatch for .artifact_owners" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$target_file" \
    --binding-file "$owner_mismatch" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

run_fails_contains \
  "evidence_rejects_bad_outcome" \
  "release outcome 'done' is not allowed" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$target_file" \
    --binding-file "$binding_file" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome 'done' \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

stop_target="$TMP_ROOT/stop-target.json"
bash "$TARGET_HELPER" --repo-root "$hub_repo" --json > "$stop_target"
run_fails_contains \
  "evidence_rejects_non_mutation_target" \
  "target binding is not mutation-allowed" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$stop_target" \
    --binding-file "$stop_target" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome blocked \
    --ci-outcome not_applicable \
    --deployment-outcome not_applicable \
    --cleanup-outcome blocked \
    --hub-tracker-ref "#1356" \
    --json

# Real producer -> consumer handoff: feed the evidence file rendered above by
# the actual component-release-evidence.sh producer straight into
# component-milestone-reconciliation.sh (the consumer), instead of a
# hand-built fixture that could accidentally embed fields the real producer
# never emits (evidence_state, hub_tracker_reconciliation_outcome,
# child_release_state) and hide a broken handoff. Use inspect-component
# (read-only, does not call gh) so this test never touches a real repository.
handoff_no_flags="$(bash "$MILESTONE_HELPER" inspect-component   --issue 1358   --target-kind component_child   --product-repo mobile-app   --component-tag mobile-v1.18.0   --evidence-file "$evidence_file"   --json)"
run_test "handoff_no_flags_evidence_state_not_missing" "false"   "$(jq '([.blockers[]] | index("evidence_state_missing")) != null' <<< "$handoff_no_flags")"
run_contains "handoff_no_flags_still_needs_hub_state" "hub_tracker_reconciliation_missing" "$handoff_no_flags"
run_contains "handoff_no_flags_still_needs_child_state" "child_release_state_missing" "$handoff_no_flags"

handoff_with_flags="$(bash "$MILESTONE_HELPER" inspect-component   --issue 1358   --target-kind component_child   --product-repo mobile-app   --component-tag mobile-v1.18.0   --evidence-file "$evidence_file"   --hub-tracker-reconciliation-outcome complete   --child-release-state released   --json)"
run_test "handoff_outcome" "component_released" "$(jq -r '.reconciliation_outcome' <<< "$handoff_with_flags")"
run_test "handoff_mutation_allowed" "true" "$(jq -r '.mutation_allowed' <<< "$handoff_with_flags")"
run_test "handoff_no_blockers" "0" "$(jq '.blockers | length' <<< "$handoff_with_flags")"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi

echo "All component release evidence tests passed ($PASS_COUNT assertions)."
