# Multi-Repository Release Adoption And Assurance - Spec

**Depends on**:
[1353-artifact-ownership-product-release-contract](../20260730174200_1353-artifact-ownership-product-release-contract/1_1353-artifact-ownership-product-release-contract_specs.md),
[1354-one-product-repository-per-implementation-item](../20260731064618_1354-one-product-repository-per-implementation-item/1_1354-one-product-repository-per-implementation-item_specs.md),
[1356-route-component-releases-to-selected-product-repository](../20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md),
[1357-delivery-bundle-issue-manifest-workflow](../20260731164352_1357-delivery-bundle-issue-manifest-workflow/1_1357-delivery-bundle-issue-manifest-workflow_specs.md),
and
[1358-component-milestones-release-statuses](../20260731193728_1358-component-milestones-release-statuses/1_1358-component-milestones-release-statuses_specs.md)

---

## Overview

Workflow hubs now have separate ownership rules for hub artifacts, product
release artifacts, delivery bundles, component evidence, and release-state
reconciliation. Teams need an adoption and assurance layer that explains how to
turn on the model, how to operate it safely, how to validate it with repeatable
fixtures, and how to migrate prospectively without rewriting historical release
records.

This feature makes the multi-repository release model adoptable by humans and
verifiable by automation. It covers setup, migration boundaries, release
runbooks, self-review evidence, deterministic regression coverage, and
troubleshooting for both workflow hubs and product repositories.

## Brief Objective List

Derived from issue #1359:

1. Add setup, operating, migration, and troubleshooting guidance for existing
   workflow hubs.
2. Add setup, operating, migration, and troubleshooting guidance for product
   repositories.
3. Add regression coverage for component routing.
4. Add regression coverage for configuration validation.
5. Add regression coverage for milestones.
6. Add regression coverage for bundle finalization.
7. Add regression coverage for partial failures.
8. Add regression coverage for reruns.
9. Add regression coverage for `single_repo` compatibility.
10. Add release-runbook or self-review evidence requirements for hub
    operations.
11. Add release-runbook or self-review evidence requirements for product
    operations.
12. Define prospective migration behavior.
13. Do not alter historical milestones automatically.
14. Provide an end-to-end non-secret fixture or equivalent deterministic harness
    for the full multi-repository release path.

## Spec-Dispatch Context

Confirmed relationship decisions for epic #1352:

- #1359 depends on #1353 for artifact ownership and product release contract
  terminology.
- #1359 depends on #1354 for the one selected product repository rule and
  child-item decomposition.
- #1359 depends on #1356 for selected-product release routing and component
  release evidence.
- #1359 depends on #1357 for delivery bundle adoption, finalization, and
  recovery guidance.
- #1359 depends on #1358 for namespaced component milestones, parent release
  states, and `single_repo` compatibility semantics.
- #1359 is the downstream assurance and adoption item for the full model; it
  should not redefine the runtime contracts owned by the dependency items.

## Use Cases

### Use Case 1: Adopt multi-repository releases in a workflow hub

**Actor**: Workflow maintainer responsible for a hub repository.
**Preconditions**: The repository is adopting the workflow-hub model and has at
least one product repository that may own product release artifacts.

**Steps**:

1. The maintainer reads the adoption guide for workflow hubs.
2. The maintainer confirms which artifacts the hub owns and which artifacts
   product repositories own.
3. The maintainer records the supported product repositories and required
   release contract information.
4. The maintainer validates the hub configuration before any release mutation.
5. The maintainer reviews the migration guidance for existing releases and
   confirms that historical release records will not be rewritten.
6. The maintainer runs the deterministic assurance checks for hub-owned
   release coordination.

**Postconditions**: The hub has a documented, validated path for coordinating
multi-repository releases without taking ownership of product release artifacts.

**Information shown**:

- Hub-owned artifacts and product-owned artifacts.
- Product repository release contract expectations.
- Adoption checklist status.
- Configuration validation result.
- Migration boundary and historical-record policy.
- Assurance run summary.

**Actions available**:

- Continue when required configuration and ownership guidance are complete.
- Stop before release mutation when product ownership, configuration, or
  migration boundaries are ambiguous.
- Re-run adoption validation after configuration changes.

**Considerations**:

- A hub can adopt the model prospectively even when older releases used a
  different convention.
- Historical milestones, tags, changelogs, and delivery records must remain
  unchanged unless a separate human-approved migration item explicitly scopes
  that repair.

---

