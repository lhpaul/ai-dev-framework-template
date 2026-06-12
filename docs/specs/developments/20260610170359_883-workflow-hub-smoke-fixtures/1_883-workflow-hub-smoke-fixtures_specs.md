# Workflow Hub Smoke Fixtures and Backwards-Compatibility Checks - Spec

**Depends on**: 875-shared-local-workflow-config, 876-workflow-hub-template-skeletons, 877-workflow-hub-product-repo-sync-status-scripts, 878-workflow-orchestration-product-repo-aware, 880-cross-repo-pr-auth-support

---

## Overview

Workflow hub support touches configuration parsing, repository-context
resolution, sync/status behavior, pull-request routing, and mode-specific sync
scope. This feature adds deterministic, non-secret smoke fixtures that model a
workflow hub and two dummy product repositories, plus single-repository
regression coverage proving existing adopters keep working. The fixture must be
safe for local and CI execution without private repositories or production
credentials.

## Brief Objective List

1. Add a workflow hub smoke fixture under the repository's fixture convention.
2. Model one workflow hub with two dummy product repositories.
3. Validate workflow config parsing.
4. Validate product repository resolution.
5. Validate sync/status command behavior.
6. Validate branch and pull-request command routing.
7. Validate mode-specific sync-template behavior.
8. Add single-repository regression coverage.
9. Avoid real production credentials.
10. Optionally include a separate live GitHub App validation path.
11. Ensure smoke fixture can run locally without secrets.
12. Ensure local checkout paths come from local config or documented defaults,
    not versioned secrets or `.tmp/template-config.json`.
13. Ensure CI can run non-secret smoke coverage.

## Use Cases

### Use Case 1: Maintainer runs non-secret workflow hub smoke coverage locally

**Actor**: Template maintainer
**Preconditions**: The maintainer has a local checkout of the framework
repository and no private product repository credentials configured.

**Steps**:

1. The maintainer runs the workflow hub smoke fixture.
2. The fixture creates or references one dummy workflow hub and two dummy
   product repositories.
3. The fixture runs config parsing and product repository resolution checks.
4. The fixture runs sync/status and command-routing checks in dry-run or
   fixture mode.
5. The fixture completes without requiring production secrets.

**Postconditions**: The maintainer has deterministic evidence that core
workflow hub behavior works without touching private product repositories.

**Information shown**:

- Fixture hub identity.
- Dummy product repository names and repository identities.
- Which checks passed or failed.
- Whether any check was skipped because it requires optional live credentials.

**Actions available**:

- Run the smoke fixture locally.
- Inspect fixture files.
- Re-run failed fixture checks after a fix.

**Considerations**:

- Fixture output must be deterministic enough to diagnose failures without
  private environment access.

### Use Case 2: CI runs non-secret workflow hub coverage

**Actor**: CI runner
**Preconditions**: A pull request changes workflow hub configuration,
orchestration, sync, authentication, or fixture behavior.

**Steps**:

1. CI runs the non-secret fixture test harness.
2. The harness uses dummy repository identities and local fixture paths.
3. The harness validates config parsing, product repository resolution,
   sync/status behavior, branch/PR routing construction, and mode-specific sync
   scope.
4. The harness fails if any non-secret workflow hub behavior regresses.

**Postconditions**: CI can block regressions without needing private
repositories, real GitHub App credentials, or production secrets.

**Information shown**:

- Test harness name.
- Per-check result.
- Failure reason and fixture path.

**Actions available**:

- Fix the failing workflow hub behavior.
- Re-run CI.

**Considerations**:

- CI must not require live GitHub App installation access for the default
  fixture path.

### Use Case 3: Single-repository adopter regression remains green

**Actor**: Existing single-repository adopter or maintainer
**Preconditions**: The workflow is running with missing mode or explicit
`single_repo` mode.

**Steps**:

1. The test harness runs the single-repository regression path.
2. The regression path confirms current default behavior still works without
   product repository selection.
3. The regression path confirms local checkout paths and hub-only config are
   not required.
4. The regression path reports success alongside workflow hub fixture checks.

**Postconditions**: Existing adopters have evidence that workflow hub support
did not make product repository configuration mandatory.

**Information shown**:

- Resolved single-repository mode.
- Existing behavior checks that passed.
- Any product repository selection requirement that would be a regression.

**Actions available**:

- Continue using the single-repository workflow.
- Report or fix regressions when product repository selection becomes required
  unexpectedly.

**Considerations**:

- Single-repository regression coverage is required because workflow hub support
  changes shared helpers used by existing adopters.

### Use Case 4: Operator optionally runs live GitHub App validation

**Actor**: Workflow hub operator
**Preconditions**: The operator has configured live GitHub App credentials for
safe test repositories.

**Steps**:

1. The operator opts into live GitHub App validation.
2. The live validation checks authentication and pull-request operation paths
   against safe test repositories.
3. The validation reports whether live app access works.
4. The default non-secret fixture remains available when live credentials are
   absent.

