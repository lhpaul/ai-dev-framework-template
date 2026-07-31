# Delivery Bundle Issue And Manifest Workflow - Spec

**Depends on**:
[1353-artifact-ownership-product-release-contract](../20260730174200_1353-artifact-ownership-product-release-contract/1_1353-artifact-ownership-product-release-contract_specs.md)
and
[1356-route-component-releases-to-selected-product-repository](../20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md)

---

## Overview

Workflow hubs need a durable way to describe one customer-facing delivery that
is made from multiple independently released product components. This feature
adds a hub-owned delivery bundle issue and a versioned delivery manifest so
operators can record which component releases make up the delivery, resume
incomplete coordination work, and finalize only when every declared component
has complete evidence.

The workflow must not create a shared suite version, a shared release branch, or
a false lockstep release. Component releases remain owned by their selected
product repositories, while the delivery bundle records the hub-owned view of
what shipped together.

## Brief Objective List

Derived from issue #1357:

1. Add a hub delivery or release issue template for coordinated customer-facing
   deliveries.
2. Add a versioned machine-readable delivery manifest.
3. Define workflow actions to create, update, inspect, and finalize a delivery
   bundle.
4. Record the parent epic, participating product children, component versions or
   tags, source and release pull requests, deployment evidence, and verification
   state.
5. Make incomplete bundles resumable.
6. Prevent bundle finalization when evidence is missing or inconsistent.
7. Make the manifest the authoritative component-version record for a
   coordinated delivery.
8. Allow independently completed component releases to update the same bundle
   safely.
9. Verify every declared component tag, deployment, and child-item release state
   before finalization.
10. Avoid introducing a shared suite version or release branch.

## Spec-Dispatch Context

Confirmed relationship decisions for epic #1352:

- #1357 depends on #1353 as the foundational artifact ownership and product
  release contract.
- #1357 depends on #1356 for component release evidence that a delivery bundle
  can consume.
- #1358 and #1359 are downstream or orthogonal to #1357 for spec dispatch.
  Their milestone reconciliation, adoption, and assurance behavior must not be
  absorbed into this delivery-bundle spec.

## Use Cases

### Use Case 1: Create a delivery bundle

**Actor**: Workflow operator coordinating a customer-facing delivery.
**Preconditions**: A hub epic or delivery request identifies a customer-facing
delivery that may include one or more independently released product
components.

**Steps**:

1. The operator creates a hub-owned delivery bundle for the intended customer
   delivery.
2. The workflow records the parent epic or delivery request that the bundle
   belongs to.
3. The operator declares the product components that may participate in the
   delivery.
4. The workflow creates or updates the delivery manifest as the authoritative
   component-version record for the bundle.
5. The workflow shows the bundle as open and not finalized until component
   evidence is complete.

**Postconditions**: A hub-owned delivery bundle exists with an authoritative
manifest and a clear list of participating component tracks.

**Information shown**:

- Delivery bundle title and parent epic or delivery request.
- Participating product components.
- Current manifest version.
- Bundle status and finalization readiness.
- Missing component evidence, when any is known.

**Actions available**:

- Add or remove a component while the bundle is open.
- Inspect current bundle evidence.
- Attach component release evidence as each product release completes.
- Finalize only when the bundle passes all readiness checks.

**Considerations**:

- Creating a bundle does not require every component release to have completed.
- A bundle can start with one component and gain more components before
  finalization.

---

### Use Case 2: Update a bundle from an independently completed component release

**Actor**: Workflow operator or release runner recording a completed component
release.
**Preconditions**: A component release has produced release evidence from one
selected product repository, and a hub-owned delivery bundle is open.

**Steps**:

1. The operator selects the delivery bundle to update.
2. The workflow reads the component release evidence and identifies the product
   component, component version or tag, release pull request, source pull
   request, deployment evidence, cleanup outcome, and child-item release state.
3. The workflow compares the incoming component evidence with any existing
   manifest entry for the same component.
4. The workflow updates the manifest when the incoming evidence is consistent.
5. The workflow reports a stop reason when the incoming evidence conflicts with
   existing bundle state.

**Postconditions**: The manifest reflects the latest accepted evidence for that
component without changing unrelated component entries.

**Information shown**:

- Component name and repository identity.
- Component version or tag.
- Source and release pull request references.
- Deployment and cleanup evidence state.
- Child item release status.
- Whether the bundle is now finalization-ready.

