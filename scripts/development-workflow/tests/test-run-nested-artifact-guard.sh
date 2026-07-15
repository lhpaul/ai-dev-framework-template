#!/usr/bin/env bash
# test-run-nested-artifact-guard.sh - tests for nested artifact guard.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/scripts/development-workflow/run-nested-artifact-guard.sh"
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
case "$*" in
  "pr list --state open --json number,headRefName,baseRefName,title"|"pr list --repo example/repo --state open --json number,headRefName,baseRefName,title")
    case "${MOCK_GH_PR_MODE:-empty}" in
      fail)
        printf 'mock gh failure\n' >&2
        exit 42
        ;;
      wrong_base)
        printf '[{"number":77,"headRefName":"feature/1200-duplicate-path","baseRefName":"main","title":"duplicate"}]\n'
        ;;
      canonical_wrong_base)
        printf '[{"number":77,"headRefName":"feature/1200-canonical-path","baseRefName":"main","title":"canonical wrong base"}]\n'
        ;;
      mixed_scope)
        printf '[{"number":77,"headRefName":"feature/1200-duplicate-path","baseRefName":"develop","title":"in scope"},{"number":78,"headRefName":"feature/999-other","baseRefName":"main","title":"out of scope"}]\n'
        ;;
      invalid_json)
        printf '{not-json]\n'
        ;;
      *)
        printf '[]\n'
        ;;
    esac
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

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

run_not_contains() {
  local name="$1" unexpected="$2" actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - output unexpectedly contained '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

guard_output() {
  local status output
  set +e
  output="$("$GUARD" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

body() {
  tail -n +2 <<< "$1"
}

status_code() {
  head -n 1 <<< "$1"
}

make_repo() {
  local name="$1"
  local repo="$TMP_ROOT/$name/repo"
  local origin="$TMP_ROOT/$name/origin.git"
  mkdir -p "$TMP_ROOT/$name"
  git init -q --bare "$origin"
  git init -q -b develop "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'base\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" push -q -u origin develop
  git -C "$repo" switch -q -c feature/1200-canonical-path
  printf '%s\n' "$repo"
}

echo ""
echo "=== nested artifact guard ==="

repo="$(make_repo clean)"
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path)"
run_test "missing_base_exit" "1" "$(status_code "$out")"
run_contains "missing_base_result" "RESULT=missing_base" "$(body "$out")"

repo="$(make_repo audit-missing-base)"
out="$(guard_output --repo-root "$repo" --mode audit --issue 1200 --expected-branch feature/1200-canonical-path)"
run_test "audit_missing_base_exit" "1" "$(status_code "$out")"
run_contains "audit_missing_base_result" "RESULT=missing_base" "$(body "$out")"

repo="$(make_repo canonical)"
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "canonical_exit_zero" "0" "$(status_code "$out")"
run_contains "canonical_clean" "RESULT=clean" "$(body "$out")"
run_contains "canonical_artifact_reported" "CANONICAL_ARTIFACT" "$(body "$out")"

repo="$(make_repo duplicate-local)"
git -C "$repo" branch feature/1200-duplicate-path
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "duplicate_local_exit_one" "1" "$(status_code "$out")"
run_contains "duplicate_local_result" "RESULT=blocked_duplicate" "$(body "$out")"
run_contains "duplicate_local_branch" "feature/1200-duplicate-path" "$(body "$out")"

repo="$(make_repo prior-stage)"
git -C "$repo" branch spec/1200-approved-spec
git -C "$repo" branch implementation-plan/1200-approved-plan
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "prior_stage_exit_zero" "0" "$(status_code "$out")"
run_contains "prior_stage_clean" "RESULT=clean" "$(body "$out")"
run_not_contains "prior_stage_ignores_spec" "spec/1200-approved-spec" "$(body "$out")"
run_not_contains "prior_stage_ignores_plan" "implementation-plan/1200-approved-plan" "$(body "$out")"

repo="$(make_repo boundary)"
git -C "$repo" branch feature/12000-unrelated-path
git -C "$repo" branch feature/foo-1200
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "lookalikes_exit_zero" "0" "$(status_code "$out")"
run_contains "lookalikes_clean" "RESULT=clean" "$(body "$out")"
run_not_contains "ignores_12000" "12000-unrelated" "$(body "$out")"
run_not_contains "ignores_foo_1200" "foo-1200" "$(body "$out")"

repo="$(make_repo team-prefix)"
git -C "$repo" branch feature/ENG-1200-prefixed
git -C "$repo" branch feature/AB12-1200-prefixed
git -C "$repo" branch feature/lh-1200-prefixed
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "team_prefix_exit_one" "1" "$(status_code "$out")"
run_contains "team_prefix_matches" "feature/ENG-1200-prefixed" "$(body "$out")"
run_contains "team_prefix_digits_match" "feature/AB12-1200-prefixed" "$(body "$out")"
run_contains "lowercase_team_prefix_match" "feature/lh-1200-prefixed" "$(body "$out")"

repo="$(make_repo remote)"
git -C "$repo" branch feature/1200-remote-only
git -C "$repo" push -q origin feature/1200-remote-only
git -C "$repo" branch -D feature/1200-remote-only >/dev/null
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "remote_duplicate_exit_one" "1" "$(status_code "$out")"
run_contains "remote_duplicate_reported" "kind=remote_branch branch=feature/1200-remote-only" "$(body "$out")"

repo="$(make_repo backport)"
git -C "$repo" branch backport/hotfix/1200-backport-path
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "backport_prefix_non_stage_exit_zero" "0" "$(status_code "$out")"
run_contains "backport_prefix_non_stage_clean" "RESULT=clean" "$(body "$out")"

repo="$(make_repo backport-duplicate)"
git -C "$repo" branch backport/hotfix/1200-other-backport
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch backport/hotfix/1200-backport-path --approved-base develop)"
run_test "backport_prefix_exit_one" "1" "$(status_code "$out")"
run_contains "backport_prefix_reported" "backport/hotfix/1200-other-backport" "$(body "$out")"

