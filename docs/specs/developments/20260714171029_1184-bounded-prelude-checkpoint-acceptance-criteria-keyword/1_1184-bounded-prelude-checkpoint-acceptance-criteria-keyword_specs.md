# Bounded Prelude Acceptance Criteria Checkpoint Parsing - Spec

---

## Overview

Workflow operators need the bounded prelude to reserve product checkpoints for
issues that actually contain unresolved product ambiguity. A normal, populated
Acceptance Criteria section is expected evidence that a Backlog item is
well-structured, so its presence alone should not force an extra confirmation
round-trip before spec work can begin.

This feature recalibrates the checkpoint signal so well-structured Backlog items
can move through approved `/run-item`, `/run-items`, and `/run-epic` flows
without checkpoint fatigue. Ambiguous issue briefs must still stop for human
input when they contain unresolved product questions, placeholders, or empty
acceptance criteria.

## Brief Objective List

Derived from issue #1184:

1. Stop treating the phrase "acceptance criteria" by itself as an ambiguity
   signal for mandatory product checkpoints.
2. Preserve product checkpoints for genuinely ambiguous or unresolved Backlog
   items.
3. Allow complete, well-structured Backlog items with populated Acceptance
   Criteria sections to proceed without an unnecessary AskUserQuestion
   round-trip after policy confirmation.
4. Keep the bounded prelude signal trustworthy by reducing checkpoint fatigue.
5. Cover the downstream scenario where expected issue structure includes
   problem statement, goal, scope, proposed solution, and testable acceptance
   criteria.
6. Define how incomplete, empty, or placeholder acceptance criteria should be
   treated so they can still trigger a checkpoint.
7. Add verification coverage that distinguishes a populated Acceptance Criteria
   section from real ambiguity keywords or unresolved product markers.

## Use Cases

### Use Case 1: Approved batch starts a well-structured Backlog item

**Actor**: Workflow operator running an approved `/run-items` batch.
**Preconditions**: A Backlog item has a clear problem statement, goal, scope,
proposed solution, and populated Acceptance Criteria section.

**Steps**:

1. The operator approves the bounded batch policy for the selected item list.
2. The work item runner evaluates the item's brief before starting the spec
   stage.
3. The runner sees the Acceptance Criteria section as normal issue structure,
   not as standalone evidence of product ambiguity.
4. The item proceeds into the next workflow stage without an additional product
   checkpoint prompt.

**Postconditions**: The item can advance through the approved workflow path
without a redundant AskUserQuestion round-trip.

**Information shown**:

- The selected policy summary from the bounded prelude or batch approval.
- The item's normal stage progression and terminal state.

**Actions available**:

- Continue the approved workflow run.
- Stop for a checkpoint only when the issue contains a real ambiguity signal.

**Considerations**:

- This use case covers well-written Backlog briefs where acceptance criteria are
  populated and testable.
- Batch approval remains the confirmation source for allowed backlog starts and
  delegated review policy.

### Use Case 2: Ambiguous Backlog item still requires product input

**Actor**: Workflow operator starting or approving a workflow item.
**Preconditions**: A Backlog item contains unresolved product language,
placeholder acceptance criteria, or an empty Acceptance Criteria section.

**Steps**:

1. The workflow evaluates the item brief before mutation.
2. The ambiguous or incomplete part of the brief is detected.
3. The workflow presents a product checkpoint that names the reason the item is
   not ready to start autonomously.
4. The operator answers the checkpoint, revises the item, or stops the run.

**Postconditions**: The workflow does not proceed past a real product ambiguity
without human confirmation or issue cleanup.

**Information shown**:

- The checkpoint reason in product language.
- The affected item and the human action needed to unblock the run.

**Actions available**:

- Confirm the intended scope.
- Update the issue brief.
- Stop and leave the item in its current tracker state.

**Considerations**:

- The feature should not weaken protection for unclear, incomplete, or
  placeholder issue briefs.
- Empty or placeholder acceptance criteria are different from a populated
  Acceptance Criteria section.

### Use Case 3: Maintainer verifies checkpoint behavior

**Actor**: Template maintainer reviewing or testing workflow behavior.
**Preconditions**: The workflow has examples of well-structured, ambiguous, and
incomplete Backlog briefs.

**Steps**:

1. The maintainer runs or reviews coverage for each brief shape.
2. A populated Acceptance Criteria section does not create a product checkpoint
   by itself.
3. Real ambiguity markers still create a product checkpoint.
4. Empty or placeholder acceptance criteria create a checkpoint when they leave
   the product scope unverified.

**Postconditions**: The maintainer can confirm the bounded prelude distinguishes
normal issue structure from unresolved product ambiguity.

