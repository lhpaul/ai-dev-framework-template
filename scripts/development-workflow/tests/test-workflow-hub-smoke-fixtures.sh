#!/usr/bin/env bash
# test-workflow-hub-smoke-fixtures.sh - non-secret workflow-hub smoke coverage.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh [--live-github-app]

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
FIXTURE_ROOT="$SCRIPT_DIR/fixtures/workflow-hub-smoke"
RESOLVER="$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py"
STATUS_CMD="$REPO_ROOT/scripts/development-workflow/hub-status.sh"
SYNC_CMD="$REPO_ROOT/scripts/development-workflow/hub-sync-product-repos.sh"
PR_CMD="$REPO_ROOT/scripts/development-workflow/open-product-pr.sh"
NEXT_ACTION_CMD="$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh"
VALIDATOR="$REPO_ROOT/scripts/development-workflow/validate-workflow-hub-skeletons.py"

LIVE_GITHUB_APP=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --live-github-app)
      LIVE_GITHUB_APP=true
      shift
      ;;
    -h|--help)
      sed -n '1,4p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

TMP_ROOT="$(mktemp -d)" || {
  echo "Failed to create temporary directory." >&2
  exit 1
}
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

init_repo() {
  local path="$1"
  local branch="$2"
  local remote_path="$3"
  mkdir -p "$path"
  git -C "$path" init -q -b "$branch"
  git -C "$path" config user.email "fixture@example.com"
  git -C "$path" config user.name "Fixture User"
  cp -R "$FIXTURE_ROOT/products/${path##*/}/." "$path/"
  git -C "$path" add .
  git -C "$path" commit -q -m "initial fixture commit"
  git init --bare -q -b "$branch" "$remote_path"
  git -C "$path" remote add origin "$remote_path"
  git -C "$path" push -q -u origin "$branch"
}

make_development() {
  local root="$1"
  local path="$root/docs/specs/developments/20260611120000_883-fixture-routing"
  mkdir -p "$path"
  cat > "$path/1_883-fixture-routing_specs.md" <<'MD'
# Fixture Routing Spec

## Acceptance Criteria

- [ ] Product implementation work routes to the selected product repository.
MD
  cat > "$path/2_883-fixture-routing_implementation-plan.md" <<'MD'
# Fixture Routing Implementation Plan

## Summary

Route implementation work to a product repository.
MD
  printf '%s\n' "$path"
}

render_local_config() {
  local template_path="$1"
  local output_path="$2"
  local checkout_root="$3"
  local mobile_path="$4"
  python3 - "$template_path" "$output_path" "$checkout_root" "$mobile_path" <<'PY'
from pathlib import Path
import sys

template, output, checkout_root, mobile_path = sys.argv[1:5]
text = Path(template).read_text(encoding="utf-8")
text = text.replace("__CHECKOUT_ROOT__", checkout_root)
text = text.replace("__MOBILE_LOCAL_PATH__", mobile_path)
Path(output).write_text(text, encoding="utf-8")
PY
}

echo ""
echo "=== hub_fixture: seed safety and topology ==="

run_equals "fixture_seed_exists" "yes" "$([ -d "$FIXTURE_ROOT" ] && echo yes || echo no)"
run_equals "fixture_hub_shared_config_exists" "yes" "$([ -f "$FIXTURE_ROOT/hub/.ai-dev-workflow.yaml" ] && echo yes || echo no)"
run_equals "fixture_local_template_exists" "yes" "$([ -f "$FIXTURE_ROOT/local-config.template.yaml" ] && echo yes || echo no)"

if private_hits="$(
  grep -RInE --exclude='README.md' \
    'Leasity|RADAR|kids-safety|baumsystem|lhpaul/|op://|BEGIN .*PRIVATE KEY|ghp_|github_pat_|private_key_path|secret_ref|token=' \
    "$FIXTURE_ROOT" 2>&1
)"; then
  :
else
  private_status=$?
  if [ "$private_status" -eq 1 ]; then
    private_hits=""
  else
    echo "FAIL: fixture_private_detail_scan - grep failed with exit code $private_status"
    printf '%s\n' "$private_hits"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    private_hits="__scan_failed__"
  fi
