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
grep -qx 'ISOLATION_RESULT=pass' <<<"$out"
grep -qx 'CHECKPOINT_STATE=satisfied' <<<"$out"

before_head="$(git -C "$TMP_ROOT/repo" rev-parse HEAD)"
before_branch="$(git -C "$TMP_ROOT/repo" rev-parse --abbrev-ref HEAD)"
before_status="$(git -C "$TMP_ROOT/repo" status --porcelain)"
set +e
out="$(cd "$TMP_ROOT/repo" && "$GATE" --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state satisfied)"
code=$?
set -e
[ "$code" -ne 0 ]
grep -qx 'RESULT=stop' <<<"$out"
grep -qx 'ISOLATION_RESULT=stop' <<<"$out"
grep -qx 'STOP_CONDITION=unclear_requirements' <<<"$out"
[ "$before_head" = "$(git -C "$TMP_ROOT/repo" rev-parse HEAD)" ]
[ "$before_branch" = "$(git -C "$TMP_ROOT/repo" rev-parse --abbrev-ref HEAD)" ]
[ "$before_status" = "$(git -C "$TMP_ROOT/repo" status --porcelain)" ]

set +e
out="$(cd "$TMP_ROOT/worktree" && "$GATE" --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state pending)"
code=$?
set -e
[ "$code" -ne 0 ]
grep -qx 'RESULT=checkpoint_pending' <<<"$out"
grep -qx 'ISOLATION_RESULT=pass' <<<"$out"
grep -qx 'STOP_CONDITION=checkpoint_pending' <<<"$out"

out="$(cd "$TMP_ROOT/worktree" && "$GATE" --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state waived --json)"
grep -qx 'RESULT=continue' <<<"$out"
test "$(printf '%s\n' "$out" | tail -1 | python3 -c 'import json,sys; print(json.load(sys.stdin)["checkpointState"])')" = "waived"

set +e
out="$("$GATE" --item 1285 --item 1285 --expected-worktree "$TMP_ROOT/worktree" --expected-branch feature/1285-gate --main-repo-root "$TMP_ROOT/repo" --checkpoint-state satisfied 2>&1)"
code=$?
set -e
[ "$code" -eq 2 ]
grep -Fqx 'ERROR: repeated option: --item' <<<"$out"

for protocol in \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
do
  grep -Fq './scripts/development-workflow/checkpoint-resume-gate.sh' "$REPO_ROOT/$protocol"
  grep -Fq -- '--expected-worktree' "$REPO_ROOT/$protocol"
  grep -Fq -- '--expected-branch' "$REPO_ROOT/$protocol"
  grep -Fq -- '--main-repo-root' "$REPO_ROOT/$protocol"
  grep -Fq -- '--checkpoint-state <pending|satisfied|waived>' "$REPO_ROOT/$protocol"
done
printf 'PASS: checkpoint resume gate\n'
