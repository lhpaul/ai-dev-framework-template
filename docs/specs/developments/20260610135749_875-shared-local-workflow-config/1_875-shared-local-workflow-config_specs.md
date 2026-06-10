# Shared and Local Workflow Configuration - Spec

**Depends on**: 874-workflow-hub-operating-model

---

## Overview

Workflow hub support needs a clear split between versioned repository
configuration and machine-local configuration. Shared configuration should
describe stable repository identity and workflow mode, while local configuration
should describe checkout paths, local secrets, and developer-specific tool
overrides. This feature defines the expected configuration behavior and
validation outcomes so workflow scripts and agents can resolve repository
context consistently.

## Brief Objective List

1. Document shared workflow configuration fields for `mode`,
   `workflow_hub.product_repos[]`, and `product_repo.workflow_hub`.
2. Keep versioned product repository entries limited to stable non-secret
   identity and metadata.
3. Introduce gitignored `.ai-dev-workflow.local.yaml` for checkout paths,
   checkout defaults, secret references, and local tool overrides.
4. Provide shared repository-context helpers that scripts can call to read mode,
   merge shared and local config, resolve product repositories, and return
   context values.
5. Add validation that fails clearly for missing or ambiguous repository
   configuration.
6. Add `.ai-dev-workflow.local.yaml` to gitignore and provide
   `.ai-dev-workflow.local.example.yaml`.
7. Define compatibility or migration behavior for `.tmp/template-config.json`.
8. Preserve existing behavior for repositories with no mode declaration.
9. Cover single-repository, workflow-hub, product-repository, local override,
   invalid config, and missing local path cases with tests.

## Use Cases

### Use Case 1: Existing adopter resolves repository context without new config

**Actor**: Existing single-repository workflow adopter
**Preconditions**: The repository has no explicit workflow mode declaration.

**Steps**:

1. The adopter runs a workflow script or agent command.
2. The workflow reads repository configuration.
3. Because no mode is declared, the workflow treats the repository as
   `single_repo`.
4. The workflow resolves repository context using current single-repository
   behavior.

**Postconditions**: Existing repositories continue to work without adding new
configuration files.

**Information shown**:

- The resolved mode is `single_repo`.
- No migration is required for the existing single-repository path.
- Missing optional local configuration is not an error in `single_repo` mode.

**Actions available**:

- Continue running current workflow commands.
- Add explicit mode configuration later if the repository adopts hub or product
  repository behavior.

**Considerations**:

- The default must be documented and testable so adopters can rely on it during
  migration.

### Use Case 2: Workflow hub owner declares product repositories safely

**Actor**: Workflow hub owner
**Preconditions**: A hub repository coordinates work across multiple product
repositories.

**Steps**:

1. The owner declares the repository as `workflow_hub`.
2. The owner lists each product repository with a stable name and stable remote
   identity.
3. The owner includes non-secret metadata that helps route work, such as default
   branch, role, scope, tracker hints, or app identifiers.
4. The owner keeps checkout paths, private key paths, and secret values out of
   versioned configuration.

**Postconditions**: The hub can identify target product repositories without
storing local paths or secrets in version control.

**Information shown**:

- Product repository stable name.
- Product repository remote identity, such as a GitHub repository slug or git
  URL.
- Default branch and optional non-secret routing metadata.
- A clear boundary between versioned and local-only values.

**Actions available**:

- Add, remove, or rename stable product repository entries through normal
  versioned review.
- Run validation to catch duplicate names, missing remote identity, or ambiguous
  target selection.

**Considerations**:

- Product repository names must be stable enough for work items to reference.
- The spec should not require any private project-specific names.

### Use Case 3: Developer provides local checkout context

**Actor**: Developer or workflow agent running commands on a local machine
**Preconditions**: The workflow needs a local checkout path for a product
repository.

**Steps**:

1. The developer creates the gitignored local workflow configuration file from
   the example file.
2. The developer supplies local checkout paths or a checkout root default.
3. The developer supplies local secret references or private key paths only in
   local configuration.
4. The workflow resolves the product repository to a local path using the local
   override, a documented default, or a clear failure.

**Postconditions**: Workflow scripts can find the intended local checkout
without storing machine-specific paths in version control.

**Information shown**:

- Which local path was selected.
- Whether the path came from an explicit local override or a documented default.
- A clear error when no usable local path can be resolved.

**Actions available**:

- Update local checkout path mappings.
- Use local reviewer or tool overrides without changing shared repository
  configuration.
- Migrate from the existing local override file according to documented
  compatibility rules.

**Considerations**:

- Local configuration must remain ignored by git.
- Example local configuration must avoid real secrets and private paths.

### Use Case 4: Script or agent resolves repository context consistently

**Actor**: Workflow script or AI workflow agent
**Preconditions**: The script or agent needs mode, target repository, branch,
local path, or tracker context.

**Steps**:

1. The script asks the shared repository-context layer for the current mode.
2. The script asks for a product repository by stable name or by the current
   repository context.
3. The repository-context layer combines shared and local configuration.
4. The script receives shell-callable values for local path, remote repository
   identity, default branch, and tracker hints.
5. If the target is missing or ambiguous, the script receives a clear failure
   instead of guessing.

**Postconditions**: Scripts and agents use one consistent repository-context
contract instead of duplicating parsing and fallback behavior.

**Information shown**:

- Resolved mode.
- Resolved stable repository name.
- Resolved remote repository identity.
- Resolved default branch.
- Resolved local path or clear missing-path error.
- Tracker hints when available.

**Actions available**:

- Continue when all required context values resolve.
- Stop with a clear validation message when required context is absent or
  ambiguous.

**Considerations**:

- Helper outputs must be safe to consume from shell scripts.
- Validation should fail before destructive or cross-repository actions run.

