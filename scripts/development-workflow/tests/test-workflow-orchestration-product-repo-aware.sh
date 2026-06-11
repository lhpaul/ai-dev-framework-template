#!/usr/bin/env bash
# test-workflow-orchestration-product-repo-aware.sh - workflow hub routing tests.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

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

make_development() {
  local root="$1"
  local path="$root/docs/specs/developments/20260611120000_900-product-routing"
  mkdir -p "$path"
  cat > "$path/1_900-product-routing_specs.md" <<'MD'
# Product Routing Spec

## Acceptance Criteria

- [ ] Implementation work targets a selected product repository.
MD
  cat > "$path/2_900-product-routing_implementation-plan.md" <<'MD'
# Product Routing Implementation Plan

## Summary

Route implementation work to a product repository.
MD
  printf '%s\n' "$path"
}

single_dir="$TMP_ROOT/single"
mkdir -p "$single_dir"
single_dev="$(make_development "$single_dir")"

hub_dir="$TMP_ROOT/hub"
mkdir -p "$hub_dir"
hub_dev="$(make_development "$hub_dir")"
cat > "$hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
    - name: admin-portal
      git_url: git@github.com:example/admin-portal.git
      default_branch: develop
YAML
cat > "$hub_dir/.ai-dev-workflow.local.yaml" <<'YAML'
checkout_root: ../products
YAML

echo ""
echo "=== Workflow orchestration product repository awareness ==="

single_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$single_dir" \
    --development "$single_dev"
)"
run_contains "single_repo_next_action_context" "WORKFLOW_MODE=single_repo" "$single_output"
run_contains "single_repo_action_kind" "ACTION_REPOSITORY_KIND=single_repo_context" "$single_output"

selected_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$hub_dir" \
    --repo mobile-app \
    --development "$hub_dev"
)"
run_contains "workflow_hub_next_action_context" "WORKFLOW_MODE=workflow_hub" "$selected_output"
run_contains "workflow_hub_product_owner" "ACTION_REPOSITORY_KIND=product_repo_owned" "$selected_output"
run_contains "workflow_hub_product_repo_name" "ACTION_REPOSITORY=mobile-app" "$selected_output"
run_contains "workflow_hub_product_github_repo" "ACTION_GITHUB_REPO=example/mobile-app" "$selected_output"

run_fails_contains \
  "workflow_hub_implementation_requires_repo_selection" \
  "product repository selection is ambiguous" \
  env WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$hub_dir" \
    --development "$hub_dev"

batch_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh" \
    --repo-root "$hub_dir" \
    --repo admin-portal \
    "$hub_dev"
)"
run_contains "batch_plan_preserves_action_kind" "ACTION_REPOSITORY_KIND=product_repo_owned" "$batch_output"
run_contains "batch_plan_derives_github_repo_from_git_url" "ACTION_GITHUB_REPO=example/admin-portal" "$batch_output"

stub_bin="$TMP_ROOT/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "$1" in
  auth)
    exit 0
    ;;
  pr)
    if [ "$2" = "view" ]; then
      printf '{"statusCheckRollup":[]}\n'
      exit 0
    fi
    ;;
  repo)
    if [ "$2" = "view" ]; then
      printf '{"nameWithOwner":"example/hub"}\n'
      exit 0
    fi
    ;;
esac

echo "unexpected gh invocation: $*" >&2
exit 1
SH
chmod +x "$stub_bin/gh"

ci_output="$(
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    7 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2
)"
run_contains "ci_loop_targets_explicit_repo" "REPO=example/mobile-app" "$ci_output"
run_contains "ci_loop_reports_green" "RESULT=green" "$ci_output"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
