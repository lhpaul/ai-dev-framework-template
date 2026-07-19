# Bounded Prelude Base-Branch Resolver Label Scope - Spec

---

## Overview

Explicit-list `/run-items` batches need predictable base-branch selection before
any tracker, branch, or PR mutation begins. A stale or unrelated
`integration-branch:<slug>` label on one item must not redirect the whole batch
away from `develop`, especially when the inferred integration branch no longer
exists.

This change tightens the operator contract for bounded prelude base resolution:
mixed or partial integration labels fall back to `develop` with a visible
warning, and any selected integration branch must be confirmed to exist before
it is presented as the batch base. The result should make batch dispatch safe
without requiring humans to catch orphaned labels manually.

## Brief Objective List

Derived from issue #1204:

1. Prevent one item's `integration-branch:<slug>` label from determining the
   base branch for an entire explicit-list batch.
2. Treat mixed, partial, or conflicting integration labels in an explicit-list
   batch as a visible warning and use `develop` as the batch base.
3. Verify that any integration branch selected from labels exists on the remote
   before the bounded prelude adopts it.
4. Fall back to `develop` with a clearly visible warning when a selected
   integration branch does not exist.
5. Apply the remote-existence guard anywhere bounded prelude base resolution
   can select an integration branch, not only in the partial-label case.
6. Preserve the read-only bounded prelude contract and avoid tracker, branch,
   label, PR, or issue mutations during base resolution.
7. Provide test or smoke coverage for partial-label, stale-branch, and valid
   shared-label explicit-list scenarios.

## Use Cases

### Use Case 1: Operator starts an ordinary explicit-list batch

**Actor**: Workflow operator.
**Preconditions**: The operator invokes `/run-items` with two or more specific
items, and none of the items are intentionally running on a shared integration
branch.

**Steps**:

1. The bounded prelude reads the in-scope item metadata before any mutation.
2. The prelude evaluates integration-branch labels only within the explicit
   item list.
3. The prelude resolves the batch base as `develop`.
4. The operator reviews the policy summary and continues the batch under the
   approved scope.

**Postconditions**: The batch dispatches only the requested items and uses
`develop` as the shared base.

**Information shown**:

- The resolved item list.
- The selected base branch.
- The reason the base branch was selected.
- Any warnings that affected base selection.

**Actions available**:

- Confirm or stop the batch before mutation.
- Remove stale labels separately if the warnings reveal cleanup work.

**Considerations**:

- The prelude must not inspect labels outside the explicit item list as reasons
  to change the batch base.
- Ordinary explicit-list batches should not need the operator to audit every
  historical integration label manually.

### Use Case 2: One listed item carries an orphaned integration label

**Actor**: Workflow operator.
**Preconditions**: The operator invokes `/run-items` for multiple items, and
only one listed item carries an old `integration-branch:<slug>` label from a
graduated or abandoned integration branch.

**Steps**:

1. The bounded prelude detects that the integration label applies to only a
   subset of the explicit item list.
2. The prelude emits a visible warning naming the partial integration label and
   the affected item.
3. The prelude resolves the batch base as `develop`.
4. The operator can continue the batch or stop to clean up stale labels.

**Postconditions**: The batch is not redirected to an integration branch because
of a label that is not shared by the full explicit list.

**Information shown**:

- Which item or items carried the partial integration label.
- That the label was ignored for batch-base selection.
- That the selected base is `develop`.

**Actions available**:

- Continue with the direct-`develop` batch.
- Stop and remove the orphaned label outside the prelude.

**Considerations**:

- The warning is required even when fallback to `develop` is safe, because it is
  the operator's signal that tracker cleanup may still be needed.

### Use Case 3: All listed items share a valid integration label

**Actor**: Workflow operator.
**Preconditions**: Every item in the explicit list carries the same
`integration-branch:<slug>` label, and the corresponding integration branch
exists on the owning remote.

**Steps**:

1. The bounded prelude verifies that the label is shared by every listed item.
2. The prelude verifies that the corresponding integration branch exists.
3. The prelude presents the integration branch as the selected base with a
   clear reason.
4. The operator reviews and confirms the batch policy before mutation.

**Postconditions**: The batch can use the shared integration branch because the
full scope and branch existence are both confirmed.

**Information shown**:

- The shared integration label.
- The selected integration base.
- Confirmation that the branch existence check passed.

**Actions available**:

- Continue with the integration-branch batch.
- Stop and rerun with a different scope or policy.

**Considerations**:

- A shared label is not sufficient by itself; the remote branch must also exist.

### Use Case 4: Shared integration label points to a deleted branch

**Actor**: Workflow operator.
**Preconditions**: Every listed item carries the same integration label, but the
corresponding integration branch no longer exists on the owning remote.

**Steps**:

1. The bounded prelude verifies the shared label.
2. The prelude checks remote branch existence.
3. The prelude emits a visible warning that the labeled branch was not found.
4. The prelude resolves the batch base as `develop`.

