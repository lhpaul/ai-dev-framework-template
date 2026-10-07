#!/usr/bin/env bash
# test-pr-review-loop-release-bugbot.sh — pr-review-loop.sh harness: release-
# PR guard and the Bugbot platform.
# duration: 30
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
#
# The pr-review-loop.sh harness is split across these suites (#1876), which
# share their preamble — snapshot re-exec, --area filter, gh/git mocks, the
# HARNESS_MODE source of pr-review-loop.sh, and the run_test helpers — through
# tests/lib/pr-review-loop-harness.sh:
#
#   test-pr-review-loop.sh
#   test-pr-review-loop-cycles-labels.sh
#   test-pr-review-loop-failure-paths-1.sh
#   test-pr-review-loop-failure-paths-2.sh
#   test-pr-review-loop-failure-paths-3.sh
#   test-pr-review-loop-failure-paths-4.sh
#   test-pr-review-loop-release-bugbot.sh
#   test-pr-review-loop-pr-agent-coderabbit.sh
#   test-pr-review-loop-staged-gates.sh
#   test-pr-review-loop-no-verdict-yet.sh
#
# Areas in this suite:
#   Area 14: _check_release_pr_guard
#   Area 15: main-loop integration — release guard
#   Area 16: run_bugbot_review — clean / needs_fixes / escalate
#
# Usage: bash scripts/development-workflow/tests/test-pr-review-loop-release-bugbot.sh [--area <name>]... [--list-areas]
# No external tooling required beyond bash, git, and jq (git only locates the
# repository root at startup; mock gh commands replace all network calls).
#
# Exit code: 0 if all tests pass, 1 if any test fails, 2 on a usage error.
#
# Many assignments here set pr-review-loop.sh globals that the functions under
# test read. ShellCheck does not follow that source, so each such assignment
# carries its own `# shellcheck disable=SC2034` with the reason inline.

set -euo pipefail

# Resolve the shared harness from the checked-in suite path. Inside a snapshot
# run $0 is a temp copy, so TEST_PR_REVIEW_LOOP_ORIGIN (set by the harness on
# re-exec, or by hand for an out-of-tree copy) takes precedence.
_prl_harness="$(dirname -- "${TEST_PR_REVIEW_LOOP_ORIGIN:-$0}")/lib/pr-review-loop-harness.sh"
if [ ! -f "$_prl_harness" ]; then
  echo "ERROR: shared harness not found: $_prl_harness" >&2
  echo "  Run the checked-in suite, or set TEST_PR_REVIEW_LOOP_ORIGIN to its path." >&2
  exit 2
fi
# shellcheck source=scripts/development-workflow/tests/lib/pr-review-loop-harness.sh
source "$_prl_harness" "$@"
unset _prl_harness

# Carried state. In the single-file harness, Area 13 exported this for every
# later area; keep the suites that held those areas running under the same
# environment so the split changes where tests live, not what they exercise.
export CODEX_GITHUB_PRE_TRIGGER_WAIT=0

# ---------------------------------------------------------------------------
# Area 14: _check_release_pr_guard — release PR early-exit guard (#960)
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 14: _check_release_pr_guard ==="

# Helper: set MOCK_GH_OUTPUT to simulate a gh pr view JSON response.
# MOCK_GH_OUTPUT is the default gh mock output used when no specific case
# applies (the default case in the mock gh script).
# For tests that pass --branch, the head is known; only the base is fetched.

# Test 14.1: release/* head branch detected as release PR (branch provided)
# When branch is provided, no gh call is made; mock output is irrelevant.
export MOCK_GH_OUTPUT='[]'
_guard_out=""
_guard_exit=0
_guard_out="$(_check_release_pr_guard "100" "release/v1.0.0")" || _guard_exit=$?
run_test "release_guard_release_head_fires" "RELEASE_GUARD_FIRED=1" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_release_head_exit0" "0" "$_guard_exit"

# Test 14.2: hotfix/* head branch detected as release PR (branch provided)
_guard_out=""
_guard_exit=0
_guard_out="$(_check_release_pr_guard "101" "hotfix/v1.0.1")" || _guard_exit=$?
run_test "release_guard_hotfix_head_fires" "RELEASE_GUARD_FIRED=1" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_hotfix_head_exit0" "0" "$_guard_exit"

# Test 14.3: develop-targeting feature branch — guard does NOT fire
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "103" "feature/some-feature")" || _guard_exit=$?
run_test "release_guard_feature_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_feature_exit1" "1" "$_guard_exit"

# Test 14.4: fix/* branch — guard does NOT fire
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "104" "fix/some-fix")" || _guard_exit=$?
run_test "release_guard_fix_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"

# Test 14.5: no --branch provided; head branch fetched from PR, parsed via jq.
# The mock returns MOCK_GH_OUTPUT for the default gh pr view call. The function
# now calls gh pr view WITHOUT --jq and then pipes to jq itself, so the mock
# must return valid JSON rather than a pre-filtered plain branch name.
export MOCK_GH_OUTPUT='{"headRefName":"release/v2.0.0"}'
_guard_out=""
_guard_exit=0
_guard_out="$(_check_release_pr_guard "105")" || _guard_exit=$?
run_test "release_guard_fetched_head_fires" "RELEASE_GUARD_FIRED=1" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_fetched_head_value" "RELEASE_GUARD_HEAD=release/v2.0.0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_HEAD=")"
export MOCK_GH_OUTPUT='[]'

# Test 14.6: no --branch provided; gh pr view failure — guard does not fire.
# Fail-safe design: a SKIP guard that can't determine the branch defaults to
# NOT firing, so the reviewer loop runs normally (fail-open is safe here).
export MOCK_GH_EXIT=1
export MOCK_GH_OUTPUT=''
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "106")" || _guard_exit=$?
run_test "release_guard_fetch_failure_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_fetch_failure_exit1" "1" "$_guard_exit"
unset MOCK_GH_EXIT
export MOCK_GH_OUTPUT='[]'

# Test 14.7: no --branch provided; gh succeeds but jq parse fails (malformed
# JSON) — guard does not fire (fail-safe).
export MOCK_GH_OUTPUT='not-valid-json'
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "107")" || _guard_exit=$?
run_test "release_guard_jq_parse_fail_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_jq_parse_fail_exit1" "1" "$_guard_exit"
export MOCK_GH_OUTPUT='[]'

# Test 14.8: no --branch provided; gh succeeds with null headRefName field —
# guard does not fire (null collapses to empty string via jq // "").
export MOCK_GH_OUTPUT='{"headRefName":null}'
_guard_out=""
_guard_exit=1
_guard_out="$(_check_release_pr_guard "108")" || _guard_exit=$?
run_test "release_guard_null_head_no_fire" "RELEASE_GUARD_FIRED=0" \
  "$(printf '%s\n' "$_guard_out" | grep "^RELEASE_GUARD_FIRED=")"
run_test "release_guard_null_head_exit1" "1" "$_guard_exit"
export MOCK_GH_OUTPUT='[]'

unset _guard_out _guard_exit

# ---------------------------------------------------------------------------
# Area 15: main-loop integration — release guard in full-script execution
# ---------------------------------------------------------------------------
# The harness-mode early-return prevents the Area 14 function tests from
# exercising the main-loop code that calls _check_release_pr_guard (lines
# 4127–4163 in pr-review-loop.sh). These integration tests run the full
# script as a subprocess with a mocked gh so the main-loop path is covered.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 15: main-loop integration — release guard ==="

_integration_mock_bin="$(mktemp -d)"
_integration_cleanup() { rm -rf "${_integration_mock_bin:-}"; }
trap '_integration_cleanup' EXIT

# Minimal mock gh for the integration tests:
#  - headRefName queries: return INTEG_MOCK_HEAD_JSON
#  - pr edit (sync_reviewer_failed_label): succeed silently
#  - everything else: succeed silently
cat > "$_integration_mock_bin/gh" <<'INTEG_GH_MOCK'
#!/usr/bin/env bash
[ -n "${INTEG_MOCK_GH_LOG:-}" ] && printf '%s\n' "$*" >> "$INTEG_MOCK_GH_LOG"
[ -n "${INTEG_MOCK_GH_ENV_LOG:-}" ] && printf '%s|%s\n' "${GH_REPO:-}" "$*" >> "$INTEG_MOCK_GH_ENV_LOG"
case "$*" in
  *"headRefName"*)
    # Use a variable for the default to avoid the bash brace-balance issue:
    # ${VAR:-{"key":""}} closes ${...} at the inner }, producing a stray }
    # in the output and therefore invalid JSON.
    _hdr_default='{"headRefName":""}'
    printf '%s\n' "${INTEG_MOCK_HEAD_JSON:-$_hdr_default}"
    exit 0
    ;;
  pr\ comment\ *)
    if [ "${INTEG_MOCK_PR_COMMENT_FAIL:-0}" = "1" ]; then
      printf 'mock pr comment failure\n' >&2
      exit 64
    fi
    exit 0
    ;;
  *"pr edit"*|*"api"*|*"pr view"*)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
