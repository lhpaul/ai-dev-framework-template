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

## Delivery Bundle Contract

A delivery bundle issue template must collect enough hub-owned information to
create a durable bundle before any component evidence is attached:

- Delivery bundle title and customer-facing delivery purpose.
- Parent epic or delivery request.
- Initial participating product components, when known.
- Expected source child items or product work items, when known.
- Finalization owner or responsible operator.
- Optional notes for release timing, rollout constraints, or known missing
  component evidence.

The delivery manifest is versioned independently from component releases. Each
accepted bundle change creates a new manifest revision, including bundle
creation, component add, component update, component removal, readiness changes,
and finalization. Current-revision validation, idempotent replay detection,
state mutation, revision increment, and audit-event append must happen as one
atomic bundle commit. Stale writes must be rejected or retried without mutating
accepted manifest state.

Each component entry in the manifest must preserve the stable identity and
outcome contract from component release evidence:

- Selected product repository key.
- Canonical repository identity.
- Release correlation key.
- Release contract revision.
- Component version or tag.
- Source pull request and release pull request references.
- Routing, release, CI, deployment, cleanup, and hub tracker reconciliation
  outcomes.
- Child item release state.

The selected product repository key, canonical repository identity, release
correlation key, and release contract revision are the stable identity fields
used for deduplication and conflict detection. Display names and branch names
are not sufficient identity by themselves.

Acceptable finalization outcomes are intentionally narrow:

- Routing outcome is component release routed.
- Release outcome is completed.
- CI outcome is passed, skipped only when the product release contract declares
  that CI is not required, or not applicable only for components that have no
  product-owned release artifact.
- Deployment outcome is recorded or not applicable with a documented rationale.
- Cleanup outcome is complete.
- Hub tracker reconciliation outcome is complete or deferred with an explicit
  human action that does not change the product component version.
- Child item release state is released or merged according to the active release
  stage semantics.

Failed, blocked, pending, missing, conflicting, or stale outcomes block
finalization.

## Use Cases

### Use Case 1: Create a delivery bundle

**Actor**: Workflow operator coordinating a customer-facing delivery.
**Preconditions**: A hub epic or delivery request identifies a customer-facing
delivery that may include one or more independently released product
components.

**Steps**:

1. The operator creates a hub-owned delivery bundle from the delivery bundle
   issue template for the intended customer delivery.
2. The workflow records the parent epic or delivery request that the bundle
   belongs to.
3. The operator declares the product components that may participate in the
   delivery.
4. The workflow records the first manifest revision as the authoritative
   component-version record for the bundle.
5. The workflow shows the bundle as open and not finalized until component
   evidence is complete.

**Postconditions**: A hub-owned delivery bundle exists with an authoritative
manifest and a clear list of participating component tracks.

**Information shown**:

- Delivery bundle title and parent epic or delivery request.
- Participating product components.
- Current manifest version.
- Template fields required before creation can complete.
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
   component, stable component identity fields, component version or tag,
   source pull request, release pull request, routing outcome, release outcome,
   CI outcome, deployment evidence, cleanup outcome, hub tracker reconciliation
   outcome, and child-item release state.
3. The workflow compares the incoming component evidence with the current
   manifest revision and any existing manifest entry for the same component as
   part of one atomic update attempt.
4. The workflow accepts the update, creates the next manifest revision, and
   appends the audit event in the same atomic bundle commit when the incoming
   evidence is consistent and based on the current manifest revision.
5. The workflow treats identical replay as a no-op within the same atomic update
   attempt.
6. The workflow reports a stop reason when the incoming evidence conflicts with
   existing bundle state or was based on a stale manifest revision.

**Postconditions**: The manifest reflects the latest accepted evidence for that
component without losing unrelated component entries.

**Information shown**:

- Component name and repository identity.
- Release correlation key and release contract revision.
- Component version or tag.
- Source and release pull request references.
- Routing, release, CI, deployment, cleanup, and hub tracker reconciliation
  outcome state.
- Child item release status.
- Manifest revision before and after the accepted update.
- Whether the bundle is now finalization-ready.

