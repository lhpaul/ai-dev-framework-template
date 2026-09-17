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
  --component-tag mobile-v1.18.0 \
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
run_test "evidence_component_tag" "mobile-v1.18.0" "$(jq -r '.component_tag' <<< "$evidence_json")"
run_test "evidence_written" "component_release_evidence.v1" "$(jq -r '.schema_version' "$evidence_file")"

# Reject a Git-valid but unrelated release branch instead of accepting it
# just because it passes git check-ref-format.
run_fails_contains \
  "evidence_rejects_branch_pattern_mismatch" \
  "does not match the target release_branch_pattern" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$target_file" \
    --binding-file "$binding_file" \
    --release-branch "totally/wrong" \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# Reproduce the fabricated-milestone gap: evidence rendered without
# --component-tag (the legacy/optional path -- still supported) never binds
# a tag, so apply-component/inspect-component must not accept an arbitrary
# caller-supplied --component-tag against it.
untagged_evidence_file="$TMP_ROOT/untagged-evidence.json"
bash "$EVIDENCE_HELPER" \
  --target-file "$target_file" \
  --binding-file "$binding_file" \
  --release-branch mobile-app/release/v1.18.0 \
  --release-outcome completed \
  --ci-outcome passed \
  --deployment-outcome recorded \
  --cleanup-outcome complete \
  --hub-tracker-ref "#1356" \
  --output "$untagged_evidence_file" \
  --json >/dev/null
run_test "untagged_evidence_has_no_component_tag" "null" "$(jq -r '.component_tag' "$untagged_evidence_file")"

fabricated_milestone_output="$(bash "$MILESTONE_HELPER" inspect-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo mobile-app \
  --component-tag "fabricated-v99.0.0" \
  --evidence-file "$untagged_evidence_file" \
  --hub-tracker-reconciliation-outcome complete \
  --child-release-state released \
  --json)"
run_test "fabricated_tag_rejected_outcome" "component_target_mismatch" "$(jq -r '.reconciliation_outcome' <<< "$fabricated_milestone_output")"
run_test "fabricated_tag_rejected_mutation_disallowed" "false" "$(jq -r '.mutation_allowed' <<< "$fabricated_milestone_output")"
run_contains "fabricated_tag_rejected_blocker" "component_tag_unbound" "$fabricated_milestone_output"

# A caller-supplied tag that disagrees with a real, bound evidence tag must
# still be rejected (not just the "no tag at all" case above).
mismatched_tag_output="$(bash "$MILESTONE_HELPER" inspect-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo mobile-app \
  --component-tag "fabricated-v99.0.0" \
  --evidence-file "$evidence_file" \
  --hub-tracker-reconciliation-outcome complete \
  --child-release-state released \
  --json)"
run_test "mismatched_bound_tag_rejected_outcome" "component_target_mismatch" "$(jq -r '.reconciliation_outcome' <<< "$mismatched_tag_output")"
run_contains "mismatched_bound_tag_rejected_blocker" "component_tag_mismatch" "$mismatched_tag_output"

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

# --- #1529 trust-boundary producer cases (T1-T6i, T27) ---

common_evidence_args=(
  --target-file "$target_file"
  --binding-file "$binding_file"
  --release-branch mobile-app/release/v1.18.0
  --release-outcome completed
  --ci-outcome passed
  --deployment-outcome recorded
  --cleanup-outcome complete
  --hub-tracker-ref "#1356"
)

# Capture helper output without aborting under set -e (needed for red-before-green).
capture_evidence() {
  local __out_var="$1"
  local __status_var="$2"
  shift 2
  local __output="" __status=0
  set +e
  __output="$("$@" 2>&1)"
  __status=$?
  set -e
  printf -v "$__out_var" '%s' "$__output"
  printf -v "$__status_var" '%s' "$__status"
}

# T1: --component-version supplied is emitted
capture_evidence t1_json t1_status bash "$EVIDENCE_HELPER" \
  "${common_evidence_args[@]}" \
  --component-tag mobile-v1.18.0 \
  --component-version v99.0.0 \
  --json
if [ "$t1_status" -eq 0 ]; then
  run_test "T1_component_version_emitted" "v99.0.0" "$(jq -r '.component_version' <<< "$t1_json")"
else
  run_test "T1_component_version_emitted" "v99.0.0" "exit_${t1_status}:${t1_json}"
