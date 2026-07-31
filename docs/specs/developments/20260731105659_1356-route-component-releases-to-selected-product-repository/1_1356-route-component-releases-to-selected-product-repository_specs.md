# Route Component Releases To The Selected Product Repository - Spec

**Depends on**:
[1353-artifact-ownership-product-release-contract](../20260730174200_1353-artifact-ownership-product-release-contract/1_1353-artifact-ownership-product-release-contract_specs.md)
and
[1354-one-product-repository-per-implementation-item](../20260731064618_1354-one-product-repository-per-implementation-item/1_1354-one-product-repository-per-implementation-item_specs.md)

---

## Overview

Workflow hubs coordinate release work for multiple product repositories, but a
component release must execute against one selected product repository before it
creates branches, changelog entries, release pull requests, tags, deployment
evidence, or cleanup records. This feature makes that selection explicit for
component release and cleanup work, prevents hub defaults from accidentally
owning product release artifacts, and keeps tracker reconciliation in the hub.

The existing single-repository release and hotfix workflows continue to behave
as they do today. Product-repository release routing applies only when a
workflow hub is coordinating a component release for a selected product
repository.

## Brief Objective List

Derived from issue #1356:

1. Make component release preparation and post-merge cleanup product-aware in
   workflow-hub mode.
2. Require explicit product-repository selection before component release
   mutation.
3. Resolve the selected product repository's canonical repository identity and
   portable release fields from the product release contract, while resolving
   local checkout and environment-specific details from local-only
   configuration.
4. Keep the hub as tracker owner while preventing hub defaults from being used
   for product release artifacts.
5. Preserve existing standalone release and hotfix paths for single-repository
   mode.
6. Ensure a component release uses only the selected product repository's
   release artifacts.
7. Fail missing or ambiguous product selection before any branch, pull request,
   tag, or tracker mutation.
8. Make cleanup safe and rerunnable for a partially completed component
   release.
9. Produce component release evidence that delivery-bundle reconciliation can
   consume.

## Spec-Dispatch Context

Confirmed relationship decisions for epic #1352:

- #1356 depends on #1353 as the foundational artifact ownership and product
  release contract.
- #1356 depends on #1354 for the upstream one-product-repository selection and
  pre-mutation blocking rules. This spec applies those rules to component
  release preparation and cleanup rather than redefining the routing contract.
- #1356 is not dependent on #1357. This spec provides component release
  evidence that the later delivery-bundle workflow may consume, but it does not
  define the delivery-bundle issue or manifest workflow.
- #1356 is orthogonal to #1358 and #1359 beyond shared workflow-hub release
  terminology.

## Use Cases

### Use Case 1: Prepare a component release from a workflow hub

**Actor**: Workflow operator preparing a hub-managed component release.
**Preconditions**: The workflow hub has a valid product release contract, and
the operator intends to release one selected product repository.

**Steps**:

1. The operator starts release preparation from the workflow hub and names the
   selected product repository.
2. The workflow validates that exactly one known product repository is selected.
3. The workflow shows the selected product repository, release base, release
   branch pattern, changelog owner, tag owner, release record owner, deployment
   evidence owner, cleanup evidence owner, tracker reconciliation owner, and
   product CI evidence source.
4. The workflow prepares release artifacts only in the selected product
   repository.
5. The hub records release coordination and tracker evidence without creating
   product-owned release artifacts in the hub.

**Postconditions**: The component release has one product repository as the
release artifact owner, and the hub has coordination evidence that points to
that product release.

**Information shown**:

- Selected product repository key and repository identity.
- Release base and release branch that will be used.
- Product changelog, release pull request, tag, release record, CI, deployment,
  and cleanup evidence ownership.
- Local checkout source from local-only configuration when local product files
  must be inspected or mutated.
- Hub tracker reconciliation ownership.
- Stop reason when selection or contract validation fails.

**Actions available**:

- Continue when one selected product repository and a valid release contract are
  present.
- Stop before mutation when the product selection is missing, ambiguous,
  unknown, unavailable, or invalid.
- Correct the selection or product release contract and retry release
  preparation.

**Considerations**:

- A workflow hub may coordinate many products, but one component release run
  acts on exactly one selected product repository.
- Hub-owned coordination evidence must not be treated as a product release
  artifact.

---

### Use Case 2: Reject unsafe product selection before mutation

**Actor**: Release runner or cleanup helper.
**Preconditions**: The workflow is about to create or mutate a release branch,
release pull request, changelog entry, tag, deployment evidence, cleanup record,
or tracker state for a hub-managed component release.

**Steps**:

