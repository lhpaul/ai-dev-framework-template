# Prevent False Dependencies From Keyword Overlap - Spec

---

## Overview

Workflow orchestration should not infer that one work item depends on another
only because both issues use similar surface terminology. When a batch contains
items with shared keywords, the orchestrator should preserve any
human-confirmed design decision for each item and make the item relationship
explicit before dispatching spec work. The expected result is fewer incorrect
prerequisite assumptions, less human mid-run correction, and cleaner specs and
plans for orthogonal work.

## Brief Objective List

Derived from issue #1182:

1. Prevent the orchestrator from treating shared surface terms between issues as
   sufficient dependency evidence.
2. Before dispatching spec work on a Backlog item, check whether the current
   session already contains a human-confirmed design decision for that item.
3. Summarize any relevant human-confirmed design decision in the spec-dispatch
   prompt.
4. When another in-scope item shares terminology with the item being dispatched,
   require the orchestrator to state the relationship explicitly as dependent,
   orthogonal, or unclear before dispatch.
5. If the relationship is orthogonal, avoid adding false dependency context to
   the dispatched spec work.
6. If the relationship is unclear or cannot be supported by concrete evidence,
   stop for human clarification instead of guessing.
7. Keep the exact data model, matching algorithm, and implementation mechanism
   decisions for the implementation plan.

## Use Cases

### Use Case 1: Orchestrator preserves a human-confirmed design decision

**Actor**: Work item runner or portfolio orchestrator.
**Preconditions**: A batch or single-item run is about to dispatch spec work for
a tracker item, and the current session or issue discussion contains a
human-confirmed design decision for that same item.

**Steps**:

1. The orchestrator reviews the item context before dispatching spec work.
2. The orchestrator identifies a human-confirmed design decision that applies to
   the selected item.
3. The orchestrator includes a concise summary of that decision in the
   spec-dispatch context.
4. The spec writer uses that decision as a product constraint while writing the
   spec.

**Postconditions**: The spec writer receives the confirmed decision before
drafting begins, reducing the risk of a spec built around a corrected or rejected
assumption.

**Information shown**:

- The selected item number, title, and brief.
- The confirmed design decision, including the source context when available.
- Any known relationship to other in-scope items.

**Actions available**:

- Dispatch spec work with the confirmed decision included.
- Stop for human clarification if the decision appears contradictory or does not
  clearly apply to the selected item.

**Considerations**:

- A design decision should be treated as confirmed only when it is clearly
  attributable to a human correction, human approval, or issue comment that
  records the intended product behavior.
- The dispatch context should stay concise and should not turn plan-stage
  technical choices into spec-stage requirements.

### Use Case 2: Orchestrator handles shared terminology across in-scope items

**Actor**: Portfolio orchestrator.
**Preconditions**: A bounded batch includes two or more in-scope items whose
briefs share notable terminology, such as a product area name, component family,
workflow phrase, or domain phrase.

**Steps**:

1. Before dispatching spec work for an item, the orchestrator checks whether any
   other in-scope item shares terminology with it.
2. For each meaningful overlap, the orchestrator states the relationship as
   Dependent, Orthogonal, or Unclear.
3. The orchestrator bases a Dependent relationship on concrete evidence such as
   an explicit issue reference, ordered requirement, shared acceptance criterion,
   or human-confirmed prerequisite.
4. The orchestrator treats surface keyword overlap without concrete evidence as
   insufficient to declare a dependency.
5. The orchestrator includes only relevant relationship context in the
   spec-dispatch prompt.

**Postconditions**: Spec work begins with an explicit relationship statement and
without a false prerequisite created from keyword overlap alone.

**Information shown**:

- Other in-scope items with meaningful terminology overlap.
- The relationship outcome for each overlap: Dependent, Orthogonal, or Unclear.
- The evidence used for the relationship outcome.

**Actions available**:

- Dispatch spec work when the relationship is Dependent with evidence or
  Orthogonal.
- Stop for human clarification when the relationship is Unclear and could alter
  product scope.

**Considerations**:

- Shared product-area language is common in batches and should not be treated as
  dependency proof.
- Relationship evidence should be explainable in product terms, not hidden in
  internal model reasoning.

### Use Case 3: Orchestrator stops instead of guessing on unclear relationships

**Actor**: Work item runner or portfolio orchestrator.
**Preconditions**: An in-scope item appears related to another item, but the
available issue context does not show whether one item is a prerequisite, whether
the items are orthogonal, or whether a prior human decision resolves the
question.

**Steps**:

1. The orchestrator detects that the relationship could change the product scope
   of the spec being dispatched.
2. The orchestrator records the relationship as Unclear.
3. The orchestrator stops before dispatch and asks for a concrete human decision
   about the item relationship.

**Postconditions**: The run avoids producing a spec or plan based on an
unsupported dependency assumption.

**Information shown**:

- The items involved.
- The overlapping terms or signals that caused the uncertainty.
- The missing decision needed to proceed.

**Actions available**:

- Human confirms the items are dependent and names the dependency.
- Human confirms the items are orthogonal.
- Human provides a narrower design decision for one item.

**Considerations**:

- The orchestrator should stop only when the unclear relationship could change
  the dispatched item's product scope, ordering, or constraints.
- Low-impact terminology overlap can be recorded as Orthogonal when the item
  briefs clearly describe separate outcomes.

## Business Rules

- Shared terminology between issues must not be sufficient by itself to mark one
  item as a dependency of another.
- A Dependent relationship must cite concrete evidence, such as an explicit
  issue reference, ordered requirement, shared acceptance criterion, required
  output from another item, or human-confirmed prerequisite.
