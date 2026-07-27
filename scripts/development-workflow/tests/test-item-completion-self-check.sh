#!/usr/bin/env bash
# test-item-completion-self-check.sh - completion self-check helper tests.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/item-completion-self-check.sh"
TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *) exit "$status" ;;
  esac
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
if [ -n "${MOCK_GH_LOG:-}" ]; then
  printf 'gh %s\n' "$*" >> "$MOCK_GH_LOG"
fi

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  case "${MOCK_GH_PR_MODE:-happy}" in
    wrong_base)
      cat <<'JSON'
{"number":17,"baseRefName":"main","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    missing_label)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    failing_ci)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    stale_ci_success)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","completedAt":"2026-07-27T14:28:15Z"},{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","completedAt":"2026-07-27T14:32:14Z"}],"comments":[{"body":"Automated Reviewer Loop Summary Result: clean"}]}
JSON
      ;;
    failing_status_context)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"context":"legacy-ci","state":"FAILURE"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    no_summary)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[]}
JSON
      ;;
    null_ci)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":null,"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    non_clean_summary)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"needs-fixes"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: needs_fixes"}]}
JSON
      ;;
    external_file)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"app/out-of-scope.js"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    reviewer_check_failure)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"Cursor Bugbot","status":"COMPLETED","conclusion":"FAILURE"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    reviewer_workflow_failure)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"workflowName":"Cursor Bugbot","status":"COMPLETED","conclusion":"FAILURE"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    wrong_head_oid)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","headRefOid":"0000000000000000000000000000000000000000","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
    invalid_json)
      printf '{not json]\n'
      ;;
    *)
      cat <<'JSON'
{"number":17,"baseRefName":"develop","headRefName":"feature/1202-self-check","isDraft":false,"labels":[{"name":"ready-for-human-review"}],"files":[{"path":"docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"}],"statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}],"comments":[{"body":"Automated Reviewer Loop Summary\n\nResult: clean"}]}
JSON
      ;;
  esac
  exit 0
fi

if [ "$1" = "api" ]; then
  case "${2:-}" in
    repos/*/issues/17/comments) ;;
    *) false ;;
  esac && {
  case "${MOCK_GH_SUMMARY_MODE:-${MOCK_GH_PR_MODE:-happy}}" in
    fetch_failed)
      printf 'issue comments unavailable\n' >&2
      exit 3
      ;;
    no_summary)
      ;;
    non_clean_summary)
      cat <<'JSON'
{"body":"Automated Reviewer Loop Summary\n\nResult: needs_fixes","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
JSON
      ;;
    stale_non_clean_summary)
      cat <<'JSON'
{"body":"Automated Reviewer Loop Summary\n\nResult: clean","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
{"body":"Automated Reviewer Loop Summary\n\nResult: needs_fixes","created_at":"2026-01-01T00:01:00Z","updated_at":"2026-01-01T00:01:00Z"}
JSON
      ;;
    bold_clean_summary)
      cat <<'JSON'
{"body":"### Automated Reviewer Loop Summary\n\n**Result:** clean — no blocking feedback","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
JSON
      ;;
    *)
      cat <<'JSON'
{"body":"Automated Reviewer Loop Summary\n\nResult: clean","created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}
JSON
      ;;
  esac
  exit 0
  }
fi

if [ "$1" = "api" ]; then
  case "${2:-}" in
    repos/*/pulls/17/comments) ;;
    *) false ;;
  esac && {
  case "${MOCK_GH_REST_THREAD_MODE:-clean}" in
    unreplied)
      cat <<'JSON'
[{"id":901,"in_reply_to_id":null,"user":{"login":"cursor[bot]"},"body":"outside diff finding"}]
JSON
      ;;
    replied)
      cat <<'JSON'
[{"id":901,"in_reply_to_id":null,"user":{"login":"cursor[bot]"},"body":"outside diff finding"},{"id":902,"in_reply_to_id":901,"user":{"login":"lhpaul"},"body":"ack"}]
JSON
      ;;
    *)
      printf '[]\n'
      ;;
  esac
  exit 0
  }