1. The runner reads the requested product repository selection.
2. The runner compares the selection against the product release contract.
3. The runner verifies that the versioned contract resolves the canonical
   repository identity and portable release fields for one product repository.
4. The runner verifies local-only checkout availability separately when local
   product files must be inspected or mutated.
5. The runner stops before any mutation if the selection is missing, ambiguous,
   unknown, invalid, or names more than one product repository.
6. The runner reports the required human action and leaves both hub and product
   repositories unmodified.

**Postconditions**: Unsafe component release routing cannot partially create
release artifacts in the wrong repository.

**Information shown**:

- The invalid or missing selection.
- The intended release operation that was blocked.
- The required correction.
- Confirmation that no release artifact mutation occurred.

**Actions available**:

- Retry with one explicit product repository selection.
- Correct the product release contract.
- Stop for human clarification when the release target is genuinely ambiguous.

**Considerations**:

- Tracker mutation is also blocked when the product selection itself is missing
  or ambiguous, because tracker state would otherwise imply a release progressed
  when no valid product release target was known.

---

### Use Case 3: Resume cleanup for a partially completed component release

**Actor**: Workflow operator reconciling a component release after merge,
interruption, or retry.
**Preconditions**: A component release run may have created, merged, or cleaned
some product-owned release artifacts already.

**Steps**:

1. The operator reruns cleanup from the workflow hub with the same selected
   product repository.
2. The workflow validates the same selected product repository and release
   contract before mutating anything.
3. The workflow compares the persisted release target with the current selected
   product repository, release correlation key, and release contract revision.
4. The workflow stops before mutation when the persisted release target no
   longer matches current release state.
5. The workflow reads current product release state from the selected product
   repository.
6. Already-completed cleanup actions are reported as complete rather than
   repeated destructively.
7. Missing cleanup actions are completed in the selected product repository.
8. Hub tracker reconciliation is updated only after product-owned cleanup state
   is confirmed.

**Postconditions**: Cleanup can be retried safely and converges to one
consistent product release state plus one hub-owned tracker reconciliation
state.

**Information shown**:

- Product release pull request state.
- Product release branch and tag cleanup status.
- Persisted release correlation key and contract revision or digest.
- Product deployment or release evidence status.
- Hub tracker reconciliation status.
- Any remaining manual action.

**Actions available**:

- Continue cleanup when validation passes.
- Report already-complete cleanup steps.
- Stop before mutation when the persisted canonical repository identity,
  release correlation key, or contract revision no longer matches the current
  release target.

**Considerations**:

- Cleanup must not infer a different product repository from the current hub
  checkout, branch name, or tracker owner.

## Component Release Routing Gate

Validation precedence is top-to-bottom. The first matching gate row determines
the canonical routing outcome for release and cleanup summaries.

| Gate input | Routing outcome | Allowed outcome | Required next action | Mirror surface | Example |
| --- | --- | --- | --- | --- | --- |
| Single-repository mode | `single_repo_release` | Continue with existing behavior | Use current release and hotfix paths without requiring a product repository selector | Release summary and existing PR evidence | A repository without workflow-hub mode prepares its own release from the current checkout. |
| No selected product repository in workflow-hub mode | `missing_product_selection` | Stop | Ask for one product repository selection before branch, pull request, tag, or tracker mutation | Stop summary and tracker-visible blocker evidence | The hub has multiple product repositories but the release command names none. |
| More than one selected product repository | `multiple_product_targets` | Stop | Split the release into one component release per product repository or choose one product | Stop summary and tracker-visible blocker evidence | The release request names both mobile and web product repositories. |
| Unknown product repository | `unknown_product_repository` | Stop | Correct product release configuration before mutation | Stop summary and validation output | The selected key is not in the product release contract. |
| One selected product repository cannot resolve to exactly one configured product repository | `ambiguous_product_selection` | Stop | Correct the selection or contract so one selected value maps to one product repository | Stop summary and validation output | A product alias matches multiple configured product repositories. |
| Invalid release artifact ownership | `invalid_release_contract` | Stop | Correct the release contract before mutation | Validation output and stop summary | The contract would write a product changelog, tag, or release record to the hub for a product-owned release. |
| Unavailable product repository checkout | `unavailable_product_repository_checkout` | Stop | Correct local-only checkout configuration before local mutation | Stop summary and validation output | The selected product repository is known, but its local checkout cannot be resolved when cleanup needs local files. |
| Exactly one selected product repository with a valid release contract and required checkout availability | `component_release_routed` | Continue | Prepare or clean up release artifacts in the selected product repository and reconcile tracker state in the hub | Release summary, PR body, cleanup log, and tracker comment | `faind-mobile-app` is selected and owns release branch, changelog, tag, deployment evidence, and cleanup evidence. |

