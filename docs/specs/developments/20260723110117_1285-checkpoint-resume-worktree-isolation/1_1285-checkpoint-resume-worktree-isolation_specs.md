# Checkpoint Resume Worktree Isolation - Spec

**Depends on**: 1174-worktree-cwd-restore-sendmessage

---

## Overview

Worktree-isolated workflow runs can pause for a human checkpoint and later
resume in a new session. The earlier checkpoint-resume safeguard introduced by
#1174 can identify and re-enter a worktree, but a downstream recurrence showed
that advisory resume guidance is not sufficient when the resumed session starts
in the shared main clone and no longer retains its isolation context reliably.

This feature makes checkpoint resume a fail-closed workflow gate. Every resumed
worktree-isolated item receives its expected isolation context automatically,
proves that it is already operating in the assigned worktree on the assigned
branch before any mutation, and stops with explicit recovery guidance whenever
that proof is missing or contradictory.

## Brief Objective List

Derived from issue #1285 and its 2026-07-23 backlog refinement:

1. Provide every checkpoint resume with the expected worktree path, expected
   branch, and main-repository root automatically.
2. Enforce the worktree resume preflight at the actual checkpoint-resume entry
   path before any mutation.
3. Fail closed when isolation metadata is missing, the resumed session is in
   the main clone, the branch is wrong, or the worktree state is ambiguous.
4. Preserve the shared main clone during concurrent workflow execution.
5. Exercise the actual checkpoint-resume handoff in regression coverage rather
   than testing only a standalone preflight capability.
6. Give operators explicit recovery guidance that prefers a fresh,
   pre-approved runner when safe resume context cannot be reconstructed.
7. Keep resume behavior and stop evidence consistent across every supported
   worktree-isolated command and orchestration surface.
8. Keep checkpoint satisfaction separate from isolation verification.

## Use Cases

### Use Case 1: Continue a checkpointed item from its assigned worktree

**Actor**: Workflow operator.
**Preconditions**: A worktree-isolated workflow item paused at a human
checkpoint, the checkpoint has been satisfied or waived, and the item is being
resumed.

**Steps**:

1. The operator sends the continuation instruction.
2. The resumed session receives the item's expected worktree path, expected
   branch, and main-repository root.
3. Before any repository, tracker, or pull-request mutation, the resumed
   session verifies its current directory, active branch, and registered
   worktree state against that context.
4. When every isolation check matches, the item continues from its existing
   checkpoint boundary.

**Postconditions**: The item continues only from its assigned worktree and the
shared main clone remains untouched.

**Information shown**:

- Item identifier.
- Expected and observed worktree locations.
- Expected and observed branches.
- Isolation verification outcome.
- Remaining checkpoint state, if any.

**Actions available**:

- Continue the item after both isolation and checkpoint gates pass.
- Stop for a still-pending human checkpoint.
- Stop for invalid isolation context.

**Considerations**:

- A valid worktree does not itself satisfy or waive a human checkpoint.
- The isolation gate runs again after every checkpoint pause, even when the
  same runner handled the earlier portion of the item.

### Use Case 2: Stop a resume that starts in the main clone

**Actor**: Workflow operator.
**Preconditions**: A worktree-isolated item is resumed, but the new session's
current directory is the shared main clone.

**Steps**:

1. The resumed session receives the expected isolation context.
2. The isolation gate observes that the current directory is the main clone.
3. The session stops before any file, git, tracker, label, comment, or
   pull-request mutation.
4. The operator receives the expected context, observed context, stop reason,
   and recovery action.

**Postconditions**: The resumed item cannot silently dirty, switch, commit from,
or otherwise mutate the main clone.

**Information shown**:

- The `unclear_requirements` stop condition.
- The affected item.
- Expected worktree and branch.
- Observed directory and branch when available.
- A concrete fresh-runner recovery action.

**Actions available**:

- Re-dispatch a fresh runner with the checkpoint already approved and the full
  isolation assignment supplied.
- Inspect the main clone separately if contamination may already have occurred.
- Leave sibling runners undisturbed.

**Considerations**:

- This iteration intentionally replaces automatic main-clone re-entry for the
  actual checkpoint-resume path with a fail-closed stop.
- The stopped session does not switch branches, recreate a worktree, reset,
  restore, stash, or clean the main clone.

### Use Case 3: Stop on missing or contradictory isolation context

**Actor**: Workflow operator.
**Preconditions**: A checkpointed item is resumed with incomplete metadata, an
unexpected directory or branch, or an untrusted registered-worktree state.

**Steps**:

1. The resumed session evaluates all required isolation inputs.
2. At least one required input is missing or does not match the observed state.
3. The session stops before mutation and reports the failed comparison.
4. The operator corrects the dispatch context or starts a fresh runner.

**Postconditions**: No workflow artifact changes from an unverified execution
context.

**Information shown**:

- Which required field or comparison failed.
- Expected and observed values when available.
- Whether the worktree was missing, detached, duplicated, or assigned to the
  wrong branch.
- The human action required to unblock the item.

**Actions available**:

