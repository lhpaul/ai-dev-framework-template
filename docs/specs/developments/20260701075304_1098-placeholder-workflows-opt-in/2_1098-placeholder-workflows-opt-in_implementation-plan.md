# Placeholder Workflows Opt-In - Implementation Plan

**Spec**: [1_1098-placeholder-workflows-opt-in_specs.md](1_1098-placeholder-workflows-opt-in_specs.md)
**Smoke test runbook**: [1098-placeholder-workflows-opt-in.smoke-test.md](../../../testing/workflow/1098-placeholder-workflows-opt-in.smoke-test.md)

---

## Summary

**Approach**: Make the template placeholder deploy workflow manual-only with an
explicit confirmation input, and keep the placeholder regression workflow
label-compatible while preventing dependency and browser installation unless a
downstream maintainer explicitly enables placeholder regression. Update the
workflow integration docs and protocol references so they distinguish real
project regression checks from inactive template scaffolding.

**Estimated complexity**: M

**Rationale**: The code changes are small, but they touch shared GitHub Actions
defaults, workflow documentation, and static validation for behavior that
downstream repositories inherit.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `471c3ae` |
| Deploy placeholder default behavior | `rg -n "push:|workflow_dispatch|github.event_name == 'push'|deploy-(develop\|production)|Template placeholder" .github/workflows/deploy.yml` | `deploy.yml` currently has `push` triggers for `develop` and `main`, plus both placeholder jobs include `github.event_name == 'push'` clauses. |
| Regression placeholder cost path | `rg -n "ready-for-regression|Install Playwright browsers|npx playwright install|npm ci|pull_request|ENABLE|vars\\." .github/workflows/e2e-regression.yml .github/workflows/apply-regression-label.yml docs/workflow/development-workflow/integrations/e2e-regression.md docs/workflow/development-workflow/integrations/ci-enforcement.md` | `e2e-regression.yml` currently runs on `pull_request` label/synchronize/reopened events and reaches `npm ci` plus `npx playwright install --with-deps chromium` whenever `ready-for-regression` is present; no opt-in variable is present. |
| Existing label-gated protocol guidance | `rg -n "ready-for-regression|e2e/regression|regression" docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md \| head -80` | Protocols `05`, `91`, and `92` already require `ready-for-regression` for configured implementation and production release regression gates; wording needs clarification that inactive placeholders may skip until enabled or replaced. |
| Documentation surfaces | `find docs/workflow/development-workflow/integrations docs/testing/workflow scripts/development-workflow/tests -maxdepth 1 -type f \| sort` | Existing integration docs include `ci-cd-deployment.md`, `e2e-regression.md`, and `ci-enforcement.md`; existing workflow test directory supports focused shell tests. |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Update `.github/workflows/deploy.yml` so placeholder deploy jobs no longer
      run on default branch pushes. Keep `workflow_dispatch` and add an explicit
      confirmation input for temporary placeholder validation. Both placeholder
      jobs should require the manual dispatch event, matching environment input,
      and the confirmation input before running.
- [ ] Update `.github/workflows/e2e-regression.yml` so the workflow remains
      compatible with the `ready-for-regression` label model, but the placeholder
      `npm ci`, Playwright browser install, and test steps only run when an
      explicit downstream opt-in is set. Use a clearly named repository variable
      such as `ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION=true`; an unset variable
      must be treated as disabled.
- [ ] Preserve the existing `pull_request` label/synchronize/reopened trigger
      shape for regression so downstream repositories can replace the placeholder
      with a real suite without changing the staged workflow's label semantics.
- [ ] Do not modify `.github/workflows/apply-regression-label.yml` unless the
      implementation discovers a direct label lifecycle bug. The label automation
      should continue to apply `ready-for-regression`; the placeholder regression
      workflow is responsible for treating the label as non-expensive until the
      placeholder is enabled or replaced.

### Documentation

- [ ] Update deployment guidance to explain that template deploy placeholders
      are inactive on push by default, how to run a temporary manual placeholder
      validation, and how downstream projects should replace the placeholder with
      real push-triggered deployment logic.
- [ ] Update regression guidance to explain the opt-in variable for placeholder
      regression, that an unset variable skips dependency and browser setup, and
      that real project suites should remain label-gated by
      `ready-for-regression` when configured.
- [ ] Update CI enforcement guidance so the auto-applied
      `ready-for-regression` label is described as a readiness signal for real
      regression checks, not as permission for inactive placeholders to spend
      runner minutes.
- [ ] Update protocol wording in `05`, `91`, and `92` only where needed to
      clarify that label-gated regression means configured real regression
      checks or an explicitly enabled placeholder.

### Shared Workflow Tests

- [ ] Add `scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh`
      with static checks for deploy push inactivity, regression opt-in gating,
      preserved `ready-for-regression` trigger semantics, and documentation
      coverage.
- [ ] Ensure the test fails if `deploy.yml` reintroduces a default `push` trigger
      for placeholder deploy jobs or if `e2e-regression.yml` can reach
      dependency/browser install without the explicit opt-in guard.

---

## Testing Strategy

**Test types**: Static shell validation, workflow syntax validation, markdown
linting, and smoke/manual review.

**Key scenarios to test**:

1. Default deploy push is inactive - maps to AC1.
2. Placeholder regression dependency and browser installation is blocked unless
   opt-in is enabled - maps to AC2.
3. `ready-for-regression` label automation remains intact but cannot by itself
   trigger expensive placeholder regression work - maps to AC3 and AC7.
4. Deployment activation docs explain replacing or explicitly validating the
   placeholder - maps to AC4.
5. Regression activation docs explain the opt-in variable and the real
   label-gated replacement path - maps to AC5 and AC6.