## Business Rules

- A workflow-hub component release must name exactly one selected product
  repository before any release or cleanup mutation.
- Product-owned release artifacts for a workflow-hub component release belong
  to the selected product repository, not the hub.
- Hub tracker reconciliation remains hub-owned after product release artifacts
  are confirmed.
- Missing, ambiguous, unknown, unavailable, or multi-target product selection
  stops before branch, pull request, tag, changelog, deployment, cleanup, or
  tracker mutation.
- Release preparation and cleanup must use the same selected product repository
  identity throughout one component release lifecycle.
- Release preparation must persist an immutable release target containing the
  canonical repository identity, release correlation key, and release contract
  revision or digest before cleanup can later mutate product release artifacts.
- Cleanup must validate the persisted release target against current selection
  and contract state before mutation, and must stop when any persisted value
  differs.
- Cleanup must be rerunnable and must report already-completed product cleanup
  steps without requiring destructive repetition.
- Single-repository release and hotfix paths do not require product repository
  selection and keep their current artifact ownership.
- Component release evidence must follow the component release evidence record
  so later delivery-bundle reconciliation can identify the product repository,
  release artifact state, deployment evidence, cleanup outcome, routing outcome,
  and hub tracker reconciliation outcome.

## Component Release Evidence Record

Component release evidence is a machine-readable record that can be linked from
the hub tracker item and consumed by later delivery-bundle reconciliation. A
record may represent a completed, blocked, failed, or pending component release,
but each record identifies exactly one release target.

| Field | Presence | Type | Allowed values or format | Purpose |
| --- | --- | --- | --- | --- |
| Canonical product repository identity | Required | Owner and repository identity | One product repository from the release contract | Proves which product owns release artifacts. |
| Product repository key | Required | Stable product key | One configured key from the product release contract | Lets hub summaries and operators match the contract entry accepted by routing. |
| Release correlation key | Required | Stable text identifier | One value per attempted component release | Distinguishes separate releases for the same product repository. |
| Release contract revision | Required | Version, commit, or digest reference | The contract version used when release preparation began | Lets cleanup detect contract drift before mutation. |
| Release branch reference | Required when a release branch exists | Branch name or pull request branch reference | One valid branch reference for the selected product repository | Locates the product release branch. |
| Release pull request reference | Required when a release pull request exists | Pull request URL or number plus repository identity | One product repository pull request | Locates the product release pull request. |
| Product changelog reference | Optional | File path or release note reference | Product-owned changelog location or not applicable | Shows where release notes were prepared. |
| Tag or release record reference | Optional | Tag name, release URL, or not applicable | Product-owned tag or release record | Shows the shipped product release marker when one exists. |
| CI outcome | Required once product CI runs | `pending`, `passed`, `failed`, or `not_applicable` | One outcome for the product release validation surface | Lets bundle reconciliation distinguish validated and blocked releases. |
| Deployment evidence outcome | Required when deployment evidence is expected | `pending`, `recorded`, `failed`, or `not_applicable` | One outcome for the deployment evidence surface | Shows whether product deployment evidence exists. |
| Cleanup outcome | Required once cleanup starts | `not_started`, `partial`, `complete`, or `blocked` | One cleanup state for the selected product repository | Lets reruns and bundle reconciliation detect incomplete cleanup. |
| Routing outcome | Required | Canonical routing outcome code | One code from the `Routing outcome` column in the routing outcomes table | Explains whether release routing continued or stopped. |
| Release outcome | Required | `pending`, `completed`, `failed`, or `blocked` | Overall component release lifecycle state | Distinguishes final release state from routing validation state. |
| Hub tracker reference | Required | Hub issue, project item, or tracker URL | One hub-owned tracker reference | Connects product evidence back to hub reconciliation. |
| Human action required | Required when blocked | Short text instruction | One actionable correction or not applicable | Gives operators the next required step when routing or cleanup stops. |

## Statuses / Enum Values

No new tracker statuses are introduced. Existing workflow statuses keep their
current display labels and meanings. The values below are release-routing
outcomes that must be visible in release and cleanup summaries.

Validation precedence is the same order as the Component Release Routing Gate.
The first matching gate row maps to exactly one canonical outcome.