**Actions available**:

- Accept consistent component evidence.
- Retry an update after missing evidence becomes available.
- Stop for correction when component identity, version, or evidence conflicts
  with the manifest.

**Considerations**:

- Multiple component releases may update the same bundle over time.
- Repeating an update with identical evidence should be safe and should not
  create duplicate component entries.

---

### Use Case 3: Inspect and resume an incomplete bundle

**Actor**: Workflow operator resuming interrupted delivery coordination.
**Preconditions**: A delivery bundle exists but is not finalized.

**Steps**:

1. The operator inspects the delivery bundle.
2. The workflow shows every declared component and its current evidence state.
3. The workflow identifies missing, incomplete, stale, or conflicting evidence.
4. The operator supplies missing component evidence or corrects inconsistent
   bundle state.
5. The workflow keeps the bundle open until all finalization requirements are
   satisfied.

**Postconditions**: The operator has a clear recovery path for the incomplete
delivery bundle.

**Information shown**:

- Declared components.
- Accepted component versions or tags.
- Missing release, deployment, cleanup, or child-status evidence.
- Conflicting evidence that blocks finalization.
- Next required action for each component.

**Actions available**:

- Add missing component evidence.
- Re-run bundle inspection.
- Remove a component before finalization when it is no longer part of the
  delivery.
- Stop and preserve current state when evidence is inconsistent.

**Considerations**:

- A partially completed bundle must remain useful as a source of truth for what
  is known and what remains missing.
- Recovery must not require rewriting historical component release evidence.

---

### Use Case 4: Finalize a delivery bundle

**Actor**: Workflow operator completing a coordinated customer-facing delivery.
**Preconditions**: The delivery bundle has one or more declared components and
all required evidence for those components is available.

**Steps**:

1. The operator requests finalization for the delivery bundle.
2. The workflow verifies each declared component has an accepted component
   version or tag.
3. The workflow verifies each declared component has release pull request,
   deployment, cleanup, and child-item release evidence.
4. The workflow verifies the manifest does not contain conflicting component
   versions or stale evidence.
5. The workflow finalizes the bundle and records the completed manifest as the
   authoritative delivery record.

**Postconditions**: The delivery bundle is finalized and represents the
customer-facing composition of independently released product components.

**Information shown**:

- Finalized bundle status.
- Final component list and versions or tags.
- Verification outcome for every component.
- Any finalization blocker and required correction.

**Actions available**:

- Finalize when all checks pass.
- Stop and report blockers when evidence is missing or inconsistent.
- Inspect the finalized bundle after completion.

**Considerations**:

- Finalization must not create a shared suite version or shared release branch.
- Finalization is a hub-owned coordination action; product release artifacts
  remain owned by their product repositories.

## Business Rules

- The delivery manifest is the authoritative component-version record for a
  hub-owned coordinated delivery.
- A delivery bundle belongs to the hub and may reference independently released
  product components.
- Each component entry must identify one product component and one accepted
  component version or tag before finalization.
- A component entry may be incomplete while the bundle is open.
- The workflow must not finalize a bundle when any declared component is missing
  required release, deployment, cleanup, or child-item release evidence.
- The workflow must not finalize a bundle when two accepted entries conflict
  for the same product component.
- Re-applying identical component evidence to an open bundle must be safe and
  must not duplicate component entries.
- Conflicting component evidence must stop the update and preserve the existing
  accepted manifest state.
- Delivery bundle finalization must not create a shared suite version, shared
  release branch, or implied lockstep release.
- Historical component release evidence must not be rewritten by bundle
  creation, update, inspection, or finalization.

## Statuses / Enum Values

The delivery bundle introduces bundle lifecycle states and component evidence
states. These are delivery-bundle concepts, not replacements for existing
workflow tracker statuses.

| Code value | Display label | Description |
| --- | --- | --- |
| `open` | Open | The bundle exists and can accept component evidence. |
| `blocked` | Blocked | The bundle has missing or inconsistent evidence that prevents finalization. |
| `ready_to_finalize` | Ready to finalize | Every declared component has complete, consistent evidence. |
| `finalized` | Finalized | The bundle has passed finalization checks and is the completed delivery record. |

**Valid bundle transitions**:

