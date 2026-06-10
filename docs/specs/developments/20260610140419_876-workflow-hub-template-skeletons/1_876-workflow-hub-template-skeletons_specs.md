# Workflow Hub and Product Repository Template Skeletons - Spec

**Depends on**: 874-workflow-hub-operating-model

---

## Overview

Workflow hub mode needs template skeletons that let teams inspect and apply only
the framework files appropriate for each repository role. A workflow hub should
carry workflow-owned protocols, scripts, agents, project configuration, and
runbooks, while a product repository should receive only the minimal integration
files needed to participate in routed work. This feature defines those skeleton
boundaries, sync-scope expectations, and setup guidance while keeping the
current root template valid for existing `single_repo` adopters.

## Brief Objective List

1. Add a `template/workflow-hub/` skeleton for workflow-owned protocols,
   scripts, agents, project config, and runbooks.
2. Add a `template/product-repo-injection/` skeleton for minimal product
   repository integration files.
3. Update the sync manifest model so files can be classified as shared,
   hub-only, or product-repo-injection.
4. Add README guidance for choosing the correct skeleton.
5. Keep the current root template valid for `single_repo` adopters.
6. Ensure new skeletons can be inspected without changing current single-repo
   setup behavior.
7. Ensure product repository injection excludes hub-owned tracker, spec, and
   plan artifacts unless explicitly required.
8. Explain how generated and existing repositories choose between
   `single_repo`, `workflow_hub`, and `product_repo` setup.

## Use Cases

### Use Case 1: Template maintainer inspects role-specific skeletons

**Actor**: Template maintainer
**Preconditions**: The repository contains the current single-repository
template.

**Steps**:

1. The maintainer opens the role-specific skeleton documentation.
2. The maintainer inspects `template/workflow-hub/` and
   `template/product-repo-injection/`.
3. The maintainer confirms that workflow hub files are grouped separately from
   product repository integration files.
4. The maintainer confirms that inspecting those skeletons does not alter the
   current single-repository template behavior.

**Postconditions**: The maintainer can review each role-specific skeleton
without applying it to the current repository layout.

**Information shown**:

- Skeleton purpose and intended repository role.
- Which categories of files belong in each skeleton.
- A statement that the root template remains the `single_repo` setup path.

**Actions available**:

- Review a skeleton before it is used.
- Compare skeleton contents against the artifact ownership model.

**Considerations**:

- Skeleton inspection must be passive; it must not trigger setup, sync, or
  injection behavior by itself.

### Use Case 2: Workflow hub adopter chooses the hub skeleton

**Actor**: Team setting up a workflow hub repository
**Preconditions**: The team wants one repository to coordinate workflow across
multiple product repositories.

**Steps**:

1. The team reads setup guidance for repository modes.
2. The team selects `workflow_hub` setup.
3. The team reviews the `template/workflow-hub/` skeleton.
4. The team confirms the skeleton includes workflow-owned protocols, scripts,
   agents, project configuration, and runbooks.
5. The team confirms product repository code scaffolding is not required in the
   hub skeleton.

**Postconditions**: The team understands which template content belongs in the
workflow hub.

**Information shown**:

- When to use the workflow hub skeleton.
- Hub-owned file categories.
- Relationship between the hub skeleton and product repository injection.

**Actions available**:

- Use the hub skeleton for a generated workflow hub.
- Use the hub skeleton as a reference when adapting an existing hub repository.

**Considerations**:

- The skeleton should avoid private product details and should be reusable
  across downstream teams.

### Use Case 3: Product repository adopter chooses minimal injection

**Actor**: Team integrating a product repository with a workflow hub
**Preconditions**: The product repository already owns product code and should
not receive the full workflow framework.

**Steps**:

1. The team reads setup guidance for `product_repo` mode.
2. The team inspects `template/product-repo-injection/`.
3. The team confirms the injection skeleton includes only the minimal files
   needed for product repository participation.
4. The team confirms hub-owned tracker, spec, and plan artifacts are excluded
   unless the setup guidance explicitly marks a file as required.

**Postconditions**: The product repository can participate in workflow hub
routing without taking ownership of hub-only planning artifacts.

**Information shown**:

- Product repository integration file categories.
- Explicit exclusions for hub-owned tracker, spec, and plan artifacts.
- Any shared files that are safe to inject into product repositories.

**Actions available**:

- Apply or inspect minimal product repository integration.
- Reject an injection set that includes hub-owned artifacts without an explicit
  requirement.

**Considerations**:

- Product repository injection must not surprise adopters by copying the full
  framework into every product repository.

### Use Case 4: Sync operator understands mode-specific file scopes

**Actor**: Workflow sync operator
**Preconditions**: The template sync manifest includes mode-specific file
scopes.

**Steps**:

1. The operator reads the sync manifest guidance.
2. The operator sees whether each relevant file is shared, hub-only, or product
   repository injection.
3. The operator confirms which files apply to a `single_repo`, `workflow_hub`,
   or `product_repo` target.
