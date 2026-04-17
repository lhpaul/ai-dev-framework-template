# batch-merge ff-pull transient failure retry — Spec

**Depends on**: none

---

## Overview

`batch-merge.sh` fails with a false "Could not fast-forward local 'develop' from origin — resolve divergence manually" error during sequential batch merges. The error is transient: a manual retry of the same command immediately succeeds. In an automated `/batch-merge` run the script exits with `MERGE_RESULT=failed`, causing the PR to be aborted from the batch for no real reason.

The fix adds a one-shot retry (fetch + ff-pull) before surfacing the failure, so a transient local-ref stale state is recovered automatically and does not abort the merge.

---

## Use Cases

### Use Case 1: Batch merge recovers from transient ff-pull failure

**Actor**: Automated batch-merge orchestrator (running `batch-merge.sh merge --pr <N>`)
**Preconditions**: A previous PR in the batch was merged and pushed to `develop` in the same orchestration run within the last few seconds.

**Steps**:
1. `batch-merge.sh merge` is called for the next PR in the batch.
2. The script runs `git pull --ff-only origin develop`.
3. The command fails transiently (local ref state is momentarily stale after the previous push).
4. The script automatically waits 2 seconds, re-fetches `origin develop`, and retries `git pull --ff-only`.
5. The retry succeeds.

**Postconditions**: The merge continues normally; `MERGE_RESULT=clean` is emitted. No human intervention required.

**Information shown**:
- On retry: a diagnostic message is written to stderr indicating that the first attempt failed and a retry is being attempted.

**Actions available**: N/A (fully automated)

**Considerations**:
- If the retry also fails (e.g., a genuine divergence), the existing `merge_die` path is taken and `MERGE_RESULT=failed` is emitted as before.
- The retry must not mask real divergence — only a transient condition where the ff-pull succeeds on the second attempt is silently recovered.

---

### Use Case 2: Genuine divergence is still surfaced as a hard failure

**Actor**: Automated batch-merge orchestrator
**Preconditions**: Local `develop` has genuinely diverged from `origin/develop` (e.g., a force-push or uncommitted local commits).

**Steps**:
1. `batch-merge.sh merge` is called.
2. The first `git pull --ff-only` fails.
3. The retry after 2 seconds also fails.

**Postconditions**: `MERGE_RESULT=failed` with the original error message is emitted, same as the current behavior. The orchestrator is not misled.

**Information shown**:
- The same structured `MERGE_RESULT=failed` and `ERROR_MESSAGE` output as the current behavior.

**Actions available**: N/A (fully automated; existing manual remediation applies)

**Considerations**:
- The retry adds at most a 2-second delay before surfacing a genuine failure.

---

## Business Rules

- A retry is attempted exactly once — no additional retries after the second attempt.
- The sleep before the retry is 2 seconds (fixed, not configurable via script flags for this MVP).
- The retry consists of: `git fetch origin <TARGET_BASE>` followed by `git pull --ff-only origin <TARGET_BASE>`.
- A diagnostic message on stderr must distinguish the retry attempt from a final failure.
- The existing `merge_die` behavior (structured `MERGE_RESULT=failed` + `ERROR_MESSAGE` output) is preserved for genuine failures.
- No changes to discovery mode, conflict handling, or any other `batch-merge.sh` section.

---

## Acceptance Criteria

- [ ] When `git pull --ff-only origin develop` fails on the first attempt but succeeds on the second attempt, the merge continues and `MERGE_RESULT=clean` is emitted.
- [ ] When both the first and second `git pull --ff-only` attempts fail, `MERGE_RESULT=failed` is emitted with an appropriate error message (same structured output contract as today).
- [ ] A diagnostic stderr message is present when a retry is attempted, clearly distinguishing "retrying" from "giving up".
- [ ] No existing test scenarios for `batch-merge.sh` are broken by the change.
- [ ] The change is scoped to the fast-forward pull step and does not alter discovery, conflict classification, or post-merge logic.

---

## Out of Scope (MVP)

- Configurable retry count or sleep duration via command-line flags.
- Retrying any other git operations in `batch-merge.sh` (only the ff-pull step is in scope).
- Changes to `post-merge-cleanup.sh`, `pr-review-loop.sh`, or other batch-member scripts.
- Addressing issue #177 (locked worktrees) — that is a separate item.
