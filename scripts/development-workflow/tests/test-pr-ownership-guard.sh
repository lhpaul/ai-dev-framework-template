#!/usr/bin/env bash
# test-pr-ownership-guard.sh - PR ownership guard coverage (issue #1444).
#
# Plants a mismatched PR number and proves the mutation behind the guard never
# runs; proves the matching number proceeds with no side effects; proves a fork
# PR with the same branch name is refused; proves an unresolvable PR and a
# detached HEAD both fail closed.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/scripts/development-workflow/pr-ownership-guard.sh"
TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
EMPTY_BIN="$TMP_ROOT/empty-bin"
GH_LOG="$TMP_ROOT/gh-calls.log"
FIXTURE_REPO="$TMP_ROOT/fixture-repo"
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

NON_GIT_DIR="$TMP_ROOT/not-a-checkout"
mkdir -p "$MOCK_BIN" "$EMPTY_BIN" "$NON_GIT_DIR"
: > "$GH_LOG"

# Mock gh: records every invocation, answers `pr view` from MOCK_GH_MODE and
# MOCK_GH_HEADS ("<pr>=<branch>[@<fork-owner>/<fork-repo>] ..."; no fork means a
# same-repository PR in example/repo), and records mutations so a test can
# prove a guarded mutation never ran.
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_LOG"
if [ "${1:-}" != "pr" ] || [ "${2:-}" != "view" ]; then
  exit 0
fi
case "${MOCK_GH_MODE:-ok}" in
  fail)
    printf 'GraphQL: Could not resolve to a PullRequest with the number of %s.\n' "$3" >&2
    exit 1
    ;;
  empty) exit 0 ;;
  null) printf 'null\n'; exit 0 ;;
  garbage) printf 'not json\n'; exit 0 ;;
  no_cross_flag) printf '{"headRefName":"spec/13-own-item"}\n'; exit 0 ;;
  null_owner)
    printf '{"headRefName":"spec/13-own-item","headRepositoryOwner":null,"headRepository":{"name":"repo"},"isCrossRepository":false}\n'
    exit 0
    ;;
  missing_head_repo)
    printf '{"headRefName":"spec/13-own-item","headRepositoryOwner":{"login":"example"},"isCrossRepository":false}\n'
    exit 0
    ;;
  malformed_owner)
    printf '{"headRefName":"spec/13-own-item","headRepositoryOwner":{"login":"bad owner!"},"headRepository":{"name":"repo"},"isCrossRepository":false}\n'
    exit 0
    ;;
  deleted_fork)
    printf '{"headRefName":"spec/13-own-item","headRepositoryOwner":null,"headRepository":null,"isCrossRepository":true}\n'
    exit 0
    ;;
  slow) sleep 5; exit 0 ;;
esac
for pair in ${MOCK_GH_HEADS:-}; do
  if [ "${pair%%=*}" = "$3" ]; then
    spec="${pair#*=}"
    branch="${spec%%@*}"
    owner="example"; name="repo"; cross=false
    if [ "$spec" != "$branch" ]; then
      fork="${spec#*@}"; owner="${fork%%/*}"; name="${fork#*/}"; cross=true
    fi
    printf '{"headRefName":"%s","headRepositoryOwner":{"login":"%s"},"headRepository":{"name":"%s"},"isCrossRepository":%s}\n' \
      "$branch" "$owner" "$name" "$cross"
    exit 0
  fi
done
printf 'no pull requests found for number %s\n' "$3" >&2
exit 1
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_LOG="$GH_LOG"
# The target repository the guard compares a same-repository PR's head with
# (--repo, else GH_REPO, else the checkout origin). Cases below override it.
export GH_REPO="example/repo"

# Two sibling PRs from one parallel wave: #52 is item 10's, #53 is item 13's.
# #54 is a fork PR that happens to use item 13's branch name.
export MOCK_GH_HEADS="52=spec/10-sibling-item 53=spec/13-own-item 54=spec/13-own-item@forker/repo-fork"

git -c init.defaultBranch=main init -q "$FIXTURE_REPO"
git -C "$FIXTURE_REPO" -c user.name=test -c user.email=test@example.com \
  commit -q --allow-empty -m init