4. The operator uses the documented scope to reason about future sync behavior.

**Postconditions**: File ownership and sync scope are visible before any
mode-aware sync implementation runs.

**Information shown**:

- Shared scope definition.
- Hub-only scope definition.
- Product-repository-injection scope definition.
- How the current root template remains valid for `single_repo`.

**Actions available**:

- Review mode-specific sync scope.
- Flag files whose ownership scope is ambiguous.

**Considerations**:

- This spec defines the product behavior; implementation details for the sync
  manifest format belong in the implementation plan.

## Business Rules

- The root template remains valid for `single_repo` adopters.
- The `template/workflow-hub/` skeleton is for workflow-owned protocols,
  scripts, agents, project configuration, and runbooks.
- The `template/product-repo-injection/` skeleton is for minimal files needed by
  product repositories that participate in a workflow hub.
- Product repository injection must exclude hub-owned tracker, spec, and plan
  artifacts unless documentation explicitly states that a specific artifact is
  required for product repository participation.
- The sync manifest model must distinguish shared, hub-only, and
  product-repo-injection file scopes.
- Documentation must explain when to use `single_repo`, `workflow_hub`, and
  `product_repo` setup for both generated repositories and existing
  repositories.
- New skeleton directories must be inspectable without changing current
  single-repository setup behavior.
- Skeleton examples must avoid private project names, private repository names,
  and private team topology.

## Statuses / Enum Values

| Code value               | Display label                | Description                                                 |
| ------------------------ | ---------------------------- | ----------------------------------------------------------- |
| `shared`                 | Shared                       | File applies across supported repository roles.             |
| `hub_only`               | Hub only                     | File belongs only in a workflow hub repository.             |
| `product_repo_injection` | Product repository injection | File may be injected into a product repository integration. |

**Valid transitions**:

- Unscoped template file -> one of the explicit sync scopes when it is modeled
  in the mode-aware sync manifest.
- Hub-owned artifact -> `hub_only` unless explicitly required in product
  repository integration.
- Product repository integration artifact -> `product_repo_injection` when it is
  safe to copy into a product repository.

## Operational Visibility

- **README guidance**: Setup documentation states which skeleton to inspect or
  use for each repository mode.
- **Skeleton directories**: Role-specific skeletons can be browsed directly.
- **Sync manifest**: File scopes are visible as shared, hub-only, or product
  repository injection.
- **Spec PR**: The coverage matrix shows how every skeleton and scope
  requirement maps to acceptance criteria.

## Acceptance Criteria

- [ ] AC1: `template/workflow-hub/` exists as an inspectable skeleton for
      workflow-owned protocols, scripts, agents, project configuration, and
      runbooks.
- [ ] AC2: `template/product-repo-injection/` exists as an inspectable skeleton
      for minimal product repository integration files.
- [ ] AC3: Inspecting the new skeletons does not change current single-repo
      setup behavior.
- [ ] AC4: Product repository injection excludes hub-owned tracker, spec, and
      plan artifacts unless a document explicitly marks a specific artifact as
      required.
- [ ] AC5: The sync manifest model can distinguish shared, hub-only, and
      product-repo-injection files.
- [ ] AC6: README guidance explains when a generated repository chooses
      `single_repo`, `workflow_hub`, or `product_repo` setup.
- [ ] AC7: README guidance explains how an existing repository chooses between
      `single_repo`, `workflow_hub`, and `product_repo` setup.
- [ ] AC8: The current root template remains valid for `single_repo` adopters.
- [ ] AC9: Skeleton and README examples avoid hardcoded private project,
      repository, or team details.

## Coverage Matrix

| Brief objective                                                                                                                | Coverage |
| ------------------------------------------------------------------------------------------------------------------------------ | -------- |
| Add a `template/workflow-hub/` skeleton for workflow-owned protocols, scripts, agents, project config, and runbooks.           | AC1      |
| Add a `template/product-repo-injection/` skeleton for minimal product repo integration files.                                  | AC2, AC4 |
| Update the sync manifest to model mode-specific scopes.                                                                        | AC5      |
| Add README guidance for when to use each skeleton.                                                                             | AC6, AC7 |
| Keep the current root template valid for `single_repo` adopters.                                                               | AC3, AC8 |
| New skeletons can be inspected without changing current single-repo setup behavior.                                            | AC3      |
| Product repo injection excludes hub-owned tracker/spec/plan artifacts unless explicitly required.                              | AC4      |
| Documentation explains how generated or existing repos choose between `single_repo`, `workflow_hub`, and `product_repo` setup. | AC6, AC7 |

## Out of Scope (MVP)

- Implementing the sync command behavior that consumes mode-specific scopes.
- Automatically applying skeletons to downstream repositories.
- Removing or replacing the current root template for `single_repo` adopters.
- Defining private downstream repository structures.
- Changing reviewer-loop, CI, tracker, spec, or plan behavior beyond the
  skeleton ownership documentation.
