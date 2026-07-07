# Smoke Test Runbook: Placeholder Workflows Opt-In

**Feature**: Placeholder workflows opt-in
**Spec**: [1_1098-placeholder-workflows-opt-in_specs.md](../../specs/developments/20260701075304_1098-placeholder-workflows-opt-in/1_1098-placeholder-workflows-opt-in_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in the repository root.
- [ ] The implementation branch for #1098 is checked out.
- [ ] GitHub Actions workflow validation tools used by the repository are
      available locally.

---

## Test Data

No application seed data is required.

| Item | Value |
| --- | --- |
| Deploy workflow | `.github/workflows/deploy.yml` |
| Regression workflow | `.github/workflows/e2e-regression.yml` |
| Opt-in variable | `ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION` |
| Deploy confirmation input | `confirm_placeholder` |
| Regression label | `ready-for-regression` |

---

## Smoke Test Steps

### Step 1: Validate Placeholder Deploy Defaults

**Maps to**: AC1, AC4, AC7

1. Open `.github/workflows/deploy.yml`.
2. Confirm placeholder deploy jobs do not run from default `push` events.
3. Confirm manual dispatch remains available for temporary placeholder
   validation.
4. Confirm each placeholder deploy job requires an explicit confirmation input
   before it runs.

**Expected result**: A downstream repository that syncs the template and pushes
to `develop` or `main` does not run a placeholder deploy by default.

### Step 2: Validate Placeholder Regression Opt-In

**Maps to**: AC2, AC3, AC5, AC7

1. Open `.github/workflows/e2e-regression.yml`.
2. Confirm the workflow still recognizes the `ready-for-regression` label.
3. Confirm the placeholder dependency install, browser install, and test run are
   gated behind an explicit opt-in.
4. Confirm an unset opt-in variable prevents browser dependency installation.

**Expected result**: Adding `ready-for-regression` alone does not install
Playwright or browser dependencies when placeholder regression is not enabled.

### Step 3: Validate Label Automation Relationship

**Maps to**: AC3, AC6, AC7

1. Open `.github/workflows/pr-policy.yml`.
2. Confirm implementation PR label automation still applies
   `ready-for-regression`.
3. Confirm the regression workflow or docs make the label a readiness signal for
   configured real regression checks while keeping inactive placeholders cheap.

**Expected result**: Real project regression can remain label-gated, and the
template placeholder cannot spend browser-install minutes by label alone.

### Step 4: Run Static Validation

**Maps to**: AC1, AC2, AC3, AC7

1. Run `bash scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh`.
2. Run `actionlint .github/workflows/deploy.yml .github/workflows/e2e-regression.yml`.
3. Run markdown lint on the changed docs and this runbook.

**Expected result**: The focused static test, workflow syntax validation, and
documentation lint all pass.

### Step 5: Validate Documentation Coverage

**Maps to**: AC4, AC5, AC6

1. Open `docs/workflow/development-workflow/integrations/ci-cd-deployment.md`.
2. Confirm it explains the inactive deploy placeholder default and downstream
   replacement path.
3. Open `docs/workflow/development-workflow/integrations/e2e-regression.md`.
4. Confirm it explains the placeholder regression opt-in and the real
   label-gated replacement path.
5. Open the updated protocol docs and confirm they still require
   `ready-for-regression` for configured real regression gates.

**Expected result**: Downstream maintainers can tell how to keep placeholders
inactive, how to opt in temporarily, and how to enable real deploy/regression
workflows intentionally.

---

## Assertions Checklist

- [ ] AC1: Placeholder deploy jobs do not run on every push by default unless a
      downstream project opts in or replaces the placeholder.
- [ ] AC2: Placeholder regression jobs do not install Playwright or browser
      dependencies unless regression is intentionally enabled.
- [ ] AC3: `ready-for-regression` label automation does not accidentally trigger
      expensive placeholder regression work when regression is not enabled.
- [ ] AC4: Documentation explains the recommended downstream activation path for
      real deploy workflows.
- [ ] AC5: Documentation explains the recommended downstream activation path for
      real regression workflows.
- [ ] AC6: Existing release and reviewer-loop protocol guidance still describes
      how real regression should be label-gated when configured.
- [ ] AC7: Tests or static validation cover default-inactive deploy behavior,
      default-inactive regression behavior, and the label-trigger relationship.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Static test reports deploy push trigger still present | Placeholder deploy workflow can still run on default branch pushes | Remove the push activation path or add the missing confirmation gate, then rerun the test. |
| Static test reports Playwright install is ungated | The expensive regression steps can still run without explicit opt-in | Add or restore the opt-in guard around dependency install, browser install, and test execution. |
| `actionlint` fails | Workflow syntax is invalid after trigger or input edits | Fix the reported workflow syntax and rerun `actionlint`. |

---

## Known Limitations

- This runbook validates the template placeholder contract. It does not validate
  any downstream project's real deployment provider or real regression suite.
