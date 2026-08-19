#!/usr/bin/env bash
# test-component-milestone-reconciliation.sh - component milestone reconciliation tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/component-milestone-reconciliation.sh"
FIXTURE_HELPER="$REPO_ROOT/scripts/development-workflow/tests/setup-component-milestone-fixture.sh"

for tool in jq git python3 rg; do
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

gh_log_hash() {
  git hash-object "$GH_CALL_LOG"
}

count_gh_calls() {
  local pattern="$1"
  local output status
  set +e
  output="$(rg -c -- "$pattern" "$GH_CALL_LOG" 2>&1)"
  status=$?
  set -e
  case "$status" in
    0) printf '%s\n' "$output" ;;
    1) printf '%s\n' 0 ;;
    *) printf 'search failed: %s\n' "$output" >&2; return "$status" ;;
  esac
}

echo ""
echo "=== Component milestone reconciliation ==="

fixture_json="$TMP_ROOT/fixtures.json"
bash "$FIXTURE_HELPER" --output-dir "$TMP_ROOT/fixtures" --json > "$fixture_json"

mock_gh_bin="$(jq -r '.mock_gh.bin_dir' "$fixture_json")"
export PATH="$mock_gh_bin:$PATH"
export COMPONENT_MILESTONE_GH_CALL_LOG
export COMPONENT_MILESTONE_MOCK_STATE
COMPONENT_MILESTONE_GH_CALL_LOG="$(jq -r '.mock_gh.call_log' "$fixture_json")"
COMPONENT_MILESTONE_MOCK_STATE="$(jq -r '.mock_gh.state' "$fixture_json")"
GH_CALL_LOG="$COMPONENT_MILESTONE_GH_CALL_LOG"

PARENT_ISSUE="$(jq -r '.issues.parent' "$fixture_json")"
COMPONENT_ISSUE="$(jq -r '.issues.component_child' "$fixture_json")"
DELIVERY_BUNDLE_ISSUE="$(jq -r '.issues.delivery_bundle' "$fixture_json")"
EVIDENCE="$(jq -r '.evidence.complete' "$fixture_json")"
MISMATCHED_EVIDENCE="$(jq -r '.evidence.mismatched_product' "$fixture_json")"
PARTIAL_BUNDLE="$(jq -r '.bundles.partial' "$fixture_json")"
FINALIZED_BUNDLE="$(jq -r '.bundles.finalized' "$fixture_json")"
FINALIZED_INCOMPLETE_BUNDLE="$(jq -r '.bundles.finalized_incomplete' "$fixture_json")"
BLOCKED_BUNDLE="$(jq -r '.bundles.blocked' "$fixture_json")"
CORRECTED_BUNDLE="$(jq -r '.bundles.corrected' "$fixture_json")"
STATUS_WRITE_FAILURE_BUNDLE="$(jq -r '.bundles.status_write_failure' "$fixture_json")"
STATUS_WRITE_FAILURE_TARGET="$(jq -r '.status_write_failure_target' "$fixture_json")"
PRODUCT_REPO="$(jq -r '.product_repo' "$fixture_json")"
COMPONENT_TAG="$(jq -r '.component_tag' "$fixture_json")"
MILESTONE_TITLE="${PRODUCT_REPO}@${COMPONENT_TAG}"
SINGLE_REPO_VERSION="v999.999.999"
SINGLE_REPO_ISSUE=3579

component_ready="$TMP_ROOT/component-ready.json"
"$HELPER" inspect-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$component_ready"

run_test "inspect_schema" "component_milestone_reconciliation.v1" "$(jq -r '.schema_version' "$component_ready")"
run_test "inspect_component_outcome" "component_released" "$(jq -r '.reconciliation_outcome' "$component_ready")"
run_test "inspect_milestone_title" "$MILESTONE_TITLE" "$(jq -r '.milestone_title' "$component_ready")"
run_test "inspect_mutation_allowed" "true" "$(jq -r '.mutation_allowed' "$component_ready")"
run_test "inspect_parent_not_released" "not_released" "$(jq -r '.parent_release_state' "$component_ready")"

component_apply="$TMP_ROOT/component-apply.json"
"$HELPER" apply-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$component_apply"

