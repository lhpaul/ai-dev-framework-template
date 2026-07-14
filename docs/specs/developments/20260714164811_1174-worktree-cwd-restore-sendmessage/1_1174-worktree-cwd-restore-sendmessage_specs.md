# Worktree CWD Restore on Checkpoint Resume - Spec

---

## Overview

Workflow runs that use isolated worktrees must resume inside the same worktree
after a human-checkpoint pause. Today, a SendMessage-triggered continuation can
start in the main clone instead, which risks moving the shared checkout away
from `develop` and contaminating parallel work.

This feature adds a resume-side operator contract for checkpointed `/run-item`
and `/run-epic` work: before any file operation or git state-changing action,
the runner verifies it is in the expected worktree, re-enters that worktree when
it can identify it safely, or stops with a clear recovery action. The existing
initial-entry branch guard remains in force; this closes the gap after a paused
session is resumed.

## Brief Objective List

Derived from issue #1174:

1. Protect worktree-isolated item-orchestrator runs that pause at a human
   checkpoint and later resume through a SendMessage continuation.
2. Verify the resumed session's current working directory matches the expected
   isolated worktree before any file operation or git state-changing action.
3. When the resumed session starts in the main clone but the correct worktree
   can be identified safely, re-enter the worktree before continuing.
4. When the expected worktree cannot be verified, stop before mutation with a
   clear error and human recovery action.
5. Preserve the invariant that the main clone remains on `develop` for
   concurrent runners.
6. Cover the resume-side gap left after the earlier pre-edit branch guard fixed
   initial entry.
7. Apply the behavior to the run-item and run-epic checkpoint-resume paths.
8. Include verification that a resumed checkpointed run cannot silently operate
   from the main clone.

## Use Cases

### Use Case 1: Resume a checkpointed item run inside its worktree

**Actor**: Workflow operator.
**Preconditions**: A `/run-item` workflow was dispatched with worktree
isolation, paused at a human checkpoint, and is later resumed through a new
message/session.

**Steps**:

1. The operator sends the continuation message after satisfying or responding
   to the checkpoint.
2. Before editing files or changing git state, the runner checks the expected
   worktree path and branch for the item.
3. If the current session is already inside the expected worktree, the runner
   continues normally.
4. If the current session started in the main clone but the expected worktree is
   registered and matches the item branch, the runner enters that worktree and
   continues from there.

**Postconditions**: The item continues from the checkpoint using the isolated
worktree, and the main clone remains available for other workflow runners.

**Information shown**:

- The item identifier and workflow branch being resumed.
- The expected worktree path.
- Whether the runner was already in the worktree or re-entered it.
- Any checkpoint status that still requires human action.

**Actions available**:

- Continue the same item after successful worktree verification.
- Stop the run if a checkpoint is still pending.
- Report a missing or inconsistent worktree for human recovery.

**Considerations**:

- Re-entering the worktree must not imply that the checkpoint was satisfied or
  waived.
- The verification happens before file writes, file edits, commits, branch
  switches, resets, restores, PR updates, or tracker mutations.

### Use Case 2: Stop when the expected worktree cannot be trusted

**Actor**: Workflow operator.
**Preconditions**: A checkpointed worktree-isolated run is resumed, but the
runner cannot verify the intended worktree path and branch.

**Steps**:

1. The runner performs the checkpoint-resume worktree preflight.
2. The runner finds that the current directory, registered worktree list, or
   branch context does not prove that the session is operating in the expected
   worktree.
3. The runner stops before mutation and prints a recovery message.

**Postconditions**: No repository or tracker mutation happens from an
unverified directory.

**Information shown**:

- The item and branch that were expected.
- The current directory and branch that were observed.
- Whether a matching registered worktree was absent, ambiguous, or mismatched.
- The concrete human action required to unblock the resume.

**Actions available**:

- Re-run the item with the correct worktree handoff context.
- Restore or recreate the missing worktree outside the paused run.
- Ask the runner to resume after the directory problem is resolved.

**Considerations**:

- If the correct worktree was deleted or is ambiguous, the runner should fail
  closed rather than continuing from the main clone.
- The stop message should be clear enough for an operator to distinguish a
  missing worktree from a pending checkpoint decision.

### Use Case 3: Preserve the main clone during parallel batch work

**Actor**: Portfolio orchestrator or workflow operator.
**Preconditions**: Multiple workflow items are running in parallel, and at
least one checkpointed item is resumed after a pause.

**Steps**:

1. The checkpointed item resumes and performs the worktree preflight before any
   mutation.
2. The runner either operates from the item's isolated worktree or stops.
3. Other runners continue to rely on the main clone remaining on `develop`.

**Postconditions**: A resumed checkpointed item cannot silently switch or dirty
the main clone, reducing cross-run contamination risk.

**Information shown**:

- The worktree verification result for the resumed item.
- Any stop reason that prevents the item from continuing.
- Final branch and worktree context in the run summary.

**Actions available**:

- Continue the resumed item once its worktree context is verified.
- Keep other batch items running without sharing the resumed item's branch.
- Investigate and repair a missing or contaminated worktree before retrying.

**Considerations**:

- This protection complements the post-run main-clone guard; it prevents the
  bad state before mutation rather than only detecting it afterward.

### Use Case 4: Keep command surfaces aligned

**Actor**: Template maintainer.
**Preconditions**: The checkpoint-resume worktree requirement is added to the
canonical workflow.