**Information shown**:

- Which brief shapes require checkpoints.
- Which brief shapes proceed after normal policy confirmation.
- Any reason text shown to operators when a checkpoint is required.

**Actions available**:

- Accept the workflow behavior.
- Request changes if the checkpoint signal is too noisy or too permissive.

**Considerations**:

- Verification should include the downstream issue structure described in the
  brief: problem statement, goal, scope, proposed solution, and testable
  acceptance criteria.

## Business Rules

- A populated Acceptance Criteria section must not trigger a product checkpoint
  solely because of its heading or phrase.
- Product checkpoints must still trigger for issue briefs that explicitly signal
  ambiguity, unresolved product decisions, open questions, or incomplete scope.
- Empty acceptance criteria must be treated as incomplete product definition.
- Placeholder acceptance criteria must be treated as incomplete product
  definition.
- The checkpoint reason shown to the operator must identify the actual ambiguity
  or incompleteness, not merely the presence of an Acceptance Criteria section.
- Approved batch policy must continue to satisfy the normal confirmation gate
  for items in that batch when no unresolved product checkpoint remains.
- The workflow must preserve the existing stop-before-mutation behavior for
  unresolved product checkpoints.
- The behavior must apply consistently anywhere the shared bounded prelude or
  checkpoint recommender is used for item start decisions.

## Operational Visibility

- **Checkpoint summary**: When a checkpoint is required, the summary should
  name the concrete ambiguous, unresolved, empty, or placeholder signal that
  caused it.
- **No-checkpoint path**: For a complete issue brief, the workflow should
  proceed without adding a product checkpoint solely due to the Acceptance
  Criteria heading.
- **Review visibility**: Spec, plan, and implementation reviewers should be able
  to trace the distinction between "has acceptance criteria" and "has
  incomplete acceptance criteria" through acceptance criteria and tests.
- **Downstream confidence**: Downstream teams using standard issue templates
  should see fewer redundant checkpoint prompts for complete Backlog items.

## Acceptance Criteria

- [ ] **AC1**: A Backlog item with a populated Acceptance Criteria section and
      no other ambiguity markers does not require a product checkpoint solely
      because the phrase "acceptance criteria" appears in the brief.
- [ ] **AC2**: A Backlog item that includes explicit unresolved product language
      still requires a product checkpoint before mutation.
- [ ] **AC3**: A Backlog item with an empty Acceptance Criteria section requires
      a product checkpoint that explains the criteria are incomplete.
- [ ] **AC4**: A Backlog item with placeholder acceptance criteria requires a
      product checkpoint that explains the criteria are incomplete.
- [ ] **AC5**: In an approved `/run-items` batch, a complete Backlog item with
      populated acceptance criteria can proceed after the batch policy
      confirmation without a second product checkpoint prompt.
- [ ] **AC6**: Checkpoint reason text distinguishes real ambiguity or
      incompleteness from normal issue-section headings.
- [ ] **AC7**: Verification coverage includes at least one complete downstream
      issue shape with problem statement, goal, scope, proposed solution, and
      testable acceptance criteria.
- [ ] **AC8**: Verification coverage includes at least one real ambiguity marker
      and at least one empty or placeholder acceptance-criteria case.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Stop treating the phrase "acceptance criteria" by itself as an ambiguity signal | Use Cases 1 and 3, Business Rules | AC1, AC6 |
| 2. Preserve checkpoints for genuinely ambiguous or unresolved items | Use Case 2, Business Rules | AC2, AC6 |
| 3. Allow complete Backlog items to proceed without an unnecessary AskUserQuestion round-trip | Use Case 1, Business Rules | AC1, AC5 |
| 4. Keep the bounded prelude signal trustworthy by reducing checkpoint fatigue | Overview, Operational Visibility | AC1, AC5, AC6 |
| 5. Cover the downstream well-structured issue scenario | Use Cases 1 and 3 | AC7 |
| 6. Define empty or placeholder acceptance-criteria handling | Use Case 2, Business Rules | AC3, AC4, AC8 |
| 7. Add verification coverage for populated criteria versus real ambiguity markers | Use Case 3 | AC7, AC8 |

## Out of Scope (MVP)

- Redesigning the full checkpoint policy model or adding new checkpoint stages.
- Changing backlog-start, delegated-review, or delegated-merge authority rules.
- Changing the required human confirmation behavior when a real product
  ambiguity remains.
- Replacing existing issue templates or requiring downstream projects to change
  their Acceptance Criteria heading.

## PR-Visible Deferral Notes

No brief objectives are deferred to out of scope.
