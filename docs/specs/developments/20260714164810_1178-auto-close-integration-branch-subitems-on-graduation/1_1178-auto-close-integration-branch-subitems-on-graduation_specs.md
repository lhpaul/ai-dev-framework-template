# Auto-Close Integration-Branch Sub-Items on Graduation - Spec

---

## Overview

When an epic uses an integration branch, each sub-item lands on
`develop-<slug>` before the integration branch graduates to `develop`. GitHub's
issue-closing keywords do not reliably close those sub-items at graduation time,
so operators can finish the delivery while the tracker still shows stale open
sub-items. This feature makes graduation closeout responsible for reconciling
the parent epic and its planned sub-items after the graduation PR merges.

The desired product outcome is that a completed integration-branch epic leaves
no phantom open planned work in the tracker. Operators should see which issues
were closed, which statuses were updated, and which optional or deferred items
still need a human disposition decision.

## Brief Objective List

Derived from issue #1178:

1. Prevent delivered planned integration-branch epic sub-items from remaining
   open after their graduation PR merges to `develop`.
2. Add a graduation closeout sweep after the graduation PR merge for issues
   referenced by PRs that merged into the integration branch.
3. For each delivered planned sub-item that is still open, close the issue and
   move its project status to the configured terminal delivery status.
4. Close the parent epic after the core deliverable has graduated.
5. Remove stale tracker state that creates phantom open work and blocks future
   planning queries.
6. Preserve human disposition for optional, deferred, or explicitly excluded
   sub-items instead of silently closing them.
7. Make the closeout result visible to the operator.
8. Leave the exact implementation mechanism for the implementation plan.

## Use Cases

### Use Case 1: Operator completes graduation closeout

**Actor**: Workflow operator.
**Preconditions**: The operator has explicit approval to graduate an integration
branch, the graduation PR from `develop-<slug>` to `develop` has merged, and the
workflow can identify the parent epic and planned sub-items.

**Steps**:

1. The operator runs the post-merge graduation closeout for the integration
   branch.
2. The workflow identifies the parent epic and every planned sub-item included
   in the graduated integration branch.
3. The workflow distinguishes planned delivered sub-items from optional,
   deferred, cancelled, or explicitly excluded sub-items.
4. The workflow closes every still-open planned delivered sub-item and updates
   its project status to the configured terminal delivery status.
5. After delivered planned sub-items are reconciled, the workflow closes the
   parent epic unless the operator has explicitly requested that it remain open.
6. The workflow reports the closeout results.

**Postconditions**: Delivered planned sub-items no longer appear as open
planning work after graduation. The parent epic is closed unless the operator
explicitly defers closure, in which case the closeout summary records that the
epic intentionally remains open.

**Information shown**:

- Integration branch slug and graduation PR number.
- Parent epic issue number and closeout result.
- Planned sub-item issue numbers, titles, source PRs when known, and closeout
  result.
- Optional, deferred, cancelled, skipped, or failed items with required next
  action.

**Actions available**:

- Accept the closeout summary.
- Manually resolve any item that could not be updated automatically.
- Decide the disposition of optional or deferred sub-items that remain open.

**Considerations**:

- Some sub-items may already be closed by tracker automation or manual operator
  action; the workflow should report them as already terminal instead of
  treating them as failures.
- A tracker update can fail independently from issue closure; the summary must
  distinguish these outcomes so the operator can repair only the failed part.
- The workflow must not close optional or deferred work merely because the
  integration branch graduated.

### Use Case 2: Portfolio scan no longer sees phantom open work

**Actor**: Portfolio orchestrator or template maintainer.
**Preconditions**: A previous integration-branch epic has graduated and closeout
has completed.

**Steps**:

1. The operator or orchestrator scans the portfolio for work that can advance.
2. The scan reads issue state and project status for the graduated epic and its
   sub-items.
3. Delivered planned sub-items are no longer returned as open actionable work.
4. Optional or deferred follow-up items remain visible only when their
   disposition intentionally keeps them open.

