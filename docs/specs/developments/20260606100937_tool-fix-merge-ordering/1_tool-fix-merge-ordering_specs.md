# Tool-Fix Merge Ordering — Spec

---

## Overview

Parallel batches sometimes include more than one fix to the workflow tools that
run reviewer loops. Dispatch serialization alone is not enough when a dependent
tool-fix branch runs its own reviewer loop with still-broken tooling. This
feature adds explicit orchestration behavior for foundational tool-fixes: merge
the foundational fix first, then rebase and re-run dependent tool-fixes before
their readiness is trusted.

## Brief Objective List

1. Document the merge-ordering hazard for batches containing multiple tool-fixes
   that repair reviewer tooling.
2. Require the foundational reviewer-tool fix to merge before dependent
   tool-fixes are trusted.
3. Require dependent tool-fixes to be rebased onto the updated base and re-run
   through their reviewer loop after the foundational fix merges.
4. Reduce spurious escalations caused by dependent PRs reviewing themselves with
   known-broken reviewer tooling.
5. Keep the existing serialize-first dispatch rule, while extending it with
   merge-ordering guidance.

## Use Cases

### Use Case 1: Orchestrator detects a foundational reviewer-tool fix

**Actor**: Portfolio orchestrator
**Preconditions**: A batch contains two or more tool-fix items, and at least one
item repairs reviewer-loop or reviewer-action behavior used by another item.

**Steps**:

1. The orchestrator classifies the affected items as tool-fixes.
2. The orchestrator identifies which item is foundational because it repairs
   reviewer tooling that dependent items will invoke.
3. The orchestrator dispatches or reports the foundational item first.
4. The orchestrator holds dependent items until the foundational PR is merged.

**Postconditions**: Dependent tool-fix PRs do not rely on reviewer tooling that is
known to be broken on their branch or base.

**Information shown**:

- Foundational tool-fix item identifier.
- Dependent held item identifiers.
- Reason each dependent item is held.

**Actions available**:

- Merge the foundational PR once it is ready.
- Resume dependent items after the foundational fix is merged.

**Considerations**:

- The orchestrator must not auto-merge; human merge approval remains required.
- The rule applies only when the dependency affects tooling used by the
  dependent item's reviewer loop.

### Use Case 2: Dependent tool-fix is resumed after foundational merge

**Actor**: Work Item Runner or portfolio orchestrator
**Preconditions**: A foundational reviewer-tool fix has merged to the target base,
and a dependent tool-fix PR or branch exists.

**Steps**:

1. The runner updates the dependent branch from the target base.
2. The runner reruns the dependent item's reviewer loop and CI checks.
3. The runner accepts readiness only after the post-rebase loop is clean.

**Postconditions**: The dependent PR's readiness reflects the fixed reviewer
tooling state.

**Information shown**:

- The foundational PR that was merged first.
- Confirmation that the dependent branch was rebased or otherwise updated from
  the target base.
- The fresh reviewer-loop outcome after the update.

**Actions available**:

- Continue the dependent PR to human review if clean.
- Address fresh findings if the fixed reviewer tooling reports issues.
- Escalate only after the refreshed loop fails for substantive reasons.

**Considerations**:

- A previous escalation from the dependent branch may be stale if it occurred
  before the foundational fix merged.

## Business Rules

- The existing tool-fix serialize-first dispatch rule remains in force.
- When a tool-fix repairs reviewer tooling used by another tool-fix in the same
  batch, the repairing item is foundational for merge-ordering purposes.
- Dependent tool-fix items must be held until the foundational PR is merged.
- After the foundational PR merges, dependent branches must be updated from the
  target base before their reviewer-loop outcome is trusted.
- A dependent tool-fix that escalated before the foundational merge must be
  re-evaluated after updating from the target base.
- The orchestrator summary must explain which items were held and why.
- Human approval is still required for every PR merge.

## Operational Visibility

- **Batch summary**: Lists foundational tool-fix PRs, held dependent PRs, and the
  merge-ordering reason.
- **Resume summary**: Notes the foundational PR that was merged and the dependent
  branch update before the reviewer loop was rerun.
- **Escalation summary**: Distinguishes stale pre-foundational-fix escalations
  from substantive post-rebase reviewer findings.

## Acceptance Criteria

- [ ] AC1: Protocol 90 documents that dispatch serialization is insufficient
      when a dependent tool-fix needs reviewer tooling fixed by another item.
- [ ] AC2: Protocol 90 instructs the orchestrator to identify foundational
      reviewer-tool fixes in batches with multiple tool-fix items.
- [ ] AC3: Dependent tool-fix items are held until the foundational PR is merged.
- [ ] AC4: After the foundational PR merges, dependent branches are updated from
      the target base before reviewer-loop results are trusted.
- [ ] AC5: A dependent pre-merge reviewer-loop escalation is treated as stale
      until a post-foundational-merge loop has run.
- [ ] AC6: Batch summaries list held dependent items and their merge-ordering
      reason.
- [ ] AC7: The feature preserves the requirement for human approval before PR
      merge.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Document the merge-ordering hazard for batches containing multiple tool-fixes that repair reviewer tooling. | AC1, AC2 |
| Require the foundational reviewer-tool fix to merge before dependent tool-fixes are trusted. | AC2, AC3 |
| Require dependent tool-fixes to be rebased onto the updated base and re-run through their reviewer loop after the foundational fix merges. | AC4, AC5 |
| Reduce spurious escalations caused by dependent PRs reviewing themselves with known-broken reviewer tooling. | AC3, AC4, AC5 |
| Keep the existing serialize-first dispatch rule, while extending it with merge-ordering guidance. | AC1, AC6, AC7 |

## Out of Scope (MVP)

- Automatic PR merging without human approval.
- A full dependency graph solver for all workflow items.
- Changing reviewer-loop platform behavior or timeout budgets.
- Replacing existing file-level conflict detection.
