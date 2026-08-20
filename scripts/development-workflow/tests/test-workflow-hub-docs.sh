#!/usr/bin/env bash
# test-workflow-hub-docs.sh - smoke checks for workflow-hub adoption docs.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)" || {
  echo "Error: could not resolve repository root." >&2
  exit 1
}

SETUP_DOC="$REPO_ROOT/docs/workflow/development-workflow/workflow-hub-setup.md"
INJECTION_DOC="$REPO_ROOT/docs/workflow/development-workflow/product-repo-injection.md"
FLOW_DOC="$REPO_ROOT/docs/workflow/development-workflow/cross-repo-pr-flow.md"
README_DOC="$REPO_ROOT/docs/workflow/development-workflow/README.md"
MODES_DOC="$REPO_ROOT/docs/workflow/development-workflow/repository-modes.md"
ADOPTION_DOC="$REPO_ROOT/docs/workflow/development-workflow/multi-repo-release-adoption.md"
SCRIPTS_README_DOC="$REPO_ROOT/scripts/development-workflow/README.md"
PREPARE_RELEASE_DOC="$REPO_ROOT/docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md"
PREPARE_RELEASE_SKILL="$REPO_ROOT/.agents/skills/prepare-release/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0

run_equals() {
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
  local file="$3"
  if grep -Fq -- "$expected" "$file"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$file' to contain '${expected}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_not_contains_any() {
  local name="$1"
  local pattern="$2"
  shift 2
  local output=""
  local status=0

  set +e
  output="$(grep -RInE "$pattern" "$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "FAIL: $name - unexpected match for pattern '$pattern'"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  elif [ "$status" -eq 1 ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - grep failed with status $status"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo ""
echo "=== workflow_hub_docs: required files ==="

run_equals "setup_doc_exists" "yes" "$([ -f "$SETUP_DOC" ] && echo yes || echo no)"
run_equals "injection_doc_exists" "yes" "$([ -f "$INJECTION_DOC" ] && echo yes || echo no)"
run_equals "flow_doc_exists" "yes" "$([ -f "$FLOW_DOC" ] && echo yes || echo no)"
run_equals "adoption_doc_exists" "yes" "$([ -f "$ADOPTION_DOC" ] && echo yes || echo no)"

echo ""
echo "=== workflow_hub_docs: setup guide ==="

run_contains "setup_has_versioned_config" ".ai-dev-workflow.yaml" "$SETUP_DOC"
run_contains "setup_has_local_config" ".ai-dev-workflow.local.yaml" "$SETUP_DOC"
run_contains "setup_has_validate_command" "validate-workflow-config.sh" "$SETUP_DOC"
run_contains "setup_has_status_command" "hub-status.sh --all" "$SETUP_DOC"
run_contains "setup_has_sync_command" "hub-sync-product-repos.sh --all" "$SETUP_DOC"
run_contains "setup_has_smoke_fixture" "test-workflow-hub-smoke-fixtures.sh" "$SETUP_DOC"
run_contains "setup_has_run_location" "Run location: hub checkout." "$SETUP_DOC"
run_contains "setup_links_auth_guide" "integrations/workflow-hub-github-app.md" "$SETUP_DOC"
run_contains "setup_has_release_contract" "The \`release\` block is the product release contract." "$SETUP_DOC"
run_contains "setup_has_release_branch_pattern" "branch_pattern: release/v{version}" "$SETUP_DOC"
run_contains "setup_rejects_release_secrets" "secret names, secret values" "$SETUP_DOC"
run_contains "setup_has_component_release_target" "component-release-target.sh" "$SETUP_DOC"
run_contains "setup_has_component_release_routed" "component_release_routed" "$SETUP_DOC"
run_contains "setup_links_adoption_guide" "multi-repo-release-adoption.md" "$SETUP_DOC"
run_contains "setup_has_adoption_validation" "Adoption validation must pass before release mutation" "$SETUP_DOC"
run_contains "setup_has_historical_no_rewrite" "historical no-rewrite" "$SETUP_DOC"

echo ""
echo "=== workflow_hub_docs: product injection guide ==="

run_contains "injection_has_product_mode" "mode: product_repo" "$INJECTION_DOC"
run_contains "injection_has_selector_command" "select-sync-manifest-entries.py" "$INJECTION_DOC"
run_contains "injection_has_dry_run" "/sync-template --local=../ai-dev-framework-template --dry-run" "$INJECTION_DOC"
run_contains "injection_selects_shared" "shared" "$INJECTION_DOC"
run_contains "injection_selects_product_scope" "product_repo_injection" "$INJECTION_DOC"
run_contains "injection_skips_hub_only" "hub_only" "$INJECTION_DOC"
run_contains "injection_excludes_protocols" "Workflow protocols." "$INJECTION_DOC"
run_contains "injection_has_release_runtime_helper" "scripts/development-workflow/validate-workflow-config.sh" "$INJECTION_DOC"
run_contains "injection_excludes_delivery_coordination" "delivery coordination runbooks" "$INJECTION_DOC"
run_contains "injection_links_adoption_guide" "multi-repo-release-adoption.md" "$INJECTION_DOC"
run_contains "injection_has_product_adoption_evidence" "product-owned release, CI, deployment, and cleanup evidence" "$INJECTION_DOC"

echo ""
echo "=== workflow_hub_docs: cross-repo PR flow ==="

run_contains "flow_has_next_action" "workflow-next-action.sh" "$FLOW_DOC"
run_contains "flow_has_open_product_pr" "open-product-pr.sh" "$FLOW_DOC"
run_contains "flow_has_reviewer_loop" "pr-review-loop.sh" "$FLOW_DOC"
run_contains "flow_has_ci_loop" "pr-ci-loop.sh" "$FLOW_DOC"
run_contains "flow_has_cleanup" "post-merge-cleanup.sh" "$FLOW_DOC"
run_contains "flow_has_ready_labels" "readiness labels" "$FLOW_DOC"
run_contains "flow_links_protocol_90" "90-batch-orchestrate-work-protocol.md" "$FLOW_DOC"
run_contains "flow_links_protocol_91" "91-orchestrate-work-protocol.md" "$FLOW_DOC"
run_contains "flow_links_protocol_93" "93-automated-reviewer-loop-protocol.md" "$FLOW_DOC"
run_contains "flow_links_protocol_94" "94-batch-merge-protocol.md" "$FLOW_DOC"
run_contains "flow_has_release_artifact_owners" "Release Artifact Owners" "$FLOW_DOC"
run_contains "flow_has_tracker_reconciliation_owner" "Tracker reconciliation evidence" "$FLOW_DOC"
run_contains "flow_has_release_contract_validation" "component-release-target.sh" "$FLOW_DOC"
run_contains "flow_has_release_evidence" "component-release-evidence.sh" "$FLOW_DOC"
run_contains "flow_has_component_milestone_reconciliation" "component-milestone-reconciliation.sh" "$FLOW_DOC"
run_contains "flow_links_adoption_guide" "multi-repo-release-adoption.md" "$FLOW_DOC"
run_contains "flow_has_assurance_evidence" "release assurance evidence" "$FLOW_DOC"
run_contains "flow_requires_validated_assurance" "adoption_status=validated" "$FLOW_DOC"
run_contains "flow_requires_hub_historical_baseline" "hub-owned" "$FLOW_DOC"
run_contains "flow_requires_product_historical_baseline" "product-owned" "$FLOW_DOC"
run_contains "flow_requires_before_release_mutation" "before release mutation proceeds" "$FLOW_DOC"
run_contains "flow_has_single_repo_exemption" 'single_repo` path is exempt' "$FLOW_DOC"
run_contains "modes_has_release_artifact_ownership" "Release Artifact Ownership" "$MODES_DOC"
run_contains "modes_has_product_runtime_scope" "minimum release runtime helpers" "$MODES_DOC"
run_contains "modes_has_component_target_contract" "component_release_target.v1" "$MODES_DOC"
run_contains "modes_has_component_evidence_contract" "component_release_evidence.v1" "$MODES_DOC"
run_contains "modes_has_namespaced_component_milestones" "<product-repo>@<component-tag>" "$MODES_DOC"
run_contains "modes_has_parent_release_status" "release_status" "$MODES_DOC"
run_contains "modes_keeps_parent_milestone_free" "remain milestone-free" "$MODES_DOC"
run_contains "modes_links_adoption_guide" "multi-repo-release-adoption.md" "$MODES_DOC"
run_contains "modes_has_prospective_migration" "adoption is prospective" "$MODES_DOC"
run_contains "modes_has_historical_no_rewrite" "historical no-rewrite baselines" "$MODES_DOC"
run_contains "modes_requires_validated_assurance" "adoption_status=validated" "$MODES_DOC"

echo ""
echo "=== workflow_hub_docs: adoption assurance ==="

run_contains "adoption_has_schema" "multi_repo_release_assurance.v1" "$ADOPTION_DOC"
run_contains "adoption_has_helper" "multi-repo-release-assurance.sh" "$ADOPTION_DOC"
run_contains "adoption_has_outcome_pass" "\`pass\`" "$ADOPTION_DOC"
run_contains "adoption_has_outcome_fail" "\`fail\`" "$ADOPTION_DOC"
run_contains "adoption_has_outcome_blocked" "\`blocked\`" "$ADOPTION_DOC"
run_contains "adoption_has_outcome_skipped" "\`skipped\`" "$ADOPTION_DOC"
run_contains "adoption_has_outcome_retryable" "\`retryable\`" "$ADOPTION_DOC"
run_contains "adoption_has_hub_history" "Hub-owned historical baseline" "$ADOPTION_DOC"
run_contains "adoption_has_product_history" "Product-owned historical baseline" "$ADOPTION_DOC"
run_contains "adoption_has_no_secrets" "no secrets, local paths, or credential references" "$ADOPTION_DOC"
run_contains "adoption_has_aggregation_rule" "Adoption status is \`validated\` only" "$ADOPTION_DOC"
run_contains "adoption_requires_validated_status" "adoption_status=validated" "$ADOPTION_DOC"
run_contains "adoption_requires_before_mutation" "Run the assurance harness before release mutation" "$ADOPTION_DOC"
run_contains "adoption_rejects_missing_evidence" "missing required evidence for a \`pass\` scenario" "$ADOPTION_DOC"
run_contains "adoption_rejects_non_boolean_skip" "approved_skipped\` must be a JSON boolean" "$ADOPTION_DOC"
run_contains "prepare_release_links_adoption" "multi-repo-release-adoption.md" "$PREPARE_RELEASE_DOC"
run_contains "prepare_release_has_reuse_rule" "may reuse persisted validation" "$PREPARE_RELEASE_DOC"
run_contains "prepare_skill_mentions_assurance" "assurance is validated with unchanged" "$PREPARE_RELEASE_SKILL"
run_contains "scripts_readme_has_assurance_helper" "multi-repo-release-assurance.sh" "$SCRIPTS_README_DOC"
run_contains "scripts_readme_has_assurance_schema" "multi_repo_release_assurance.v1" "$SCRIPTS_README_DOC"

echo ""
echo "=== workflow_hub_docs: troubleshooting and examples ==="

combined_docs=("$SETUP_DOC" "$INJECTION_DOC" "$FLOW_DOC" "$ADOPTION_DOC")
run_contains "example_hub_present" "faind-workflow-hub" "$SETUP_DOC"
run_contains "example_mobile_present" "faind-mobile-app" "$SETUP_DOC"
run_contains "example_admin_present" "faind-admin-portal" "$SETUP_DOC"
run_contains "troubleshoot_missing_checkout" "Missing Product Checkout" "$FLOW_DOC"
run_contains "troubleshoot_dirty_repo" "Dirty Product Repo" "$FLOW_DOC"
run_contains "troubleshoot_missing_credentials" "Missing App Credentials" "$FLOW_DOC"
run_contains "troubleshoot_failed_ci" "Failed CI" "$FLOW_DOC"
run_contains "troubleshoot_reviewer_loop" "Reviewer-Loop Failures" "$FLOW_DOC"
run_contains "readme_links_setup" "workflow-hub-setup.md" "$README_DOC"
run_contains "readme_links_injection" "product-repo-injection.md" "$README_DOC"
run_contains "readme_links_flow" "cross-repo-pr-flow.md" "$README_DOC"
run_contains "modes_links_setup" "workflow-hub-setup.md" "$MODES_DOC"

run_not_contains_any \
  "docs_avoid_unsafe_commands" \
  'git reset --hard|push --force|--force-with-lease|ambient token fallback|unrelated ambient token' \
  "${combined_docs[@]}"

run_not_contains_any \
  "docs_avoid_private_details" \
  'Leasity|RADAR|kids-safety|baumsystem|lhpaul/|op://|BEGIN .*PRIVATE KEY|ghp_|github_pat_|token=' \
  "${combined_docs[@]}"

echo ""
echo "workflow-hub docs smoke tests complete: $PASS_COUNT passed, $FAIL_COUNT failed."

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
