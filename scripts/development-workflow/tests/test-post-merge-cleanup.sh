#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh"
REAL_GIT="$(command -v git)"

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"

  if grep -Fq "$needle" <<<"$haystack"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '$needle'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1"
  local needle="$2"
  shift 2
  local output status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 0 ] && grep -Fq "$needle" <<<"$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure output to contain '$needle' (status $status)"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

write_gh_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

args=" $* "

case "$1 $2" in
  "pr list")
    head=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --head)
          head="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ -n "${GH_PR_LIST_FAIL:-}" ]; then
      echo "mock pr list failure" >&2
      exit 1
    fi
    if [ "$head" = "${GH_MERGED_HEAD:-}" ] && [ -n "${GH_MERGED_PR:-}" ]; then
      if [[ "$args" == *"--jq"* ]]; then
        if [[ "$args" == *"isCrossRepository"* ]]; then
          printf '{"number":%s,"isCrossRepository":%s,"headRepository":{"name":"repo","owner":{"login":"owner"}},"headRepositoryOwner":{"login":"owner"}}\n' "$GH_MERGED_PR" "${GH_IS_CROSS_REPOSITORY:-false}"
        else
          printf '%s\n' "$GH_MERGED_PR"
        fi
      else
        printf '[{"number":%s,"isCrossRepository":%s}]\n' "$GH_MERGED_PR" "${GH_IS_CROSS_REPOSITORY:-false}"
      fi
    else
      if [[ "$args" == *"--jq"* ]]; then
        printf '\n'
      else
        printf '[]\n'
      fi
    fi
    ;;
  "pr view")
    pr_number="${3:-}"
    if [[ "$args" == *"--json number,state,headRefName,isCrossRepository"* ]]; then
      if [ "$pr_number" = "${GH_MERGED_PR:-}" ] && [ "${GH_PR_STATE:-MERGED}" = "MERGED" ] && [ "${GH_PR_HEAD_REF_NAME:-${GH_MERGED_HEAD:-}}" = "${GH_MERGED_HEAD:-}" ]; then
        printf '{"number":%s,"state":"%s","headRefName":"%s","isCrossRepository":%s,"headRepository":{"name":"repo","owner":{"login":"owner"}},"headRepositoryOwner":{"login":"owner"}}\n' \
          "$GH_MERGED_PR" \
          "${GH_PR_STATE:-MERGED}" \
          "${GH_PR_HEAD_REF_NAME:-${GH_MERGED_HEAD:-}}" \
          "${GH_IS_CROSS_REPOSITORY:-false}"
      else
        printf '\n'
      fi
    elif [[ "$args" == *"--json number,state,headRefName"* ]]; then
      if [ "$pr_number" = "${GH_MERGED_PR:-}" ]; then
        printf '{"number":%s,"state":"%s","headRefName":"%s"}\n' \
          "$GH_MERGED_PR" \
          "${GH_PR_STATE:-MERGED}" \
          "${GH_PR_HEAD_REF_NAME:-${GH_MERGED_HEAD:-}}"
      else
        printf '\n'
      fi
    elif [[ "$args" == *"--json state,baseRefName,headRefName"* ]]; then
      if [ "$pr_number" = "${GH_MERGED_PR:-}" ]; then
        printf 'develop\n'
      else
        printf '\n'
      fi
    elif [[ "$args" == *"--json commits"* ]]; then
      # Emulates '[.commits[] | ...] | join("\n")' — tests control it via
      # GH_PR_COMMITS_TEXT (already-joined text, may be empty).
      printf '%s\n' "${GH_PR_COMMITS_TEXT:-}"
    elif [[ "$args" == *"--json title "* || "$args" == *'--json title'* ]]; then
      if [ -n "${GH_PR_TITLE_FETCH_FAIL:-}" ]; then
        echo "mock pr view --json title failure" >&2
        exit 1
      fi
      printf '%s\n' "${GH_PR_TITLE:-}"
    elif [[ "$args" == *"--json body,title"* ]]; then
      # Emulates the real command's jq filter
      # '(.title // "") + "\n" + (.body // "")' without invoking jq, so tests
      # can control the PR title/body via GH_PR_TITLE / GH_PR_BODY.
      printf '%s\n%s' "${GH_PR_TITLE:-}" "${GH_PR_BODY:-}"
    elif [[ "$args" == *"--jq"* ]]; then
      printf '\n'
    else
      printf '{"body":"","title":""}\n'
    fi
    ;;
  "issue view")
    if [[ "$args" == *"--jq"* ]]; then
      printf '%s\n' "${GH_ISSUE_STATE:-CLOSED}"
    else
      printf '{"state":"%s"}\n' "${GH_ISSUE_STATE:-CLOSED}"
    fi
    ;;
  "issue close")
    printf 'closed\n'
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$dir/gh"
}

write_git_failure_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "push" ] && [ "${2:-}" = "origin" ] && [ "${3:-}" = "--delete" ] && [ "${4:-}" = "${GIT_FAIL_DELETE_BRANCH:-}" ]; then
  echo "permission denied deleting ${4}" >&2
  exit 1
fi

exec "$REAL_GIT" "$@"
STUB
  chmod +x "$dir/git"
}

make_repo() {
  local name="$1"
  local branch="$2"
  local push_branch="${3:-yes}"
  local bare="$TMP_ROOT/${name}.git"
  local repo="$TMP_ROOT/$name"

  "$REAL_GIT" init --bare -q -b develop "$bare"
  "$REAL_GIT" init -q -b develop "$repo"
  "$REAL_GIT" -C "$repo" config user.email "fixture@example.com"
  "$REAL_GIT" -C "$repo" config user.name "Fixture User"
  printf 'base\n' >"$repo/README.md"
  "$REAL_GIT" -C "$repo" add README.md
  "$REAL_GIT" -C "$repo" commit -q -m "initial base"
  "$REAL_GIT" -C "$repo" remote add origin "$bare"
  "$REAL_GIT" -C "$repo" push -q -u origin develop
  "$REAL_GIT" -C "$repo" checkout -q -b "$branch"
  printf 'branch\n' >"$repo/branch.txt"
  "$REAL_GIT" -C "$repo" add branch.txt
  "$REAL_GIT" -C "$repo" commit -q -m "branch fixture"
  if [ "$push_branch" = "yes" ]; then
    "$REAL_GIT" -C "$repo" push -q -u origin "$branch"
  fi
  "$REAL_GIT" -C "$repo" checkout -q develop
  printf '%s\n' "$repo"
}

stub_bin="$TMP_ROOT/bin"
write_gh_stub "$stub_bin"

merged_branch="feature/noissue-cleanup"
merged_repo="$(make_repo merged "$merged_branch" yes)"
merged_output="$(
  GH_MERGED_HEAD="$merged_branch" \
  GH_MERGED_PR=77 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$merged_repo" --base develop --pr 77 "$merged_branch"
)"
run_contains "merged_implementation_remote_deleted" "REMOTE_DELETE_RESULT=deleted" "$merged_output"
run_contains "merged_implementation_records_pr" "REMOTE_DELETE_PR_NUMBER=77" "$merged_output"
run_test "merged_implementation_remote_ref_absent" "" "$("$REAL_GIT" -C "$merged_repo" ls-remote --heads origin "$merged_branch")"