**Smoke test runbook**: `docs/testing/workflow/1098-placeholder-workflows-opt-in.smoke-test.md`

**Regression suite**: Add
`scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh` to the
workflow test suite.

### Parser-risk Addendum

This plan is parser-risk because the new shell test statically scans GitHub
Actions YAML and markdown documentation with structured-text checks.

- **Edge-case enumeration**:
  - Deploy workflow has a top-level `push:` trigger active in the `on:` block.
  - Deploy workflow has only `workflow_dispatch` but a job-level `if` clause
    still contains `github.event_name == 'push'`.
  - Deploy workflow references a placeholder deploy job without requiring the
    explicit confirmation input.
  - Regression workflow preserves the `ready-for-regression` label condition,
    but expensive steps are missing the explicit opt-in guard.
  - Regression workflow contains `npx playwright install` in a step that can run
    when the opt-in variable is unset.
  - Documentation mentions label-gated regression but omits the inactive
    placeholder default or downstream activation path.
- **Unit test mapping**:
  - `scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh`
    should include a focused assertion for each edge case above.
- **Suppression semantics**: Not applicable - the static checks do not support
  inline suppression directives.

### Concurrent-Event-Source Addendum

Not applicable. The workflows receive multiple GitHub event types, but the
implementation does not introduce shared mutable state across concurrent event
handlers. GitHub Actions jobs evaluate each event independently.

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/ci-cd-deployment.md` -
      document dispatch-only placeholder deploy defaults, confirmation input,
      and downstream replacement guidance for real push-triggered deploys.
- [ ] `docs/workflow/development-workflow/integrations/e2e-regression.md` -
      document the placeholder regression opt-in variable, default skip
      behavior, and real label-gated regression activation path.
- [ ] `docs/workflow/development-workflow/integrations/ci-enforcement.md` -
      clarify that `apply-regression-label.yml` still applies the readiness
      signal but inactive placeholders must not spend runner minutes.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      - clarify that production release regression waits for configured real
      regression checks or an explicitly enabled placeholder.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - clarify Step 7b/Step 8 wording for configured real regression checks
      while preserving the label requirement.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      - clarify the readiness label meaning after placeholder regression becomes
      inactive by default.
- [ ] `docs/testing/workflow/1098-placeholder-workflows-opt-in.smoke-test.md` -
      add the smoke runbook during Plan Ready and update it during
      implementation if commands or activation names change.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Downstream projects assume deploys still run on every push after syncing | Medium | Medium | Document that placeholders are inactive by default and that real deploy workflows should reintroduce project-specific push triggers. |
| Gating placeholder regression causes a required check to be skipped in a repository that already made the placeholder required | Low | Medium | Document the opt-in variable and recommend replacing the placeholder with a real required check before enforcing branch protection. |
| Static workflow checks become brittle because they scan YAML text | Medium | Low | Keep assertions focused on stable contract strings and validate with `actionlint` in addition to the focused shell test. |
| Protocol wording accidentally weakens the real regression label requirement | Low | High | Limit protocol edits to clarification that real configured regression remains label-gated; do not change label application rules. |

---

## Code Samples

No production code samples are included. Workflow details should be implemented
directly in the implementation PR and validated with `actionlint`.

---

## Implementation Order

1. Update `.github/workflows/deploy.yml`.
   - Remove the default `push` trigger for placeholder deploys.
   - Keep `workflow_dispatch` with the existing environment choice.
   - Add an explicit confirmation input such as `confirm_placeholder`.
   - Gate `deploy-develop` and `deploy-production` on manual dispatch, matching
     environment, and confirmation.
   - Verify by reading the workflow and confirming no placeholder job can run
     from a push event.
2. Update `.github/workflows/e2e-regression.yml`.
   - Keep the `pull_request` trigger and `ready-for-regression` label condition.
   - Add the explicit placeholder opt-in guard, using an unset repository
     variable as disabled.
   - Ensure expensive steps (`npm ci`, Playwright browser install, and test run)
     cannot execute when the opt-in guard is false.
   - Verify by confirming the workflow still references
     `ready-for-regression` and that expensive steps are gated by the opt-in
     mechanism.
3. Add `scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh`.
   - Assert deploy placeholders are dispatch-only and confirmation-gated.
   - Assert regression placeholders preserve label semantics but require the
     explicit opt-in before dependency/browser installation.
   - Assert the docs name the inactive defaults and downstream activation paths.
4. Update documentation listed in **Documentation Updates**.
   - Keep protocol label requirements intact.
   - Clearly distinguish inactive placeholders from configured real regression
     and deploy workflows.
5. Update `docs/testing/workflow/1098-placeholder-workflows-opt-in.smoke-test.md`
   if implementation details differ from this plan.
6. Run focused validation:
   - `bash scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh`
   - `shellcheck scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh`
   - `actionlint .github/workflows/deploy.yml .github/workflows/e2e-regression.yml`
   - `npx markdownlint-cli2 "docs/specs/developments/20260701075304_1098-placeholder-workflows-opt-in/2_1098-placeholder-workflows-opt-in_implementation-plan.md" "docs/testing/workflow/1098-placeholder-workflows-opt-in.smoke-test.md" "docs/workflow/development-workflow/integrations/ci-cd-deployment.md" "docs/workflow/development-workflow/integrations/e2e-regression.md" "docs/workflow/development-workflow/integrations/ci-enforcement.md" "docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md" "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md"`
   - `git diff --check`
7. Update `CHANGELOG.md` under `[Unreleased]` with:
   - `- **Placeholder workflows opt-in** (#1098): Make template placeholder deploy and regression workflows opt-in so downstream repositories do not spend runner minutes before configuring real pipelines.`
