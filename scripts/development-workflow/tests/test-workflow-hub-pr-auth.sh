#!/usr/bin/env bash
# test-workflow-hub-pr-auth.sh - workflow-hub product PR auth helper tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py"
TOKEN_HELPER="$REPO_ROOT/scripts/development-workflow/github-app-token.sh"
PR_HELPER="$REPO_ROOT/scripts/development-workflow/open-product-pr.sh"

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

run_not_contains() {
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - output unexpectedly contained '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

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

make_private_key() {
  local path="$1"
  openssl genrsa 2048 > "$path" 2>/dev/null
}

echo ""
echo "=== Workflow hub product PR auth ==="

hub_dir="$(fixture_dir hub)"
mobile_key="$hub_dir/mobile-app.pem"
admin_key="$hub_dir/admin-portal.pem"
make_private_key "$mobile_key"
make_private_key "$admin_key"

cat > "$hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
      github_app:
        app_id: "12345"
        installation_id: "999"
    - name: admin-portal
      git_url: git@github.com:example/admin-portal.git
      default_branch: develop
      github_app:
        app_id: "23456"
        installation_id: "888"
YAML
cat > "$hub_dir/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    github_app:
      private_key_path: "$mobile_key"
  - name: admin-portal
    private_key_path: "$admin_key"
YAML

auth_status="$(python3 "$RESOLVER" auth --repo-root "$hub_dir" --repo mobile-app)"
run_contains "auth_status_configured" "AUTH_STATUS=auth_configured" "$auth_status"
run_contains "auth_status_redacted_source" "AUTH_SECRET_SOURCE=private_key_path" "$auth_status"
run_not_contains "auth_status_hides_private_key_path" "$mobile_key" "$auth_status"

auth_machine="$(python3 "$RESOLVER" auth --repo-root "$hub_dir" --repo mobile-app --include-local-secrets)"
run_contains "auth_machine_includes_private_key_path" "AUTH_PRIVATE_KEY_PATH=$mobile_key" "$auth_machine"

body_file="$hub_dir/body.md"
printf 'PR body\n' > "$body_file"
mobile_dry_run="$(bash "$PR_HELPER" --repo-root "$hub_dir" --repo mobile-app --base main --head feature/test --title "Mobile PR" --body-file "$body_file" --dry-run)"
admin_dry_run="$(bash "$PR_HELPER" --repo-root "$hub_dir" --repo admin-portal --base develop --head feature/test --title "Admin PR" --body-file "$body_file" --dry-run)"
run_contains "mobile_dry_run_targets_mobile" "TARGET_REPO=example/mobile-app" "$mobile_dry_run"
run_contains "admin_dry_run_targets_admin" "TARGET_REPO=example/admin-portal" "$admin_dry_run"
run_not_contains "dry_run_redacts_token" "fixture-installation-token" "$mobile_dry_run"
run_contains "dry_run_command_shape" "GH_TOKEN=<redacted> gh pr create --repo 'example/mobile-app'" "$mobile_dry_run"

non_github_dir="$(fixture_dir non-github)"
cat > "$non_github_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: internal-app
      git_url: ssh://git@example.com/internal-app.git
YAML
run_fails_contains \
  "product_pr_non_github_url_fails" \
  "does not resolve to a GitHub owner/repo slug" \
  bash "$PR_HELPER" --repo-root "$non_github_dir" --repo internal-app --base main --head feature/test --title "Internal PR" --body-file "$body_file" --dry-run

single_repo_dir="$(fixture_dir single-repo)"
cat > "$single_repo_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: single_repo
YAML
run_fails_contains \
  "product_pr_single_repo_mode_fails" \
  "product PR operations require workflow_hub mode" \
  bash "$PR_HELPER" --repo-root "$single_repo_dir" --repo mobile-app --base main --head feature/test --title "Mobile PR" --body-file "$body_file" --dry-run

missing_app_dir="$(fixture_dir missing-app)"
cat > "$missing_app_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        installation_id: "999"
YAML
run_fails_contains \
  "token_helper_missing_app_id" \
  "missing_app_id" \
  bash "$TOKEN_HELPER" --repo-root "$missing_app_dir" --repo mobile-app --print-token

missing_key_dir="$(fixture_dir missing-key)"
cat > "$missing_key_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        app_id: "12345"
        installation_id: "999"
YAML
run_fails_contains \
  "token_helper_missing_private_key" \
  "missing_private_key" \
  bash "$TOKEN_HELPER" --repo-root "$missing_key_dir" --repo mobile-app --print-token

secret_ref_dir="$(fixture_dir secret-ref)"
cat > "$secret_ref_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        app_id: "12345"
        installation_id: "999"
YAML
cat > "$secret_ref_dir/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: mobile-app
    github_app:
      secret_ref: op://ExampleVault/mobile-app-github-app/private-key
YAML
run_fails_contains \
  "token_helper_secret_ref_without_resolver_command" \
  "WORKFLOW_GITHUB_APP_SECRET_REF_COMMAND is not set" \
  bash "$TOKEN_HELPER" --repo-root "$secret_ref_dir" --repo mobile-app --print-token

missing_installation_dir="$(fixture_dir missing-installation)"
cat > "$missing_installation_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        app_id: "12345"
YAML
cat > "$missing_installation_dir/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    private_key_path: "$mobile_key"
YAML
run_fails_contains \
  "token_helper_missing_installation" \
  "missing_installation" \
  bash "$TOKEN_HELPER" --repo-root "$missing_installation_dir" --repo mobile-app --print-token

shared_secret_dir="$(fixture_dir shared-secret)"
cat > "$shared_secret_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        app_id: "12345"
        private_key_path: /private/key.pem
YAML
run_fails_contains \
  "shared_config_rejects_private_key_path" \
  "contains local-only field(s): github_app.private_key_path" \
  python3 "$RESOLVER" auth --repo-root "$shared_secret_dir" --repo mobile-app

token_exchange_stub="$TMP_ROOT/token-exchange-stub.sh"
cat > "$token_exchange_stub" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture-installation-token\n'
SH
chmod +x "$token_exchange_stub"

token_stdout="$(
  WORKFLOW_GITHUB_APP_TOKEN_EXCHANGE_CMD="$token_exchange_stub" \
    bash "$TOKEN_HELPER" --repo-root "$hub_dir" --repo mobile-app --print-token 2>"$TMP_ROOT/token.stderr"
)"
run_equals "token_helper_prints_only_token" "fixture-installation-token" "$token_stdout"
run_not_contains "token_helper_stderr_no_token" "fixture-installation-token" "$(cat "$TMP_ROOT/token.stderr")"

