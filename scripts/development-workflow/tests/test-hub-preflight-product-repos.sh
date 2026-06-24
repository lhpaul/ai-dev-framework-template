#!/usr/bin/env bash
# test-hub-preflight-product-repos.sh - workflow hub product preflight tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/development-workflow/hub-preflight-product-repos.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_contains() {
  local name="$1" expected="$2" actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}'"
    printf 'Actual:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
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

hub_dir="$TMP_ROOT/hub"
mkdir -p "$hub_dir"
git -C "$hub_dir" init -q -b main
cat > "$hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
      ci_policy: required
    - name: docs-only-app
      github_repo: example/docs-only-app
      default_branch: main
      ci_policy: none
YAML
cat > "$hub_dir/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: mobile-app
    local_path: ../mobile-app
  - name: docs-only-app
    local_path: ../docs-only-app
YAML

stub_bin="$TMP_ROOT/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
repo=""
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "--repo" ]; then
    j=$((i + 1))
    repo="${!j}"
  fi
done
if [ "$1" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
if [ "$1" = "label" ] && [ "${2:-}" = "list" ]; then
  case "$repo" in
    example/mobile-app)
      printf '[{"name":"ready-for-human-review"}]\n'
      ;;
    *)
      printf '[]\n'
      ;;
  esac
  exit 0
fi
if [ "$1" = "label" ] && [ "${2:-}" = "create" ]; then
  printf 'created %s\n' "${3:-}"
  exit 0
fi
if [ "$1" = "api" ]; then
  case "${2:-}" in
    repos/example/mobile-app/actions/workflows)
      printf '0\n'
      ;;
    repos/example/docs-only-app/actions/workflows)
      printf '0\n'
      ;;
    *)
      printf 'unexpected api path: %s\n' "${2:-}" >&2
      exit 1
      ;;
  esac
  exit 0
fi
printf 'unexpected gh: %s\n' "$*" >&2
exit 1
STUB
chmod +x "$stub_bin/gh"

echo ""
echo "=== Hub preflight product repos ==="

run_fails_contains \
  "requires_workflow_hub_mode" \
  "workflow_hub mode is required" \
  env PATH="$stub_bin:$PATH" "$PREFLIGHT" --repo mobile-app --repo-root "$TMP_ROOT/single"

mobile_output="$(env PATH="$stub_bin:$PATH" "$PREFLIGHT" --repo mobile-app --repo-root "$hub_dir" 2>&1)" || true
run_contains "mobile_ci_required_fails_without_workflows" "CI_PREFLIGHT=failed" "$mobile_output"
run_contains "mobile_creates_missing_labels" "LABEL_CREATED=needs-fixes" "$mobile_output"
run_contains "mobile_existing_label_reported" "LABEL_EXISTING=ready-for-human-review" "$mobile_output"

docs_output="$(env PATH="$stub_bin:$PATH" "$PREFLIGHT" --repo docs-only-app --repo-root "$hub_dir")"
run_contains "docs_ci_none_passes_without_workflows" "CI_PREFLIGHT=ok" "$docs_output"
run_contains "docs_overall_ok" "STATUS=ok" "$docs_output"

labels_only="$(env PATH="$stub_bin:$PATH" "$PREFLIGHT" --repo docs-only-app --repo-root "$hub_dir" --labels-only)"
run_contains "labels_only_skips_ci" "LABELS=ok" "$labels_only"
run_not_contains() {
  local name="$1" unexpected="$2" actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - did not expect '${unexpected}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}
run_not_contains "labels_only_no_ci_probe" "CI_WORKFLOW_COUNT" "$labels_only"

error_hub="$TMP_ROOT/error-hub"
mkdir -p "$error_hub"
git -C "$error_hub" init -q -b main
cat > "$error_hub/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: api-error-app
      github_repo: example/api-error-app
      default_branch: main
      ci_policy: none
YAML
cat > "$error_hub/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: api-error-app
    local_path: ../api-error-app
YAML
cat > "$stub_bin/gh-api-error" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
repo=""
for ((i=1; i<=$#; i++)); do
  if [ "${!i}" = "--repo" ]; then
    j=$((i + 1))
    repo="${!j}"
  fi
done
if [ "$1" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
if [ "$1" = "label" ] && [ "${2:-}" = "list" ]; then
  printf '[]\n'
  exit 0
fi
if [ "$1" = "label" ] && [ "${2:-}" = "create" ]; then
  exit 0
fi
if [ "$1" = "api" ]; then
  case "${2:-}" in
    repos/example/api-error-app/actions/workflows)
      exit 1
      ;;
    *)
      printf '0\n'
      ;;
  esac
  exit 0
fi
exit 1
STUB
chmod +x "$stub_bin/gh-api-error"
api_error_stub="$TMP_ROOT/api-error-bin"
mkdir -p "$api_error_stub"
cp "$stub_bin/gh-api-error" "$api_error_stub/gh"
api_error_output="$(env PATH="$api_error_stub:$PATH" "$PREFLIGHT" --repo api-error-app --repo-root "$error_hub")"
run_contains "ci_none_tolerates_workflow_query_failure" "CI_PREFLIGHT=ok" "$api_error_output"
run_contains "ci_none_workflow_query_failure_note" "workflow_query_failed_ci_policy_none" "$api_error_output"

bad_slug_hub="$TMP_ROOT/bad-slug-hub"
mkdir -p "$bad_slug_hub"
git -C "$bad_slug_hub" init -q -b main
cat > "$bad_slug_hub/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: bad-slug-app
      git_url: https://gitlab.com/example/bad-slug-app
      default_branch: main
YAML
cat > "$bad_slug_hub/.ai-dev-workflow.local.yaml" <<'YAML'
product_repos:
  - name: bad-slug-app
    local_path: ../bad-slug-app
YAML
bad_slug_output="$(env PATH="$stub_bin:$PATH" "$PREFLIGHT" --repo bad-slug-app --repo-root "$bad_slug_hub" 2>&1)" || true
run_contains "missing_github_slug_fails" "STATUS=failed" "$bad_slug_output"
run_contains "missing_github_slug_reason" "missing_github_repo_slug" "$bad_slug_output"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