fi
if [ "$private_hits" = "__scan_failed__" ]; then
  :
else
  run_equals "fixture_private_detail_scan" "" "$private_hits"
fi

hub_dir="$(fixture_dir workflow-hub)"
cp -R "$FIXTURE_ROOT/hub/." "$hub_dir/"
products_root="$(fixture_dir products)"
mobile_repo="$products_root/mobile-app"
admin_repo="$products_root/admin-portal"
mobile_remote="$(fixture_dir mobile-remote.git)"
admin_remote="$(fixture_dir admin-remote.git)"
init_repo "$mobile_repo" main "$mobile_remote"
init_repo "$admin_repo" develop "$admin_remote"
render_local_config "$FIXTURE_ROOT/local-config.template.yaml" "$hub_dir/.ai-dev-workflow.local.yaml" "$products_root" "$mobile_repo"

repo_names="$(python3 "$RESOLVER" list-product-repos --repo-root "$hub_dir")"
run_contains "fixture_lists_mobile" "mobile-app" "$repo_names"
run_contains "fixture_lists_admin" "admin-portal" "$repo_names"
run_equals "fixture_has_exactly_two_products" "2" "$(printf '%s\n' "$repo_names" | sed '/^$/d' | wc -l | tr -d ' ')"

echo ""
echo "=== product_fixture: config parsing and resolution ==="

mode_output="$(python3 "$RESOLVER" mode --repo-root "$hub_dir")"
run_contains "fixture_mode_workflow_hub" "WORKFLOW_MODE=workflow_hub" "$mode_output"

mobile_context="$(python3 "$RESOLVER" resolve --repo-root "$hub_dir" --repo mobile-app)"
admin_context="$(python3 "$RESOLVER" resolve --repo-root "$hub_dir" --repo admin-portal)"
run_contains "mobile_context_repo_name" "TARGET_REPO_NAME=mobile-app" "$mobile_context"
run_contains "mobile_context_github_repo" "TARGET_GITHUB_REPO=example/mobile-app" "$mobile_context"
run_contains "mobile_context_local_override" "TARGET_LOCAL_PATH_SOURCE=local_override" "$mobile_context"
run_contains "mobile_context_local_path" "TARGET_LOCAL_PATH=$mobile_repo" "$mobile_context"
run_contains "admin_context_repo_name" "TARGET_REPO_NAME=admin-portal" "$admin_context"
run_contains "admin_context_git_url" "TARGET_GIT_URL=git@github.com:example/admin-portal.git" "$admin_context"
run_contains "admin_context_checkout_root" "TARGET_LOCAL_PATH_SOURCE=checkout_root" "$admin_context"
run_contains "admin_context_local_path" "TARGET_LOCAL_PATH=$admin_repo" "$admin_context"
run_not_contains "products_have_distinct_identities" "TARGET_GITHUB_REPO=example/mobile-app" "$admin_context"

python3 "$RESOLVER" validate --repo-root "$hub_dir" --repo mobile-app --require-local >/dev/null
echo "PASS: mobile_validate_require_local"
PASS_COUNT=$((PASS_COUNT + 1))
python3 "$RESOLVER" validate --repo-root "$hub_dir" --repo admin-portal --require-local >/dev/null
echo "PASS: admin_validate_require_local"
PASS_COUNT=$((PASS_COUNT + 1))

run_fails_contains \
  "fixture_ambiguous_selection_fails" \
  "product repository selection is ambiguous" \
  python3 "$RESOLVER" resolve --repo-root "$hub_dir"
run_fails_contains \
  "fixture_unknown_repo_fails" \
  "no workflow_hub.product_repos entry named 'unknown-app'" \
  python3 "$RESOLVER" resolve --repo-root "$hub_dir" --repo unknown-app

tmp_config_hub="$(fixture_dir tmp-config-hub)"
cp -R "$FIXTURE_ROOT/hub/." "$tmp_config_hub/"
mkdir -p "$tmp_config_hub/.tmp"
cat > "$tmp_config_hub/.tmp/template-config.json" <<JSON
{"product_repos":[{"name":"mobile-app","local_path":"$mobile_repo"}]}
JSON
run_fails_contains \
  "tmp_template_config_not_checkout_source" \
  "local path for product repo 'mobile-app' is required" \
  python3 "$RESOLVER" validate --repo-root "$tmp_config_hub" --repo mobile-app --require-local