fi

# T2: omitted --component-version emits JSON null; full 16-key list
capture_evidence t2_json t2_status bash "$EVIDENCE_HELPER" \
  "${common_evidence_args[@]}" \
  --component-tag mobile-v1.18.0 \
  --json
if [ "$t2_status" -eq 0 ]; then
  run_test "T2_component_version_null" "null" "$(jq -c '.component_version' <<< "$t2_json")"
  EXPECTED_KEYS="artifact_owners,canonical_repository_identity,ci_outcome,cleanup_outcome,component_tag,component_version,contract_revision,deployment_outcome,hub_tracker_ref,release_branch,release_correlation_key,release_outcome,routing_outcome,schema_version,selected_product_repo_key,target_binding"
  run_test "T2_emitted_key_list" "$EXPECTED_KEYS" "$(jq -r 'keys | join(",")' <<< "$t2_json")"
else
  run_test "T2_component_version_null" "null" "exit_${t2_status}:${t2_json}"
  run_test "T2_emitted_key_list" "16_keys" "exit_${t2_status}"
fi

# T3: charset reject on --component-tag
run_fails_contains \
  "T3_component_tag_charset" \
  "--component-tag" \
  bash "$EVIDENCE_HELPER" \
    "${common_evidence_args[@]}" \
    --component-tag "bad tag" \
    --json

# T4: charset reject on --component-version (genuine red after D1, green after D3)
run_fails_contains \
  "T4_component_version_charset" \
  "--component-version" \
  bash "$EVIDENCE_HELPER" \
    "${common_evidence_args[@]}" \
    --component-version "1.0.0;rm" \
    --json

# Helper: write matching empty-identity target+binding pair
write_identity_pair() {
  local out_target="$1"
  local jq_expr="$2"
  jq "$jq_expr" "$target_file" > "$out_target"
  cp "$out_target" "${out_target%.json}-binding.json"
}

