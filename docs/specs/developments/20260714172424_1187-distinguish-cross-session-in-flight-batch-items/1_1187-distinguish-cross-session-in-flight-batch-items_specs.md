# Distinguish Cross-Session In-Flight Items in Run-Work Batch Proposals - Spec

---

## Overview

`/run-work` scan output should help the operator distinguish portfolio context
from the decision being requested in the current session. When a scan finds
cross-session items already in progress, items waiting for human merge, or items
otherwise being handled elsewhere, those items are useful context but should not
look like the proposed start batch. The report should label informational items
separately from Backlog items that need the operator's current approval and from
resume work that can advance in the current run.

This change keeps `/run-work` scan-and-propose behavior read-only while making
the proposal easier to act on. Operators should be able to read the report once
and know which items are merely being shown for awareness, which resume items
can advance now, which Backlog items they can approve now, and which command or
approval action will start the proposed batch.

## Brief Objective List

Derived from issue #1187:

1. Identify the confusion caused when `/run-work` reports cross-session
   in-flight items alongside a proposed Backlog start batch without explaining
   their different meanings.
2. Label cross-session in-flight or review-waiting portfolio items as
   informational context, not as items awaiting the current session's decision.
3. Label proposal-eligible Backlog items as the proposed batch that requires
   the operator's current decision.
4. Preserve useful portfolio awareness by still showing cross-session in-flight
   items when they affect context, capacity, or ordering.
5. Make the scan output and `/run-work` batch proposal report immediately clear
   about what action, if any, the operator can take now.
6. Cover Protocol 90 Step 2 scan output and the `/run-work` batch proposal
   report surface.

## Use Cases

### Use Case 1: Operator reviews a mixed portfolio scan

**Actor**: Workflow operator running `/run-work`.
**Preconditions**: The portfolio contains at least one in-flight or
review-waiting item from another session, and at least one Backlog item that can
be proposed for the current session.

**Steps**:

1. The operator invokes `/run-work` with no target.
2. The scan builds a portfolio map containing in-flight context, any
   current-session resume work, and proposal-eligible Backlog work.
3. The report presents cross-session or waiting items under an informational
   marker.
4. The report presents Backlog items under a proposed-batch marker.
5. The report states the current decision requested from the operator.

**Postconditions**: The operator can tell which items are already being handled
elsewhere and which items are awaiting approval in the current session.

**Information shown**:

- Informational in-flight items with item number, title, current workflow state,
  and why they are not actionable in this `/run-work` decision.
- Current-session resume items, when present, with item number, title, current
  workflow state, and next action.
- Proposed Backlog batch items with item number, title, priority, type, next
  stage, and parallelization notes.
- The exact action requested from the operator for the proposed batch.

**Actions available**:

- Approve or decline the proposed Backlog batch.
- Invoke the recommended execution command for the proposed batch.
- Ignore informational items unless the report names a separate human action
  outside the current proposal.

**Considerations**:

- Items already waiting for human review or merge may still matter as portfolio
  context, but they must not appear to be part of the proposed start batch.
- Resume work that can advance in the current session must not be mislabeled as
  informational.
- The report should not require the operator to infer intent from batch numbers
  alone.

### Use Case 2: Operator sees only cross-session or waiting items

**Actor**: Workflow operator running `/run-work`.
**Preconditions**: The portfolio has cross-session in-flight, review-waiting, or
merge-waiting items, but no current-session resume work and no safe Backlog
start batch can be proposed.

**Steps**:

1. The operator invokes `/run-work` with no target.
2. The scan reports the cross-session or waiting items as informational context.
3. The report states that no current-session start decision is being requested.
4. If a human action exists outside the current session, such as reviewing or
   merging an existing PR, the report names that action separately.

**Postconditions**: The operator understands that `/run-work` did not propose a
new batch and that any listed cross-session or waiting items are not queued for
current-session dispatch.

**Information shown**:

- Informational items with their current state and non-actionable reason.
- A clear no-proposal statement when no Backlog start batch is available.
- Any separate human-review or merge handoff when applicable.

**Actions available**:

- Review or merge existing PRs through the appropriate workflow.
- Re-run `/run-work` later after the current in-flight work changes state.
- Take no action when the scan is informational only.

**Considerations**:

- "No proposed start batch" should be distinct from "no portfolio activity".
- Existing PR review or merge work should not be disguised as a Backlog start
  decision.

### Use Case 3: Operator approves a proposed Backlog batch