git -C "$FIXTURE_REPO" checkout -q -b spec/13-own-item

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected '%s', got '%s'\n" "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1" expected="$2" actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected output to contain '%s'\n" "$name" "$expected"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_not_contains() {
  local name="$1" unexpected="$2" actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    printf "FAIL: %s - output unexpectedly contained '%s'\n" "$name" "$unexpected"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

# guard_output <args...> -> first line: exit status; rest: stdout+stderr.
guard_output() {
  local status output
  set +e
  output="$("$GUARD" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

status_code() { head -n 1 <<< "$1"; }
body() { tail -n +2 <<< "$1"; }

# guarded_edit <pr> <expected-branch>: the protocol pattern — the mutation runs
# only when the guard exits 0.
guarded_edit() {
  local pr="$1" expected="$2"
  if "$GUARD" --pr "$pr" --expected-branch "$expected" >/dev/null 2>&1; then
    gh pr edit "$pr" --body-file "$TMP_ROOT/pr-body-13-$$.md"
    return 0
  fi
  return 1
}

# --- Planted mismatch: item 13's agent holds sibling #52's number. ---
: > "$GH_LOG"
out="$(guard_output --pr 52 --expected-branch spec/13-own-item)"
run_test "mismatch_refused_exit_1" "1" "$(status_code "$out")"
run_contains "mismatch_reports_not_owned" "RESULT=not_owned" "$(body "$out")"
run_contains "mismatch_names_actual_head" "PR_HEAD_BRANCH=spec/10-sibling-item" "$(body "$out")"
run_contains "mismatch_prints_refusal" "REFUSED: PR #52 mutation blocked" "$(body "$out")"
run_contains "mismatch_required_action" "never mutate a sibling PR" "$(body "$out")"
run_contains "mismatch_kind_branch" "MISMATCH=branch" "$(body "$out")"

: > "$GH_LOG"
set +e
guarded_edit 52 spec/13-own-item
edit_status=$?
set -e
run_test "mismatch_guarded_edit_blocked" "1" "$edit_status"
run_not_contains "mismatch_sibling_pr_never_edited" "pr edit 52" "$(cat "$GH_LOG")"

# --- Matching number proceeds with no side effects. ---
: > "$GH_LOG"
status_before="$(git -C "$FIXTURE_REPO" status --porcelain)"
head_before="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --repo-root "$FIXTURE_REPO")"
run_test "match_proceeds_exit_0" "0" "$(status_code "$out")"
run_contains "match_reports_owned" "RESULT=owned" "$(body "$out")"
run_not_contains "match_prints_no_refusal" "REFUSED" "$(body "$out")"
run_test "match_guard_only_reads" "pr view 53 --json headRefName,headRepositoryOwner,headRepository,isCrossRepository" "$(cat "$GH_LOG")"
run_test "match_checkout_unchanged" "$status_before" "$(git -C "$FIXTURE_REPO" status --porcelain)"
run_test "match_head_unchanged" "$head_before" "$(git -C "$FIXTURE_REPO" rev-parse HEAD)"

: > "$GH_LOG"
set +e
guarded_edit 53 spec/13-own-item
edit_status=$?
set -e
run_test "match_guarded_edit_runs" "0" "$edit_status"
run_contains "match_own_pr_edited" "pr edit 53" "$(cat "$GH_LOG")"

# --- Fork PR with the same branch name: head repository is part of identity. ---
: > "$GH_LOG"
out="$(guard_output --pr 54 --expected-branch spec/13-own-item)"
run_test "fork_same_branch_refused_exit_1" "1" "$(status_code "$out")"
run_contains "fork_same_branch_not_owned" "RESULT=not_owned" "$(body "$out")"
run_contains "fork_same_branch_kind" "MISMATCH=head_repository" "$(body "$out")"
run_contains "fork_same_branch_names_fork" "PR_HEAD_REPO=forker/repo-fork" "$(body "$out")"
set +e
guarded_edit 54 spec/13-own-item
edit_status=$?
set -e
run_test "fork_guarded_edit_blocked" "1" "$edit_status"
run_not_contains "fork_pr_never_edited" "pr edit 54" "$(cat "$GH_LOG")"

out="$(guard_output --pr 54 --expected-branch spec/13-own-item --expected-head-repo Forker/Repo-Fork)"
run_test "fork_named_head_repo_proceeds_exit_0" "0" "$(status_code "$out")"
run_contains "fork_named_head_repo_owned" "RESULT=owned" "$(body "$out")"
out="$(guard_output --pr 54 --expected-branch spec/13-own-item --expected-head-repo other/fork)"
run_test "fork_wrong_head_repo_refused_exit_1" "1" "$(status_code "$out")"
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --expected-head-repo forker/repo-fork)"
run_test "same_repo_pr_wrong_expected_head_repo_exit_1" "1" "$(status_code "$out")"
run_contains "same_repo_pr_wrong_expected_head_repo_kind" "MISMATCH=head_repository" "$(body "$out")"
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --expected-head-repo example/repo)"
run_test "same_repo_pr_matching_expected_head_repo_exit_0" "0" "$(status_code "$out")"
out="$(MOCK_GH_MODE=deleted_fork guard_output --pr 54 --expected-branch spec/13-own-item)"
run_test "deleted_fork_fails_closed_exit_3" "3" "$(status_code "$out")"
run_contains "deleted_fork_reports_unresolved" "RESULT=pr_unresolved" "$(body "$out")"
run_contains "deleted_fork_cross_flag_parsed" "PR_IS_CROSS_REPOSITORY=true" "$(body "$out")"

