# Orchestrator Worktree Isolation for Concurrent Items — Spec

---

## Overview

When a portfolio batch dispatches multiple file-mutating Work Item Runners at the
same time, each runner must operate in its own isolated worktree instead of the
main repository checkout. This prevents one runner from inheriting another
runner's active branch, editing on the wrong branch, or contaminating a sibling
PR. The workflow should make isolation a mandatory dispatch contract for
concurrent item work and should surface clear verification signals before any
runner starts editing files.

## Brief Objective List

- **BO-1**: Protocol 90 and the `/run-items` bounded execution path require
  worktree isolation for any batch with two or more concurrent file-mutating
  runners.
- **BO-2**: The pre-dispatch checklist verifies that every concurrent
  file-mutating runner is dispatched with worktree isolation and a distinct
  worktree path.
- **BO-3**: Each dispatched runner confirms, before its first file edit, that it
  is operating inside its assigned isolated worktree rather than the main clone.
- **BO-4**: The workflow distinguishes this dispatch-time shared-tree
  contamination risk from the separate unsanctioned nested-agent PR risk tracked
  by issue #1200.
- **BO-5**: Operators receive enough warning and audit evidence to diagnose a
  missing isolation contract without requiring live mid-batch intervention.

## Use Cases

### Use Case 1: Dispatch a Concurrent Mutating Batch

**Actor**: Portfolio Orchestrator
**Preconditions**: A human has approved a bounded batch containing two or more
file-mutating item runners that will execute concurrently.

**Steps**:

1. The orchestrator resolves the approved item list and identifies which item
   runners will mutate files concurrently.
2. Before dispatching the concurrent mutating runners, the orchestrator verifies
   that each one has worktree isolation enabled.
3. The orchestrator verifies that each concurrent mutating runner has a distinct
   assigned worktree path.
4. The orchestrator dispatches the concurrent mutating runners only after every
   one has a complete isolation assignment.

**Postconditions**: Every concurrent mutating runner starts in an assigned
worktree, and no runner is expected to share the main repository checkout for
file edits or branch-changing operations.

**Information shown**:

- The number of concurrent mutating runners in the batch.
- Each item identifier, assigned branch, and assigned worktree path.
- A confirmation that every mutating dispatch uses worktree isolation.

**Actions available**:

- Proceed with isolated dispatch when all assignments are valid.
- Stop before dispatch and report the missing or duplicate isolation assignment.

**Considerations**:

- Read-only inspection tasks do not require file-mutating worktree isolation.
- A batch with only one mutating runner may still use a worktree, but this spec
  only makes isolation mandatory when two or more mutating runners run
  concurrently.

### Use Case 2: Runner Self-Checks Before Editing

**Actor**: Work Item Runner
**Preconditions**: The runner was dispatched as part of a concurrent batch with
an assigned worktree path and branch.

**Steps**:

1. The runner enters the assigned worktree.
2. Before any file edit, branch-changing command, commit, or push, the runner
   confirms that its current working directory is inside the assigned worktree.
3. The runner confirms that the active branch matches the assigned item branch.
4. If either check fails, the runner stops before mutating files and reports the
   mismatch.

**Postconditions**: A runner cannot silently begin editing from the main
repository checkout or from a sibling runner's branch.

**Information shown**:

- The assigned worktree path.
- The active current working directory.
- The expected branch and active branch.
- A clear pass or stop result.

**Actions available**:

- Continue with stage work after the self-check passes.
- Stop and report a guardrail failure when the self-check fails.

**Considerations**:

- The self-check happens before the first file edit, not after a commit or PR
  has already been created.
- Recovery guidance must avoid switching, resetting, restoring, or otherwise
  mutating the main repository checkout.

### Use Case 3: Isolation Contract Is Missing or Invalid

**Actor**: Human operator
**Preconditions**: The orchestrator or a runner detects that a concurrent
mutating item lacks worktree isolation, has a duplicate worktree path, or is not
running from its assigned worktree.

**Steps**:

1. The workflow stops before further file mutation.
2. The workflow reports the affected item, expected branch, expected worktree
   path, observed current working directory, and observed branch when available.
3. The workflow names the human action required to unblock the batch.

**Postconditions**: The batch does not proceed with shared-tree branch
contamination risk, and the operator has enough evidence to recover without
guessing which runner or branch is affected.

**Information shown**:

- A clear isolation failure message.
- Item and branch identifiers for the affected runner.
- The expected and observed worktree context.
- Whether any file mutation happened before the stop.

**Actions available**:

- Re-dispatch the affected item with a valid isolated worktree.
- Inspect and reconcile any partial work if a runner reports that mutation
  already happened.

**Considerations**:

- The workflow should not auto-correct by switching the main repository branch
  when the main tree is dirty or when another runner may be using it.
- The stop message should make it clear whether the problem is dispatch-time
  isolation omission or a later runner-context violation.

## Business Rules

- **BR-1**: A batch has a mandatory worktree-isolation requirement when it
  dispatches two or more concurrent runners that may mutate files.
- **BR-1a**: The user-facing concurrent-dispatch contract may expose this
  requirement as `isolation: "worktree"` so operators can verify the actual
  dispatch setting, not only a prose claim that isolation is intended.
- **BR-2**: Every concurrent mutating runner must have a unique worktree path.
  Two runners must never be assigned the same path.
