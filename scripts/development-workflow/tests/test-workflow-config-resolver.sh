#!/usr/bin/env bash
# test-workflow-config-resolver.sh - repository-context config resolver tests.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-config-resolver.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py"
VALIDATOR="$REPO_ROOT/scripts/development-workflow/validate-workflow-config.sh"

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

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

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
  local output=""
  local status=0

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

fixture_dir() {
  local name="$1"
  local path="$TMP_ROOT/$name"
  mkdir -p "$path"
  printf '%s\n' "$path"
}

echo ""
echo "=== Workflow config resolver ==="

missing_mode_dir="$(fixture_dir missing-mode)"
missing_mode_output="$(python3 "$RESOLVER" mode --repo-root "$missing_mode_dir")"
run_test "missing_mode_defaults_single_repo" "WORKFLOW_MODE=single_repo" "$missing_mode_output"
missing_mode_wrapper_output="$(workflow_repository_mode "$missing_mode_dir")"
run_test "workflow_repository_mode_wrapper" "WORKFLOW_MODE=single_repo" "$missing_mode_wrapper_output"

single_repo_dir="$(fixture_dir single-repo)"
mkdir -p "$single_repo_dir/.git"
cat > "$single_repo_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: single_repo
YAML
cat > "$single_repo_dir/.git/config" <<'GITCONFIG'
[remote "origin"]
  url = https://github.com/example/mobile-app.extra.git
GITCONFIG
single_repo_output="$(workflow_repository_context "" "$single_repo_dir")"
run_contains "single_repo_context_mode" "WORKFLOW_MODE=single_repo" "$single_repo_output"
run_contains "single_repo_context_github_repo" "TARGET_GITHUB_REPO=example/mobile-app.extra" "$single_repo_output"
run_contains "single_repo_context_local_path" "TARGET_LOCAL_PATH=$single_repo_dir" "$single_repo_output"
run_contains "single_repo_context_default_branch" "TARGET_DEFAULT_BRANCH=main" "$single_repo_output"
run_contains "single_repo_release_default_tag_owner" "TARGET_RELEASE_TAG_OWNER=current_repo" "$single_repo_output"
run_contains "single_repo_release_default_changelog_owner" "TARGET_RELEASE_CHANGELOG_OWNER=current_repo" "$single_repo_output"
run_contains "single_repo_release_default_tracker_owner" "TARGET_RELEASE_TRACKER_RECONCILIATION_OWNER=current_repo" "$single_repo_output"
run_contains "single_repo_release_contract_revision" "TARGET_RELEASE_CONTRACT_REVISION=sha256:" "$single_repo_output"
validator_output="$(bash "$VALIDATOR" --repo-root "$single_repo_dir")"
run_contains "validate_workflow_config_sh_repo_root_arg" "TARGET_REPO_NAME=single-repo" "$validator_output"

# validate-workflow-config.sh argument parsing coverage: help flags, unknown
# flags, and missing values for both value-taking options.
validator_help_output="$(bash "$VALIDATOR" --help)"
run_contains "validate_workflow_config_sh_help" "Usage:" "$validator_help_output"
validator_short_help_output="$(bash "$VALIDATOR" -h)"
run_contains "validate_workflow_config_sh_short_help" "Usage:" "$validator_short_help_output"
run_fails_contains \
  "validate_workflow_config_sh_unknown_arg" \
  "unknown argument '--unknown'" \
  bash "$VALIDATOR" --unknown
run_fails_contains \
  "validate_workflow_config_sh_missing_repo_value" \
  "--repo requires a value" \
  bash "$VALIDATOR" --repo
run_fails_contains \
  "validate_workflow_config_sh_missing_repo_root_value" \
  "--repo-root requires a value" \
  bash "$VALIDATOR" --repo-root

hub_dir="$(fixture_dir workflow-hub)"
cat > "$hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
      role: mobile
      scope: app
      tracker:
        component: mobile
    - name: admin-portal
      git_url: git@github.com:example/admin-portal.git
      default_branch: develop
YAML
cat > "$hub_dir/.ai-dev-workflow.local.yaml" <<'YAML'
checkout_root: ../checkouts

product_repos:
  - name: mobile-app
    local_path: ../local/mobile-app
