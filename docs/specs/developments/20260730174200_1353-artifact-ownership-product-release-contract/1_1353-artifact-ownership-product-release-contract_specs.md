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
4. The operator uses the ownership map together with
   [Repository Modes](../../../workflow/development-workflow/repository-modes.md)
   to choose the correct repository before starting release, cleanup, or
   evidence collection work.

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
- Supported mode names, display labels, and fallback behavior remain defined in
  the repository-mode source of truth; this spec only adds release-specific
  artifact ownership and product-release contract expectations.

---

### Use Case 2: Configure a product release contract

**Actor**: Workflow maintainer configuring a hub-managed product repository.
**Preconditions**: The maintainer knows the product repository identity and the
non-secret release information the hub is allowed to store.

**Steps**:

1. The maintainer records the product repository release contract in the
   appropriate versioned configuration surface.
2. The maintainer keeps every value from the canonical forbidden-data list out
   of the contract.
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

**Considerations**:

- Unknown or mixed repository roles stop before file selection.
- The `single_repo` result preserves the current manifest selection.
- Invalid or stale sync selections must be corrected before apply mode runs.

## Product Release Contract Fields

The product release contract is a non-secret, reviewable description of how a
workflow hub identifies a product repository and its release behavior.

Canonical forbidden-data list: local checkout paths, credentials, tokens,
secret names, secret values, and environment-specific account details.

Branch contract values must be machine-checkable without depending on a
particular Git client. A branch name is valid when it is a non-empty sequence of
slash-separated segments, every segment contains only letters, numbers, `.`,
`_`, or `-`, no segment is empty, and the full value contains none of these
portable forbidden forms: whitespace, `..`, `@{`, `//`, a leading slash, a
trailing slash, `?`, `^`, `~`, `:`, backslash, or `#`. A branch value is
unresolved when a required input such as the product repository key or release
version is missing, or when placeholder text remains after resolution. A release
branch pattern is a human-readable template that may use only `{version}` and
`{product_repo}` placeholders; after substituting one release version and one
selected product repository key, it must produce exactly one valid branch name.

| Field | Required | Allowed values | Default semantics | Ambiguity rules |
| --- | --- | --- | --- | --- |
| Product repository key | Required in `workflow_hub` for product-owned release work | One stable product repository key from hub configuration | No default when more than one product repository is configured | Missing key, unknown key, or multiple keys for one product item stops before release mutation |
| GitHub repository | Required for each configured product repository | Owner/repository slug | No implicit fallback in `workflow_hub`; current repository in `single_repo` | Missing or malformed slug stops before branch, PR, tag, GitHub Release, or cleanup mutation |
| Default release base | Optional | One valid branch name using the branch contract above | Product repository default branch when omitted; current release base in `single_repo` | Empty, invalid, or unresolved branch names stop before branch creation |
| Release branch pattern | Optional | One branch pattern using the placeholder rules above | `release/v{version}` for `single_repo`, `workflow_hub` product releases, and `product_repo` product releases | Multiple active patterns, unknown placeholders, unresolved placeholders, or a pattern that does not resolve to exactly one valid branch name are ambiguous |
| Changelog owner | Optional | Product repository or not applicable | Product repository for product-owned releases; current repository in `single_repo` | Hub-owned changelog for product code is invalid unless a later contract explicitly allows it |
| Tag owner | Optional | Product repository or not applicable | Product repository for product-owned releases; current repository in `single_repo` | Hub-owned product tags are invalid unless a later contract explicitly allows them |
| GitHub Release owner | Optional | Product repository or not applicable | Product repository for product-owned releases; current repository in `single_repo` | "Release record" means a GitHub Release; any other record type must be named separately before implementation |
| Deployment evidence owner | Optional | Product repository, hub reference, or not applicable | Product repository records source evidence; hub may reference it in delivery coordination | Evidence with no product source or only a hub assertion is incomplete |
| Product branch/PR cleanup evidence owner | Optional | Product repository, current repository, or not applicable | Product repository for product-owned releases; current repository in `single_repo` | Missing product branch or PR cleanup evidence is incomplete for product-owned releases |
| Tracker reconciliation evidence owner | Optional | Hub repository, current repository, or not applicable | Hub repository for hub-managed product releases; current repository in `single_repo` | Tracker reconciliation evidence is ambiguous when it is recorded only in the product repository for hub-tracked work |

## Role-Aware Sync Oracle

Role-aware sync compares selected files against logical release surfaces, not
against product-specific path guesses. The repository-mode document defines the
`mode_scope` mechanics; this spec defines the release-specific oracle that tests
must verify.

| Repository role | Required included logical surfaces | Required excluded logical surfaces | Expected result |
| --- | --- | --- | --- |
| `single_repo` | Existing shared, hub, product, release, setup, and workflow surfaces selected by the current manifest | None beyond existing manifest exclusions | Unchanged file-selection behavior |
| `workflow_hub` | Shared workflow surfaces, hub tracker coordination, hub specs/plans, delivery coordination guidance, hub release manifest guidance, and product contract documentation | Product-only runtime wrappers, product-local release execution files, product smoke fixtures, local checkout paths, and credentials | Hub can coordinate release ownership without receiving product-only runtime state |
| `product_repo` | Shared workflow surfaces, product release runtime wrappers, product CI/reviewer handoff guidance, product smoke/runbook scaffolding, and product-local cleanup helpers required for product-owned release work | Hub tracker state, historical hub specs/plans, hub-only delivery coordination records, cross-product portfolio state, and hub-only runbooks | Product repository can execute product-owned release work without inheriting hub coordination state |
| Unknown or invalid role | None | All mutating apply selections | Fail closed before file changes |

## Business Rules

- Every release artifact named by the workflow has exactly one owner in each
  repository mode.
- Single-repository mode keeps its current ownership behavior and must not
  require workflow-hub or product-repository configuration.
- Product release configuration is versioned only when it is non-secret and
  portable across machines.
- Values from the canonical forbidden-data list are never part of the versioned
  product release contract.
- Role-aware sync must fail closed when a repository role is unknown or when a
  file has no documented ownership.
- Product repositories receive the minimum release runtime surface needed to
  execute product-owned release work; hub-only coordination files remain
  hub-owned.
- "Release record" means a GitHub Release unless another record type is named
  explicitly in a later spec.

## Release Artifact Ownership Table

| Release artifact | `single_repo` owner | `workflow_hub` owner | `product_repo` owner |
| --- | --- | --- | --- |
| Tracker work | Current repository tracker | Hub tracker | Hub tracker |
| Specs and plans | Current repository | Hub repository | Hub repository |
| Product code | Current repository | Selected product repository for product work; hub only for hub-owned workflow code | Product repository |
| Changelog entries | Current repository | Product repository for product releases; hub for hub-only releases | Product repository |
| Release branches | Current repository | Product repository for product releases; hub for hub-only releases | Product repository |
| Tags | Current repository | Product repository for product releases; hub for hub-only releases | Product repository |
| GitHub Releases | Current repository | Product repository for product releases; hub for hub-only releases | Product repository |
| Deployment evidence | Current repository | Product repository records source evidence; hub may reference it | Product repository |
| Delivery manifests | Current repository when a single-repo delivery manifest exists | Hub repository | Hub repository |
| Product branch and PR cleanup evidence | Current repository | Product repository | Product repository |
| Tracker reconciliation evidence | Current repository | Hub repository | Hub repository |

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
      include any value from the canonical forbidden-data list.
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
