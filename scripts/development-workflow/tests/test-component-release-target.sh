#!/usr/bin/env bash
# test-component-release-target.sh - component release target adapter tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
TARGET_HELPER="$REPO_ROOT/scripts/development-workflow/component-release-target.sh"
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

run_not_equal() {
  local name="$1"
  local left="$2"
  local right="$3"
  if [ "$left" != "$right" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected values to differ, both were '${left}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo ""
echo "=== Component release target ==="

fixture_json="$(bash "$FIXTURE_HELPER" --work-dir "$TMP_ROOT/fixtures" --json)"
single_repo="$(jq -r '.single_repo.path // .single_repo' <<< "$fixture_json")"
hub_repo="$(jq -r '.workflow_hub.path // .hub_repo' <<< "$fixture_json")"
bad_release_repo="$(jq -r '.bad_release_repo' <<< "$fixture_json")"

single_output="$(bash "$TARGET_HELPER" --repo-root "$single_repo")"
run_contains "single_repo_shell_outcome" "ROUTING_OUTCOME=single_repo_release" "$single_output"
run_contains "single_repo_shell_allowed" "MUTATION_ALLOWED=true" "$single_output"
run_contains "single_repo_shell_release_owner" "ARTIFACT_OWNER_RELEASE=current_repository" "$single_output"
run_contains "single_repo_shell_revision" "CONTRACT_REVISION=sha256:" "$single_output"

bad_single_repo="$TMP_ROOT/bad-single-repo"
cp -R "$single_repo" "$bad_single_repo"
python3 - "$bad_single_repo/.ai-dev-workflow.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("branch_pattern: release/v{version}", "branch_pattern: release/static"), encoding="utf-8")
PY
bad_single_json="$(bash "$TARGET_HELPER" --repo-root "$bad_single_repo" --json)"
run_test "single_repo_invalid_contract_outcome" "invalid_release_contract" "$(jq -r '.routing_outcome' <<< "$bad_single_json")"
run_test "single_repo_invalid_contract_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$bad_single_json")"

component_json="$(bash "$TARGET_HELPER" --repo-root "$hub_repo" --repo mobile-app --json)"
run_test "component_json_schema" "component_release_target.v1" "$(jq -r '.schema_version' <<< "$component_json")"
run_test "component_json_outcome" "component_release_routed" "$(jq -r '.routing_outcome' <<< "$component_json")"
run_test "component_json_allowed" "true" "$(jq -r '.mutation_allowed' <<< "$component_json")"
run_test "component_json_selected_repo" "mobile-app" "$(jq -r '.selected_product_repo_key' <<< "$component_json")"
run_test "component_json_identity" "example/mobile-app" "$(jq -r '.canonical_repository_identity' <<< "$component_json")"
run_test "component_json_local_source" "local_override" "$(jq -r '.local_checkout.source' <<< "$component_json")"
run_test "component_json_release_base" "release-base" "$(jq -r '.release_base' <<< "$component_json")"
run_test "component_json_release_owner" "product_repository" "$(jq -r '.artifact_owners.release' <<< "$component_json")"
run_test "component_json_github_release_owner" "product_repository" "$(jq -r '.artifact_owners.github_release' <<< "$component_json")"
run_test "component_json_tracker_owner" "hub_repository" "$(jq -r '.artifact_owners.tracker' <<< "$component_json")"
run_contains "component_json_contract_revision" "sha256:" "$(jq -r '.contract_revision' <<< "$component_json")"
run_contains "component_json_correlation_key" "sha256:" "$(jq -r '.release_correlation_key' <<< "$component_json")"
component_json_repeat="$(bash "$TARGET_HELPER" --repo-root "$hub_repo" --repo mobile-app --json)"
run_test "component_contract_revision_stable" "$(jq -r '.contract_revision' <<< "$component_json")" "$(jq -r '.contract_revision' <<< "$component_json_repeat")"
run_test "component_correlation_key_stable" "$(jq -r '.release_correlation_key' <<< "$component_json")" "$(jq -r '.release_correlation_key' <<< "$component_json_repeat")"

variant_hub="$(dirname "$hub_repo")/revision-variant-hub"
cp -R "$hub_repo" "$variant_hub"
python3 - "$variant_hub/.ai-dev-workflow.yaml" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(text.replace("release-base", "release-alt"), encoding="utf-8")
PY
variant_json="$(bash "$TARGET_HELPER" --repo-root "$variant_hub" --repo mobile-app --json)"
run_test "component_variant_json_outcome" "component_release_routed" "$(jq -r '.routing_outcome' <<< "$variant_json")"
run_not_equal "component_contract_revision_changes_with_base" "$(jq -r '.contract_revision' <<< "$component_json")" "$(jq -r '.contract_revision' <<< "$variant_json")"
run_not_equal "component_correlation_key_changes_with_revision" "$(jq -r '.release_correlation_key' <<< "$component_json")" "$(jq -r '.release_correlation_key' <<< "$variant_json")"

missing_json="$(bash "$TARGET_HELPER" --repo-root "$hub_repo" --json)"
run_test "missing_repo_outcome" "missing_product_selection" "$(jq -r '.routing_outcome' <<< "$missing_json")"
run_test "missing_repo_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$missing_json")"
run_test "missing_repo_no_product_owner" "not_applicable" "$(jq -r '.artifact_owners.release' <<< "$missing_json")"

multiple_json="$(bash "$TARGET_HELPER" --repo-root "$hub_repo" --repo mobile-app --repo admin-portal --json)"
run_test "multiple_repo_outcome" "multiple_product_targets" "$(jq -r '.routing_outcome' <<< "$multiple_json")"
run_test "multiple_repo_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$multiple_json")"

unknown_json="$(bash "$TARGET_HELPER" --repo-root "$hub_repo" --repo unknown --json)"
run_test "unknown_repo_outcome" "unknown_product_repository" "$(jq -r '.routing_outcome' <<< "$unknown_json")"
run_test "unknown_repo_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$unknown_json")"

nonexistent_local_hub="$(dirname "$hub_repo")/nonexistent-local-hub"
cp -R "$hub_repo" "$nonexistent_local_hub"
cat > "$nonexistent_local_hub/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: mobile-app
    local_path: /definitely/not/here
YAML
nonexistent_local_json="$(bash "$TARGET_HELPER" --repo-root "$nonexistent_local_hub" --repo mobile-app --json)"
run_test "nonexistent_local_path_outcome" "unavailable_product_repository_checkout" "$(jq -r '.routing_outcome' <<< "$nonexistent_local_json")"
run_test "nonexistent_local_path_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$nonexistent_local_json")"

rm "$hub_repo/.ai-dev-workflow.local.yaml"
unavailable_json="$(bash "$TARGET_HELPER" --repo-root "$hub_repo" --repo mobile-app --json)"
run_test "unavailable_checkout_outcome" "unavailable_product_repository_checkout" "$(jq -r '.routing_outcome' <<< "$unavailable_json")"
run_test "unavailable_checkout_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$unavailable_json")"

invalid_json="$(bash "$TARGET_HELPER" --repo-root "$bad_release_repo" --repo mobile-app --json)"
run_test "invalid_contract_outcome" "invalid_release_contract" "$(jq -r '.routing_outcome' <<< "$invalid_json")"
run_test "invalid_contract_disallows_mutation" "false" "$(jq -r '.mutation_allowed' <<< "$invalid_json")"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAILURES: $FAIL_COUNT"
  exit 1
fi

echo "All component release target tests passed ($PASS_COUNT assertions)."
