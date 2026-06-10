# Workflow Hub Operating Model and Artifact Ownership - Spec

---

## Overview

The framework needs a shared operating model for teams that want one workflow
hub to coordinate AI development across multiple product repositories. This
feature adds an architecture note that defines the supported repository modes,
where workflow artifacts live in each mode, and how work items identify their
target product repository. The note is documentation-only and must preserve the
current behavior for existing single-repository adopters.

## Brief Objective List

1. Define the supported repository modes: `single_repo`, `workflow_hub`, and
   `product_repo`.
2. Define artifact ownership for backlog or tracker items, specs, plans, smoke
   runbooks, implementation branches, PRs, CI checks, and reviewer-loop checks.
3. Define how a work item selects its target product repository.
4. Define what lives in the workflow hub versus what gets injected into product
   repositories.
5. Preserve current behavior for existing single-repository adopters.
6. Link the architecture note from the repository README and development
   workflow README.
7. State that a missing mode declaration is treated as `single_repo`.
8. State where spec, plan, and code PRs are opened in each mode.
9. Include a generic multi-product example similar to a Faind-style hub without
   hardcoding private project details.
10. Avoid runtime behavior changes in this item.

## Use Cases

### Use Case 1: Framework maintainer defines the supported repository modes

**Actor**: Framework maintainer
**Preconditions**: The workflow hub mode work has been approved for
documentation.

**Steps**:

1. The maintainer opens the architecture note from the repository README or the
   development workflow README.
2. The maintainer reads the supported modes and their display labels.
3. The maintainer confirms which artifacts are owned by the hub and which are
   owned by product repositories.
4. The maintainer uses the note as the source of truth for later script, agent,
   and template changes.

**Postconditions**: The framework has a documented operating model that later
implementation work can reference without redefining repository responsibilities.

**Information shown**:

- The three supported modes and their meanings.
- A per-mode artifact ownership table.
- The rule for selecting the target product repository.
- The default behavior when no mode declaration exists.

**Actions available**:

- Link to the note from workflow documentation.
- Use the note to review later implementation plans for mode-specific behavior.

**Considerations**:

- The note must stay precise enough to guide implementation work without
  changing runtime behavior in this item.
- Private project names, private repository names, and private team details must
  not be hardcoded.

### Use Case 2: Existing single-repository adopter verifies nothing changes

**Actor**: Existing downstream adopter using the current single-repository
workflow
**Preconditions**: The adopter has not declared a repository mode.

**Steps**:

1. The adopter reads the architecture note.
2. The adopter checks the missing-mode rule.
3. The adopter confirms that missing mode is treated as `single_repo`.
4. The adopter confirms that backlog items, specs, plans, implementation
   branches, PRs, CI checks, and reviewer-loop checks remain in the current
   repository.

**Postconditions**: Existing adopters can continue using the workflow without a
new required configuration step.

**Information shown**:

- The default mode rule.
- The artifact ownership table for `single_repo`.
- A statement that this item introduces no runtime behavior changes.

**Actions available**:

- Continue using the current workflow unchanged.
- Defer any explicit mode declaration until a later implementation item makes
  one useful.

**Considerations**:

- The note must not imply that an existing repository has to migrate before
  continuing normal workflow operations.

### Use Case 3: Workflow hub operator routes a work item to a product repo

**Actor**: Workflow hub operator
**Preconditions**: The team uses a hub repository to coordinate work across
multiple product repositories.

**Steps**:

1. The operator creates or reviews a work item in the workflow hub.
2. The work item identifies its target product repository using a visible,
   unambiguous target-repository value.
3. The operator checks the architecture note to determine which artifacts remain
   in the hub and which artifacts are opened in the product repository.
4. The operator confirms that specs and plans are reviewed in the hub while code
   changes, product CI, and product reviewer-loop checks happen in the target
   product repository.

**Postconditions**: The work item has one clear target product repository for
implementation work, and reviewers can tell where each PR should be opened.

**Information shown**:

- Target repository selection rule.
- Artifact ownership table for `workflow_hub` and `product_repo`.
- A generic multi-product hub example.

**Actions available**:

- Route a work item to the intended product repository.
- Reject or flag a work item whose target repository is missing or ambiguous.

**Considerations**:

- A work item that affects more than one product repository must make that
  multi-target nature visible rather than relying on an implicit default.
- The spec should not prescribe the technical storage format for the target
  repository value; that belongs in the implementation plan.

## Business Rules

- Exactly three repository modes are supported by the architecture note:
  `single_repo`, `workflow_hub`, and `product_repo`.
- If a repository has no mode declaration, the documented interpretation is
  `single_repo`.
- In `single_repo` mode, all workflow artifacts and product implementation
  artifacts remain in the same repository.
