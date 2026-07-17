# Smoke Test Runbook: Complex Workflow Decision Gate Consistency Matrix

**Feature**: Complex workflow decision gate consistency matrix
**Spec**: [1_1242-consistency-matrix-complex-workflow-decision-gates_specs.md](../../specs/developments/20260716103200_1242-consistency-matrix-complex-workflow-decision-gates/1_1242-consistency-matrix-complex-workflow-decision-gates_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR is available locally or on GitHub.
- [ ] The implementation PR changes workflow documentation or guidance surfaces only.
- [ ] Markdown lint has passed for every changed markdown file.
- [ ] The PR description includes the stage-required readiness evidence.

---

## Test Data

| Item | Value |
| --- | --- |
| Complex gate scenario | A PR that adds or changes a workflow decision gate with multiple inputs, outcomes, next actions, labels, examples, or mirror surfaces |
| Simple documentation scenario | A PR that changes documentation but does not add or modify workflow decision-gate behavior |
| Primary reviewer contract | `REVIEW.md` |
| Primary protocols | Protocols 01, 02, 03, 91, and 92 |

---

## Smoke Test Steps

### Step 1: Complex Gate Matrix Evidence

**Maps to**: AC1, AC2, AC6, AC7

1. Inspect the implementation PR description or linked readiness evidence.
2. Confirm a complex workflow decision-gate change includes matrix evidence before `ready-for-human-review` is applied.
3. Confirm the matrix lists the gate name, gate inputs, allowed outcomes, required next actions, and mirror surfaces.
4. Confirm the PR still goes through internal review, automated reviewer loop, CI, readiness labels, tracker update, and human merge review.

**Expected result**: The PR cannot claim human readiness for an applicable complex gate change without matrix evidence, and the matrix does not replace any existing readiness gate.

### Step 2: Not-Applicable Row Rationale

**Maps to**: AC3

1. Inspect a matrix row where an expected input, outcome, example, or mirror surface is marked not applicable.
2. Confirm the row includes a short rationale.
3. Confirm the rationale is specific to the changed gate rather than a generic placeholder.

**Expected result**: Every not-applicable matrix row explains why the item does not apply.

### Step 3: Reviewer Finding Path

**Maps to**: AC4

1. Review `REVIEW.md`.
2. Confirm spec, plan, and code review guidance tells reviewers to flag missing or contradictory matrix evidence for complex gate PRs.
3. Inspect the implementation PR diff and confirm affected protocol or agent surfaces use matching matrix field names.

**Expected result**: Reviewers have an explicit review-contract basis to block or request fixes for missing inputs, outcomes, next actions, mirror surfaces, examples, or contradictory wording.

### Step 4: Simple Documentation Bypass

**Maps to**: AC5

1. Inspect the updated protocol guidance for simple documentation changes that do not alter workflow decision-gate behavior.
2. Confirm the workflow permits a short not-applicable rationale instead of a full matrix.
3. Confirm the guidance does not require ordinary typo fixes or non-gate documentation updates to create a full matrix.

**Expected result**: Simple non-gate documentation changes can proceed with a concise not-applicable rationale when the evidence format asks for the check.

### Step 5: Mirror Surface Consistency

**Maps to**: AC2, AC6

1. Search the changed files for `consistency matrix`, `complex workflow decision gate`, `gate inputs`, `allowed outcomes`, `required next actions`, `mirror surfaces`, and `not applicable`.
2. Confirm Protocol 01, Protocol 02, Protocol 03, Protocol 91, Protocol 92, `REVIEW.md`, and updated agent/skill guidance use compatible terminology.
3. Confirm any unchanged delegating wrapper remains delegated to the canonical protocol or review contract and does not duplicate stale matrix semantics.

**Expected result**: Mirrored workflow surfaces tell the same story about applicability, required fields, not-applicable rationales, and readiness behavior.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: Applicable complex gate PRs include matrix evidence before `ready-for-human-review`.
- [ ] AC2: Matrix evidence lists gate inputs, allowed outcomes, required next actions, and mirror surfaces.
- [ ] AC3: Not-applicable inputs, outcomes, examples, or surfaces include short rationales.
- [ ] AC4: Reviewers can flag missing or contradictory matrix evidence before readiness.
- [ ] AC5: Simple non-gate documentation PRs can use a not-applicable rationale instead of a full matrix.
- [ ] AC6: Matrix evidence identifies mirrored workflow surfaces that must stay consistent.
- [ ] AC7: Existing internal review, automated reviewer loop, CI, readiness labels, tracker, and human merge gates still apply.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Matrix wording differs between protocols and agent docs | A mirror surface copied local semantics instead of pointing to the canonical protocol | Align the field names and make secondary surfaces point back to the canonical protocol |
| Simple documentation PRs appear to require a full matrix | Not-applicable path is missing or too narrow | Add a concise rationale path for non-gate documentation changes |
| PR readiness appears to bypass reviewer loop or CI | Matrix evidence was described as a replacement gate | Reword it as additive evidence and preserve all existing readiness requirements |

---

## Known Limitations

- The MVP is documentation-only and relies on authors and reviewers to classify complex workflow decision-gate changes.
- The runbook does not require an automated detector for complex gate changes.