**Actions available**:

- Accept consistent component evidence against the current manifest revision.
- Retry an update after missing evidence becomes available.
- Retry a stale update against the latest manifest revision.
- Stop for correction when component identity, version, or evidence conflicts
  with the manifest.

**Considerations**:

- Multiple component releases may update the same bundle over time.
- Repeating an update with identical evidence should be safe and should not
  create duplicate component entries.
- Independent updates must merge into the current manifest revision without
  losing previously accepted component entries.

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
- Missing routing, release pull request, CI, deployment, cleanup, hub tracker
  reconciliation, or child-status evidence.
- Invalid, stale, or conflicting evidence that blocks finalization.
- Next required action for each component.

**Actions available**:

- Add missing component evidence.
- Re-run bundle inspection.
- Remove a component before finalization through a new manifest revision that
  records the removal reason.
- Stop and preserve current state when evidence is inconsistent.

**Considerations**:

- A partially completed bundle must remain useful as a source of truth for what
  is known and what remains missing.
- Recovery must not require rewriting historical component release evidence.
- Prior manifest revisions remain auditable after a component is removed from
  the current bundle revision.

---

### Use Case 4: Finalize a delivery bundle

**Actor**: Workflow operator completing a coordinated customer-facing delivery.
**Preconditions**: The delivery bundle has one or more declared components and
all required evidence for those components is available.

**Steps**:

1. The operator requests finalization for the delivery bundle.
2. The workflow verifies each declared component has an accepted component
   version or tag.
3. The workflow verifies each declared component has acceptable routing,
   release pull request, CI, deployment, cleanup, hub tracker reconciliation,
   and child-item release evidence.
4. The workflow verifies the manifest does not contain conflicting component
   versions, stale evidence, or stale readiness computed for an older manifest
   revision as part of the finalization attempt.
5. The workflow moves the bundle from `ready_to_finalize` to `finalized`,
   increments the manifest revision, and appends the finalization audit event in
   one atomic bundle commit.

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
  required routing, release, CI, deployment, cleanup, hub tracker
  reconciliation, or child-item release evidence.
- The workflow must not finalize a bundle when two accepted entries conflict
  for the same product component.
- Re-applying identical component evidence to an open bundle must be safe and
  must not duplicate component entries.
- Conflicting component evidence must stop the update and preserve the existing
  accepted manifest state.
- Stale component updates must stop or retry against the latest manifest
  revision without overwriting accepted component entries.
- Every accepted bundle change must create a new manifest revision and audit
  event in the same atomic bundle commit as the accepted state change.
- Component removal must be recorded as a new manifest revision with a removal
  reason; prior manifest revisions continue to show the component that was
  previously accepted.
- Re-adding a removed component requires fresh accepted evidence for the current
  manifest revision.
- Any add, update, or removal after a bundle becomes ready to finalize must move
  the bundle back to open or blocked and require readiness to be recomputed for
  the current manifest revision.
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
- `ready_to_finalize` -> `open` when an operator adds, updates, or removes a
  component before finalization and the changed manifest has not yet been
  rechecked.
- `ready_to_finalize` -> `blocked` when an add, update, removal, or final
  readiness recheck finds missing, stale, or conflicting evidence.
- `ready_to_finalize` -> `finalized` when the operator finalizes the bundle
  through an atomic finalization commit against the current manifest revision.
- `finalized` has no automatic transition back to an editable state.

Component evidence states shown inside a bundle:

| Code value | Display label | Description |
| --- | --- | --- |
| `missing` | Missing | Required component evidence has not been supplied. |
| `partial` | Partial | Some required component evidence is present, but finalization requirements are incomplete. |
| `conflicting` | Conflicting | Supplied evidence disagrees with accepted manifest state. |
| `stale` | Stale | Supplied evidence or readiness was computed from an older manifest revision and must be retried or refreshed. |
| `verified` | Verified | Required component evidence is present and consistent. |

## Operational Visibility

- **Inspection output**: Bundle inspection shows current bundle status,
  component evidence state, finalization readiness, and next required action.
