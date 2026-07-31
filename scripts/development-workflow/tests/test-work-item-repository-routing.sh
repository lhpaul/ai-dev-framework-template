#!/usr/bin/env bash
# test-work-item-repository-routing.sh - one-target work-item routing tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/development-workflow/work-item-repository-routing.py"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/1354-routing"
CONFIG="$FIXTURE_DIR/config-workflow-hub.json"

PASS_COUNT=0
FAIL_COUNT=0

run_case() {
  local name="$1"
  local fixture="$2"
  local expression="$3"
  local output

  output="$(python3 "$CLASSIFIER" --config "$CONFIG" --fixture "$FIXTURE_DIR/$fixture" --json)"
  if jq -e "$expression" >/dev/null <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

contract_expression='
  (.schema_version == "work_item_repository_routing.v1")
  and (.outcome_code | type == "string")
  and (.display_label | type == "string")
  and (.continue_allowed | type == "boolean")
  and has("selected_product_repo_key")
  and (.artifact_owner | IN("selected_product_repository", "hub_repository", "current_repository", "none"))
  and has("stop_reason")
  and has("required_human_action")
  and (.configured_product_repo_keys == ["admin-portal", "mobile-app"])
  and (.selected_product_repo_keys | type == "array")
  and (.fingerprint | test("^sha256:[0-9a-f]{64}$"))
'

run_case "product_owned_contract" "product-owned.json" \
  "$contract_expression and .outcome_code == \"product_owned\" and .continue_allowed == true and .selected_product_repo_key == \"mobile-app\""
run_case "product_owned_peer_contract" "product-owned-admin-portal.json" \
  "$contract_expression and .outcome_code == \"product_owned\" and .continue_allowed == true and .selected_product_repo_key == \"admin-portal\""
run_case "missing_target_contract" "missing-target.json" \
  "$contract_expression and .outcome_code == \"missing_target\" and .continue_allowed == false and .selected_product_repo_key == null"
run_case "ambiguous_target_contract" "ambiguous-target.json" \
  "$contract_expression and .outcome_code == \"ambiguous_target\" and .continue_allowed == false and .required_human_action != null"
run_case "multiple_targets_contract" "multiple-targets.json" \
  "$contract_expression and .outcome_code == \"multiple_targets\" and .continue_allowed == false and (.selected_product_repo_keys == [\"admin-portal\", \"mobile-app\"])"
run_case "hub_only_contract" "hub-only.json" \
  "$contract_expression and .outcome_code == \"hub_only\" and .continue_allowed == true and .artifact_owner == \"hub_repository\""
run_case "unsupported_mode_contract" "unsupported-mode.json" \
  "(.schema_version == \"work_item_repository_routing.v1\") and .outcome_code == \"unsupported_mode\" and .continue_allowed == false and .artifact_owner == \"none\" and .stop_reason != null and .required_human_action != null"

single_output="$(python3 "$CLASSIFIER" --fixture "$FIXTURE_DIR/single-repo.json" --json)"
if jq -e '
  .outcome_code == "single_repo"
  and .continue_allowed == true
  and .artifact_owner == "current_repository"
  and has("selected_product_repo_key")
  and .selected_product_repo_key == null
' >/dev/null <<< "$single_output"; then
  echo "PASS: single_repo_contract"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: single_repo_contract"
  printf '%s\n' "$single_output"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

error_file="$(mktemp)"
set +e
python3 "$CLASSIFIER" --config "$FIXTURE_DIR/missing-config.json" --fixture "$FIXTURE_DIR/product-owned.json" --json >"$error_file" 2>&1
missing_status=$?
set -e
if [ "$missing_status" -eq 2 ]; then
  echo "PASS: malformed_or_unreadable_config_exits_2"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: malformed_or_unreadable_config_exits_2"
  cat "$error_file"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
rm -f "$error_file"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