fi

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case "${MOCK_GH_THREAD_MODE:-clean}" in
    fetch_failed)
      printf 'graphql unavailable\n' >&2
      exit 3
      ;;
    unresolved)
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"databaseId":901,"author":{"login":"cursor"},"body":"blocking thread"}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
      ;;
    addressed)
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"cursor"},"body":"✅ Addressed in latest commit"}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
      ;;
    human)
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"lhpaul"},"body":"human comment"}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
      ;;
    paginated)
      case "$*" in
        *"cursor=PAGE2"*)
          cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"databaseId":903,"author":{"login":"cursor"},"body":"blocking thread on second page"}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
          ;;
        *)
          cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"isResolved":false,"isOutdated":false,"comments":{"nodes":[{"author":{"login":"lhpaul"},"body":"human first page"}]}}],"pageInfo":{"hasNextPage":true,"endCursor":"PAGE2"}}}}}}
JSON
          ;;
      esac
      ;;
    *)
      cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
      ;;
  esac
  exit 0
fi

if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  printf 'example/repo\n'
  exit 0
fi

printf 'unexpected gh invocation: gh %s\n' "$*" >&2
exit 64
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

run_contains() {
  local name="$1" expected="$2" actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

self_check_output() {
  local status output
  set +e
  output="$("$HELPER" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

status_code() {
  head -n 1 <<< "$1"
}

body() {
  tail -n +2 <<< "$1"
}

make_repo() {
  local name="$1"
  local repo="$TMP_ROOT/$name/repo"
  mkdir -p "$repo"
  git init -q -b develop "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
  git -C "$repo" switch -q -c feature/1202-self-check
  repo="$(CDPATH='' cd -- "$repo" && pwd -P)"
  printf '%s\n' "$repo"
}

echo ""
echo "=== item completion self-check ==="

repo="$(make_repo happy)"
gh_log="$TMP_ROOT/target-repo-gh.log"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
export WORKFLOW_TARGET_GITHUB_REPO="example/product-repo"
export MOCK_GH_LOG="$gh_log"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --expected-label ready-for-human-review \
  --forbid-label needs-fixes \
  --require-review-summary true \
  --expected-tracker-status "Development in Review")"
unset WORKFLOW_TARGET_GITHUB_REPO MOCK_GH_LOG
run_test "happy_exit_zero" "0" "$(status_code "$out")"
run_contains "happy_heading" "## Ground-Truth Completion Verification" "$(body "$out")"
run_contains "happy_result" "- Result: verified" "$(body "$out")"
run_contains "happy_pr_base" "| pull_request.base | verified | develop |" "$(body "$out")"
run_contains "happy_tracker" "| tracker.status | verified | Development in Review |" "$(body "$out")"
run_contains "target_repo_pr_view_uses_repo" "gh pr view 17 --repo example/product-repo" "$(cat "$gh_log")"

repo="$(make_repo no-pr)"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Plan Ready"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --expected-tracker-status "Plan Ready")"
run_test "no_pr_exit_zero" "0" "$(status_code "$out")"
run_contains "no_pr_not_applicable" "| pull_request | not_applicable | no PR supplied |" "$(body "$out")"

repo="$(make_repo default-repo-root)"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Plan Ready"
out="$(self_check_output \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --expected-tracker-status "Plan Ready")"
run_test "default_repo_root_uses_worktree_exit_zero" "0" "$(status_code "$out")"
run_contains "default_repo_root_path_verified" "| workspace.path | verified | $repo |" "$(body "$out")"

repo="$(make_repo worktree-main)"
worktree_path="$TMP_ROOT/parallel-worktree"
git -C "$repo" switch -q develop
git -C "$repo" branch -D feature/1202-self-check >/dev/null
git -C "$repo" worktree add -q -b feature/1202-self-check "$worktree_path"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$worktree_path" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$worktree_path" \
  --require-ci-green false \
  --tracker-required false)"
run_test "parallel_worktree_exit_zero" "0" "$(status_code "$out")"
run_contains "parallel_worktree_path" "$worktree_path" "$(body "$out")"
run_contains "parallel_worktree_evidence" "| workspace.worktrees | verified |" "$(body "$out")"

repo="$(make_repo returned-to-base)"
git -C "$repo" switch -q develop
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --expected-label ready-for-human-review \
  --tracker-required false)"
run_test "returned_to_base_exit_zero" "0" "$(status_code "$out")"
run_contains "returned_to_base_branch_allowed" "| repository.branch | verified | develop | local checkout returned to expected base; PR head check verifies item branch |" "$(body "$out")"
run_contains "returned_to_base_worktree_allowed" "| workspace.worktrees | verified | local checkout returned to expected base; PR head check verifies item branch |" "$(body "$out")"

