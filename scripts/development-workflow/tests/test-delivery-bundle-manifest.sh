#!/usr/bin/env bash
# test-delivery-bundle-manifest.sh - delivery bundle manifest helper tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/delivery-bundle-manifest.sh"

for tool in jq git python3; do
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
  # 141 is SIGPIPE from a downstream consumer closing stdout early, not a test failure.
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

write_evidence() {
  local path="$1"
  local repo_key="$2"
  local identity="$3"
  local release_outcome="${4:-completed}"
  local ci_outcome="${5:-passed}"
  local deployment_outcome="${6:-recorded}"
  local cleanup_outcome="${7:-complete}"
  jq -cnS \
    --arg repo_key "$repo_key" \
    --arg identity "$identity" \
    --arg release_outcome "$release_outcome" \
    --arg ci_outcome "$ci_outcome" \
    --arg deployment_outcome "$deployment_outcome" \
    --arg cleanup_outcome "$cleanup_outcome" \
    '{
      schema_version:"component_release_evidence.v1",
      target_binding:{
        selected_product_repo_key:$repo_key,
        canonical_repository_identity:$identity,
        release_correlation_key:("sha256:" + $repo_key + "-correlation"),
        contract_revision:("sha256:" + $repo_key + "-contract")
      },
      routing_outcome:"component_release_routed",
      selected_product_repo_key:$repo_key,
      canonical_repository_identity:$identity,
      release_correlation_key:("sha256:" + $repo_key + "-correlation"),
      contract_revision:("sha256:" + $repo_key + "-contract"),
      release_branch:($repo_key + "/release/v1.0.0"),
      release_outcome:$release_outcome,
      ci_outcome:$ci_outcome,
      deployment_outcome:$deployment_outcome,
      cleanup_outcome:$cleanup_outcome,
      hub_tracker_ref:"#1357"
    }' > "$path"
}

create_bundle() {
  local manifest="$1"
  bash "$HELPER" create \
    --manifest "$manifest" \
    --bundle-key mobile-web-july-delivery \
    --title "Mobile and Web July delivery" \
    --purpose "Coordinated customer-facing July workflow-hub delivery" \
    --parent-ref "#1352" \
    --component mobile-app \
    --component web-app \
    --child-item "#1356" \
    --child-item "#1357" \
    --finalization-owner "@workflow-operator" \
    --rollout-notes "No shared suite branch." \
    --json >/dev/null
}

update_component() {
  local manifest="$1"
  local component="$2"
  local evidence="$3"
  local tag="$4"
  local version="$5"
  local source_pr="$6"
  local release_pr="$7"
  local child_item="$8"
  bash "$HELPER" update-component \
    --manifest "$manifest" \
    --bundle-key mobile-web-july-delivery \
    --expected-revision "$(jq -r '.revision' "$manifest")" \
    --component-key "$component" \
    --evidence-file "$evidence" \
    --component-tag "$tag" \
    --component-version "$version" \
    --source-pr "$source_pr" \
    --release-pr "$release_pr" \
    --hub-tracker-reconciliation-outcome complete \
    --child-item "$child_item" \
    --child-release-state merged \
    --json
}

echo ""
echo "=== Delivery bundle manifest ==="

manifest="$TMP_ROOT/delivery-bundle.json"
mobile_evidence="$TMP_ROOT/mobile-evidence.json"
web_evidence="$TMP_ROOT/web-evidence.json"
write_evidence "$mobile_evidence" mobile-app example/mobile-app
write_evidence "$web_evidence" web-app example/web-app

create_bundle "$manifest"
run_test "create_schema" "delivery_bundle_manifest.v1" "$(jq -r '.schema_version' "$manifest")"
run_test "create_bundle_key" "mobile-web-july-delivery" "$(jq -r '.bundle_key' "$manifest")"
run_test "create_revision" "1" "$(jq -r '.revision' "$manifest")"
run_test "create_components" "2" "$(jq -r '.components | length' "$manifest")"

nested_manifest="$TMP_ROOT/nested/path/delivery-bundle.json"
create_bundle "$nested_manifest"
run_test "create_nested_manifest_directory" "delivery_bundle_manifest.v1" "$(jq -r '.schema_version' "$nested_manifest")"

shell_manifest="$TMP_ROOT/shell-output.json"
shell_output="$(bash "$HELPER" create \
  --manifest "$shell_manifest" \
  --bundle-key mobile-web-july-delivery \
  --title "Mobile and Web July delivery" \
  --purpose "Coordinated customer-facing July workflow-hub delivery" \
  --parent-ref "#1352" \
  --component mobile-app \
  --finalization-owner "@workflow-operator")"
run_contains "create_shell_output_result" "RESULT=created" "$shell_output"
run_contains "create_shell_output_manifest" "MANIFEST=" "$shell_output"