- **BR-3**: A concurrent mutating runner must not edit files, create commits, or
  push until it has confirmed that it is inside its assigned worktree and on its
  assigned branch.
- **BR-4**: A missing isolation assignment is a pre-dispatch stop condition, not
  a warning that can be ignored while the batch proceeds.
- **BR-5**: A failed runner self-check is a pre-mutation stop condition when no
  file edits have occurred yet.
- **BR-6**: If mutation may already have occurred outside the assigned
  worktree, the workflow must escalate for human inspection instead of
  discarding, moving, or auto-committing the unexpected changes.
- **BR-7**: Read-only concurrent work may run without an isolated worktree only
  when the dispatch is explicitly classified as non-mutating.
- **BR-8**: The dispatch-time isolation requirement is separate from the issue
  #1200 nested-agent PR boundary. This feature prevents shared-tree
  contamination caused by missing isolation at the initial orchestrator dispatch.
- **BR-9**: The workflow must preserve the main repository checkout as a stable
  operator surface during concurrent item execution.

## Operational Visibility

- **Dispatch summary**: Concurrent batch startup output shows each mutating item,
  assigned branch, assigned worktree path, and isolation status.
- **Runner self-check result**: Each runner reports its expected path, observed
  path, expected branch, observed branch, and pass or stop outcome before file
  mutation.
- **Failure reporting**: Missing isolation, duplicate worktree paths, wrong
  current working directory, and wrong branch each produce a specific failure
  message naming the affected item and required human action.
- **Audit trail**: Terminal batch summaries include any isolation failures or
  guardrail stops so the operator can distinguish safe isolated execution from
  a recovered or escalated batch.

## Acceptance Criteria

- [ ] **AC-1**: Given an approved batch with two or more concurrent
  file-mutating items, the orchestrator requires worktree isolation for every
  mutating item before dispatching the runners.
- [ ] **AC-2**: Given a concurrent mutating batch, the pre-dispatch summary
  lists every mutating item with a distinct worktree path and confirms that
  worktree isolation is enabled for each one.
- [ ] **AC-3**: Given a concurrent mutating batch where one runner lacks a
  worktree isolation assignment, the workflow stops the batch before
  dispatching any concurrent mutating runner and reports the affected item plus
  the missing assignment.
- [ ] **AC-4**: Given a concurrent mutating batch where two runners are assigned
  the same worktree path, the workflow stops before dispatch and reports both
  affected items plus the duplicate path.
- [ ] **AC-5**: Given a concurrent file-mutating runner dispatched in batch
  context, the runner confirms its current working directory is inside the
  assigned worktree before its first file edit, branch-changing command, commit,
  or push.
- [ ] **AC-6**: Given a concurrent file-mutating runner whose current working
  directory is the main repository checkout, the runner stops before mutating
  files and reports the expected worktree path, observed path, expected branch,
  and observed branch when available.
- [ ] **AC-7**: Given a concurrent file-mutating runner inside a worktree but on
  the wrong branch, the runner stops before mutating files and reports the
  expected and observed branch values.
- [ ] **AC-8**: Given a runner reports that mutation may already have occurred
  outside its assigned worktree, the workflow escalates for human inspection and
  does not auto-reset, auto-restore, or auto-commit the unexpected changes.
- [ ] **AC-9**: Given a concurrent read-only batch, the workflow may proceed
  without mandatory worktree isolation only when every non-isolated runner is
  explicitly classified as read-only.
- [ ] **AC-10**: Given an operator reviewing the final item or batch summary,
  the summary identifies whether worktree isolation passed, failed before
  mutation, or escalated after possible out-of-worktree mutation.
- [ ] **AC-11**: Given documentation for this feature, the dispatch-time
  shared-tree contamination risk is described separately from the unsanctioned
  nested-agent PR risk tracked by issue #1200.
- [ ] **AC-12**: Given an operator following Protocol 90 or the `/run-items`
  bounded execution path, the dispatch instructions state that concurrent
  file-mutating item runners require `isolation: "worktree"`.

## Coverage Matrix

| Brief objective | Covered by | Notes |
| --- | --- | --- |
| BO-1 | AC-1, AC-12, BR-1, BR-1a | Makes isolation mandatory for two or more concurrent mutating runners and visible in the dispatch contract. |
| BO-2 | AC-2, AC-3, AC-4, BR-2, BR-4 | Covers positive dispatch evidence and invalid-assignment stops. |
| BO-3 | AC-5, AC-6, AC-7, BR-3, BR-5 | Requires each runner to verify path and branch before mutation. |
| BO-4 | AC-11, BR-8 | Keeps issue #1200 separate from this dispatch-time contamination problem. |
| BO-5 | AC-8, AC-10, BR-6, Operational Visibility | Requires actionable failure reporting and safe escalation. |

## Out of Scope (MVP)

- Changing the separate issue #1200 behavior for unsanctioned nested-agent PRs.
- Defining the exact script, helper, prompt, or data structure changes that
  implement the isolation contract; those belong in the implementation plan.
- Reworking all non-batch single-item runs to require worktree isolation.
- Automatically repairing dirty main-checkout changes after a runner has already
  mutated outside its assigned worktree.

## Deferral Notes

No brief objectives are deferred to out of scope.