INTEG_GH_MOCK
chmod +x "$_integration_mock_bin/gh"

_run_loop_integration() {
  # Run pr-review-loop.sh as a subprocess with the integration mock in PATH.
  # Captures combined stdout; ignores stderr (diagnostic messages).
  PATH="$_integration_mock_bin:$PATH" \
    bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$@" 2>/dev/null
}

# Without --branch the loop derives the expected branch from the checkout it
# runs against (#1444), so the no-branch cases run against a real fixture
# checkout on the item's branch, with real git (the harness PATH shadows git
# with a fail-fast mock) and the integration gh mock.
_integ_fixtures="$(mktemp -d)"
# _integ_fixture <name> <branch>: a checkout whose origin is example/repo and
# whose HEAD names <branch> (unborn — no commit is needed to name a branch).
_integ_fixture() {
  local dir="$_integ_fixtures/$1"
  PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -c init.defaultBranch=main init -q "$dir"
  PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$dir" remote add origin https://github.com/example/repo.git
  PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$dir" symbolic-ref HEAD "refs/heads/$2"
  printf '%s\n' "$dir"
}
# _run_loop_derived <args...>: like _run_loop_integration, with real git and
# GH_REPO / WORKFLOW_TARGET_GITHUB_REPO cleared so the target comes from the
# fixture's origin.
_run_loop_derived() {
  env GH_REPO= WORKFLOW_TARGET_GITHUB_REPO= \
    PATH="$_integration_mock_bin:$TEST_PR_REVIEW_LOOP_REAL_PATH" \
    bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$@" 2>/dev/null
}
# _integ_head_json <branch> [<owner/repo>]: a same-repository PR head
# (default repository: example/repo).
_integ_head_json() {
  local slug="${2:-example/repo}"
  printf '{"headRefName":"%s","headRepositoryOwner":{"login":"%s"},"headRepository":{"name":"%s"},"isCrossRepository":false}' \
    "$1" "${slug%%/*}" "${slug#*/}"
}

# Test 15.1: release/* head branch, no --branch → the expected branch is derived
# from the --repo-root checkout and verified; main loop emits RESULT=skipped,
# REASON=release_pr, exits 0
INTEG_MOCK_HEAD_JSON="$(_integ_head_json release/v9.9.9)"
export INTEG_MOCK_HEAD_JSON
_integ_gh_log="$(mktemp)"
export INTEG_MOCK_GH_LOG="$_integ_gh_log"
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(_run_loop_derived 999 --repo-root "$(_integ_fixture r999 release/v9.9.9)")"
_integ_exit=$?
set -e
run_test "mainloop_derived_branch_source_checkout" "PR_OWNERSHIP_BRANCH_SOURCE=checkout" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_BRANCH_SOURCE=')"
run_test "mainloop_derived_branch_owned" "PR_OWNERSHIP_RESULT=owned" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_release_guard_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_release_guard_reason_release_pr" "REASON=release_pr" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_release_guard_exit0" "0" "$_integ_exit"
run_test "mainloop_release_guard_posts_summary" "1" "$(
  grep -c -- 'pr comment 999 --body-file' "$_integ_gh_log" 2>/dev/null || true
)"
rm -f "$_integ_gh_log"
unset INTEG_MOCK_GH_LOG
unset INTEG_MOCK_HEAD_JSON

# Test 15.1b: release guard escalates if it cannot post the required summary marker
INTEG_MOCK_HEAD_JSON="$(_integ_head_json release/v9.9.10)"
export INTEG_MOCK_HEAD_JSON
export INTEG_MOCK_PR_COMMENT_FAIL=1
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(_run_loop_derived 997 --repo-root "$(_integ_fixture r997 release/v9.9.10)")"
_integ_exit=$?
set -e
run_test "mainloop_release_guard_comment_failure_result" "RESULT=escalate" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=' | tail -1)"
run_test "mainloop_release_guard_comment_failure_reason" "REASON=release_guard_summary_failed" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=' | tail -1)"
run_test "mainloop_release_guard_comment_failure_single_result" "1" \
  "$(printf '%s\n' "$_integ_out" | grep -c '^RESULT=')"
run_test "mainloop_release_guard_comment_failure_exit1" "1" "$_integ_exit"
unset INTEG_MOCK_PR_COMMENT_FAIL
unset INTEG_MOCK_HEAD_JSON

# Test 15.2: hotfix/* head branch → main loop also emits RESULT=skipped, exits 0
# (expected branch derived from the working directory: no --repo-root). The
# working directory is another checkout of this repository — same origin as
# the checkout the loop enters, which is what makes it acceptable.
_integ_self_origin="$(PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" \
  || _integ_self_origin="https://github.com/example/repo.git"
_integ_self_slug="${_integ_self_origin%.git}"
_integ_self_slug="${_integ_self_slug#*github.com[:/]}"
INTEG_MOCK_HEAD_JSON="$(_integ_head_json hotfix/v9.9.1 "$_integ_self_slug")"
export INTEG_MOCK_HEAD_JSON
_integ_gh_log="$(mktemp)"
export INTEG_MOCK_GH_LOG="$_integ_gh_log"
_integ_out=""
_integ_exit=0
_integ_hotfix_dir="$(_integ_fixture h998 hotfix/v9.9.1)"
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_integ_hotfix_dir" remote set-url origin "$_integ_self_origin"
set +e
_integ_out="$(cd "$_integ_hotfix_dir" && _run_loop_derived 998)"
_integ_exit=$?
set -e
run_test "mainloop_hotfix_guard_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_hotfix_guard_exit0" "0" "$_integ_exit"
run_test "mainloop_hotfix_guard_posts_summary" "1" "$(
  grep -c -- 'pr comment 998 --body-file' "$_integ_gh_log" 2>/dev/null || true
)"
rm -f "$_integ_gh_log"
unset INTEG_MOCK_GH_LOG
unset INTEG_MOCK_HEAD_JSON

# Test 15.3: --branch release/v9.9.9 flag → the PR ownership guard (#1444)
# confirms PR 997 is that branch's PR, then the release guard fires on the
# given branch without its own head lookup, exits 0
export INTEG_MOCK_HEAD_JSON='{"headRefName":"release/v9.9.9","headRepositoryOwner":{"login":"example"},"headRepository":{"name":"repo"},"isCrossRepository":false}'
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(GH_REPO= WORKFLOW_TARGET_GITHUB_REPO=example/repo _run_loop_integration 997 --branch release/v9.9.9)"
_integ_exit=$?
set -e
run_test "mainloop_branch_flag_release_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_branch_flag_release_exit0" "0" "$_integ_exit"
run_test "mainloop_branch_flag_ownership_owned" "PR_OWNERSHIP_RESULT=owned" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
unset INTEG_MOCK_HEAD_JSON

# Test 15.4: --branch names this item's branch but the PR number is a
# sibling's (#1444) → RESULT=escalate REASON=pr_ownership_mismatch, exit 2, and
# the only gh call is the ownership read: nothing posted, readied, or labelled.
export INTEG_MOCK_HEAD_JSON='{"headRefName":"spec/10-sibling-item","headRepositoryOwner":{"login":"example"},"headRepository":{"name":"repo"},"isCrossRepository":false}'
_integ_gh_log="$(mktemp)"
export INTEG_MOCK_GH_LOG="$_integ_gh_log"
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(GH_REPO= WORKFLOW_TARGET_GITHUB_REPO=example/repo _run_loop_integration 52 --branch spec/13-own-item)"
_integ_exit=$?
set -e
run_test "mainloop_ownership_mismatch_result_escalate" "RESULT=escalate" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_ownership_mismatch_reason" "REASON=pr_ownership_mismatch" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_ownership_mismatch_exit2" "2" "$_integ_exit"
run_test "mainloop_ownership_mismatch_head_reported" "PR_OWNERSHIP_PR_HEAD_BRANCH=spec/10-sibling-item" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_PR_HEAD_BRANCH=')"
run_test "mainloop_ownership_mismatch_only_read_call" \
  "pr view 52 --repo example/repo --json headRefName,headRepositoryOwner,headRepository,isCrossRepository" \
  "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"
unset INTEG_MOCK_GH_LOG

# Test 15.5: fork PR carrying the same branch name → mismatch on head repository
export INTEG_MOCK_HEAD_JSON='{"headRefName":"spec/13-own-item","headRepositoryOwner":{"login":"forker"},"headRepository":{"name":"repo-fork"},"isCrossRepository":true}'
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(GH_REPO= WORKFLOW_TARGET_GITHUB_REPO=example/repo _run_loop_integration 54 --branch spec/13-own-item)"
_integ_exit=$?
set -e
run_test "mainloop_ownership_fork_reason" "REASON=pr_ownership_mismatch" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_ownership_fork_kind" "PR_OWNERSHIP_MISMATCH=head_repository" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_MISMATCH=')"
run_test "mainloop_ownership_fork_exit2" "2" "$_integ_exit"