restore_msg_branch="feature/noissue-restore-message"
restore_msg_repo="$(make_repo restore-message "$restore_msg_branch" yes)"
"$REAL_GIT" -C "$restore_msg_repo" checkout -q -b ops/current
restore_msg_output="$(
  GH_MERGED_HEAD="$restore_msg_branch" \
  GH_MERGED_PR=177 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$restore_msg_repo" --base develop --pr 177 "$restore_msg_branch"
)"
run_contains "restore_message_reports_original_branch" \
  "exit cleanup will restore 'ops/current'" \
  "$restore_msg_output"
run_test "restore_message_branch_restored" \
  "ops/current" \
  "$("$REAL_GIT" -C "$restore_msg_repo" symbolic-ref --quiet --short HEAD)"

worktree_branch="feature/123-worktree-cleanup"
worktree_repo="$(make_repo worktree-cleanup "$worktree_branch" yes)"
mkdir -p "$worktree_repo/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" "$worktree_repo/scripts/development-workflow/post-merge-cleanup.sh"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$worktree_repo/scripts/development-workflow/workflow-lib.sh"
# post-merge-cleanup.sh sources the canonical closing-keyword filter from here
# (#1644). Without it the script cannot start, and every assertion after this
# point fails on a missing file rather than on the behaviour it tests.
cp "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh" "$worktree_repo/scripts/development-workflow/closing-keyword-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py" "$worktree_repo/scripts/development-workflow/workflow-config-resolver.py"
chmod +x "$worktree_repo/scripts/development-workflow/post-merge-cleanup.sh"
worktree_pr_path="$TMP_ROOT/worktree-cleanup-pr"
"$REAL_GIT" -C "$worktree_repo" worktree add -q "$worktree_pr_path" "$worktree_branch"
mkdir -p "$worktree_pr_path/scripts/development-workflow"
cp "$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh" "$worktree_pr_path/scripts/development-workflow/post-merge-cleanup.sh"
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" "$worktree_pr_path/scripts/development-workflow/workflow-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh" "$worktree_pr_path/scripts/development-workflow/closing-keyword-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/workflow-config-resolver.py" "$worktree_pr_path/scripts/development-workflow/workflow-config-resolver.py"
chmod +x "$worktree_pr_path/scripts/development-workflow/post-merge-cleanup.sh"
worktree_output="$(
  GH_MERGED_HEAD="$worktree_branch" \
  GH_MERGED_PR=85 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$worktree_pr_path/scripts/development-workflow/post-merge-cleanup.sh" \
    --repo-root "$worktree_pr_path" \
    --base develop \
    --pr 85 \
    "$worktree_branch"
)"
run_contains \
  "worktree_cleanup_reenters_base_worktree" \
  "Re-entering cleanup through the workflow hub helper" \
  "$worktree_output"
run_contains \
  "worktree_cleanup_deletes_remote_branch" \
  "REMOTE_DELETE_RESULT=deleted" \
  "$worktree_output"
run_contains \
  "worktree_cleanup_uses_stable_tracker_root" \
  "TRACKER_REPO_ROOT=$worktree_repo" \
  "$worktree_output"
run_contains \
  "worktree_cleanup_processes_numbered_issue_after_reentry" \
  "Issue #123 is already CLOSED, skipping close." \
  "$worktree_output"
# --repo-root names the caller's own worktree, so cleanup must detach it rather
# than remove the directory the caller is running in (#1386).
run_test "worktree_cleanup_caller_worktree_survives" "yes" "$(
  if [ -d "$worktree_pr_path" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_contains "worktree_cleanup_caller_worktree_detached" "CALLER_WORKTREE_ACTION=detached" "$worktree_output"
run_test "worktree_cleanup_caller_worktree_head_detached_at_base" \
  "$("$REAL_GIT" -C "$worktree_repo" rev-parse develop)" \
  "$("$REAL_GIT" -C "$worktree_pr_path" rev-parse HEAD)"
run_test "worktree_cleanup_local_branch_removed" "no" "$(
  if "$REAL_GIT" -C "$worktree_repo" show-ref --quiet "refs/heads/$worktree_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# install_cleanup_helper <checkout>
# Copies the helper and its sourced dependencies into a fixture checkout so the
# script resolves that checkout as its own repository root.
install_cleanup_helper() {
  local checkout="$1"
  local file
  mkdir -p "$checkout/scripts/development-workflow"
  for file in post-merge-cleanup.sh workflow-lib.sh closing-keyword-lib.sh workflow-config-resolver.py; do
    cp "$REPO_ROOT/scripts/development-workflow/$file" "$checkout/scripts/development-workflow/$file"
  done
  chmod +x "$checkout/scripts/development-workflow/post-merge-cleanup.sh"
}

# #1386 regression: a worktree runner standing in its own worktree invokes the
# main clone's copy of the helper without --repo-root. The helper used to
# default to the main clone and then remove the caller's worktree with --force.
caller_cwd_branch="feature/1386-caller-cwd"
caller_cwd_repo="$(make_repo caller-cwd "$caller_cwd_branch" yes)"
install_cleanup_helper "$caller_cwd_repo"
caller_cwd_worktree="$TMP_ROOT/caller-cwd-worktree"
"$REAL_GIT" -C "$caller_cwd_repo" worktree add -q "$caller_cwd_worktree" "$caller_cwd_branch"
caller_cwd_output="$(
  cd "$caller_cwd_worktree" &&
    GH_MERGED_HEAD="$caller_cwd_branch" \
    GH_MERGED_PR=1386 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$caller_cwd_repo/scripts/development-workflow/post-merge-cleanup.sh" \
      --base develop \
      --pr 1386 \
      "$caller_cwd_branch"
)"
run_contains "caller_cwd_defaults_repo_root_to_caller_worktree" \
  "as --repo-root (no --repo-root was passed)" \
  "$caller_cwd_output"