### Use Case 2: Adopt multi-repository releases in a product repository

**Actor**: Product repository maintainer.
**Preconditions**: A workflow hub may route selected component releases to the
product repository.

**Steps**:

1. The maintainer reads the product repository adoption guide.
2. The maintainer confirms the product repository owns product changelog,
   release branch, tag, GitHub Release, CI, deployment evidence, and cleanup
   evidence for its own component releases.
3. The maintainer verifies the product release contract required by the hub.
4. The maintainer runs product-side validation without exposing secrets or
   local machine paths.
5. The maintainer follows the runbook for a selected component release and
   records self-review evidence before handoff back to the hub.

**Postconditions**: The product repository can participate in a hub-coordinated
release while preserving product-owned release authority and evidence.

**Information shown**:

- Product-owned release artifact checklist.
- Required release evidence before hub handoff.
- Validation and troubleshooting result.
- Product-side self-review evidence summary.
- Handoff state for the hub tracker.

**Actions available**:

- Complete product release evidence when product-owned steps finish.
- Stop when the selected product repository does not match the hub request.
- Retry cleanup and handoff steps safely after partial failure.

**Considerations**:

- Product repositories do not own hub specs, hub plans, delivery bundles, hub
  tracker state, or parent release-state reconciliation.
- Product-side evidence must be non-secret and portable enough for hub
  operators to verify.

---

### Use Case 3: Verify the full release path with deterministic assurance

**Actor**: Workflow maintainer or reviewer validating the model.
**Preconditions**: The multi-repository release model has been configured or
changed, and the maintainer needs confidence before using it on live releases.

**Steps**:

1. The maintainer runs the assurance suite or deterministic harness.
2. The harness exercises product selection, component release routing,
   configuration validation, delivery bundle updates, milestone
   reconciliation, partial failure handling, reruns, and `single_repo`
   compatibility.
3. The harness reports which release stages passed, which failed, and what
   evidence was produced.
4. The maintainer reviews the output as release-runbook or self-review evidence.
5. The maintainer stops live adoption when the harness cannot prove the required
   release path without secrets.

**Postconditions**: The team has repeatable evidence that the release model is
safe to operate for the covered scenarios.

**Information shown**:

- Covered release scenarios.
- Fixture or harness inputs.
- Pass, fail, blocked, and skipped outcomes.
- Evidence summaries for hub and product operations.
- Recovery guidance for failed or partial runs.

**Actions available**:

- Accept the assurance result when every required scenario passes.
- Re-run the harness after correcting configuration or evidence.
- Stop and document a blocker when an unverified path remains.

**Considerations**:

- The assurance path must not require real secrets, production deployments, or
  private local paths.
- Skipped checks must explain why they are not applicable; silent omissions are
  not acceptable for adoption evidence.

---

### Use Case 4: Migrate prospectively without rewriting history

**Actor**: Workflow maintainer adopting the model in an existing project.
**Preconditions**: The project has older release records, milestones, tags, or
delivery notes created before the workflow-hub release model.

**Steps**:

1. The maintainer reviews the migration guidance before changing release
   operations.
2. The maintainer identifies the first release or delivery that will use the
   new model.
3. The workflow explains which historical records are left as-is.
4. The workflow explains what new evidence is required for future releases.
5. The maintainer documents any historical inconsistency as a known legacy
   state rather than rewriting it automatically.

**Postconditions**: Future releases use the multi-repository model while
historical release records remain stable.

**Information shown**:

- Prospective adoption boundary.
- Historical artifacts that are not rewritten.
- New release evidence expectations.
- Known legacy-state notes.
- Human approval requirements for any separate historical repair.

**Actions available**:

- Start using the new model for future release work.
- Document legacy exceptions.
- Create a separate scoped migration or repair item only when humans explicitly
  approve historical changes.

**Considerations**:

- Automatic historical milestone rewrites are out of scope.
- Historical release data can be referenced for context but must not be mutated
  by adoption.

## Business Rules

- Adoption guidance must distinguish hub-owned artifacts from product-owned
  artifacts.
- Hub adoption must validate configuration before any branch, tag, release,
  tracker, milestone, or delivery-bundle mutation.
- Product adoption must validate selected-product ownership before any
  product-owned release mutation.
- Release-runbook evidence must show the selected product repository, release
  ownership, evidence handoff, cleanup result, and hub reconciliation state.
- Assurance coverage must include component routing, configuration validation,
  milestones, bundle finalization, partial failures, reruns, and `single_repo`
  compatibility.
