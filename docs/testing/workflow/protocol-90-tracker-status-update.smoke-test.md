# Smoke Test Runbook: Protocol-90 Tracker Status Update Before Dispatch

**Feature**: Protocol 90 — Pre-dispatch tracker status update (issue #159)
**Spec**: N/A (Refactor — see [GitHub issue #159](https://github.com/lhpaul/ai-dev-framework-template/issues/159))
**Implementation plan**: [`docs/specs/developments/20260416154733_protocol-90-tracker-status-update/2_protocol-90-tracker-status-update_implementation-plan.md`](../../specs/developments/20260416154733_protocol-90-tracker-status-update/2_protocol-90-tracker-status-update_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI is authenticated with `project` and `repo` scopes
- [ ] The repository's GitHub Projects board is accessible
- [ ] The updated protocol files (`90-batch-orchestrate-work-protocol.md` and `91-orchestrate-work-protocol.md`) are merged and in the branch under test
- [ ] At least one GitHub issue exists in `Backlog` status with no project board entry (for Scenario 1)
- [ ] At least one GitHub issue exists already in `Writing Spec` or `Writing Plan` status on the board (for Scenario 2)

---

## Test Data

| Item                              | Value                                                                          |
| --------------------------------- | ------------------------------------------------------------------------------ |
| Test Backlog issue (not on board) | A fresh GitHub issue with Status = Backlog, not added to the project board     |
| Test in-progress issue            | A GitHub issue already on the board with Status = Writing Spec or Writing Plan |
| Project number                    | Obtain via `gh project list --owner <OWNER>`                                   |

---

## Smoke Test Steps

### Step 1: Verify new Step 2.5 exists in Protocol 90

- Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- Confirm a **Step 2.5: Pre-Dispatch Tracker Status Update** (or equivalent heading) appears between Step 2 and Step 3
- Confirm it documents:
  - Adding missing items to the project board
  - Setting the appropriate in-flight status before dispatch
  - A status-transition table covering `Writing Spec`, `Writing Plan`, and `In Development`
  - Idempotent behavior for items already in the correct status
  - Fallback warning when the tracker is unavailable

**Expected result**: The section is present with all required content; existing step numbering (Steps 3–6) is unchanged.

### Step 2: Verify Protocol 91 pre-dispatch note

- Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- Navigate to **Step 2: Determine the Next Deterministic Action**
- Confirm a note or row exists instructing the Work Item Runner to update tracker status before dispatching a creator agent when the item's current status is stale (e.g., still `Backlog` for a Refactor item)

**Expected result**: The note is present and references the same status-transition logic as Protocol 90 Step 2.5.

### Step 3: Scenario 1 — Backlog item not on board

**Maps to**: Acceptance Criterion: items added to board and status updated before dispatch

1. Simulate a Portfolio Orchestrator run against the test Backlog issue (read the updated protocol and verify the Step 2.5 instructions would cause the item to be added to the board and set to `Writing Spec` or `Writing Plan` before Work Item Runner dispatch)
2. If the orchestrator supports dry-run or step-by-step: confirm Step 2.5 fires before Step 3 (batch building)
3. Alternatively, trace the protocol by hand: confirm the new step explicitly mentions adding missing items and setting status

**Expected result**: Protocol text unambiguously requires the board addition and status update to complete before Work Item Runners are dispatched.

### Step 4: Scenario 2 — Item already in correct in-flight status

**Maps to**: Acceptance Criterion: idempotent behavior for already-updated items

1. Review the Step 2.5 text for an explicit "skip if already correct" condition
2. Confirm the step does not reset or change a status that is already `Writing Spec`, `Writing Plan`, or `In Development`

**Expected result**: The protocol includes an idempotency guard — no redundant status update when the item is already in the correct in-flight state.

### Step 5: Scenario 3 — Single-item dispatch via Protocol 91

**Maps to**: Acceptance Criterion: Protocol 91 mirrors the pre-dispatch status update for single-item runs

1. Review the updated Protocol 91 Step 2 note
2. Confirm that a Work Item Runner started for a Refactor item in `Backlog` status would set `Writing Plan` before calling the plan-writing stage

**Expected result**: The Protocol 91 update is present and consistent with the Protocol 90 Step 2.5 table.

### Last Step: Assertions Checklist

- Verify all assertions below are met before closing

---

## Assertions Checklist

- [ ] Protocol 90 contains a new pre-dispatch tracker status update step between Step 2 and Step 3
- [ ] The new step requires adding missing items to the project board
- [ ] The new step requires setting the appropriate in-flight status (Writing Spec / Writing Plan / In Development) before dispatch
- [ ] The new step is idempotent — no change when status is already correct
- [ ] The new step follows the tracker-unavailable fallback pattern (warn and proceed)
- [ ] Protocol 91 Step 2 contains a matching note for single-item dispatch
- [ ] No existing step numbers (3–6) in Protocol 90 were changed
- [ ] CHANGELOG.md has an `[Unreleased]` entry for this change

---

## Seed Data Reference

Not applicable — this smoke test validates protocol documentation only; no seed data is required.

---

## Troubleshooting

| Symptom                                   | Likely cause                                            | Fix                                                                                                      |
| ----------------------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Step 2.5 heading not found in Protocol 90 | Implementation not yet merged                           | Confirm the `refactor/159-protocol-90-tracker-status-update` branch is merged into the branch under test |
| Protocol 91 note missing                  | Step 2 of Protocol 91 not updated during implementation | Re-read issue #159 scope and apply the missing edit                                                      |
| Step numbering in Protocol 90 changed     | Editor renumbered steps                                 | Restore original step numbers (3–6) and use "2.5" for the new step                                       |

---

## Known Limitations

- This runbook validates protocol text only — it does not execute an actual orchestrator run against a live GitHub project. Full behavioral validation requires a live orchestrator run with a real GitHub project board.