run_test "caller_cwd_worktree_survives" "yes" "$(
  if [ -d "$caller_cwd_worktree" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_contains "caller_cwd_worktree_detached" "CALLER_WORKTREE_ACTION=detached" "$caller_cwd_output"
run_contains "caller_cwd_local_delete_reported" "LOCAL_DELETE_RESULT=deleted" "$caller_cwd_output"
run_test "caller_cwd_worktree_still_registered" "yes" "$(
  if "$REAL_GIT" -C "$caller_cwd_repo" worktree list --porcelain | grep -Fqx "worktree $(cd "$caller_cwd_worktree" && pwd -P)"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_test "caller_cwd_local_branch_removed" "no" "$(
  if "$REAL_GIT" -C "$caller_cwd_repo" show-ref --quiet "refs/heads/$caller_cwd_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_test "caller_cwd_main_clone_stays_on_base" "develop" \
  "$("$REAL_GIT" -C "$caller_cwd_repo" symbolic-ref --quiet --short HEAD)"
run_contains "caller_cwd_tracker_processing_still_runs" \
  "Issue #1386 is already CLOSED, skipping close." \
  "$caller_cwd_output"

# #1386 review finding: with no worktree holding develop, the caller's own
# worktree is the one that checks develop out to fast-forward it. It must not
# be left holding develop afterwards, or no other checkout can switch to it.
caller_nobase_branch="feature/1389-caller-no-base"
caller_nobase_repo="$(make_repo caller-no-base "$caller_nobase_branch" yes)"
install_cleanup_helper "$caller_nobase_repo"
"$REAL_GIT" -C "$caller_nobase_repo" checkout -q -b ops/current
caller_nobase_worktree="$TMP_ROOT/caller-no-base-worktree"
"$REAL_GIT" -C "$caller_nobase_repo" worktree add -q "$caller_nobase_worktree" "$caller_nobase_branch"
caller_nobase_output="$(
  cd "$caller_nobase_worktree" &&
    GH_MERGED_HEAD="$caller_nobase_branch" \
    GH_MERGED_PR=1389 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$caller_nobase_repo/scripts/development-workflow/post-merge-cleanup.sh" \
      --base develop \
      --pr 1389 \
      "$caller_nobase_branch"
)"
run_contains "caller_no_base_worktree_detached" "CALLER_WORKTREE_ACTION=detached" "$caller_nobase_output"
run_test "caller_no_base_worktree_head_detached" "detached" "$(
  if "$REAL_GIT" -C "$caller_nobase_worktree" symbolic-ref --quiet HEAD >/dev/null; then
    printf 'attached'
  else
    printf 'detached'
  fi
)"
run_test "caller_no_base_worktree_at_base_tip" \
  "$("$REAL_GIT" -C "$caller_nobase_repo" rev-parse develop)" \
  "$("$REAL_GIT" -C "$caller_nobase_worktree" rev-parse HEAD)"
run_test "caller_no_base_main_clone_restored" "ops/current" \
  "$("$REAL_GIT" -C "$caller_nobase_repo" symbolic-ref --quiet --short HEAD)"
run_test "caller_no_base_main_clone_can_check_out_base" "yes" "$(
  if "$REAL_GIT" -C "$caller_nobase_repo" checkout -q develop 2>/dev/null; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# #1386 review finding: on the base-worktree re-entry the process directory is
# the first pass's cleanup root, not the caller. A caller standing outside the
# repository must not have that directory mistaken for its own worktree.
outside_branch="feature/noissue-outside-caller"
outside_repo="$(make_repo outside-caller "$outside_branch" yes)"
install_cleanup_helper "$outside_repo"
outside_worktree="$TMP_ROOT/outside-caller-worktree"
"$REAL_GIT" -C "$outside_repo" worktree add -q "$outside_worktree" "$outside_branch"
install_cleanup_helper "$outside_worktree"
outside_cwd="$TMP_ROOT/not-a-repo"
mkdir -p "$outside_cwd"
outside_output="$(
  cd "$outside_cwd" &&
    GH_MERGED_HEAD="$outside_branch" \
    GH_MERGED_PR=1390 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$outside_worktree/scripts/development-workflow/post-merge-cleanup.sh" \
      --base develop \
      --pr 1390 \
      "$outside_branch"
)"
run_contains "outside_caller_reenters_base_worktree" \
  "Re-entering cleanup through the workflow hub helper" \
  "$outside_output"
run_test "outside_caller_not_marked_as_caller" "no" "$(
  if grep -Fq "CALLER_WORKTREE_ACTION=" <<<"$outside_output"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_test "outside_caller_non_caller_worktree_removed" "no" "$(
  if [ -d "$outside_worktree" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# Codex review on PR #1831: a dirty caller worktree with no other worktree
# holding the base must not fail on a base checkout before the tracker work.
# The base ref is fast-forwarded without being checked out in the caller.
dirty_nobase_branch="feature/1391-dirty-no-base"
dirty_nobase_repo="$(make_repo dirty-no-base "$dirty_nobase_branch" yes)"
install_cleanup_helper "$dirty_nobase_repo"
"$REAL_GIT" -C "$dirty_nobase_repo" checkout -q -b ops/current
dirty_nobase_worktree="$TMP_ROOT/dirty-no-base-worktree"
"$REAL_GIT" -C "$dirty_nobase_repo" worktree add -q "$dirty_nobase_worktree" "$dirty_nobase_branch"
dirty_nobase_pusher="$TMP_ROOT/dirty-no-base-pusher"
"$REAL_GIT" clone -q -b develop "$TMP_ROOT/dirty-no-base.git" "$dirty_nobase_pusher"
"$REAL_GIT" -C "$dirty_nobase_pusher" -c user.email=fixture@example.com -c user.name=Fixture \
  commit -q --allow-empty -m "advance develop"
"$REAL_GIT" -C "$dirty_nobase_pusher" push -q origin develop
dirty_nobase_remote_tip="$("$REAL_GIT" -C "$dirty_nobase_pusher" rev-parse HEAD)"
printf 'uncommitted edit\n' >"$dirty_nobase_worktree/branch.txt"
set +e
dirty_nobase_output="$(
  cd "$dirty_nobase_worktree" &&
    GH_MERGED_HEAD="$dirty_nobase_branch" \
    GH_MERGED_PR=1391 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$dirty_nobase_repo/scripts/development-workflow/post-merge-cleanup.sh" \
      --base develop \
      --pr 1391 \
      "$dirty_nobase_branch" 2>&1
)"
dirty_nobase_status=$?
set -e
run_test "dirty_no_base_exit_status" "0" "$dirty_nobase_status"
run_contains "dirty_no_base_local_delete_skipped" "LOCAL_DELETE_REASON=caller_worktree_detach_failed" "$dirty_nobase_output"
run_test "dirty_no_base_base_fast_forwarded" "$dirty_nobase_remote_tip" \
  "$("$REAL_GIT" -C "$dirty_nobase_repo" rev-parse develop)"
run_test "dirty_no_base_caller_stays_on_branch" "$dirty_nobase_branch" \
  "$("$REAL_GIT" -C "$dirty_nobase_worktree" symbolic-ref --quiet --short HEAD)"
run_test "dirty_no_base_edit_survives" "uncommitted edit" "$(cat "$dirty_nobase_worktree/branch.txt" 2>/dev/null || true)"
run_contains "dirty_no_base_tracker_processing_still_runs" \
  "Issue #1391 is already CLOSED, skipping close." \
  "$dirty_nobase_output"

