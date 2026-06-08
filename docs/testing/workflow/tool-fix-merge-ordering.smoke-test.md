# Smoke Test Runbook: Tool-Fix Merge Ordering

**Feature**: Tool-fix merge ordering
**Spec**: [1_tool-fix-merge-ordering_specs.md](../../specs/developments/20260606100937_tool-fix-merge-ordering/1_tool-fix-merge-ordering_specs.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] The implementation branch for #825 is checked out.
- [ ] The changed documentation has been linted with `markdownlint-cli2`.

---

## Smoke Test Steps

### Step 1: Verify foundational hazard explanation

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Find the same-batch tool-fix ordering section.
3. Confirm it explains that dispatch serialization is insufficient when one tool-fix repairs reviewer tooling that another same-batch tool-fix needs.

**Expected result**: Protocol 90 names the merge-ordering hazard, not only dispatch ordering.

### Step 2: Verify foundational detection and hold behavior

1. In the same section, confirm the orchestrator is instructed to identify foundational reviewer-tool fixes.
2. Confirm dependent tool-fix items are held until the foundational PR is merged.
3. Confirm the hold reason must be visible in the batch summary.

**Expected result**: Dependent tool-fixes are not trusted while they still depend on broken reviewer tooling.

### Step 3: Verify post-merge resume behavior

1. Confirm dependent branches or PRs must be updated from the target base after the foundational PR merges.
2. Confirm the dependent reviewer loop and CI must be rerun after that update.
3. Confirm readiness is trusted only after the fresh post-update loop is clean.

**Expected result**: Dependent readiness cannot rely on stale pre-foundational-merge reviewer results.

### Step 4: Verify stale escalation treatment

1. Confirm a dependent escalation that happened before the foundational merge is treated as stale.
2. Confirm it must be re-evaluated after updating from the fixed base.

**Expected result**: The orchestrator distinguishes stale tool-caused escalations from substantive post-update findings.

### Step 5: Verify human merge approval remains required

1. Confirm Protocol 90 does not authorize autonomous merge of the foundational PR.
2. Confirm the text explicitly preserves human approval for every PR merge.

**Expected result**: Merge-ordering guidance changes sequencing, not merge authority.

---

## Assertions Checklist

- [ ] Foundational reviewer-tool fixes are defined.
- [ ] Dependent tool-fixes are held until foundational merge.
- [ ] Dependent branches update from target base before rerun.
- [ ] Fresh reviewer loop and CI are required before readiness.
- [ ] Stale pre-merge escalations are explicitly re-evaluated.
- [ ] Batch summaries list held items and reasons.
- [ ] Human merge approval remains required.

---

## Seed Data Reference

No seed data is required.