- The end-to-end assurance path must be deterministic and non-secret.
- A skipped assurance scenario must state why it is not applicable.
- Existing historical release records must not be automatically rewritten by
  adoption.
- Prospective migration guidance must name the first release or delivery that
  uses the new model.
- Any historical repair must require a separate explicitly scoped human-approved
  item.
- Documentation must use the same ownership, release, bundle, component, and
  status language as the dependency specs.
- Adoption guidance must not redefine runtime contracts owned by #1353, #1354,
  #1356, #1357, or #1358.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `not_started` | Not started | Adoption has not been attempted for the repository or release path. |
| `configured` | Configured | Required ownership and product repository configuration exists. |
| `validated` | Validated | Configuration validation and required assurance checks passed. |
| `blocked` | Blocked | Adoption or assurance found a missing, ambiguous, or unsafe condition. |
| `deferred` | Deferred | Adoption is intentionally postponed with a recorded reason. |

**Valid transitions**:

- `not_started` -> `configured` when required ownership and product repository
  configuration is recorded.
- `configured` -> `validated` when validation and required assurance checks
  pass.
- `configured` -> `blocked` when validation finds a missing or unsafe
  condition.
- `blocked` -> `configured` when the blocking condition is corrected.
- `not_started` -> `deferred` when the team records that adoption is postponed.
- `deferred` -> `configured` when the team resumes adoption.

## Operational Visibility

- **Logs**: Adoption and assurance runs must report configuration scope,
  covered scenarios, skipped scenarios, pass/fail outcomes, and required next
  actions without printing secrets or private local paths.
- **Notifications**: No automatic notifications are required. Human-facing PR
  descriptions, runbooks, and tracker comments are sufficient for this feature.
- **Audit trail**: Release-runbook and self-review evidence must record the
  adoption boundary, validation result, assurance result, and any migration or
  legacy-state notes.

## Acceptance Criteria

- [ ] A workflow maintainer can follow hub adoption guidance that identifies
      hub-owned artifacts, product-owned artifacts, validation steps,
      troubleshooting, and the prospective migration boundary.
- [ ] A product repository maintainer can follow product adoption guidance that
      identifies product-owned release artifacts, evidence handoff
      requirements, validation steps, troubleshooting, and cleanup/retry
      expectations.
- [ ] The release runbook or self-review evidence requirements cover both hub
      operations and product operations.
- [ ] Regression coverage verifies component routing, configuration validation,
      namespaced component milestones, delivery bundle finalization, partial
      failures, reruns, and `single_repo` compatibility.
- [ ] The full multi-repository release path has an end-to-end non-secret
      fixture or equivalent deterministic harness that reports pass/fail/blocked
      outcomes and produced evidence.
- [ ] Prospective migration guidance states that historical milestones and other
      historical release records are not rewritten automatically.
- [ ] Skipped or not-applicable assurance checks include an explicit rationale.
- [ ] Documentation uses the ownership and status language established by
      #1353, #1354, #1356, #1357, and #1358 without redefining those runtime
      contracts.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Add setup, operating, migration, and troubleshooting guidance for workflow hubs | AC1 |
| Add setup, operating, migration, and troubleshooting guidance for product repositories | AC2 |
| Add regression coverage for component routing | AC4, AC5 |
| Add regression coverage for configuration validation | AC4, AC5 |
| Add regression coverage for milestones | AC4, AC5 |
| Add regression coverage for bundle finalization | AC4, AC5 |
| Add regression coverage for partial failures | AC4, AC5 |
| Add regression coverage for reruns | AC4, AC5 |
| Add regression coverage for `single_repo` compatibility | AC4, AC5 |
| Add release-runbook or self-review evidence requirements for hub operations | AC3 |
| Add release-runbook or self-review evidence requirements for product operations | AC3 |
| Define prospective migration behavior | AC1, AC6 |
| Do not alter historical milestones automatically | AC6 |
| Provide an end-to-end non-secret fixture or deterministic harness | AC5 |

## Out of Scope (MVP)

- Automatically rewriting, renaming, or backfilling historical milestones,
  tags, changelogs, delivery bundles, or tracker records.
- Introducing a shared suite version, shared release branch, or shared product
  release artifact across product repositories.
- Replacing the runtime contracts already owned by the artifact ownership,
  product selection, component release routing, delivery bundle, or component
  milestone features.
- Requiring production secrets, production deployments, or private local paths
  for assurance evidence.
