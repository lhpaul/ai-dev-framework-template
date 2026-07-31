# One Product Repository Per Implementation Item - Spec

---

## Overview

Workflow hubs need a deterministic way to route each product implementation item
to exactly one product repository before any branch, PR, review, CI, or cleanup
work begins. Today the guidance says product work should select a repository,
but it does not make that selection an enforceable tracker contract or explain
how hub epics, repository-scoped children, and hub-only coordination work fit
together.

This feature formalizes the one-target routing model for hub-managed
implementation work. It gives operators a clear decomposition pattern, makes
missing, ambiguous, and multi-target routing stop before mutation, and preserves
the existing single-repository workflow behavior.

## Brief Objective List

Derived from issue #1354:

1. Require exactly one target product repository for every product
   implementation item.
2. Reject missing, ambiguous, and multi-target implementation routing before
   mutation.
3. Define and enforce the hub epic plus repository-scoped child-item pattern,
   including optional hub-only coordination work.
4. Propagate selected-repository context consistently through spec, plan,
   implementation, review, cleanup, and release handoffs.
5. Ensure a cross-repository request is decomposed into an epic and
   single-repository children.
6. Ensure no product implementation action can rely on an implicit or multiple
   repository target.
7. Ensure hub-only work remains distinguishable and routable.
8. Preserve current behavior for single-repository workflows.

## Spec-Dispatch Context

Confirmed relationship decisions for epic #1352:

- #1354 depends on #1353 as the foundational artifact ownership and product
  release contract.
- #1354 is upstream/foundational for #1356, #1357, #1358, and #1359 and has no
  dispatch-ordering dependency on those peer items.
- Shared terminology with #1356, #1357, #1358, and #1359 must not cause this
  spec to absorb release execution, delivery-bundle, milestone, or adoption
  assurance behavior.

## Use Cases

### Use Case 1: Decompose cross-repository product work

**Actor**: Workflow operator creating or triaging hub-managed work.
**Preconditions**: The requested work may affect one or more product
repositories from a workflow hub.

**Steps**:

1. The operator identifies whether the request is cross-repository product work,
   hub-only coordination work, or unchanged single-repository work.
2. For cross-repository product work, the operator creates or uses a hub epic to
   hold the shared outcome.
3. The operator creates one child item per product repository that will receive
   implementation changes.
4. The operator records the selected product repository on each product child.
5. The operator records hub-only coordination work as a separate hub-owned child
   when such work exists.

**Postconditions**: Every product implementation child has one and only one
target product repository before implementation routing begins.

**Information shown**:

- Parent hub epic.
- Child item purpose.
- Child item repository role: product-owned or hub-only.
- Selected product repository for product-owned children.
- Relationship to any foundational workflow contract.

**Actions available**:

- Continue a child item when it has exactly one target repository.
- Split a child item when it names more than one product repository.
- Stop and request routing clarification when the target is missing or
  ambiguous.

**Considerations**:

- A hub epic may coordinate multiple product children, but each product child
  remains scoped to one repository.
- Hub-only workflow or documentation work is not forced into a product
  repository target.

---

### Use Case 2: Route a product implementation item

**Actor**: Work item runner or implementation agent.
**Preconditions**: The item is ready for a mutating implementation stage and is
classified as product-owned hub work.

**Steps**:

1. The runner reads the item's selected product repository context.
2. The runner verifies that the selection names exactly one configured product
   repository.
3. The runner verifies that the selected repository context is available before
   branch creation or PR mutation.
4. The runner includes the selected repository context in every downstream
   handoff.
5. Review, CI, and cleanup evidence are collected from the selected repository
   while tracker reconciliation remains hub-owned.

**Postconditions**: The implementation workflow mutates only the selected
product repository for product-owned work.

**Information shown**:

- Selected product repository key.
- Target repository identity.
- Artifact owner for the current stage.
- Stop reason when repository routing is unavailable.

**Actions available**:

- Continue with selected product repository routing.
- Stop before mutation when the selection is missing, ambiguous, unavailable,
  or names multiple repositories.
- Report hub-only routing when the item is explicitly hub-owned.

**Considerations**:

- Repository context must travel through spec, plan, implementation, review,
  CI, cleanup, and later release handoffs without being re-inferred from branch
  names alone.
- Product implementation work must not default to the hub checkout merely
  because the hub owns the tracker item.

---

### Use Case 3: Preserve single-repository behavior

**Actor**: Maintainer using the existing single-repository workflow.
**Preconditions**: The repository is not configured as a workflow hub.

**Steps**:

1. The maintainer runs the normal item workflow.
2. The workflow treats the current repository as the implementation target.
3. The workflow does not require a product repository selector.

**Postconditions**: Existing single-repository item routing behaves as it did
before this feature.

**Information shown**:

- Current repository as the artifact owner.
- No product-repository selection requirement.

**Actions available**:

- Continue through the existing single-repository stage flow.

**Considerations**:

- Single-repository workflows may still have epics and child issues, but they
  do not need hub product-routing metadata.

## Routing Model

