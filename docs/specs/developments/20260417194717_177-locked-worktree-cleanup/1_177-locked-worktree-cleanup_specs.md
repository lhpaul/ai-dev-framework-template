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
2. The script attempts to forcibly remove the worktree.
3. The removal fails because the worktree is locked.
4. The script detects the lock condition and emits a human-readable warning including the worktree path and the detected lock reason.
5. The script unlocks the worktree and then removes it. If unlocking is unavailable or fails, the script uses an alternative removal method that bypasses the lock.
6. The worktree is removed successfully.
7. The script proceeds to delete the local branch and complete cleanup.

**Postconditions**: Cleanup completes without manual intervention; the locked worktree is removed and the branch is deleted.

**Information shown**:
- A warning log line on stdout including the worktree path, the detected lock reason, and a note that the lock is being force-overridden.

**Actions available**: N/A (fully automated)

**Considerations**:
- The force-override warning must be visible to the human operator so that if a legitimately-active worktree is ever accidentally removed, the incident can be diagnosed.
- The script must not silently swallow the lock error; the warning must always appear when a lock is force-overridden.
- If the remediation fails (e.g., filesystem permissions), the script must surface the error and exit non-zero rather than continuing.

---

### Use Case 2: Cleanup falls through to the double-force path when unlock is unavailable

**Actor**: Automated post-merge cleanup
**Preconditions**: `git worktree unlock` fails (e.g., git version predating the unlock subcommand), but the lock is a stale Claude agent lock.

**Steps**:
1. Script detects the locked-worktree condition as in Use Case 1.
2. The unlock attempt is unavailable or exits non-zero.
3. Script falls back to an alternative removal method that bypasses the lock.
4. Worktree is removed; cleanup continues.

**Postconditions**: Cleanup completes; worktree and branch are gone.

**Information shown**:
- Same force-override warning as Use Case 1, plus an additional note that the primary unlock path failed and the fallback was used.

**Actions available**: N/A (fully automated)

**Considerations**:
- The fallback removal method is a safety net; the unlock-then-remove path is preferred when available because it is explicit about the lock release.

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

- The script must detect when a worktree removal attempt fails because the worktree is locked (as opposed to other removal failures).
- When a lock is detected, the script MUST emit a human-readable warning that includes: the worktree path, the detected lock reason (from the lock error output), and a note that the lock is being force-overridden.
- The script must first attempt to unlock the worktree and then remove it. If unlocking is unavailable or fails, the script must use an alternative removal method that bypasses the lock.
- If both remediation paths fail, the script must exit non-zero with a clear error message. It must not silently skip the worktree and leave it dangling.
- The lock-override warning must be emitted before the remediation attempt, not after, so it appears in the log even if the remediation fails.
- No changes to the branch-deletion logic, issue-close logic, or `develop` checkout/pull steps.
- The fix must only modify `post-merge-cleanup.sh` behavior, not `batch-merge.sh`.

---

## Operational Visibility

- **Logs**: A warning line is written to stdout (not stderr) so it appears in the normal cleanup output that operators see. The format is:
  `WARNING: Worktree '<path>' is locked (reason: <lock-reason>). Force-overriding — if this worktree belongs to an active agent, data may be lost.`
- **Audit trail**: Because the warning is part of stdout, it is captured in any CI or terminal log that records cleanup output.

---

## Acceptance Criteria

- [ ] When a worktree removal attempt fails because the worktree is locked, the script logs a force-override warning and successfully removes the worktree via the unlock-then-remove or fallback path.
- [ ] The force-override warning includes the worktree path and the detected lock reason.
- [ ] When the worktree is not locked, the standard single removal attempt succeeds and no warning is emitted — behavior is unchanged.
- [ ] When no worktree is found for the merged branch, behavior is unchanged.
- [ ] If both remediation attempts fail, the script exits non-zero with a clear error; it does not silently continue.
- [ ] End-to-end: running `post-merge-cleanup.sh <branch>` against a branch whose worktree is locked completes successfully without manual intervention.

---

## Out of Scope (MVP)

- Changes to `batch-merge.sh` merge step or conflict-resolution logic.
- Changes to `pr-review-loop.sh`, developer agent docs, Protocol 91 Step 7a, or Protocol 90 batching logic.
- Fixing the root cause of why Claude Code's subagent runtime leaves the worktree lock in place (upstream issue — tracked separately).
- Configurable retry count or lock-override behavior via command-line flags.
- Handling locked worktrees in any script other than `post-merge-cleanup.sh`.
- Issue #184 (also touches `post-merge-cleanup.sh`) — queued for the next batch to avoid conflict.