- **Audit trail**: Bundle creation, component updates, rejected conflicting
  evidence, component removals, stale update rejections, and finalization
  attempts are recorded in hub-visible evidence.
- **Failure visibility**: Missing or inconsistent evidence reports the affected
  component, the blocked finalization requirement, and the required correction.
- **Resume visibility**: Re-running inspection after an interruption shows
  whether the bundle can continue, remains blocked, or is ready to finalize.

## Acceptance Criteria

- [ ] A workflow operator can create a hub-owned delivery bundle from a template
  that records the delivery title, delivery purpose, parent epic or request,
  participating product components, known child items, finalization owner, and
  optional rollout notes.
- [ ] The delivery manifest is created as the authoritative component-version
  record for the bundle and identifies its current revision.
- [ ] A completed component release can update one matching component entry
  against the current manifest revision without losing unrelated component
  entries.
- [ ] Re-applying identical component release evidence to an open bundle is
  safe and does not create duplicate component entries.
- [ ] Bundle inspection reports missing routing, release pull request, CI,
  deployment, cleanup, hub tracker reconciliation, child-item release evidence,
  and invalid or stale outcomes for each incomplete declared component.
- [ ] Bundle updates stop without mutating accepted manifest state when incoming
  component evidence conflicts with existing stable identity fields, version
  state, release correlation key, or release contract revision.
- [ ] Bundle updates stop or retry without mutating accepted manifest state when
  incoming component evidence is based on a stale manifest revision.
- [ ] Removing a component before finalization creates a new manifest revision
  with a removal reason and preserves prior manifest revisions for audit.
- [ ] Adding, updating, or removing a component after the bundle is ready to
  finalize invalidates readiness and requires a fresh readiness check for the
  current manifest revision.
- [ ] Finalization is blocked when any declared component is missing a component
  version or tag.
- [ ] Finalization is blocked when any declared component lacks acceptable
  routing, release pull request, CI, deployment, cleanup, hub tracker
  reconciliation, or child-item release-state evidence.
- [ ] Finalization is blocked when any declared component has failed, blocked,
  pending, missing, conflicting, or stale outcomes.
- [ ] Finalization succeeds only when every declared component has complete and
  consistent evidence for the current manifest revision, and the
  `ready_to_finalize` -> `finalized` transition records the finalization state,
  revision increment, and audit event atomically.
- [ ] Finalization records a completed hub-owned delivery bundle without
  creating a shared suite version or shared release branch.
- [ ] Existing independently owned component release evidence remains unchanged
  when a delivery bundle is created, updated, inspected, or finalized.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Add a hub delivery or release issue template for coordinated customer-facing deliveries. | Delivery Bundle Contract; Use Case 1; Acceptance Criterion 1 |
| Add a versioned machine-readable delivery manifest. | Delivery Bundle Contract; Use Case 1; Business Rules; Acceptance Criterion 2 |
| Define workflow actions to create, update, inspect, and finalize a delivery bundle. | Use Cases 1-4; Operational Visibility |
| Record the parent epic, participating product children, component versions or tags, source and release pull requests, deployment evidence, and verification state. | Delivery Bundle Contract; Use Cases 1-4; Acceptance Criteria 1, 3, 5, 11 |
| Make incomplete bundles resumable. | Use Case 3; Business Rules; Operational Visibility; Acceptance Criteria 7-9 |
| Prevent bundle finalization when evidence is missing or inconsistent. | Use Case 4; Business Rules; Acceptance Criteria 10-13 |
| Make the manifest the authoritative component-version record for a coordinated delivery. | Overview; Business Rules; Acceptance Criterion 2 |
| Allow independently completed component releases to update the same bundle safely. | Delivery Bundle Contract; Use Case 2; Business Rules; Acceptance Criteria 3-7 |
| Verify every declared component tag, deployment, and child-item release state before finalization. | Delivery Bundle Contract; Use Case 4; Acceptance Criteria 10-13 |
| Avoid introducing a shared suite version or release branch. | Overview; Business Rules; Acceptance Criterion 14 |

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
