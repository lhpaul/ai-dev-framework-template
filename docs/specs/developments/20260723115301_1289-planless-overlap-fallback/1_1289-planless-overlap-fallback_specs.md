# Planless Batch Overlap Fallback — Spec

---

## Overview

The workflow must assess likely implementation overlap before dispatching
multiple items in parallel, even when one or more items do not yet have an
implementation plan. Existing plan-derived file-set evidence remains the
preferred source; this feature adds a best-effort fallback from the current work
item briefs so fast-track and otherwise planless items do not proceed in
parallel without an explicit overlap disposition.

## Actors

- **Batch operator**: reviews and approves a proposed multi-item batch.
- **Portfolio orchestrator**: assembles the batch, reports overlap evidence, and
  chooses parallel or serial dispatch according to the approved policy.
- **Work Item Runner**: executes an item only after the orchestrator has assigned
  it to a safe dispatch lane.

## Use Cases

### Use Case 1: Detect a concrete overlap between planless items

**Actor**: Portfolio orchestrator

**Preconditions**:

- A multi-item batch contains at least two implementation-stage items.
- At least one item has no usable plan-derived file set.
- The current item briefs contain the same specific implementation target, such
  as a file path, route, function, or explicitly named module.

**Steps**:

1. The orchestrator evaluates the available plan-derived evidence.
2. For every item without usable plan-derived evidence, it evaluates the current
   title and brief for specific implementation-target signals.
3. It compares the resulting signals across candidate item pairs.
4. It reports the concrete overlap and assigns the affected items to serial
   execution.

**Postconditions**:

- The overlapping items are not dispatched concurrently.
- The confirmation summary names the affected pair and the evidence supporting
  serialization.
- The later item waits until the earlier item has completed the required
  integration step and can start from the updated base.

**Information shown**:

- Both item identifiers.
- The shared implementation target or targets.
- The overlap confidence and resulting dispatch recommendation.

**Actions available**:

- Accept the serial order.
- Remove an item from the proposed batch.
- Clarify or re-scope an item before confirming the batch.

**Considerations**:

- A concrete shared route or function counts even when neither brief names a
  file path.
- Multiple concrete overlaps may form one serial group.

### Use Case 2: Review a suspected overlap

**Actor**: Batch operator

**Preconditions**:

- The orchestrator finds a meaningful but non-conclusive shared target between
  two planless items.
- The available evidence is insufficient to declare a concrete overlap or
  independence.

**Steps**:

1. The orchestrator identifies the suspected pair before dispatch.
2. The confirmation summary explains the shared signal and why it is not
   conclusive.
3. The operator explicitly confirms parallel execution or accepts the serial
   fallback.

**Postconditions**:

- Parallel dispatch occurs only after an explicit decision for the suspected
  pair.
- Without explicit confirmation, the pair is serialized.

**Information shown**:

- Both item identifiers.
- The signal that caused suspicion.
- The available choices and the default serial outcome.

**Actions available**:

- Confirm parallel execution.
- Choose serial execution.
- Re-scope or remove an item.

**Considerations**:

- Generic workflow terminology alone must not create a suspected overlap.
- A prior approval for another pair does not approve this pair.

### Use Case 3: Keep unrelated planless items parallel

**Actor**: Portfolio orchestrator

**Preconditions**:

- A multi-item implementation batch contains planless items.
- Their briefs name distinct targets or provide no meaningful shared target.

**Steps**:

1. The orchestrator evaluates plan-derived and fallback evidence.
2. It finds no concrete or suspected overlap between the items.
3. It reports that no actionable overlap was found and retains the items in
   parallel lanes, subject to all other workflow gates.

**Postconditions**:

- The new fallback does not serialize unrelated items.
- Existing capacity, dependency, tool-fix, and isolation rules remain in force.

**Information shown**:

- A concise no-actionable-overlap result for the proposed parallel group.

**Actions available**:

- Confirm the batch.
- Adjust the proposed scope for reasons unrelated to overlap.

**Considerations**:

- Missing evidence is not proof of independence; the summary must distinguish
  “no actionable overlap found” from “proven independent.”

## Business Rules

- **BR-1 — Evidence precedence**: Usable plan-derived file-set evidence is the
  preferred and higher-confidence source. The planless fallback supplements it
  and never replaces, weakens, or downgrades it.
- **BR-2 — Fallback scope**: The fallback evaluates current work item titles and
  briefs for specific file paths, route names, function names, and explicitly
  named modules.
- **BR-3 — Pairwise result**: Every meaningful candidate pair is classified as
  concrete overlap, suspected overlap, or no actionable overlap found.
- **BR-4 — Concrete overlap outcome**: A concrete overlap is serialized by
  default and cannot enter concurrent dispatch under the same batch approval.
- **BR-5 — Suspected overlap outcome**: A suspected overlap requires explicit
  human confirmation for parallel dispatch. Without that confirmation, the
  orchestrator uses the serial fallback.
- **BR-6 — Summary timing**: Concrete and suspected overlap evidence appears in
  the batch confirmation summary before any affected item is dispatched.
- **BR-7 — Decision scope**: A human decision applies only to the identified
  item pair and current batch proposal. It does not become a reusable waiver for
  future batches.
