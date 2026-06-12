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
git -C "$hub_dir" init -q -b main
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
    - name: trunk-app
      github_repo: example/trunk-app
      default_branch: trunk
YAML
cat > "$hub_dir/.ai-dev-workflow.local.yaml" <<'YAML'
checkout_root: ../products
YAML
trunk_product_dir="$TMP_ROOT/products/trunk-app"
mkdir -p "$trunk_product_dir"
git -C "$trunk_product_dir" init -q -b trunk

solo_hub_dir="$TMP_ROOT/solo-hub"
mkdir -p "$solo_hub_dir"
git -C "$solo_hub_dir" init -q -b main
cat > "$solo_hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
YAML

echo ""
echo "=== Workflow orchestration product repository awareness ==="

lib_script="$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"

git_url_repo="$(
  bash -c 'source "$1"; workflow_github_repo_from_git_url "$2"' \
    bash "$lib_script" "ssh://git@github.com/example/admin-portal.git"
)"
run_contains "workflow_lib_derives_repo_from_ssh_url" "example/admin-portal" "$git_url_repo"

env_repo="$(
  bash -c 'source "$1"; WORKFLOW_TARGET_GITHUB_REPO=example/mobile-app repo_slug' \
    bash "$lib_script"
)"
run_contains "workflow_lib_uses_valid_repo_override" "example/mobile-app" "$env_repo"

run_fails_contains \
  "workflow_lib_rejects_invalid_repo_override" \
  "WORKFLOW_TARGET_GITHUB_REPO must be an owner/repo" \
  bash -c 'source "$1"; WORKFLOW_TARGET_GITHUB_REPO=example/mobile/app repo_slug' \
    bash "$lib_script"

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

branch_resolution_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$hub_dir" \
    --repo missing-app \
    --branch feature/900-product-routing
)"
run_contains "workflow_branch_unresolved_repo_action" "NEXT_ACTION=resolve-repository-selection" "$branch_resolution_output"
run_contains "workflow_branch_unresolved_repo_context" "ACTION_REPOSITORY_KIND=repository_resolution_failed" "$branch_resolution_output"

pr_selection_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$hub_dir" \
    --pr 123
)"
run_contains "workflow_pr_requires_repo_selection" "NEXT_ACTION=resolve-repository-selection" "$pr_selection_output"
run_contains "workflow_pr_selection_required_context" "ACTION_REPOSITORY_KIND=repository_selection_required" "$pr_selection_output"

run_fails_contains \
  "workflow_next_action_repo_requires_value" \
  "--repo requires a value." \
  "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo

run_fails_contains \
  "workflow_next_action_repo_root_requires_value" \
  "--repo-root requires a value." \
  "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root

batch_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh" \
    --repo-root "$hub_dir" \
    --repo admin-portal \
    "$hub_dev"
)"
run_contains "batch_plan_preserves_action_kind" "ACTION_REPOSITORY_KIND=product_repo_owned" "$batch_output"
run_contains "batch_plan_derives_github_repo_from_git_url" "ACTION_GITHUB_REPO=example/admin-portal" "$batch_output"

run_fails_contains \
  "batch_plan_repo_rejects_next_flag_as_value" \
  "--repo requires a value." \
  env WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh" \
    --repo \
    --repo-root "$hub_dir" \
    "$hub_dev"

run_fails_contains \
  "batch_plan_repo_root_rejects_next_flag_as_value" \
  "--repo-root requires a value." \
  env WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-batch-plan.sh" \
    --repo-root \
    --repo admin-portal \
    "$hub_dev"

stub_bin="$TMP_ROOT/bin"
mkdir -p "$stub_bin"
cat > "$stub_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "${GH_FAIL_PR_VIEW:-}" = "1" ] && [ "$1" = "pr" ] && [ "${2:-}" = "view" ]; then
  echo "simulated pr view failure" >&2
  exit 1
fi

if [ -n "${GH_ARGS_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$GH_ARGS_LOG"
fi

case "$1" in
  auth)
    exit 0
    ;;
  pr)
    if [ "$2" = "view" ]; then
      printf '{"headRefName":"feature/900-product-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}\n'
      exit 0
    fi
    if [ "$2" = "list" ]; then
      if [ -n "${GH_PR_LIST_BASE:-}" ]; then
        printf '%s\n' "$GH_PR_LIST_BASE"
        exit 0
      fi
      printf '[]\n'
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