# Step 7a review: a local base that is ahead of origin (unpushed commits) must
# not stop cleanup, just as `git pull --ff-only` does not.
ahead_branch="feature/1392-base-ahead"
ahead_repo="$(make_repo base-ahead "$ahead_branch" yes)"
install_cleanup_helper "$ahead_repo"
"$REAL_GIT" -C "$ahead_repo" commit -q --allow-empty -m "local-only base commit"
ahead_local_tip="$("$REAL_GIT" -C "$ahead_repo" rev-parse develop)"
"$REAL_GIT" -C "$ahead_repo" checkout -q -b ops/current
ahead_worktree="$TMP_ROOT/base-ahead-worktree"
"$REAL_GIT" -C "$ahead_repo" worktree add -q "$ahead_worktree" "$ahead_branch"
set +e
ahead_output="$(
  cd "$ahead_worktree" &&
    GH_MERGED_HEAD="$ahead_branch" \
    GH_MERGED_PR=1392 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$ahead_repo/scripts/development-workflow/post-merge-cleanup.sh" \
      --base develop \
      --pr 1392 \
      "$ahead_branch" 2>&1
)"
ahead_status=$?
set -e
run_test "base_ahead_exit_status" "0" "$ahead_status"
run_test "base_ahead_local_commits_kept" "$ahead_local_tip" "$("$REAL_GIT" -C "$ahead_repo" rev-parse develop)"
run_contains "base_ahead_caller_detached" "CALLER_WORKTREE_ACTION=detached" "$ahead_output"
run_contains "base_ahead_tracker_processing_runs" "Issue #1392 is already CLOSED, skipping close." "$ahead_output"

# A worktree that is NOT the caller's keeps the existing behavior: it is
# removed so the merged branch can be deleted.
other_wt_branch="feature/noissue-other-worktree"
other_wt_repo="$(make_repo other-worktree "$other_wt_branch" yes)"
other_wt_path="$TMP_ROOT/other-worktree-checkout"
"$REAL_GIT" -C "$other_wt_repo" worktree add -q "$other_wt_path" "$other_wt_branch"
other_wt_output="$(
  cd "$other_wt_repo" &&
    GH_MERGED_HEAD="$other_wt_branch" \
    GH_MERGED_PR=1387 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$other_wt_repo" --base develop --pr 1387 "$other_wt_branch"
)"
run_contains "non_caller_worktree_removed_message" "Worktree removed." "$other_wt_output"
run_test "non_caller_worktree_removed" "no" "$(
  if [ -d "$other_wt_path" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# When the caller's worktree cannot be detached (uncommitted changes that the
# base would overwrite), cleanup must leave the worktree and branch alone and
# still finish the tracker work instead of force-removing the worktree.
dirty_branch="feature/1388-dirty-caller"
dirty_repo="$(make_repo dirty-caller "$dirty_branch" yes)"
dirty_worktree="$TMP_ROOT/dirty-caller-worktree"
"$REAL_GIT" -C "$dirty_repo" worktree add -q "$dirty_worktree" "$dirty_branch"
printf 'uncommitted edit\n' >"$dirty_worktree/branch.txt"
set +e
dirty_output="$(
  cd "$dirty_worktree" &&
    GH_MERGED_HEAD="$dirty_branch" \
    GH_MERGED_PR=1388 \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$dirty_repo" --base develop --pr 1388 "$dirty_branch" 2>&1
)"
dirty_status=$?
set -e
run_test "dirty_caller_exit_status" "0" "$dirty_status"
run_contains "dirty_caller_detach_failed" "CALLER_WORKTREE_ACTION=detach_failed" "$dirty_output"
run_contains "dirty_caller_local_delete_skipped" "LOCAL_DELETE_REASON=caller_worktree_detach_failed" "$dirty_output"
run_test "dirty_caller_worktree_and_edit_survive" "uncommitted edit" "$(cat "$dirty_worktree/branch.txt" 2>/dev/null || true)"
run_test "dirty_caller_local_branch_kept" "yes" "$(
  if "$REAL_GIT" -C "$dirty_repo" show-ref --quiet "refs/heads/$dirty_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_contains "dirty_caller_summary_reports_branch_kept" \
  "local branch '$dirty_branch' was KEPT" \
  "$dirty_output"
run_contains "dirty_caller_tracker_processing_still_runs" \
  "Issue #1388 is already CLOSED, skipping close." \
  "$dirty_output"

absent_branch="feature/noissue-already-absent"
absent_repo="$(make_repo absent "$absent_branch" no)"
absent_output="$(
  GH_MERGED_HEAD="$absent_branch" \
  GH_MERGED_PR=78 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$absent_repo" --base develop --pr 78 "$absent_branch"
)"
run_contains "already_absent_remote_is_successful" "REMOTE_DELETE_RESULT=not_found" "$absent_output"
run_contains "already_absent_remote_status" "REMOTE_DELETE_STATUS=already_absent" "$absent_output"

unmerged_branch="feature/noissue-unmerged"
unmerged_repo="$(make_repo unmerged "$unmerged_branch" yes)"
run_fails_contains \
  "unmerged_implementation_skips_remote_delete" \
  "REMOTE_DELETE_REASON=pr_number_required" \
  env WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$unmerged_repo" --base develop "$unmerged_branch"
run_test "unmerged_remote_ref_still_exists" "yes" "$(
  if "$REAL_GIT" -C "$unmerged_repo" ls-remote --heads origin "$unmerged_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

unmerged_before_local_head="$("$REAL_GIT" -C "$unmerged_repo" rev-parse HEAD)"
unmerged_before_branch_sha="$("$REAL_GIT" -C "$unmerged_repo" rev-parse "refs/heads/$unmerged_branch")"
set +e
unmerged_no_mutation_output="$(
  env WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$unmerged_repo" --base develop "$unmerged_branch" 2>&1
)"
set -e
unmerged_after_local_head="$("$REAL_GIT" -C "$unmerged_repo" rev-parse HEAD)"
unmerged_after_branch_sha="$("$REAL_GIT" -C "$unmerged_repo" rev-parse "refs/heads/$unmerged_branch")"

# Regression coverage for the no-mutation property: the pr_number_required
# guard must fire before any fetch/checkout/pull/local-delete runs. Asserts
# both that the "Fetching origin..." banner (printed immediately before the
# first mutating git command) never appears, and that the local develop HEAD
# and the target branch's local ref are byte-identical before and after the
# failing invocation. A future refactor that moved the guard back below the
# mutating work would make this fail.
run_test "unmerged_guard_fires_before_fetch" "no" "$(
  if grep -Fq "Fetching origin..." <<<"$unmerged_no_mutation_output"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_test "unmerged_guard_local_develop_head_unchanged" "$unmerged_before_local_head" "$unmerged_after_local_head"
run_test "unmerged_guard_local_branch_ref_unchanged" "$unmerged_before_branch_sha" "$unmerged_after_branch_sha"