# --- Head repository is part of identity: absent or malformed fails closed. ---
for mode in null_owner missing_head_repo malformed_owner; do
  : > "$GH_LOG"
  out="$(MOCK_GH_MODE="$mode" guard_output --pr 53 --expected-branch spec/13-own-item)"
  run_test "head_repo_${mode}_fails_closed_exit_3" "3" "$(status_code "$out")"
  run_contains "head_repo_${mode}_reports_unresolved" "RESULT=pr_unresolved" "$(body "$out")"
  run_contains "head_repo_${mode}_names_cause" "no valid head repository" "$(body "$out")"
done

# --- A same-repository PR's head must be the target repository. ---
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --repo acme/other)"
run_test "target_repo_flag_mismatch_exit_1" "1" "$(status_code "$out")"
run_contains "target_repo_flag_mismatch_kind" "MISMATCH=head_repository" "$(body "$out")"
out="$(GH_REPO=acme/other guard_output --pr 53 --expected-branch spec/13-own-item)"
run_test "target_repo_env_mismatch_exit_1" "1" "$(status_code "$out")"
run_contains "target_repo_env_mismatch_names_source" "GH_REPO" "$(body "$out")"
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --repo EXAMPLE/Repo)"
run_test "target_repo_case_insensitive_exit_0" "0" "$(status_code "$out")"
ORIGIN_FIXTURE="$TMP_ROOT/origin-fixture"
git -c init.defaultBranch=main init -q "$ORIGIN_FIXTURE"
git -C "$ORIGIN_FIXTURE" remote add origin git@github.com:acme/originrepo.git
out="$(GH_REPO= guard_output --pr 53 --expected-branch spec/13-own-item --repo-root "$ORIGIN_FIXTURE")"
run_test "target_repo_origin_mismatch_exit_1" "1" "$(status_code "$out")"
run_contains "target_repo_origin_mismatch_names_origin" "acme/originrepo" "$(body "$out")"
git -C "$ORIGIN_FIXTURE" remote set-url origin https://github.com/example/repo.git
out="$(GH_REPO= guard_output --pr 53 --expected-branch spec/13-own-item --repo-root "$ORIGIN_FIXTURE")"
run_test "target_repo_origin_match_exit_0" "0" "$(status_code "$out")"
out="$(GH_REPO= guard_output --pr 53 --expected-branch spec/13-own-item --repo-root "$NON_GIT_DIR")"
run_test "target_repo_unknown_still_owned_exit_0" "0" "$(status_code "$out")"
# With no known target, the cross-repository flag alone must still refuse a
# fork PR that reuses the branch name.
out="$(GH_REPO= guard_output --pr 54 --expected-branch spec/13-own-item --repo-root "$NON_GIT_DIR")"
run_test "fork_refused_without_known_target_exit_1" "1" "$(status_code "$out")"
run_contains "fork_refused_without_known_target_kind" "cross-repository PR" "$(body "$out")"