run_test "apply_component_outcome" "component_released" "$(jq -r '.reconciliation_outcome' "$component_apply")"
run_test "apply_target_issue" "$COMPONENT_ISSUE" "$(jq -r '.milestone_assignment.target_issue' "$component_apply")"
run_test "apply_no_parent_stamp" "false" "$(jq -r '.milestone_assignment.parent_epic_stamped' "$component_apply")"
run_test "apply_component_patch_once" "1" "$(count_gh_calls "issues/${COMPONENT_ISSUE}.*milestone")"
run_test "apply_parent_not_patched" "0" "$(count_gh_calls "issues/${PARENT_ISSUE}.*milestone")"
run_test "apply_delivery_not_patched" "0" "$(count_gh_calls "issues/${DELIVERY_BUNDLE_ISSUE}.*milestone")"

hash_after_apply="$(gh_log_hash)"
"$HELPER" apply-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$TMP_ROOT/component-reapply.json"
run_test "reapply_is_idempotent" "true" "$(jq -r '.idempotent' "$TMP_ROOT/component-reapply.json")"
run_test "reapply_no_mutation_calls" "$hash_after_apply" "$(gh_log_hash)"

set +e
"$HELPER" apply-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$MISMATCHED_EVIDENCE" \
  --json > "$TMP_ROOT/mismatch.json" 2> "$TMP_ROOT/mismatch.err"
mismatch_status=$?
set -e
run_test "mismatch_rejected" "1" "$((mismatch_status == 0 ? 0 : 1))"
run_test "mismatch_outcome" "component_target_mismatch" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/mismatch.json")"
run_test "mismatch_no_mutation" "$hash_after_apply" "$(gh_log_hash)"

while IFS= read -r evidence_case; do
  case_name="$(jq -r '.name' <<< "$evidence_case")"
  expected_outcome="$(jq -r '.expected_outcome' <<< "$evidence_case")"
  product_repo="$(jq -r '.product_repo // empty' <<< "$evidence_case")"
  component_tag="$(jq -r '.component_tag // empty' <<< "$evidence_case")"
  evidence_file="$(jq -r '.evidence_file // empty' <<< "$evidence_case")"
  output_file="$TMP_ROOT/evidence-case-${case_name}.json"
  before_case_hash="$(gh_log_hash)"

  cmd=("$HELPER" apply-component --issue "$COMPONENT_ISSUE" --target-kind component_child --json)
  [ -z "$product_repo" ] || cmd+=(--product-repo "$product_repo")
  [ -z "$component_tag" ] || cmd+=(--component-tag "$component_tag")
  [ -z "$evidence_file" ] || cmd+=(--evidence-file "$evidence_file")

  set +e
  "${cmd[@]}" > "$output_file" 2> "$TMP_ROOT/evidence-case-${case_name}.err"
  case_status=$?
  set -e
  if [ "$case_status" -eq 0 ]; then
    echo "FAIL: evidence_case_${case_name}_rejected - command succeeded"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: evidence_case_${case_name}_rejected"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
  run_test "evidence_case_${case_name}_outcome" "$expected_outcome" "$(jq -r '.reconciliation_outcome' "$output_file")"
  run_test "evidence_case_${case_name}_no_mutation" "$before_case_hash" "$(gh_log_hash)"
done < <(jq -c '.evidence_cases[]' "$fixture_json")

run_fails_contains \
  "invalid_product_repo_rejected" \
  "invalid_product_repository" \
  "$HELPER" apply-component \
    --issue "$COMPONENT_ISSUE" \
    --target-kind component_child \
    --product-repo "mobile app" \
    --component-tag "$COMPONENT_TAG" \
    --evidence-file "$EVIDENCE" \
    --json
run_fails_contains \
  "invalid_component_tag_rejected" \
  "invalid_component_tag" \
  "$HELPER" apply-component \
    --issue "$COMPONENT_ISSUE" \
    --target-kind component_child \
    --product-repo "$PRODUCT_REPO" \
    --component-tag "mobile/v1.4.0" \
    --evidence-file "$EVIDENCE" \
    --json
run_test "invalid_inputs_no_mutation" "$hash_after_apply" "$(gh_log_hash)"

CONFLICT_ISSUE=2468
jq --arg issue "$CONFLICT_ISSUE" '.issues[$issue].milestone = {number:123}' \
  "$COMPONENT_MILESTONE_MOCK_STATE" > "$TMP_ROOT/mock-state-conflict.json"
mv "$TMP_ROOT/mock-state-conflict.json" "$COMPONENT_MILESTONE_MOCK_STATE"
conflict_hash_before="$(gh_log_hash)"
run_fails_contains \
  "milestone_conflict_rejected" \
  "milestone_conflict" \
  "$HELPER" apply-component \
    --issue "$CONFLICT_ISSUE" \
    --target-kind component_child \
    --product-repo "$PRODUCT_REPO" \
    --component-tag "$COMPONENT_TAG" \
    --evidence-file "$EVIDENCE" \
    --json
