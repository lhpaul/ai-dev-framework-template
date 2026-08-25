#!/usr/bin/env bash
# test-reviewer-loop-guard-workflow.sh - Static checks for consolidated PR policy workflow.
#
# Usage: bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh
# covers: .github/workflows/pr-policy.yml
# The three workflows below no longer exist — they were consolidated into
# pr-policy.yml, and this suite asserts they stay gone. Declaring them is
# deliberate, not a stale path: re-adding any of them must run this suite.
# covers: .github/workflows/reviewer-loop-guard.yml
# covers: .github/workflows/apply-regression-label.yml
# covers: .github/workflows/remove-regression-label-on-push.yml

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/pr-policy.yml"

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

contains() {
  local pattern="$1"
  grep -Fq -- "$pattern" "$WORKFLOW" && echo yes || echo no
}

not_contains() {
  local pattern="$1"
  grep -Fq -- "$pattern" "$WORKFLOW" && echo no || echo yes
}

echo ""
echo "=== Consolidated PR policy workflow static checks ==="

run_test "workflow_exists" "yes" "$([ -f "$WORKFLOW" ] && echo yes || echo no)"
run_test "old_apply_workflow_removed" "yes" "$([ ! -f "$REPO_ROOT/.github/workflows/apply-regression-label.yml" ] && echo yes || echo no)"
run_test "old_remove_workflow_removed" "yes" "$([ ! -f "$REPO_ROOT/.github/workflows/remove-regression-label-on-push.yml" ] && echo yes || echo no)"
run_test "old_guard_workflow_removed" "yes" "$([ ! -f "$REPO_ROOT/.github/workflows/reviewer-loop-guard.yml" ] && echo yes || echo no)"
run_test "pull_request_target_trigger_present" "yes" "$(contains "pull_request_target:")"
run_test "issue_comment_trigger_present" "yes" "$(contains "issue_comment:")"
run_test "issue_comment_created_edited" "yes" "$(contains "types: [created, edited]")"
run_test "pr_event_types_preserved" "yes" "$(contains "types: [opened, reopened, ready_for_review, synchronize]")"
run_test "summary_comments_get_separate_concurrency" "yes" "$(contains "'summary-comment' ||")"
run_test "non_summary_comments_get_separate_concurrency" "yes" "$(contains "'non-summary' ||")"
run_test "synchronize_events_get_separate_concurrency" "yes" "$(contains "'pr-synchronize' ||")"
run_test "label_apply_events_get_separate_concurrency" "yes" "$(contains "'pr-label-and-guard' ||")"
run_test "pr_events_get_separate_concurrency" "yes" "$(contains "'pr-event'")"
run_test "guard_path_cancels_stale_runs" "yes" "$(contains "cancel-in-progress: true")"

run_test "no_default_max_wait" "yes" "$(not_contains "GUARD_MAX_WAIT")"
run_test "no_poll_interval" "yes" "$(not_contains "GUARD_POLL_INTERVAL")"
run_test "no_sleep_polling" "yes" "$(not_contains "sleep ")"
run_test "no_checkout" "yes" "$(not_contains "actions/checkout")"
run_test "missing_summary_fails_without_elapsed_wait" "yes" "$(contains "No reviewer-loop summary found. Run the automated reviewer loop before merging.")"

run_test "summary_marker_one_checked" "yes" "$(contains "MARKER1=\"### Automated Reviewer Loop Summary\"")"
run_test "summary_marker_two_checked" "yes" "$(contains "MARKER2='*Posted automatically by \`pr-review-loop.sh\`.*'")"
run_test "summary_marker_two_required_in_comment_scan" "yes" "$(contains '(.body // "" | contains($m2))')"
run_test "non_summary_comment_skips" "yes" "$(contains "Issue comment does not contain the canonical reviewer-loop summary markers; skipping.")"
run_test "summary_comment_payload_is_counted" "yes" "$(contains "Fresh comment listing did not include triggering summary comment; counting event payload.")"
run_test "comment_path_fetches_current_pr" "yes" "$(contains 'gh api "repos/$REPO/pulls/$PR_NUMBER"')"
run_test "comment_path_fetches_current_comments" "yes" "$(contains 'gh api "repos/$REPO/issues/$PR_NUMBER/comments"')"
run_test "metadata_fetch_failure_posts_status" "yes" "$(contains "Could not fetch PR metadata. Re-run the workflow to retry.")"
run_test "missing_head_sha_failure_posts_status" "yes" "$(contains "Could not resolve PR head SHA. Re-run the workflow to retry.")"
run_test "missing_head_branch_failure_posts_status" "yes" "$(contains "Could not resolve PR head branch. Re-run the workflow to retry.")"
run_test "missing_base_branch_failure_posts_status" "yes" "$(contains "Could not resolve PR base branch. Re-run the workflow to retry.")"
run_test "missing_head_repo_failure_posts_status" "yes" "$(contains "Could not resolve PR head repository. Re-run the workflow to retry.")"
run_test "metadata_failure_uses_event_sha" "yes" "$(contains '${EVENT_HEAD_SHA:-}')"
run_test "failure_status_helper_present" "yes" "$(contains "post_failure_status_if_possible()")"

