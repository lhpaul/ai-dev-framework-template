#!/usr/bin/env bash
# test-validate-branch-reuse.sh - disposable Git coverage for branch reuse.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/development-workflow/validate-branch-reuse.sh"
TMP_ROOT="$(mktemp -d)"
REAL_GIT="$(command -v git)"
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

validator_output() {
  local status output
  set +e
  output="$("$VALIDATOR" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

validator_output_with_path() {
  local path_prefix="$1"
  local status output
  shift
  set +e
  output="$(PATH="$path_prefix:$PATH" "$VALIDATOR" "$@" 2>&1)"
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

field() {
  local key="$1" output="$2"
  sed -n "s/^${key}=//p" <<< "$output" | head -n 1
}

make_repo() {
  local name="$1"
  local repo="$TMP_ROOT/$name/repo"
  local origin="$TMP_ROOT/$name/origin.git"
  mkdir -p "$TMP_ROOT/$name"
  "$REAL_GIT" init -q --bare "$origin"
  "$REAL_GIT" init -q -b develop "$repo"
  "$REAL_GIT" -C "$repo" config user.email test@example.com
  "$REAL_GIT" -C "$repo" config user.name Test
  "$REAL_GIT" -C "$repo" commit -q --allow-empty -m "initial"
  "$REAL_GIT" -C "$repo" remote add origin "$origin"
  "$REAL_GIT" -C "$repo" push -q -u origin develop
  printf '%s\n' "$repo"
}

make_compatible_local_branch() {
  local repo="$1" branch="$2"
  local parent tree commit
  parent="$("$REAL_GIT" -C "$repo" rev-parse refs/remotes/origin/develop)"
  tree="$("$REAL_GIT" -C "$repo" rev-parse "${parent}^{tree}")"
  commit="$(printf 'candidate\n' | "$REAL_GIT" -C "$repo" commit-tree "$tree" -p "$parent")"
  "$REAL_GIT" -C "$repo" update-ref "refs/heads/$branch" "$commit"
}

snapshot_repo() {
  local repo="$1"
  {
    "$REAL_GIT" -C "$repo" show-ref | sort
    "$REAL_GIT" -C "$repo" worktree list --porcelain
    "$REAL_GIT" -C "$repo" symbolic-ref -q HEAD || true
    "$REAL_GIT" -C "$repo" status --porcelain=v1
  }
}

branch="feature/1179-stale-branch-reuse"

repo="$(make_repo no-existing)"
"$REAL_GIT" -C "$repo" branch feature/11790-lookalike
"$REAL_GIT" -C "$repo" tag "backup-feature-1179-stale-branch-reuse"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
run_test "no_existing_branch_exit_zero" "0" "$(status_code "$out")"
run_test "no_existing_branch_uses_fresh_path" "no_existing_branch" "$(field RESULT "$(body "$out")")"
run_contains "lookalike_refs_do_not_match" "No exact local, remote-tracking, or worktree-owned ref" "$(body "$out")"

repo="$(make_repo compatible-local)"
make_compatible_local_branch "$repo" "$branch"
before="$(snapshot_repo "$repo")"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
after="$(snapshot_repo "$repo")"
run_test "compatible_local_exit_zero" "0" "$(status_code "$out")"
run_test "compatible_local_branch_resumes" "compatible" "$(field RESULT "$(body "$out")")"
run_test "compatible_local_source" "local" "$(field CANDIDATE_SOURCE "$(body "$out")")"
run_test "compatible_local_validator_is_read_only" "$before" "$after"

repo="$(make_repo compatible-remote)"
make_compatible_local_branch "$repo" "$branch"
"$REAL_GIT" -C "$repo" push -q origin "$branch"
"$REAL_GIT" -C "$repo" branch -D "$branch" >/dev/null
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
run_test "compatible_remote_only_branch_resumes" "compatible" "$(field RESULT "$(body "$out")")"
run_test "compatible_remote_only_source" "remote_only" "$(field CANDIDATE_SOURCE "$(body "$out")")"
run_test "compatible_remote_only_tracking" "remote_only" "$(field TRACKING_STATE "$(body "$out")")"

repo="$(make_repo compatible-worktree)"
worktree_path="$TMP_ROOT/compatible-worktree/linked worktree"
"$REAL_GIT" -C "$repo" worktree add -q -b "$branch" "$worktree_path" refs/remotes/origin/develop
worktree_path="$(CDPATH='' cd -- "$worktree_path" && pwd -P)"
before="$(snapshot_repo "$repo")"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
after="$(snapshot_repo "$repo")"
run_test "compatible_worktree_branch_resumes" "compatible" "$(field RESULT "$(body "$out")")"
run_test "compatible_worktree_source" "worktree" "$(field CANDIDATE_SOURCE "$(body "$out")")"
run_test "compatible_worktree_path" "$worktree_path" "$(field WORKTREE_PATH "$(body "$out")")"
run_test "compatible_worktree_validator_is_read_only" "$before" "$after"

repo="$(make_repo incompatible)"
"$REAL_GIT" -C "$repo" branch "$branch" refs/remotes/origin/develop
"$REAL_GIT" -C "$repo" commit -q --allow-empty -m "advance approved base"
"$REAL_GIT" -C "$repo" push -q origin develop
before="$(snapshot_repo "$repo")"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
after="$(snapshot_repo "$repo")"
run_test "incompatible_base_exit_one" "1" "$(status_code "$out")"
run_test "incompatible_base_blocks" "incompatible" "$(field RESULT "$(body "$out")")"
run_contains "incompatible_base_recovery_names_item" "item #1179" "$(body "$out")"
run_contains "incompatible_base_recovery_forbids_automatic_rewrite" "do not delete, reset, rebase, or force-push automatically" "$(body "$out")"
run_test "incompatible_validator_is_read_only" "$before" "$after"

repo="$(make_repo stale-tracking)"
make_compatible_local_branch "$repo" "$branch"
"$REAL_GIT" -C "$repo" push -q origin "$branch"
remote_tip="$("$REAL_GIT" -C "$repo" rev-parse "refs/remotes/origin/$branch")"
tree="$("$REAL_GIT" -C "$repo" rev-parse "${remote_tip}^{tree}")"
local_tip="$(printf 'local ahead\n' | "$REAL_GIT" -C "$repo" commit-tree "$tree" -p "$remote_tip")"
"$REAL_GIT" -C "$repo" update-ref "refs/heads/$branch" "$local_tip"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
run_test "stale_tracking_ref_is_diagnostic" "compatible" "$(field RESULT "$(body "$out")")"
run_test "stale_tracking_state" "local_ahead" "$(field TRACKING_STATE "$(body "$out")")"
run_test "stale_tracking_ahead_count" "1" "$(field AHEAD "$(body "$out")")"

repo="$(make_repo missing-base)"
make_compatible_local_branch "$repo" "$branch"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop-missing --repo-root "$repo")"
run_test "missing_base_exit_three" "3" "$(status_code "$out")"
run_test "missing_base_blocks" "verification_blocked" "$(field RESULT "$(body "$out")")"
run_contains "missing_base_recovery" "Restore or fetch the approved base" "$(body "$out")"

repo="$(make_repo ambiguous-worktree)"
make_compatible_local_branch "$repo" "$branch"
mock_bin="$TMP_ROOT/ambiguous-worktree/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
if [ "$#" -ge 5 ] &&
   [ "$1" = "-C" ] &&
   [ "$3" = "worktree" ] &&
   [ "$4" = "list" ] &&
   [ "$5" = "--porcelain" ]; then
  printf 'worktree /tmp/first\nHEAD deadbeef\nbranch refs/heads/feature/1179-stale-branch-reuse\n\n'
  printf 'worktree /tmp/second\nHEAD deadbeef\nbranch refs/heads/feature/1179-stale-branch-reuse\n\n'
  exit 0
fi
exec "$REAL_GIT" "$@"
MOCK_GIT
chmod +x "$mock_bin/git"
export REAL_GIT
out="$(validator_output_with_path "$mock_bin" --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
run_test "ambiguous_ref_exit_three" "3" "$(status_code "$out")"
run_test "ambiguous_ref_blocks" "verification_blocked" "$(field RESULT "$(body "$out")")"
run_contains "ambiguous_ref_reason" "ambiguously registered to multiple worktrees" "$(body "$out")"

repo="$(make_repo ancestry-failure)"
make_compatible_local_branch "$repo" "$branch"
mock_bin="$TMP_ROOT/ancestry-failure/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "--is-ancestor" ]; then
    exit 42
  fi
done
exec "$REAL_GIT" "$@"
MOCK_GIT
chmod +x "$mock_bin/git"
out="$(validator_output_with_path "$mock_bin" --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo")"
run_test "ancestry_query_failure_exit_three" "3" "$(status_code "$out")"
run_test "ancestry_query_failure_blocks" "verification_blocked" "$(field RESULT "$(body "$out")")"
run_contains "ancestry_query_failure_reason" "Ancestry query failed" "$(body "$out")"

repo="$(make_repo structured-output)"
make_compatible_local_branch "$repo" "$branch"
out="$(validator_output --issue 1179 --branch "$branch" --approved-base develop --repo-root "$repo" --json)"
shell_result="$(field RESULT "$(body "$out")")"
json_record="$(sed -n '/^{/,$p' <<< "$(body "$out")")"
json_result="$(jq -r '.result' <<< "$json_record")"
run_test "shell_and_json_outputs_agree" "$shell_result" "$json_result"
run_test "json_item" "1179" "$(jq -r '.item' <<< "$json_record")"
run_test "json_candidate_tip_matches_shell" "$(field CANDIDATE_TIP "$(body "$out")")" "$(jq -r '.candidate.tip' <<< "$json_record")"
run_test "json_human_action_matches_shell" "$(field HUMAN_ACTION "$(body "$out")")" "$(jq -r '.humanAction' <<< "$json_record")"

printf '\nResults: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