echo ""
echo "=== product_fixture: sync and status commands ==="

status_output="$(bash "$STATUS_CMD" --repo-root "$hub_dir" --all)"
run_contains "status_names_mobile" "REPO mobile-app" "$status_output"
run_contains "status_names_admin" "REPO admin-portal" "$status_output"
run_contains "status_reports_mobile_path" "LOCAL_PATH=$mobile_repo" "$status_output"
run_contains "status_reports_admin_path" "LOCAL_PATH=$admin_repo" "$status_output"
run_contains "status_reports_clean" "STATUS=clean" "$status_output"
run_contains "status_summary_clean" "SUMMARY synced=0 skipped=0 clean=2 dirty=0 missing=0 blocked=0 failed=0" "$status_output"

sync_output="$(bash "$SYNC_CMD" --repo-root "$hub_dir" --all)"
run_contains "sync_names_mobile" "REPO mobile-app" "$sync_output"
run_contains "sync_names_admin" "REPO admin-portal" "$sync_output"
run_contains "sync_already_current" "REASON=already_current" "$sync_output"
run_contains "sync_summary_skipped" "SUMMARY synced=0 skipped=2 clean=0 dirty=0 missing=0 blocked=0 failed=0" "$sync_output"
run_fails_contains \
  "status_unknown_product_fails" \
  "no workflow_hub.product_repos entry named 'unknown-app'" \
  bash "$STATUS_CMD" --repo-root "$hub_dir" --repo unknown-app
run_fails_contains \
  "sync_missing_local_path_guidance" \
  "STATUS=missing_path" \
  bash "$SYNC_CMD" --repo-root "$tmp_config_hub" --repo mobile-app

echo ""
echo "=== dry_run_routing: branch and pull-request targeting ==="

stub_bin="$TMP_ROOT/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  auth)
    exit 0
    ;;
  pr)
    case "${2:-}" in
      list)
        for arg in "$@"; do
          if [ "$arg" = "length" ]; then
            printf '0\n'
            exit 0
          fi
        done
        printf '[]\n'
        exit 0
        ;;
      view)
        printf '{"headRefName":"feature/883-fixture-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}\n'
        exit 0
        ;;
    esac
    ;;
  repo)
    if [ "${2:-}" = "view" ]; then
      printf '{"nameWithOwner":"example/workflow-hub"}\n'
      exit 0
    fi
    ;;
esac

echo "unexpected gh invocation: $*" >&2
exit 1
SH
chmod +x "$stub_bin/gh"

hub_dev="$(make_development "$hub_dir")"
next_action_output="$(
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$NEXT_ACTION_CMD" \
    --repo-root "$hub_dir" \
    --repo mobile-app \
    --development "$hub_dev"
)"
run_contains "next_action_targets_product_kind" "ACTION_REPOSITORY_KIND=product_repo_owned" "$next_action_output"
run_contains "next_action_targets_mobile_repo" "ACTION_GITHUB_REPO=example/mobile-app" "$next_action_output"
run_not_contains "next_action_not_hub_repo" "ACTION_GITHUB_REPO=example/workflow-hub" "$next_action_output"

body_file="$TMP_ROOT/body.md"
printf 'Fixture product PR body\n' > "$body_file"
mobile_pr_output="$(
  bash "$PR_CMD" \
    --repo-root "$hub_dir" \
    --repo mobile-app \
    --base main \
    --head feature/883-fixture-routing \
    --title "Fixture mobile PR" \
    --body-file "$body_file" \
    --dry-run
)"
admin_pr_output="$(
  bash "$PR_CMD" \
    --repo-root "$hub_dir" \
    --repo admin-portal \
    --base develop \
    --head feature/883-fixture-routing \
    --title "Fixture admin PR" \
    --body-file "$body_file" \
    --dry-run
)"
run_contains "mobile_pr_dry_run_targets_product" "TARGET_REPO=example/mobile-app" "$mobile_pr_output"
run_contains "mobile_pr_dry_run_base" "BASE_BRANCH=main" "$mobile_pr_output"
run_contains "mobile_pr_dry_run_head" "HEAD_BRANCH=feature/883-fixture-routing" "$mobile_pr_output"
run_contains "admin_pr_dry_run_targets_product" "TARGET_REPO=example/admin-portal" "$admin_pr_output"
run_not_contains "product_pr_dry_run_no_token" "fixture-installation-token" "$mobile_pr_output"
run_not_contains "product_pr_dry_run_no_secret_ref" "op://" "$mobile_pr_output"

