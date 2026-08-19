# Multi-Repository Release Adoption And Assurance Smoke Test

## Scope

This runbook verifies #1359 adoption and assurance behavior after
implementation. It covers hub adoption, product adoption, deterministic
assurance outcomes, reruns, historical no-rewrite checks, and `single_repo`
compatibility.

## Preconditions

- The implementation branch contains the #1359 adoption guide, assurance
  harness, fixtures, and tests.
- The repository is checked out on the #1359 implementation branch.
- No production secrets, production deployments, or private local paths are
  required.

## Automated Verification

1. Run syntax and shell lint for the new scripts.

   ```bash
   bash -n scripts/development-workflow/multi-repo-release-assurance.sh \
     scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh \
     scripts/development-workflow/tests/test-multi-repo-release-assurance.sh
   shellcheck scripts/development-workflow/multi-repo-release-assurance.sh \
     scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh \
     scripts/development-workflow/tests/test-multi-repo-release-assurance.sh
   ```

2. Run the deterministic assurance suite.

   ```bash
   bash scripts/development-workflow/tests/test-multi-repo-release-assurance.sh
   ```

   Expected result: the suite passes and reports coverage for component
   routing, configuration validation, namespaced milestones, bundle
   finalization, partial failures, reruns, historical no-rewrite baselines, and
   `single_repo` compatibility.

3. Run dependency suites that the assurance harness composes.

   ```bash
   bash scripts/development-workflow/tests/test-component-release-target.sh
   bash scripts/development-workflow/tests/test-component-release-evidence.sh
   bash scripts/development-workflow/tests/test-delivery-bundle-manifest.sh
   bash scripts/development-workflow/tests/test-component-milestone-reconciliation.sh
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
   ```

   Expected result: all dependency suites remain green.

4. Run workflow-hub documentation coverage.

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-docs.sh
   ```

   Expected result: the test confirms the adoption guide, assurance contract,
   outcome vocabulary, migration boundary, and historical no-rewrite policy are
   linked from the workflow-hub docs.

## Manual Review

1. Open `docs/workflow/development-workflow/multi-repo-release-adoption.md`.

   Expected result: the guide distinguishes hub-owned and product-owned
   artifacts, explains adoption setup for both repository roles, and names the
   canonical assurance contract.

2. Inspect the assurance harness output for a passing fixture run.

   Expected result: output includes `schema_version`, `adoption_status`,
   `scenario_results`, `historical_no_rewrite`, `owner_actions`, and
   `required_next_action`.

3. Inspect a fixture run with a skipped scenario.

   Expected result: the skipped scenario includes an applicability rationale,
   and adoption can be validated only when every required scenario is `pass` or
   approved `skipped`.

4. Inspect a fixture run with a retryable cleanup or handoff step.

   Expected result: durable run and step identities are visible, stale attempts
   are rejected, and completed side effects are not repeated.

5. Inspect historical baseline fixtures before and after an assurance run.

   Expected result: hub-owned and product-owned historical milestones, tags,
   changelogs, delivery records, and tracker records are unchanged.

6. Inspect the `single_repo` compatibility scenario.

   Expected result: the non-hub release path remains compatible with the #1358
   invariant and does not require workflow-hub adoption fixtures.

## Closeout

- Record the automated suite output and any manual review notes in the
  implementation PR.
- Stop before readiness if any required scenario is `fail`, `blocked`, or
  unresolved `retryable`.
