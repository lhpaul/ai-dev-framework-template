#!/usr/bin/env bash
# test-workflow-orchestration-product-repo-aware.sh - workflow hub routing tests.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh
# covers: scripts/development-workflow/discover-workflow-state.sh
# covers: scripts/development-workflow/workflow-batch-plan.sh
# covers: scripts/development-workflow/workflow-next-action.sh
# covers: scripts/development-workflow/pr-ci-loop.sh
# covers: scripts/development-workflow/post-merge-cleanup.sh

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

make_development_for_issue() {
  local root="$1"
  local issue="$2"
  local path="$root/docs/specs/developments/20260611120000_${issue}-routing"
  mkdir -p "$path"
  cat > "$path/1_${issue}-routing_specs.md" <<'MD'
# Routing Spec

## Acceptance Criteria

- [ ] Implementation work resolves repository ownership before mutation.
MD
  cat > "$path/2_${issue}-routing_implementation-plan.md" <<'MD'
# Routing Implementation Plan

## Summary

Resolve repository ownership before implementation work.
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
run_contains "workflow_hub_routing_product_owned" "ROUTING_OUTCOME_CODE=product_owned" "$selected_output"
run_contains "workflow_hub_routing_continue" "ROUTING_CONTINUE_ALLOWED=true" "$selected_output"
run_contains "workflow_hub_routing_selected_key" "ROUTING_SELECTED_PRODUCT_REPO_KEY=mobile-app" "$selected_output"
run_contains "workflow_hub_product_owner" "ACTION_REPOSITORY_KIND=product_repo_owned" "$selected_output"
run_contains "workflow_hub_product_repo_name" "ACTION_REPOSITORY=mobile-app" "$selected_output"
run_contains "workflow_hub_product_github_repo" "ACTION_GITHUB_REPO=example/mobile-app" "$selected_output"

missing_selection_output="$(
  env WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$hub_dir" \
    --development "$hub_dev"
)"
run_contains \
  "workflow_hub_implementation_requires_repo_selection" \
  "NEXT_ACTION=resolve-repository-selection" \
  "$missing_selection_output"
run_contains "workflow_hub_missing_target_outcome" "ROUTING_OUTCOME_CODE=missing_target" "$missing_selection_output"
run_contains "workflow_hub_missing_target_stops" "ROUTING_CONTINUE_ALLOWED=false" "$missing_selection_output"
run_contains "workflow_hub_missing_target_evidence" "ROUTING_STOP_REASON=product-owned work has no selected product repository key" "$missing_selection_output"

branch_resolution_output="$(
  WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$hub_dir" \
    --repo missing-app \
    --branch feature/900-product-routing
)"
run_contains "workflow_branch_unresolved_repo_action" "NEXT_ACTION=resolve-repository-selection" "$branch_resolution_output"
run_contains "workflow_branch_unresolved_repo_context" "ACTION_REPOSITORY_KIND=repository_resolution_failed" "$branch_resolution_output"

# The gh stub is defined here rather than further down because the --pr
# invocation below reaches require_gh in workflow-lib.sh, which shells out to
# 'gh auth status'. Without the stub that call depends on the ambient gh login:
# it passed on developer machines and exited 2 on CI runners, where gh is
# installed but unauthenticated. The suite never ran in CI to reveal that
# (issue #1537). Every later invocation already used this same stub.
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
      if [ -n "${GH_PR_VIEW_JSON:-}" ]; then
        printf '%s\n' "$GH_PR_VIEW_JSON"
        exit 0
      fi
      printf '{"headRefName":"feature/900-product-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}\n'
      exit 0
    fi
    if [ "$2" = "list" ]; then
      if [ "${GH_FAIL_PR_LIST:-}" = "1" ]; then
        echo "simulated pr list failure" >&2
        exit 1
      fi
      case " $* " in
        *" --json baseRefName "*)
          [ -n "${GH_PR_LIST_BASE:-}" ] && printf '%s\n' "$GH_PR_LIST_BASE"
          exit 0
          ;;
        *" --json number "*)
          if [ -n "${GH_PR_LIST_NUMBER:-}" ]; then
            printf '%s\n' "$GH_PR_LIST_NUMBER"
            exit 0
          fi
          if [ -n "${GH_PR_LIST_HEAD:-}" ] && [[ " $* " == *" --head ${GH_PR_LIST_HEAD} "* ]]; then
            printf '%s\n' "${GH_PR_LIST_HEAD_NUMBER:-42}"
            exit 0
          fi
          exit 0
          ;;
      esac
      exit 0
    fi
    ;;
  api)
    if [ "$2" = "graphql" ]; then
      case "$*" in
        *'projectV2(number:'*)
          printf '{"data":{"user":{"projectV2":{"id":"PVT_test"}},"organization":null}}\n'
          exit 0
          ;;
        *'issueNumber=901'*)
          printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_901","project":{"id":"PVT_test","number":1},"status":{"name":"Plan Ready"},"configuredType":null,"customType":null,"compactCustomType":null,"type":{"name":"Workflow"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
          exit 0
          ;;
        *'issueNumber=902'*)
          printf '{"data":{"repository":{"issue":{"projectItems":{"nodes":[{"id":"PVTI_902","project":{"id":"PVT_test","number":1},"status":{"name":"Plan Ready"},"configuredType":null,"customType":null,"compactCustomType":null,"type":{"name":"Feature"}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n'
          exit 0
          ;;
      esac
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

