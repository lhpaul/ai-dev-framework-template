# Smoke Test Runbook: Consolidate Lightweight PR Policy Workflows

**Feature**: Consolidate lightweight PR policy workflows
**Spec**: [1_1150-consolidate-lightweight-pr-policy-workflows_specs.md](../../specs/developments/20260705092758_1150-consolidate-lightweight-pr-policy-workflows/1_1150-consolidate-lightweight-pr-policy-workflows_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out.
- [ ] GitHub CLI authentication is available for repository metadata checks.
- [ ] No real fork PR code is checked out or executed as part of this smoke test.

---

## Test Data

| Item | Value |
| --- | --- |
| Consolidated workflow | `.github/workflows/pr-policy.yml` |
| Static workflow test | `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` |
| CI enforcement docs | `docs/workflow/development-workflow/integrations/ci-enforcement.md` |
| Regression docs | `docs/workflow/development-workflow/integrations/e2e-regression.md` |

---

## Smoke Test Steps

### Step 1: Validate the consolidated workflow exists

**Maps to**: AC1, AC3, AC13

1. Confirm `.github/workflows/pr-policy.yml` exists.
2. Confirm the old split workflow files were removed unless the implementation
   intentionally kept one with documented rationale:
   - `.github/workflows/apply-regression-label.yml`
   - `.github/workflows/remove-regression-label-on-push.yml`
   - `.github/workflows/reviewer-loop-guard.yml`
3. Read the consolidated workflow comments and confirm they state the
   recommendation or rationale for consolidation.

**Expected result**: One PR policy workflow owns the lightweight PR policy
surface, and documentation or comments explain why consolidation is the final
shape.

### Step 2: Validate trigger and event-routing coverage

**Maps to**: AC3, AC5, AC7, AC11

1. Inspect `.github/workflows/pr-policy.yml`.
2. Confirm it handles `pull_request_target` events for `opened`, `reopened`,
   `ready_for_review`, and `synchronize`.
3. Confirm it handles `issue_comment` events for `created` and `edited`.
4. Confirm non-summary comments exit without changing labels or statuses.
5. Confirm summary comments are recognized only when they include both canonical
   reviewer-loop summary markers.

**Expected result**: The workflow covers the full trigger matrix and preserves
the summary-comment readiness path.

### Step 3: Validate implementation branch scoping and label lifecycle

**Maps to**: AC5, AC6, AC12

1. Confirm `IN_SCOPE_PREFIXES` includes `feature/`, `fix/`, `refactor/`, and
   `hotfix/`.
2. Confirm non-implementation branches skip implementation-only label behavior.
3. Confirm same-repository implementation PRs do not apply
   `ready-for-regression` on open/reopen/ready-for-review alone.
4. Confirm clean or allowed-skipped canonical reviewer-loop summaries for the
   current PR head dispatch regression and then apply `ready-for-regression`.
5. Confirm synchronize behavior removes `ready-for-regression` when the label is
   present and no current-head clean reviewer-loop evidence exists.
6. Confirm synchronize behavior preserves reviewer-loop-owned labels when a
   clean canonical summary is bound to the current PR head.

**Expected result**: The consolidated workflow preserves the intended
`ready-for-regression` lifecycle and does not label non-implementation PRs.

### Step 4: Validate reviewer-loop guard status semantics

**Maps to**: AC7, AC8, AC11, AC13

1. Confirm the guard context remains
   `Reviewer-loop completion guard (#${PR_NUMBER})`.
2. Confirm implementation PRs without a reviewer-loop summary receive a failure
   status explaining that the reviewer loop must run.
3. Confirm implementation PRs with a canonical reviewer-loop summary receive a
   success status.
4. Confirm non-implementation PRs receive the existing successful skipped-guard
   meaning.

**Expected result**: Reviewer-loop readiness remains tied to the canonical
summary markers and scoped to the evaluated PR number.

### Step 5: Validate fork safety and permissions

**Maps to**: AC9, AC10, AC12

1. Confirm the workflow does not use `actions/checkout`.
2. Confirm fork-head PRs, where the head repository differs from the base
   repository, skip privileged label/status mutation.
3. Confirm permissions are limited to the combined behavior:
   - `issues: read`
   - `pull-requests: write`
   - `statuses: write`
4. Confirm no secrets beyond the default `GITHUB_TOKEN` are required.

**Expected result**: The workflow remains API-only and safe under privileged PR
events.

### Step 6: Run focused validation

**Maps to**: AC10, AC11, AC12, AC13

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh
   ```

2. Run markdown lint for the plan and this runbook.
3. Run the workflow shell guard from the implementation branch.

**Expected result**: Static workflow checks, markdown lint, and workflow shell
guard pass.

---

## Assertions Checklist

Each checkbox maps to acceptance criteria from the spec.

- [ ] A documented recommendation explains why consolidation proceeds or why it
      is deferred.
- [ ] The recommendation weighs downstream private-repository runner-minute risk
      against reviewer readiness, regression readiness, fork safety, and
      PR-scoped status safety.
- [ ] One PR policy workflow owns the current apply-label, stale-label removal,
      and reviewer-loop guard behavior if consolidation proceeds.
- [ ] Same-repository implementation PRs keep the expected
      reviewer-clean `ready-for-regression` lifecycle.
- [ ] Non-implementation PRs do not receive implementation-only labels or fail
      implementation-only reviewer-loop policy.
- [ ] Reviewer-loop readiness is still derived from canonical summary markers.
- [ ] Reviewer-loop guard status remains PR-number-scoped.
- [ ] Fork-originated PRs do not check out or execute untrusted code from a
      privileged workflow.
- [ ] Workflow permissions are minimal and documented.
- [ ] Trigger matrix, fork behavior, status context behavior, and stale
      `ready-for-regression` handling are covered by static checks.
- [ ] CI enforcement and e2e-regression documentation match the final workflow
      shape and signal names.

---

## Seed Data Reference

No application seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Workflow text | Static validation of consolidated PR policy workflow | Committed repository files |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Static test still looks for `reviewer-loop-guard.yml` only | Test was not updated for consolidation | Point the test at `pr-policy.yml` and add label lifecycle assertions. |
| Fork safety assertion fails | Workflow tries to mutate status or labels before checking head repository | Move fork-head checks before privileged operations. |
| `ready-for-regression` is removed after reviewer loop has run clean for the current head | Summary-comment result or head binding was not preserved in synchronize path | Restore canonical summary result parsing and current-head lookup before label removal. |
| Docs mention deleted workflow files as current behavior | Documentation updates missed old split workflow references | Update docs to name `pr-policy.yml` and keep old names only as historical replacement context. |

---

## Known Limitations

- This smoke test is mostly static because exercising live GitHub PR event
  permutations would require opening temporary PRs and comments. Implementation
  should rely on static checks plus one normal PR run through GitHub Actions.