- Correct the handoff metadata and re-dispatch.
- Recreate a missing worktree outside the stopped session.
- Inspect ambiguous or potentially contaminated state before retrying.

**Considerations**:

- Absence of evidence is not treated as a safe default.
- A stopped resume cannot repair uncertain state automatically.

### Use Case 4: Preserve isolation while sibling runners remain active

**Actor**: Portfolio orchestrator.
**Preconditions**: Multiple batch items are active and one worktree-isolated
item resumes after a human checkpoint.

**Steps**:

1. The resumed item performs the isolation gate before mutation.
2. The item continues from its assigned worktree or stops.
3. Sibling items keep operating in their own assigned worktrees.
4. The portfolio orchestrator receives the resumed item's isolation outcome.

**Postconditions**: No resumed item competes with a sibling through the main
clone, and the orchestrator can distinguish safe continuation from a required
fresh dispatch.

**Information shown**:

- Per-item isolation result.
- Whether mutation was allowed or blocked.
- Any recovery action required before the item can be resumed.

**Actions available**:

- Continue unaffected sibling items.
- Re-dispatch only the stopped item.
- Halt broader dispatch if main-clone contamination is suspected.

**Considerations**:

- A sibling runner being active never weakens the resumed item's isolation
  requirements.

### Use Case 5: Keep checkpoint-resume surfaces aligned

**Actor**: Template maintainer.
**Preconditions**: The checkpoint-resume contract is exposed through multiple
supported workflow commands and orchestration paths.

**Steps**:

1. The maintainer applies the same required context, allowed outcomes, stop
   evidence, and recovery behavior to each resume surface.
2. Regression coverage exercises the real handoff path for each applicable
   surface.
3. The maintainer verifies that examples and operator guidance agree with the
   canonical decision matrix.

**Postconditions**: Operators receive the same fail-closed protection
regardless of which supported worktree-isolated workflow surface resumes the
item.

**Information shown**:

- Required resume context.
- Allowed continuation and stop outcomes.
- Recovery guidance for every failure outcome.

**Actions available**:

- Resume through any supported surface with consistent behavior.
- Identify a surface mismatch as a workflow defect.

**Considerations**:

- A standalone preflight test does not prove that the resume entry path invokes
  the gate.
- Surface-specific wording may vary, but observable outcomes and required
  evidence must not.

## Business Rules

- Every checkpoint resume for a worktree-isolated item must automatically
  receive the item identifier, expected worktree path, expected branch, and
  main-repository root.
- The isolation gate must complete before file edits, branch or worktree
  changes, commits, pushes, tracker writes, pull-request changes, label changes,
  comments, review decisions, or merges.
- Continuation is allowed only when the current directory is the expected
  worktree or one of its descendants, the active branch is the expected branch,
  and the registered worktree state proves the assignment is unique and
  consistent.
- A resumed session observed in the main clone must stop before mutation. It
  must not automatically re-enter another directory as part of that resumed
  session.
- Missing required metadata, an unexpected directory, a wrong branch, a
  missing or detached worktree, or multiple matching worktrees must fail closed.
- Every isolation stop must name the `unclear_requirements` stop condition, the
  affected item, the failed expected-versus-observed comparison, and the human
  action required to unblock it.
- Isolation verification must not satisfy, waive, or otherwise modify a human
  checkpoint.
- A stopped resume must not attempt automatic repair of the main clone or
  uncertain worktree state.
- When safe resume context cannot be reconstructed, recovery guidance must
  prefer a fresh runner that receives the complete isolation assignment and any
  already-approved checkpoint decision at initial dispatch.
- The same contract applies to supported item, epic, and portfolio-batch paths
  whenever they resume a worktree-isolated item after a checkpoint.
- Regression coverage must exercise the real resume handoff and demonstrate
  that no mutation occurs before the isolation decision.

## Checkpoint Resume Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Complete metadata; current directory is the expected worktree; active branch and registered assignment match; checkpoint satisfied or waived | Continue | Resume the existing item from its checkpoint boundary | Item resume, epic child resume, portfolio-batch item resume, regression scenarios | A resumed item starts inside its assigned worktree on its assigned branch |
| Complete metadata and valid worktree context; checkpoint still pending | Stop for checkpoint | Request the unresolved human decision without changing isolation state | All checkpoint-bearing resume surfaces and examples | The worktree is valid, but product approval has not been supplied |
| Current directory is the main clone | Fail closed with `unclear_requirements` | Re-dispatch a fresh runner with full isolation context and the approved checkpoint decision | Session initialization, all worktree-isolated resume surfaces, regression scenarios, operator guidance | A continuation message starts a new session at the process root |
| Required isolation metadata is missing | Fail closed with `unclear_requirements` | Correct the handoff or re-dispatch; do not infer defaults | Session initialization, item/epic/batch handoffs, regression scenarios | Expected worktree path was not carried across the pause |
| Current directory is outside the expected worktree | Fail closed with `unclear_requirements` | Inspect the observed location and re-dispatch safely | All resume surfaces and regression scenarios | The session starts in a sibling worktree |
| Active branch does not match the expected branch | Fail closed with `unclear_requirements` | Inspect branch ownership and re-dispatch; do not switch automatically | All resume surfaces and regression scenarios | The expected worktree is registered but checked out on a different item branch |
| Registered worktree is missing, detached, duplicated, or ambiguous | Fail closed with `unclear_requirements` | Repair or recreate worktree state outside the stopped session, then start a fresh runner | Worktree discovery, all resume surfaces, regression scenarios, recovery guidance | Two worktrees appear to claim the expected item branch |

