# Smoke Test Runbook: Regression After Reviewer Clean

**Feature**: Trigger regression only after reviewer-clean PRs
**Spec**: Refactor item #1615 brief in GitHub Issues
**Created in**: Plan Ready stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out.
- [ ] GitHub CLI authentication is available for repository metadata checks if
      live PR verification is performed.
- [ ] No fork PR code is checked out or executed as part of this smoke test.

---

## Test Data

| Item | Value |
| --- | --- |
| Consolidated policy workflow | `.github/workflows/pr-policy.yml` |
| Regression workflow | `.github/workflows/e2e-regression.yml` |
| Static workflow test | `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` |
| Label | `ready-for-regression` |
| Reviewer summary marker | `### Automated Reviewer Loop Summary` |

---

## Smoke Test Steps

### Step 1: Verify PR lifecycle events no longer trigger regression

**Maps to**: #1615 AC1

1. Inspect `.github/workflows/pr-policy.yml`.
2. Confirm `opened`, `reopened`, and `ready_for_review` events still participate
   in reviewer-loop guard/status evaluation where needed.
3. Confirm those PR lifecycle events do not call `gh workflow run` for
   regression and do not apply `ready-for-regression` solely because the event
   happened.

**Expected result**: Regression readiness is not triggered before reviewer-loop
clean evidence exists.

### Step 2: Verify non-clean summaries do not trigger regression

**Maps to**: #1615 AC2

1. Inspect the policy workflow summary-result parsing.
2. Confirm summaries with `needs_fixes`, `escalate`, `pending_timeout`,
   `timeout`, or missing canonical markers fail or skip the regression label and
   dispatch path.
3. Run the focused static workflow test:

   ```bash
   bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh
   ```

**Expected result**: Non-clean reviewer-loop outcomes keep
`ready-for-regression` absent and do not dispatch regression.

### Step 3: Verify clean current-head summaries trigger regression

**Maps to**: #1615 AC3

1. Confirm the workflow recognizes a canonical reviewer-loop summary with
   `Result: clean` or an allowed `Result: skipped`.
2. Confirm the workflow binds that result to the live PR head before mutation.
3. Confirm the workflow dispatches the configured regression workflow for that
   head and then applies `ready-for-regression` only after dispatch succeeds and
   metadata is still current.
4. Confirm repeated processing is idempotent.

**Expected result**: Clean current-head reviewer evidence triggers regression
readiness exactly through the post-reviewer path.

### Step 4: Verify stale clean summaries fail closed

**Maps to**: #1615 AC4

1. Inspect the stale-head guard for summary-driven regression dispatch.
2. Confirm a clean summary whose recorded head differs from the live PR head
   cannot apply `ready-for-regression`.
3. Confirm `synchronize` behavior prevents a post-clean push from reusing old
   reviewer evidence for a newer unreviewed head.

**Expected result**: A push after reviewer clean requires fresh reviewer-loop
evidence before regression readiness is restored.

### Step 5: Verify exempt and unsafe PRs remain non-mutating

**Maps to**: #1615 AC5

1. Confirm `spec/*`, `implementation-plan/*`, and graduation PRs do not receive
   implementation-only regression labels.
2. Confirm fork-head PRs still exit before privileged label, status, or workflow
   dispatch mutation.
3. Confirm `.github/workflows/e2e-regression.yml` keeps its label gate and
   dispatch input contract.

**Expected result**: The refactor changes timing only; it does not widen the
set of PRs that can receive privileged regression actions.

### Step 6: Verify recovery behavior remains intact

**Maps to**: #1615 AC6

1. Inspect Protocol 91 Step 8a behavior if needed.
2. Confirm the implementation does not remove the existing Step 8a fallback for
   missing `ready-for-regression`.
3. Confirm tests and docs describe Step 8a as recovery, while the normal path is
   summary-driven policy dispatch.

**Expected result**: Missing-label recovery remains available without becoming
the expected way to trigger regression.

---

## Assertions Checklist

- [ ] PR open/reopen/ready events do not trigger regression readiness.
- [ ] Non-clean reviewer summaries do not trigger regression readiness.
- [ ] Clean or allowed-skipped current-head summaries trigger regression
      readiness idempotently.
- [ ] Stale clean summaries fail closed after a new push.
- [ ] Exempt branch types and fork-head PRs remain non-mutating.
- [ ] Focused static workflow tests pass.