YAML
hub_output="$(workflow_repository_context mobile-app "$hub_dir")"
run_contains "workflow_hub_context_mode" "WORKFLOW_MODE=workflow_hub" "$hub_output"
run_contains "workflow_hub_context_name" "TARGET_REPO_NAME=mobile-app" "$hub_output"
run_contains "workflow_hub_context_github_repo" "TARGET_GITHUB_REPO=example/mobile-app" "$hub_output"
run_contains "workflow_hub_context_default_branch" "TARGET_DEFAULT_BRANCH=main" "$hub_output"
run_contains "workflow_hub_context_tracker_hints" "TARGET_TRACKER_HINTS=component:mobile" "$hub_output"
run_contains "workflow_hub_context_ci_policy" "TARGET_CI_POLICY=required" "$hub_output"
run_contains "workflow_hub_local_path_override" "TARGET_LOCAL_PATH=$TMP_ROOT/local/mobile-app" "$hub_output"
run_contains "workflow_hub_local_path_source" "TARGET_LOCAL_PATH_SOURCE=local_override" "$hub_output"

admin_output="$(workflow_repository_context admin-portal "$hub_dir")"
run_contains "workflow_hub_checkout_root_path" "TARGET_LOCAL_PATH=$TMP_ROOT/checkouts/admin-portal" "$admin_output"
run_contains "workflow_hub_checkout_root_source" "TARGET_LOCAL_PATH_SOURCE=checkout_root" "$admin_output"
repo_list_output="$(python3 "$RESOLVER" list-product-repos --repo-root "$hub_dir")"
run_contains "workflow_hub_list_product_repos_mobile" "mobile-app" "$repo_list_output"
run_contains "workflow_hub_list_product_repos_admin" "admin-portal" "$repo_list_output"

set_local_path_output="$(python3 "$RESOLVER" set-local-path --repo-root "$hub_dir" --repo admin-portal --local-path "$TMP_ROOT/local/admin-portal")"
run_contains "workflow_hub_set_local_path_output" "LOCAL_CONFIG_PATH=$hub_dir/.ai-dev-workflow.local.yaml" "$set_local_path_output"
admin_local_output="$(workflow_repository_context admin-portal "$hub_dir")"
run_contains "workflow_hub_set_local_path_resolves" "TARGET_LOCAL_PATH=$TMP_ROOT/local/admin-portal" "$admin_local_output"
python3 "$RESOLVER" set-local-path --repo-root "$hub_dir" --repo mobile-app --local-path "true" >/dev/null
run_contains "workflow_hub_set_local_path_quotes_yaml_token" 'local_path: "true"' "$(cat "$hub_dir/.ai-dev-workflow.local.yaml")"
newline_path=$'line1\nline2'
python3 "$RESOLVER" set-local-path --repo-root "$hub_dir" --repo mobile-app --local-path "$newline_path" >/dev/null
run_contains "workflow_hub_set_local_path_escapes_newline" 'local_path: "line1\nline2"' "$(cat "$hub_dir/.ai-dev-workflow.local.yaml")"

duplicate_local_dir="$(fixture_dir duplicate-local)"
cat > "$duplicate_local_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
YAML
cat > "$duplicate_local_dir/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: mobile-app
    local_path: ../one
  - name: mobile-app
    local_path: ../two
YAML
run_fails_contains \
  "workflow_hub_set_local_path_duplicate_local_fails" \
  "duplicate product_repos entries named 'mobile-app'" \
  python3 "$RESOLVER" set-local-path --repo-root "$duplicate_local_dir" --repo mobile-app --local-path ../three

run_fails_contains \
  "workflow_hub_ambiguous_without_repo" \
  "product repository selection is ambiguous" \
  python3 "$RESOLVER" resolve --repo-root "$hub_dir"

run_fails_contains \
  "workflow_hub_unknown_repo" \
  "no workflow_hub.product_repos entry named 'unknown-app'" \
  python3 "$RESOLVER" resolve --repo-root "$hub_dir" --repo unknown-app

ci_policy_dir="$(fixture_dir ci-policy-hub)"
cat > "$ci_policy_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      ci_policy: none
YAML
none_ci_output="$(workflow_repository_context mobile-app "$ci_policy_dir")"
run_contains "workflow_hub_ci_policy_none" "TARGET_CI_POLICY=none" "$none_ci_output"