# Test 15.6: PR head cannot be resolved (mock returns an empty head) → fail
# closed with REASON=pr_ownership_unverified, exit 2
unset INTEG_MOCK_HEAD_JSON
_integ_out=""
_integ_exit=0
set +e
_integ_out="$(GH_REPO= WORKFLOW_TARGET_GITHUB_REPO=example/repo _run_loop_integration 53 --branch spec/13-own-item)"
_integ_exit=$?
set -e
run_test "mainloop_ownership_unresolved_result_escalate" "RESULT=escalate" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_ownership_unresolved_reason" "REASON=pr_ownership_unverified" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_ownership_unresolved_exit2" "2" "$_integ_exit"

# Tests 15.7–15.12: the ownership check inspects the repository the loop
# mutates, resolved like the lock key, and always passes it as --repo; the
# verified repository is then pinned for every later gh call (#1444 review).
_own_view_args='--json headRefName,headRepositoryOwner,headRepository,isCrossRepository'
export INTEG_MOCK_HEAD_JSON='{"headRefName":"release/v9.9.9","headRepositoryOwner":{"login":"acme"},"headRepository":{"name":"rootonly"},"isCrossRepository":false}'
_own_fixture_root="$(mktemp -d)"
# Real git (the harness PATH shadows git with a fail-fast mock): the fixtures
# are real checkouts, and the loop must read their origin remotes.
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -c init.defaultBranch=main init -q "$_own_fixture_root/with-origin"
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_own_fixture_root/with-origin" remote add origin https://github.com/acme/rootonly.git
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -c init.defaultBranch=main init -q "$_own_fixture_root/no-origin"

# _own_run <env-assignments...> -- <loop args...>: run the loop with GH_REPO and
# WORKFLOW_TARGET_GITHUB_REPO cleared unless the case sets them, the integration
# gh mock, and real git.
_own_run() {
  local _envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do _envs+=("$1"); shift; done
  shift
  _integ_gh_log="$(mktemp)"
  _integ_gh_env_log="$(mktemp)"
  _integ_out=""
  _integ_exit=0
  set +e
  _integ_out="$(env GH_REPO= WORKFLOW_TARGET_GITHUB_REPO= ${_envs[@]+"${_envs[@]}"} \
    INTEG_MOCK_GH_LOG="$_integ_gh_log" INTEG_MOCK_GH_ENV_LOG="$_integ_gh_env_log" \
    PATH="$_integration_mock_bin:$TEST_PR_REVIEW_LOOP_REAL_PATH" \
    bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" "$@" 2>/dev/null)"
  _integ_exit=$?
  set -e
}

# 15.7: --repo-root only → the root's origin, not the caller's cwd repo
_own_run -- 997 --branch release/v9.9.9 --repo-root "$_own_fixture_root/with-origin"
run_test "mainloop_ownership_repo_root_only_queries_root_origin" \
  "pr view 997 --repo acme/rootonly $_own_view_args" "$(head -n 1 "$_integ_gh_log")"
run_test "mainloop_ownership_repo_root_only_reports_repo" "PR_OWNERSHIP_REPO=acme/rootonly" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_REPO=')"
run_test "mainloop_ownership_repo_root_only_result_skipped" "RESULT=skipped" \
  "$(printf '%s\n' "$_integ_out" | grep '^RESULT=')"
run_test "mainloop_ownership_repo_root_only_summary_pinned" "1" \
  "$(grep -c '^acme/rootonly|pr comment 997 --body-file' "$_integ_gh_env_log" || true)"
rm -f "$_integ_gh_log" "$_integ_gh_env_log"

# 15.8: WORKFLOW_TARGET_GITHUB_REPO only
_own_run INTEG_MOCK_HEAD_JSON='{"headRefName":"release/v9.9.9","headRepositoryOwner":{"login":"acme"},"headRepository":{"name":"envonly"},"isCrossRepository":false}' \
  WORKFLOW_TARGET_GITHUB_REPO=acme/envonly -- 997 --branch release/v9.9.9
run_test "mainloop_ownership_env_target_only_queries_env_repo" \
  "pr view 997 --repo acme/envonly $_own_view_args" "$(head -n 1 "$_integ_gh_log")"
run_test "mainloop_ownership_env_target_only_owned" "PR_OWNERSHIP_RESULT=owned" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
rm -f "$_integ_gh_log" "$_integ_gh_env_log"

# 15.9: GH_REPO only — bare gh calls in the loop follow it, so the check must too
_own_run GH_REPO=acme/ghonly -- 997 --branch release/v9.9.9
run_test "mainloop_ownership_gh_repo_only_queries_gh_repo" \
  "pr view 997 --repo acme/ghonly $_own_view_args" "$(head -n 1 "$_integ_gh_log")"
rm -f "$_integ_gh_log" "$_integ_gh_env_log"

# 15.10: --repo slug wins over the environment
_own_run WORKFLOW_TARGET_GITHUB_REPO=acme/envonly -- 997 --branch release/v9.9.9 --repo acme/flag
run_test "mainloop_ownership_repo_flag_queries_flag_repo" \
  "pr view 997 --repo acme/flag $_own_view_args" "$(head -n 1 "$_integ_gh_log")"
rm -f "$_integ_gh_log" "$_integ_gh_env_log"

# 15.11: WORKFLOW_TARGET_GITHUB_REPO and GH_REPO disagree → fail closed, no gh call
_own_run WORKFLOW_TARGET_GITHUB_REPO=acme/one GH_REPO=acme/two -- 997 --branch release/v9.9.9
run_test "mainloop_ownership_env_conflict_reason" "REASON=pr_ownership_unverified" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_ownership_env_conflict_result" "PR_OWNERSHIP_RESULT=repo_unresolved" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_ownership_env_conflict_exit2" "2" "$_integ_exit"
run_test "mainloop_ownership_env_conflict_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log" "$_integ_gh_env_log"

# 15.12: --repo-root without an origin and no other source → fail closed
_own_run -- 997 --branch release/v9.9.9 --repo-root "$_own_fixture_root/no-origin"
run_test "mainloop_ownership_no_target_reason" "REASON=pr_ownership_unverified" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_ownership_no_target_exit2" "2" "$_integ_exit"
run_test "mainloop_ownership_no_target_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log" "$_integ_gh_env_log"
rm -rf "$_own_fixture_root"
unset INTEG_MOCK_HEAD_JSON _own_view_args _own_fixture_root _integ_gh_env_log

# Tests 15.13–15.17: no --branch (#1444 review). The derived branch is checked
# like --branch; a checkout that cannot vouch for a PR number fails closed.
# 15.13: derived branch, PR number is a sibling's → mismatch, only the read call
INTEG_MOCK_HEAD_JSON="$(_integ_head_json spec/10-sibling-item)"
export INTEG_MOCK_HEAD_JSON
_integ_gh_log="$(mktemp)"
_integ_out="$(INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 52 --repo-root "$(_integ_fixture own13 spec/13-own-item)")" || true
run_test "mainloop_derived_mismatch_reason" "REASON=pr_ownership_mismatch" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_derived_mismatch_expected_branch" "PR_OWNERSHIP_EXPECTED_BRANCH=spec/13-own-item" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_EXPECTED_BRANCH=')"
run_test "mainloop_derived_mismatch_only_read_call" \
  "pr view 52 --repo example/repo --json headRefName,headRepositoryOwner,headRepository,isCrossRepository" \
  "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"

# 15.14–15.16: develop, main, and a detached HEAD cannot vouch → fail closed
# with REASON=pr_ownership_branch_required and no gh call at all
_integ_detached="$(_integ_fixture detached fix/1-x)"
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_integ_detached" -c user.name=t -c user.email=t@example.com \
  commit -q --allow-empty -m init
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_integ_detached" checkout -q --detach
for _integ_case in develop main detached; do
  case "$_integ_case" in
    detached) _integ_dir="$_integ_detached" ;;
    *) _integ_dir="$(_integ_fixture "nw-$_integ_case" "$_integ_case")" ;;
  esac
  _integ_gh_log="$(mktemp)"
  _integ_exit=0
  _integ_out="$(INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 53 --repo-root "$_integ_dir")" || _integ_exit=$?
  run_test "mainloop_${_integ_case}_branch_required_reason" "REASON=pr_ownership_branch_required" \
    "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
  run_test "mainloop_${_integ_case}_branch_required_exit2" "2" "$_integ_exit"
  run_test "mainloop_${_integ_case}_branch_required_no_gh_call" "" "$(cat "$_integ_gh_log")"
  rm -f "$_integ_gh_log"
done