- An Orthogonal relationship means the items may share words or a product area
  but can be specified independently without requiring the other item to be
  designed, implemented, or merged first.
- An Unclear relationship means the available context is insufficient and the
  relationship could change product scope, ordering, or constraints.
- When a human-confirmed design decision exists for the selected item, it must
  be included in the spec-dispatch context before the spec writer starts.
- When a relevant human-confirmed design decision conflicts with inferred
  dependency context, the human-confirmed decision wins unless a newer human
  correction supersedes it.
- The orchestrator must stop for human clarification when an Unclear
  relationship could affect the spec's objective, dependencies, acceptance
  criteria, or out-of-scope boundaries.
- The spec stage must describe the expected workflow behavior and evidence
  requirements; exact matching mechanics, data structures, and implementation
  algorithms are deferred to the implementation plan.

## Operational Visibility

- **Run output**: When shared terminology is detected between in-scope items,
  the orchestrator shows the relationship outcome and supporting evidence in
  the run summary or dispatch context.
- **Dispatch context**: The spec-dispatch prompt includes any applicable
  human-confirmed design decision and any relevant Dependent, Orthogonal, or
  Unclear relationship statement.
- **Stop message**: If the relationship is Unclear and blocks dispatch, the
  orchestrator names the affected items and the concrete human decision needed
  to continue.

## Relationship Outcomes

| Outcome | Display label | Description |
| ------- | ------------- | ----------- |
| Dependent | Dependent | One item requires another item's outcome or confirmed design before the selected item can be specified correctly. |
| Orthogonal | Orthogonal | Items share terminology or product area but can be specified independently. |
| Unclear | Unclear | Available context does not establish dependency or independence, and the ambiguity could affect product scope. |

**Valid transitions**:

- Unclear -> Dependent when a human confirms the dependency or the issue context
  provides concrete dependency evidence.
- Unclear -> Orthogonal when a human confirms independence or the issue context
  shows separate objectives with no ordering requirement.
- Dependent -> Orthogonal when a newer human-confirmed decision corrects the
  prior dependency assumption.
- Orthogonal -> Dependent when a newer human-confirmed decision or issue update
  introduces a real prerequisite.

## Acceptance Criteria

- [ ] AC-1: In a batch where two items share product-area terminology but have
  no concrete dependency evidence, the orchestrator records the relationship as
  Orthogonal or asks for clarification; it does not mark either item as a
  prerequisite based on keywords alone.
- [ ] AC-2: When the selected item has a human-confirmed design decision in the
  current session or issue discussion, the spec-dispatch context includes a
  concise summary of that decision before spec writing begins.
- [ ] AC-3: When the orchestrator marks two in-scope items as Dependent, the run
  output or dispatch context includes the concrete evidence supporting that
  relationship.
- [ ] AC-4: When a relationship is Unclear and could change the selected item's
  product scope, ordering, dependencies, acceptance criteria, or out-of-scope
  boundaries, the orchestrator stops before dispatch and asks for the missing
  human decision.
- [ ] AC-5: The spec-dispatch context for an Orthogonal relationship does not
  tell the spec writer to assume a dependency, prerequisite, shared data model,
  or shared implementation path.
- [ ] AC-6: A scenario matching the issue #1182 example is handled correctly:
  an item about an internal state switcher within one component instance is not
  treated as dependent on a separate item about allowing multiple component
  instances only because both mention the same public-site component area.
- [ ] AC-7: The behavior is testable through workflow-level verification that
  covers Dependent, Orthogonal, and Unclear outcomes.
- [ ] AC-8: The implementation plan decides the exact data model, matching
  algorithm, persistence approach, and helper boundaries; the spec does not
  require a specific implementation mechanism.

## Coverage Matrix

| Brief objective | Covered by |
| --------------- | ---------- |
| 1. Prevent the orchestrator from treating shared surface terms between issues as sufficient dependency evidence. | Business Rules; AC-1; AC-5; AC-6 |
| 2. Before dispatching spec work on a Backlog item, check whether the current session already contains a human-confirmed design decision for that item. | Use Case 1; Business Rules; AC-2 |
| 3. Summarize any relevant human-confirmed design decision in the spec-dispatch prompt. | Use Case 1; Operational Visibility; AC-2 |
| 4. When another in-scope item shares terminology with the item being dispatched, require the orchestrator to state the relationship explicitly as dependent, orthogonal, or unclear before dispatch. | Use Case 2; Relationship Outcomes; AC-1; AC-3; AC-4; AC-7 |
| 5. If the relationship is orthogonal, avoid adding false dependency context to the dispatched spec work. | Use Case 2; Business Rules; AC-5; AC-6 |
| 6. If the relationship is unclear or cannot be supported by concrete evidence, stop for human clarification instead of guessing. | Use Case 3; Business Rules; AC-4 |
| 7. Keep the exact data model, matching algorithm, and implementation mechanism decisions for the implementation plan. | Business Rules; AC-8; Out of Scope |

## Out of Scope (MVP)

- Choosing or specifying the exact matching algorithm, prompt structure, data
  model, persistence format, or helper-script interface.
- Implementing automatic cross-repository dependency analysis beyond the
  currently dispatched batch or item context.
- Changing the meaning of existing tracker dependency fields, GitHub issue
  links, or project-board fields.
- Writing the implementation plan or implementation for this behavior in the
  spec PR.

## Deferral Notes

- **Objective deferred**: Exact data model, matching algorithm, and
  implementation mechanism decisions.
  **Rationale**: The batch checkpoint explicitly accepted plan-stage handling
  for data, model, and algorithm choices. The spec captures product and workflow
  requirements only.
  **Human confirmation requested**: No; this deferral follows the accepted
  checkpoint for this item.
