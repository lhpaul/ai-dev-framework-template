# Delete Remote Implementation Branch After Multi-Stage Merge - Spec

---

## Overview

Multi-stage workflow runs should finish with the same implementation-branch
cleanup guarantees as single-stage runs. When a full-pipeline item advances
through separate spec, plan, and implementation PRs, the final implementation
PR merge should leave no stale implementation branch on the remote.

The branch lifecycle should remain explicit: spec and implementation-plan
branches may persist after merge, while implementation branches are expected to
be deleted after the implementation PR is confirmed merged. Portfolio scans
should distinguish these expected states so operators see real cleanup problems
instead of noisy warnings about intentionally persistent branches.

## Brief Objective List

Derived from issue #1185:

1. Multi-stage item runners delete the remote implementation branch after the
   implementation PR merges.
2. The implementation-stage terminal cleanup path matches the single-stage
   cleanup behavior.
3. Spec and implementation-plan branches remain intentionally persistent after
   merge and are not treated as implementation cleanup failures.
4. Stale-branch audit or scan output distinguishes expected-persistent
   spec/plan branches from implementation branches that should have been
   deleted.
5. Operators receive clear visibility when an implementation branch remains on
   the remote after its PR has merged.
6. Test or audit coverage prevents the multi-stage cleanup regression from
   returning.

## Use Cases

### Use Case 1: Multi-stage item finishes implementation merge

**Actor**: Work Item Runner operating on a full-pipeline item.
**Preconditions**: The item has already completed spec and plan stages, an
implementation PR exists on an implementation branch, and the implementation PR
has been merged or is merged by a delegated merge path.

**Steps**:

1. The runner verifies that the implementation PR is merged.
2. The runner performs the implementation-stage cleanup sequence for the merged
   implementation branch.
3. The runner verifies that the remote implementation branch no longer exists
   or reports that it was already absent.
4. The runner completes the post-merge tracker and local cleanup checks for the
   item.

**Postconditions**: The item reaches its merged terminal state without leaving
the implementation branch on the remote.

**Information shown**:

- The merged implementation PR and branch name.
- The remote branch cleanup result: deleted, already absent, skipped with a
  named reason, or failed.
- The final tracker and cleanup state for the item.

**Actions available**:

- Continue cleanup when the branch was deleted or already absent.
- Stop and report a cleanup failure when the branch cannot be safely deleted.

**Considerations**:

- Cleanup must happen only after the implementation PR is confirmed merged.
- The cleanup path must not delete branches for unmerged PRs.
- The behavior applies to full-pipeline items even though their earlier spec and
  plan PR branches follow a different lifecycle.

### Use Case 2: Single-stage implementation cleanup remains unchanged

**Actor**: Work Item Runner operating on a fast-track or implementation-only
item.
**Preconditions**: A single-stage implementation PR has merged and the workflow
is entering terminal cleanup.

**Steps**:

1. The runner verifies that the implementation PR is merged.
2. The runner performs the existing implementation-branch cleanup sequence.
3. The runner reports the cleanup and tracker outcome.

**Postconditions**: Existing single-stage cleanup behavior remains intact while
multi-stage cleanup is brought into parity with it.

**Information shown**:

- The merged implementation PR and branch name.
- The same cleanup result categories used for multi-stage runs.

**Actions available**:

- Continue cleanup after a successful or already-complete branch deletion.
- Report a safe cleanup failure without masking the issue.

**Considerations**:

- This feature should close the multi-stage gap without weakening the already
  working single-stage path.

### Use Case 3: Portfolio scan finds stale branch evidence

**Actor**: Portfolio Orchestrator or workflow operator running a portfolio scan.
**Preconditions**: The repository has workflow branches from prior item runs,
including merged spec, plan, or implementation PRs.

**Steps**:

1. The scan evaluates workflow branches by lifecycle category.
2. The scan treats merged spec and implementation-plan branches as
   expected-persistent unless another workflow rule marks them stale locally.
3. The scan treats a merged implementation PR with a still-present remote
   implementation branch as a cleanup problem.
4. The scan reports the cleanup problem with enough context for a human or
   runner to remediate it.

**Postconditions**: Operators can distinguish real implementation cleanup gaps
from acceptable spec and plan branch persistence.

**Information shown**:

