# Protocol-90 Tracker Status Update Before Dispatch — Implementation Plan

**Spec**: N/A (Refactor — see [GitHub issue #159](https://github.com/lhpaul/ai-dev-framework-template/issues/159))
**Smoke test runbook**: [`docs/testing/workflow/protocol-90-tracker-status-update.smoke-test.md`](../../../testing/workflow/protocol-90-tracker-status-update.smoke-test.md)

---

## Summary

**Approach**: Insert a new "Pre-Dispatch Tracker Status Update" step into Protocol 90 (between the current Step 2 "Determine Eligibility" and Step 3 "Build Parallel Batches") that explicitly requires the Portfolio Orchestrator to (a) add each eligible item to the configured project board if it is not already present and (b) update each item's tracker status to the appropriate in-flight stage before dispatching Work Item Runners. Additionally, add a matching note to Protocol 91 clarifying that the Work Item Runner owns status transitions for single-item dispatch when the item is still in a stale pre-dispatch state.

**Estimated complexity**: S

**Rationale**: The change is documentation-only (two Markdown protocol files). No code, scripts, templates, or other files are modified. The scope is narrow and the desired behavior is already well-understood from the Batch 3 retro analysis.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

Not applicable — this is a doc-only change.

### Workflow Protocol Documentation

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — Add new **Step 2.5: Pre-Dispatch Tracker Status Update** section between existing Step 2 and Step 3. This step must:
  - Enumerate every item that passed the Step 2 eligibility check
  - For each item, check whether it already exists in the configured project board; add it if missing
  - For each item, update its tracker status to the appropriate in-flight value based on the next action that will be dispatched:
    | Next action | Status to set |
    |---|---|
    | Write Spec | `Writing Spec` |
    | Write Plan | `Writing Plan` |
    | Implement | `In Development` |
    | Resume in-progress stage (Writing Spec, Writing Plan, In Development already set) | No change needed — skip |
  - Log each update (added to board / status changed / already correct) for transparency
  - Only after all updates complete, proceed to Step 3

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Add a short note in **Step 2: Determine the Next Deterministic Action** (under "What can advance now?") to clarify that when the Work Item Runner is invoked directly (not via Protocol 90) and the item's tracker status is stale (e.g., still `Backlog` when the Refactor type dictates `Writing Plan`), the runner must update the status before dispatching the creator agent — mirroring Protocol 90's new Step 2.5. Reference the same status-transition table. This covers the single-item dispatch path (issue #159 explicitly calls for Protocol 91 to be updated as well).

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:
1. Portfolio Orchestrator runs against items in Backlog with no project board entry — items are added to the board and set to the correct in-flight status before any Work Item Runner is dispatched
2. Portfolio Orchestrator runs against items already in the correct in-flight status — no spurious status changes occur (idempotent)
3. Work Item Runner invoked directly for a single Refactor item that is still `Backlog` — runner sets status to `Writing Plan` before proceeding

**Smoke test runbook**: [`docs/testing/workflow/protocol-90-tracker-status-update.smoke-test.md`](../../../testing/workflow/protocol-90-tracker-status-update.smoke-test.md)

**Regression suite**: Not applicable — no automated regression suite configured in this repository.

---

## Seed Data

Not applicable — this is a protocol documentation change; no seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — Primary change: add Step 2.5 as described above
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Secondary change: add pre-dispatch status note to Step 2

No other project docs require updating. The change does not affect architecture, best practices, repo structure, AGENTS.md, or other files.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Step numbering conflict with existing protocol cross-references | Low | Low | Introduce the new step as "Step 2.5" (a sub-step after Step 2) to avoid renumbering existing Step 3 through Step 6 which are referenced in Protocol 91 and elsewhere |
| New step adds overhead to orchestrator runs when the tracker is unavailable | Low | Low | Step 2.5 should follow the same "warn and fall back" pattern established in Steps 1a–1c: if the tracker API is unreachable, log a warning and proceed without blocking the batch |
| Duplicate status updates from Protocol 91 when Protocol 90 already ran | Low | Low | Both protocols use idempotent `gh` GraphQL mutations; updating an already-correct status is a no-op |

---

## Implementation Order

1. Edit `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`: insert new Step 2.5 section after the existing Step 2 content, before the Step 3 heading
2. Edit `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`: add pre-dispatch tracker status note to Step 2 ("What can advance now?" table or its prose)
3. Update `CHANGELOG.md` with an entry under `[Unreleased]` for this protocol improvement
4. Verify smoke test runbook scenarios manually against the updated protocol text
5. Update project docs per **Documentation Updates** section above (both files are the target, so this step is already covered by steps 1–2)