# T5: empty contract_revision
t5_target="$TMP_ROOT/t5-target.json"
write_identity_pair "$t5_target" '.contract_revision = ""'
run_fails_contains \
  "T5_empty_contract_revision" \
  "missing required identity field: contract_revision" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t5_target" \
    --binding-file "${t5_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T5b: empty canonical_repository_identity
t5b_target="$TMP_ROOT/t5b-target.json"
write_identity_pair "$t5b_target" '.canonical_repository_identity = ""'
run_fails_contains \
  "T5b_empty_canonical_identity" \
  "missing required identity field: canonical_repository_identity" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t5b_target" \
    --binding-file "${t5b_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6: empty release_correlation_key
t6_target="$TMP_ROOT/t6-target.json"
write_identity_pair "$t6_target" '.release_correlation_key = ""'
run_fails_contains \
  "T6_empty_release_correlation_key" \
  "missing required identity field: release_correlation_key" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6_target" \
    --binding-file "${t6_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# Pattern-omitted base for routing/null-key cases (T6a-T6i)
write_routing_pair() {
  local out_target="$1"
  local jq_expr="$2"
  jq "$jq_expr | .release_branch_pattern = \"\"" "$target_file" > "$out_target"
  cp "$out_target" "${out_target%.json}-binding.json"
}

# T6a: routed + null selected_product_repo_key
t6a_target="$TMP_ROOT/t6a-target.json"
write_routing_pair "$t6a_target" '.routing_outcome = "component_release_routed" | .selected_product_repo_key = null'
run_fails_contains \
  "T6a_routed_null_selected_key" \
  "missing required identity field: selected_product_repo_key" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6a_target" \
    --binding-file "${t6a_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6b: single_repo_release + null key (green-by-construction / exempt)
t6b_target="$TMP_ROOT/t6b-target.json"
write_routing_pair "$t6b_target" '.routing_outcome = "single_repo_release" | .selected_product_repo_key = null'
capture_evidence t6b_json t6b_status bash "$EVIDENCE_HELPER" \
  --target-file "$t6b_target" \
  --binding-file "${t6b_target%.json}-binding.json" \
  --release-branch mobile-app/release/v1.18.0 \
  --release-outcome completed \
  --ci-outcome passed \
  --deployment-outcome recorded \
  --cleanup-outcome complete \
  --hub-tracker-ref "#1356" \
  --json
if [ "$t6b_status" -eq 0 ]; then
  run_test "T6b_single_repo_null_key" "null" "$(jq -c '.selected_product_repo_key' <<< "$t6b_json")"
else
  run_test "T6b_single_repo_null_key" "null" "exit_${t6b_status}:${t6b_json}"
fi

# T6c: empty routing_outcome
t6c_target="$TMP_ROOT/t6c-target.json"
write_identity_pair "$t6c_target" '.routing_outcome = ""'
run_fails_contains \
  "T6c_empty_routing_outcome" \
  "missing required identity field: routing_outcome" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6c_target" \
    --binding-file "${t6c_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6d: each artifact_owners sub-field emptied
for owner_field in release ci github_release deployment cleanup tracker; do
  t6d_target="$TMP_ROOT/t6d-${owner_field}-target.json"
  write_identity_pair "$t6d_target" ".artifact_owners.${owner_field} = \"\""
  run_fails_contains \
    "T6d_empty_artifact_owners_${owner_field}" \
    "missing required identity field: artifact_owners" \
    bash "$EVIDENCE_HELPER" \
      --target-file "$t6d_target" \
      --binding-file "${t6d_target%.json}-binding.json" \
      --release-branch mobile-app/release/v1.18.0 \
      --release-outcome completed \
      --ci-outcome passed \
      --deployment-outcome recorded \
      --cleanup-outcome complete \
      --hub-tracker-ref "#1356" \
      --json
done

# T6e: single_repo_release with bound non-null key
t6e_target="$TMP_ROOT/t6e-target.json"
write_routing_pair "$t6e_target" '.routing_outcome = "single_repo_release" | .selected_product_repo_key = "mobile-app"'
run_fails_contains \
  "T6e_single_repo_bound_key" \
  "must not bind selected_product_repo_key under single_repo_release routing" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6e_target" \
    --binding-file "${t6e_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6f: single_repo_release with empty-string key
t6f_target="$TMP_ROOT/t6f-target.json"
write_routing_pair "$t6f_target" '.routing_outcome = "single_repo_release" | .selected_product_repo_key = ""'
run_fails_contains \
  "T6f_single_repo_empty_string_key" \
  "must not bind selected_product_repo_key under single_repo_release routing" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6f_target" \
    --binding-file "${t6f_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6g: single_repo_release with key absent
t6g_target="$TMP_ROOT/t6g-target.json"
write_routing_pair "$t6g_target" '.routing_outcome = "single_repo_release" | del(.selected_product_repo_key)'
run_fails_contains \
  "T6g_single_repo_missing_key" \
  "must not bind selected_product_repo_key under single_repo_release routing" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6g_target" \
    --binding-file "${t6g_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6h: unrecognized routing_outcome
t6h_target="$TMP_ROOT/t6h-target.json"
write_routing_pair "$t6h_target" '.routing_outcome = "unknown" | .selected_product_repo_key = null'
run_fails_contains \
  "T6h_unknown_routing_outcome" \
  "routing_outcome must be component_release_routed or single_repo_release, got: unknown" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6h_target" \
    --binding-file "${t6h_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T6i: routed with selected_product_repo_key as JSON array
t6i_target="$TMP_ROOT/t6i-target.json"
write_routing_pair "$t6i_target" '.routing_outcome = "component_release_routed" | .selected_product_repo_key = []'
run_fails_contains \
  "T6i_routed_array_selected_key" \
  "missing required identity field: selected_product_repo_key" \
  bash "$EVIDENCE_HELPER" \
    --target-file "$t6i_target" \
    --binding-file "${t6i_target%.json}-binding.json" \
    --release-branch mobile-app/release/v1.18.0 \
    --release-outcome completed \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "#1356" \
    --json

# T27: SemVer build-metadata + accepted in --component-version
capture_evidence t27_json t27_status bash "$EVIDENCE_HELPER" \
  "${common_evidence_args[@]}" \
  --component-version "v1.4.0+build.7" \
  --json
if [ "$t27_status" -eq 0 ]; then
  run_test "T27_component_version_plus_build" "v1.4.0+build.7" "$(jq -r '.component_version' <<< "$t27_json")"
else
  run_test "T27_component_version_plus_build" "v1.4.0+build.7" "exit_${t27_status}:${t27_json}"
fi

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi

echo "All component release evidence tests passed ($PASS_COUNT assertions)."