**Postconditions**: A deleted integration branch cannot become the selected base
for the batch.

**Information shown**:

- The shared integration label.
- The missing integration branch name.
- That the base fell back to `develop`.

**Actions available**:

- Continue with `develop`.
- Stop and repair the tracker labels or recreate the integration branch outside
  the bounded prelude.

**Considerations**:

- The fallback must not silently hide the stale branch condition.

## Business Rules

- Explicit-list base resolution must consider only the items in the explicit
  list.
- An integration label must not select a batch base unless every item in the
  explicit list carries the same integration label.
- If integration labels are absent, partial, mixed, or conflicting, the bounded
  prelude must select `develop` for the explicit-list batch and emit a visible
  warning for any non-empty label set.
- Any integration branch selected from labels must be verified to exist on the
  owning remote before it is adopted as the base.
- If the integration branch existence check fails or finds no branch, the
  bounded prelude must select `develop` and emit a visible warning.
- The warning must name the reason for fallback: partial label coverage, mixed
  labels, conflicting labels, failed branch verification, or missing branch.
- Base-branch resolution must remain read-only: it must not create branches,
  remove labels, update tracker fields, open PRs, or close issues.
- The bounded prelude summary must expose the selected base and the reason for
  selection in operator-facing language.
- Single-item and epic-scoped workflows must not lose their existing
  integration-branch behavior, but they must also avoid adopting a non-existent
  integration branch silently.
- Batch dispatch must continue to enforce the approved explicit item list and
  must not use out-of-scope items to resolve the base.

## Operational Visibility

- **Policy summary**: The bounded prelude output shows the selected base branch,
  why it was selected, and whether any fallback warning was triggered.
- **Warning visibility**: Partial-label, mixed-label, branch-check failure, and
  missing-branch cases are printed prominently enough for the operator to see
  before confirming mutation.
- **Scope visibility**: Warnings identify the in-scope items that supplied
  integration labels, without implying any out-of-scope item can influence the
  batch.
- **Read-only visibility**: The summary continues to state that no tracker,
  branch, PR, label, issue, merge, or cleanup mutation has happened.
- **Review visibility**: Test or smoke evidence for the explicit-list resolver
  cases is included in the implementation PR so reviewers can verify the
  operator-facing contract.

## Acceptance Criteria

- [ ] In an explicit-list batch where no listed items have integration labels,
      the bounded prelude resolves the base as `develop`.
- [ ] In an explicit-list batch where only a subset of listed items carry an
      integration label, the bounded prelude resolves the base as `develop` and
      emits a visible partial-label warning.
- [ ] In an explicit-list batch where listed items carry different integration
      labels, the bounded prelude resolves the base as `develop` and emits a
      visible mixed-label warning.
- [ ] In an explicit-list batch where all listed items carry the same
      integration label and the corresponding branch exists, the bounded prelude
      may resolve the base as that integration branch and reports the successful
      branch validation.
- [ ] In an explicit-list batch where all listed items carry the same
      integration label but the corresponding branch does not exist, the bounded
      prelude resolves the base as `develop` and emits a visible missing-branch
      warning.
- [ ] If remote branch validation cannot complete, the bounded prelude does not
      adopt the integration branch silently and reports the validation failure in
      the pre-mutation summary.
- [ ] The bounded prelude does not create or delete branches, add or remove
      labels, update tracker status, open PRs, close issues, or perform cleanup
      while resolving the base.
- [ ] The operator-facing summary includes the selected base branch and the
      reason for that selection for explicit-list batches.
- [ ] Single-item or epic-scoped integration-branch resolution still respects
      valid integration labels, while preventing a missing remote branch from
      being adopted silently.
- [ ] Automated test or smoke coverage exercises no-label, partial-label,
      mixed-label, valid-shared-label, and stale-shared-label explicit-list
      scenarios.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Prevent one item's integration label from determining the whole batch base | AC2, AC3, BR1, BR2, BR10 |
| 2. Use `develop` plus warning for mixed, partial, or conflicting labels | AC2, AC3, BR3, BR6 |
| 3. Verify selected integration branch exists before adopting it | AC4, AC5, AC6, BR4 |
| 4. Fall back to `develop` with visible warning when the branch is missing | AC5, AC6, BR5, BR6 |
| 5. Apply remote-existence guard to any bounded prelude integration-base selection | AC9, BR4, BR9 |
| 6. Preserve read-only bounded prelude behavior | AC7, BR7, Operational Visibility |
| 7. Cover partial-label, stale-branch, and valid shared-label cases | AC10 |

## Out of Scope (MVP)

- Automatically removing orphaned `integration-branch:<slug>` labels from
  tracker items.
- Recreating deleted integration branches during bounded prelude execution.
- Changing the human-approved item list or adding related items to a batch.
- Changing merge authority, reviewer delegation, checkpoint policy, or risk
  classification behavior.
- Introducing a new tracker status or workflow stage.
- Rewriting the broader integration-branch graduation workflow.