fork_branch="feature/noissue-fork-pr"
fork_repo="$(make_repo fork "$fork_branch" yes)"
fork_output="$(
  GH_MERGED_HEAD="$fork_branch" \
  GH_MERGED_PR=81 \
  GH_IS_CROSS_REPOSITORY=true \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$fork_repo" --base develop --pr 81 "$fork_branch"
)"
run_contains "fork_remote_delete_skipped" "REMOTE_DELETE_RESULT=skipped" "$fork_output"
run_contains "fork_remote_delete_reason" "REMOTE_DELETE_REASON=cross_repository_pr" "$fork_output"
run_contains "fork_remote_delete_records_pr" "REMOTE_DELETE_PR_NUMBER=81" "$fork_output"
run_test "fork_remote_ref_remains" "yes" "$(
  if "$REAL_GIT" -C "$fork_repo" ls-remote --heads origin "$fork_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

spec_branch="spec/noissue-persistent"
spec_repo="$(make_repo spec "$spec_branch" yes)"
spec_output="$(
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$spec_repo" --base develop "$spec_branch"
)"
run_contains "spec_branch_expected_persistent" "BRANCH_LIFECYCLE=expected_persistent" "$spec_output"
run_test "spec_remote_ref_remains" "yes" "$(
  if "$REAL_GIT" -C "$spec_repo" ls-remote --heads origin "$spec_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

persistent_mismatch_branch="spec/123-persistent"
persistent_mismatch_repo="$(make_repo persistent-mismatch "$persistent_mismatch_branch" yes)"
run_fails_contains \
  "persistent_branch_pr_mismatch_blocks_tracker" \
  "refusing cleanup and tracker updates" \
  env GH_MERGED_HEAD="$persistent_mismatch_branch" \
    GH_MERGED_PR=84 \
    GH_PR_HEAD_REF_NAME="spec/different-branch" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$persistent_mismatch_repo" --base develop --pr 84 "$persistent_mismatch_branch"

hub_sync_branch="feature/sync-template-v0.37.0"
hub_sync_repo="$(make_repo hub-sync "$hub_sync_branch" yes)"
printf 'mode: workflow_hub\n' >"$hub_sync_repo/.ai-dev-workflow.yaml"
hub_sync_output="$(
  GH_MERGED_HEAD="$hub_sync_branch" \
  GH_MERGED_PR=80 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$hub_sync_repo" --base develop "$hub_sync_branch"
)"
run_contains "hub_sync_branch_is_hub_owned" "ACTION_REPOSITORY_KIND=hub_owned" "$hub_sync_output"
run_contains "hub_sync_branch_skips_product_repo_requirement" "BRANCH_LIFECYCLE=unclassified" "$hub_sync_output"

hub_product_branch="feature/hub-product-cleanup"
hub_product_repo="$(make_repo hub-product "$hub_product_branch" yes)"
hub_product_worktree="$TMP_ROOT/hub-product-worktree"
"$REAL_GIT" -C "$hub_product_repo" worktree add -q "$hub_product_worktree" "$hub_product_branch"
hub_repo="$TMP_ROOT/workflow-hub"
"$REAL_GIT" init -q -b develop "$hub_repo"
"$REAL_GIT" -C "$hub_repo" config user.email "fixture@example.com"
"$REAL_GIT" -C "$hub_repo" config user.name "Fixture User"
cat >"$hub_repo/.ai-dev-workflow.yaml" <<HUB_CONFIG
schema_version: 2
mode: workflow_hub
workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/repo
      default_branch: develop
      role: mobile
      scope: fixture app
      tracker:
        component: mobile
HUB_CONFIG
cat >"$hub_repo/.ai-dev-workflow.local.yaml" <<HUB_LOCAL_CONFIG
product_repos:
  - name: mobile-app
    local_path: "$hub_product_worktree"
HUB_LOCAL_CONFIG
"$REAL_GIT" -C "$hub_repo" add .ai-dev-workflow.yaml .ai-dev-workflow.local.yaml
"$REAL_GIT" -C "$hub_repo" commit -q -m "hub config"
hub_product_output="$(
  GH_MERGED_HEAD="$hub_product_branch" \
  GH_MERGED_PR=85 \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$hub_repo" --repo mobile-app --base develop --pr 85 "$hub_product_branch"
)"
run_contains \
  "workflow_hub_reentry_uses_hub_helper" \
  "Re-entering cleanup through the workflow hub helper" \
  "$hub_product_output"
run_contains "workflow_hub_reentry_preserves_tracker_root" "TRACKER_REPO_ROOT=$hub_repo" "$hub_product_output"
run_contains "workflow_hub_reentry_uses_product_base_worktree" "CLEANUP_REPO_ROOT=$hub_product_repo" "$hub_product_output"
run_test "workflow_hub_reentry_removes_product_branch" "no" "$(
  if "$REAL_GIT" -C "$hub_product_repo" show-ref --quiet "refs/heads/$hub_product_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

fail_branch="feature/noissue-delete-fails"
fail_repo="$(make_repo delete-fails "$fail_branch" yes)"
fail_bin="$TMP_ROOT/fail-bin"
write_gh_stub "$fail_bin"
write_git_failure_stub "$fail_bin"
run_fails_contains \
  "exact_pr_head_mismatch_blocks_delete" \
  "REMOTE_DELETE_REASON=pr_not_merged_or_branch_mismatch" \
  env GH_MERGED_HEAD="$merged_branch" \
    GH_MERGED_PR=82 \
    GH_PR_HEAD_REF_NAME="feature/different-branch" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$(make_repo exact-mismatch "$merged_branch" yes)" --base develop --pr 82 "$merged_branch"

quoted_branch='feature/x"),true#'
quoted_repo="$(make_repo quoted "$quoted_branch" yes)"
run_fails_contains \
  "quoted_branch_does_not_bypass_exact_pr_filter" \
  "REMOTE_DELETE_REASON=pr_not_merged_or_branch_mismatch" \
  env GH_MERGED_HEAD="$quoted_branch" \
    GH_MERGED_PR=83 \
    GH_PR_HEAD_REF_NAME="feature/different-branch" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$quoted_repo" --base develop --pr 83 "$quoted_branch"
run_test "quoted_branch_remote_ref_remains" "yes" "$(
  if "$REAL_GIT" -C "$quoted_repo" ls-remote --heads origin "$quoted_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

run_fails_contains \
  "remote_delete_failure_blocks_cleanup" \
  "REMOTE_DELETE_RESULT=failed" \
  env GH_MERGED_HEAD="$fail_branch" \
    GH_MERGED_PR=79 \
    GIT_FAIL_DELETE_BRANCH="$fail_branch" \
    REAL_GIT="$REAL_GIT" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$fail_bin:$PATH" \
    "$HELPER" --repo-root "$fail_repo" --base develop --pr 79 "$fail_branch"
run_test "failed_delete_local_branch_remains" "yes" "$(
  if "$REAL_GIT" -C "$fail_repo" show-ref --quiet "refs/heads/$fail_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# --- Team-prefixed issue identifier vs. PR-body-derived issue (issue #1511) ---
#
# Team-prefixed branch slugs (2-6 letters, dash, digits) are ambiguous with
# ordinary descriptive slug fragments that happen to contain a number
# (retro-517, http-500, sha-256). These tests cover the three scenarios from
# the fix: a false-positive slug overridden by the PR body, a team-prefixed
# slug whose PR body confirms the same issue, and a team-prefixed slug with
# no PR-body closing reference falling back to the slug-derived issue.

