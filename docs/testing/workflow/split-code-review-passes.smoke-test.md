# Smoke Test Runbook: Split Code Review into Spec-Compliance and Code-Quality Passes

**Feature**: Split Step 7a internal review gate into Pass 1 (Spec Compliance) and Pass 2 (Code Quality) for implementation PRs
**Spec**: [`docs/specs/developments/20260504102543_split-code-review-passes/1_split-code-review-passes_specs.md`](../../specs/developments/20260504102543_split-code-review-passes/1_split-code-review-passes_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR (feature #449) is merged to `develop`
- [ ] A test repository exists (or the template repo itself) with a configured internal reviewer (`claude` in `review.internal_reviewers`)
- [ ] A merged spec and plan exist on `develop` for the test item (to satisfy Pass 1 spec-compliance evaluation)
- [ ] `gh` CLI is authenticated

---

## Test Data

| Item | Value |
|---|---|
| Test implementation branch | `fix/smoke-test-449` (create fresh for each run) |
| Test spec/plan branch | `spec/smoke-test-449` (create fresh for single-pass verification) |
| Reviewer config | `internal_reviewers: [claude]` in `.ai-dev-workflow.yaml` |

---

## Smoke Test Steps

### Scenario 1: Pass sequence enforced for implementation PR

**Maps to**: Acceptance Criterion 1

1. Create a small `fix/*` branch from `develop` and open a draft PR.
2. Initiate Step 7a (internal review gate) on the draft PR.
3. Observe the orchestrator's dispatch log or PR comments.

**Expected result**: Pass 1 (Spec Compliance) is dispatched first. Pass 2 (Code Quality) is not dispatched until Pass 1 returns `APPROVED`. The orchestrator's dispatch prompt for each reviewer includes the active pass name.

---

### Scenario 2: Non-draft conversion requires both passes

**Maps to**: Acceptance Criterion 2

1. Using the same draft PR from Scenario 1.
2. Let Pass 1 approve but stop before Pass 2 approves (e.g., halt the run mid-way, or use a scenario where Pass 2 returns `NEEDS REVISION` first).
3. Verify that `gh pr ready` has NOT been called while Pass 2 is still pending.
4. Resume the run until both passes approve at the same commit SHA.
5. Verify that `gh pr ready` is called only after both passes approve.

**Expected result**: `gh pr view <pr_number> --json isDraft` returns `false` only after both Pass 1 and Pass 2 have approved at the same commit SHA.

---

### Scenario 3: Summary comment labels findings by pass

**Maps to**: Acceptance Criterion 3

1. Run Step 7a to completion on an implementation PR where at least one finding was raised and resolved during Pass 1 and at least one during Pass 2.
2. Check the PR comment posted at the end of Step 7a.

**Expected result**: The Step 7a summary comment contains distinct `Pass 1 (Spec Compliance)` and `Pass 2 (Code Quality)` sections, each with its own verdict. Findings are labeled by which pass raised them.

---

### Scenario 4: Spec and plan PRs use single-pass review

**Maps to**: Acceptance Criterion 4

1. Create a `spec/*` draft PR and initiate Step 7a.
2. Observe the dispatch log or PR comments.

**Expected result**: Only a single review pass is dispatched (no `Pass 1` / `Pass 2` split visible). The Step 7a summary comment does not mention two passes. The behavior is identical to pre-feature behavior.

Repeat for an `implementation-plan/*` draft PR to confirm both spec and plan PRs are unaffected.

---

### Scenario 5: Non-trivial fix during Pass 2 re-triggers Pass 1

**Maps to**: Acceptance Criterion 5

1. Run Step 7a on an implementation PR where Pass 1 approves and Pass 2 returns `NEEDS REVISION`.
2. Apply a fix that is non-trivial (involves a logic change, a new function, or structural markup — does not meet all three trivial-fix conditions).
3. Push the fix commit.
4. Observe the orchestrator's next dispatch.

**Expected result**: After the non-trivial fix push, Pass 1 is dispatched again before Pass 2 continues. The `internal_review_cycle` counter increments.

---

### Scenario 6: Trivial fix during Pass 2 skips Pass 1 re-run

**Maps to**: Acceptance Criterion 6

1. Run Step 7a on an implementation PR where Pass 1 approves and Pass 2 returns `NEEDS REVISION`.
2. Apply a fix that is trivial: the fixer self-certifies `TRIVIAL_FIX: non-structural` in the commit message, the diff is only plain-text changes (≤10 lines), and no logic or structural markup changes.
3. Push the fix commit.
4. Observe the orchestrator's next dispatch and PR comments.

**Expected result**: Pass 1 is NOT re-run. The orchestrator posts the skip note: "Step 7a Pass 1 re-run skipped: fixer push classified as trivial (non-structural, ≤10 lines). Proceeding directly to Pass 2." Pass 2 is re-dispatched on the new commit.

---

### Scenario 7: `max_internal_review_cycles` counts full restarts

**Maps to**: Acceptance Criterion 7

1. Configure `max_internal_review_cycles: 2` temporarily.
2. Run Step 7a on an implementation PR where each fix cycle introduces a non-trivial fix, causing a full Pass 1 → Pass 2 restart each time.
3. Observe when escalation occurs.

**Expected result**: The gate escalates after 2 full restart cycles (Pass 1 restart count = 2), not after 2 individual pass runs. The Step 7a summary comment shows `escalated — max cycles reached`.

---

### Scenario 8: Refactor item — Pass 1 evaluates work item brief

**Maps to**: Acceptance Criterion 8

1. Create a `refactor/*` draft PR for a Refactor item (no spec file; work item brief in tracker).
2. Initiate Step 7a.
3. Observe the Pass 1 dispatch prompt.

**Expected result**: Pass 1 dispatches the reviewer with instructions to evaluate against the work item brief (not a spec document, since none exists). The reviewer does not fail with "spec not found." Pass 2 evaluates code quality as normal.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: For an implementation PR with a configured internal reviewer, Step 7a runs Pass 1 (Spec Compliance) before Pass 2 (Code Quality). Pass 2 is not dispatched until Pass 1 approves.
- [ ] AC 2: For an implementation PR, both Pass 1 and Pass 2 must approve (at the same commit SHA) before the PR is converted from draft to non-draft via `gh pr ready`.
- [ ] AC 3: The Step 7a summary comment for an implementation PR labels findings separately for Pass 1 and Pass 2, and shows the verdict for each pass.
- [ ] AC 4: For a spec PR (`spec/*`) or plan PR (`implementation-plan/*`), Step 7a runs a single pass without any change to existing behavior.
- [ ] AC 5: If Pass 2 introduces a non-trivial fix, Pass 1 re-runs on the new commit before Pass 2 continues.
- [ ] AC 6: If Pass 2 introduces a trivial fix (meets the trivial-fix conditions in Protocol 91), Pass 1 re-run is skipped and a note is posted to the PR indicating the skip.
- [ ] AC 7: The `max_internal_review_cycles` limit is applied to full restart cycles (from Pass 1), not to individual pass runs.
- [ ] AC 8: The feature works correctly for Refactor items (no spec): Pass 1 evaluates against the work item brief.

---

## Seed Data Reference

No persistent seed data is required. Each scenario creates its own transient test PR on the fly.

| Entity | Scenario | How to load |
|---|---|---|
| Test fix branch | Scenarios 1–3, 5–7 | `git checkout -b fix/smoke-test-449 origin/develop` |
| Test spec branch | Scenario 4 | `git checkout -b spec/smoke-test-449 origin/develop` |
| Test refactor branch | Scenario 8 | `git checkout -b refactor/smoke-test-449 origin/develop` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pass 2 dispatched without Pass 1 approving | Orchestrator skipped branch-type detection | Verify that Protocol 91 Step 7a now contains the implementation-PR branch-type preamble |
| `gh pr ready` called before Pass 2 approves | Summary comment posted prematurely | Confirm the two-pass execution rule requires both passes approved at same SHA |
| Summary comment shows no pass labels | Old Step 7a code path still executing | Confirm Protocol 91 Step 7a summary comment template was updated |
| Pass 1 re-run after trivial fix | Trivial-fix conditions not validated by orchestrator | Confirm orchestrator independently verifies all three trivial-fix conditions before skipping |

---

## Known Limitations

- These scenarios require a working internal reviewer (`claude`) and a PR open on a real repository. They cannot be run in an offline environment.
- Scenario 7 requires temporarily lowering `max_internal_review_cycles` which modifies the shared config; restore after the test.