pr_selection_output="$(
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
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


typed_hub_dir="$TMP_ROOT/typed-hub"
mkdir -p "$typed_hub_dir"
git -C "$typed_hub_dir" init -q -b main
cat > "$typed_hub_dir/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
mode: workflow_hub

issue_tracker:
  provider: github_projects
  project_number: 1

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
YAML
workflow_dev="$(make_development_for_issue "$typed_hub_dir" 901)"
feature_dev="$(make_development_for_issue "$typed_hub_dir" 902)"

workflow_output="$(
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --development "$workflow_dev"
)"
run_contains "workflow_type_routes_hub_only" "ROUTING_OUTCOME_CODE=hub_only" "$workflow_output"
run_contains "workflow_type_routes_hub_owner" "ACTION_REPOSITORY_KIND=hub_owned" "$workflow_output"
run_contains "workflow_type_allows_without_repo" "ROUTING_CONTINUE_ALLOWED=true" "$workflow_output"

feature_output="$(
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --development "$feature_dev"
)"
run_contains "feature_type_requires_repo_selection" "NEXT_ACTION=resolve-repository-selection" "$feature_output"
run_contains "feature_type_missing_target" "ROUTING_OUTCOME_CODE=missing_target" "$feature_output"

workflow_pr_output="$(
  GH_PR_VIEW_JSON='{"headRefName":"feature/901-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}' \
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --pr 901
)"
# --pr without --repo used to force resolve-repository-selection even for a
# hub-only PR, because routing ran before branch_name was known (branch_name
# only came from the gh pr view call below the old preflight). PR 901's
# headRefName (mocked above) resolves issue #901, which the mocked tracker
# types as Workflow (hub-only), so this must now resolve without requiring a
# product repository selection.
run_contains "workflow_pr_without_repo_hub_only_outcome" "ROUTING_OUTCOME_CODE=hub_only" "$workflow_pr_output"
run_contains "workflow_pr_without_repo_hub_only_continues" "ROUTING_CONTINUE_ALLOWED=true" "$workflow_pr_output"
run_contains "workflow_pr_without_repo_hub_owned" "ACTION_REPOSITORY_KIND=hub_owned" "$workflow_pr_output"
run_contains "workflow_pr_without_repo_no_selection_required" "NEXT_ACTION=resolve-pr-readiness" "$workflow_pr_output"

# A spec or plan PR (or any hub-owned implementation branch) without --repo
# must resolve directly too: the implementation-only preflight used to run
# unconditionally for every --pr invocation, and implementation_issue_number()
# only recognizes feature|fix|refactor|hotfix branches, so a spec/*
# headRefName always fell through to missing_target/resolve-repository-selection
# even after branch_name was known. No product-repo routing is exercised at
# all here (no tracker/gh call beyond the single gh pr view read), since a
# non-implementation branch is classified as hub-owned without calling the
# routing classifier.
workflow_pr_spec_output="$(
  GH_PR_VIEW_JSON='{"headRefName":"spec/950-example","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}' \
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --pr 950
)"
run_contains "workflow_pr_spec_without_repo_hub_owned" "ACTION_REPOSITORY_KIND=hub_owned" "$workflow_pr_spec_output"
run_contains "workflow_pr_spec_without_repo_no_selection_required" "NEXT_ACTION=resolve-pr-readiness" "$workflow_pr_spec_output"
run_equals "workflow_pr_spec_without_repo_no_routing_outcome" "0" "$(grep -c '^ROUTING_OUTCOME_CODE=' <<< "$workflow_pr_spec_output" || true)"