release_contract_dir="$(fixture_dir release-contract)"
cat > "$release_contract_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: develop
      release:
        base: release-base
        branch_pattern: "{product_repo}/release/v{version}"
        changelog_owner: product_repo
        tag_owner: product_repo
        github_release_owner: product_repo
        deployment_evidence_owner: product_repo
        cleanup_evidence_owner: product_repo
        tracker_reconciliation_owner: hub
YAML
release_contract_output="$(workflow_repository_context mobile-app "$release_contract_dir")"
run_contains "workflow_hub_release_base" "TARGET_RELEASE_BASE=release-base" "$release_contract_output"
run_contains "workflow_hub_release_base_source" "TARGET_RELEASE_BASE_SOURCE=explicit" "$release_contract_output"
run_contains "workflow_hub_release_pattern" "TARGET_RELEASE_BRANCH_PATTERN='{product_repo}/release/v{version}'" "$release_contract_output"
run_contains "workflow_hub_release_pattern_source" "TARGET_RELEASE_BRANCH_PATTERN_SOURCE=explicit" "$release_contract_output"
run_contains "workflow_hub_release_changelog_owner" "TARGET_RELEASE_CHANGELOG_OWNER=product_repo" "$release_contract_output"
run_contains "workflow_hub_release_tracker_owner" "TARGET_RELEASE_TRACKER_RECONCILIATION_OWNER=hub" "$release_contract_output"
run_contains "workflow_hub_release_contract_revision" "TARGET_RELEASE_CONTRACT_REVISION=sha256:" "$release_contract_output"

release_defaults_dir="$(fixture_dir release-defaults)"
cat > "$release_defaults_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
YAML
release_defaults_output="$(workflow_repository_context mobile-app "$release_defaults_dir")"
run_contains "workflow_hub_release_default_base" "TARGET_RELEASE_BASE=main" "$release_defaults_output"
run_contains "workflow_hub_release_default_base_source" "TARGET_RELEASE_BASE_SOURCE=default" "$release_defaults_output"
run_contains "workflow_hub_release_default_pattern" "TARGET_RELEASE_BRANCH_PATTERN='release/v{version}'" "$release_defaults_output"
run_contains "workflow_hub_release_default_owner" "TARGET_RELEASE_TAG_OWNER=product_repo" "$release_defaults_output"
run_contains "workflow_hub_release_default_tracker_owner" "TARGET_RELEASE_TRACKER_RECONCILIATION_OWNER=hub" "$release_defaults_output"

bad_ci_dir="$(fixture_dir bad-ci-policy)"
cat > "$bad_ci_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      ci_policy: maybe
YAML
run_fails_contains \
  "workflow_hub_invalid_ci_policy" \
  "workflow_hub.product_repos[1].ci_policy must be one of" \
  python3 "$RESOLVER" resolve --repo-root "$bad_ci_dir" --repo mobile-app

bad_release_branch_dir="$(fixture_dir bad-release-branch)"
cat > "$bad_release_branch_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        base: "bad branch"
YAML
run_fails_contains \
  "workflow_hub_release_rejects_bad_base" \
  "workflow_hub.product_repos[1].release.base is not a portable branch name" \
  python3 "$RESOLVER" resolve --repo-root "$bad_release_branch_dir" --repo mobile-app

bad_release_pattern_dir="$(fixture_dir bad-release-pattern)"
cat > "$bad_release_pattern_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        branch_pattern: "release/{channel}/v{version}"
YAML
run_fails_contains \
  "workflow_hub_release_rejects_unknown_pattern_placeholder" \
  "contains unknown placeholder(s): {channel}" \
  python3 "$RESOLVER" resolve --repo-root "$bad_release_pattern_dir" --repo mobile-app

static_release_pattern_dir="$(fixture_dir static-release-pattern)"
cat > "$static_release_pattern_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        branch_pattern: release/current
YAML
run_fails_contains \
  "workflow_hub_release_rejects_static_pattern" \
  "must include the {version} placeholder" \
  python3 "$RESOLVER" resolve --repo-root "$static_release_pattern_dir" --repo mobile-app

bad_release_owner_dir="$(fixture_dir bad-release-owner)"
cat > "$bad_release_owner_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        tag_owner: hub
        changelog_owner: somewhere-else