**Postconditions**: Planning queries reflect the real remaining work after
graduation.

**Information shown**:

- Graduated planned sub-items in a terminal state.
- Any intentionally open optional or deferred items, with their current labels
  or status.

**Actions available**:

- Continue planning from accurate tracker state.
- Route intentionally open follow-up items through normal workflow paths.

**Considerations**:

- The workflow should avoid reopening or moving terminal items backward.
- The terminal status label can vary by configured tracker; the product
  requirement is terminal delivery state, not one hard-coded provider label.

### Use Case 3: Closeout cannot safely update every item

**Actor**: Workflow operator.
**Preconditions**: The graduation PR has merged, but the workflow cannot close
or update one or more planned delivered items.

**Steps**:

1. The operator runs the graduation closeout.
2. The workflow closes and updates every item it can safely reconcile.
3. For each item it cannot reconcile, the workflow reports the issue number,
   attempted action, and reason the item still requires human repair.
4. The workflow leaves optional or unresolved-disposition items open and reports
   the required human choice.
5. If any delivered planned sub-item remains unreconciled, the workflow reports
   that parent epic closure is held until those failures are repaired or the
   operator explicitly defers epic closure.

**Postconditions**: Successfully reconciled items are terminal, and unresolved
items are clearly listed for human follow-up.

**Information shown**:

- Items successfully closed and moved to terminal status.
- Items already terminal before the sweep.
- Items skipped by rule, including optional or deferred work.
- Items that failed issue closure or status update.

**Actions available**:

- Retry closeout after fixing credentials, tracker access, or transient API
  failures.
- Close or update failed items manually.
- Choose the disposition of skipped optional or deferred items.

**Considerations**:

- Partial closeout should be visible and actionable; it should not silently
  report graduation cleanup as complete.
- A failure to close one sub-item should not undo successful closeout for other
  sub-items.

## Business Rules

- BR1: A successful integration-branch graduation closeout must leave every planned
  delivered sub-item in a terminal issue state and terminal project status.
- BR2: Terminal project status means the configured delivery-complete display label
  for the tracker, such as `Done` or `Released`.
- BR3: Already-terminal planned sub-items are valid closeout results only when
  both issue state and project status are already terminal; they must not be
  moved backward.
- BR4: The parent epic must be closed only after the core planned deliverable
  graduates and delivered planned sub-items are reconciled, unless the operator
  explicitly defers epic closure.
- BR5: Optional, deferred, cancelled, or explicitly excluded sub-items must not be
  silently closed as part of the planned-delivery sweep.
- BR6: Issues referenced by sub-item PRs merged into the integration branch must be
  considered during closeout when those references are available.
- BR7: The workflow must surface optional or deferred items that remain open so the
  operator can reassign, defer, or close them intentionally.
- BR8: The closeout must be repeatable: rerunning it after a partial failure should
  close or update only the items that still need reconciliation.
- BR9: The closeout summary must distinguish closed, already terminal, skipped, and
  failed items.
- BR10: The graduation workflow must not rely on GitHub default-branch auto-close
  behavior as the only way planned sub-items become terminal.

## Statuses / Enum Values

| Code value | Display label | Description |
| ---------- | ------------- | ----------- |
| `delivered_terminal` | Done or Released | The tracker's configured terminal delivery status for a planned item whose work graduated to `develop`. |
| `already_terminal` | Already terminal | The issue was already closed and the project item was already in terminal delivery status before the sweep. |
| `skipped_optional` | Skipped - optional/deferred | The item was intentionally left open because it is optional, deferred, cancelled, or explicitly excluded from the graduation. |
| `failed` | Failed | The workflow could not close the issue or update its project status and human repair is required. |

**Valid transitions**:

- Open planned delivered sub-item -> Done or Released after the graduation PR is
  merged and closeout confirms the item was included in the core deliverable.
- Open parent epic -> Done or Released after the graduation PR is merged and
  planned delivered sub-items have been reconciled, unless the operator defers
  epic closure.