| Work shape | Required tracker structure | Required repository target | Routing result |
| --- | --- | --- | --- |
| Single product repository change from a hub | Hub child item under the hub epic | Exactly one selected product repository | Product-owned child can advance |
| Multiple product repositories from one request | Hub epic with one child per product repository | Exactly one selected product repository per product child | Each child advances independently |
| Hub-only coordination work | Hub-owned child item or hub-only epic task | Hub repository | Hub-owned child can advance |
| Ambiguous product request | Hub issue or child needing clarification | None until clarified | Stop before mutation |
| Multi-target child item | One child naming more than one product repository | Invalid | Stop and split into repository-scoped children |
| Single-repository work | Existing issue structure | Current repository | Existing behavior continues |

## Business Rules

- A product-owned implementation child in `workflow_hub` mode has exactly one
  selected product repository.
- A product-owned implementation child with zero selected repositories is
  unroutable and must stop before mutation.
- A product-owned implementation child with more than one selected product
  repository is invalid and must be split or narrowed before mutation.
- Hub-only coordination work must be explicitly distinguishable from
  product-owned implementation work.
- The selected product repository context must remain visible through spec,
  plan, implementation, review, CI, cleanup, and release handoffs.
- Spec and plan artifacts remain hub-owned unless a later workflow contract
  explicitly says otherwise.
- Product code branches, product PRs, product CI, product reviewer-loop checks,
  and product cleanup evidence are owned by the selected product repository.
- Tracker reconciliation remains hub-owned for hub-managed product work.
- Single-repository workflows do not require product repository selection and
  keep current behavior.

## Statuses / Enum Values

No new tracker statuses are introduced. Existing workflow statuses keep their
current display labels and meanings.

The routing outcome must be operator-visible before mutation:

| Routing outcome | Display label | Description |
| --- | --- | --- |
| Product owned | Product owned | The child item names exactly one product repository and may route product artifacts there. |
| Hub only | Hub only | The item intentionally mutates hub-owned workflow or coordination artifacts. |
| Missing target | Missing target | The item appears product-owned but has no selected product repository. |
| Ambiguous target | Ambiguous target | The item's target repository cannot be determined from confirmed tracker context. |
| Multiple targets | Multiple targets | The item names more than one product repository and must be split or narrowed. |

## Operational Visibility

- **Routing summary**: Before any mutating stage handoff, the workflow names the
  item, repository role, selected product repository, and artifact owner.
- **Stop evidence**: Missing, ambiguous, and multiple-target routing failures
  identify the affected item and the required human action.
- **Handoff context**: Stage handoffs carry the selected repository context so
  reviewers, CI, cleanup, and release workflows can verify the same target.
- **Tracker evidence**: Hub-owned tracker records show whether a child is
  product-owned or hub-only.

## Acceptance Criteria

- [ ] A hub-managed product implementation item with exactly one selected
      product repository can advance, and its stage handoffs show that product
      repository as the mutation target.
- [ ] A hub-managed product implementation item with no selected product
      repository stops before branch creation, PR mutation, tracker mutation, or
      cleanup and reports "Missing target" or equivalent stop evidence.
- [ ] A hub-managed product implementation item with multiple selected product
      repositories stops before mutation and reports that the item must be split
      or narrowed to one product repository.
- [ ] A cross-repository request can be represented as one hub epic with
      repository-scoped product children, and each child has only one product
      target.
- [ ] Hub-only coordination work can be represented and routed without a product
      repository target.
- [ ] Selected repository context is visible in spec, plan, implementation,
      review, CI, cleanup, and release handoff summaries for product-owned hub
      work.
- [ ] Existing `single_repo` workflows continue without requiring any product
      repository selection.
- [ ] Shared terminology with release execution, delivery bundle, milestone,
      and adoption assurance items does not expand this feature beyond
      one-target routing and tracker decomposition.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Require exactly one target product repository for every product implementation item. | Business Rules; Use Case 2; AC1, AC2, AC3 |
| Reject missing, ambiguous, and multi-target implementation routing before mutation. | Routing Model; Operational Visibility; AC2, AC3 |
| Define and enforce the hub epic plus repository-scoped child-item pattern, including optional hub-only coordination work. | Use Case 1; Routing Model; AC4, AC5 |
| Propagate selected-repository context consistently through spec, plan, implementation, review, cleanup, and release handoffs. | Use Case 2; Operational Visibility; AC6 |
| Ensure a cross-repository request is decomposed into an epic and single-repository children. | Use Case 1; Routing Model; AC4 |
| Ensure no product implementation action can rely on an implicit or multiple repository target. | Business Rules; Routing Model; AC2, AC3 |
| Ensure hub-only work remains distinguishable and routable. | Use Case 1; Routing Model; AC5 |
| Preserve current behavior for single-repository workflows. | Use Case 3; Business Rules; AC7 |

## Out of Scope (MVP)

- Product-aware component release execution for a selected repository; that is
  owned by #1356.
- Delivery-bundle issue and manifest behavior; that is owned by #1357.
- Component milestone and release-status reconciliation; that is owned by
  #1358.
- Migration, adoption, and end-to-end assurance runbooks; those are owned by
  #1359.
- Changing the already established artifact ownership and product release
  contract from #1353.