**Actor**: Workflow operator approving work after a `/run-work` scan.
**Preconditions**: The scan has presented one or more Backlog items under the
proposed-batch marker.

**Steps**:

1. The operator reviews the proposed-batch section.
2. The operator confirms that the listed Backlog items should start in the
   current session.
3. The operator invokes the recommended bounded execution command, or gives the
   explicit approval required by the workflow surface.
4. Execution proceeds only for the proposed items that were approved.

**Postconditions**: The approved items can move into their workflow stages
without accidentally including informational cross-session items.

**Information shown**:

- Proposed item list and recommended execution command.
- Any held items or dependency reasons that prevented inclusion.
- A reminder that informational items are excluded from the current approval.

**Actions available**:

- Approve the proposed batch exactly as listed.
- Decline or narrow the proposed batch.
- Ask for a revised scan or proposal.

**Considerations**:

- Approval of the proposed batch must not be ambiguous about whether it includes
  informational items.
- Cross-session in-flight items remain outside the current bounded execution
  scope unless the human explicitly expands scope through a separate command.

### Use Case 4: Maintainer verifies the `/run-work` report contract

**Actor**: Template maintainer or reviewer.
**Preconditions**: A workflow change updates Protocol 90 or user-facing
`/run-work` guidance.

**Steps**:

1. The maintainer reviews the scan output contract for informational and
   proposed-batch categories.
2. The maintainer verifies that the proposed-batch section asks for a current
   decision only for proposal-eligible Backlog items.
3. The maintainer verifies that command, skill, and protocol guidance use the
   same labels and meaning.
4. The maintainer verifies smoke-test or documentation coverage for a mixed
   portfolio scan.

**Postconditions**: Future workflow changes preserve the distinction between
cross-session context and current-session decisions.

**Information shown**:

- Consistent display labels for informational and proposed-batch records.
- Coverage proving that mixed scan output remains unambiguous.
- Any intentional deferrals or non-goals for deeper scheduler changes.

**Actions available**:

- Approve the workflow documentation and behavior update.
- Request fixes if any report surface still mixes informational and
  decision-eligible items without a label.

## Business Rules

- `/run-work` scan-only mode remains read-only: it may report a proposal but
  must not mutate tracker state, create branches, open PRs, or dispatch work.
- A portfolio item that is already being handled by another session, waiting for
  human review or merge, or otherwise outside the current command's actionable
  scope is informational.
- A resume item whose next deterministic action can advance in the current
  session must be labeled as actionable resume work, not informational context.
- Proposal-eligible Backlog items are the only items that may be presented as
  awaiting the operator's current start decision in a `/run-work` scan.
- The proposed-batch section must list the exact Backlog items included in the
  current start decision and must exclude informational and actionable-resume
  items.
- Informational items may still be shown when they explain portfolio capacity,
  dependency order, active parallel work, or human review/merge queues.
- The report must not rely on batch numbering alone to communicate
  actionability.
- When no Backlog start batch is proposed, the report must say so directly
  rather than presenting only informational items.
- The same display labels and meanings must be used across Protocol 90 scan
  output, `/run-work` command guidance, and Codex skill guidance that describes
  batch proposals.

## UX Rules

- Use a clear display marker for proposal-eligible items:
  `PROPOSED BATCH - your decision`.
- Use a clear display marker for current-session resume items:
  `ACTIONABLE RESUME - can advance now`.
- Use a clear display marker for cross-session or waiting items:
  `INFORMATIONAL - not actionable in this proposal`.
- When an informational item is waiting on a specific human action, the report
  may add a more specific reason, such as `waiting on human review` or `waiting
  on merge`, but it must still be visibly separate from the proposed batch.
- The proposed-batch section must appear near the approval or command guidance
  so the operator can see what they are approving.
- Informational sections must use wording that discourages accidental approval
  or dispatch, such as "shown for context" or "already handled elsewhere".
- Held or blocked Backlog items must be labeled separately from informational,
  actionable-resume, and proposed-batch items.

## Statuses / Enum Values

These are user-facing report categories, not tracker workflow statuses.

| Code value | Display label | Description |
| --- | --- | --- |
| `informational` | Informational - not actionable in this proposal | A portfolio item shown for awareness because it is waiting for review or merge, owned by another active session, or otherwise outside the current `/run-work` action or start decision. |
| `actionable_resume` | Actionable resume - can advance now | An already-started item whose next deterministic action can advance in the current run without being confused with a Backlog start proposal. |
| `proposed_batch` | Proposed batch - your decision | A Backlog item included in the current proposed start batch and awaiting operator approval or bounded execution. |
| `held` | Held - not included in proposed batch | A candidate item that was evaluated but not included because of dependency, priority, capacity, conflict, or ordering constraints. |

