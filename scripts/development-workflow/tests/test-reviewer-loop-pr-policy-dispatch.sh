#!/usr/bin/env bash
# Best-effort pr-policy.yml workflow_dispatch after summary post (#1998).
# covers: scripts/development-workflow/pr-review-loop.sh
#
# Usage: bash scripts/development-workflow/tests/test-reviewer-loop-pr-policy-dispatch.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

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

# shellcheck source=scripts/development-workflow/pr-review-loop.sh
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"

repo_slug() { printf 'owner/repo\n'; }

_make_gh_mock() {
  local mode="$1"
  local mock_dir
  mock_dir="$(mktemp -d)"
  cat > "$mock_dir/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$*" in
  *"repos/owner/repo"*"--jq"*".default_branch"*|*"repos/owner/repo --jq .default_branch"*)
    printf 'main\n'
    exit 0
    ;;
  *"contents/.github/workflows/pr-policy.yml"*)
    if [ "$mode" = "absent" ]; then
      echo "Not Found" >&2
      exit 1
    fi
    if [[ "\$*" == *"--jq"*".path"* ]] || [[ "\$*" == *"--jq .path"* ]]; then
      printf '%s\n' '.github/workflows/pr-policy.yml'
    else
      printf '{"path":".github/workflows/pr-policy.yml","type":"file"}\n'
    fi
    exit 0
    ;;
  *"workflow run"*pr-policy.yml*)
    if [ "$mode" = "dispatch_fail" ]; then
      echo "HTTP 422: workflow does not have workflow_dispatch trigger" >&2
      exit 1
    fi
    printf 'Created workflow_dispatch for pr-policy.yml\n'
    exit 0
    ;;
  *)
    echo "unexpected gh invocation: \$*" >&2
    exit 64
    ;;
esac
EOF
  chmod +x "$mock_dir/gh"
  printf '%s\n' "$mock_dir"
}

echo "=== reviewer_loop_dispatch_pr_policy (#1998) ==="

_mock_ok="$(_make_gh_mock ok)"
_out="$(PATH="${_mock_ok}:$PATH" reviewer_loop_dispatch_pr_policy 42 owner/repo)"
_rc=0
PATH="${_mock_ok}:$PATH" reviewer_loop_dispatch_pr_policy 42 owner/repo >/dev/null || _rc=$?
run_test "dispatch_requested_after_summary_helper" "PR_POLICY_DISPATCH=requested" "$(printf '%s\n' "$_out" | grep -E '^PR_POLICY_DISPATCH=' | tail -1)"
run_test "dispatch_requested_exit_zero" "0" "$_rc"
rm -rf "$_mock_ok"

_mock_absent="$(_make_gh_mock absent)"
_out="$(PATH="${_mock_absent}:$PATH" reviewer_loop_dispatch_pr_policy 42 owner/repo)"
run_test "dispatch_skipped_when_workflow_absent" "PR_POLICY_DISPATCH=skipped reason=pr_policy_workflow_absent" \
  "$(printf '%s\n' "$_out" | grep -E '^PR_POLICY_DISPATCH=' | tail -1)"
rm -rf "$_mock_absent"

_out="$(PR_REVIEW_LOOP_POLICY_DISPATCH=0 reviewer_loop_dispatch_pr_policy 42 owner/repo)"
run_test "dispatch_skipped_on_opt_out" "PR_POLICY_DISPATCH=skipped reason=opt_out" \
  "$(printf '%s\n' "$_out" | grep -E '^PR_POLICY_DISPATCH=' | tail -1)"

_mock_fail="$(_make_gh_mock dispatch_fail)"
_out="$(PATH="${_mock_fail}:$PATH" reviewer_loop_dispatch_pr_policy 42 owner/repo)"
_rc=0
PATH="${_mock_fail}:$PATH" reviewer_loop_dispatch_pr_policy 42 owner/repo >/dev/null || _rc=$?
if grep -Eq '^PR_POLICY_DISPATCH=failed reason=' <<<"$_out"; then
  _failed_line=yes
else
  _failed_line=no
fi
run_test "dispatch_failed_prints_failed" "yes" "$_failed_line"
unset _failed_line
run_test "dispatch_failed_exit_zero" "0" "$_rc"
rm -rf "$_mock_fail"

# Prove a failing dispatch cannot change a surrounding RESULT/exit contract.
_mock_fail="$(_make_gh_mock dispatch_fail)"
_out="$(
  PATH="${_mock_fail}:$PATH"
  aggregate_result=clean
  aggregate_reason=none
  reviewer_loop_dispatch_pr_policy 99 owner/repo
  printf 'RESULT=%s\n' "$aggregate_result"
  printf 'REASON=%s\n' "$aggregate_reason"
  exit 0
)"
_rc=$?
run_test "failing_dispatch_preserves_result" "RESULT=clean" \
  "$(printf '%s\n' "$_out" | grep -E '^RESULT=' | tail -1)"
run_test "failing_dispatch_preserves_reason" "REASON=none" \
  "$(printf '%s\n' "$_out" | grep -E '^REASON=' | tail -1)"
run_test "failing_dispatch_preserves_exit" "0" "$_rc"
rm -rf "$_mock_fail"

# Static: _post_review_summary and post_release_guard_summary call the helper.
run_test "post_review_summary_calls_dispatch" "yes" \
  "$(grep -Fq 'reviewer_loop_dispatch_pr_policy "$pr_number"' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" && echo yes || echo no)"
run_test "release_guard_summary_calls_dispatch" "yes" \
  "$(grep -Fq 'reviewer_loop_dispatch_pr_policy "$_pr_number"' \
    "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" && echo yes || echo no)"

echo ""
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