echo ""
echo "=== hub_fixture: mode-scope classification ==="

sync_scope_output="$(
  python3 "$VALIDATOR" \
    --repo-root "$REPO_ROOT" \
    --sync-manifest "$REPO_ROOT/sync-manifest.yaml"
)"
run_contains "mode_scope_validator_reports_ok" "VALID" "$sync_scope_output"
sync_manifest_text="$(cat "$REPO_ROOT/sync-manifest.yaml")"
run_contains "mode_scope_manifest_defines_shared" "shared:" "$sync_manifest_text"
run_contains "mode_scope_manifest_defines_hub_only" "hub_only:" "$sync_manifest_text"
run_contains "mode_scope_manifest_defines_product_injection" "product_repo_injection:" "$sync_manifest_text"
run_contains "mode_scope_has_shared_entries" "mode_scope: shared" "$(cat "$REPO_ROOT/sync-manifest.yaml")"
run_contains "mode_scope_has_hub_entries" "mode_scope: hub_only" "$(cat "$REPO_ROOT/sync-manifest.yaml")"
run_contains "mode_scope_has_product_entries" "mode_scope: product_repo_injection" "$(cat "$REPO_ROOT/sync-manifest.yaml")"
echo "INFO: runtime mode-aware sync filtering remains outside this smoke harness; #883 validates classification metadata only."

echo ""
echo "=== single_repo_regression: default compatibility ==="

missing_mode_dir="$(fixture_dir missing-mode-single)"
explicit_single_dir="$(fixture_dir explicit-single)"
mkdir -p "$missing_mode_dir" "$explicit_single_dir"
git -C "$missing_mode_dir" init -q -b main
cat > "$explicit_single_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: single_repo
YAML
missing_mode_output="$(python3 "$RESOLVER" mode --repo-root "$missing_mode_dir")"
explicit_single_output="$(python3 "$RESOLVER" mode --repo-root "$explicit_single_dir")"
run_contains "missing_mode_defaults_single_repo" "WORKFLOW_MODE=single_repo" "$missing_mode_output"
run_contains "explicit_single_repo_resolves" "WORKFLOW_MODE=single_repo" "$explicit_single_output"
missing_mode_dev="$(make_development "$missing_mode_dir")"
single_next_action="$(
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$NEXT_ACTION_CMD" \
    --repo-root "$missing_mode_dir" \
    --development "$missing_mode_dev"
)"
run_contains "single_repo_next_action_context" "ACTION_REPOSITORY_KIND=single_repo_context" "$single_next_action"
run_not_contains "single_repo_no_product_selection_required" "product repository selection is ambiguous" "$single_next_action"

echo ""
echo "=== live_optional: explicit GitHub App boundary ==="

if [ "$LIVE_GITHUB_APP" != "true" ]; then
  echo "LIVE_VALIDATION=skipped"
  echo "LIVE_VALIDATION_REASON=not_requested"
  echo "PASS: live_validation_skipped_by_default"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  required_missing=false
  for var_name in WORKFLOW_HUB_SMOKE_LIVE_REPO WORKFLOW_HUB_SMOKE_LIVE_BASE WORKFLOW_HUB_SMOKE_LIVE_HEAD; do
    if [ -z "${!var_name:-}" ]; then
      echo "LIVE_VALIDATION=failed"
      echo "LIVE_VALIDATION_REASON=missing_${var_name}"
      required_missing=true
    fi
  done
  if [ "$required_missing" = "true" ]; then
    exit 1
  fi
  echo "LIVE_VALIDATION=requested"
  echo "LIVE_VALIDATION_REPO=$WORKFLOW_HUB_SMOKE_LIVE_REPO"
  echo "LIVE_VALIDATION_SCOPE=operator_supplied_safe_test_repository"
fi

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