# --- Default expectation: the checkout's current branch. ---
out="$(guard_output --pr 53 --repo-root "$FIXTURE_REPO")"
run_test "current_branch_match_exit_0" "0" "$(status_code "$out")"
run_contains "current_branch_source_reported" "EXPECTED_BRANCH_SOURCE=current_branch" "$(body "$out")"
out="$(guard_output --pr 52 --repo-root "$FIXTURE_REPO")"
run_test "current_branch_mismatch_exit_1" "1" "$(status_code "$out")"

# --- --repo passthrough. ---
: > "$GH_LOG"
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --repo example/repo)"
run_test "repo_passthrough_exit_0" "0" "$(status_code "$out")"
run_test "repo_passthrough_args" "pr view 53 --repo example/repo --json headRefName,headRepositoryOwner,headRepository,isCrossRepository" "$(cat "$GH_LOG")"

# --- Unresolvable PR fails closed. ---
out="$(guard_output --pr 999 --expected-branch spec/13-own-item)"
run_test "unknown_pr_fails_closed_exit_3" "3" "$(status_code "$out")"
run_contains "unknown_pr_reports_unresolved" "RESULT=pr_unresolved" "$(body "$out")"

for mode in fail empty null garbage no_cross_flag; do
  out="$(MOCK_GH_MODE="$mode" guard_output --pr 53 --expected-branch spec/13-own-item)"
  run_test "gh_${mode}_fails_closed_exit_3" "3" "$(status_code "$out")"
  run_contains "gh_${mode}_reports_unresolved" "RESULT=pr_unresolved" "$(body "$out")"
done

out="$(MOCK_GH_MODE=slow PR_OWNERSHIP_GUARD_TIMEOUT_SECONDS=1 guard_output --pr 53 --expected-branch spec/13-own-item)"
run_test "gh_timeout_fails_closed_exit_3" "3" "$(status_code "$out")"
run_contains "gh_timeout_reported" "timed out" "$(body "$out")"

set +e
out="$(PATH="$EMPTY_BIN" /bin/bash "$GUARD" --pr 53 --expected-branch spec/13-own-item 2>&1)"
status=$?
set -e
run_test "gh_missing_fails_closed_exit_3" "3" "$status"
run_contains "gh_missing_reported" "gh CLI is not available" "$out"

# --- Detached HEAD fails closed before any gh call. ---
git -C "$FIXTURE_REPO" checkout -q --detach
: > "$GH_LOG"
out="$(guard_output --pr 53 --repo-root "$FIXTURE_REPO")"
run_test "detached_head_fails_closed_exit_4" "4" "$(status_code "$out")"
run_contains "detached_head_reports_branch_unknown" "RESULT=branch_unknown" "$(body "$out")"
run_test "detached_head_no_gh_call" "" "$(cat "$GH_LOG")"

out="$(guard_output --pr 53 --repo-root "$NON_GIT_DIR")"
run_test "non_git_root_fails_closed_exit_4" "4" "$(status_code "$out")"

# An explicit expected branch still works from a detached checkout.
out="$(guard_output --pr 53 --expected-branch spec/13-own-item --repo-root "$FIXTURE_REPO")"
run_test "detached_with_explicit_branch_exit_0" "0" "$(status_code "$out")"

# --- Usage errors. ---
out="$(guard_output)"
run_test "missing_pr_usage_exit_2" "2" "$(status_code "$out")"
for bad_pr in abc 0 07 -5; do
  out="$(guard_output --pr "$bad_pr" --expected-branch spec/13-own-item)"
  run_test "bad_pr_${bad_pr}_usage_exit_2" "2" "$(status_code "$out")"
done
out="$(guard_output --pr 53 --repo not-a-slug)"
run_test "bad_repo_usage_exit_2" "2" "$(status_code "$out")"
for bad_repo in solo a/b/c /repo owner/; do
  out="$(guard_output --pr 53 --expected-branch spec/13-own-item --expected-head-repo "$bad_repo")"
  run_test "bad_expected_head_repo_usage_exit_2" "2" "$(status_code "$out")"
done
out="$(guard_output --pr 53 --expected-branch 'spec/13 own')"
run_test "whitespace_branch_usage_exit_2" "2" "$(status_code "$out")"
out="$(guard_output --pr 53 --bogus)"
run_test "unknown_argument_usage_exit_2" "2" "$(status_code "$out")"
out="$(guard_output --help)"
run_test "help_exit_0" "0" "$(status_code "$out")"

printf '\nResults: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