- Optional or deferred sub-item -> Skipped - optional/deferred when it is not
  part of the graduated core deliverable.
- Any item requiring manual repair -> Failed when issue closure or tracker
  status update cannot be completed.

## Operational Visibility

- **Closeout summary**: Graduation closeout must report the integration branch,
  graduation PR, parent epic, planned sub-items, and final result for each item.
- **Tracker visibility**: Delivered planned sub-items must no longer appear as
  open actionable work after successful closeout. The parent epic must also be
  closed unless the operator explicitly defers epic closure and the summary
  records that decision.
- **Human follow-up visibility**: Failed, optional, deferred, cancelled, or
  explicitly excluded items must be listed with the human action needed.
- **Audit trail**: The workflow should leave enough issue or PR-visible evidence
  for a later operator to understand which graduation closed which planned
  sub-items.

## Acceptance Criteria

- [ ] AC1: After a graduation PR from `develop-<slug>` to `develop` merges, the
      graduation closeout identifies the parent epic and all planned sub-items
      included in the graduated integration branch, including issues referenced
      by sub-item PRs merged into that integration branch when those references
      are available.
- [ ] AC2: If a planned delivered sub-item is still open after graduation
      closeout starts, the workflow closes it and moves its project status to
      the configured terminal delivery status.
- [ ] AC3: If a planned delivered sub-item is already closed and already in a
      terminal delivery status, the workflow reports it as already terminal and
      does not move it backward.
- [ ] AC3a: If a planned delivered sub-item is closed but its project status is
      not terminal, the workflow updates the project status before reporting the
      item as reconciled.
- [ ] AC4: The parent epic is closed after the core deliverable graduates and
      delivered planned sub-items are reconciled, unless the operator explicitly
      defers epic closure.
- [ ] AC5: Optional, deferred, cancelled, or explicitly excluded sub-items remain
      open unless the operator chooses a terminal disposition for them.
- [ ] AC6: The closeout summary lists closed, already terminal, skipped, and
      failed items separately, including issue numbers and enough context for
      manual follow-up.
- [ ] AC7: If an issue closure or project-status update fails for one item, the
      workflow still reports successful updates for other items and lists the
      failed item for retry or manual repair.
- [ ] AC8: Rerunning graduation closeout after a partial failure reconciles only
      the still-open, closed-but-non-terminal, or otherwise non-terminal planned
      delivered items and treats previously fully reconciled items as already
      terminal.
- [ ] AC9: A portfolio scan after successful closeout does not return delivered
      planned sub-items as open actionable work.
- [ ] AC10: The accepted implementation documents whether it satisfies closeout
      by explicit post-merge sweep, graduation PR close references, or another
      mechanism that provides the same observable tracker outcome.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Prevent sub-items from remaining open after graduation | BR1, BR10, AC1, AC2, AC9 |
| 2. Add post-graduation closeout for issues referenced by integration-branch PRs | Use Case 1, BR1, BR6, AC1, AC10 |
| 3. Close still-open sub-items and set terminal status | BR1, BR2, AC2, AC3, AC3a, AC8 |
| 4. Close the parent epic | BR4, AC4 |
| 5. Remove phantom open work from planning queries | Use Case 2, AC9 |
| 6. Preserve human disposition for optional or deferred items | BR5, BR7, AC5 |
| 7. Make the closeout result visible | Operational Visibility, AC6, AC7 |
| 8. Defer exact mechanism to implementation plan | AC10, Out of Scope |

## Out of Scope (MVP)

- Choosing the exact implementation mechanism, including whether closeout is a
  post-merge sweep, graduation PR close references, an extension of existing
  cleanup tooling, or another equivalent implementation.
- Changing GitHub's native issue-closing behavior.
- Automatically closing optional, deferred, cancelled, or explicitly excluded
  sub-items without an operator disposition decision.
- Changing how sub-items are created, labeled, or linked before graduation.
- Changing the requirement that humans explicitly approve integration-branch
  graduation before the graduation PR is opened or merged.