# #1391: a numeric branch names one issue; the PR may resolve more. Closing
# refs from body/commits are processed as extras, and bare title refs warn.
multi_branch="fix/1520-retro-followups"
multi_repo="$(make_repo multi-close "$multi_branch" yes)"
multi_output="$(
  GH_MERGED_HEAD="$multi_branch" \
  GH_MERGED_PR=1521 \
  GH_PR_TITLE="fix(#1520): retro followups" \
  GH_PR_BODY="Also resolves the report tracked separately. Closes #1517" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$multi_repo" --base develop --pr 1521 "$multi_branch"
)"
run_contains "branch_issue_still_closed" "Closing issue #1520..." "$multi_output"
run_contains "body_extra_ref_processed" "Processing issue #1517 from PR #1521" "$multi_output"
run_contains "extras_announced" "PR #1521 also closes: 1517" "$multi_output"

commitmsg_branch="fix/1600-commit-ref"
commitmsg_repo="$(make_repo commitmsg-close "$commitmsg_branch" yes)"
commitmsg_output="$(
  GH_MERGED_HEAD="$commitmsg_branch" \
  GH_MERGED_PR=1601 \
  GH_PR_TITLE="fix(#1600): thing" \
  GH_PR_BODY="No closing keyword in the body." \
  GH_PR_COMMITS_TEXT=$'fix: the thing\nCloses #1602' \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$commitmsg_repo" --base develop --pr 1601 "$commitmsg_branch"
)"
run_contains "commit_message_ref_processed" "Processing issue #1602 from PR #1601" "$commitmsg_output"

# #1391: title/body and commit text must be fence-stripped SEPARATELY. An
# unclosed fence in the PR body extends "to end of input" by design (see the
# unclosed_fence_extends_to_end_of_input test above); if body and commit text
# were combined before stripping, that same unclosed-fence rule would treat
# every commit message as inside the fence too and silently drop a live
# commit-message closing reference as collateral damage.
unclosed_body_fence_branch="fix/1610-unclosed-body-fence"
unclosed_body_fence_repo="$(make_repo unclosed-body-fence "$unclosed_body_fence_branch" yes)"
unclosed_body_fence_output="$(
  GH_MERGED_HEAD="$unclosed_body_fence_branch" \
  GH_MERGED_PR=1611 \
  GH_PR_TITLE="fix(#1610): thing" \
  GH_PR_BODY=$'Accidentally unclosed fence below.\n\n```\nsome example text' \
  GH_PR_COMMITS_TEXT="fix: the thing
Closes #1612" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$unclosed_body_fence_repo" --base develop --pr 1611 "$unclosed_body_fence_branch"
)"
run_contains "unclosed_body_fence_does_not_swallow_commit_ref" \
  "Processing issue #1612 from PR #1611" \
  "$unclosed_body_fence_output"

bare_branch="fix/2053-first-of-two"
bare_repo="$(make_repo bare-title "$bare_branch" yes)"
bare_output="$(
  GH_MERGED_HEAD="$bare_branch" \
  GH_MERGED_PR=2060 \
  GH_PR_TITLE="fix(#2053,#2055): shared component edits" \
  GH_PR_BODY="No closing keywords." \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$bare_repo" --base develop --pr 2060 "$bare_branch" 2>&1
)"
run_contains "bare_title_ref_warns_loudly" "title references issue(s) #2055 without a closing keyword" "$bare_output"
run_test "bare_title_ref_branch_issue_not_warned" "no" \
  "$(if grep -Fq "#2053 without" <<<"$bare_output"; then printf yes; else printf no; fi)"

# #1391: the branch-derived issue may already be closed (e.g. a re-run, or an
# issue closed by hand before cleanup ran) — extras from the PR body/commits
# must still be processed rather than being skipped along with the branch
# issue's own (redundant) close step.
already_closed_branch="fix/1800-already-closed-with-extra"
already_closed_repo="$(make_repo already-closed-extra "$already_closed_branch" yes)"
already_closed_output="$(
  GH_MERGED_HEAD="$already_closed_branch" \
  GH_MERGED_PR=1801 \
  GH_PR_TITLE="fix(#1800): thing" \
  GH_PR_BODY="Also closes #1802" \
  GH_ISSUE_STATE=CLOSED \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$already_closed_repo" --base develop --pr 1801 "$already_closed_branch"
)"
run_contains "already_closed_branch_issue_skips_close" "Issue #1800 is already CLOSED, skipping close." "$already_closed_output"
run_contains "already_closed_branch_extra_still_processed" "Processing issue #1802 from PR #1801" "$already_closed_output"

# #1391: a transient failure fetching the PR title for the bare-ref check
# must not go completely silent — it is the one helper whose purpose is
# avoiding exactly that kind of silent gap.
title_fetch_fail_branch="fix/1900-title-fetch-fails"
title_fetch_fail_repo="$(make_repo title-fetch-fail "$title_fetch_fail_branch" yes)"
title_fetch_fail_output="$(
  GH_MERGED_HEAD="$title_fetch_fail_branch" \
  GH_MERGED_PR=1901 \
  GH_PR_TITLE="fix(#1900): thing" \
  GH_PR_BODY="No closing keywords." \
  GH_ISSUE_STATE=OPEN \
  GH_PR_TITLE_FETCH_FAIL=1 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$title_fetch_fail_repo" --base develop --pr 1901 "$title_fetch_fail_branch" 2>&1
)"
run_contains "title_fetch_failure_warns_instead_of_silent" \
  "could not fetch PR #1901 title to check for unprocessed bare issue references" \
  "$title_fetch_fail_output"

false_positive_branch="fix/retro-517-doc-gaps"
false_positive_repo="$(make_repo false-positive "$false_positive_branch" yes)"
false_positive_output="$(
  GH_MERGED_HEAD="$false_positive_branch" \
  GH_MERGED_PR=632 \
  GH_PR_BODY="Fixes #601" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$false_positive_repo" --base develop --pr 632 "$false_positive_branch"
)"
run_contains \
  "false_positive_slug_uses_pr_body_issue" \
  "Closing issue #601..." \
  "$false_positive_output"
run_test \
  "false_positive_slug_does_not_close_slug_derived_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #517" <<<"$false_positive_output" || grep -Fq "Processing issue #517" <<<"$false_positive_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
run_contains \
  "false_positive_slug_notes_ambiguity" \
  "Team-prefixed identifier 'retro-517'" \
  "$false_positive_output"

matching_override_branch="fix/lh-97-fix-thing"
matching_override_repo="$(make_repo matching-override "$matching_override_branch" yes)"
matching_override_output="$(
  GH_MERGED_HEAD="$matching_override_branch" \
  GH_MERGED_PR=645 \
  GH_PR_BODY="Closes #97" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$matching_override_repo" --base develop --pr 645 "$matching_override_branch"
)"
run_contains \
  "pr_body_derived_happy_path_closes_issue" \
  "Closing issue #97..." \
  "$matching_override_output"