| Routing outcome | Display label | Description |
| --- | --- | --- |
| `single_repo_release` | Single-repository release | The current repository owns the release path and no product repository selector is required. |
| `missing_product_selection` | Missing product selection | No product repository was selected for a workflow-hub component release. |
| `multiple_product_targets` | Multiple product targets | The release request names more than one product repository up front and must be split or narrowed. |
| `unknown_product_repository` | Unknown product repository | The selected product repository key is not present in the product release contract. |
| `ambiguous_product_selection` | Ambiguous product selection | One requested product selection is present, but it cannot be resolved to exactly one known product repository. |
| `invalid_release_contract` | Invalid release contract | The selected product repository release contract is missing required portable release fields, contains unsafe values, or would route product artifacts to the wrong owner. |
| `unavailable_product_repository_checkout` | Unavailable product repository checkout | The selected product repository is known, but the local checkout needed for release or cleanup mutation is not available from local-only configuration. |
| `component_release_routed` | Component release routed | One selected product repository, a valid release contract, and required checkout availability allow release or cleanup to continue. |

## Operational Visibility

- **Release routing summary**: Before mutation, release preparation and cleanup
  show the selected product repository, artifact owners, release base, release
  branch, and tracker reconciliation owner.
- **Stop evidence**: Unsafe selection outcomes name the blocked operation, the
  invalid or missing selection, and the human action required to continue.
- **Product evidence**: Successful component release evidence names the product
  release pull request, release branch, tag or release record when applicable,
  CI outcome, deployment evidence, cleanup status, release correlation key, and
  release contract revision.
- **Hub evidence**: Hub tracker reconciliation records the selected product
  repository and points to product-owned release evidence instead of duplicating
  product release artifacts.
- **Rerun evidence**: Cleanup reports already-complete, completed-now, skipped,
  and blocked cleanup steps so a later run can distinguish convergence from
  silent omission.

## Acceptance Criteria

- [ ] A workflow-hub component release with exactly one selected product
      repository validates the product release contract and prepares release
      artifacts only in that selected product repository.
- [ ] A workflow-hub component release with missing product selection stops
      before branch, pull request, changelog, tag, deployment, cleanup, or
      tracker mutation and reports the required selection.
- [ ] A workflow-hub component release with ambiguous, unknown, unavailable, or
      multiple product targets stops before mutation and names the unsafe
      routing outcome.
- [ ] Release preparation shows the selected product repository's release base,
      release branch, changelog owner, release pull request owner, tag owner,
      product CI evidence source, deployment evidence owner, cleanup evidence
      owner, and hub tracker reconciliation owner.
- [ ] Post-merge cleanup for a component release validates the same selected
      product repository, release correlation key, and release contract revision
      before mutation and updates hub tracker state only after product-owned
      cleanup state is confirmed.
- [ ] Re-running cleanup after a partial component release reports completed
      steps as already complete and safely completes missing cleanup steps
      without switching product repositories.
- [ ] Single-repository release and hotfix workflows continue without requiring
      a product repository selector and continue to use current repository
      release artifacts.
- [ ] Component release evidence follows the component release evidence record
      and includes selected product repository, release correlation, release
      artifact, CI, deployment, cleanup, routing, and hub tracker reconciliation
      information for a later delivery-bundle workflow to consume.

## Out of Scope (MVP)

- Defining the delivery-bundle issue or manifest workflow; #1357 owns that
  behavior.
- Reconciling component milestones and release status rollups; #1358 owns that
  behavior.
- Adoption guidance, assurance runbooks, or migration criteria for downstream
  repositories; #1359 owns that behavior.
- Changing single-repository release semantics beyond preserving current
  compatibility.
- Adding a new tracker status taxonomy for release routing outcomes.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Make component release preparation and post-merge cleanup product-aware in workflow-hub mode. | Overview, Use Cases 1 and 3, Business Rules, AC1, AC5, AC6 |
| Require explicit product-repository selection before component release mutation. | Use Cases 1 and 2, Component Release Routing Gate, Business Rules, AC1, AC2, AC3 |
| Resolve canonical repository identity and portable release fields from the product release contract while resolving local checkout from local-only configuration. | Use Cases 1 and 2, Component Release Routing Gate, Component Release Evidence Record, Operational Visibility, AC4 |
| Keep the hub as tracker owner while preventing hub defaults from being used for product release artifacts. | Overview, Use Case 1, Business Rules, Operational Visibility, AC5 |
| Preserve existing standalone release and hotfix paths for single-repository mode. | Overview, Component Release Routing Gate, Business Rules, AC7 |
| Ensure a component release uses only the selected product repository's release artifacts. | Use Case 1, Business Rules, AC1 |
| Fail missing or ambiguous product selection before any branch, pull request, tag, or tracker mutation. | Use Case 2, Component Release Routing Gate, Business Rules, AC2, AC3 |
| Make cleanup safe and rerunnable for a partially completed component release. | Use Case 3, Business Rules, Operational Visibility, AC5, AC6 |
| Produce component release evidence that delivery-bundle reconciliation can consume. | Spec-Dispatch Context, Operational Visibility, AC8, Out of Scope |