# 15.17: --branch wins over the --repo-root checkout's branch (here develop,
# which alone would fail closed)
INTEG_MOCK_HEAD_JSON="$(_integ_head_json release/v9.9.9)"
export INTEG_MOCK_HEAD_JSON
_integ_exit=0
_integ_out="$(_run_loop_derived 997 --branch release/v9.9.9 --repo-root "$_integ_fixtures/nw-develop")" || _integ_exit=$?
run_test "mainloop_branch_flag_wins_over_checkout_source" "PR_OWNERSHIP_BRANCH_SOURCE=argument" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_BRANCH_SOURCE=')"
run_test "mainloop_branch_flag_wins_over_checkout_owned" "PR_OWNERSHIP_RESULT=owned" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_branch_flag_wins_over_checkout_exit0" "0" "$_integ_exit"

# Tests 15.18–15.21: the expected branch and the target repository come from
# the same checkout (#1444 review, round 3).
INTEG_MOCK_HEAD_JSON="$(_integ_head_json spec/13-own-item)"
export INTEG_MOCK_HEAD_JSON
_integ_other="$(_integ_fixture cwd-other spec/13-own-item)"
# 15.18: branch derived from a working directory whose origin (example/repo)
# is not the repository of the checkout the loop enters (this repository) →
# fail closed, no gh call; never verify and pin a same-number PR elsewhere
_integ_gh_log="$(mktemp)"
_integ_exit=0
_integ_out="$(cd "$_integ_other" && INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 53)" || _integ_exit=$?
run_test "mainloop_cwd_origin_differs_reason" "REASON=pr_ownership_unverified" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_cwd_origin_differs_result" "PR_OWNERSHIP_RESULT=repo_conflict" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_cwd_origin_differs_exit2" "2" "$_integ_exit"
run_test "mainloop_cwd_origin_differs_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"

# 15.19: a named repository that differs from the origin of the checkout the
# branch came from → fail closed, no gh call
_integ_gh_log="$(mktemp)"
_integ_exit=0
_integ_out="$(INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 53 --repo-root "$_integ_other" --repo acme/other)" || _integ_exit=$?
run_test "mainloop_explicit_repo_vs_checkout_reason" "REASON=pr_ownership_unverified" \
  "$(printf '%s\n' "$_integ_out" | grep '^REASON=')"
run_test "mainloop_explicit_repo_vs_checkout_result" "PR_OWNERSHIP_RESULT=repo_conflict" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_explicit_repo_vs_checkout_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"
# ... and the same conflict when the repository is named through the environment
_integ_gh_log="$(mktemp)"
_integ_out="$(INTEG_MOCK_GH_LOG="$_integ_gh_log" env WORKFLOW_TARGET_GITHUB_REPO=acme/other \
  PATH="$_integration_mock_bin:$TEST_PR_REVIEW_LOOP_REAL_PATH" \
  bash "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh" 53 --repo-root "$_integ_other" 2>/dev/null)" || true
run_test "mainloop_env_repo_vs_checkout_result" "PR_OWNERSHIP_RESULT=repo_conflict" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_env_repo_vs_checkout_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"

# 15.20: a checkout the branch came from with no GitHub origin → fail closed
_integ_noorigin="$_integ_fixtures/no-origin-branch"
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -c init.defaultBranch=main init -q "$_integ_noorigin"
PATH="$TEST_PR_REVIEW_LOOP_REAL_PATH" git -C "$_integ_noorigin" symbolic-ref HEAD refs/heads/spec/13-own-item
_integ_gh_log="$(mktemp)"
_integ_out="$(INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 53 --repo-root "$_integ_noorigin" --repo example/repo)" || true
run_test "mainloop_checkout_without_origin_result" "PR_OWNERSHIP_RESULT=repo_unresolved" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_checkout_without_origin_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"

# 15.20b: working-directory branch plus a named repository equal to that
# directory's origin still fails closed when the checkout the loop enters is
# another repository — the name cannot reconcile two checkouts
_integ_gh_log="$(mktemp)"
_integ_out="$(cd "$_integ_other" && INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 53 --repo example/repo)" || true
run_test "mainloop_cwd_named_repo_other_root_result" "PR_OWNERSHIP_RESULT=repo_conflict" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_RESULT=')"
run_test "mainloop_cwd_named_repo_other_root_no_gh_call" "" "$(cat "$_integ_gh_log")"
rm -f "$_integ_gh_log"

# 15.21: a named repository equal to the checkout's origin (any case) → the
# check runs against it
_integ_gh_log="$(mktemp)"
_integ_out="$(INTEG_MOCK_GH_LOG="$_integ_gh_log" _run_loop_derived 52 --repo-root "$_integ_other" --repo Example/Repo)" || true
run_test "mainloop_explicit_repo_matches_checkout_source" "PR_OWNERSHIP_REPO_SOURCE=explicit_matches_checkout" \
  "$(printf '%s\n' "$_integ_out" | grep '^PR_OWNERSHIP_REPO_SOURCE=')"
run_test "mainloop_explicit_repo_matches_checkout_queries_it" \
  "pr view 52 --repo Example/Repo --json headRefName,headRepositoryOwner,headRepository,isCrossRepository" \
  "$(head -n 1 "$_integ_gh_log")"
rm -f "$_integ_gh_log"

rm -rf "$_integ_fixtures"
unset INTEG_MOCK_HEAD_JSON _integ_fixtures _integ_detached _integ_dir _integ_case _integ_hotfix_dir \
  _integ_other _integ_noorigin _integ_self_origin _integ_self_slug

_integration_cleanup
unset _integ_out _integ_exit INTEG_MOCK_HEAD_JSON

# ---------------------------------------------------------------------------
# Area 16: run_bugbot_review() — exit-code and key-value output contract (AC-9)
#
# Tests cover:
#   16.0a bot_login_for_platform returns "cursor[bot]" by default for bugbot
#   16.0b bot_login_for_platform respects BUGBOT_BOT_LOGIN env override
#   16.1  clean path: check run completes with conclusion=success, no blocking
#         comments → RESULT=clean, exit 0
#   16.2  needs_fixes path: check run completes with conclusion=failure, blocking
#         cursor[bot] review body → RESULT=needs_fixes, exit 1
#   16.3  No verdict yet: check run in_progress, budget exhausted with
#         check_appeared=1 → RESULT=waiting_on_reviewer,
#         REASON=reviewer-no-verdict-yet, detail check_not_completed, exit 4
#         (#1789; was escalate/timeout)
#   16.4  No verdict yet: no check run appears within budget
#         (check_appeared=0) → RESULT=waiting_on_reviewer, detail
#         check_not_started, exit 4 (#1789; was escalate/unavailable)
#   16.5  escalate (head-sha-unavailable): pulls API returns empty head SHA
#         → RESULT=escalate, REASON=head-sha-unavailable, exit 2
#   16.6  idempotency fast-path: existing blocking cursor[bot] finding on HEAD
#         → RESULT=needs_fixes REASON=existing_findings, exit 1 (no trigger POST)
#   16.7  trigger-failed path: trigger comment POST fails
#         → RESULT=escalate REASON=trigger-failed, exit 2
#   16.8  fetch-failed path: check-run API call fails during Phase 3 poll
#         → RESULT=escalate REASON=fetch-failed, exit 2
#   16.8b fetch-failed path: check-run API call fails during Phase 2 trigger guard
#         → RESULT=escalate REASON=fetch-failed, exit 2
#   16.8c fetch-failed path: check-run JSON parse fails during Phase 2 trigger guard
#         → RESULT=escalate REASON=fetch-failed, exit 2
#   16.9  neutral conclusion with no output.summary: not a verdict
#         → RESULT=escalate REASON=bugbot-unverified-verdict, exit 2
#   16.9a neutral conclusion with an affirmative no-issues summary
#         → RESULT=clean BLOCKING_COUNT=0, exit 0
#   16.9b neutral conclusion whose summary reports 3 findings, with matching
#         cursor[bot] High Severity comments → RESULT=needs_fixes with
#         BLOCKING_COUNT=3 and BLOCKING_* detail, exit 1
#   16.9c neutral conclusion whose summary reports findings but none are
#         retrievable → RESULT=escalate REASON=bugbot-findings-not-retrievable
#   16.9d neutral conclusion whose summary is unparseable
#         → RESULT=escalate REASON=bugbot-unverified-verdict, exit 2
#   16.13 retry-once: an unfinished check run is re-triggered once, at the
#         plan D3 point inside the budget, before the loop reports No verdict
#         yet (#1789; was REASON=timeout after a second full budget)
#   16.14 is_bugbot_clean_review rejects finding counts above 5
#   16.10 run_platform_review routes "bugbot" to run_bugbot_review
#
# Each test that exercises run_bugbot_review requires a custom gh mock because
# the function issues several incompatible gh API call shapes in a single run
# (pulls API, commits API, check-runs API, PR comments API, reviews API).  The
# per-test custom mock is written to a temp directory and placed on PATH before
# calling run_bugbot_review.
# ---------------------------------------------------------------------------
echo ""
echo "=== Area 16: run_bugbot_review — clean / needs_fixes / escalate ==="