run_contains \
  "pr_body_derived_happy_path_used_override_path" \
  "using closing keyword refs from PR #645" \
  "$matching_override_output"

no_reference_branch="fix/lh-97-real-issue"
no_reference_repo="$(make_repo no-reference "$no_reference_branch" yes)"
no_reference_output="$(
  GH_MERGED_HEAD="$no_reference_branch" \
  GH_MERGED_PR=650 \
  GH_PR_BODY="No closing keyword here." \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$no_reference_repo" --base develop --pr 650 "$no_reference_branch"
)"
run_contains \
  "no_closing_reference_falls_back_to_slug_issue" \
  "Closing issue #97..." \
  "$no_reference_output"
run_test \
  "no_closing_reference_does_not_use_override_path" \
  "no" \
  "$(
    if grep -Fq "using closing keyword refs from PR" <<<"$no_reference_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# Punctuation-delimited closing keyword (e.g. "(Fixes #601)") must still be
# recognized — the word-boundary regex requires a non-alnum/underscore
# character immediately before the keyword, not specifically whitespace, so
# a parenthesis directly abutting the keyword still matches.
punctuation_branch="fix/retro-518-doc-gaps"
punctuation_repo="$(make_repo punctuation "$punctuation_branch" yes)"
punctuation_output="$(
  GH_MERGED_HEAD="$punctuation_branch" \
  GH_MERGED_PR=651 \
  GH_PR_BODY="Cleans up doc gaps. (Fixes #602)" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$punctuation_repo" --base develop --pr 651 "$punctuation_branch"
)"
run_contains \
  "punctuation_delimited_keyword_uses_pr_body_issue" \
  "Closing issue #602..." \
  "$punctuation_output"
run_test \
  "punctuation_delimited_keyword_does_not_close_slug_derived_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #518" <<<"$punctuation_output" || grep -Fq "Processing issue #518" <<<"$punctuation_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# An example closing keyword inside a fenced code block in the PR body must
# not be treated as a live reference — only the real footer reference should
# be used.
fenced_branch="fix/retro-519-doc-gaps"
fenced_repo="$(make_repo fenced "$fenced_branch" yes)"
fenced_pr_body='Cleans up doc gaps.

```
Example commit message: Closes #999
```

Closes #603'
fenced_output="$(
  GH_MERGED_HEAD="$fenced_branch" \
  GH_MERGED_PR=652 \
  GH_PR_BODY="$fenced_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$fenced_repo" --base develop --pr 652 "$fenced_branch"
)"
run_contains \
  "fenced_example_excludes_code_block_reference_closes_real_issue" \
  "Closing issue #603..." \
  "$fenced_output"
run_test \
  "fenced_example_does_not_close_code_block_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #999" <<<"$fenced_output" || grep -Fq "Processing issue #999" <<<"$fenced_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# Inline-code examples quoted in prose must not be treated as live references.
inline_code_branch="fix/retro-525-doc-gaps"
inline_code_repo="$(make_repo inline-code "$inline_code_branch" yes)"
inline_code_pr_body='Cleans up doc gaps.

The old parser matched `Closes #995` in prose.

Closes #610'
inline_code_output="$(
  GH_MERGED_HEAD="$inline_code_branch" \
  GH_MERGED_PR=658 \
  GH_PR_BODY="$inline_code_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$inline_code_repo" --base develop --pr 658 "$inline_code_branch"
)"
run_contains \
  "inline_code_example_closes_real_issue" \
  "Closing issue #610..." \
  "$inline_code_output"
run_test \
  "inline_code_example_does_not_close_quoted_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #995" <<<"$inline_code_output" || grep -Fq "Processing issue #995" <<<"$inline_code_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# Multi-line inline code spans must stay excluded until their closing delimiter.
multiline_inline_branch="fix/retro-527-doc-gaps"
multiline_inline_repo="$(make_repo multiline-inline "$multiline_inline_branch" yes)"
multiline_inline_pr_body='Cleans up doc gaps.

This quoted inline example starts here: `Closes #992
and keeps quoting Closes #991`

Closes #612'
multiline_inline_output="$(
  GH_MERGED_HEAD="$multiline_inline_branch" \
  GH_MERGED_PR=660 \
  GH_PR_BODY="$multiline_inline_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$multiline_inline_repo" --base develop --pr 660 "$multiline_inline_branch"
)"
run_contains \
  "multiline_inline_code_example_closes_real_issue" \
  "Closing issue #612..." \
  "$multiline_inline_output"
run_test \
  "multiline_inline_code_example_does_not_close_quoted_issues" \
  "no" \
  "$(
    if grep -Fq "Closing issue #992" <<<"$multiline_inline_output" \
      || grep -Fq "Processing issue #992" <<<"$multiline_inline_output" \
      || grep -Fq "Closing issue #991" <<<"$multiline_inline_output" \
      || grep -Fq "Processing issue #991" <<<"$multiline_inline_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# An unmatched backtick in an earlier paragraph must not swallow a later live
# closing reference after a blank-line paragraph break.
unmatched_inline_branch="fix/retro-528-doc-gaps"
unmatched_inline_repo="$(make_repo unmatched-inline "$unmatched_inline_branch" yes)"
unmatched_inline_pr_body='Cleans up doc gaps with an unmatched `example marker.

Closes #613'
unmatched_inline_output="$(
  GH_MERGED_HEAD="$unmatched_inline_branch" \
  GH_MERGED_PR=661 \
  GH_PR_BODY="$unmatched_inline_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$unmatched_inline_repo" --base develop --pr 661 "$unmatched_inline_branch"
)"
run_contains \
  "unmatched_inline_previous_paragraph_closes_real_issue" \
  "Closing issue #613..." \
  "$unmatched_inline_output"

# Blockquoted closing-keyword examples must not be treated as live references.
blockquote_branch="fix/retro-526-doc-gaps"
blockquote_repo="$(make_repo blockquote "$blockquote_branch" yes)"
blockquote_pr_body='Cleans up doc gaps.

> Reviewer said: Closes #993

Closes #611'
blockquote_output="$(
  GH_MERGED_HEAD="$blockquote_branch" \
  GH_MERGED_PR=659 \
  GH_PR_BODY="$blockquote_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$blockquote_repo" --base develop --pr 659 "$blockquote_branch"
)"
run_contains \
  "blockquote_example_closes_real_issue" \
  "Closing issue #611..." \
  "$blockquote_output"
run_test \
  "blockquote_example_does_not_close_quoted_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #993" <<<"$blockquote_output" || grep -Fq "Processing issue #993" <<<"$blockquote_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# Tilde-fenced (~~~) code blocks must be excluded the same way as
# backtick-fenced blocks.
tilde_fenced_branch="fix/retro-520-doc-gaps"
tilde_fenced_repo="$(make_repo tilde-fenced "$tilde_fenced_branch" yes)"
tilde_fenced_pr_body='Cleans up doc gaps.