run_test "fork_head_guard_present" "yes" "$(contains 'HEAD_REPO" != "$REPO')"
run_test "fork_head_skip_no_mutation" "yes" "$(contains "skipping privileged PR policy mutation")"
run_test "out_of_scope_success_preserved" "yes" "$(contains "Not an implementation branch; guard skipped.")"
run_test "status_context_preserved" "yes" "$(contains 'Reviewer-loop completion guard (#${PR_NUMBER})')"
run_test "in_scope_prefixes_preserved" "yes" "$(contains "IN_SCOPE_PREFIXES: \"feature/ fix/ refactor/ hotfix/\"")"

run_test "regression_label_constant_preserved" "yes" "$(contains "LABEL_NAME=\"ready-for-regression\"")"
run_test "regression_label_create_preserved" "yes" "$(contains 'gh label create "$LABEL_NAME"')"
run_test "regression_label_create_race_handled" "yes" "$(contains "Concurrent creator race")"
run_test "label_applies_on_open_reopen_ready" "yes" "$(contains "opened|reopened|ready_for_review)")"
run_test "label_add_preserved" "yes" "$(contains '--add-label "$LABEL_NAME"')"
run_test "label_add_failure_continues_to_guard" "yes" "$(contains "Continuing to reviewer-loop guard status.")"
run_test "regression_workflow_default_present" "yes" "$(contains "vars.PR_POLICY_REGRESSION_WORKFLOW || 'e2e-regression.yml'")"
run_test "regression_dispatch_disable_var_present" "yes" "$(contains "vars.PR_POLICY_REGRESSION_DISPATCH_ENABLED || 'true'")"
run_test "regression_dispatch_disable_guard_present" "yes" "$(contains "Regression workflow dispatch disabled by PR_POLICY_REGRESSION_DISPATCH_ENABLED")"
run_test "regression_workflow_dispatch_present" "yes" "$(contains 'gh workflow run "$REGRESSION_WORKFLOW"')"
run_test "regression_dispatch_uses_head_ref" "yes" "$(contains '--ref "$BRANCH"')"
run_test "regression_dispatch_uses_pr_number" "yes" "$(contains '-f pr_number="$PR_NUMBER"')"
run_test "regression_dispatch_uses_head_sha" "yes" "$(contains '-f head_sha="$HEAD_SHA"')"
run_test "regression_dispatch_uses_base_ref" "yes" "$(contains '-f base_ref="$BASE_BRANCH"')"
run_test "regression_dispatch_gates_base_branch" "yes" "$(contains "develop|develop-*|main)")"
run_test "dispatch_disabled_skips_label" "yes" "$(contains "skipping \${LABEL_NAME}")"
run_test "dispatch_failure_skips_label" "yes" "$(contains "Skipping \${LABEL_NAME} and continuing to reviewer-loop guard status.")"
run_test "dispatch_revalidates_head_before_label" "yes" "$(contains "refresh_pr_metadata()")"
run_test "dispatch_redispatches_on_stale_head" "yes" "$(contains "Redispatching regression for the current head.")"
run_test "dispatch_skips_label_after_repeated_head_change" "yes" "$(contains "changed again after regression dispatch")"
run_test "synchronize_removes_stale_label" "yes" "$(contains 'EVENT_ACTION" = "synchronize"')"
run_test "label_remove_preserved" "yes" "$(contains '--remove-label "$LABEL_NAME"')"
run_test "label_removal_skips_on_comment_failure" "yes" "$(contains "Skipping label removal to avoid dropping a loop-applied label on API failure.")"
run_test "label_removal_skips_after_summary" "yes" "$(contains 'Reviewer loop has already run on PR #${PR_NUMBER}')"
run_test "label_policy_failure_flag_present" "yes" "$(contains "LABEL_POLICY_FAILED=true")"
run_test "label_policy_failure_after_guard_status" "yes" "$(contains "PR policy label mutation failed after reviewer-loop guard status was posted.")"

run_test "permissions_include_issues_write" "yes" "$(contains "issues: write")"
run_test "permissions_include_pull_requests_write" "yes" "$(contains "pull-requests: write")"
run_test "permissions_include_statuses_write" "yes" "$(contains "statuses: write")"
run_test "permissions_include_actions_write" "yes" "$(contains "actions: write")"

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
