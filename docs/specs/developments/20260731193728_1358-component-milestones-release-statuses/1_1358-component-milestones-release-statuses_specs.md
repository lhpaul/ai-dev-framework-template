# Component Milestones And Release Statuses - Spec

**Depends on**:
[1353-artifact-ownership-product-release-contract](../20260730174200_1353-artifact-ownership-product-release-contract/1_1353-artifact-ownership-product-release-contract_specs.md),
[1354-one-product-repository-per-implementation-item](../20260731064618_1354-one-product-repository-per-implementation-item/1_1354-one-product-repository-per-implementation-item_specs.md),
[1356-route-component-releases-to-selected-product-repository](../20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md),
and
[1357-delivery-bundle-issue-manifest-workflow](../20260731164352_1357-delivery-bundle-issue-manifest-workflow/1_1357-delivery-bundle-issue-manifest-workflow_specs.md)

---

## Overview

Workflow hubs need release-status reconciliation that respects repository
ownership. Product component milestones are repository-scoped, but hub epics and
delivery bundles can represent a customer-facing release that spans multiple
product repositories. This feature makes component milestone stamping
namespaced and targeted, lets each component child reach release status
independently, and keeps the parent epic unreleased until the completed delivery
bundle gate passes.

The existing single-repository milestone behavior continues to work as it does
today. Multi-repository release reconciliation applies only when a workflow hub
is coordinating component releases through selected product repositories and a
delivery bundle records the final shipped composition.

## Brief Objective List

Derived from issue #1358:

1. Introduce namespaced hub milestone titles in the form `<product-repo>@<tag>`.
2. Stamp only the matching repository-scoped child after its component release
   is verified.
3. Keep cross-repository epics milestone-free.
4. Keep delivery issues milestone-free; shipped composition lives in the
   delivery manifest.
5. Define component-child status transitions for independent release,
   retries, and failures.
6. Define parent-epic status transitions for partial shipment and final bundle
   release.
7. Preserve existing single-repository `vX.Y.Z` milestone behavior.

## Spec-Dispatch Context

Confirmed relationship decisions for epic #1352:

- #1358 depends on #1353 for artifact ownership and the product release
  contract.
- #1358 depends on #1354 for the rule that product implementation and release
  work has exactly one selected product repository.
- #1358 depends on #1356 for component release evidence from the selected
  product repository.
- #1358 depends on #1357 for the delivery bundle manifest that represents the
  final customer-facing composition.
- #1359 is downstream assurance and adoption work. This spec defines the
  release-status semantics that #1359 can document and test more broadly.

## Use Cases

### Use Case 1: Stamp a verified component release milestone

**Actor**: Workflow operator reconciling a completed component release.
**Preconditions**: A component child belongs to one selected product repository,
and that component release has verified release, cleanup, and tracker evidence.

**Steps**:

1. The operator starts hub tracker reconciliation for the completed component
   child.
2. The workflow identifies the selected product repository and component tag
   from verified component release evidence.
3. The workflow shows the namespaced component milestone that represents that
   repository-scoped shipment.
4. The workflow stamps the milestone only on the matching component child.
5. The workflow marks the component child as released when the milestone and
   release evidence agree.
6. The workflow leaves the parent epic and delivery bundle milestone-free.

**Postconditions**: The component child reflects its own completed product
release without implying that the full cross-repository delivery has shipped.

**Information shown**:

- Selected product repository.
- Component tag or released version.
- Namespaced component milestone.
- Component child tracker status.
- Release evidence and cleanup evidence summary.
- Parent epic and delivery bundle status.

**Actions available**:

- Continue when release evidence is verified and the milestone target matches
  the selected product repository.
- Stop before tracker mutation when the selected product repository, tag, or
  child item does not match the evidence.
- Retry after missing release or cleanup evidence is completed.

**Considerations**:

- A customer-facing delivery can have one component released while another
  component remains unreleased.
- Milestone stamping must not make the parent epic look fully released.

---

### Use Case 2: Preserve cross-repository parent state during partial shipment

**Actor**: Workflow operator monitoring a multi-repository delivery.
**Preconditions**: At least one component child has shipped, and at least one
declared delivery component is still pending, failed, or blocked.

**Steps**:

1. The operator inspects the parent epic or delivery bundle.
2. The workflow shows which component children have reached released state.
3. The workflow shows which component children remain pending, failed, blocked,
   or missing release evidence.
4. The workflow keeps the parent epic open and unreleased.
5. The workflow keeps the delivery bundle open until every declared component
   passes the bundle finalization gate.

**Postconditions**: Partial shipment is visible without incorrectly completing
the parent epic or final delivery.

**Information shown**:

- Released component children.
- Pending, failed, blocked, or missing component children.
- Delivery bundle readiness.
- Parent epic release state.
- Next required action for each unreleased component.

**Actions available**:

- Continue reconciling individual component children.
- Retry failed component release reconciliation.
- Finalize the delivery bundle only after every declared component is complete.

**Considerations**:

- A parent epic can be implementation-complete while still not released as a
  customer-facing delivery.
- The delivery manifest is the source of truth for the final shipped
  composition.

---

### Use Case 3: Finalize parent release state from a completed delivery bundle

**Actor**: Workflow operator completing a cross-repository customer-facing
delivery.
**Preconditions**: Every declared component child has verified release state,
and the delivery bundle has passed finalization readiness.

**Steps**:

1. The operator finalizes the delivery bundle.
2. The workflow verifies that every declared component has complete release,
   cleanup, tracker reconciliation, and child release-state evidence.
3. The workflow records the delivery bundle as the customer-facing release
   composition.
4. The workflow allows the parent epic to move to the final released state.
5. The workflow reports the completed component list and the final parent
   release outcome.

**Postconditions**: The parent epic is released only after the delivery bundle
confirms the full customer-facing composition.

**Information shown**:

- Finalized delivery bundle status.
- Component children included in the released delivery.
- Component milestones already stamped.
- Parent epic release status.
- Any deferred hub tracker reconciliation noted by the final bundle.

**Actions available**:

- Complete parent release reconciliation when bundle finalization passes.
- Stop and report blockers when any component child or bundle evidence is
  incomplete.
- Inspect the finalized delivery record after completion.

**Considerations**:

- Parent release reconciliation must not create a shared suite version or shared
  release branch.
- The parent epic remains milestone-free even when it moves to released state.

---

### Use Case 4: Preserve single-repository release behavior

**Actor**: Workflow operator running a normal single-repository release.
**Preconditions**: The repository is not operating as a workflow hub for a
multi-repository delivery.

**Steps**:

1. The operator runs the existing single-repository release flow.
2. The workflow uses the existing version milestone convention.
3. The workflow updates the single-repository release items as it does today.
4. The workflow does not require namespaced component milestones or delivery
   bundle finalization.

**Postconditions**: Existing single-repository release behavior remains
unchanged.

**Information shown**:

- Existing version milestone.
- Existing single-repository release status.
- Existing release issue or item scope.

**Actions available**:

- Continue the normal single-repository release and cleanup flow.
- Use multi-repository component reconciliation only when workflow-hub mode is
  active for a selected product repository.

**Considerations**:

- Namespaced component milestones are a workflow-hub behavior, not a replacement
  for simple single-repository version milestones.

## Business Rules

- Component milestones are scoped to one selected product repository and one
  component tag.
- A namespaced component milestone must identify both the product repository and
  the component tag.
- Milestone stamping must target only the component child whose verified release
  evidence matches the selected product repository and tag.
- Cross-repository parent epics must not receive component milestones.
- Delivery bundle issues must not receive component milestones.
- A component child can reach released state independently from sibling
  components.
- A failed, blocked, pending, missing, stale, or conflicting component release
  must not move the component child to released state.
- A parent epic must not move to released state until the delivery bundle
  finalization gate passes for every declared current component.
- A parent epic can show partial shipment while remaining unreleased.
- Single-repository release flows continue to use their existing version
  milestone behavior.
- Historical milestones must not be rewritten automatically during adoption of
  the workflow-hub release model.

## Statuses / Enum Values

Component child release states:

| Code value | Display label | Description |
| --- | --- | --- |
| `not_started` | Not started | No verified component release reconciliation has begun. |
| `pending` | Pending release | Release work is in progress or waiting for required evidence. |
| `released` | Released | The selected product repository's component release is verified and reconciled. |
| `blocked` | Blocked | Release or tracker reconciliation cannot continue without correction. |
| `failed` | Failed | A release attempt failed and must be retried or replaced. |

Parent epic release states:

| Code value | Display label | Description |
| --- | --- | --- |
| `not_released` | Not released | No component has completed release reconciliation yet. |
| `partially_released` | Partially released | One or more component children are released, but the delivery bundle is not finalized. |
| `released` | Released | The delivery bundle is finalized and the parent epic release state is reconciled. |
| `blocked` | Blocked | Parent release reconciliation is blocked by missing, failed, conflicting, or stale bundle evidence. |

**Valid transitions**:

- Component child `not_started` -> `pending` when release reconciliation begins.
- Component child `pending` -> `released` when matching component evidence and
  milestone reconciliation are verified.
- Component child `pending` -> `blocked` when required evidence is missing,
  conflicting, stale, or targets a different product repository.
- Component child `pending` -> `failed` when a release attempt fails.
- Component child `blocked` -> `pending` when the blocker is corrected and
  reconciliation is retried.
- Component child `failed` -> `pending` when a replacement release attempt
  starts.
- Parent epic `not_released` -> `partially_released` when at least one
  component child is released and at least one declared component remains
  unreleased.
- Parent epic `partially_released` -> `released` when the delivery bundle
  finalization gate passes.
- Parent epic `not_released` -> `released` when all declared components are
  released and the delivery bundle is finalized in one reconciliation pass.
- Parent epic `not_released` or `partially_released` -> `blocked` when bundle
  finalization evidence is missing, failed, conflicting, or stale.