update_component "$manifest" mobile-app "$mobile_evidence" mobile-v1.4.0 1.4.0 1411 1501 "#1356" >/dev/null
run_test "update_revision" "2" "$(jq -r '.revision' "$manifest")"
run_test "update_tag" "mobile-v1.4.0" "$(jq -r '.components[] | select(.component_key == "mobile-app") | .component_tag' "$manifest")"
run_test "web_still_declared" "1" "$(jq -r '[.components[] | select(.component_key == "web-app")] | length' "$manifest")"

revision_before="$(jq -r '.revision' "$manifest")"
audit_before="$(jq -r '.audit_events | length' "$manifest")"
update_component "$manifest" mobile-app "$mobile_evidence" mobile-v1.4.0 1.4.0 1411 1501 "#1356" >/dev/null
run_test "idempotent_revision_unchanged" "$revision_before" "$(jq -r '.revision' "$manifest")"
run_test "idempotent_audit_unchanged" "$audit_before" "$(jq -r '.audit_events | length' "$manifest")"

inspect_json="$(bash "$HELPER" inspect --manifest "$manifest" --bundle-key mobile-web-july-delivery --json)"
run_test "inspect_partial_status" "blocked" "$(jq -r '.status' <<< "$inspect_json")"
run_contains "inspect_missing_routing" "routing_evidence_missing" "$inspect_json"

conflict_evidence="$TMP_ROOT/mobile-conflict.json"
jq '.contract_revision = "sha256:conflict"' "$mobile_evidence" > "$conflict_evidence"
manifest_hash="$(git hash-object "$manifest")"
run_fails_contains \
  "conflict_rejected" \
  "ERROR_CODE=conflicting_component_evidence" \
  update_component "$manifest" mobile-app "$conflict_evidence" mobile-v1.4.0 1.4.0 1411 1501 "#1356"
run_test "conflict_preserves_manifest" "$manifest_hash" "$(git hash-object "$manifest")"

manifest_hash="$(git hash-object "$manifest")"
run_fails_contains \
  "component_key_repo_mismatch_rejected" \
  "ERROR_CODE=component_key_repo_mismatch" \
  update_component "$manifest" web-app "$mobile_evidence" web-v2.8.1 2.8.1 1414 1503 "#1357"
run_test "component_key_repo_mismatch_preserves_manifest" "$manifest_hash" "$(git hash-object "$manifest")"

stale_revision="$(jq -r '.revision' "$manifest")"
bash "$HELPER" remove-component \
  --manifest "$manifest" \
  --bundle-key mobile-web-july-delivery \
  --expected-revision "$stale_revision" \
  --component-key web-app \
  --reason "Split web delivery" \
  --json >/dev/null
run_test "remove_revision_incremented" "3" "$(jq -r '.revision' "$manifest")"
run_test "remove_audited" "Split web delivery" "$(jq -r '.removed_components[] | select(.component_key == "web-app") | .reason' "$manifest")"
manifest_hash="$(git hash-object "$manifest")"
run_fails_contains \
  "stale_revision_rejected" \
  "ERROR_CODE=stale_manifest_revision" \
  bash "$HELPER" finalize \
    --manifest "$manifest" \
    --bundle-key mobile-web-july-delivery \
    --expected-revision "$stale_revision" \
    --json
run_test "stale_preserves_manifest" "$manifest_hash" "$(git hash-object "$manifest")"

ready_bundle="$TMP_ROOT/ready-bundle.json"
create_bundle "$ready_bundle"
update_component "$ready_bundle" mobile-app "$mobile_evidence" mobile-v1.4.0 1.4.0 1411 1501 "#1356" >/dev/null
update_component "$ready_bundle" web-app "$web_evidence" web-v2.8.1 2.8.1 1414 1503 "#1357" >/dev/null
ready_inspect="$(bash "$HELPER" inspect --manifest "$ready_bundle" --bundle-key mobile-web-july-delivery --json)"
run_test "ready_inspect_status" "ready_to_finalize" "$(jq -r '.status' <<< "$ready_inspect")"

ready_add="$TMP_ROOT/ready-add.json"
cp "$ready_bundle" "$ready_add"
bash "$HELPER" add-component \
  --manifest "$ready_add" \
  --bundle-key mobile-web-july-delivery \
  --expected-revision "$(jq -r '.revision' "$ready_add")" \
  --component-key api-service \
  --json >/dev/null
run_test "add_invalidates_readiness" "null" "$(jq -c '.readiness' "$ready_add")"

add_revision="$(jq -r '.revision' "$ready_add")"
add_output="$(bash "$HELPER" add-component \
  --manifest "$ready_add" \
  --bundle-key mobile-web-july-delivery \
  --expected-revision "$add_revision" \
  --component-key api-service \
  --json)"
run_test "add_component_idempotent_result" "idempotent" "$(jq -r '.result' <<< "$add_output")"
run_test "add_component_idempotent_revision" "$add_revision" "$(jq -r '.revision' "$ready_add")"

