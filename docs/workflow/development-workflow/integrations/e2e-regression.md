# Integration: E2E / Regression Tests

This template includes a label-gated GitHub Actions workflow for e2e/regression testing:

- `.github/workflows/e2e-regression.yml`

The workflow triggers on PRs targeting `develop` or `main` when the `ready-for-regression` label is present. It is intentionally generic so downstream repositories can implement their own test suites.

---

## How It Fits Into the Workflow

The `ready-for-regression` label is applied by the orchestrator (Step 7b in `91-orchestrate-work-protocol.md`) after the automated reviewer loop (Step 7) is clean, and before the CI loop (Step 8). The prepare-release flow applies the same label on production release PRs per `05-prepare-release-protocol.md` Step 7.4. This means:

1. Step 7a: Internal review gate passes
2. Step 7: External automated reviewers are clean
3. **Step 7b: `ready-for-regression` label is applied** (triggers this workflow)
4. Step 8: CI loop polls `statusCheckRollup` — the e2e job appears as a check

Regression tests are expensive in time and compute, so they only run after all reviewer gates confirm the code is clean.

The CI loop (`pr-ci-loop.sh`) naturally picks up the e2e check result as part of its green/red polling. No script changes are needed.

---

## Label Gate Pattern

The workflow uses a two-part `if` condition:

```yaml
if: >-
  (github.event.action == 'labeled' && github.event.label.name == 'ready-for-regression') ||
  (github.event.action != 'labeled' && contains(github.event.pull_request.labels.*.name, 'ready-for-regression'))
```

- First clause: fires when the label is just applied
- Second clause: fires on `synchronize` (new push) or `reopened` if the label is already present

This means e2e tests re-run automatically after fixer pushes — the label stays on the PR, and `synchronize` triggers the second clause.

---

## Default Behavior

The template ships with a minimal Playwright project at `e2e/` that has one always-passing baseline test. This keeps the template pipeline green without external dependencies.

---

## What Downstream Repositories Should Customize

Replace the placeholder e2e project with project-specific tests:

1. Update `e2e/package.json` with your dependencies (Playwright, Cypress, etc.).
2. Configure `e2e/playwright.config.ts` (or equivalent) with your base URL, projects, web server, and auth setup.
3. Replace `e2e/tests/baseline.spec.ts` with real regression specs.
4. Update the workflow steps in `.github/workflows/e2e-regression.yml` if your test runner differs (e.g. different install commands, environment variables, artifact uploads).

You may also:

- Add the `E2E regression (placeholder)` check as a required status check in branch protection rules.
- Split into multiple workflow files for different test suites (each gated on `ready-for-regression`).
- Add environment variables or secrets for test infrastructure.

---

## Scope

The `ready-for-regression` label is applied to implementation PRs (`feature/*`, `fix/*`, `hotfix/*`, `refactor/*`) and to **production** release PRs (`release/*` → `main`) per [`05-prepare-release-protocol.md`](../protocols/05-prepare-release-protocol.md) Step 7.4, so e2e/regression can run before merge. Spec and plan PRs (`spec/*`, `implementation-plan/*`) skip this label and regression testing.

---

## Notes

- The label persists on the PR after e2e tests pass. It is not removed.
- This workflow does not store test credentials or environment URLs in the template.
- For projects without e2e tests, the baseline test keeps the check green. Alternatively, remove the workflow file and do not configure the check as required — the orchestrator will still apply the label but the CI loop will not block on a missing check.