repo="$(make_repo worktree)"
git -C "$repo" worktree add -q -b feature/1200-duplicate-worktree "$TMP_ROOT/worktree-dup"
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "worktree_duplicate_exit_one" "1" "$(status_code "$out")"
run_contains "worktree_duplicate_path" "$TMP_ROOT/worktree-dup" "$(body "$out")"

repo="$(make_repo expected-path-wrong-branch)"
expected_wrong_path="$TMP_ROOT/worktree-expected-path-wrong-branch"
git -C "$repo" worktree add -q -b feature/1200-wrong-worktree-branch "$expected_wrong_path"
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --expected-worktree "$expected_wrong_path" --approved-base develop)"
run_test "expected_path_wrong_branch_exit_one" "1" "$(status_code "$out")"
run_contains "expected_path_wrong_branch_result" "RESULT=blocked_duplicate" "$(body "$out")"
run_contains "expected_path_wrong_branch_reported" "feature/1200-wrong-worktree-branch" "$(body "$out")"

repo="$(make_repo wrong-pr-base)"
export MOCK_GH_PR_MODE=wrong_base
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "wrong_base_exit_one" "1" "$(status_code "$out")"
run_contains "wrong_base_result" "RESULT=wrong_base" "$(body "$out")"
run_contains "wrong_base_pr" "base=main" "$(body "$out")"

repo="$(make_repo canonical-wrong-pr-base)"
export MOCK_GH_PR_MODE=canonical_wrong_base
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "canonical_wrong_base_exit_one" "1" "$(status_code "$out")"
run_contains "canonical_wrong_base_result" "RESULT=wrong_base" "$(body "$out")"

repo="$(make_repo split-wrong-pr-base)"
export MOCK_GH_PR_MODE=wrong_base
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop --allow-split true)"
unset MOCK_GH_PR_MODE
run_test "split_wrong_base_exit_one" "1" "$(status_code "$out")"
run_contains "split_wrong_base_still_blocks" "RESULT=wrong_base" "$(body "$out")"