stub_bin="$TMP_ROOT/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$GH_TOKEN" > "$GH_TOKEN_CAPTURE"
printf '%s\n' "$*" > "$GH_ARGS_CAPTURE"
printf 'https://github.com/example/mobile-app/pull/123\n'
SH
chmod +x "$stub_bin/gh"

live_output="$(
  PATH="$stub_bin:$PATH" \
  GH_TOKEN_CAPTURE="$TMP_ROOT/gh-token.txt" \
  GH_ARGS_CAPTURE="$TMP_ROOT/gh-args.txt" \
  WORKFLOW_GITHUB_APP_TOKEN_EXCHANGE_CMD="$token_exchange_stub" \
    bash "$PR_HELPER" --repo-root "$hub_dir" --repo mobile-app --base main --head feature/test --title "Mobile PR" --body-file "$body_file"
)"
run_contains "live_pr_returns_url" "PR_URL=https://github.com/example/mobile-app/pull/123" "$live_output"
run_equals "live_pr_child_receives_token" "fixture-installation-token" "$(cat "$TMP_ROOT/gh-token.txt")"
run_contains "live_pr_targets_repo" "pr create --repo example/mobile-app" "$(cat "$TMP_ROOT/gh-args.txt")"
run_not_contains "live_pr_output_no_token" "fixture-installation-token" "$live_output"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
