#!/usr/bin/env bash
# test-worktree-resume-preflight.sh - Unit tests for checkpoint resume preflight.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/scripts/development-workflow/worktree-resume-preflight.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL: %s - expected %s, got %s\n' "$name" "$expected" "$actual"
  fi
}

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<<"$output"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL: %s - expected failure containing %s\n%s\n' "$name" "$expected" "$output"
  fi
}

setup_repo() {
  local name="$1"
  local repo="$TMP_ROOT/$name"
  git init -q "$repo"
  git -C "$repo" config user.email "test@example.invalid"
  git -C "$repo" config user.name "Workflow Test"
  printf 'seed\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "chore: seed"
  git -C "$repo" branch -m develop
  printf '%s\n' "$repo"
}

make_worktree() {
  local repo="$1" branch="$2" path="$3"
  git -C "$repo" worktree add -q -b "$branch" "$path" develop
}

result_field() {
  local text="$1" key="$2"
  printf '%s\n' "$text" | sed -n "s/^${key}=//p" | tail -1
}

expected_branch="implementation-plan/1174-worktree-cwd-restore-sendmessage"

run_fails_contains "missing_option_value_rejected" \
  "missing value for --expected-branch" \
  "$HELPER" --item 1174 --expected-branch

repo1="$(setup_repo already-in-worktree)"
wt1="$TMP_ROOT/wt1"
make_worktree "$repo1" "$expected_branch" "$wt1"
out1="$(cd "$wt1" && "$HELPER" --item 1174 --expected-branch "$expected_branch" --expected-worktree "$wt1" --main-repo-root "$repo1" --json)"
run_test "already_in_expected_worktree_allows_continue" "continue" "$(result_field "$out1" RESULT)"
run_test "already_in_expected_worktree_json" "continue" "$(printf '%s\n' "$out1" | tail -1 | jq -r '.result')"

repo2="$(setup_repo main-clone-reentry)"
wt2="$TMP_ROOT/worktree with spaces"
make_worktree "$repo2" "$expected_branch" "$wt2"
out2="$(cd "$repo2" && "$HELPER" --item 1174 --expected-branch "$expected_branch" --main-repo-root "$repo2")"
run_test "main_clone_single_matching_worktree_returns_reentry" "reenter" "$(result_field "$out2" RESULT)"
run_test "worktree_path_with_spaces_is_preserved" "$(cd "$wt2" && pwd -P)" "$(result_field "$out2" TARGET_WORKTREE)"

repo3="$(setup_repo missing-worktree)"
run_fails_contains "main_clone_missing_worktree_stops_before_mutation" \
  "no registered worktree matches" \
  bash -c "cd '$repo3' && '$HELPER' --item 1174 --expected-branch '$expected_branch' --main-repo-root '$repo3'"

repo4="$(setup_repo expected-path-authoritative)"
git -C "$repo4" checkout -q -b "$expected_branch"
run_fails_contains "expected_worktree_path_rejects_branch_only_main_clone_match" \
  "no registered worktree matches" \
  bash -c "cd '$repo4' && '$HELPER' --item 1174 --expected-branch '$expected_branch' --expected-worktree '$TMP_ROOT/missing-expected-wt' --main-repo-root '$repo4'"

repo5="$(setup_repo wrong-branch)"
wrong_branch="implementation-plan/11740-worktree-cwd-restore-sendmessage"
wt5="$TMP_ROOT/wt5"
make_worktree "$repo5" "$wrong_branch" "$wt5"
run_fails_contains "expected_path_wrong_branch_stops_before_mutation" \
  "different branch" \
  bash -c "cd '$repo5' && '$HELPER' --item 1174 --expected-branch '$expected_branch' --expected-worktree '$wt5' --main-repo-root '$repo5'"

repo6="$(setup_repo detached-worktree)"
wt6="$TMP_ROOT/wt6"
make_worktree "$repo6" "$expected_branch" "$wt6"
git -C "$wt6" checkout -q --detach
run_fails_contains "detached_or_incomplete_entry_stops_before_mutation" \
  "detached or missing branch metadata" \
  bash -c "cd '$repo6' && '$HELPER' --item 1174 --expected-branch '$expected_branch' --expected-worktree '$wt6' --main-repo-root '$repo6'"

repo7="$(setup_repo path-boundary)"
wt7="$TMP_ROOT/wt7"
make_worktree "$repo7" "$expected_branch" "$wt7"
mkdir -p "$wt7/subdir" "$TMP_ROOT/wt7-sibling"
out7="$(cd "$wt7/subdir" && "$HELPER" --item 1174 --expected-branch "$expected_branch" --expected-worktree "$wt7" --main-repo-root "$repo7")"
run_test "path_boundary_subdir_allowed" "continue" "$(result_field "$out7" RESULT)"
run_fails_contains "path_boundary_sibling_rejected" \
  "neither expected worktree nor main clone" \
  bash -c "cd '$TMP_ROOT/wt7-sibling' && '$HELPER' --item 1174 --expected-branch '$expected_branch' --expected-worktree '$wt7' --main-repo-root '$repo7'"

repo8="$(setup_repo branch-lookalike)"
make_worktree "$repo8" "implementation-plan/11740-worktree-cwd-restore-sendmessage" "$TMP_ROOT/wt8"
run_fails_contains "branch_lookalikes_do_not_match" \
  "no registered worktree matches" \
  bash -c "cd '$repo8' && '$HELPER' --item 1174 --expected-branch '$expected_branch' --main-repo-root '$repo8'"

mock_bin="$TMP_ROOT/bin"
mkdir -p "$mock_bin"
real_git="$(command -v git)"
cat >"$mock_bin/git" <<MOCK_GIT
#!/usr/bin/env bash
args=("\$@")
if [ "\${args[0]:-}" = "-C" ]; then
  args=("\${args[@]:2}")
fi
if [ "\${WORKTREE_PREFLIGHT_MOCK_MODE:-}" = "ambiguous" ] && [ "\${args[*]}" = "worktree list --porcelain" ]; then
  cat <<'EOF'
worktree $TMP_ROOT/mock-main
branch refs/heads/develop

worktree $TMP_ROOT/mock-one
branch refs/heads/$expected_branch

worktree $TMP_ROOT/mock-two
branch refs/heads/$expected_branch
EOF
  exit 0
fi
if [ "\${WORKTREE_PREFLIGHT_MOCK_MODE:-}" = "list-fail" ] && [ "\${args[*]}" = "worktree list --porcelain" ]; then
  exit 1
fi
exec "$real_git" "\$@"
MOCK_GIT
chmod +x "$mock_bin/git"
run_fails_contains "ambiguous_matching_worktrees_stop_before_mutation" \
  "multiple registered worktrees match" \
  bash -c "cd '$repo1' && PATH='$mock_bin':\$PATH WORKTREE_PREFLIGHT_MOCK_MODE=ambiguous '$HELPER' --item 1174 --expected-branch '$expected_branch' --main-repo-root '$repo1'"
repo10="$(setup_repo worktree-list-fail)"
run_fails_contains "worktree_list_failure_stops_before_mutation" \
  "git worktree list failed" \
  bash -c "cd '$repo10' && PATH='$mock_bin':\$PATH WORKTREE_PREFLIGHT_MOCK_MODE=list-fail '$HELPER' --item 1174 --expected-branch '$expected_branch' --main-repo-root '$repo10'"

printf '\nWorktree resume preflight tests: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