repo="$(make_repo audit)"
git -C "$repo" branch feature/1200-audit-fork
out="$(guard_output --repo-root "$repo" --mode audit --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
run_test "audit_unexpected_exit_one" "1" "$(status_code "$out")"
run_contains "audit_unexpected_result" "RESULT=unexpected_fork" "$(body "$out")"

repo="$(make_repo audit-split)"
git -C "$repo" branch feature/1200-audit-split-fork
out="$(guard_output --repo-root "$repo" --mode audit --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop --allow-split true)"
run_test "audit_split_exit_one" "1" "$(status_code "$out")"
run_contains "audit_split_still_reports_fork" "RESULT=unexpected_fork" "$(body "$out")"

repo="$(make_repo backport-prior-stage)"
git -C "$repo" branch hotfix/1200-released-hotfix
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch backport/hotfix/1200-backport-path --approved-base develop)"
run_test "backport_prior_hotfix_exit_zero" "0" "$(status_code "$out")"
run_contains "backport_prior_hotfix_clean" "RESULT=clean" "$(body "$out")"

repo="$(make_repo audit-wrong-pr-base)"
export MOCK_GH_PR_MODE=canonical_wrong_base
out="$(guard_output --repo-root "$repo" --mode audit --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "audit_wrong_base_exit_one" "1" "$(status_code "$out")"
run_contains "audit_wrong_base_result" "RESULT=wrong_base" "$(body "$out")"

repo="$(make_repo github-origin)"
origin_url="$(git -C "$repo" config --get remote.origin.url)"
git -C "$repo" remote set-url origin https://github.com/example/repo.git
git -C "$repo" config "url.${origin_url}.insteadOf" https://github.com/example/repo.git
export MOCK_GH_PR_MODE=wrong_base
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "github_origin_exit_one" "1" "$(status_code "$out")"
run_contains "github_origin_repo_scan" "RESULT=wrong_base" "$(body "$out")"

repo="$(make_repo split)"
git -C "$repo" branch feature/1200-split-path
out="$(guard_output --repo-root "$repo" --mode pre-create --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop --allow-split true)"
run_test "split_exit_zero" "0" "$(status_code "$out")"
run_contains "split_clean" "RESULT=clean" "$(body "$out")"
run_contains "split_required_action" "explicit split approval" "$(body "$out")"

repo="$(make_repo gh-fail)"
export MOCK_GH_PR_MODE=fail
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "gh_failure_exit_one" "1" "$(status_code "$out")"
run_contains "gh_failure_scan_failed" "RESULT=scan_failed" "$(body "$out")"
run_contains "gh_failure_action" "Retry gh PR scan" "$(body "$out")"

repo="$(make_repo gh-invalid-json)"
export MOCK_GH_PR_MODE=invalid_json
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "gh_invalid_json_exit_one" "1" "$(status_code "$out")"
run_contains "gh_invalid_json_scan_failed" "SCAN=open_prs_json" "$(body "$out")"

repo="$(make_repo missing-gh)"
git_bin_dir="$(dirname "$(command -v git)")"
set +e
out="$(PATH="$git_bin_dir:/usr/bin:/bin" "$GUARD" --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop 2>&1)"
status=$?
set -e
run_test "missing_gh_exit_one" "1" "$status"
run_contains "missing_gh_scan_failed" "SCAN=open_prs_missing_gh" "$out"

repo="$(make_repo mixed-scope)"
export MOCK_GH_PR_MODE=mixed_scope
out="$(guard_output --repo-root "$repo" --mode pre-pr --issue 1200 --expected-branch feature/1200-canonical-path --approved-base develop)"
unset MOCK_GH_PR_MODE
run_test "mixed_scope_exit_one" "1" "$(status_code "$out")"
run_contains "mixed_scope_in_scope" "feature/1200-duplicate-path" "$(body "$out")"
run_not_contains "mixed_scope_out_of_scope" "feature/999-other" "$(body "$out")"

echo ""
echo "Nested artifact guard tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