YAML
run_fails_contains \
  "workflow_hub_release_rejects_unknown_owner" \
  "release.changelog_owner must be one of" \
  python3 "$RESOLVER" resolve --repo-root "$bad_release_owner_dir" --repo mobile-app

secret_release_dir="$(fixture_dir secret-release)"
cat > "$secret_release_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        secret_name: production-token
YAML
run_fails_contains \
  "workflow_hub_release_rejects_secret_key" \
  "contains local-only field(s): release.secret_name" \
  python3 "$RESOLVER" resolve --repo-root "$secret_release_dir" --repo mobile-app

password_release_dir="$(fixture_dir password-release)"
cat > "$password_release_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        password: hunter2
YAML
run_fails_contains \
  "workflow_hub_release_rejects_password_key" \
  "contains local-only field(s): release.password" \
  python3 "$RESOLVER" resolve --repo-root "$password_release_dir" --repo mobile-app

api_key_release_dir="$(fixture_dir api-key-release)"
cat > "$api_key_release_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        external:
          apiKey: placeholder
YAML
run_fails_contains \
  "workflow_hub_release_rejects_api_key" \
  "contains forbidden local or secret value(s): external.apiKey" \
  python3 "$RESOLVER" resolve --repo-root "$api_key_release_dir" --repo mobile-app

token_release_dir="$(fixture_dir token-release)"
cat > "$token_release_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      release:
        evidence_note: ghp_FAKEPLACEHOLDER
YAML
run_fails_contains \
  "workflow_hub_release_rejects_token_value" \
  "contains forbidden local or secret value(s): evidence_note" \
  python3 "$RESOLVER" resolve --repo-root "$token_release_dir" --repo mobile-app

no_local_dir="$(fixture_dir no-local)"
cat > "$no_local_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
YAML
run_fails_contains \
  "workflow_hub_require_local_path" \
  "local path for product repo 'mobile-app' is required" \
  python3 "$RESOLVER" validate --repo-root "$no_local_dir" --repo mobile-app --require-local

duplicate_dir="$(fixture_dir duplicate)"
cat > "$duplicate_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
    - name: mobile-app
      github_repo: example/mobile-app-2
YAML
run_fails_contains \
  "workflow_hub_duplicate_names" \
  "duplicate workflow_hub.product_repos name 'mobile-app'" \
  python3 "$RESOLVER" resolve --repo-root "$duplicate_dir" --repo mobile-app

missing_identity_dir="$(fixture_dir missing-identity)"
cat > "$missing_identity_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
YAML
run_fails_contains \
  "workflow_hub_missing_identity" \
  "must define github_repo or git_url" \
  python3 "$RESOLVER" resolve --repo-root "$missing_identity_dir" --repo mobile-app

local_only_dir="$(fixture_dir local-only-field)"
cat > "$local_only_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      local_path: ../mobile-app
YAML
run_fails_contains \
  "workflow_hub_rejects_local_only_fields" \
  "contains local-only field(s): local_path" \
  python3 "$RESOLVER" resolve --repo-root "$local_only_dir" --repo mobile-app

nested_local_only_dir="$(fixture_dir nested-local-only-field)"
cat > "$nested_local_only_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        app_id: "123"
        private_key_path: ~/.config/example/private-key.pem
YAML
run_fails_contains \
  "workflow_hub_rejects_nested_local_only_fields" \
  "contains local-only field(s): github_app.private_key_path" \
  python3 "$RESOLVER" resolve --repo-root "$nested_local_only_dir" --repo mobile-app

nested_list_local_only_dir="$(fixture_dir nested-list-local-only-field)"
cat > "$nested_list_local_only_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      app_identifiers:
        - github_app:
            app_id: "123"
            private_key_path: ~/.config/example/private-key.pem
YAML
run_fails_contains \
  "workflow_hub_preserves_nested_list_mapping" \
  "contains local-only field(s): app_identifiers[1].github_app.private_key_path" \
  python3 "$RESOLVER" resolve --repo-root "$nested_list_local_only_dir" --repo mobile-app

