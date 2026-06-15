# Smoke Test Runbook: Workflow Orchestration Product Repository Awareness

**Feature**: Workflow orchestration product repository awareness
**Spec**: [1_878-workflow-orchestration-product-repo-aware_specs.md](../../specs/developments/20260610164605_878-workflow-orchestration-product-repo-aware/1_878-workflow-orchestration-product-repo-aware_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #878.
- [ ] #875 is already merged into `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Discovery script | `scripts/development-workflow/discover-workflow-state.sh` |
| Next-action script | `scripts/development-workflow/workflow-next-action.sh` |
| Batch planner | `scripts/development-workflow/workflow-batch-plan.sh` |
| Reviewer loop | `scripts/development-workflow/pr-review-loop.sh` |
| CI loop | `scripts/development-workflow/pr-ci-loop.sh` |
| Cleanup script | `scripts/development-workflow/post-merge-cleanup.sh` |
| Workflow library | `scripts/development-workflow/workflow-lib.sh` |
| Product-aware tests | `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh` |

---

## Smoke Test Steps

### Step 1: Verify Single-Repository Regression

**Maps to**: AC1

1. Run the product-aware orchestration test harness.
2. Inspect the missing-mode and explicit `single_repo` fixture output.
3. Confirm discovery, next-action, batch planning, reviewer loop, CI loop, and
   cleanup do not require a product repository selector.

**Expected result**: Existing single-repository behavior remains valid.

### Step 2: Verify Product Repository Selection

**Maps to**: AC2, AC3, AC9

1. Use a workflow hub fixture with two product repositories.
2. Run next-action planning for implementation work with `--repo <name>`.
3. Confirm output names the selected product repository.
4. Run the same implementation action without selection.
5. Confirm the script fails clearly before product branch or PR inspection.

**Expected result**: Implementation actions require and report one selected
product repository in workflow hub mode.

### Step 3: Verify Hub-Owned and Product-Owned State Separation

**Maps to**: AC4

1. Run discovery and batch planning against the workflow hub fixture.
2. Confirm tracker, spec, and plan state are reported as hub-owned.
3. Confirm implementation branch and implementation PR state are reported as
   product-repository-owned.
4. Confirm file-conflict output does not compare hub paths and product paths as
   the same repository namespace.

**Expected result**: Output separates ownership instead of collapsing everything
into the hub repository.

### Step 4: Verify Reviewer Loop Routing

**Maps to**: AC5

1. Run the reviewer-loop fixture for an implementation PR in a product repo.
2. Confirm the command uses the selected product repository slug for PR API
   calls.
3. Confirm reviewer-loop output and summary include the selected repository.

**Expected result**: Implementation PR review targets the product repository.

### Step 5: Verify CI Loop Routing

**Maps to**: AC6

1. Run the CI-loop fixture for an implementation PR in a product repo.
2. Confirm the command polls checks in the selected product repository.
3. Confirm output includes `REPO=<owner/repo>` for the selected repository.

**Expected result**: Implementation PR CI readiness reflects the product PR,
not a hub PR with the same number.

### Step 6: Verify Cleanup Ownership

**Maps to**: AC7

1. Run cleanup fixture cases for a merged implementation branch and a merged
   plan branch.
2. Confirm implementation cleanup runs in the selected product checkout.
3. Confirm spec and plan cleanup remain in the workflow hub checkout.
4. Confirm tracker updates still target the hub project.

**Expected result**: Cleanup deletes branches in the owning repository only.

### Step 7: Verify Tracker Helper Ownership

**Maps to**: AC8

1. Run the fixture case with a selected product repository.
2. Trigger status/type helper reads or updates.
3. Confirm the helper uses the workflow hub GitHub Projects context.
4. Confirm no product repository tracker is queried unless explicitly
   configured by a future workflow contract.

**Expected result**: Tracker state remains hub-owned.

### Step 8: Run Automated Validation

**Maps to**: AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   ```

2. Run shell and markdown validation from the implementation plan.

**Expected result**: Multi-product and single-repository regression paths pass.

---

## Assertions Checklist

- [ ] AC1: Missing-mode and `single_repo` behavior remains unchanged.
- [ ] AC2: Workflow hub implementation next-action planning resolves and
      reports one selected product repository.
- [ ] AC3: Missing or ambiguous product repository selection fails clearly.
- [ ] AC4: Discovery and batch planning distinguish hub-owned tracker/spec/plan
      state from product-owned implementation state.
- [ ] AC5: Reviewer-loop checks target the selected product repository.
- [ ] AC6: CI-loop checks target the selected product repository.
- [ ] AC7: Cleanup runs in the repository that owns the merged work.
- [ ] AC8: Project status/type helper paths remain hub-owned.
- [ ] AC9: Missing/ambiguous selection errors occur before product mutations.
- [ ] AC10: Tests cover one multi-product path and one single-repository
      regression path.

---

## Seed Data Reference

No persistent seed data is required. The automated test harness should create
temporary hub and product repository fixtures.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Single-repo fixtures require `--repo` | Mode default was changed accidentally | Restore missing mode -> `single_repo` behavior. |
| Product PR checks read the hub PR | `gh pr view` lacks an explicit `--repo` route | Use the resolved product repository slug for implementation PRs. |
| Tracker updates hit a product repo | Tracker helpers consumed implementation repo context | Keep tracker helpers anchored to the workflow hub. |
| Cleanup deletes a hub branch for implementation work | Branch ownership was inferred from current directory only | Resolve branch type plus selected product repository before cleanup. |

---

## Known Limitations

- This smoke test uses fixtures and command stubs. It does not require live
  product repositories or real cross-repository pull requests.