# Helper overrides injected into every run_bugbot_review subshell.
_bugbot_overrides='
  cd_workflow_repo_root() { :; }
  repo_slug() { printf "owner/repo\n"; }
  require_gh() { :; }
  _interruptible_sleep() { :; }
'

# ---------------------------------------------------------------------------
# Test 16.0a: bot_login_for_platform returns "cursor[bot]" for bugbot (default)
# ---------------------------------------------------------------------------
unset BUGBOT_BOT_LOGIN
actual="$(bot_login_for_platform "bugbot")"
run_test "bugbot_bot_login_default" "cursor[bot]" "$actual"

# ---------------------------------------------------------------------------
# Test 16.0b: bot_login_for_platform respects BUGBOT_BOT_LOGIN env override
# ---------------------------------------------------------------------------
export BUGBOT_BOT_LOGIN="my-custom-bugbot[bot]"
actual="$(bot_login_for_platform "bugbot")"
run_test "bugbot_bot_login_env_override" "my-custom-bugbot[bot]" "$actual"
unset BUGBOT_BOT_LOGIN

# ---------------------------------------------------------------------------
# Test 16.0c-d: Bugbot clean summary detection must not hide finding markers
# ---------------------------------------------------------------------------
bugbot_clean_body="Cursor Bugbot found no new issues in this pull request."
if is_bugbot_clean_review "$bugbot_clean_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_clean_phrase_is_non_blocking" "clean" "$actual"

bugbot_current_clean_body=$'<!-- BUGBOT_REVIEW -->\n✅ Bugbot reviewed your changes and found no new issues!\n\n_Comment `@cursor review` or `bugbot run` to trigger another review on this PR_\n\n<sup>Reviewed by [Cursor Bugbot](https://cursor.com/bugbot) for commit a195d26744760a2060cc934596779c821394ba21. Configure [here](https://www.cursor.com/dashboard/bugbot).</sup>'
if is_bugbot_clean_review "$bugbot_current_clean_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_current_clean_review_is_non_blocking" "clean" "$actual"

bugbot_current_mixed_body="$bugbot_current_clean_body"$'\n\n**Medium Severity**\n\n<!-- BUGBOT_BUG_ID: abc123 -->'
if is_bugbot_clean_review "$bugbot_current_mixed_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_current_finding_markers_override_clean_phrase" "blocking" "$actual"

bugbot_mixed_body=$'Cursor Bugbot found no issues in this pull request.\n\n**High Severity**\n\n<!-- BUGBOT_BUG_ID: abc123 -->'
if is_bugbot_clean_review "$bugbot_mixed_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_finding_markers_override_clean_phrase" "blocking" "$actual"

bugbot_multiline_body=$'Cursor Bugbot found no issues in this pull request.\n\nThis review still describes a blocking workflow problem.'
if is_bugbot_clean_review "$bugbot_multiline_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_clean_phrase_in_multiline_body_is_blocking" "blocking" "$actual"

bugbot_same_line_severity_body="Cursor Bugbot found no issues in this pull request. **High Severity**: still broken"
if is_bugbot_clean_review "$bugbot_same_line_severity_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_same_line_severity_is_blocking" "blocking" "$actual"

bugbot_same_line_mixed_body="Cursor Bugbot found no issues in this pull request, but the reviewer loop still drops blocking findings."
if is_bugbot_clean_review "$bugbot_same_line_mixed_body"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_same_line_mixed_phrase_is_blocking" "blocking" "$actual"
unset bugbot_clean_body bugbot_current_clean_body bugbot_current_mixed_body bugbot_mixed_body bugbot_multiline_body bugbot_same_line_severity_body bugbot_same_line_mixed_body actual

if is_bugbot_disabled_message "Bugbot is disabled for this repository."; then
  actual="disabled"
else
  actual="active"
fi
run_test "bugbot_disabled_message_detected" "disabled" "$actual"

if is_bugbot_disabled_message "Cursor Bugbot found no issues in this pull request."; then
  actual="disabled"
else
  actual="active"
fi
run_test "bugbot_clean_phrase_not_disabled" "active" "$actual"

if is_bugbot_disabled_message "This repository setting is disabled for this repository in general."; then
  actual="disabled"
else
  actual="active"
fi
run_test "bugbot_generic_disabled_phrase_not_matched" "active" "$actual"

if is_bugbot_usage_limit_message "Bugbot couldn't run - usage limit reached"; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_usage_limit_message_detected" "usage_limit" "$actual"

if is_bugbot_usage_limit_message "Bugbot could not run: usage/spend limit reached"; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_usage_spend_slash_message_detected" "usage_limit" "$actual"

if is_bugbot_usage_limit_message "Bugbot could not run: usage/spend-limit reached"; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_usage_spend_hyphen_message_detected" "usage_limit" "$actual"

if is_bugbot_usage_limit_message "Cursor Bugbot found no issues in this pull request."; then
  actual="usage_limit"
else
  actual="active"
fi
run_test "bugbot_clean_phrase_not_usage_limit" "active" "$actual"

bugbot_explicit_skip_body="Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."
if is_bugbot_explicit_skip_message "$bugbot_explicit_skip_body"; then
  actual="explicit_skip"
else
  actual="active"
fi
run_test "bugbot_explicit_skip_message_detected" "explicit_skip" "$actual"

if is_bugbot_explicit_skip_message "Cursor Bugbot found no issues in this pull request."; then
  actual="explicit_skip"
else
  actual="active"
fi
run_test "bugbot_clean_phrase_not_explicit_skip" "active" "$actual"
unset bugbot_explicit_skip_body actual

# ---------------------------------------------------------------------------
# Test 16.1: clean path — check run conclusion=success, no blocking comments
# ---------------------------------------------------------------------------
_bugbot_mock_dir_161="$(mktemp -d)"
cat > "$_bugbot_mock_dir_161/gh" <<'BUGBOT_GH_161'
#!/usr/bin/env bash
case "$*" in
  # pulls API — head SHA resolution
  *"--jq .head.sha"*)
    printf 'abc161sha\n'; exit 0 ;;
  # commit timestamp resolution
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  # trigger comment POST
  *"--method POST"*)
    exit 0 ;;
  # existing inline comments (Phase 1 and Phase 3 success path): no cursor[bot] comments
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  # existing reviews (Phase 1): none
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # check-runs Phase 2 (trigger guard) and Phase 3 poll: conclusion=success.
  # Output one page as a raw JSON object (no outer array) to match gh --paginate
  # format: each page is a top-level object with a check_runs key.
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  # headRefOid refresh inside poll loop
  *"headRefOid"*)
    printf 'abc161sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_161
chmod +x "$_bugbot_mock_dir_161/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_161:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_clean_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_clean_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_clean_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_161"
unset _bugbot_mock_dir_161 actual_output actual_exit

# A successful check-run with both an explicit skip and a real finding must
# preserve the blocker. The comments endpoint returns empty for Phase 1, then
# mixed comments for the success-conclusion inspection.
_bugbot_mock_dir_161b="$(mktemp -d)"
printf '0\n' > "$_bugbot_mock_dir_161b/comment_calls"
cat > "$_bugbot_mock_dir_161b/gh" <<'BUGBOT_GH_161B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc161bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 1 ]; then
      printf '[]\n'
    else
      printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc161bsha","original_commit_id":"abc161bsha","path":"src/lib.c","line":10,"body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."},{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:01:00Z","commit_id":"abc161bsha","original_commit_id":"abc161bsha","path":"src/lib.c","line":11,"body":"BUGBOT_REVIEW: null pointer"}]\n'
    fi
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc161bsha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_161B
chmod +x "$_bugbot_mock_dir_161b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_161b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_success_blocker_beats_explicit_skip_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_success_blocker_beats_explicit_skip_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_success_blocker_beats_explicit_skip_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_161b"
unset _bugbot_mock_dir_161b actual_output actual_exit