ssh_remote_dir="$(fixture_dir ssh-remote)"
mkdir -p "$ssh_remote_dir/.git"
cat > "$ssh_remote_dir/.git/config" <<'GITCONFIG'
[remote "origin"]
  url = ssh://git@github.com/example/ssh-product.git
GITCONFIG
ssh_remote_output="$(python3 "$RESOLVER" resolve --repo-root "$ssh_remote_dir")"
run_contains "single_repo_ssh_remote_slug" "TARGET_GITHUB_REPO=example/ssh-product" "$ssh_remote_output"

product_repo_dir="$(fixture_dir product-repo)"
cat > "$product_repo_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: product_repo

product_repo:
  default_branch: release
  workflow_hub:
    github_repo: example/workflow-hub
YAML
product_repo_output="$(workflow_repository_context "" "$product_repo_dir")"
run_contains "product_repo_context_mode" "WORKFLOW_MODE=product_repo" "$product_repo_output"
run_contains "product_repo_context_hub" "WORKFLOW_HUB_GITHUB_REPO=example/workflow-hub" "$product_repo_output"
run_contains "product_repo_context_branch" "TARGET_DEFAULT_BRANCH=release" "$product_repo_output"
run_contains "product_repo_release_default_pattern" "TARGET_RELEASE_BRANCH_PATTERN='release/v{version}'" "$product_repo_output"
run_contains "product_repo_release_default_tracker_owner" "TARGET_RELEASE_TRACKER_RECONCILIATION_OWNER=hub" "$product_repo_output"

product_ci_none_dir="$(fixture_dir product-ci-none)"
cat > "$product_ci_none_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: product_repo

product_repo:
  ci_policy: none
  workflow_hub:
    github_repo: example/workflow-hub
YAML
product_ci_none_output="$(workflow_repository_context "" "$product_ci_none_dir")"
run_contains "product_repo_ci_policy_none" "TARGET_CI_POLICY=none" "$product_ci_none_output"

bad_product_repo_dir="$(fixture_dir bad-product-repo)"
cat > "$bad_product_repo_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: product_repo

product_repo:
  workflow_hub: {}
YAML
run_fails_contains \
  "product_repo_requires_hub_reference" \
  "product_repo.workflow_hub must define github_repo or git_url" \
  python3 "$RESOLVER" resolve --repo-root "$bad_product_repo_dir"

review_dir="$(fixture_dir review-overrides)"
cat > "$review_dir/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    runner: [codex]
    github: [pr-agent]
  on_ready:
    github: [bugbot]
  internal_reviewers_unavailable_policy: warn
YAML
review_output="$(workflow_review_override_context "$review_dir")"
run_contains "local_review_override_runner_value" "REVIEW_ON_DRAFT_RUNNER=codex" "$review_output"
run_contains "local_review_override_runner_source" "REVIEW_ON_DRAFT_RUNNER_SOURCE=.ai-dev-workflow.local.yaml" "$review_output"
run_contains "local_review_override_draft_github_value" "REVIEW_ON_DRAFT_GITHUB=pr-agent" "$review_output"
run_contains "local_review_override_draft_github_source" "REVIEW_ON_DRAFT_GITHUB_SOURCE=.ai-dev-workflow.local.yaml" "$review_output"
run_contains "local_review_override_ready_github_value" "REVIEW_ON_READY_GITHUB=bugbot" "$review_output"
run_contains "local_review_override_ready_github_source" "REVIEW_ON_READY_GITHUB_SOURCE=.ai-dev-workflow.local.yaml" "$review_output"
run_contains "local_review_override_policy_value" "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY=warn" "$review_output"
run_contains "local_review_override_policy_source" "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY_SOURCE=.ai-dev-workflow.local.yaml" "$review_output"
run_contains "local_review_override_combined_source" "LOCAL_OVERRIDE_SOURCE=runner:.ai-dev-workflow.local.yaml,draft-github:.ai-dev-workflow.local.yaml,ready-github:.ai-dev-workflow.local.yaml,policy:.ai-dev-workflow.local.yaml" "$review_output"

empty_review_dir="$(fixture_dir empty-review-overrides)"
cat > "$empty_review_dir/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    runner: []
    github: []
  on_ready:
    github: []