**Steps**:

1. The maintainer updates the canonical run-item and run-epic checkpoint-resume
   guidance.
2. The maintainer updates any command or skill surface that can resume the same
   workflow.
3. The maintainer verifies that supported agent surfaces describe the same
   resume-side worktree requirement.

**Postconditions**: Operators get consistent worktree-resume behavior from the
supported command surfaces.

**Information shown**:

- Which resumed workflow path is protected.
- What context must be present to verify or re-enter the worktree.
- What stop condition appears when verification fails.

**Actions available**:

- Resume checkpointed work through supported surfaces.
- Follow the same recovery guidance regardless of command surface.

**Considerations**:

- Surface updates should point back to the canonical workflow behavior instead
  of creating separate worktree policies.

## Business Rules

- Worktree-isolated checkpoint resumes must verify the active working directory
  before any file operation, git state-changing action, PR mutation, tracker
  mutation, or label/comment mutation.
- The preflight applies when a paused checkpointed run resumes in a new session,
  including SendMessage-triggered continuations.
- The runner may continue only when the active directory is the expected
  worktree for the item branch, or when it safely re-enters that registered
  worktree before mutation.
- The runner must stop before mutation when the expected worktree path is
  missing, the item branch is not registered to a worktree, multiple candidate
  worktrees exist, or the observed directory/branch does not match the resumed
  item.
- A successful worktree re-entry does not satisfy, waive, or bypass a pending
  human checkpoint.
- The main clone must remain on `develop` and must not be used as the execution
  directory for a resumed worktree-isolated item.
- The resume-side preflight must complement, not replace, the existing
  initial-entry branch/worktree guard.
- The run-item and run-epic checkpoint-resume paths must expose the same
  operator-facing behavior and recovery language.
- Verification coverage must prove that a checkpointed resume starting from the
  main clone cannot silently mutate from that clone.

## Operational Visibility

- **Resume preflight log**: The run output names the item, branch, expected
  worktree path, observed current directory, and verification result.
- **Safe re-entry log**: When the runner moves from the main clone to the
  expected worktree, the run output records that correction before continuing.
- **Failure log**: When verification fails, the run output gives a clear stop
  reason and a concrete human recovery action.
- **Final summary**: The Work Item Runner summary includes the worktree path used
  for the resumed item and whether any checkpoint remains pending.
- **Main-clone invariant**: Verification or smoke evidence confirms the main
  clone remains on `develop` after the resumed run attempts to continue.

## Acceptance Criteria

- [ ] AC1: A checkpointed worktree-isolated `/run-item` resume performs a
      worktree CWD preflight before any file operation, git state-changing
      action, PR mutation, tracker mutation, label mutation, or comment
      mutation.
- [ ] AC2: A checkpointed worktree-isolated `/run-epic` resume performs the same
      worktree CWD preflight before mutation.
- [ ] AC3: When the resumed session starts in the main clone and exactly one
      registered worktree matches the expected item branch, the runner enters
      that worktree, logs the correction, and continues from that directory.
- [ ] AC4: When the expected worktree is missing, ambiguous, or on a mismatched
      branch, the runner stops before mutation with a clear message naming the
      item, expected branch, observed directory, observed branch when available,
      and human recovery action.
- [ ] AC5: Resuming or re-entering a worktree does not mark any human checkpoint
      as satisfied or waived.
- [ ] AC6: A resumed checkpointed run cannot silently switch, dirty, or otherwise
      use the main clone as the execution directory for the item branch.
- [ ] AC7: The existing initial-entry branch/worktree guard still applies before
      the first edit of newly dispatched worktree-isolated items.
- [ ] AC8: Run-item and run-epic command, skill, or protocol surfaces that can
      resume checkpointed work describe the same worktree-resume requirement and
      recovery behavior.
- [ ] AC9: Tests or smoke coverage simulate a checkpoint-resume session that
      begins from the main clone and verify that the runner either re-enters the
      correct worktree or stops before mutation.
- [ ] AC10: Verification evidence includes a main-clone branch check showing the
      shared checkout remains on `develop` after the resume attempt.

## Out of Scope (MVP)

- Redesigning human-checkpoint satisfaction or waiver semantics.
- Changing the guardrails policy model, delegated review model, or merge-risk
  model.
- General recovery for non-worktree serial runs that intentionally operate from
  the main clone.
- Automatically reconstructing deleted worktrees during a checkpoint resume.
- Solving runtime isolation for ports, databases, caches, or other shared
  resources beyond the repository working directory.
- Changing the earlier pre-edit branch guard except where documentation must
  clarify that it is complemented by the resume-side preflight.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| 1. Protect checkpointed SendMessage resumes | AC1, AC2; Use Cases 1 and 3 |
| 2. Verify CWD before mutation | AC1, AC2; Business Rules; Operational Visibility |
| 3. Re-enter the correct worktree when safe | AC3; Use Case 1 |
| 4. Stop clearly when verification fails | AC4; Use Case 2 |
| 5. Preserve the main clone invariant | AC6, AC10; Use Case 3 |
| 6. Cover the resume-side gap after the pre-edit guard | AC7; Overview; Out of Scope |
| 7. Apply to run-item and run-epic checkpoint resumes | AC1, AC2, AC8; Use Cases 1 and 4 |
| 8. Verify resumed runs cannot silently use the main clone | AC9, AC10 |