# A blocking check conclusion with only an explicit skip message should still
# surface the authoritative skip, not a synthetic blocker.
_bugbot_mock_dir_161c="$(mktemp -d)"
printf '0\n' > "$_bugbot_mock_dir_161c/comment_calls"
cat > "$_bugbot_mock_dir_161c/gh" <<'BUGBOT_GH_161C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc161csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    calls_file="$(dirname "$0")/comment_calls"
    calls="$(cat "$calls_file")"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$calls_file"
    if [ "$calls" -eq 1 ]; then
      printf '[]\n'
    else
      printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc161csha","original_commit_id":"abc161csha","path":"src/lib.c","line":10,"body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."}]\n'
    fi
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"failure","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc161csha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_161C
chmod +x "$_bugbot_mock_dir_161c/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_161c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_failure_explicit_skip_only_result" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_failure_explicit_skip_only_reason" "REASON=explicit-skip" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_failure_explicit_skip_only_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_161c"
unset _bugbot_mock_dir_161c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.2: needs_fixes path — conclusion=failure, blocking cursor[bot] review
# ---------------------------------------------------------------------------
_bugbot_mock_dir_162="$(mktemp -d)"
cat > "$_bugbot_mock_dir_162/gh" <<'BUGBOT_GH_162'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc162sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  # Phase 1 existing comments — none on entry
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  # Phase 1 existing reviews — none on entry; Phase 3 blocking review
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","state":"CHANGES_REQUESTED","body":"BUGBOT_REVIEW: null pointer dereference at src/main.c:42"}]\n'
    exit 0 ;;
  # Output raw page object (no outer array) to match gh --paginate format.
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"failure","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc162sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_162
chmod +x "$_bugbot_mock_dir_162/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_162:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_needs_fixes_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_needs_fixes_blocking_count_nonzero" "1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" | cut -d= -f2)"
run_test "bugbot_needs_fixes_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_162"
unset _bugbot_mock_dir_162 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.2b: CHANGES_REQUESTED review blocks even with clean body text
# ---------------------------------------------------------------------------
_bugbot_mock_dir_162b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_162b/gh" <<'BUGBOT_GH_162B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc162bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","commit_id":"abc162bsha","state":"CHANGES_REQUESTED","body":"Cursor Bugbot found no issues in this pull request."}]\n'
    exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc162bsha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_162B
chmod +x "$_bugbot_mock_dir_162b/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_162b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_clean_body_blocks_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_changes_requested_clean_body_blocks_count" "1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_clean_body_blocks_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_162b"
unset _bugbot_mock_dir_162b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.2c: CHANGES_REQUESTED review blocks even with an empty body
# ---------------------------------------------------------------------------
_bugbot_mock_dir_162c="$(mktemp -d)"
cat > "$_bugbot_mock_dir_162c/gh" <<'BUGBOT_GH_162C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc162csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","commit_id":"abc162csha","state":"CHANGES_REQUESTED","body":""}]\n'
    exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc162csha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_162C
chmod +x "$_bugbot_mock_dir_162c/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_162c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_empty_body_blocks_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_changes_requested_empty_body_blocks_count" "1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=" | cut -d= -f2)"
run_test "bugbot_changes_requested_empty_body_blocks_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_162c"
unset _bugbot_mock_dir_162c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.3: No verdict yet — run appeared but never completed
# poll_interval=1, max_wait=1: loop runs once (sets check_appeared=1 via
# in_progress status), then budget exhausted → No verdict yet,
# check_not_completed (#1789, plan D8 Bugbot row; was REASON=timeout)
# ---------------------------------------------------------------------------
_bugbot_mock_dir_163="$(mktemp -d)"
cat > "$_bugbot_mock_dir_163/gh" <<'BUGBOT_GH_163'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc163sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # Return in_progress (raw page object) so check_appeared is set but run never completes.
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"in_progress","conclusion":null,"started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc163sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_163
chmod +x "$_bugbot_mock_dir_163/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_163:$PATH" run_bugbot_review "42" "feature/42-test" "1" "1" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_timeout_result" "RESULT=waiting_on_reviewer" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_timeout_reason" "REASON=reviewer-no-verdict-yet" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_timeout_detail" "WAIT_EXPIRED_DETAIL=check_not_completed" \
  "$(printf '%s\n' "$actual_output" | grep "^WAIT_EXPIRED_DETAIL=")"
run_test "bugbot_timeout_exit_code" "4" "$actual_exit"
rm -rf "$_bugbot_mock_dir_163"
unset _bugbot_mock_dir_163 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.4: No verdict yet — no check run appeared within budget
# max_wait=0: poll loop never executes, check_appeared=0 → No verdict yet,
# check_not_started (#1789, plan D8 Bugbot row; was REASON=unavailable)
# ---------------------------------------------------------------------------
_bugbot_mock_dir_164="$(mktemp -d)"
cat > "$_bugbot_mock_dir_164/gh" <<'BUGBOT_GH_164'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc164sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # check-runs: no Cursor Bugbot runs → triggers POST (handled above), then
  # poll loop doesn't run because max_wait=0 → check_appeared stays 0.
  # Output raw page object (no outer array) to match gh --paginate format.
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_164
chmod +x "$_bugbot_mock_dir_164/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_164:$PATH" run_bugbot_review "42" "feature/42-test" "1" "0" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_unavailable_result" "RESULT=waiting_on_reviewer" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_unavailable_reason" "REASON=reviewer-no-verdict-yet" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_unavailable_detail" "WAIT_EXPIRED_DETAIL=check_not_started" \
  "$(printf '%s\n' "$actual_output" | grep "^WAIT_EXPIRED_DETAIL=")"
run_test "bugbot_unavailable_exit_code" "4" "$actual_exit"
rm -rf "$_bugbot_mock_dir_164"
unset _bugbot_mock_dir_164 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.4b: explicit Bugbot skip issue comment is warning-only
#
# Cursor can post an issue comment saying Bugbot skipped the PR before a check
# run appears. That is an explicit platform decision, not an unavailable
# reviewer; the loop must surface it as RESULT=skipped and avoid trigger POST.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_164b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_164b/gh" <<'BUGBOT_GH_164B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc164bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."}]\n'
    exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *)
    printf 'ERROR: unexpected gh call: %s\n' "$*" >&2; exit 1 ;;
esac
BUGBOT_GH_164B
chmod +x "$_bugbot_mock_dir_164b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_164b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_explicit_skip_result" "RESULT=skipped" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_explicit_skip_reason" "REASON=explicit-skip" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_explicit_skip_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_explicit_skip_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_164b"
unset _bugbot_mock_dir_164b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.5: escalate (head-sha-unavailable) — pulls API returns empty SHA
# ---------------------------------------------------------------------------
_bugbot_mock_dir_165="$(mktemp -d)"
cat > "$_bugbot_mock_dir_165/gh" <<'BUGBOT_GH_165'
#!/usr/bin/env bash
case "$*" in
  # pulls API returns empty body — jq produces empty string
  *"--jq .head.sha"*)
    printf '\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_165
chmod +x "$_bugbot_mock_dir_165/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_165:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_head_sha_unavailable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_head_sha_unavailable_reason" "REASON=head-sha-unavailable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_head_sha_unavailable_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_165"
unset _bugbot_mock_dir_165 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.6: idempotency fast-path — existing blocking cursor[bot] finding on HEAD
#
# When blocking cursor[bot] inline or review comments already exist for the
# current HEAD, run_bugbot_review must return needs_fixes with
# REASON=existing_findings immediately (Phase 1), without posting a trigger
# comment.  The mock returns an existing CHANGES_REQUESTED review from
# cursor[bot]; the check-runs and trigger POST endpoints must NOT be reached
# (they return non-zero to confirm they were not invoked).
# ---------------------------------------------------------------------------
_bugbot_mock_dir_166="$(mktemp -d)"
cat > "$_bugbot_mock_dir_166/gh" <<'BUGBOT_GH_166'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc166sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  # Phase 1 inline comments — none
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  # Phase 1 reviews — one blocking CHANGES_REQUESTED from cursor[bot]
  *"pulls/"*"/reviews"*)
    printf '[{"user":{"login":"cursor[bot]"},"submitted_at":"2020-01-02T00:00:00Z","commit_id":"abc166sha","state":"CHANGES_REQUESTED","body":"BUGBOT_REVIEW: null pointer at src/lib.c:10"}]\n'
    exit 0 ;;
  # check-runs and trigger POST must NOT be reached (function returns early)
  *"check-runs"*)
    printf 'ERROR: check-runs reached unexpectedly\n' >&2; exit 1 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_166
chmod +x "$_bugbot_mock_dir_166/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_166:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_existing_findings_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_existing_findings_reason" "REASON=existing_findings" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_existing_findings_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_166"
unset _bugbot_mock_dir_166 actual_output actual_exit

# Existing blockers must take precedence over an explicit skip comment.
_bugbot_mock_dir_166b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_166b/gh" <<'BUGBOT_GH_166B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc166bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc166bsha","original_commit_id":"abc166bsha","path":"src/lib.c","line":10,"body":"BUGBOT_REVIEW: null pointer"},{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:01:00Z","commit_id":"abc166bsha","original_commit_id":"abc166bsha","path":"src/lib.c","line":11,"body":"Skipping Bugbot: your auto mode classified this PR to skip. Visit the Bugbot dashboard to update your settings."}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf 'ERROR: check-runs reached unexpectedly\n' >&2; exit 1 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_166B
chmod +x "$_bugbot_mock_dir_166b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_166b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_existing_blocker_beats_explicit_skip_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_existing_blocker_beats_explicit_skip_blocking_count" "BLOCKING_COUNT=1" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_existing_blocker_beats_explicit_skip_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_166b"
unset _bugbot_mock_dir_166b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.7: trigger-failed path — trigger comment POST fails
#
# When no check run exists for the head SHA (Phase 2 count=0), the function
# posts a trigger comment.  If that POST fails, the function must escalate
# with REASON=trigger-failed.  The mock returns an empty check-runs page so
# the trigger POST branch is reached, then returns non-zero for the POST.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_167="$(mktemp -d)"
cat > "$_bugbot_mock_dir_167/gh" <<'BUGBOT_GH_167'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc167sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # Phase 2: no Bugbot run → trigger POST will be attempted
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  # Trigger comment POST fails
  *"--method POST"*)
    exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_167