- In `workflow_hub` mode, the hub owns portfolio-level coordination, tracker
  items, specs, plans, and cross-repository workflow documentation.
- In `product_repo` mode, the product repository owns product code changes,
  implementation branches, product PRs, product CI checks, and product
  reviewer-loop checks.
- A hub-managed work item must identify its target product repository before
  implementation work can be routed to a product repository.
- The architecture note must state where spec PRs, plan PRs, and code PRs are
  opened in every supported mode.
- The architecture note must define what framework-owned content is expected to
  live in the hub and what framework-owned content may be injected into product
  repositories.
- The generic multi-product example must avoid private project details while
  still showing a hub with multiple product repositories.
- This item must not introduce runtime behavior changes, new automation
  requirements, or migration requirements for existing adopters.

## Statuses / Enum Values

| Code value     | Display label      | Description                                                                |
| -------------- | ------------------ | -------------------------------------------------------------------------- |
| `single_repo`  | Single repository  | One repository owns tracker work, document PRs, code PRs, CI, and reviews. |
| `workflow_hub` | Workflow hub       | A coordination repository owns workflow planning across product repos.     |
| `product_repo` | Product repository | A product repository receives routed implementation work from a hub.       |

**Valid transitions**:

- Missing mode declaration -> `single_repo` for interpretation and
  documentation.
- `single_repo` -> `workflow_hub` when a team intentionally introduces a hub
  repository to coordinate multiple products.
- `single_repo` -> `product_repo` when a repository becomes a product target
  that receives work from a workflow hub.
- `workflow_hub` and `product_repo` are complementary roles; a team may use both
  roles at once across different repositories.

## Operational Visibility

- **Documentation links**: The repository README and development workflow README
  link to the architecture note.
- **Architecture note**: The note contains the mode definitions, artifact
  ownership table, target repository selection rule, default mode rule, and
  generic multi-product example.
- **PR description**: The spec PR records the brief coverage matrix and document
  quality gate so reviewers can verify every brief objective was considered.

## Acceptance Criteria

- [ ] AC1: The repository includes an architecture note that defines
      `single_repo`, `workflow_hub`, and `product_repo` with display labels and
      user-facing descriptions.
- [ ] AC2: The architecture note is linked from the repository README and the
      development workflow README.
- [ ] AC3: The note states that a missing mode declaration is interpreted as
      `single_repo`.
- [ ] AC4: The note identifies the owner for backlog or tracker items, specs,
      plans, smoke runbooks, implementation branches, PRs, CI checks, and
      reviewer-loop checks in each supported mode.
- [ ] AC5: The note states where spec PRs, plan PRs, and code PRs are opened in
      each supported mode.
- [ ] AC6: The note defines how a hub-managed work item identifies its target
      product repository, including the expectation that ambiguous or missing
      targets are flagged before product implementation routing.
- [ ] AC7: The note distinguishes content that lives in the workflow hub from
      content that may be injected into product repositories.
- [ ] AC8: The note includes a generic multi-product hub example similar to a
      Faind-style setup without hardcoding private project, repository, or team
      details.
- [ ] AC9: Existing single-repository adopters can read the note and verify that
      current behavior is preserved when no mode is declared.
- [ ] AC10: The implementation for this item changes documentation only and does
      not introduce runtime behavior changes.

## Coverage Matrix

| Brief objective                                                                                                                                       | Coverage |
| ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Define supported modes: `single_repo`, `workflow_hub`, and `product_repo`.                                                                            | AC1      |
| Define artifact ownership for backlog/tracker items, specs, plans, smoke runbooks, implementation branches, PRs, CI checks, and reviewer-loop checks. | AC4, AC5 |
| Define how a work item selects its target product repo.                                                                                               | AC6      |
| Define what lives in the workflow hub versus what gets injected into product repos.                                                                   | AC7      |
| Preserve current behavior for existing single-repo adopters.                                                                                          | AC3, AC9 |
| Architecture note is linked from the main README and development workflow README.                                                                     | AC2      |
| Missing mode declaration is explicitly treated as `single_repo`.                                                                                      | AC3      |
| The note states where spec, plan, and code PRs are opened in each mode.                                                                               | AC5      |
| Examples include a Faind-like workflow hub with multiple product repos without hardcoding private project details.                                    | AC8      |
| No runtime behavior changes are introduced by this item.                                                                                              | AC10     |

## Out of Scope (MVP)

- Implementing mode-aware scripts, agents, or template injection behavior.
- Adding validation that enforces mode declarations or target repository values.
- Migrating existing downstream repositories to explicit mode declarations.
- Changing PR routing, CI execution, reviewer-loop execution, or tracker
  automation.
- Defining private project-specific repository names, team names, or product
  topology.
