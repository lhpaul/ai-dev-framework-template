#!/usr/bin/env bash
# test-check-workflow-branch.sh - coverage for check-workflow-branch.sh (#1572).
#
# The script resolves its repository from its own location, so each case runs a
# copy of it inside a disposable fixture repository. Covers the usage error
# (exit 2), the local / remote / worktree hits (exit 0) and the missing-branch
# miss (exit 1).

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/development-workflow/check-workflow-branch.sh"
TMP_ROOT="$(mktemp -d)"
FIXTURE="$TMP_ROOT/fixture"
ORIGIN="$TMP_ROOT/origin.git"
PASS_COUNT=0
FAIL_COUNT=0

trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# run_check <branch...> - sets OUT (stdout+stderr) and CODE.
run_check() {
  set +e
  OUT="$(bash "$FIXTURE/scripts/development-workflow/check-workflow-branch.sh" "$@" 2>&1)"
  CODE=$?
  set -e
}

expect() {
  local name="$1" want_code="$2" want_line="$3"
  if [ "$CODE" -eq "$want_code" ] && grep -Fq -- "$want_line" <<<"$OUT"; then
    pass "$name"
  else
    fail "$name (exit=$CODE, want exit=$want_code, want line '$want_line')"
    printf '%s\n' "$OUT" >&2
  fi
}

git init -q --bare "$ORIGIN"
git init -q -b develop "$FIXTURE"
git -C "$FIXTURE" config user.email test@example.invalid
git -C "$FIXTURE" config user.name 'Workflow Test'
mkdir -p "$FIXTURE/scripts/development-workflow"
cp "$SCRIPT_UNDER_TEST" "$FIXTURE/scripts/development-workflow/check-workflow-branch.sh"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit -qm 'chore: seed'
git -C "$FIXTURE" remote add origin "$ORIGIN"
git -C "$FIXTURE" push -q origin develop

git -C "$FIXTURE" branch fix/1-local-only
git -C "$FIXTURE" branch fix/2-remote-only
git -C "$FIXTURE" push -q origin fix/2-remote-only
git -C "$FIXTURE" branch -q -D fix/2-remote-only
git -C "$FIXTURE" fetch -q origin
git -C "$FIXTURE" worktree add -q -b fix/3-in-worktree "$TMP_ROOT/wt3"

run_check
expect "no argument is a usage error" 2 "Usage:"

run_check fix/1-local-only extra
expect "two arguments are a usage error" 2 "Usage:"

run_check fix/1-local-only
expect "local branch is reported" 0 "local: fix/1-local-only"
if grep -q '^remote:\|^worktree:' <<<"$OUT"; then
  fail "local-only branch reports no remote or worktree match"
else
  pass "local-only branch reports no remote or worktree match"
fi

run_check fix/2-remote-only
expect "remote-only branch is reported" 0 "remote: origin/fix/2-remote-only"
if grep -q '^local:' <<<"$OUT"; then
  fail "remote-only branch has no local match"
else
  pass "remote-only branch has no local match"
fi

run_check fix/3-in-worktree
expect "worktree branch is reported" 0 "worktree: "
case "$OUT" in
  *"[fix/3-in-worktree]"*"local: fix/3-in-worktree"* | *"local: fix/3-in-worktree"*"[fix/3-in-worktree]"*)
    pass "worktree branch also reports its local match"
    ;;
  *)
    fail "worktree branch also reports its local match"
    printf '%s\n' "$OUT" >&2
    ;;
esac

run_check fix/9-does-not-exist
expect "unknown branch exits 1 with missing line" 1 "missing: fix/9-does-not-exist"

run_check fix/1-local
expect "partial name does not match a longer branch" 1 "missing: fix/1-local"

run_check fix/2-remote
expect "partial name does not match a longer remote branch" 1 "missing: fix/2-remote"

run_check fix/3-in
expect "partial name does not match a longer worktree branch" 1 "missing: fix/3-in"

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