YAML
empty_review_output="$(workflow_review_override_context "$empty_review_dir")"
run_contains "empty_local_review_override_runner_value" "REVIEW_ON_DRAFT_RUNNER=" "$empty_review_output"
run_contains "empty_local_review_override_runner_source" "REVIEW_ON_DRAFT_RUNNER_SOURCE=.ai-dev-workflow.local.yaml" "$empty_review_output"
run_contains "empty_local_review_override_draft_github_value" "REVIEW_ON_DRAFT_GITHUB=" "$empty_review_output"
run_contains "empty_local_review_override_draft_github_source" "REVIEW_ON_DRAFT_GITHUB_SOURCE=.ai-dev-workflow.local.yaml" "$empty_review_output"
run_contains "empty_local_review_override_ready_github_value" "REVIEW_ON_READY_GITHUB=" "$empty_review_output"
run_contains "empty_local_review_override_ready_github_source" "REVIEW_ON_READY_GITHUB_SOURCE=.ai-dev-workflow.local.yaml" "$empty_review_output"

local_review_dir="$(fixture_dir local-review-overrides)"
cat > "$local_review_dir/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_draft:
    runner: ["claude,with-comma", codex]
  internal_reviewers_unavailable_policy: warn
YAML
inline_list_parse_output="$(
  python3 - "$RESOLVER" "$local_review_dir/.ai-dev-workflow.local.yaml" <<'PY'
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("workflow_config_resolver", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
runner = module.parse_yaml_subset(Path(sys.argv[2]))["review"]["on_draft"]["runner"]
print(f"{len(runner)}:{runner[0]}:{runner[1]}")
PY
)"
run_test "inline_list_parser_respects_quotes" "2:claude,with-comma:codex" "$inline_list_parse_output"
local_review_output="$(workflow_review_override_context "$local_review_dir")"
run_contains "local_review_override_runner" "REVIEW_ON_DRAFT_RUNNER=claude,with-comma,codex" "$local_review_output"
run_contains "local_review_override_source" "LOCAL_OVERRIDE_SOURCE=runner:.ai-dev-workflow.local.yaml,policy:.ai-dev-workflow.local.yaml" "$local_review_output"

stale_review_dir="$(fixture_dir stale-review-overrides)"
mkdir -p "$stale_review_dir/.tmp"
cat > "$stale_review_dir/.tmp/template-config.json" <<'JSON'
{
  "overrides": {
    "review": {
      "on_draft": {
        "runner": ["claude"]
      },
      "internal_reviewers_unavailable_policy": "fail-if-any-unavailable"
    }
  }
}
JSON
stale_review_output="$(workflow_review_override_context "$stale_review_dir")"
run_contains "stale_review_override_runner_empty" "REVIEW_ON_DRAFT_RUNNER=" "$stale_review_output"
run_contains "stale_review_override_runner_source_empty" "REVIEW_ON_DRAFT_RUNNER_SOURCE=" "$stale_review_output"
run_contains "stale_review_override_draft_github_empty" "REVIEW_ON_DRAFT_GITHUB=" "$stale_review_output"
run_contains "stale_review_override_draft_github_source_empty" "REVIEW_ON_DRAFT_GITHUB_SOURCE=" "$stale_review_output"
run_contains "stale_review_override_ready_github_empty" "REVIEW_ON_READY_GITHUB=" "$stale_review_output"
run_contains "stale_review_override_ready_github_source_empty" "REVIEW_ON_READY_GITHUB_SOURCE=" "$stale_review_output"
run_contains "stale_review_override_policy_empty" "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY=" "$stale_review_output"
run_contains "stale_review_override_policy_source_empty" "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY_SOURCE=" "$stale_review_output"
run_contains "stale_review_override_source_empty" "LOCAL_OVERRIDE_SOURCE=" "$stale_review_output"

malformed_dir="$(fixture_dir malformed)"
cat > "$malformed_dir/.ai-dev-workflow.yaml" <<'YAML'
 schema_version: 2
YAML
run_fails_contains \
  "malformed_yaml_fails_closed" \
  "indentation must use multiples of two spaces" \
  python3 "$RESOLVER" mode --repo-root "$malformed_dir"

wrapper_output="$(workflow_validate_repository_context mobile-app "$hub_dir" require-local)"
run_contains "workflow_lib_validate_wrapper" "TARGET_REPO_NAME=mobile-app" "$wrapper_output"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
