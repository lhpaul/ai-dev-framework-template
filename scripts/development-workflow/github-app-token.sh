#!/usr/bin/env bash
# github-app-token.sh - resolve workflow-hub GitHub App auth for product repos.

set -euo pipefail
TOKEN_TMP_DIR=""
_github_app_token_exit() {
  local status=$?
  if [ -n "$TOKEN_TMP_DIR" ]; then
    rm -rf "$TOKEN_TMP_DIR"
  fi
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _github_app_token_exit EXIT

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
RESOLVER="$SCRIPT_DIR/workflow-config-resolver.py"

usage() {
  cat <<'USAGE'
Usage: github-app-token.sh --repo <product-name> [--repo-root <path>] [--status|--dry-run|--print-token]

Options:
  --repo <name>       Product repository name from workflow_hub.product_repos[].
  --repo-root <path>  Workflow hub repository root. Defaults to this repository.
  --status           Print redacted auth status only.
  --dry-run          Validate auth metadata without exchanging a token.
  --print-token      Print only the installation token to stdout.
  -h, --help         Show this help.

Secret values and token material are never printed in normal logs.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*" >&2
}

json_field() {
  local json="$1"
  local key="$2"
  if ! printf '%s' "$json" | jq -re --arg key "$key" '.[$key] // ""' 2>/dev/null; then
    die "resolver output did not include expected field '$key'"
  fi
}

base64url_file() {
  openssl base64 -A -in "$1" | tr '+/' '-_' | tr -d '='
}

json_string() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

create_jwt() {
  local app_id="$1"
  local private_key_file="$2"
  local tmp_dir="$3"
  local now iat exp header payload signing_input signature

  now="$(date +%s)"
  iat=$((now - 60))
  exp=$((now + 540))
  header='{"alg":"RS256","typ":"JWT"}'
  payload="{\"iat\":${iat},\"exp\":${exp},\"iss\":$(json_string "$app_id")}"

  printf '%s' "$header" > "$tmp_dir/header.json"
  printf '%s' "$payload" > "$tmp_dir/payload.json"
  signing_input="$(base64url_file "$tmp_dir/header.json").$(base64url_file "$tmp_dir/payload.json")"
  printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$private_key_file" > "$tmp_dir/signature.bin"
  signature="$(base64url_file "$tmp_dir/signature.bin")"
  printf '%s.%s\n' "$signing_input" "$signature"
}

normalize_private_key_path() {
  local raw_path="$1"

  case "$raw_path" in
    \~)
      printf '%s\n' "$HOME"
      ;;
    \~/*)
      printf '%s/%s\n' "$HOME" "${raw_path#\~/}"
      ;;
    /*)
      printf '%s\n' "$raw_path"
      ;;
    *)
      printf '%s/%s\n' "$REPO_ROOT" "$raw_path"
      ;;
  esac
}

load_private_key_file() {
  local private_key_path="$1"
  local secret_ref="$2"
  local tmp_dir="$3"
  local resolved_private_key_path

  if [ -n "$private_key_path" ]; then
    resolved_private_key_path="$(normalize_private_key_path "$private_key_path")"
    if [ ! -r "$resolved_private_key_path" ]; then
      die "missing_private_key: configured private key path is not readable for selected product repository"
    fi
    printf '%s\n' "$resolved_private_key_path"
    return 0
  fi

  if [ -z "$secret_ref" ]; then
    die "missing_private_key: configure product_repos[].github_app.private_key_path or secret_ref in .ai-dev-workflow.local.yaml"
  fi
  if [ -z "${WORKFLOW_GITHUB_APP_SECRET_REF_COMMAND:-}" ]; then
    die "missing_private_key: secret_ref is configured, but WORKFLOW_GITHUB_APP_SECRET_REF_COMMAND is not set"
  fi

  if ! "$WORKFLOW_GITHUB_APP_SECRET_REF_COMMAND" "$secret_ref" > "$tmp_dir/private-key.pem"; then
    die "missing_private_key: secret_ref resolver command failed for selected product repository"
  fi
  if [ ! -s "$tmp_dir/private-key.pem" ]; then
    die "missing_private_key: secret_ref resolver returned an empty private key"
  fi
  printf '%s\n' "$tmp_dir/private-key.pem"
}

exchange_token() {
  local app_id="$1"
  local installation_id="$2"
  local private_key_path="$3"
  local secret_ref="$4"
  local jwt response token

  TOKEN_TMP_DIR="$(mktemp -d)"

  local key_file
  if ! key_file="$(load_private_key_file "$private_key_path" "$secret_ref" "$TOKEN_TMP_DIR")"; then
    exit 1
  fi
  if ! jwt="$(create_jwt "$app_id" "$key_file" "$TOKEN_TMP_DIR")"; then
    die "missing_private_key: failed to sign GitHub App JWT with selected private key"
  fi

  if [ -n "${WORKFLOW_GITHUB_APP_TOKEN_EXCHANGE_CMD:-}" ]; then
    if ! token="$("$WORKFLOW_GITHUB_APP_TOKEN_EXCHANGE_CMD" "$app_id" "$installation_id" "$jwt")"; then
      die "missing_installation: token exchange command failed for selected product repository"
    fi
    [ -n "$token" ] || die "missing_installation: token exchange command returned an empty token"
    printf '%s\n' "$token"
    return 0
  fi

  if ! response="$(gh api -X POST "/app/installations/${installation_id}/access_tokens" \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" 2>/dev/null)"; then
    die "missing_installation: GitHub App installation token exchange failed"
  fi
  if [ -z "$response" ]; then
    die "missing_installation: GitHub App installation token exchange returned an empty response"
  fi
  if ! token="$(printf '%s' "$response" | jq -re '.token' 2>/dev/null)"; then
    die "permission_denied: token exchange response did not include an installation token"
  fi
  printf '%s\n' "$token"
}

REPO_NAME=""
MODE="status"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      REPO_NAME="$2"
      shift 2
      ;;
    --repo-root)
      [ "$#" -ge 2 ] || die "--repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    --status)
      MODE="status"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --print-token)
      MODE="print-token"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument '$1'"
      ;;
  esac
done

[ -n "$REPO_NAME" ] || die "--repo is required"

if [ "$MODE" = "status" ] || [ "$MODE" = "dry-run" ]; then
  if ! STATUS_OUTPUT="$(python3 "$RESOLVER" auth --repo-root "$REPO_ROOT" --repo "$REPO_NAME" 2>&1)"; then
    printf '%s\n' "$STATUS_OUTPUT" >&2
    exit 1
  fi
  printf '%s\n' "$STATUS_OUTPUT"
  if [ "$MODE" = "dry-run" ]; then
    log "DRY_RUN=true"
  fi
  exit 0
fi

if ! AUTH_OUTPUT="$(python3 "$RESOLVER" auth --repo-root "$REPO_ROOT" --repo "$REPO_NAME" --include-local-secrets --json 2>&1)"; then
  printf '%s\n' "$AUTH_OUTPUT" >&2
  exit 1
fi
AUTH_STATUS="$(json_field "$AUTH_OUTPUT" AUTH_STATUS)"
AUTH_APP_ID="$(json_field "$AUTH_OUTPUT" AUTH_APP_ID)"
AUTH_INSTALLATION_ID="$(json_field "$AUTH_OUTPUT" AUTH_INSTALLATION_ID)"
AUTH_PRIVATE_KEY_PATH="$(json_field "$AUTH_OUTPUT" AUTH_PRIVATE_KEY_PATH)"
AUTH_SECRET_REF="$(json_field "$AUTH_OUTPUT" AUTH_SECRET_REF)"

case "${AUTH_STATUS:-}" in
  auth_configured) ;;
  missing_app_id) die "missing_app_id: configure product_repos[].github_app.app_id for selected product repository" ;;
  missing_private_key) die "missing_private_key: configure a local private_key_path or secret_ref for selected product repository" ;;
  missing_installation) die "missing_installation: configure product_repos[].github_app.installation_id for selected product repository" ;;
  *) die "auth is not configured for selected product repository: ${AUTH_STATUS:-unknown}" ;;
esac

TOKEN="$(exchange_token "$AUTH_APP_ID" "$AUTH_INSTALLATION_ID" "${AUTH_PRIVATE_KEY_PATH:-}" "${AUTH_SECRET_REF:-}")"
[ -n "$TOKEN" ] || die "missing_installation: token exchange produced an empty token"
printf '%s\n' "$TOKEN"
