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
        printf '%s\n' "$GH_MERGED_PR"
      else
        printf '[{"number":%s}]\n' "$GH_MERGED_PR"
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
    if [[ "$args" == *"--jq"* ]]; then
      printf '\n'
    else
      printf '{"body":"","title":""}\n'
    fi
    ;;
  "issue view")
    if [[ "$args" == *"--jq"* ]]; then
      printf 'CLOSED\n'
    else
      printf '{"state":"CLOSED"}\n'
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
  "$HELPER" --repo-root "$merged_repo" --base develop "$merged_branch"
)"
run_contains "merged_implementation_remote_deleted" "REMOTE_DELETE_RESULT=deleted" "$merged_output"
run_contains "merged_implementation_records_pr" "REMOTE_DELETE_PR_NUMBER=77" "$merged_output"
run_test "merged_implementation_remote_ref_absent" "" "$("$REAL_GIT" -C "$merged_repo" ls-remote --heads origin "$merged_branch")"

absent_branch="feature/noissue-already-absent"
absent_repo="$(make_repo absent "$absent_branch" no)"
absent_output="$(
  GH_MERGED_HEAD="$absent_branch" \
  GH_MERGED_PR=78 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$absent_repo" --base develop "$absent_branch"
)"
run_contains "already_absent_remote_is_successful" "REMOTE_DELETE_RESULT=not_found" "$absent_output"
run_contains "already_absent_remote_status" "REMOTE_DELETE_STATUS=already_absent" "$absent_output"

unmerged_branch="feature/noissue-unmerged"
unmerged_repo="$(make_repo unmerged "$unmerged_branch" yes)"
run_fails_contains \
  "unmerged_implementation_skips_remote_delete" \
  "REMOTE_DELETE_REASON=pr_not_merged" \
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

fail_branch="feature/noissue-delete-fails"
fail_repo="$(make_repo delete-fails "$fail_branch" yes)"
fail_bin="$TMP_ROOT/fail-bin"
write_gh_stub "$fail_bin"
write_git_failure_stub "$fail_bin"
run_fails_contains \
  "remote_delete_failure_blocks_cleanup" \
  "REMOTE_DELETE_RESULT=failed" \
  env GH_MERGED_HEAD="$fail_branch" \
    GH_MERGED_PR=79 \
    GIT_FAIL_DELETE_BRANCH="$fail_branch" \
    REAL_GIT="$REAL_GIT" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$fail_bin:$PATH" \
    "$HELPER" --repo-root "$fail_repo" --base develop "$fail_branch"
run_test "failed_delete_local_branch_remains" "yes" "$(
  if "$REAL_GIT" -C "$fail_repo" show-ref --quiet "refs/heads/$fail_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
