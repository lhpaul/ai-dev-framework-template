#!/usr/bin/env bash
# test-worktree-cwd-guard.sh - coverage for worktree-cwd-guard.sh (#1572).
#
# Covers the standalone --check-cwd entry point (0 inside the worktree, 1 inside
# the main repo tree, 2 on bad usage), the nested-worktree-under-main-repo case,
# and the sourced wrapper functions (git_switch / git_checkout / git_reset /
# git_restore) refusing to run from the main repo root while the guard is armed.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/scripts/development-workflow/worktree-cwd-guard.sh"
TMP_ROOT="$(cd "$(mktemp -d)" && pwd -P)"
MAIN="$TMP_ROOT/main"
WT="$TMP_ROOT/wt"
NESTED_WT="$MAIN/.claude/worktrees/nested"
OUTSIDE="$TMP_ROOT/outside"
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

# check <name> <want_code> <cwd> <args...> - runs the guard standalone.
check() {
  local name="$1" want="$2" cwd="$3"
  shift 3
  set +e
  OUT="$(cd "$cwd" && bash "$GUARD" "$@" 2>&1)"
  CODE=$?
  set -e
  if [ "$CODE" -eq "$want" ]; then
    pass "$name"
  else
    fail "$name (exit=$CODE, want=$want)"
    printf '%s\n' "$OUT" >&2
  fi
}

has() {
  if grep -Fq -- "$2" <<<"$OUT"; then pass "$1"; else fail "$1 (missing '$2')"; printf '%s\n' "$OUT" >&2; fi
}

hasnt() {
  if grep -Fq -- "$2" <<<"$OUT"; then fail "$1 (found '$2')"; else pass "$1"; fi
}

git init -q -b develop "$MAIN"
git -C "$MAIN" config user.email test@example.invalid
git -C "$MAIN" config user.name 'Workflow Test'
printf 'seed\n' >"$MAIN/README.md"
git -C "$MAIN" add README.md
git -C "$MAIN" commit -qm 'chore: seed'
git -C "$MAIN" worktree add -q -b fix/1-wt "$WT"
mkdir -p "$MAIN/.claude/worktrees" "$OUTSIDE"
git -C "$MAIN" worktree add -q -b fix/2-nested "$NESTED_WT"
mkdir -p "$MAIN/sub"

# --- standalone --check-cwd -------------------------------------------------
check "cwd inside worktree is safe" 0 "$WT" --check-cwd "$WT" "$MAIN"
has "safe verdict message" "OK: CWD is not the main repo root."

check "cwd at main repo root is a violation" 1 "$MAIN" --check-cwd "$WT" "$MAIN"
has "violation prints GUARDRAIL warning" "GUARDRAIL WARNING"
has "violation names the isolation protocol" "protocol-91 worktree isolation violation"
has "violation suggests the worktree path" "$WT"

check "cwd in a main repo subdirectory is a violation" 1 "$MAIN/sub" --check-cwd "$WT" "$MAIN"
check "cwd in worktree subdirectory is safe" 0 "$WT" --check-cwd "$WT" "$MAIN"
check "cwd outside both trees is allowed" 0 "$OUTSIDE" --check-cwd "$WT" "$MAIN"
check "worktree nested under main repo is safe from its own cwd" 0 "$NESTED_WT" --check-cwd "$NESTED_WT" "$MAIN"
check "main root stays a violation when a nested worktree is armed" 1 "$MAIN" --check-cwd "$NESTED_WT" "$MAIN"

check "--check-cwd with no paths is a usage error" 2 "$WT" --check-cwd
has "usage error names the sub-command" "Usage:"
check "--check-cwd with one path is a usage error" 2 "$WT" --check-cwd "$WT"
check "unknown argument is a usage error" 2 "$WT" --bogus
has "unknown argument is named" "unknown argument: --bogus"
check "no argument is a usage error" 2 "$WT"
check "--help exits 0" 0 "$WT" --help
has "--help documents the standalone form" "--check-cwd"

# --- sourced API ------------------------------------------------------------
# Each case runs in a subshell so guard state never leaks between cases.
sourced() {
  local cwd="$1" body="$2"
  set +e
  OUT="$(cd "$cwd" && bash -c "source '$GUARD'; $body" 2>&1)"
  CODE=$?
  set -e
}

sourced "$MAIN" 'worktree_cwd_guard_init; echo "rc=$?"'
has "init without arguments reports usage" "Usage: worktree_cwd_guard_init"
has "init without arguments returns 2" "rc=2"

sourced "$MAIN" 'git_switch -h >/dev/null 2>&1; echo "rc=$?"'
hasnt "uninitialised guard does not warn" "GUARDRAIL WARNING"

for fn in switch checkout reset restore; do
  sourced "$MAIN" "worktree_cwd_guard_init '$WT' '$MAIN'; git_$fn --bogus-flag-never-reached; echo \"rc=\$?\""
  has "git_$fn aborts from the main repo root" "git $fn was called from inside the main repository tree"
  has "git_$fn returns 1 on violation" "rc=1"
done

# State-changing guarded call is never executed from the main root.
sourced "$MAIN" "worktree_cwd_guard_init '$WT' '$MAIN'; git_switch -c fix/should-not-exist; echo \"rc=\$?\""
if git -C "$MAIN" show-ref --verify --quiet refs/heads/fix/should-not-exist; then
  fail "guarded git_switch created no branch from main root"
else
  pass "guarded git_switch created no branch from main root"
fi
if [ "$(git -C "$MAIN" rev-parse --abbrev-ref HEAD)" = "develop" ]; then
  pass "main repo stays on develop after refused switch"
else
  fail "main repo stays on develop after refused switch"
fi

# Inside the worktree the wrapper delegates to real git.
sourced "$WT" "worktree_cwd_guard_init '$WT' '$MAIN'; git_switch -c fix/3-created-in-wt >/dev/null 2>&1; echo \"rc=\$?\""
has "git_switch succeeds inside the worktree" "rc=0"
if [ "$(git -C "$WT" rev-parse --abbrev-ref HEAD)" = "fix/3-created-in-wt" ]; then
  pass "git_switch changed the worktree branch"
else
  fail "git_switch changed the worktree branch"
fi

sourced "$WT" "worktree_cwd_guard_init '$WT' '$MAIN'; git_checkout fix/1-wt >/dev/null 2>&1; echo \"rc=\$?\""
has "git_checkout succeeds inside the worktree" "rc=0"

sourced "$MAIN" "worktree_cwd_guard_init '$WT' '$MAIN'; worktree_cwd_guard_status"
has "status shows the worktree path" "worktree_path : $WT"
has "status shows a violation from the main root" "verdict       : VIOLATION"
sourced "$WT" "worktree_cwd_guard_init '$WT' '$MAIN'; worktree_cwd_guard_status"
has "status shows SAFE inside the worktree" "verdict       : SAFE"
sourced "$WT" 'worktree_cwd_guard_status'
has "status before init shows unset paths" "<not set>"

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