**Postconditions**: Operators who need live auth confidence can run an
explicitly opt-in check, while CI and local default smoke coverage remain
secret-free.

**Information shown**:

- Whether live validation was requested.
- Which safe test repository identity was used.
- Auth or access failure reason without secret disclosure.

**Actions available**:

- Run live validation after configuring credentials.
- Skip live validation and rely on non-secret fixture coverage.

**Considerations**:

- Live validation must be optional and must never run accidentally in default
  CI.

## Business Rules

- Default smoke coverage must run locally without secrets.
- Default CI smoke coverage must not require private repositories, production
  credentials, or live GitHub App installation access.
- The fixture must model one workflow hub and two dummy product repositories
  with distinct names and repository identities.
- Fixture product repository checkout paths must come from local workflow
  config or documented defaults.
- Fixture product repository checkout paths must not come from versioned secret
  values or `.tmp/template-config.json`.
- Single-repository regression coverage must remain part of the default
  non-secret test path.
- Pull-request routing validation may use dry-run or fixture output instead of
  opening real pull requests.
- Optional live GitHub App validation must be explicitly requested and
  separable from default CI.
- Fixture examples must avoid private project, repository, customer, and team
  names.

## Fixture Experience Rules

- Fixture setup should be documented with one local command.
- Fixture output must identify the hub and both dummy product repositories.
- Failures must name the fixture file or behavior that failed.
- Optional live validation output must state that it is not part of the default
  non-secret smoke path.
- The test harness must distinguish workflow hub failures from
  single-repository regression failures.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `non_secret` | Non-secret | Fixture path runs without private repositories or credentials. |
| `live_optional` | Live optional | Validation requires explicit opt-in live credentials. |
| `hub_fixture` | Hub fixture | The dummy workflow hub fixture context. |
| `product_fixture` | Product fixture | A dummy product repository fixture context. |
| `single_repo_regression` | Single-repo regression | Existing single-repository behavior check. |
| `dry_run_routing` | Dry-run routing | Command routing validated without mutating a real remote. |

**Valid transitions**:

- `non_secret` remains the default fixture mode in local and CI runs.
- `non_secret` -> `live_optional` only after the operator explicitly opts into
  live validation.
- `hub_fixture` and `product_fixture` are evaluated together for multi-repo
  smoke coverage.
- `single_repo_regression` runs independently of live validation.

## Operational Visibility

- **Fixture output**: Reports hub fixture identity, product repository fixture
  identities, and per-check results.
- **CI output**: Shows non-secret fixture and single-repository regression
  status.
- **Live validation output**: Clearly identifies live validation as opt-in and
  reports auth failures without secrets.

## Acceptance Criteria

- [ ] AC1: A workflow hub smoke fixture exists under the repository's fixture
      convention and can run locally without secrets.
- [ ] AC2: The fixture models one workflow hub and two dummy product
      repositories with different names and repository identities.
- [ ] AC3: Fixture coverage validates workflow config parsing and product
      repository resolution.
- [ ] AC4: Fixture coverage validates sync/status behavior for the dummy
      product repositories.
- [ ] AC5: Fixture coverage validates branch and pull-request command routing
      in dry-run or fixture mode without opening production pull requests.
- [ ] AC6: Fixture coverage validates mode-specific sync-template behavior.
- [ ] AC7: Tests prove local checkout paths come from
      `.ai-dev-workflow.local.yaml` or documented defaults, not versioned
      secrets or `.tmp/template-config.json`.
- [ ] AC8: A single-repository regression path remains green without requiring
      product repository selection.
- [ ] AC9: CI can run the non-secret smoke coverage without private product
      repositories or live GitHub App credentials.
- [ ] AC10: Optional live GitHub App validation, if included, is explicitly
      opt-in and separate from default local/CI smoke coverage.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Add a workflow hub smoke fixture under the repository's fixture convention. | AC1 |
| Model one workflow hub with two dummy product repositories. | AC2 |
| Validate workflow config parsing. | AC3 |
| Validate product repository resolution. | AC3 |
| Validate sync/status command behavior. | AC4 |
| Validate branch and pull-request command routing. | AC5 |
| Validate mode-specific sync-template behavior. | AC6 |
| Add single-repository regression coverage. | AC8 |
| Avoid real production credentials. | AC1, AC5, AC9 |
| Optionally include a separate live GitHub App validation path. | AC10 |
| Ensure smoke fixture can run locally without secrets. | AC1 |
| Ensure local checkout paths come from local config or documented defaults, not versioned secrets or `.tmp/template-config.json`. | AC7 |
| Ensure CI can run non-secret smoke coverage. | AC9 |

## Out of Scope (MVP)

- Requiring private product repositories for default smoke coverage.
- Requiring live GitHub App credentials in default local or CI runs.
- Opening production pull requests as part of default smoke coverage.
- Validating every downstream product repository topology.
- Replacing implementation-specific unit tests for individual workflow hub
  helpers.
- Storing real secrets, private repository names, or private team topology in
  fixture files.