discover_output="$(
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/discover-workflow-state.sh" \
    --repo-root "$hub_dir" \
    --repo mobile-app
)"
run_contains "discover_state_emits_action_github_repo" "ACTION_GITHUB_REPO=example/mobile-app" "$discover_output"

pr_inferred_repo_log="$TMP_ROOT/pr-inferred-repo-gh-args.log"
touch "$pr_inferred_repo_log"
pr_inferred_output="$(
  env GH_ARGS_LOG="$pr_inferred_repo_log" PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$solo_hub_dir" \
    --pr 42
)"
run_contains "workflow_pr_infers_single_product_repo" "ACTION_GITHUB_REPO=example/mobile-app" "$pr_inferred_output"
run_contains "workflow_pr_passes_inferred_repo_to_gh" "--repo example/mobile-app" "$(tr '\n' ' ' < "$pr_inferred_repo_log")"

ci_output="$(
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    7 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2
)"
run_contains "ci_loop_targets_explicit_repo" "REPO=example/mobile-app" "$ci_output"
run_contains "ci_loop_reports_green" "RESULT=green" "$ci_output"

ci_product_log="$TMP_ROOT/ci-product-gh-args.log"
ci_product_output="$(
  GH_ARGS_LOG="$ci_product_log" PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    8 \
    --repo-root "$hub_dir" \
    --product-repo mobile-app \
    --poll-interval 1 \
    --max-wait 2
)"
run_contains "ci_loop_resolves_product_repo" "REPO=example/mobile-app" "$ci_product_output"
run_contains "ci_loop_passes_resolved_repo_to_gh" "--repo example/mobile-app" "$(tr '\n' ' ' < "$ci_product_log")"

run_fails_contains \
  "ci_loop_fails_closed_when_pr_status_unreadable" \
  "REASON=pr_status_fetch_failed" \
  env GH_FAIL_PR_VIEW=1 PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    9 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2

run_fails_contains \
  "post_merge_cleanup_refuses_product_default_branch" \
  "Refusing to delete protected branch 'trunk'." \
  "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$hub_dir" \
    --repo trunk-app \
    trunk

run_fails_contains \
  "post_merge_cleanup_implementation_requires_repo_selection" \
  "pass --repo <name>" \
  "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$hub_dir" \
    feature/900-product-routing

cleanup_remote="$TMP_ROOT/integration-cleanup.git"
cleanup_repo="$TMP_ROOT/integration-cleanup"
git init --bare -q -b develop-workflow-hub-mode "$cleanup_remote"
git init -q -b develop-workflow-hub-mode "$cleanup_repo"
git -C "$cleanup_repo" config user.email "fixture@example.com"
git -C "$cleanup_repo" config user.name "Fixture User"
printf 'base\n' > "$cleanup_repo/README.md"
git -C "$cleanup_repo" add README.md
git -C "$cleanup_repo" commit -q -m "initial integration base"
git -C "$cleanup_repo" remote add origin "$cleanup_remote"
git -C "$cleanup_repo" push -q -u origin develop-workflow-hub-mode
git -C "$cleanup_repo" checkout -q -b spec/integration-cleanup
printf 'branch\n' > "$cleanup_repo/spec.txt"
git -C "$cleanup_repo" add spec.txt
git -C "$cleanup_repo" commit -q -m "spec branch fixture"
git -C "$cleanup_repo" checkout -q develop-workflow-hub-mode

cleanup_output="$(
  GH_PR_LIST_BASE=develop-workflow-hub-mode \
  WORKFLOW_TARGET_GITHUB_REPO=example/workflow-hub \
  PATH="$stub_bin:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$cleanup_repo" \
    spec/integration-cleanup
)"
run_contains \
  "post_merge_cleanup_uses_merged_pr_base" \
  "will switch to develop-workflow-hub-mode" \
  "$cleanup_output"
run_contains \
  "post_merge_cleanup_deletes_integration_branch" \
  "Deleted branch spec/integration-cleanup" \
  "$cleanup_output"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
