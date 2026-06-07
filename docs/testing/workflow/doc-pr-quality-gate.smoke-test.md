# Smoke Test Runbook: Doc PR Quality Gate

**Feature**: Doc PR quality gate
**Spec**: [1_doc-pr-quality-gate_specs.md](../../specs/developments/20260606094538_doc-pr-quality-gate/1_doc-pr-quality-gate_specs.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] The implementation branch for #816 is checked out.
- [ ] The changed documentation has been linted with `markdownlint-cli2`.

---

## Smoke Test Steps

### Step 1: Verify spec author gate

1. Open `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`.
2. Find the pre-PR document quality gate section.
3. Confirm it requires checks for brief coverage, internal consistency, naming/casing consistency, behavioral guarantees, recurring reviewer categories, placeholder cleanup, and not-applicable rationale.
4. Confirm it requires a PR-description log before opening the draft spec PR.

**Expected result**: Protocol 01 clearly blocks opening a spec PR until the quality gate and log are complete.

### Step 2: Verify plan author gate

1. Open `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`.
2. Find the pre-PR document quality gate section.
3. Confirm it requires checks for brief/spec coverage, cross-section consistency, naming/casing consistency, behavioral guarantees, verification-log support, and applicable parser/concurrency checklist completeness.
4. Confirm it requires a PR-description log before opening the draft plan PR.

**Expected result**: Protocol 02 clearly blocks opening a plan PR until the quality gate and log are complete.

### Step 3: Verify review contract

1. Open `REVIEW.md`.
2. Review the spec and plan review checklist sections.
3. Confirm reviewers can flag a missing or incomplete document quality-gate log.
4. Confirm a stale or contradictory log can block readiness.

**Expected result**: Reviewers have explicit authority to enforce the gate without treating it as a replacement for normal review.

### Step 4: Verify orchestrator and operator guidance

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Confirm spec/plan PR readiness still requires internal review, automated review, CI, and human review after the gate.
3. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
4. Confirm operators are told how to inspect long spec/plan review cycles using the quality-gate log and reviewer-loop context.

**Expected result**: The gate improves first-pass quality but does not weaken existing reviewer-loop readiness rules.

### Step 5: Verify agent guidance

1. Open the Claude and Cursor product-manager agent docs.
2. Confirm they mention the Protocol 01 document quality gate.
3. Open the Claude and Cursor tech-lead agent docs.
4. Confirm they mention the Protocol 02 document quality gate.
5. Confirm Codex skill files continue to delegate to Protocol 01/02 without contradictory local gate text.

**Expected result**: Agent-facing summaries point to the same canonical gate behavior.

---

## Assertions Checklist

- [ ] Spec PRs require a document quality-gate log before draft PR creation.
- [ ] Plan PRs require a document quality-gate log before draft PR creation.
- [ ] The gate covers the recurring high-value reviewer categories from the spec.
- [ ] The gate is explicitly not a replacement for internal review, automated review, CI, or human review.
- [ ] Operator guidance for long document-review cycles references the gate and reviewer-loop context.

---

## Seed Data Reference

No seed data is required.