run_test "milestone_conflict_no_patch" "$conflict_hash_before" "$(gh_log_hash)"

for target_kind in parent_epic delivery_bundle; do
  case "$target_kind" in
    parent_epic) target_issue="$PARENT_ISSUE" ;;
    delivery_bundle) target_issue="$DELIVERY_BUNDLE_ISSUE" ;;
  esac
  run_fails_contains \
    "reject_${target_kind}_milestone" \
    "milestone_target_not_allowed" \
    "$HELPER" apply-component \
      --issue "$target_issue" \
      --target-kind "$target_kind" \
      --product-repo "$PRODUCT_REPO" \
      --component-tag "$COMPONENT_TAG" \
      --evidence-file "$EVIDENCE" \
      --json
done
run_test "target_rejections_no_mutation" "$hash_after_apply" "$(gh_log_hash)"

"$HELPER" inspect-parent --parent-issue "$PARENT_ISSUE" --delivery-manifest "$BLOCKED_BUNDLE" --json > "$TMP_ROOT/parent-blocked.json"
run_test "parent_blocked_outcome" "parent_blocked" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/parent-blocked.json")"
run_test "parent_blocked_state" "blocked" "$(jq -r '.parent_release_state' "$TMP_ROOT/parent-blocked.json")"

"$HELPER" inspect-parent --parent-issue "$PARENT_ISSUE" --delivery-manifest "$PARTIAL_BUNDLE" --json > "$TMP_ROOT/parent-partial.json"
run_test "parent_partial_outcome" "parent_partially_released" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/parent-partial.json")"
run_test "parent_partial_state" "partially_released" "$(jq -r '.parent_release_state' "$TMP_ROOT/parent-partial.json")"

"$HELPER" inspect-parent --parent-issue "$PARENT_ISSUE" --delivery-manifest "$FINALIZED_INCOMPLETE_BUNDLE" --require-finalized --json > "$TMP_ROOT/parent-finalized-incomplete.json"
run_test "parent_finalized_incomplete_outcome" "parent_blocked" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/parent-finalized-incomplete.json")"
run_contains "parent_finalized_incomplete_blocker" "finalized_bundle_has_unreleased_components" "$(cat "$TMP_ROOT/parent-finalized-incomplete.json")"

"$HELPER" inspect-parent --parent-issue "$PARENT_ISSUE" --delivery-manifest "$CORRECTED_BUNDLE" --require-finalized --json > "$TMP_ROOT/parent-corrected.json"
run_test "parent_corrected_outcome" "parent_released" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/parent-corrected.json")"

# The finalized bundle's parent_ref is "#$PARENT_ISSUE"; a different --parent-issue
# must not be accepted as released, even though every component is released.
MISMATCHED_PARENT_ISSUE=999999
"$HELPER" inspect-parent --parent-issue "$MISMATCHED_PARENT_ISSUE" --delivery-manifest "$FINALIZED_BUNDLE" --require-finalized --json > "$TMP_ROOT/parent-identity-mismatch.json"
run_test "parent_identity_mismatch_outcome" "parent_blocked" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/parent-identity-mismatch.json")"
run_test "parent_identity_mismatch_mutation_not_allowed" "false" "$(jq -r '.mutation_allowed' "$TMP_ROOT/parent-identity-mismatch.json")"
run_contains "parent_identity_mismatch_blocker" "parent_identity_mismatch" "$(cat "$TMP_ROOT/parent-identity-mismatch.json")"

parent_identity_mismatch_hash_before="$(git hash-object "$FINALIZED_BUNDLE")"
run_fails_contains \
  "parent_identity_mismatch_apply_rejected" \
  "ERROR_CODE=parent_identity_mismatch" \
  "$HELPER" apply-parent --parent-issue "$MISMATCHED_PARENT_ISSUE" --delivery-manifest "$FINALIZED_BUNDLE" --require-finalized --json
run_test "parent_identity_mismatch_apply_preserves_manifest" "$parent_identity_mismatch_hash_before" "$(git hash-object "$FINALIZED_BUNDLE")"

