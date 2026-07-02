#!/usr/bin/env bash
# test-reviewer-loop-guard-workflow.sh - Static checks for reviewer-loop guard workflow.
#
# Usage: bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/reviewer-loop-guard.yml"

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
echo "=== Reviewer-loop guard workflow static checks ==="

run_test "workflow_exists" "yes" "$([ -f "$WORKFLOW" ] && echo yes || echo no)"
run_test "pull_request_target_trigger_present" "yes" "$(contains "pull_request_target:")"
run_test "issue_comment_trigger_present" "yes" "$(contains "issue_comment:")"
run_test "issue_comment_created_edited" "yes" "$(contains "types: [created, edited]")"
run_test "pr_event_types_preserved" "yes" "$(contains "types: [opened, reopened, ready_for_review, synchronize]")"
run_test "non_summary_comments_do_not_cancel_summary_refresh" "yes" "$(contains "cancel-in-progress: false")"

run_test "no_default_max_wait" "yes" "$(not_contains "GUARD_MAX_WAIT")"
run_test "no_poll_interval" "yes" "$(not_contains "GUARD_POLL_INTERVAL")"
run_test "no_sleep_polling" "yes" "$(not_contains "sleep ")"
run_test "missing_summary_fails_without_elapsed_wait" "yes" "$(contains "No reviewer-loop summary found. Run the automated reviewer loop before merging.")"

run_test "summary_marker_one_checked" "yes" "$(contains "MARKER1=\"### Automated Reviewer Loop Summary\"")"
run_test "summary_marker_two_checked" "yes" "$(contains "MARKER2='*Posted automatically by \`pr-review-loop.sh\`.*'")"
run_test "non_summary_comment_skips" "yes" "$(contains "Issue comment does not contain the canonical reviewer-loop summary markers; skipping.")"
run_test "summary_comment_payload_is_counted" "yes" "$(contains "Fresh comment listing did not include triggering summary comment; counting event payload.")"
run_test "comment_path_fetches_current_pr" "yes" "$(contains 'gh api "repos/$REPO/pulls/$PR_NUMBER"')"
run_test "comment_path_fetches_current_comments" "yes" "$(contains 'gh api "repos/$REPO/issues/$PR_NUMBER/comments"')"
run_test "metadata_fetch_failure_posts_status" "yes" "$(contains "Could not fetch PR metadata. Re-run the workflow to retry.")"
run_test "missing_head_sha_failure_posts_status" "yes" "$(contains "Could not resolve PR head SHA. Re-run the workflow to retry.")"
run_test "missing_head_branch_failure_posts_status" "yes" "$(contains "Could not resolve PR head branch. Re-run the workflow to retry.")"
run_test "missing_head_repo_failure_posts_status" "yes" "$(contains "Could not resolve PR head repository. Re-run the workflow to retry.")"
run_test "metadata_failure_uses_event_sha" "yes" "$(contains '${EVENT_HEAD_SHA:-}')"
run_test "failure_status_helper_present" "yes" "$(contains "post_failure_status_if_possible()")"

run_test "fork_head_guard_present" "yes" "$(contains 'HEAD_REPO" != "$REPO')"
run_test "fork_head_skip_no_status" "yes" "$(contains "skipping guard status")"
run_test "out_of_scope_success_preserved" "yes" "$(contains "Not an implementation branch; guard skipped.")"
run_test "status_context_preserved" "yes" "$(contains 'Reviewer-loop completion guard (#${PR_NUMBER})')"
run_test "in_scope_prefixes_preserved" "yes" "$(contains "IN_SCOPE_PREFIXES: \"feature/ fix/ refactor/ hotfix/\"")"

run_test "permissions_include_issues_read" "yes" "$(contains "issues: read")"
run_test "permissions_include_pull_requests_read" "yes" "$(contains "pull-requests: read")"
run_test "permissions_include_statuses_write" "yes" "$(contains "statuses: write")"

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
