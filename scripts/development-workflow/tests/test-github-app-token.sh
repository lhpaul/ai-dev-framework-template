#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/development-workflow/github-app-token.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains_text() {
  local text="$1"
  local pattern="$2"
  local message="$3"

  case "$text" in
    *"$pattern"*) ;;
    *) fail "$message" ;;
  esac
}

write_hub_config() {
  local repo_root="$1"
  local private_key_path="$2"

  cat > "$repo_root/.ai-dev-workflow.yaml" <<'YAML'
mode: workflow_hub
workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      github_app:
        app_id: 12345
        installation_id: 67890
YAML

  cat > "$repo_root/.ai-dev-workflow.local.yaml" <<YAML
product_repos:
  - name: mobile-app
    github_app:
      private_key_path: '$private_key_path'
YAML
}

exchange_cmd="$TMP_DIR/exchange-token.sh"
cat > "$exchange_cmd" <<'SH'
#!/usr/bin/env bash
[ "$#" -eq 3 ] || exit 64
[ -n "$3" ] || exit 65
printf 'mock-installation-token\n'
SH
chmod +x "$exchange_cmd"

key_file="$TMP_DIR/home-as-key.pem"
openssl genrsa -out "$key_file" 2048 >/dev/null 2>&1

bare_home_repo="$TMP_DIR/bare-home-repo"
mkdir -p "$bare_home_repo"
write_hub_config "$bare_home_repo" "~"

bare_home_output="$(
  HOME="$key_file" \
  WORKFLOW_GITHUB_APP_TOKEN_EXCHANGE_CMD="$exchange_cmd" \
    bash "$SCRIPT" --repo mobile-app --repo-root "$bare_home_repo" --print-token
)" || fail "bare ~ private_key_path should normalize to HOME and exchange a token"
[ "$bare_home_output" = "mock-installation-token" ] \
  || fail "bare ~ private_key_path should complete token exchange"

missing_key_repo="$TMP_DIR/missing-key-repo"
mkdir -p "$missing_key_repo"
write_hub_config "$missing_key_repo" "$TMP_DIR/does-not-exist.pem"
set +e
missing_output="$(bash "$SCRIPT" --repo mobile-app --repo-root "$missing_key_repo" --print-token 2>&1)"
missing_status=$?
set -e
[ "$missing_status" -ne 0 ] || fail "missing private key path should fail"
assert_contains_text "$missing_output" \
  "missing_private_key: configured private key path is not readable for selected product repository" \
  "missing private key path should explain unreadable path"

invalid_key="$TMP_DIR/invalid-key.pem"
printf 'not a private key\n' > "$invalid_key"
invalid_key_repo="$TMP_DIR/invalid-key-repo"
mkdir -p "$invalid_key_repo"
write_hub_config "$invalid_key_repo" "$invalid_key"
set +e
invalid_output="$(
  WORKFLOW_GITHUB_APP_TOKEN_EXCHANGE_CMD="$exchange_cmd" \
    bash "$SCRIPT" --repo mobile-app --repo-root "$invalid_key_repo" --print-token 2>&1
)"
invalid_status=$?
set -e
[ "$invalid_status" -ne 0 ] || fail "invalid private key should fail during JWT signing"
assert_contains_text "$invalid_output" \
  "missing_private_key: failed to sign GitHub App JWT with selected private key" \
  "JWT signing failure should use the configured diagnostic"

printf 'github app token tests passed\n'