## Operational Visibility

- **Resume context**: Output names the item, expected worktree, expected branch,
  main-repository root, observed directory, and observed branch when available.
- **Gate result**: Output states whether isolation verification passed or
  stopped before mutation.
- **Named stop**: Failure output includes `unclear_requirements`, the affected
  item, the failed comparison, and the human recovery action.
- **Mutation boundary**: Verification evidence demonstrates that no file, git,
  tracker, pull-request, label, comment, review, or merge mutation preceded the
  gate.
- **Checkpoint state**: Output reports checkpoint satisfaction separately from
  isolation state.
- **Batch visibility**: The parent orchestrator receives the stop or continue
  disposition without inferring success from a silent child exit.
- **Recovery guidance**: Unsafe resume contexts recommend a fresh,
  pre-approved runner and warn against automatic repair from the stopped
  session.

## Acceptance Criteria

- [ ] AC1: Every actual checkpoint-resume handoff for a worktree-isolated item
      supplies the item identifier, expected worktree path, expected branch,
      and main-repository root automatically.
- [ ] AC2: The resumed execution path evaluates the isolation gate before any
      file, git, tracker, pull-request, label, comment, review, or merge
      mutation.
- [ ] AC3: A resumed item continues only when its current directory is the
      expected worktree or a descendant, its active branch matches the expected
      branch, its registered worktree assignment is unique and consistent, and
      its checkpoint is satisfied or waived.
- [ ] AC4: When a resumed session starts in the main clone, it stops before
      mutation with `unclear_requirements`, the affected item, expected and
      observed context, and fresh-runner recovery guidance.
- [ ] AC5: Missing isolation metadata, an unexpected directory, a wrong branch,
      or missing, detached, duplicated, or ambiguous worktree state stops before
      mutation with the failed comparison and human recovery action.
- [ ] AC6: A stopped checkpoint resume does not re-enter another directory,
      switch branches, recreate a worktree, reset, restore, stash, clean, or
      otherwise repair repository state automatically.
- [ ] AC7: Isolation verification does not satisfy, waive, or alter the
      checkpoint lifecycle; valid isolation with a pending checkpoint still
      stops for the human decision.
- [ ] AC8: Supported item, epic, and portfolio-batch resume surfaces enforce
      the same inputs, outcomes, next actions, and stop evidence described in
      the consistency matrix.
- [ ] AC9: Regression coverage exercises the actual continuation or
      session-resume handoff, begins at least one scenario in the main clone,
      and proves that the resume stops before mutation.
- [ ] AC10: Regression coverage includes missing metadata, wrong branch,
      unexpected directory, and ambiguous worktree scenarios as fail-closed
      outcomes.
- [ ] AC11: Recovery guidance prefers a fresh runner with checkpoint approval
      front-loaded when safe resume context cannot be reconstructed.
- [ ] AC12: A concurrent batch scenario proves that a stopped resumed item does
      not switch, dirty, or commit from the shared main clone while sibling
      runners remain active.

## Out of Scope (MVP)

- Redesigning checkpoint recommendation, satisfaction, waiver, or approval
  semantics.
- Automatically re-entering, recreating, or repairing a worktree from the
  stopped resumed session.
- Automatically resetting, restoring, stashing, cleaning, or otherwise
  repairing a potentially contaminated main clone.
- General process-level working-directory management outside
  checkpoint-resume workflows.
- Changing intentionally serial, non-worktree workflow execution.
- Solving isolation for ports, services, databases, caches, credentials, or
  other shared resources outside repository worktrees.
- Replacing the existing initial-dispatch worktree isolation gate.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| 1. Supply expected worktree, branch, and main root automatically | AC1; Use Case 1; Business Rules |
| 2. Enforce preflight at the actual resume entry path before mutation | AC2, AC9; Use Cases 1 and 5; Operational Visibility |
| 3. Fail closed for missing metadata, main-clone CWD, wrong branch, and ambiguity | AC4, AC5, AC6, AC10; Use Cases 2 and 3; Consistency Matrix |
| 4. Preserve the shared main clone during concurrency | AC12; Use Case 4; Business Rules |
| 5. Test the actual checkpoint-resume handoff | AC9, AC10; Use Case 5 |
| 6. Prefer fresh, pre-approved runner recovery | AC4, AC11; Use Cases 2 and 3; Operational Visibility |
| 7. Keep supported resume surfaces aligned | AC8; Use Case 5; Consistency Matrix |
| 8. Keep checkpoint and isolation state separate | AC3, AC7; Use Case 1; Business Rules |

## Deferral Notes

No brief objectives are deferred from this iteration.