- **BR-8 — Avoid false positives**: Shared generic terminology without a
  specific implementation target does not create an overlap classification.
- **BR-9 — Serial handoff**: A serialized item starts only after the preceding
  item’s implementation PR is merged into the approved base and the later item
  can start from that updated base.
- **BR-10 — Existing gates preserved**: Relationship, dependency, lane-capacity,
  tool-fix, worktree-isolation, and nested-artifact gates continue to apply
  independently of this overlap fallback.

## Overlap and Dispatch Consistency Matrix

| Available evidence | Pair result | Confirmation summary | Required next action | Command surfaces |
| --- | --- | --- | --- | --- |
| Usable plan-derived file sets share a target | Concrete overlap | Name the pair and shared planned target | Serialize the pair | All supported multi-item batch entry points |
| No usable plan file set; briefs name the same specific path, route, function, or module | Concrete overlap | Name the pair and shared brief-derived target | Serialize the pair | All supported multi-item batch entry points |
| Brief-derived signals indicate a meaningful but non-conclusive shared target | Suspected overlap | Name the pair, signal, uncertainty, and choices | Require explicit parallel approval or use serial fallback | All supported multi-item batch entry points |
| Brief-derived targets are distinct, or only generic terminology overlaps | No actionable overlap found | Report no overlap action for the parallel group | Keep parallel eligibility; continue through other gates | All supported multi-item batch entry points |
| A plan-derived result and a fallback result disagree | Suspected overlap, unless the plan already proves a concrete overlap | Report both sources and identify plan evidence as higher confidence | Never downgrade a concrete plan overlap; otherwise require explicit parallel approval or use serial fallback | All supported multi-item batch entry points |

## Operational Visibility

- **Confirmation summary**: Shows each concrete or suspected item pair, the
  relevant evidence, its classification, and the required next action.
- **Batch result**: Preserves the overlap disposition so the final batch report
  can explain why an item ran in parallel, was serialized, or was held for a
  decision.
- **Human decisions**: Records explicit approval when a suspected pair is
  allowed to run in parallel.

## Brief Objective List

- **BO-1**: Derive best-effort overlap signals from issue-body file paths, route
  names, function names, and explicitly named modules when no plan file set is
  available.
- **BO-2**: Flag concrete and suspected pairs in the confirmation summary before
  parallel dispatch.
- **BO-3**: Serialize concrete overlaps by default; require explicit human
  confirmation for suspected overlaps or use the serial fallback.
- **BO-4**: Preserve the existing plan-derived file-set detector as the
  higher-confidence source.
- **BO-5**: Cover same-route, same-function, and unrelated planless item
  scenarios with automated verification.

## Acceptance Criteria

- **AC-1**: Given two planless implementation items whose briefs name the same
  route, the batch confirmation summary identifies the pair and the shared
  route as a concrete overlap before either item is dispatched.
- **AC-2**: Given two planless implementation items whose briefs name the same
  function, the batch confirmation summary identifies the pair and the shared
  function as a concrete overlap before either item is dispatched.
- **AC-3**: A pair classified as a concrete overlap is assigned to serial
  execution by default and is not dispatched concurrently under that batch
  approval; the later item starts from the approved base only after the earlier
  item’s implementation PR is merged into it.
- **AC-4**: A pair classified as a suspected overlap is not dispatched in
  parallel until the operator explicitly approves parallel execution for that
  pair; absent approval, the serial fallback is selected.
- **AC-5**: The confirmation summary shows the identifiers, evidence,
  classification, and required next action for every concrete or suspected
  pair.
- **AC-6**: When usable plan-derived file-set evidence exists, it remains the
  authoritative source and is not replaced or downgraded by brief-derived
  evidence.
- **AC-7**: Two planless items with unrelated specific targets remain eligible
  for parallel dispatch, subject to the workflow’s other gates.
- **AC-8**: Two items sharing only generic workflow terms are not classified as
  overlapping without a specific shared implementation target.
- **AC-9**: The overlap disposition is visible in the final batch result,
  including any explicit human decision that allowed a suspected pair to run in
  parallel.
- **AC-10**: The behavior is consistent across all supported multi-item batch
  entry points and their shared protocol surface.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| BO-1 — Derive planless overlap signals | BR-2, BR-3; AC-1, AC-2, AC-7, AC-8 |
| BO-2 — Flag pairs before dispatch | BR-6; AC-1, AC-2, AC-5 |
| BO-3 — Serialize or require confirmation | BR-4, BR-5, BR-7, BR-9; AC-3, AC-4, AC-9 |
| BO-4 — Preserve plan-derived detector | BR-1; AC-6 |
| BO-5 — Verify same-route, same-function, and unrelated cases | AC-1, AC-2, AC-7, AC-8 |

## Out of Scope (MVP)

- Predicting every file that implementation will modify when neither the plan
  nor the brief names a specific target.
- Performing semantic code analysis to infer transitive call-graph collisions.
- Automatically rewriting or re-scoping work item briefs.
- Replacing dependency, relationship, lane-capacity, tool-fix, isolation, or
  merge-conflict handling.
- Treating a no-actionable-overlap result as proof that two items cannot
  conflict.