## Business Rules

- Missing mode declaration resolves as `single_repo`.
- Shared workflow configuration may contain stable mode and repository identity
  only; machine-local paths and secrets must not be required in versioned
  configuration.
- A workflow hub may declare multiple product repositories, each identified by a
  stable name and either a GitHub repository slug or git URL.
- Product repository entries may include default branch, role or scope metadata,
  tracker hints, and optional non-secret app identifiers.
- Local workflow configuration owns checkout paths, checkout root defaults,
  private key paths or secret references, and local reviewer or tool overrides.
- The local workflow configuration file is `.ai-dev-workflow.local.yaml`, and it
  must be ignored by git.
- The example local configuration file is
  `.ai-dev-workflow.local.example.yaml`; it must document the local-only fields
  without containing real secrets, private paths, or private repository names.
- The shared workflow configuration fields for this feature are `mode`,
  `workflow_hub.product_repos[]`, and `product_repo.workflow_hub`.
- Product repository entries under `workflow_hub.product_repos[]` must use
  stable identity fields such as `name`, `github_repo` or `git_url`, and
  `default_branch`, plus optional non-secret metadata.
- Repository-context helper output must be shell-callable and suitable for
  existing workflow scripts.
- Missing or ambiguous product repository selection must fail clearly before a
  script performs routing, branch, PR, or checkout actions.
- Existing local override behavior must either continue as a compatibility
  fallback or have a documented migration path.
- Tests must cover valid and invalid repository-context resolution across
  `single_repo`, `workflow_hub`, and `product_repo` modes.

## Statuses / Enum Values

| Code value     | Display label      | Description                                                                |
| -------------- | ------------------ | -------------------------------------------------------------------------- |
| `single_repo`  | Single repository  | Current behavior: one repository owns workflow and product artifacts.      |
| `workflow_hub` | Workflow hub       | A coordination repository routes work to one or more product repositories. |
| `product_repo` | Product repository | A product repository can receive routed work from a workflow hub.          |

**Valid transitions**:

- Missing declaration -> `single_repo` for backward-compatible resolution.
- `single_repo` -> `workflow_hub` when a repository begins coordinating
  multiple product repositories.
- `single_repo` -> `product_repo` when a repository becomes a target for a
  workflow hub.

## Operational Visibility

- **Validation output**: Validation reports the resolved mode, selected product
  repository, and any missing or ambiguous required values.
- **Example local config**: `.ai-dev-workflow.local.example.yaml` shows
  local-only fields and safe placeholder values.
- **Compatibility notes**: Documentation states whether the existing
  `.tmp/template-config.json` override file remains supported and how users
  migrate if it is replaced.
- **Test output**: The test suite demonstrates successful and failing resolution
  paths for each supported mode.

## Acceptance Criteria

- [ ] AC1: A repository with no mode declaration resolves as `single_repo`.
- [ ] AC2: Shared workflow documentation describes `mode`,
      `workflow_hub.product_repos[]`, and `product_repo.workflow_hub`.
- [ ] AC3: A workflow hub can declare multiple product repositories by stable
      name plus GitHub repository slug or git URL.
- [ ] AC4: Versioned product repository entries are limited to stable non-secret
      identity, default branch, role or scope metadata, tracker hints, and
      optional non-secret app identifiers.
- [ ] AC5: Local checkout paths, checkout root defaults, private key paths or
      secret references, and local reviewer or tool overrides are documented as
      local-only configuration.
- [ ] AC6: `.ai-dev-workflow.local.yaml` is ignored by git, and
      `.ai-dev-workflow.local.example.yaml` documents required local-only fields
      without real secrets or private paths.
- [ ] AC7: Repository-context helpers expose shell-callable outputs for mode,
      local path, remote repository identity, default branch, and tracker hints.
- [ ] AC8: Local checkout path resolution uses an explicit local override, a
      documented default, or a clear error.
- [ ] AC9: Validation fails clearly when product repository configuration is
      missing, duplicated, or ambiguous.
- [ ] AC10: Existing `.tmp/template-config.json` behavior is preserved as a
      compatibility fallback or replaced with documented migration coverage.
- [ ] AC11: Tests cover `single_repo`, valid and invalid `workflow_hub`,
      `product_repo`, local path overrides, and missing local path cases.

## Coverage Matrix

| Brief objective                                                                                               | Coverage |
| ------------------------------------------------------------------------------------------------------------- | -------- |
| Document shared fields for `mode`, `workflow_hub.product_repos[]`, and `product_repo.workflow_hub`.           | AC2      |
| Keep versioned product repo entries limited to stable identity and metadata.                                  | AC3, AC4 |
| Introduce gitignored `.ai-dev-workflow.local.yaml` for paths, defaults, secrets, and overrides.               | AC5, AC6 |
| Add shared helpers to read mode, merge config, resolve product repos, and return context values.              | AC7, AC8 |
| Add validation that fails clearly on missing or ambiguous repo config.                                        | AC9      |
| Add `.ai-dev-workflow.local.yaml` to gitignore and provide `.ai-dev-workflow.local.example.yaml`.             | AC6      |
| Define compatibility or migration behavior for `.tmp/template-config.json`.                                   | AC10     |
| Existing repos with no mode declaration still resolve as `single_repo`.                                       | AC1      |
| Tests cover single-repo, valid/invalid hub, product-repo, local path overrides, and missing local path cases. | AC11     |

## Out of Scope (MVP)

- Implementing cross-repository orchestration beyond repository-context
  resolution.
- Changing tracker data models or adding new tracker fields.
- Storing real secrets, private keys, private checkout paths, or private project
  names in repository files.
- Requiring existing single-repository adopters to add a mode declaration before
  their current workflow continues to work.
- Defining UI screens for editing workflow configuration.