workflow_pr_plan_output="$(
  GH_PR_VIEW_JSON='{"headRefName":"implementation-plan/950-example","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}' \
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --pr 951
)"
run_contains "workflow_pr_plan_without_repo_hub_owned" "ACTION_REPOSITORY_KIND=hub_owned" "$workflow_pr_plan_output"
run_contains "workflow_pr_plan_without_repo_no_selection_required" "NEXT_ACTION=resolve-pr-readiness" "$workflow_pr_plan_output"

workflow_pr_selected_repo_output="$(
  GH_PR_VIEW_JSON='{"headRefName":"feature/901-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[]}' \
  PATH="$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --repo mobile-app \
    --pr 901
)"
run_contains "workflow_pr_selected_repo_rechecks_branch_identity" "NEXT_ACTION=resolve-repository-selection" "$workflow_pr_selected_repo_output"
run_contains "workflow_pr_selected_repo_hub_only_conflict" "ROUTING_OUTCOME_CODE=ambiguous_target" "$workflow_pr_selected_repo_output"

provider_fail_bin="$TMP_ROOT/provider-fail-bin"
real_awk="$(command -v awk)"
mkdir -p "$provider_fail_bin"
cat > "$provider_fail_bin/awk" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = "-v" ] && [ "\${2:-}" = "section=issue_tracker" ]; then
  echo "simulated provider resolver failure" >&2
  exit 2
fi
exec "$real_awk" "\$@"
SH
chmod +x "$provider_fail_bin/awk"
run_fails_contains \
  "workflow_provider_resolution_failure_fails_closed" \
  "ERROR: could not resolve issue tracker provider" \
  env PATH="$provider_fail_bin:$stub_bin:$PATH" WORKFLOW_SKIP_FETCH=1 "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$typed_hub_dir" \
    --repo mobile-app \
    --development "$workflow_dev"

discover_output="$(
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/discover-workflow-state.sh" \
    --repo-root "$hub_dir" \
    --repo mobile-app
)"
run_contains "discover_state_emits_action_github_repo" "ACTION_GITHUB_REPO=example/mobile-app" "$discover_output"

pr_missing_repo_log="$TMP_ROOT/pr-missing-repo-gh-args.log"
touch "$pr_missing_repo_log"
pr_missing_output="$(
  env GH_ARGS_LOG="$pr_missing_repo_log" PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/workflow-next-action.sh" \
    --repo-root "$solo_hub_dir" \
    --pr 42
)"
run_contains "workflow_pr_requires_explicit_product_repo" "NEXT_ACTION=resolve-repository-selection" "$pr_missing_output"
run_contains "workflow_pr_missing_repo_outcome" "ROUTING_OUTCOME_CODE=missing_target" "$pr_missing_output"
run_equals "workflow_pr_does_not_query_implicit_product_repo" "0" "$(grep -c -- '--repo example/mobile-app' "$pr_missing_repo_log" || true)"

ci_output="$(
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    7 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2
)"
run_contains "ci_loop_targets_explicit_repo" "REPO=example/mobile-app" "$ci_output"
run_contains "ci_loop_reports_green" "RESULT=green" "$ci_output"

ci_haystack_config="$TMP_ROOT/ci-haystack-workflow.yaml"
cat > "$ci_haystack_config" <<'YAML'
schema_version: 2
review:
  on_ready:
    github:
      - haystack
YAML

ci_haystack_review_output="$(
  AI_DEV_WORKFLOW_CONFIG_FILE="$ci_haystack_config" \
  GH_PR_VIEW_JSON='{"headRefName":"feature/900-product-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"},{"__typename":"CheckRun","name":"Unit Tests","status":"COMPLETED","conclusion":"SUCCESS"}]}' \
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    70 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2
)"
run_contains "ci_loop_ignores_configured_haystack_review_check" "RESULT=green" "$ci_haystack_review_output"
run_contains "ci_loop_reports_ignored_reviewer_check" "REVIEWER_CHECKS=Haystack / Review" "$ci_haystack_review_output"
run_contains "ci_loop_reports_structured_reviewer_check_json" 'REVIEWER_CHECKS_JSON=[{"name":"Haystack / Review","provider":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"' "$ci_haystack_review_output"
run_contains "ci_loop_counts_only_ci_checks" "TOTAL_CHECK_COUNT=1" "$ci_haystack_review_output"