- Branch category: expected-persistent spec/plan branch or expected-deleted
  implementation branch.
- Associated merged PR when available.
- Suggested cleanup action or rerun path when a stale implementation branch is
  found.

**Actions available**:

- Ignore expected-persistent spec and plan branches.
- Delete or otherwise remediate stale implementation branches after merge
  verification.
- Continue portfolio dispatch when the finding is informational and non-
  blocking according to the scan contract.

**Considerations**:

- Scan output should not create noise for branches that intentionally persist.
- Branch deletion remains a safety-sensitive action and must keep merge-state
  verification before destructive cleanup.

## Business Rules

- Implementation branches are `feature/*`, `fix/*`, `refactor/*`, and
  `hotfix/*` workflow branches.
- Spec branches and implementation-plan branches are not implementation
  branches and may remain on the remote after their PRs merge.
- A merged implementation PR must trigger the implementation-branch cleanup path
  regardless of whether the item was single-stage or multi-stage.
- Remote implementation branch deletion must happen only after the PR's merged
  state is confirmed.
- If the remote implementation branch is already absent, cleanup should be
  reported as already complete rather than as a failure.
- If branch deletion cannot be verified or safely completed, the runner must
  report the cleanup failure and avoid marking the cleanup as complete.
- Portfolio scans and audits must categorize workflow branches by expected
  lifecycle before surfacing stale-branch findings.
- The tracker terminal state for a merged implementation PR must remain tied to
  the implementation merge and cleanup path, not to the earlier spec or plan
  PRs.

## Operational Visibility

- **Runner summary**: The final run summary for a multi-stage item should show
  the implementation branch cleanup result alongside merge and tracker status.
- **Audit output**: Stale-branch checks should identify whether each branch is
  expected-persistent or expected-deleted.
- **Failure reporting**: When remote implementation branch deletion fails, the
  output should name the affected branch, associated PR when known, and the
  reason cleanup did not complete.
- **Regression coverage**: Test or audit coverage should exercise a multi-stage
  implementation merge path and verify that the implementation remote branch is
  not left dangling.

## Acceptance Criteria

- [ ] A full-pipeline item that completes spec, plan, and implementation PRs
      deletes the remote implementation branch after the implementation PR is
      confirmed merged.
- [ ] The implementation-stage terminal cleanup path uses the same observable
      cleanup guarantees for multi-stage runs as for single-stage implementation
      runs.
- [ ] The workflow never deletes a remote implementation branch unless the
      associated implementation PR is confirmed merged.
- [ ] If the remote implementation branch is already absent, the cleanup path
      reports that state as successful or already complete.
- [ ] Spec and implementation-plan branches are documented or classified as
      expected-persistent after merge and are not reported as missing
      implementation cleanup.
- [ ] Stale-branch scan or audit output flags merged implementation PRs whose
      remote implementation branches still exist.
- [ ] Stale-branch scan or audit output includes enough branch category and PR
      context for an operator to distinguish expected persistence from a cleanup
      regression.
- [ ] Cleanup failures are visible in runner output and do not silently produce a
      merged terminal summary that implies remote branch cleanup succeeded.
- [ ] Tests or workflow audit coverage verify the multi-stage branch cleanup
      behavior and the spec/plan versus implementation branch distinction.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Multi-stage item runners delete the remote implementation branch after implementation PR merge | AC1, AC2, AC3, AC4; Use Case 1 |
| 2. Terminal cleanup matches single-stage behavior | AC2; Use Cases 1 and 2 |
| 3. Spec and implementation-plan branches remain expected-persistent | AC5; Business Rules; Use Case 3 |
| 4. Stale-branch audit distinguishes expected-persistent from expected-deleted branches | AC6, AC7; Use Case 3; Operational Visibility |
| 5. Operators receive clear visibility for lingering implementation branches | AC6, AC7, AC8; Operational Visibility |
| 6. Regression coverage prevents recurrence | AC9; Operational Visibility |

## Out of Scope (MVP)

- Deleting remote spec or implementation-plan branches after their PRs merge.
- Changing the branch naming convention for workflow stages.
- Changing the tracker status mapping for merged spec, plan, or implementation
  PRs.
- Introducing a new workflow stage or a new branch category.
- Changing the human merge policy for this repository.
- Retrospectively deleting existing stale remote branches outside the verified
  cleanup or audit path.