~~~
Example commit message: Closes #998
~~~

Closes #604'
tilde_fenced_output="$(
  GH_MERGED_HEAD="$tilde_fenced_branch" \
  GH_MERGED_PR=653 \
  GH_PR_BODY="$tilde_fenced_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$tilde_fenced_repo" --base develop --pr 653 "$tilde_fenced_branch"
)"
run_contains \
  "tilde_fenced_example_closes_real_issue" \
  "Closing issue #604..." \
  "$tilde_fenced_output"
run_test \
  "tilde_fenced_example_does_not_close_code_block_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #998" <<<"$tilde_fenced_output" || grep -Fq "Processing issue #998" <<<"$tilde_fenced_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# An unclosed opening fence must extend to end of input, so a real closing
# reference placed after an accidentally-unclosed fence is NOT treated as
# live (rather than leaking past the unclosed fence and being extracted).
unclosed_fence_branch="fix/retro-521-doc-gaps"
unclosed_fence_repo="$(make_repo unclosed-fence "$unclosed_fence_branch" yes)"
unclosed_fence_pr_body='Cleans up doc gaps.

~~~
Example commit message: Closes #997
Closes #605'
unclosed_fence_output="$(
  GH_MERGED_HEAD="$unclosed_fence_branch" \
  GH_MERGED_PR=654 \
  GH_PR_BODY="$unclosed_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$unclosed_fence_repo" --base develop --pr 654 "$unclosed_fence_branch"
)"
run_test \
  "unclosed_fence_extends_to_end_of_input" \
  "no" \
  "$(
    if grep -Fq "Closing issue #997" <<<"$unclosed_fence_output" || grep -Fq "Processing issue #997" <<<"$unclosed_fence_output" || grep -Fq "Closing issue #605" <<<"$unclosed_fence_output" || grep -Fq "Processing issue #605" <<<"$unclosed_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
run_contains \
  "unclosed_fence_falls_back_to_slug_issue" \
  "Closing issue #521..." \
  "$unclosed_fence_output"

# A closing fence marker shorter than the opening one must NOT be treated as
# a closer (GFM requires the closer to be at least as long as the opener).
# Using tildes here (not backticks) keeps this test out of reach of
# workflow-shell-snippet-lint.py's backtick-only WS001 fence scan.
mismatched_fence_branch="fix/retro-522-doc-gaps"
mismatched_fence_repo="$(make_repo mismatched-fence "$mismatched_fence_branch" yes)"
mismatched_fence_pr_body='Cleans up doc gaps.

~~~~
Example commit message: Closes #996
~~~
still fenced content after a too-short closer
~~~~

Closes #606'
mismatched_fence_output="$(
  GH_MERGED_HEAD="$mismatched_fence_branch" \
  GH_MERGED_PR=655 \
  GH_PR_BODY="$mismatched_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$mismatched_fence_repo" --base develop --pr 655 "$mismatched_fence_branch"
)"
run_contains \
  "mismatched_fence_length_closes_real_issue" \
  "Closing issue #606..." \
  "$mismatched_fence_output"
run_test \
  "mismatched_fence_length_does_not_close_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #996" <<<"$mismatched_fence_output" || grep -Fq "Processing issue #996" <<<"$mismatched_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# A closing fence line with trailing content after the fence marker (not
# pure whitespace) must NOT be treated as a closer either (GFM requires the
# closing fence to be followed only by whitespace).
trailing_content_fence_branch="fix/retro-523-doc-gaps"
trailing_content_fence_repo="$(make_repo trailing-content-fence "$trailing_content_fence_branch" yes)"
trailing_content_fence_pr_body='Cleans up doc gaps.

~~~
Example commit message: Closes #994
~~~ not a real closer
still fenced
~~~

Closes #607'
trailing_content_fence_output="$(
  GH_MERGED_HEAD="$trailing_content_fence_branch" \
  GH_MERGED_PR=656 \
  GH_PR_BODY="$trailing_content_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$trailing_content_fence_repo" --base develop --pr 656 "$trailing_content_fence_branch"
)"
run_contains \
  "trailing_content_fence_closes_real_issue" \
  "Closing issue #607..." \
  "$trailing_content_fence_output"
run_test \
  "trailing_content_fence_does_not_close_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #994" <<<"$trailing_content_fence_output" || grep -Fq "Processing issue #994" <<<"$trailing_content_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# A genuine sort failure while extracting closing-keyword issue numbers must
# propagate as a fatal error, not be silently swallowed and fall through to
# the ambiguous slug-derived issue.
sort_failure_bin="$TMP_ROOT/sort-failure-bin"
write_gh_stub "$sort_failure_bin"
cat >"$sort_failure_bin/sort" <<'STUB'
#!/usr/bin/env bash
echo "mock sort failure" >&2
exit 2
STUB
chmod +x "$sort_failure_bin/sort"

sort_failure_branch="fix/retro-524-doc-gaps"
sort_failure_repo="$(make_repo sort-failure "$sort_failure_branch" yes)"
set +e
sort_failure_output="$(
  env GH_MERGED_HEAD="$sort_failure_branch" \
    GH_MERGED_PR=657 \
    GH_PR_BODY="Closes #608" \
    GH_ISSUE_STATE=OPEN \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$sort_failure_bin:$PATH" \
    "$HELPER" --repo-root "$sort_failure_repo" --base develop --pr 657 "$sort_failure_branch" 2>&1
)"
sort_failure_status=$?
set -e
run_test \
  "extraction_sort_failure_propagates_as_fatal" \
  "nonzero" \
  "$([ "$sort_failure_status" -ne 0 ] && printf 'nonzero' || printf 'zero')"
run_contains \
  "extraction_sort_failure_error_message" \
  "ERROR: failed to sort extracted closing-keyword issue numbers" \
  "$sort_failure_output"
run_test \
  "extraction_sort_failure_does_not_fall_back_to_slug_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #524" <<<"$sort_failure_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# A 4-space-indented fence marker is GFM indented code, not a real fence, and
# must not be treated as one — otherwise it can spuriously open an unclosed
# fence that swallows a later, real closing reference.
indented_fence_branch="fix/retro-525-doc-gaps"
indented_fence_repo="$(make_repo indented-fence "$indented_fence_branch" yes)"
indented_fence_pr_body='Cleans up doc gaps.

Example indented code (not a fence):
    ~~~
    some literal example content

Closes #609'
indented_fence_output="$(
  GH_MERGED_HEAD="$indented_fence_branch" \
  GH_MERGED_PR=658 \
  GH_PR_BODY="$indented_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$indented_fence_repo" --base develop --pr 658 "$indented_fence_branch"
)"
run_contains \
  "indented_fence_marker_is_not_a_fence_closes_real_issue" \
  "Closing issue #609..." \
  "$indented_fence_output"
run_test \
  "indented_fence_marker_does_not_fall_back_to_slug_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #525" <<<"$indented_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