ci_custom_haystack_review_output="$(
  AI_DEV_WORKFLOW_CONFIG_FILE="$ci_haystack_config" \
  HAYSTACK_CHECK_NAME="Custom Haystack Review" \
  GH_PR_VIEW_JSON='{"headRefName":"feature/900-product-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"Custom Haystack Review","status":"COMPLETED","conclusion":"FAILURE"},{"__typename":"CheckRun","name":"Unit Tests","status":"COMPLETED","conclusion":"SUCCESS"}]}' \
  PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    72 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2
)"
run_contains "ci_loop_uses_custom_haystack_check_name" "RESULT=green" "$ci_custom_haystack_review_output"
run_contains "ci_loop_reports_custom_reviewer_check" "REVIEWER_CHECKS=Custom Haystack Review" "$ci_custom_haystack_review_output"
run_contains "ci_loop_structured_reviewer_check_uses_custom_name" '"name":"Custom Haystack Review"' "$ci_custom_haystack_review_output"

run_fails_contains \
  "ci_loop_still_fails_real_ci_with_haystack_review_check" \
  "FAILING_CHECKS=Unit Tests" \
  env AI_DEV_WORKFLOW_CONFIG_FILE="$ci_haystack_config" \
    GH_PR_VIEW_JSON='{"headRefName":"feature/900-product-routing","labels":[],"isDraft":false,"comments":[],"statusCheckRollup":[{"__typename":"CheckRun","name":"Haystack / Review","status":"COMPLETED","conclusion":"FAILURE"},{"__typename":"CheckRun","name":"Unit Tests","status":"COMPLETED","conclusion":"FAILURE"}]}' \
    PATH="$stub_bin:$PATH" "$REPO_ROOT/scripts/development-workflow/pr-ci-loop.sh" \
    71 \
    --repo example/mobile-app \
    --poll-interval 1 \
    --max-wait 2

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

run_fails_contains \
  "post_merge_cleanup_refuses_main_branch" \
  "Refusing to delete protected branch 'main'." \
  "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$hub_dir" \
    main

run_fails_contains \
  "post_merge_cleanup_fails_when_merged_base_unknown" \
  "could not determine merged PR base" \
  env WORKFLOW_TARGET_GITHUB_REPO=example/workflow-hub \
    PATH="$stub_bin:$PATH" \
    "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$hub_dir" \
    spec/integration-cleanup

run_fails_contains \
  "post_merge_cleanup_fails_when_merged_base_query_fails" \
  "could not query merged PR base" \
  env GH_FAIL_PR_LIST=1 \
    WORKFLOW_TARGET_GITHUB_REPO=example/workflow-hub \
    PATH="$stub_bin:$PATH" \
    "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$hub_dir" \
    spec/integration-cleanup

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
git -C "$cleanup_repo" checkout -q -b spec/base-override
printf 'override\n' > "$cleanup_repo/override.txt"
git -C "$cleanup_repo" add override.txt
git -C "$cleanup_repo" commit -q -m "base override fixture"
git -C "$cleanup_repo" checkout -q develop-workflow-hub-mode

run_fails_contains \
  "post_merge_cleanup_refuses_resolved_base_branch" \
  "Refusing to delete protected branch 'develop-workflow-hub-mode'." \
  env GH_PR_LIST_BASE=develop-workflow-hub-mode \
    WORKFLOW_TARGET_GITHUB_REPO=example/workflow-hub \
    PATH="$stub_bin:$PATH" \
    "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$cleanup_repo" \
    develop-workflow-hub-mode

base_override_output="$(
  GH_PR_LIST_BASE=wrong-base \
  WORKFLOW_TARGET_GITHUB_REPO=example/workflow-hub \
  PATH="$stub_bin:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$cleanup_repo" \
    --base develop-workflow-hub-mode \
    spec/base-override
)"
run_contains \
  "post_merge_cleanup_base_override_precedes_lookup" \
  "will switch to develop-workflow-hub-mode" \
  "$base_override_output"
run_contains \
  "post_merge_cleanup_base_override_deletes_branch" \
  "Deleted branch spec/base-override" \
  "$base_override_output"

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

already_deleted_output="$(
  GH_PR_LIST_BASE=develop-workflow-hub-mode \
  GH_PR_LIST_HEAD=spec/already-deleted \
  GH_PR_LIST_HEAD_NUMBER=99 \
  WORKFLOW_TARGET_GITHUB_REPO=example/workflow-hub \
  PATH="$stub_bin:$PATH" \
  "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$cleanup_repo" \
    spec/already-deleted
)"
run_contains \
  "post_merge_cleanup_continues_when_local_branch_missing" \
  "already gone; verified merged PR #99" \
  "$already_deleted_output"
run_contains \
  "post_merge_cleanup_skips_delete_when_local_branch_missing" \
  "Skipping local branch delete" \
  "$already_deleted_output"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