## Component Milestone Reconciliation Gate

Validation precedence is top-to-bottom. The first matching gate row determines
the reconciliation outcome shown to the operator.

| Gate input | Reconciliation outcome | Allowed outcome | Required next action | Mirror surface | Example |
| --- | --- | --- | --- | --- | --- |
| No workflow-hub mode is active | `single_repo_milestone` | Continue | Use existing version milestone behavior | Release summary | A standard repository release uses `v1.4.0`. |
| Selected product repository is missing or ambiguous | `missing_product_selection` | Stop | Select exactly one product repository | Release summary and tracker comment | The operator starts hub reconciliation without a product key. |
| Component release evidence is missing | `component_release_pending` | Stop | Complete or attach component release evidence | Component child and delivery bundle | The product release PR has not merged yet. |
| Evidence product repository does not match the child | `component_target_mismatch` | Stop | Correct the child target or release evidence | Component child | A mobile child receives web release evidence. |
| Evidence tag is missing or invalid | `component_tag_missing` | Stop | Provide the released component tag | Component child | Cleanup completed but no tag is recorded. |
| Component release failed, blocked, pending, stale, or conflicting | `component_release_not_ready` | Stop | Retry or repair the component release | Component child and bundle readiness | Product CI failed after the release PR. |
| Matching component child and verified release evidence are present | `component_released` | Continue | Stamp the namespaced component milestone and mark the child released | Component child and release summary | `mobile-app@mobile-v1.4.0` is applied to the mobile child only. |
| All declared components are released and the bundle finalization gate passes | `parent_released` | Continue | Mark the parent epic released without adding a component milestone | Parent epic and delivery bundle | Mobile and web components are both finalized in the delivery bundle. |

## Operational Visibility

- **Component child summary**: Shows selected product repository, component tag,
  namespaced milestone, release evidence status, and reconciliation result.
- **Parent epic summary**: Shows unreleased, partially released, released, or
  blocked state without component milestones on the parent.
- **Delivery bundle summary**: Shows whether every declared component has
  released child state and whether the final bundle gate can complete.
- **Audit trail**: Records milestone decisions, stopped reconciliation attempts,
  component child release transitions, parent release transitions, and the
  evidence used for each decision.
- **Failure visibility**: Reports the child, selected product repository,
  component tag, stop reason, and required correction before any tracker state is
  changed.

## Acceptance Criteria

- [ ] A workflow-hub component release can stamp a namespaced milestone in the
  form `<product-repo>@<tag>` only on the matching component child.
- [ ] Milestone reconciliation stops before tracker mutation when product
  selection, component evidence, or component tag information is missing or
  ambiguous.
- [ ] Milestone reconciliation stops before tracker mutation when component
  evidence targets a different product repository than the child.
- [ ] A component child can move to released state independently after its own
  release evidence and namespaced milestone are verified.
- [ ] A failed, blocked, pending, stale, missing, or conflicting component
  release does not move the component child to released state.
- [ ] Cross-repository parent epics remain milestone-free during partial and
  final release reconciliation.
- [ ] Delivery bundle issues remain milestone-free, and their shipped
  composition is represented by the delivery manifest.
- [ ] The parent epic shows partial release state when at least one component is
  released and at least one declared component remains unreleased.
- [ ] The parent epic reaches released state only after the completed delivery
  bundle gate passes.
- [ ] Existing single-repository `vX.Y.Z` milestone behavior is unchanged.
- [ ] Reconciliation audit output identifies the targeted child, selected
  product repository, component tag, outcome, and required next action.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Introduce namespaced hub milestone titles in the form `<product-repo>@<tag>`. | Use Case 1; Business Rules; Acceptance Criteria 1 and 11 |
| Stamp only the matching repository-scoped child after its component release is verified. | Use Case 1; Component Milestone Reconciliation Gate; Acceptance Criteria 1-5 |
| Keep cross-repository epics milestone-free. | Use Cases 2 and 3; Business Rules; Acceptance Criterion 6 |
| Keep delivery issues milestone-free; shipped composition lives in the delivery manifest. | Use Cases 2 and 3; Business Rules; Acceptance Criterion 7 |
| Define component-child status transitions, including partial shipment, retries, and failures. | Statuses / Enum Values; Acceptance Criteria 4 and 5 |
| Define parent-epic status transitions, including partial shipment and final bundle release. | Use Cases 2 and 3; Statuses / Enum Values; Acceptance Criteria 8 and 9 |
| Preserve existing single-repository `vX.Y.Z` milestone behavior. | Use Case 4; Business Rules; Acceptance Criterion 10 |

## Out of Scope (MVP)

- Creating a shared suite version, shared release branch, shared tag, or shared
  GitHub Release for a multi-repository delivery.
- Rewriting historical milestones or tracker history automatically.
- Replacing product repository release milestones with hub-only records.
- Defining the adoption, migration, and broad regression harness for every
  downstream repository mode; that is covered by #1359.