repo="$(make_repo wrong-base)"
export MOCK_GH_PR_MODE=wrong_base
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --expected-label ready-for-human-review \
  --expected-tracker-status "Development in Review")"
unset MOCK_GH_PR_MODE
run_test "wrong_base_exit_one" "1" "$(status_code "$out")"
run_contains "wrong_base_discrepancy" "| pull_request.base | discrepancy | expected=develop observed=main |" "$(body "$out")"
run_contains "wrong_base_result" "- Result: discrepancy" "$(body "$out")"

repo="$(make_repo missing-label)"
export MOCK_GH_PR_MODE=missing_label
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --expected-label ready-for-human-review)"
unset MOCK_GH_PR_MODE
run_test "missing_label_exit_one" "1" "$(status_code "$out")"
run_contains "missing_label_discrepancy" "| pull_request.label.ready-for-human-review | discrepancy |" "$(body "$out")"

repo="$(make_repo dirty)"
printf 'dirty\n' >> "$repo/README.md"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false)"
run_test "dirty_exit_one" "1" "$(status_code "$out")"
run_contains "dirty_status_discrepancy" "| workspace.status | discrepancy |" "$(body "$out")"

repo="$(make_repo failing-ci)"
export MOCK_GH_PR_MODE=failing_ci
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "failing_ci_exit_one" "1" "$(status_code "$out")"
run_contains "failing_ci_discrepancy" "| pull_request.ci | discrepancy | ci:FAILURE |" "$(body "$out")"

repo="$(make_repo stale-ci-success)"
export MOCK_GH_PR_MODE=stale_ci_success
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "stale_ci_success_exit_zero" "0" "$(status_code "$out")"
run_contains "stale_ci_success_verified" "| pull_request.ci | verified | ci:SUCCESS |" "$(body "$out")"

repo="$(make_repo changed-file-scope)"
export MOCK_GH_PR_MODE=external_file
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --changed-file-prefix docs/workflow/)"
unset MOCK_GH_PR_MODE
run_test "changed_file_scope_exit_one" "1" "$(status_code "$out")"
run_contains "changed_file_scope_discrepancy" "| pull_request.changed_files | discrepancy | outside_prefix=app/out-of-scope.js |" "$(body "$out")"

repo="$(make_repo invalid-json)"
export MOCK_GH_PR_MODE=invalid_json
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "invalid_json_exit_one" "1" "$(status_code "$out")"
run_contains "invalid_json_structured" "| pull_request | unavailable_required | invalid JSON from gh pr view |" "$(body "$out")"

repo="$(make_repo failing-status-context)"
export MOCK_GH_PR_MODE=failing_status_context
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "failing_status_context_exit_one" "1" "$(status_code "$out")"
run_contains "failing_status_context_discrepancy" "| pull_request.ci | discrepancy | legacy-ci:FAILURE |" "$(body "$out")"

repo="$(make_repo null-ci)"
export MOCK_GH_PR_MODE=null_ci
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "null_ci_exit_zero" "0" "$(status_code "$out")"
run_contains "null_ci_structured" "| pull_request.ci | verified | no checks |" "$(body "$out")"

repo="$(make_repo reviewer-check-failure)"
export MOCK_GH_PR_MODE=reviewer_check_failure
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "reviewer_check_failure_excluded_exit_zero" "0" "$(status_code "$out")"
run_contains "reviewer_check_failure_excluded" "| pull_request.ci | verified | no checks |" "$(body "$out")"

repo="$(make_repo reviewer-workflow-failure)"
export MOCK_GH_PR_MODE=reviewer_workflow_failure
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "reviewer_workflow_failure_excluded_exit_zero" "0" "$(status_code "$out")"
run_contains "reviewer_workflow_failure_excluded" "| pull_request.ci | verified | no checks |" "$(body "$out")"

repo="$(make_repo wrong-head-oid)"
export MOCK_GH_PR_MODE=wrong_head_oid
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE
run_test "wrong_head_oid_exit_one" "1" "$(status_code "$out")"
run_contains "wrong_head_oid_discrepancy" "| repository.head.pr_tip | discrepancy |" "$(body "$out")"