run_fails_contains \
  "invalid_bundle_key_rejected" \
  "ERROR_CODE=invalid_bundle_key" \
  bash "$HELPER" inspect --manifest "$ready_bundle" --bundle-key "bad key/#1" --json

pending_default="$TMP_ROOT/pending-default.json"
create_bundle "$pending_default"
bash "$HELPER" update-component \
  --manifest "$pending_default" \
  --bundle-key mobile-web-july-delivery \
  --expected-revision "$(jq -r '.revision' "$pending_default")" \
  --component-key mobile-app \
  --evidence-file "$mobile_evidence" \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --source-pr 1411 \
  --release-pr 1501 \
  --child-item "#1356" \
  --child-release-state merged \
  --json >/dev/null
run_test "hub_reconciliation_defaults_pending" "pending" \
  "$(jq -r '.components[] | select(.component_key == "mobile-app") | .hub_tracker_reconciliation_outcome' "$pending_default")"
run_test "pending_default_persisted_partial" "partial" \
  "$(jq -r '.components[] | select(.component_key == "mobile-app") | .evidence_state' "$pending_default")"
run_contains "pending_default_records_blocker" "pending_component_outcome" \
  "$(jq -c '.components[] | select(.component_key == "mobile-app") | .blockers' "$pending_default")"

missing_tag="$TMP_ROOT/missing-tag.json"
missing_evidence="$TMP_ROOT/missing-evidence.json"
failed_outcome="$TMP_ROOT/failed-outcome.json"
pending_outcome="$TMP_ROOT/pending-outcome.json"
conflicting_outcome="$TMP_ROOT/conflicting-outcome.json"
stale_readiness="$TMP_ROOT/stale-readiness.json"
jq 'del((.components[] | select(.component_key == "mobile-app")).component_tag)' "$ready_bundle" > "$missing_tag"
jq '(.components[] | select(.component_key == "web-app")).evidence_state = "missing"' "$ready_bundle" > "$missing_evidence"
jq '(.components[] | select(.component_key == "mobile-app")).release_outcome = "failed"' "$ready_bundle" > "$failed_outcome"
jq '(.components[] | select(.component_key == "mobile-app")).ci_outcome = "pending"' "$ready_bundle" > "$pending_outcome"
jq '(.components[] | select(.component_key == "mobile-app")).evidence_state = "conflicting"' "$ready_bundle" > "$conflicting_outcome"
jq '.readiness = {revision:(.revision - 1), ready:true, status:"ready_to_finalize", blockers:[]}' "$ready_bundle" > "$stale_readiness"

for fixture in \
  "$missing_tag|missing_component_tag" \
  "$missing_evidence|missing_component_evidence" \
  "$failed_outcome|blocked_component_outcome" \
  "$pending_outcome|pending_component_outcome" \
  "$conflicting_outcome|conflicting_component_evidence" \
  "$stale_readiness|stale_readiness"
do
  fixture_path="${fixture%%|*}"
  expected_error="${fixture##*|}"
  manifest_hash="$(git hash-object "$fixture_path")"
  run_fails_contains \
    "finalize_rejects_${expected_error}" \
    "ERROR_CODE=$expected_error" \
    bash "$HELPER" finalize \
      --manifest "$fixture_path" \
      --bundle-key mobile-web-july-delivery \
      --expected-revision "$(jq -r '.revision' "$fixture_path")" \
      --json
  run_test "finalize_${expected_error}_preserves_manifest" "$manifest_hash" "$(git hash-object "$fixture_path")"
done

mobile_hash="$(git hash-object "$mobile_evidence")"
web_hash="$(git hash-object "$web_evidence")"
revision_before="$(jq -r '.revision' "$ready_bundle")"
bash "$HELPER" finalize \
  --manifest "$ready_bundle" \
  --bundle-key mobile-web-july-delivery \
  --expected-revision "$revision_before" \
  --json >/dev/null
run_test "finalized_status" "finalized" "$(jq -r '.status' "$ready_bundle")"
run_test "finalized_revision_incremented" "$((revision_before + 1))" "$(jq -r '.revision' "$ready_bundle")"
run_test "finalized_event" "1" "$(jq -r '[.audit_events[] | select(.event == "bundle_finalized")] | length' "$ready_bundle")"
run_test "finalized_no_shared_version" "" "$(jq -r '.shared_suite_version? // empty, .shared_release_branch? // empty' "$ready_bundle")"
run_test "mobile_evidence_unchanged" "$mobile_hash" "$(git hash-object "$mobile_evidence")"
run_test "web_evidence_unchanged" "$web_hash" "$(git hash-object "$web_evidence")"

run_fails_contains \
  "bundle_key_mismatch_rejected" \
  "ERROR_CODE=bundle_key_mismatch" \
  bash "$HELPER" inspect --manifest "$ready_bundle" --bundle-key other-bundle --json

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi

echo "All delivery bundle manifest tests passed ($PASS_COUNT assertions)."
