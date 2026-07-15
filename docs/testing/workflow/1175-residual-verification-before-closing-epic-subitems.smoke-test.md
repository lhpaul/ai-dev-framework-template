# Smoke Test Runbook: Residual Verification Before Closing Epic Sub-items

**Feature**: Residual verification before closing epic sub-items
**Spec**: [1_1175-residual-verification-before-closing-epic-subitems_specs.md](../../specs/developments/20260714164804_1175-residual-verification-before-closing-epic-subitems/1_1175-residual-verification-before-closing-epic-subitems_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for issue `#1175`.
- [ ] The implementation PR includes the residual gate helper and its tests.
- [ ] GitHub CLI is authenticated if PR label or comment behavior is tested against a real PR.
- [ ] No production or downstream repository data is required.

---

## Test Data

| Item | Value |
| --- | --- |
| Sweep issue title | `Clean 127 console.log occurrences across apps/admin` |
| Clean evidence | JSON evidence with zero residual groups |
| Blocking evidence | JSON evidence with at least one residual group and no disposition |
| Follow-up evidence | JSON evidence with remaining residuals linked to `#1234` |
| Helper extraction title | `Extract 7 shared helpers from workflow scripts` |
| Unused helper evidence | JSON evidence listing helper outputs with no apparent callers |
| Ambiguous broad-scope title | `Clean all unresolved workflow leftovers across the codebase` |

---

## Smoke Test Steps

### Step 1: Verify Sweep Classification

**Maps to**: AC-1, AC-6, AC-8

1. Run the residual gate helper in classification mode with the sweep issue title.
2. Confirm the result identifies the item as applicable for residual verification.
3. Confirm the summary preserves the target count or checked target.

**Expected result**: The helper reports an applicable sweep or occurrence-based classification and includes the checked target in human-readable output.

### Step 2: Verify Clean Residual Evidence

**Maps to**: AC-1, AC-2, AC-6

1. Run the helper in verification mode with the sweep issue title and clean evidence.
2. Confirm the result is `pass`.
3. Confirm the summary says no residuals were found.

**Expected result**: The workflow can continue to the normal readiness flow, and the evidence is visible in the helper output.

### Step 3: Verify Blocking Residual Evidence

**Maps to**: AC-3, AC-6

1. Run the helper in verification mode with the sweep issue title and blocking evidence.
2. Confirm the result is `block`.
3. Confirm the summary names the remaining residual group and the required unblock path.

**Expected result**: The runner must not apply `ready-for-human-review`; the item remains fixable until residuals are completed, linked, or explicitly out of scope.

### Step 4: Verify Linked Follow-up Disposition

**Maps to**: AC-4, AC-6

1. Run the helper in verification mode with follow-up evidence.
2. Confirm the result permits readiness only because the remaining residuals have a linked follow-up issue.
3. Confirm the summary distinguishes completed scope from deferred follow-up work.

**Expected result**: The workflow can continue only when the linked follow-up is visible in the residual summary.

### Step 5: Verify Helper Extraction Caller Risk

**Maps to**: AC-5

1. Run the helper in verification mode with the helper extraction title and unused helper evidence.
2. Confirm the result is `block`.
3. Confirm the summary names helper outputs with no apparent callers.

**Expected result**: The runner must not mark helper extraction complete until helper outputs are connected, removed, tracked in a follow-up, or explicitly outside scope.

### Step 6: Verify Ambiguous Scope Escalation

**Maps to**: AC-7

1. Run the helper with the ambiguous broad-scope title and no concrete residual evidence strategy.
2. Confirm the result is `escalate` or an equivalent human-decision outcome.
3. Confirm the summary explains that the runner cannot determine residual scope safely.

**Expected result**: The workflow asks for a human decision rather than guessing that the item is complete.

### Step 7: Verify Protocol Integration

**Maps to**: AC-1, AC-3, AC-8

1. Inspect the implementation diff for Protocols 90, 91, 92, and 95.
2. Confirm the single-item, explicit batch, and epic paths all run or honor the residual gate before `ready-for-human-review`.
3. Confirm blocked residual results keep the item out of the human-ready state.

**Expected result**: Every applicable item path has visible residual-gate behavior before readiness handoff.

### Last Step: Validate and Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary fixture files created during manual testing.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Sweep items record residual verification evidence before `ready-for-human-review`.
- [ ] AC-2: Sweep items with no residuals continue through normal readiness.
- [ ] AC-3: Sweep items with undisposed residuals do not receive `ready-for-human-review`.
- [ ] AC-4: Remaining residuals with linked follow-up issues are visible and distinguished from completed scope.
- [ ] AC-5: Helper extraction items flag unused helper outputs before readiness.
- [ ] AC-6: Residual summaries report checked targets and remaining counts or groupings.
- [ ] AC-7: Ambiguous sweep scope escalates for a human decision.
- [ ] AC-8: Epic or batch summaries show residual verification status for applicable sub-items.

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
| --- | --- | --- |
| Issue title/body fixtures | Sweep, helper extraction, clean, blocking, follow-up, and ambiguous cases | Create temporary text files or inline shell variables during the smoke test. |
| Residual evidence fixtures | Pass, block, linked follow-up, and unused helper cases | Create temporary JSON files during the smoke test. |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Helper reports `not_applicable` for sweep title | Classification patterns are too narrow | Re-run unit tests for boundary variants and update the classifier conservatively. |
| Helper passes evidence with prose-only deferral | Follow-up validation is too permissive | Require linked issue references or explicit `out_of_scope` disposition. |
| Protocol smoke passes single-item path but not epic path | Protocol 95 or epic ledger guidance was not updated | Update epic guidance and rerun Step 7. |

---

## Known Limitations

- The smoke test validates workflow behavior and evidence handling; it does not prove semantic dead-code detection for every programming language.
- The runbook uses local fixtures unless the implementation PR adds a dedicated end-to-end harness for real PR labels and comments.