repo="$(make_repo stale-non-clean-summary)"
export MOCK_GH_SUMMARY_MODE=stale_non_clean_summary
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-summary true)"
unset MOCK_GH_SUMMARY_MODE
run_test "stale_non_clean_summary_exit_one" "1" "$(status_code "$out")"
run_contains "stale_non_clean_summary_discrepancy" "| pull_request.review_summary | discrepancy | summary present but not clean/skipped |" "$(body "$out")"

repo="$(make_repo bold-clean-summary)"
export MOCK_GH_SUMMARY_MODE=bold_clean_summary
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-summary true)"
unset MOCK_GH_SUMMARY_MODE
run_test "bold_clean_summary_exit_zero" "0" "$(status_code "$out")"
run_contains "bold_clean_summary_verified" "| pull_request.review_summary | verified | clean_or_skipped |" "$(body "$out")"

repo="$(make_repo optional-summary-fetch-failed)"
export MOCK_GH_SUMMARY_MODE=fetch_failed
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-summary false)"
unset MOCK_GH_SUMMARY_MODE
run_test "optional_summary_fetch_failed_exit_zero" "0" "$(status_code "$out")"
run_contains "optional_summary_fetch_failed_optional" "| pull_request.review_summary | unavailable_optional |" "$(body "$out")"

repo="$(make_repo unconfigured-reviewer-check-failure)"
no_bugbot_config="$TMP_ROOT/no-bugbot-workflow.yaml"
cat > "$no_bugbot_config" <<'YAML'
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github: []
YAML
export MOCK_GH_PR_MODE=reviewer_check_failure
export AI_DEV_WORKFLOW_CONFIG_FILE="$no_bugbot_config"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop)"
unset MOCK_GH_PR_MODE AI_DEV_WORKFLOW_CONFIG_FILE
run_test "unconfigured_reviewer_check_failure_exit_one" "1" "$(status_code "$out")"
run_contains "unconfigured_reviewer_check_failure_blocks_ci" "| pull_request.ci | discrepancy | Cursor Bugbot:FAILURE |" "$(body "$out")"

repo="$(make_repo non-clean-summary)"
export MOCK_GH_PR_MODE=non_clean_summary
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-ci-green false)"
unset MOCK_GH_PR_MODE
run_test "non_clean_summary_optional_exit_zero" "0" "$(status_code "$out")"
run_contains "non_clean_summary_observed" "| pull_request.review_summary | verified | non_clean_summary_observed |" "$(body "$out")"

repo="$(make_repo addressed-thread)"
export MOCK_GH_THREAD_MODE=addressed
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_THREAD_MODE
run_test "addressed_thread_exit_zero" "0" "$(status_code "$out")"
run_contains "addressed_thread_verified" "| pull_request.review_threads | verified | unresolved=0 |" "$(body "$out")"

repo="$(make_repo human-thread)"
export MOCK_GH_THREAD_MODE=human
export BUGBOT_BOT_LOGIN=cursor
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_THREAD_MODE BUGBOT_BOT_LOGIN
run_test "human_thread_exit_zero" "0" "$(status_code "$out")"
run_contains "human_thread_ignored" "| pull_request.review_threads | verified | unresolved=0 |" "$(body "$out")"

repo="$(make_repo non-thread-platform-logins)"
non_thread_platforms_config="$TMP_ROOT/non-thread-platforms-workflow.yaml"
cat > "$non_thread_platforms_config" <<'YAML'
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github:
      - haystack
YAML
export AI_DEV_WORKFLOW_CONFIG_FILE="$non_thread_platforms_config"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset AI_DEV_WORKFLOW_CONFIG_FILE
run_test "non_thread_platform_logins_exit_zero" "0" "$(status_code "$out")"
run_contains "non_thread_platform_logins_verified" "| pull_request.review_threads | verified | unresolved=0 |" "$(body "$out")"

repo="$(make_repo no-thread-bot-logins)"
no_thread_bots_config="$TMP_ROOT/no-thread-bots-workflow.yaml"
cat > "$no_thread_bots_config" <<'YAML'
review:
  on_draft:
    github:
      - custom-reviewer
  on_ready:
    github: []
YAML
export AI_DEV_WORKFLOW_CONFIG_FILE="$no_thread_bots_config"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset AI_DEV_WORKFLOW_CONFIG_FILE
run_test "no_thread_bot_logins_exit_one" "1" "$(status_code "$out")"
run_contains "no_thread_bot_logins_unavailable" "| pull_request.review_threads | unavailable_required | no configured bot logins |" "$(body "$out")"

