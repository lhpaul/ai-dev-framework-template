# Artifact Ownership and Product Release Contract - Spec

---

## Overview

Workflow hubs need one product-facing contract that explains which repository
owns each release artifact in a multi-repository delivery. Today the workflow
separates hub coordination from product code work, but release ownership is not
complete enough for operators to know where branches, changelogs, tags,
deployment evidence, delivery manifests, and cleanup records belong.

This feature defines the release-artifact ownership map and the minimum product
release contract that a workflow hub can rely on without storing local paths,
credentials, or product-specific secrets in versioned files. It keeps the
existing single-repository workflow unchanged while giving multi-repository
operators clear setup, validation, and sync expectations.

## Brief Objective List

Derived from issue #1353:

1. Define the owner for tracker work, specs/plans, product code, changelogs,
   release branches, tags, GitHub releases, deployment evidence, delivery
   manifests, and cleanup.
2. Add a non-secret product release contract to workflow-hub/product-repository
   configuration, with explicit defaults and validation.
3. Update role-aware skeleton and sync behavior so product repositories receive
   the required minimal release runtime files while hub-only coordination stays
   excluded.
4. Ensure every release artifact has one documented owner.
5. Ensure product release configuration validates without leaking local paths or
   credentials.
6. Ensure role-aware sync tests prove selected files match the ownership
   contract.
7. Preserve compatibility for existing single-repository setups.

## Spec-Dispatch Context

The current epic relationship decision is that #1353 is the foundational
contract for the remaining multi-repository release items. Issues #1354,
#1356, #1357, #1358, and #1359 depend on this ownership and release-contract
baseline before their more specific workflow behavior is finalized.

## Use Cases

### Use Case 1: Understand release artifact ownership

**Actor**: Workflow operator planning a multi-repository release.
**Preconditions**: The repository is configured as a workflow hub or is being
evaluated for workflow-hub adoption.

**Steps**:

1. The operator reads the multi-repository release ownership guidance.
2. The operator identifies each release artifact involved in the delivery.
3. The operator confirms whether each artifact is owned by the hub, the
   selected product repository, or the current single-repository workflow.
4. The operator uses the ownership map to choose the correct repository before
   starting release, cleanup, or evidence collection work.

**Postconditions**: Every release artifact has exactly one documented owner for
the selected repository mode.

**Information shown**:

- The artifact category.
- The owning repository role.
- The single-repository fallback behavior.
- Any operator-visible evidence required to prove the artifact was handled.

**Actions available**:

- Continue setup when ownership is complete.
- Stop and correct configuration when ownership is ambiguous.

**Considerations**:

- Hub-owned coordination records must not be mistaken for product release
  artifacts.
- Product-owned release artifacts must not be created in the hub repository
  merely because the hub owns tracker coordination.

---

### Use Case 2: Configure a product release contract

**Actor**: Workflow maintainer configuring a hub-managed product repository.
**Preconditions**: The maintainer knows the product repository identity and the
non-secret release information the hub is allowed to store.

**Steps**:

1. The maintainer records the product repository release contract in the
   appropriate versioned configuration surface.
2. The maintainer keeps machine-local checkout paths, credentials, and secret
   names out of the contract.
3. The workflow validates the contract before any product release artifact is
   created or mutated.
4. The maintainer receives a clear stop reason when required non-secret
   contract fields are missing or ambiguous.

**Postconditions**: The hub can identify the selected product repository and
its release behavior without relying on hidden local state or leaking sensitive
information.

**Information shown**:

- Whether the product release contract is complete.
- Which non-secret fields are missing or ambiguous.
- Which values are defaults and which are explicitly configured.

**Actions available**:

- Add or correct non-secret product release metadata.
- Keep local checkout paths and credentials in local-only configuration.
- Retry validation after configuration is corrected.

**Considerations**:

- A valid contract identifies repository ownership and release behavior, not
  local machine paths or account credentials.

---

### Use Case 3: Sync only the right workflow files

**Actor**: Template maintainer or downstream adopter running role-aware sync.
**Preconditions**: A repository is classified as a workflow hub, product
repository, or unchanged single-repository adopter.

**Steps**:

1. The maintainer runs or reviews role-aware sync behavior.
2. The workflow selects files required by the repository role.
3. Product repositories receive the minimal release runtime surfaces needed for
   product-owned release work.
4. Hub-only coordination surfaces remain excluded from product repositories.
5. Tests verify that selected files match the documented ownership contract.

**Postconditions**: Repository role determines the synced release workflow
surface, and no repository receives files outside its ownership role.

**Information shown**:

- Repository role.
- Included release runtime surfaces.
- Excluded hub-only coordination surfaces.
- Validation or test evidence for the selected file set.

**Actions available**:

- Accept the selected sync set.
- Stop and correct role configuration when the selection is ambiguous.

## Business Rules

- Every release artifact named by the workflow has exactly one owner in each
  repository mode.