chmod +x "$_bugbot_mock_dir_167/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_167:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_trigger_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_trigger_failed_reason" "REASON=trigger-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_trigger_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_167"
unset _bugbot_mock_dir_167 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.8: fetch-failed path — check-run API call fails during Phase 3 poll
#
# After a successful trigger, the poll loop calls the check-runs API each
# iteration.  When that call fails, the function must escalate immediately
# with REASON=fetch-failed rather than continuing to loop or returning clean.
#
# The mock differentiates Phase 2 (first check-runs call; returns empty so
# the trigger fires) from Phase 3 poll (second check-runs call; returns
# non-zero exit) using a call counter written to a tmp file.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_168="$(mktemp -d)"
_bugbot_cr_counter_168="/tmp/bugbot-test-168-cr-count.$$"
rm -f "$_bugbot_cr_counter_168"
cat > "$_bugbot_mock_dir_168/gh" <<BUGBOT_GH_168
#!/usr/bin/env bash
_counter_file="${_bugbot_cr_counter_168}"
case "\$*" in
  *"--jq .head.sha"*)
    printf 'abc168sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    _n="\$(cat "\$_counter_file" 2>/dev/null || printf '0')"
    _n=\$(( _n + 1 ))
    printf '%s\n' "\$_n" > "\$_counter_file"
    if [ "\$_n" -eq 1 ]; then
      # Phase 2: return empty page so trigger POST is attempted
      printf '{"check_runs":[]}\n'; exit 0
    else
      # Phase 3 poll: fail to trigger fetch-failed branch
      exit 1
    fi ;;
  *"--method POST"*)
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc168sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_168
chmod +x "$_bugbot_mock_dir_168/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_168:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_fetch_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_fetch_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_fetch_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_168"
rm -f "$_bugbot_cr_counter_168"
unset _bugbot_mock_dir_168 _bugbot_cr_counter_168 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.8b: fetch-failed path — Phase 2 check-run API call fails before trigger
#
# A failed check-run read must not be treated as "zero check runs" and must not
# trigger a Bugbot comment. It escalates as fetch-failed immediately.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_168b="$(mktemp -d)"
cat > "$_bugbot_mock_dir_168b/gh" <<'BUGBOT_GH_168B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc168bsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    exit 1 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_168B
chmod +x "$_bugbot_mock_dir_168b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_168b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_phase2_fetch_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_phase2_fetch_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_phase2_fetch_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_168b"
unset _bugbot_mock_dir_168b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.8c: fetch-failed path — Phase 2 check-run JSON parse fails
#
# Malformed check-run JSON must also escalate as fetch-failed instead of being
# coerced to an empty run list.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_168c="$(mktemp -d)"
cat > "$_bugbot_mock_dir_168c/gh" <<'BUGBOT_GH_168C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc168csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{not-json\n'; exit 0 ;;
  *"--method POST"*)
    printf 'ERROR: trigger POST reached unexpectedly\n' >&2; exit 1 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_168C
chmod +x "$_bugbot_mock_dir_168c/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_168c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_phase2_parse_failed_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_phase2_parse_failed_reason" "REASON=fetch-failed" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_phase2_parse_failed_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_168c"
unset _bugbot_mock_dir_168c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9: neutral conclusion with no recognisable summary — never clean
#
# Cursor concludes the check run `neutral` both for a review that found nothing
# and for one that found blocking issues. With no output.summary there is no
# verdict to read, so the loop must escalate rather than report clean
# (issue #1390 — the previous behaviour returned RESULT=clean here).
# ---------------------------------------------------------------------------
_bugbot_mock_dir_169="$(mktemp -d)"
cat > "$_bugbot_mock_dir_169/gh" <<'BUGBOT_GH_169'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc169sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  # check-runs: completed with conclusion=neutral and no output summary
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc169sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_169
chmod +x "$_bugbot_mock_dir_169/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_169:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_no_summary_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_no_summary_reason" "REASON=bugbot-unverified-verdict" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_neutral_no_summary_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_169"
unset _bugbot_mock_dir_169 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9a: neutral conclusion with an affirmative no-issues summary
#
# The healthy counterpart: a neutral check whose summary explicitly reports no
# issues is the one neutral shape that may pass.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_169a="$(mktemp -d)"
cat > "$_bugbot_mock_dir_169a/gh" <<'BUGBOT_GH_169A'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc169asha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z","output":{"summary":"Bugbot completed review - no issues found!"}}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc169asha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_169A
chmod +x "$_bugbot_mock_dir_169a/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_169a:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_clean_summary_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_clean_summary_blocking_count" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_neutral_clean_summary_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_169a"
unset _bugbot_mock_dir_169a actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9b: neutral conclusion whose summary reports findings, with the
# cursor[bot] comments retrievable — the exact issue #1390 failure shape.
#
# "found 3 potential issues" in output.summary plus three High/Medium severity
# cursor[bot] inline comments must produce needs_fixes with every finding
# surfaced as BLOCKING_* detail.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_169b="$(mktemp -d)"
# The initial head SHA ("old") has no findings, so Phase 1 does not short-circuit;
# a push moves HEAD to "new" before the poll observes the neutral run, and the
# findings are scoped to that new SHA — which is the path the neutral arm reads.
cat > "$_bugbot_mock_dir_169b/gh" <<'BUGBOT_GH_169B'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc169bold\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","commit_id":"abc169bnew","original_commit_id":"abc169bnew","path":"src/tenant.ts","line":42,"body":"**High Severity**\\n\\nRBAC is checked but tenant ownership is never verified.\\n\\n<!-- BUGBOT_BUG_ID: bug-1 -->"},{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:01:00Z","commit_id":"abc169bnew","original_commit_id":"abc169bnew","path":"src/status.ts","line":88,"body":"**High Severity**\\n\\nCheck-then-update race on status === pending.\\n\\n<!-- BUGBOT_BUG_ID: bug-2 -->"},{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:02:00Z","commit_id":"abc169bnew","original_commit_id":"abc169bnew","path":"src/audit.ts","line":12,"body":"**Medium Severity**\\n\\nState transition nulls the audit trail column.\\n\\n<!-- BUGBOT_BUG_ID: bug-3 -->"}]\n'
    exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z","output":{"summary":"Bugbot Analysis Progress (6m 9s elapsed)\\n Final Result: Bugbot completed review and found 3 potential issues."}}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc169bnew\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_169B
chmod +x "$_bugbot_mock_dir_169b/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_169b:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_findings_result" "RESULT=needs_fixes" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_findings_reason" "REASON=blocking_findings" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_neutral_findings_blocking_count" "BLOCKING_COUNT=3" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"
run_test "bugbot_neutral_findings_first_path" "BLOCKING_1_PATH=src/tenant.ts" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_1_PATH=")"
run_test "bugbot_neutral_findings_first_line" "BLOCKING_1_LINE=42" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_1_LINE=")"
run_test "bugbot_neutral_findings_first_body_kept" "yes" \
  "$(grep -q "tenant ownership is never verified" <<< "$actual_output" && printf 'yes' || printf 'no')"
run_test "bugbot_neutral_findings_exit_code" "1" "$actual_exit"
rm -rf "$_bugbot_mock_dir_169b"
unset _bugbot_mock_dir_169b actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9c: neutral conclusion reporting findings whose comments are not
# retrievable → escalate, not clean.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_169c="$(mktemp -d)"
cat > "$_bugbot_mock_dir_169c/gh" <<'BUGBOT_GH_169C'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc169csha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z","output":{"summary":"Final Result: Bugbot completed review and found 2 potential issues."}}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc169csha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_169C
chmod +x "$_bugbot_mock_dir_169c/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_169c:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_unretrievable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_unretrievable_reason" "REASON=bugbot-findings-not-retrievable" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_neutral_unretrievable_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_169c"
unset _bugbot_mock_dir_169c actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9d: neutral conclusion with an unrecognised summary shape →
# escalate. Fails closed when the summary format changes (issue #1390 AC-4).
# ---------------------------------------------------------------------------
_bugbot_mock_dir_169d="$(mktemp -d)"
cat > "$_bugbot_mock_dir_169d/gh" <<'BUGBOT_GH_169D'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc169dsha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z","output":{"summary":"Bugbot finished. See the review tab for details."}}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc169dsha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_169D
chmod +x "$_bugbot_mock_dir_169d/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_169d:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_unparseable_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_unparseable_reason" "REASON=bugbot-unverified-verdict" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_neutral_unparseable_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_169d"
unset _bugbot_mock_dir_169d actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.14: is_bugbot_clean_review rejects finding counts above 5
#
# The first adapter enumerated "found 1..5 potential issues" only, so a body
# reporting six or more findings fell through to the clean-phrase path and was
# counted as a suggestion (issue #1390).
# ---------------------------------------------------------------------------
for _bb_n in 6 12 137; do
  bugbot_many_body="Cursor Bugbot found $_bb_n potential issues in this pull request."
  if is_bugbot_clean_review "$bugbot_many_body"; then
    actual="clean"
  else
    actual="blocking"
  fi
  run_test "bugbot_${_bb_n}_findings_is_blocking" "blocking" "$actual"
done
unset _bb_n bugbot_many_body actual

bugbot_clean_phrase_with_count="Cursor Bugbot found no new issues in this pull request."$'\n\nBugbot completed review and found 9 potential issues.'
if is_bugbot_clean_review "$bugbot_clean_phrase_with_count"; then
  actual="clean"
else
  actual="blocking"
fi
run_test "bugbot_clean_phrase_with_positive_count_is_blocking" "blocking" "$actual"
unset bugbot_clean_phrase_with_count actual

# ---------------------------------------------------------------------------
# Test 16.13: retry-once — an unfinished check run is re-triggered once
#
# Bugbot intermittently leaves its check run unfinished. A timeout is not a
# finding: the loop posts the trigger comment once more (issue #1390). #1789
# (plan D3): the re-trigger fires inside the budget at
# budget - min(600, floor(budget / 2)), which for max_wait=2 is elapsed 1, and
# the budget then ends as No verdict yet rather than a second full wait.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_1613="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1613/gh" <<'BUGBOT_GH_1613'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1613sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    printf 'posted\n' >> "$BUGBOT_1613_POSTS"
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"in_progress","conclusion":null,"started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc1613sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1613
chmod +x "$_bugbot_mock_dir_1613/gh"

_bugbot_posts_file="$(mktemp)"
export BUGBOT_1613_POSTS="$_bugbot_posts_file"
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_1613:$PATH" run_bugbot_review "42" "feature/42-test" "1" "2" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
# The Phase 2 trigger guard does not post (an in_progress run is present), so
# the only POST is the one-shot re-trigger inside the budget.
_bugbot_post_lines="$(grep -c '' "$_bugbot_posts_file" 2>/dev/null || printf '0')"
unset BUGBOT_1613_POSTS
run_test "bugbot_timeout_retriggered_at_least_once" "yes" \
  "$([ "${_bugbot_post_lines:-0}" -ge 1 ] && printf 'yes' || printf 'no')"
run_test "bugbot_timeout_retriggered_exactly_once" "1" "${_bugbot_post_lines:-0}"
run_test "bugbot_timeout_after_retry_result" "RESULT=waiting_on_reviewer" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_timeout_after_retry_reason" "REASON=reviewer-no-verdict-yet" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_timeout_after_retry_exit_code" "4" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1613"
rm -f "$_bugbot_posts_file"
unset _bugbot_mock_dir_1613 _bugbot_posts_file _bugbot_post_lines actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.9.1: neutral usage-limit comment escalates
#
# Cursor can conclude the check run as neutral while posting an issue comment
# that Bugbot could not run because a usage/spend limit was reached. That is
# unavailable, not clean.
# ---------------------------------------------------------------------------
_bugbot_mock_dir_1691="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1691/gh" <<'BUGBOT_GH_1691'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1691sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-01T00:00:01Z","body":"Bugbot could not run - usage limit reached. The organization hit a usage or spend limit."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:00Z"}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc1691sha\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1691
chmod +x "$_bugbot_mock_dir_1691/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_1691:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_usage_limit_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_usage_limit_reason" "REASON=bugbot-usage-limit" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_neutral_usage_limit_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1691"
unset _bugbot_mock_dir_1691 actual_output actual_exit