repo="$(make_repo graphql-thread-fetch-failed)"
export MOCK_GH_THREAD_MODE=fetch_failed
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_THREAD_MODE
run_test "graphql_thread_fetch_failed_exit_one" "1" "$(status_code "$out")"
run_contains "graphql_thread_fetch_failed_unavailable" "| pull_request.review_threads | unavailable_required |" "$(body "$out")"
run_contains "graphql_thread_fetch_failed_overall" "- Result: unavailable_required" "$(body "$out")"

repo="$(make_repo unresolved-thread)"
export MOCK_GH_THREAD_MODE=unresolved
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_THREAD_MODE
run_test "unresolved_thread_exit_one" "1" "$(status_code "$out")"
run_contains "unresolved_thread_discrepancy" "| pull_request.review_threads | discrepancy | unresolved=1 graph=1 rest=0 |" "$(body "$out")"

repo="$(make_repo rest-unreplied-thread)"
export MOCK_GH_REST_THREAD_MODE=unreplied
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_REST_THREAD_MODE
run_test "rest_unreplied_thread_exit_one" "1" "$(status_code "$out")"
run_contains "rest_unreplied_thread_discrepancy" "| pull_request.review_threads | discrepancy | unresolved=1 graph=0 rest=1 |" "$(body "$out")"

repo="$(make_repo graph-rest-same-thread)"
export MOCK_GH_THREAD_MODE=unresolved
export MOCK_GH_REST_THREAD_MODE=unreplied
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_THREAD_MODE MOCK_GH_REST_THREAD_MODE
run_test "graph_rest_same_thread_exit_one" "1" "$(status_code "$out")"
run_contains "graph_rest_same_thread_not_double_counted" "| pull_request.review_threads | discrepancy | unresolved=1 graph=1 rest=0 |" "$(body "$out")"

repo="$(make_repo paginated-thread)"
export MOCK_GH_THREAD_MODE=paginated
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="Development in Review"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --pr 17 \
  --expected-base develop \
  --require-review-threads true)"
unset MOCK_GH_THREAD_MODE
run_test "paginated_thread_exit_one" "1" "$(status_code "$out")"
run_contains "paginated_thread_discrepancy" "| pull_request.review_threads | discrepancy | unresolved=1 graph=1 rest=0 |" "$(body "$out")"

repo="$(make_repo tracker-required)"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="__FAIL__"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --tracker-required true)"
run_test "tracker_required_exit_one" "1" "$(status_code "$out")"
run_contains "tracker_required_unavailable" "| tracker.status | unavailable_required |" "$(body "$out")"
run_contains "tracker_required_overall_unavailable" "- Result: unavailable_required" "$(body "$out")"
unset WORKFLOW_SELF_CHECK_TRACKER_STATUS

repo="$(make_repo tracker-deferred)"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="TRACKER_ACTION_REQUIRED=read_status issue=1202"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --tracker-required true)"
run_test "tracker_deferred_required_exit_one" "1" "$(status_code "$out")"
run_contains "tracker_deferred_required" "| tracker.status | unavailable_required | TRACKER_ACTION_REQUIRED=read_status issue=1202 |" "$(body "$out")"
unset WORKFLOW_SELF_CHECK_TRACKER_STATUS

repo="$(make_repo optional-claim)"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --claim "browser|false|")"
run_test "optional_claim_exit_zero" "0" "$(status_code "$out")"
run_contains "optional_claim_unavailable" "| external.browser | unavailable_optional |" "$(body "$out")"

repo="$(make_repo pipe-claim)"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --claim "runtime|true|observed left | observed right")"
run_test "pipe_claim_exit_zero" "0" "$(status_code "$out")"
run_contains "pipe_claim_preserves_evidence" "| external.runtime | verified | observed left \\| observed right |" "$(body "$out")"

repo="$(make_repo required-claim)"
out="$(self_check_output \
  --repo-root "$repo" \
  --issue 1202 \
  --branch feature/1202-self-check \
  --stage implementation \
  --worktree-path "$repo" \
  --require-ci-green false \
  --claim "runtime|true|")"
run_test "required_claim_exit_one" "1" "$(status_code "$out")"
run_contains "required_claim_unavailable" "| external.runtime | unavailable_required | missing evidence |" "$(body "$out")"

echo ""
echo "=== Results ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