- Workflow hubs own tracker coordination, specs, plans, delivery coordination,
  and hub release records unless a later contract explicitly moves an artifact.
- Product repositories own product code, product release branches, product
  changelog entries, product tags, product release records, product deployment
  evidence, and product cleanup evidence.
- Single-repository mode keeps its current ownership behavior and must not
  require workflow-hub or product-repository configuration.
- Product release configuration is versioned only when it is non-secret and
  portable across machines.
- Local checkout paths, credentials, tokens, and secret values are never part of
  the versioned product release contract.
- Role-aware sync must fail closed when a repository role is unknown or when a
  file has no documented ownership.
- Product repositories receive the minimum release runtime surface needed to
  execute product-owned release work; hub-only coordination files remain
  hub-owned.

## Operational Visibility

- **Ownership map**: Operators can see the documented owner for every release
  artifact category before running a release or cleanup workflow.
- **Configuration validation**: Validation output names missing or ambiguous
  non-secret contract fields and confirms when no local paths or credentials
  are present.
- **Role-aware sync evidence**: Tests and sync output show which release files
  are included or excluded for workflow hubs, product repositories, and
  single-repository adopters.
- **Stop evidence**: When ownership cannot be determined, the workflow names
  the ambiguous artifact or repository role before mutation.

## Acceptance Criteria

- [ ] The workflow documentation includes an ownership map for tracker work,
      specs/plans, product code, changelogs, release branches, tags, GitHub
      releases, deployment evidence, delivery manifests, and cleanup.
- [ ] Each artifact in the ownership map has exactly one owner for workflow-hub,
      product-repository, and single-repository contexts.
- [ ] The product release contract records only non-secret, portable release
      metadata and identifies which values are defaults versus explicit
      configuration.
- [ ] Validation fails before release-artifact mutation when required product
      release contract information is missing or ambiguous.
- [ ] Validation confirms that versioned product release configuration does not
      include local checkout paths, credentials, tokens, or secret values.
- [ ] Role-aware sync behavior includes the minimum product release runtime
      files for product repositories and excludes hub-only coordination files.
- [ ] Automated tests prove the selected sync file set matches the documented
      ownership contract for workflow hub, product repository, and unchanged
      single-repository modes.
- [ ] Existing single-repository setup, release, and sync behavior remains
      compatible without requiring multi-repository configuration.

## Ownership Decision Matrix

| Repository context | Gate input | Allowed outcome | Required next action | Mirror surfaces | Verification example |
| --- | --- | --- | --- | --- | --- |
| Single repository | No multi-repository mode is configured | Use existing single-repository ownership | Continue existing release and sync behavior | Repository-mode docs, sync manifest, release guidance | Existing release workflow still validates without product-repository configuration. |
| Workflow hub | Artifact is tracker, spec, plan, delivery coordination, or hub release record | Hub-owned | Keep artifact in the hub and exclude product-only runtime files unless shared ownership is documented | Repository-mode docs, setup guidance, sync tests | Hub role sync includes hub coordination files and excludes product-only release runtime files. |
| Workflow hub selecting product work | Artifact is product code, product changelog, product release branch, product tag, product release record, product deployment evidence, or product cleanup evidence | Product-owned | Require a selected product repository and validate its non-secret release contract before mutation | Release protocol guidance, cleanup guidance, product contract docs | Missing product selection stops before branch, tag, release record, or cleanup mutation. |
| Product repository | Artifact belongs to product-owned release runtime | Product-owned | Include the minimal runtime surfaces needed for product release work | Role-aware sync, product-repository setup docs | Product role sync includes required release runtime files. |
| Unknown or mixed role | Artifact owner cannot be derived from repository role and contract | Stop | Report the ambiguous artifact and required configuration correction | Validation output and runner stop summaries | Unknown role fails closed before any release artifact is created. |

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Define owner for each release artifact | Use Case 1, Business Rules, AC1-AC2, Ownership Decision Matrix |
| 2. Add non-secret product release contract | Use Case 2, Business Rules, AC3-AC5 |
| 3. Update role-aware skeleton and sync behavior | Use Case 3, Business Rules, AC6-AC7 |
| 4. Every release artifact has one owner | Business Rules, AC1-AC2 |
| 5. Configuration validates without leaking local paths or credentials | Use Case 2, AC3-AC5 |
| 6. Role-aware sync tests prove selected files match ownership | Use Case 3, AC6-AC7 |
| 7. Preserve single-repository compatibility | Business Rules, AC8, Ownership Decision Matrix |

## Out of Scope (MVP)

- Implementing component release routing for a selected product repository.
- Creating delivery-bundle manifests or finalization workflows.
- Changing milestone stamping or release status reconciliation behavior.
- Migrating historical milestones, releases, tags, or tracker records.
- Storing local checkout paths, credentials, tokens, or secret values in
  versioned configuration.