# Test 16.9.2: neutral usage-limit comment from prior head is ignored
#
# The stale comment must not escalate. The head's own summary is an affirmative
# no-issues one, which is the only neutral shape that may report clean.
_bugbot_mock_dir_1692="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1692/gh" <<'BUGBOT_GH_1692'
#!/usr/bin/env bash
case "$*" in
  *"commits/abc1692old"*".commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"commits/abc1692new"*".commit.committer.date"*)
    printf '2020-01-03T00:00:00Z\n'; exit 0 ;;
  *"--jq .head.sha"*)
    printf 'abc1692old\n'; exit 0 ;;
  *"--method POST"*)
    exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","body":"Bugbot could not run - usage limit reached."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"neutral","started_at":"2020-01-01T00:00:01Z","output":{"summary":"Bugbot completed review - no issues found!"}}]}\n'
    exit 0 ;;
  *"headRefOid"*)
    printf 'abc1692new\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1692
chmod +x "$_bugbot_mock_dir_1692/gh"

unset BUGBOT_BOT_LOGIN BUGBOT_CHECK_NAME BUGBOT_TRIGGER_COMMENT
actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  _ec=0
  PATH="$_bugbot_mock_dir_1692:$PATH" run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_neutral_stale_usage_limit_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_neutral_stale_usage_limit_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1692"
unset _bugbot_mock_dir_1692 actual_output actual_exit

# ---------------------------------------------------------------------------
# Test 16.10: run_platform_review routes "bugbot" to run_bugbot_review
# ---------------------------------------------------------------------------
_bugbot_dispatch_called=0
run_bugbot_review() { _bugbot_dispatch_called=1; }
run_platform_review "bugbot" "999" "feature/test" "30" "120" >/dev/null 2>&1 || true
run_test "run_platform_review_routes_to_run_bugbot_review" "1" "$_bugbot_dispatch_called"
unset -f run_bugbot_review
unset _bugbot_dispatch_called
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
workflow_repo_root() { printf '%s\n' "${HARNESS_REPO_ROOT:-$REPO_ROOT}"; }

# ---------------------------------------------------------------------------
# Test 16.11: disabled Bugbot preflight — escalate with bugbot-disabled
# ---------------------------------------------------------------------------
_bugbot_mock_dir_1611="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1611/gh" <<'BUGBOT_GH_1611'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1611sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-01T00:00:00Z\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-02T00:00:00Z","body":"Bugbot is disabled for this repository."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[]}\n'; exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1611
chmod +x "$_bugbot_mock_dir_1611/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  PATH="$_bugbot_mock_dir_1611:$PATH"
  _ec=0
  run_bugbot_review "42" "feature/42-test" "1" "30" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_disabled_preflight_result" "RESULT=escalate" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_disabled_preflight_reason" "REASON=bugbot-disabled" \
  "$(printf '%s\n' "$actual_output" | grep "^REASON=")"
run_test "bugbot_disabled_preflight_exit_code" "2" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1611"
unset _bugbot_mock_dir_1611 actual_output actual_exit

# Test 16.12: stale disabled issue comment before HEAD is ignored
_bugbot_mock_dir_1612="$(mktemp -d)"
cat > "$_bugbot_mock_dir_1612/gh" <<'BUGBOT_GH_1612'
#!/usr/bin/env bash
case "$*" in
  *"--jq .head.sha"*)
    printf 'abc1612sha\n'; exit 0 ;;
  *"--jq .commit.committer.date"*)
    printf '2020-01-02T00:00:00Z\n'; exit 0 ;;
  *"issues/"*"/timeline"*)
    printf '[]\n'; exit 0 ;;
  *"issues/"*"/comments"*)
    printf '[{"user":{"login":"cursor[bot]"},"created_at":"2020-01-01T00:00:00Z","body":"Bugbot is disabled for this repository."}]\n'
    exit 0 ;;
  *"pulls/"*"/comments"*)
    printf '[]\n'; exit 0 ;;
  *"pulls/"*"/reviews"*)
    printf '[]\n'; exit 0 ;;
  *"check-runs"*)
    printf '{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success","started_at":"2020-01-02T00:00:00Z"}]}\n'
    exit 0 ;;
  *)
    printf '[]\n'; exit 0 ;;
esac
BUGBOT_GH_1612
chmod +x "$_bugbot_mock_dir_1612/gh"

actual_output=""
actual_exit=0
actual_output="$(
  eval "$_bugbot_overrides"
  PATH="$_bugbot_mock_dir_1612:$PATH"
  _ec=0
  run_bugbot_review "42" "feature/42-test" "1" "5" || _ec=$?
  printf 'EXIT=%s\n' "$_ec"
)"
actual_exit="$(printf '%s\n' "$actual_output" | grep "^EXIT=" | cut -d= -f2)"
run_test "bugbot_stale_disabled_comment_result" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "bugbot_stale_disabled_comment_exit_code" "0" "$actual_exit"
rm -rf "$_bugbot_mock_dir_1612"
unset _bugbot_mock_dir_1612 actual_output actual_exit

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
