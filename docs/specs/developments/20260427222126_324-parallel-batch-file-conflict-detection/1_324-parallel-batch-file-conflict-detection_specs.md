# Parallel Batch File-Level Conflict Detection — Spec

**Issue**: [#324](https://github.com/lhpaul/ai-dev-framework-template/issues/324)

---

## Brief Coverage (issue #324)

Brief objectives extracted from the issue description, mapped to spec coverage:

| Brief objective | Spec coverage |
|---|---|
| Inspect spec/plan documents for each item to identify which files will be modified | Use Case 1 steps 2–3; Use Case 2 steps 1–2; BR-3; AC-3 |
| Cross-check for file overlaps between items in the same proposed parallel batch | Use Case 1 steps 3–4; BR-2; AC-1, AC-2 |
| Serialize (or flag to human) any batch pairs with overlapping file sets | Use Case 1 steps 5–6 (auto-serialize); Use Case 2 steps 3–4 (flag unknown); Use Case 3 (human override); BR-4, BR-5, BR-6, BR-7; AC-1, AC-3, AC-5 |

**Deferral notes**: No objectives deferred to Out of Scope.

---

## Overview

When the Portfolio Orchestrator groups multiple implementation items into a parallel batch, two or more of those items can modify the same source files, producing merge conflicts at integration time. Today the orchestrator relies on human judgment to identify safe batches — the protocol says "implementations that clearly touch different areas of the codebase" are safe, but this determination is manual and imprecise.

This feature adds an automated file-level conflict-detection step to the batch-planning stage. Before the orchestrator dispatches a parallel batch, it inspects the implementation plan document for each candidate item, extracts the set of files that each item expects to modify, cross-checks for overlaps between items in the same proposed batch, and either serializes conflicting pairs automatically or surfaces the overlap to the human for a final decision.

---

## Use Cases

### Use Case 1: Automatic serialization of overlapping implementation items

**Actor**: Portfolio Orchestrator (automated, no direct human interaction in the happy path)
**Preconditions**:
- Two or more implementation items are candidates for the same parallel batch
- At least one item has a published implementation plan document with an explicit list of files to be modified
- The batch-planning step has run but the batch has not yet been dispatched

**Steps**:
1. The orchestrator invokes the conflict-detection check for the proposed parallel batch
2. The detector reads the implementation plan document for each candidate item and extracts the set of files that plan declares it will modify
3. For each pair of candidate items, the detector checks whether their extracted file sets overlap
4. When an overlap is found between two items, the detector marks those items as a conflicting pair
5. The orchestrator automatically moves the lower-priority item out of the current parallel batch and places it in the next serial sub-batch
6. The orchestrator proceeds to dispatch the current batch (without the conflicting item) and reports the serialization decision in the batch summary

**Postconditions**:
- No two items dispatched in the same parallel batch share a declared file in their implementation plans
- The serialized item is queued to start after the current batch completes

**Information shown** (in the batch summary report):
- Which items were serialized and why (file overlap detected, overlapping file paths listed)
- Which batch each item now belongs to

**Actions available**:
- Human can override the serialization decision and force parallel dispatch by explicit instruction (see Use Case 3)

**Considerations**:
- Spec-stage and plan-stage items are out of scope for conflict detection entirely (see BR-1); the detector does not evaluate them
- If an implementation-branch item has no implementation plan document yet, the detector cannot extract a file set; the item is treated as having an unknown file set and a warning is included in the batch summary (see BR-3 and Use Case 2)
- If an item's plan document does not include an explicit file list, the detector cannot determine the overlap; the item is also treated as having an unknown file set (see Business Rule 3)

---

### Use Case 2: Flagging items with unknown file sets

**Actor**: Portfolio Orchestrator
**Preconditions**:
- Two or more items are candidates for a parallel batch
- At least one item's plan document does not contain an explicit file list (or no plan document exists)

**Steps**:
1. The detector attempts to extract the file set for each candidate item
2. For items where extraction fails or yields an empty result, the detector marks the file set as "unknown"
3. The orchestrator reports items with unknown file sets in the batch summary, noting that file-level conflict detection could not be performed
4. The orchestrator proceeds with the proposed batch as-is (no automatic serialization for unknown-set items), but highlights the reduced confidence level to the human

**Postconditions**:
- The batch is dispatched with the unknown-set items included
- The batch summary clearly notes which items had unknown file sets and were not checked for conflicts

**Information shown**:
- A warning per item with an unknown file set, including the reason (no plan, no explicit file list in plan)

**Considerations**:
- This keeps the happy path non-blocking: if detection data is missing, the orchestrator does not stall the batch
- The human retains the ability to inspect and override before confirming dispatch (see Use Case 3)

---

### Use Case 3: Human override of a serialization decision

**Actor**: Human operator reviewing the batch summary
**Preconditions**:
- The orchestrator has serialized one or more items due to a detected file overlap
- The human has read the batch summary and determines the detected conflict is acceptable (e.g., the files overlap in name only but the edits are to unrelated sections)

**Steps**:
1. Human explicitly instructs the orchestrator to override the serialization for a named pair of items
2. The orchestrator logs the override, annotates the batch summary with a warning, and dispatches the previously-serialized item in parallel alongside the original batch

**Postconditions**:
- The overridden items are dispatched in parallel
- The override decision and rationale are recorded in the batch summary

**Considerations**:
- The orchestrator must never autonomously skip serialization — override is only valid when the human explicitly requests it

---

## Business Rules

- **BR-1** — Conflict detection runs only for implementation items (branches with prefix `feature/`, `fix/`, `refactor/`, `hotfix/`). Spec and plan items are never subject to file-level conflict serialization.
- **BR-2** — A conflict exists between two items when their declared file sets share at least one common file path. Paths are compared as normalized, repo-root-relative strings (forward slashes, no leading slash).
- **BR-3** — An item's file set is "unknown" when: (a) no implementation plan document exists for that item, or (b) the implementation plan document exists but contains no extractable explicit file list. Unknown-set items are not automatically serialized but are flagged in the batch summary.
- **BR-4** — When a conflict is detected, the lower-priority item (per the priority ordering defined in the batch-planning protocol) is moved to the next serial sub-batch. The higher-priority item remains in the current batch.
- **BR-5** — When two conflicting items have equal priority, the item with the later creation date is serialized (the older item stays in the current batch). If both items also share the same creation date, the item whose branch name comes later in lexicographic order is serialized.
- **BR-6** — The orchestrator must never autonomously dispatch an override. Only an explicit human instruction enables parallel dispatch when a conflict has been detected.
- **BR-7** — When a conflict is detected and an item is serialized, the batch summary must list: the conflicting item pair, the overlapping file path(s), and the resulting batch assignment for each item.
- **BR-8** — Conflict detection is additive to the existing tool-fix ordering hazard check (protocol 90 Step 3). Both checks must pass before a batch is dispatched. If an item is already serialized by the tool-fix rule, it is excluded from the conflict-detection input set for the current batch.

---

## Acceptance Criteria

- [ ] Given two implementation items that both declare the same file in their implementation plans, when the orchestrator builds a parallel batch containing both, then only the higher-priority item is dispatched in the current batch; the other is moved to the next sub-batch and the batch summary lists the overlapping file path and the serialization decision.
- [ ] Given two implementation items whose declared file sets have no overlap, when the orchestrator builds a parallel batch containing both, then both items are dispatched together and the batch summary contains no conflict-detection warning for this pair.
- [ ] Given an implementation item whose implementation plan does not include an explicit file list, when the orchestrator builds a parallel batch containing this item, then the item is dispatched normally and the batch summary notes that file-level conflict detection was not possible for this item (unknown file set).
- [ ] Given an implementation-branch item (for example, a `feature/` or `fix/` item) that has no implementation plan document yet, when the orchestrator evaluates it for conflict detection, then the item is treated as having an unknown file set: it is dispatched in the batch and the batch summary includes a warning noting that conflict detection was not possible for this item.
- [ ] Given that the orchestrator has serialized an item due to a detected file overlap, when the human explicitly overrides the decision, then the previously-serialized item is dispatched in parallel and the batch summary records the override with a warning.
- [ ] Conflict detection does not apply to spec-stage or plan-stage items; those items are always dispatched without file-level conflict checks.
- [ ] The conflict-detection check runs after the existing tool-fix ordering check (protocol 90 Step 3); items already serialized by the tool-fix rule are excluded from conflict-detection input.
- [ ] File path comparison is case-sensitive and uses normalized repo-root-relative paths (forward slashes, no leading slash).

---

## Out of Scope (MVP)

- Detecting conflicts at the function or symbol level within the same file (line-range analysis) — this spec covers file-level overlap only
- Automatically resolving merge conflicts after they occur — the feature only prevents conflicting items from being dispatched in parallel
- Conflict detection for spec or plan PRs
- Conflict detection across batches that have already been dispatched (retroactive analysis)
- Integration with an external static-analysis or dependency-graph tool to infer file sets when the plan document does not list them explicitly
- Automatically updating or re-ordering the implementation plan to reflect conflict-detection outcomes
- Persisting the conflict-detection history beyond the current orchestrator run (no new database or storage)