- `open` -> `blocked` when inspection finds missing or inconsistent required
  evidence.
- `blocked` -> `open` when blockers are corrected but finalization readiness has
  not been fully rechecked.
- `open` -> `ready_to_finalize` when every declared component has complete and
  consistent evidence.
- `blocked` -> `ready_to_finalize` when all blockers are corrected and readiness
  checks pass.
- `ready_to_finalize` -> `finalized` when the operator finalizes the bundle.
- `finalized` has no automatic transition back to an editable state.

Component evidence states shown inside a bundle:

| Code value | Display label | Description |
| --- | --- | --- |
| `missing` | Missing | Required component evidence has not been supplied. |
| `partial` | Partial | Some required component evidence is present, but finalization requirements are incomplete. |
| `conflicting` | Conflicting | Supplied evidence disagrees with accepted manifest state. |
| `verified` | Verified | Required component evidence is present and consistent. |

## Operational Visibility

- **Inspection output**: Bundle inspection shows current bundle status,
  component evidence state, finalization readiness, and next required action.
- **Audit trail**: Bundle creation, component updates, rejected conflicting
  evidence, and finalization attempts are recorded in hub-visible evidence.
- **Failure visibility**: Missing or inconsistent evidence reports the affected
  component, the blocked finalization requirement, and the required correction.
- **Resume visibility**: Re-running inspection after an interruption shows
  whether the bundle can continue, remains blocked, or is ready to finalize.

## Acceptance Criteria

- [ ] A workflow operator can create a hub-owned delivery bundle for a parent
  epic or delivery request, and the bundle records participating product
  components.
- [ ] The delivery manifest is created as the authoritative component-version
  record for the bundle and identifies its version.
- [ ] A completed component release can update one matching component entry
  without changing unrelated component entries.
- [ ] Re-applying identical component release evidence to an open bundle is
  safe and does not create duplicate component entries.
- [ ] Bundle inspection reports missing release, deployment, cleanup, or
  child-item release evidence for each incomplete declared component.
- [ ] Bundle updates stop without mutating accepted manifest state when incoming
  component evidence conflicts with existing component identity or version
  state.
- [ ] Finalization is blocked when any declared component is missing a component
  version or tag.
- [ ] Finalization is blocked when any declared component lacks deployment
  evidence or child-item release-state evidence.
- [ ] Finalization succeeds only when every declared component has complete and
  consistent evidence.
- [ ] Finalization records a completed hub-owned delivery bundle without
  creating a shared suite version or shared release branch.
- [ ] Existing independently owned component release evidence remains unchanged
  when a delivery bundle is created, updated, inspected, or finalized.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Add a hub delivery or release issue template for coordinated customer-facing deliveries. | Use Case 1; Acceptance Criterion 1 |
| Add a versioned machine-readable delivery manifest. | Use Case 1; Business Rules; Acceptance Criterion 2 |
| Define workflow actions to create, update, inspect, and finalize a delivery bundle. | Use Cases 1-4; Operational Visibility |
| Record the parent epic, participating product children, component versions or tags, source and release pull requests, deployment evidence, and verification state. | Use Cases 1-4; Acceptance Criteria 1, 3, 5, 8 |
| Make incomplete bundles resumable. | Use Case 3; Business Rules; Operational Visibility |
| Prevent bundle finalization when evidence is missing or inconsistent. | Use Case 4; Business Rules; Acceptance Criteria 7-9 |
| Make the manifest the authoritative component-version record for a coordinated delivery. | Overview; Business Rules; Acceptance Criterion 2 |
| Allow independently completed component releases to update the same bundle safely. | Use Case 2; Business Rules; Acceptance Criteria 3-4 |
| Verify every declared component tag, deployment, and child-item release state before finalization. | Use Case 4; Acceptance Criteria 7-9 |
| Avoid introducing a shared suite version or release branch. | Overview; Business Rules; Acceptance Criterion 10 |

## Out of Scope (MVP)

- Milestone naming, component milestone stamping, and release-status
  reconciliation rules owned by #1358.
- Adoption, migration, end-to-end assurance, and historical rollout guidance
  owned by #1359.
- Any shared suite version, shared release branch, or lockstep product release
  process.
- Rewriting historical component release evidence or historical milestones.
- Product repository release artifact creation; component release artifacts stay
  owned by the product release workflow from #1356.