**Valid transitions**:

- An `informational` item can become `actionable_resume` only when the current
  run is allowed to advance it and it is no longer waiting on another session or
  human action.
- An `actionable_resume` item can become normal in-flight work after execution
  begins through the appropriate bounded workflow.
- An `informational` item can become `proposed_batch` only after it returns to a
  proposal-eligible Backlog state.
- A `proposed_batch` item becomes normal in-flight work only after the operator
  approves the proposal and execution begins through the appropriate bounded
  workflow.
- A `held` item can become `proposed_batch` in a later scan when the hold reason
  is gone or when the operator explicitly overrides the hold where the workflow
  allows it.

## Operational Visibility

- **Scan summary**: Shows separate sections for informational items,
  actionable-resume items, proposed-batch items, and held or blocked items when
  those categories are present.
- **Decision summary**: States exactly what the operator is being asked to
  approve, including the recommended command or confirmation path.
- **Review visibility**: Spec and implementation review should verify that
  mirrored command, agent, skill, and protocol guidance use the same report
  categories.
- **Regression visibility**: Workflow smoke-test or documentation coverage
  should include a mixed portfolio scan with at least one informational item and
  at least one proposed-batch item.

## Acceptance Criteria

- [ ] AC1: Given a `/run-work` no-target scan with both cross-session in-flight
      items and proposal-eligible Backlog items, the output separates them into
      informational and proposed-batch categories.
- [ ] AC2: Informational items use a display marker equivalent to
      `INFORMATIONAL - not actionable in this proposal` and include the reason
      they are not part of the current decision.
- [ ] AC3: Proposal-eligible Backlog items use a display marker equivalent to
      `PROPOSED BATCH - your decision` and include the item number, title,
      priority, type, next stage, and parallelization notes.
- [ ] AC4: The current start-decision text names only proposed-batch items as
      awaiting Backlog start approval.
- [ ] AC5: Given a scan with only cross-session in-flight, review-waiting, or
      merge-waiting items, the output says no Backlog start batch is currently
      proposed.
- [ ] AC6: Given held or blocked Backlog candidates, the output labels them
      separately from informational, actionable-resume, and proposed-batch items
      and states the hold reason.
- [ ] AC7: Approving or invoking the recommended command for the proposed batch
      cannot reasonably be read as approving informational items.
- [ ] AC8: Protocol 90 scan-output guidance and `/run-work` command or skill
      guidance use consistent names and meanings for informational,
      actionable-resume, proposed-batch, and held items.
- [ ] AC9: Workflow smoke-test or documentation coverage includes a mixed scan
      scenario that demonstrates the category distinction.
- [ ] AC10: Given a scan with current-session resume work, the output labels
      that work as actionable resume work rather than informational context or
      proposed Backlog start work.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Identify the confusion caused when mixed scan output lacks meaning labels. | Use Case 1, Business Rules, AC1, AC4, AC7 |
| 2. Label cross-session in-flight or review-waiting items as informational context. | Use Cases 1-2, UX Rules, Statuses, AC1, AC2, AC5, AC10 |
| 3. Label proposal-eligible Backlog items as the proposed batch requiring the current decision. | Use Cases 1 and 3, UX Rules, Statuses, AC3, AC4, AC7 |
| 4. Preserve portfolio awareness for cross-session in-flight items. | Use Cases 1-2, Business Rules, Operational Visibility, AC2, AC5 |
| 5. Make the report clear about what action the operator can take now. | Use Cases 1-3, UX Rules, Operational Visibility, AC4, AC7 |
| 6. Cover Protocol 90 Step 2 scan output and the `/run-work` proposal report surface. | Use Case 4, Business Rules, Operational Visibility, AC8, AC9, AC10 |

## PR-Visible Deferral Notes

No brief objectives are deferred. The full issue brief is covered by the
acceptance criteria above.

## Out of Scope (MVP)

- Changing how `/run-items` executes an explicitly approved bounded list.
- Changing tracker workflow statuses or adding new project-board fields.
- Automatically detecting which external human or session owns an in-flight
  item beyond the reason already available in the scan.
- Changing priority scoring, dependency resolution, or lane-cap behavior except
  where needed to label held items in the report.
- Changing merge authority, delegated review policy, or guardrails behavior.
- Starting, merging, or closing any item directly from `/run-work` scan-only
  mode.
