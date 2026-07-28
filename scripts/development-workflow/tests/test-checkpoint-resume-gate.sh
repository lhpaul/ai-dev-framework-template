#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
GATE="$REPO_ROOT/scripts/development-workflow/checkpoint-resume-gate.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

git init -q "$TMP_ROOT/repo"
git -C "$TMP_ROOT/repo" config user.email test@example.invalid
git -C "$TMP_ROOT/repo" config user.name 'Workflow Test'
printf 'seed\n' >"$TMP_ROOT/repo/README.md"
git -C "$TMP_ROOT/repo" add README.md
git -C "$TMP_ROOT/repo" commit -qm 'chore: seed'
git -C "$TMP_ROOT/repo" branch -m develop
git -C "$TMP_ROOT/repo" worktree add -qb feature/1285-gate "$TMP_ROOT/worktree" develop

out="$(cd "$TMP_ROOT/worktree" && "$GATE" --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state satisfied)"
grep -qx 'RESULT=continue' <<<"$out"

set +e
out="$(cd "$TMP_ROOT/repo" && "$GATE" --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state satisfied)"
code=$?
set -e
[ "$code" -ne 0 ]
grep -qx 'RESULT=stop' <<<"$out"
grep -qx 'STOP_CONDITION=unclear_requirements' <<<"$out"

set +e
out="$(cd "$TMP_ROOT/worktree" && "$GATE" --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state pending)"
code=$?
set -e
[ "$code" -ne 0 ]
grep -qx 'RESULT=checkpoint_pending' <<<"$out"
grep -qx 'STOP_CONDITION=checkpoint_pending' <<<"$out"
printf 'PASS: checkpoint resume gate\n'
