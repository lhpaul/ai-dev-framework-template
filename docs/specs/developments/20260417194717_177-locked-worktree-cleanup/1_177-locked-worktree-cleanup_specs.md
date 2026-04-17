# fix(post-merge-cleanup): handle locked Claude worktrees — Spec

**Depends on**: none

---

## Overview

After every parallel batch merge, `post-merge-cleanup.sh` fails when trying to remove worktrees that the Claude Code subagent runtime left in a locked state. The single `git worktree remove --force` call is insufficient against a locked worktree — git refuses and prints `fatal: cannot remove a locked working tree`. The script must detect this condition and fall back to an unlock-then-remove (or double-force) sequence, logging that a lock was force-overridden so humans can spot if a legitimately-active worktree is ever force-removed.

---

## Use Cases

### Use Case 1: Cleanup succeeds when worktree is locked by a completed Claude agent

**Actor**: Automated post-merge cleanup (`post-merge-cleanup.sh` called by `/batch-merge` or directly by the user after a PR merge)
**Preconditions**: The merged branch's worktree exists and is locked with reason `claude agent agent-<id> (pid <n>)` — the agent has already exited and returned control.

**Steps**:
1. `post-merge-cleanup.sh` discovers a worktree using the merged branch.
2. The script attempts `git worktree remove "$WORKTREE_PATH" --force`.
3. Git returns `fatal: cannot remove a locked working tree, lock reason: claude agent…`.
4. The script detects the lock error and logs a warning: `Worktree '<path>' was locked (lock reason: <reason>). Force-overriding lock — verify no active agent is still using this path.`
5. The script runs `git worktree unlock "$WORKTREE_PATH"` followed by `git worktree remove "$WORKTREE_PATH" --force`. If `git worktree unlock` fails, the script falls back to `git worktree remove -f -f "$WORKTREE_PATH"` (double-force).
6. The worktree is removed successfully.
7. The script proceeds to delete the local branch and complete cleanup.

**Postconditions**: Cleanup completes without manual intervention; the locked worktree is removed and the branch is deleted.

**Information shown**:
- A log line on stdout indicating a locked worktree was detected and force-overridden, including the worktree path and lock reason.

**Actions available**: N/A (fully automated)

**Considerations**:
- The force-override log must be visible to the human operator so that if a legitimately-active worktree is ever accidentally removed, the incident can be diagnosed.
- The script must not silently swallow the lock error; the warning must always appear when a lock is force-overridden.
- If the unlock+remove sequence itself fails (e.g., filesystem permissions), the script must surface the error and exit non-zero rather than continuing.

---

### Use Case 2: Cleanup falls through to the double-force path when unlock is unavailable

**Actor**: Automated post-merge cleanup
**Preconditions**: `git worktree unlock` fails (e.g., git version predating the unlock subcommand), but the lock is a stale Claude agent lock.

**Steps**:
1. Script detects the locked-worktree error as in Use Case 1.
2. `git worktree unlock "$WORKTREE_PATH"` exits non-zero.
3. Script falls back to `git worktree remove -f -f "$WORKTREE_PATH"` (double-force, which bypasses the lock entirely in git ≥ 2.39).
4. Worktree is removed; cleanup continues.

**Postconditions**: Cleanup completes; worktree and branch are gone.

**Information shown**:
- Same force-override warning as Use Case 1, plus an additional note that `unlock` failed and double-force was used.

**Actions available**: N/A (fully automated)

**Considerations**:
- The double-force fallback is a safety net; the unlock-first path is preferred when available because it is explicit.

---

### Use Case 3: Cleanup continues unchanged for worktrees that are not locked

**Actor**: Automated post-merge cleanup
**Preconditions**: The merged branch's worktree exists but is not locked (standard case, e.g., worktree created by the orchestrator but the agent used the normal exit path that releases the lock).

**Steps**:
1. `post-merge-cleanup.sh` discovers the worktree.
2. `git worktree remove "$WORKTREE_PATH" --force` succeeds on the first attempt.
3. Cleanup proceeds as before.

**Postconditions**: No change in behavior for the non-locked case; no spurious log lines.

**Information shown**: Same as current behavior (no force-override warning).

**Considerations**:
- The lock-detection path must not trigger unless the error output matches the locked-worktree pattern.

---

### Use Case 4: No worktree found for the merged branch

**Actor**: Automated post-merge cleanup
**Preconditions**: The merged branch has no associated worktree (e.g., the work was done directly on the main working tree or the worktree was already cleaned up manually).

**Steps**:
1. `post-merge-cleanup.sh` finds no worktree for the branch.
2. Script skips the worktree-removal block entirely.
3. Branch is deleted directly.

**Postconditions**: No change in behavior; this path is unchanged.

**Information shown**: Same as current behavior.

**Actions available**: N/A (fully automated)

**Considerations**: Unchanged from current behavior.

---

## Business Rules

- The lock-detection trigger is the string `cannot remove a locked working tree` in git's stderr output on the first `git worktree remove --force` attempt.
- When a lock is detected, the script MUST emit a human-readable warning that includes: the worktree path, the detected lock reason (extracted from git's error output), and a note that the lock is being force-overridden.
- The preferred remediation sequence is: `git worktree unlock "$WORKTREE_PATH"` followed by `git worktree remove "$WORKTREE_PATH" --force`.
- If `git worktree unlock` exits non-zero, the script falls back to `git worktree remove -f -f "$WORKTREE_PATH"`.
- If both remediation paths fail, the script must exit non-zero with a clear error message. It must not silently skip the worktree and leave it dangling.
- The lock-override warning must be emitted before the remediation attempt, not after, so it appears in the log even if the remediation fails.
- No changes to the branch-deletion logic, issue-close logic, or `develop` checkout/pull steps.
- The fix must not alter the behavior of `batch-merge.sh`'s merge step — it operates only in `post-merge-cleanup.sh`.

---

## Operational Visibility

- **Logs**: A warning line is written to stdout (not stderr) so it appears in the normal cleanup output that operators see. The format is:
  `WARNING: Worktree '<path>' is locked (reason: <lock-reason>). Force-overriding — if this worktree belongs to an active agent, data may be lost.`
- **Audit trail**: Because the warning is part of stdout, it is captured in any CI or terminal log that records cleanup output.

---

## Acceptance Criteria

- [ ] When `git worktree remove --force` fails with `cannot remove a locked working tree`, the script logs a force-override warning and successfully removes the worktree using the unlock-then-force or double-force path.
- [ ] The force-override warning includes the worktree path and the lock reason extracted from git's error output.
- [ ] When the worktree is not locked, `git worktree remove --force` is called exactly once and no warning is emitted — behavior is unchanged.
- [ ] When no worktree is found for the merged branch, behavior is unchanged.
- [ ] If both the unlock and double-force attempts fail, the script exits non-zero with a clear error; it does not silently continue.
- [ ] End-to-end: running `post-merge-cleanup.sh <branch>` against a branch whose worktree is locked (lock reason `claude agent …`) completes successfully without manual intervention.

---

## Out of Scope (MVP)

- Changes to `batch-merge.sh` merge step or conflict-resolution logic.
- Changes to `pr-review-loop.sh`, developer agent docs, Protocol 91 Step 7a, or Protocol 90 batching logic.
- Fixing the root cause of why Claude Code's subagent runtime leaves the worktree lock in place (upstream issue — tracked separately).
- Configurable retry count or lock-override behavior via command-line flags.
- Handling locked worktrees in any script other than `post-merge-cleanup.sh`.
- Issue #184 (also touches `post-merge-cleanup.sh`) — queued for the next batch to avoid conflict.