"$HELPER" apply-parent --parent-issue "$PARENT_ISSUE" --delivery-manifest "$FINALIZED_BUNDLE" --require-finalized --json > "$TMP_ROOT/parent-apply.json"
run_test "parent_apply_outcome" "parent_released" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/parent-apply.json")"
run_test "parent_apply_status" "released" "$(jq -r '.release_status.state' "$TMP_ROOT/parent-apply.json")"
run_test "parent_apply_audit_event" "1" "$(jq -r '[.audit_events[] | select(.event == "parent_release_status_updated")] | length' "$FINALIZED_BUNDLE")"
run_test "parent_apply_no_gh_mutation" "$hash_after_apply" "$(gh_log_hash)"

parent_hash_after_apply="$(git hash-object "$FINALIZED_BUNDLE")"
"$HELPER" apply-parent --parent-issue "$PARENT_ISSUE" --delivery-manifest "$FINALIZED_BUNDLE" --require-finalized --json > "$TMP_ROOT/parent-reapply.json"
run_test "parent_reapply_idempotent" "true" "$(jq -r '.idempotent' "$TMP_ROOT/parent-reapply.json")"
run_test "parent_reapply_no_manifest_change" "$parent_hash_after_apply" "$(git hash-object "$FINALIZED_BUNDLE")"

failure_hash_before="$(git hash-object "$STATUS_WRITE_FAILURE_BUNDLE")"
set +e
"$HELPER" apply-parent \
  --parent-issue "$PARENT_ISSUE" \
  --delivery-manifest "$STATUS_WRITE_FAILURE_BUNDLE" \
  --status-output "$STATUS_WRITE_FAILURE_TARGET" \
  --require-finalized \
  --json > "$TMP_ROOT/parent-write-failure.json" 2> "$TMP_ROOT/parent-write-failure.err"
failure_status=$?
set -e
run_test "parent_status_write_failure_exercised" "1" "$((failure_status == 0 ? 0 : 1))"
run_test "parent_status_failure_preserves_manifest" "$failure_hash_before" "$(git hash-object "$STATUS_WRITE_FAILURE_BUNDLE")"
run_test "parent_status_failure_no_target" "0" "$([ -e "$STATUS_WRITE_FAILURE_TARGET" ] && echo 1 || echo 0)"
run_contains "parent_status_failure_reason" "ERROR_CODE=status_write_failed" "$(cat "$TMP_ROOT/parent-write-failure.err")"

"$HELPER" inspect-component \
  --mode single_repo \
  --issue "$SINGLE_REPO_ISSUE" \
  --target-kind component_child \
  --version "$SINGLE_REPO_VERSION" \
  --json > "$TMP_ROOT/single-repo.json"
run_test "single_repo_outcome" "single_repo_milestone" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/single-repo.json")"
run_test "single_repo_milestone" "$SINGLE_REPO_VERSION" "$(jq -r '.milestone_title' "$TMP_ROOT/single-repo.json")"
run_test "single_repo_no_bundle" "false" "$(jq -r '.requires_delivery_bundle' "$TMP_ROOT/single-repo.json")"

single_hash_before="$(gh_log_hash)"
set +e
"$HELPER" apply-component \
  --mode single_repo \
  --issue "$SINGLE_REPO_ISSUE" \
  --target-kind component_child \
  --version "not-a-version" \
  --json > "$TMP_ROOT/single-repo-invalid.json" 2> "$TMP_ROOT/single-repo-invalid.err"
single_invalid_status=$?
set -e
run_test "single_repo_invalid_version_rejected" "1" "$((single_invalid_status == 0 ? 0 : 1))"
run_test "single_repo_invalid_version_outcome" "component_release_not_ready" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/single-repo-invalid.json")"
run_test "single_repo_invalid_version_no_mutation" "$single_hash_before" "$(gh_log_hash)"

"$HELPER" apply-component \
  --mode single_repo \
  --issue "$SINGLE_REPO_ISSUE" \
  --target-kind component_child \
  --version "$SINGLE_REPO_VERSION" \
  --json > "$TMP_ROOT/single-repo-apply.json"
run_test "single_repo_apply_outcome" "single_repo_milestone" "$(jq -r '.reconciliation_outcome' "$TMP_ROOT/single-repo-apply.json")"
run_test "single_repo_apply_mutates" "1" "$([ "$single_hash_before" != "$(gh_log_hash)" ] && echo 1 || echo 0)"
run_contains "single_repo_log_mentions_version" "$SINGLE_REPO_VERSION" "$(cat "$GH_CALL_LOG")"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi

echo "All component milestone reconciliation tests passed ($PASS_COUNT assertions)."
