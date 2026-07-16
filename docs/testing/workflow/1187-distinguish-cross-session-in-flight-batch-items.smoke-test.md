# Smoke Test Runbook: Distinguish Cross-Session In-Flight Items in Run-Work Batch Proposals

**Feature**: Distinguish cross-session in-flight items in `/run-work` batch proposals
**Spec**: [../../specs/developments/20260714172424_1187-distinguish-cross-session-in-flight-batch-items/1_1187-distinguish-cross-session-in-flight-batch-items_specs.md](../../specs/developments/20260714172424_1187-distinguish-cross-session-in-flight-batch-items/1_1187-distinguish-cross-session-in-flight-batch-items_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for #1187 is checked out.
- [ ] `gh` is authenticated if running a live `/run-work` scan against the real
      project board.
- [ ] You are running from the repository root.
- [ ] The helper regression tests added for #1187 pass locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Informational item | Existing in-flight, review-waiting, merge-waiting, or skipped fixture item |
| Actionable resume item | Fixture item whose next action can advance in the current run |
| Proposed Backlog item | Fixture Backlog candidate included in the current proposal |
| Held Backlog item | Fixture Backlog candidate excluded with a hold reason |
| Primary helper | `scripts/development-workflow/workflow-batch-lanes.sh` |
| Optional live entrypoint | `/run-work` or `scripts/development-workflow/run-work-router.sh` followed by Protocol 90 scan reporting |

---

## Smoke Test Steps

### Step 0: Confirm plan artifacts exist

- Run `ls docs/specs/developments/20260714172424_1187-distinguish-cross-session-in-flight-batch-items/2_1187-distinguish-cross-session-in-flight-batch-items_implementation-plan.md docs/testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md`.
- Verify both files exist.

### Step 1: Run helper regression tests

**Maps to**: AC1, AC2, AC3, AC5, AC6, AC10

1. Run `bash scripts/development-workflow/tests/test-workflow-batch-lanes.sh`.
2. Inspect the test names and output for the #1187 category assertions.

**Expected result**: The suite passes and includes coverage for
`REPORT_CATEGORY=informational`, `REPORT_CATEGORY=actionable_resume`,
`REPORT_CATEGORY=proposed_batch`, and `REPORT_CATEGORY=held`.

### Step 2: Verify mixed scan report categories

**Maps to**: AC1, AC2, AC3, AC4, AC7

1. Run the implemented mixed-scan fixture or a live `/run-work` no-target scan
   with at least one informational item and one proposed Backlog item.
2. Inspect the rendered scan report.

**Expected result**: Cross-session or waiting work appears under
`INFORMATIONAL - not actionable in this proposal` with a reason. Backlog items
awaiting the current decision appear under `PROPOSED BATCH - your decision`
with item number, title, priority, type, next stage, and parallelization notes.
The current start-decision text names only the proposed-batch items.

### Step 3: Verify informational-only scan wording

**Maps to**: AC5

1. Run the informational-only fixture or a live scan where no Backlog start batch
   is safe to propose.
2. Inspect the report summary.

**Expected result**: The report still shows informational items for awareness
but states directly that no Backlog start batch is currently proposed.

### Step 4: Verify held-item separation

**Maps to**: AC6

1. Run a fixture with at least one held Backlog candidate.
2. Inspect the report section and helper output.

**Expected result**: Held items are labeled `HELD - not included in proposed
batch` and remain separate from informational, actionable-resume, and
proposed-batch sections. Each held item names a hold reason.

### Step 5: Verify actionable resume separation

**Maps to**: AC10

1. Run a fixture with a current-session resume item that can advance now.
2. Inspect the report section and helper output.

**Expected result**: Resume work is labeled `ACTIONABLE RESUME - can advance
now`, not informational context and not a proposed Backlog start item.

### Step 6: Verify guidance consistency

**Maps to**: AC8

1. Read the updated `/run-work` guidance in Protocol 90, the command wrappers,
   skill aliases, README, and AGENTS guidance.
2. Compare the category labels and approval-scope wording.

**Expected result**: All surfaces use the same meanings for informational,
actionable-resume, proposed-batch, and held items. No surface suggests that
approval of the proposed batch includes informational items.

### Step 7: Verify smoke/documentation coverage

**Maps to**: AC9

1. Confirm this runbook is linked from the implementation plan.
2. Confirm the implementation PR includes either automated fixture coverage or
   documented smoke evidence for a mixed portfolio scan.

**Expected result**: Reviewers can see a mixed scan scenario that demonstrates
the category distinction.

### Last Step: Validate and shut down

- Verify all assertions in the checklist below are met.
- Run markdown lint for the edited markdown files.
- Shut down any temporary fixture environment if one was created.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: Mixed no-target scan output separates informational and
      proposed-batch categories.
- [ ] AC2: Informational items use the informational marker and include a reason.
- [ ] AC3: Proposed Backlog items use the proposed-batch marker and include item
      number, title, priority, type, next stage, and parallelization notes.
- [ ] AC4: Current start-decision text names only proposed-batch items.
- [ ] AC5: Informational-only scans state no Backlog start batch is proposed.
- [ ] AC6: Held or blocked Backlog candidates are labeled separately with a hold
      reason.
- [ ] AC7: The recommended command or approval text cannot reasonably be read as
      approving informational items.
- [ ] AC8: Protocol and command or skill guidance use consistent category names
      and meanings.
- [ ] AC9: Workflow smoke-test or documentation coverage includes a mixed scan
      scenario.
- [ ] AC10: Current-session resume work is labeled as actionable resume work.

---

## Seed Data Reference

No persisted seed data is required. Use shell fixtures in the workflow helper
tests, or a live GitHub Projects portfolio that naturally contains the required
states.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Helper fixture block | Informational, actionable-resume, proposed-batch, and held records | Inline in `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` |
| Live portfolio item | Optional real scan verification | Use existing GitHub Projects items; do not mutate them during `/run-work` scan-only mode |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Live `/run-work` scan finds no mixed portfolio | The current project board does not contain both context and Backlog items | Use the shell fixture coverage for smoke evidence, or wait for a mixed live portfolio state |
| Informational item appears in the proposed batch | Category derivation is relying only on `DISPATCH=proposed` | Re-check `NEXT_ACTION`, tracker status, and the `REPORT_CATEGORY` mapping |
| Held item has no reason | `HOLD_REASON` was not carried into `REPORT_REASON` | Preserve the lane helper hold reason in the rendered report |
| Guidance labels differ across tools | One command or skill wrapper was missed | Re-run the guidance search from the implementation plan Verification Log |

---

## Known Limitations

- Live verification depends on whatever items are currently present in the
  GitHub Projects board. The committed helper tests are the deterministic
  evidence source for the mixed-category contract.
- This runbook validates read-only scan reporting. It does not execute
  `/run-items` or start Backlog work.
