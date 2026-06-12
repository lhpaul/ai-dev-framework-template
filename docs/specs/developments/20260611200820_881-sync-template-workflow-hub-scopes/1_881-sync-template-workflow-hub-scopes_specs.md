# Sync-Template Workflow-Hub Scopes - Spec

**Depends on**: 875-shared-local-workflow-config, 876-workflow-hub-template-skeletons, 877-workflow-hub-product-repo-sync-status-scripts, 883-workflow-hub-smoke-fixtures

---

## Overview

Template synchronization must adapt to the repository role that is receiving the
framework update. Workflow hubs need the full staged workflow surface, while
product repositories should receive only the minimal integration files needed to
participate in hub-owned workflow orchestration. This feature makes sync-template
selection role-aware while preserving the current single-repository sync
experience.

## Brief Objective List

1. Read workflow mode and mode-specific sync categories during sync-template.
2. In `workflow_hub` mode, sync workflow protocols, agents, scripts, and
   framework docs to the hub.
3. In `product_repo` mode, sync only product repository injection files and
   CI-bound declared files.
4. Preserve current behavior for `single_repo` mode.
5. Report divergent local changes before overwriting.
6. Support hub-only and product-repo-injection scopes in the sync manifest.
7. Keep single-repo sync output unchanged except for documented metadata
   additions.
8. Prevent product repo sync from copying hub-owned tracker, spec, and plan
   artifacts.
9. Provide tests or fixtures that prove different output sets for hub and
   product repo modes.

## Use Cases

### Use Case 1: Maintainer syncs a workflow hub

**Actor**: Template maintainer operating a workflow hub
**Preconditions**: The target repository declares itself as a workflow hub and
has access to the upstream template source.

**Steps**:

1. The maintainer runs sync-template from the workflow hub.
2. The sync flow identifies the repository as a workflow hub.
3. The sync summary shows framework-managed workflow docs, protocols, agent
   definitions, command wrappers, scripts, and shared files that apply to the
   hub.
4. The maintainer reviews divergent local changes before any overwrite occurs.
5. The maintainer approves the sync.

**Postconditions**: The workflow hub receives the hub-owned framework update
set and does not lose unreviewed local changes.

**Information shown**:

- Resolved repository mode and role label.
- Template source and template version.
- Files selected for hub sync.
- Files skipped because they are product-repo-only.
- Divergent local changes that require review.

**Actions available**:

- Apply all selected hub sync updates.
- Apply only always-sync updates.
- Skip manual-review or special-handling files.
- Stop before applying when divergent local changes need a decision.

**Considerations**:

- Hub sync must include the workflow system of record: tracker protocols, specs,
  plans, orchestration scripts, and agent surfaces.
- Product repository injection files may still be visible as shared examples or
  references when the manifest marks them shared.

### Use Case 2: Maintainer syncs a product repository

**Actor**: Product repository maintainer
**Preconditions**: The target repository declares itself as a product repository
that is connected to a workflow hub.

**Steps**:

1. The maintainer runs sync-template from the product repository.
2. The sync flow identifies the repository as a product repository.
3. The sync summary shows only shared files and product repository injection
   files that are allowed for product repositories.
4. Hub-owned tracker, spec, plan, and orchestration artifacts are excluded from
   the product repository update set.
5. The maintainer reviews divergent local changes before approving the sync.

**Postconditions**: The product repository receives only its integration surface
and remains free of hub-owned workflow state.

**Information shown**:

- Resolved product repository mode.
- Files selected for product repository sync.
- Hub-only files skipped for this role.
- Any local files that differ from the template and need review.

**Actions available**:

- Apply allowed product repository sync updates.
- Skip optional or manual-review entries.
- Stop before applying when the selected file set is surprising.

**Considerations**:

- Product repositories must not receive hub-owned tracker, spec, or plan
  artifacts.
- The product repository may still receive CI or lightweight agent integration
  files when the manifest declares them as shared or product-repo-injection.

### Use Case 3: Existing single-repository adopter syncs as before

**Actor**: Existing single-repository adopter
**Preconditions**: The repository omits mode or explicitly declares
`single_repo`.

**Steps**:

1. The maintainer runs sync-template in the existing repository.
2. The sync flow resolves the repository as a single repository.
3. The sync summary presents the same practical file set the maintainer expects
   today.
4. Any new role metadata is visible only as explanatory context and does not
   remove files from the single-repository sync set.

**Postconditions**: Existing adopters keep the current sync behavior and are not
forced into workflow-hub or product-repo setup.

**Information shown**:

- Resolved single-repository mode.
- The selected sync file set.
- Any role metadata added to the summary.
- Divergent local changes before overwrite.

**Actions available**:

- Continue with the standard sync flow.
- Stop if local changes need review.

**Considerations**:

- Missing mode must remain backward-compatible with the existing
  single-repository workflow.

### Use Case 4: Maintainer previews role-specific sync output

**Actor**: Template maintainer or reviewer
**Preconditions**: The maintainer is evaluating a sync-template change or
reviewing a role-specific downstream repository.

**Steps**:

1. The maintainer runs sync-template in preview or dry-run mode.
2. The sync flow reports the resolved repository mode and selected file set.
3. The maintainer compares selected and skipped files for the target role.
4. The maintainer confirms that divergent local changes are listed before any
   apply step.

**Postconditions**: The maintainer can verify role-specific sync behavior
without mutating the target repository.

**Information shown**:

- Resolved role.
- Selected files.
- Skipped files grouped by mode scope.
- Divergent local changes.

**Actions available**:

- Continue to apply after review.
- Exit without changes.

**Considerations**:

- Preview output must be deterministic enough for tests and fixture assertions.

## Business Rules

- Sync-template must resolve repository mode before building the file selection
  set.
- Missing mode and explicit `single_repo` must preserve the existing
  single-repository file selection behavior.
- Workflow hubs receive hub-only files and shared files.
- Product repositories receive product-repo-injection files and shared files.
- Product repositories must not receive hub-owned tracker, spec, plan, workflow
  protocol, or hub orchestration artifacts unless a future manifest entry
  explicitly marks a specific file as product-repo-injection.
- Every selected file with divergent local content must be shown before it can be
  overwritten.
- Role-specific skipped files must be visible in the sync summary so maintainers
  can understand why a file was not selected.
- The sync manifest is the source of truth for role scopes.
- Unknown or unsupported mode-scope values must fail closed before file changes
  are applied.
- Product repository sync must not require private hub credentials for default
  preview or dry-run behavior.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `single_repo` | Single repository | One repository receives the existing full single-repository framework sync behavior. |
| `workflow_hub` | Workflow hub | The repository receives hub-owned workflow docs, protocols, agents, scripts, and shared files. |
| `product_repo` | Product repository | The repository receives only shared and product-repo-injection files. |
| `shared` | Shared | A manifest scope that applies across supported repository roles. |
| `hub_only` | Hub only | A manifest scope selected for workflow hubs and excluded from product repositories. |
| `product_repo_injection` | Product repository injection | A manifest scope selected for product repositories and excluded from hub-only sync sets unless also shared. |

**Valid transitions**:

- A sync run starts in a mode discovery state and transitions to one resolved
  repository role before file selection.
- A preview run can stop after summary without applying changes.
- An apply run can proceed only after the maintainer confirms the selected
  update set and any divergent local changes.

## Operational Visibility

- **Sync summary**: Reports repository mode, selected files, skipped files by
  scope, divergent local changes, and template version.
- **Dry-run output**: Shows the same role-specific selection information without
  mutating files.
- **PR description**: For sync-template PRs opened by the workflow, includes the
  resolved repository role and the categories of files applied.

## Acceptance Criteria

- [ ] AC1: A sync-template dry run in `workflow_hub` mode reports the repository
      role as workflow hub and selects hub-only plus shared framework files.
- [ ] AC2: A sync-template dry run in `product_repo` mode reports the repository
      role as product repository and selects product-repo-injection plus shared
      files.
- [ ] AC3: Product repository sync output excludes hub-owned tracker, spec,
      implementation-plan, workflow protocol, and hub orchestration artifacts.
- [ ] AC4: Missing mode and explicit `single_repo` produce the same practical
      sync selection as the current single-repository flow, apart from additive
      explanatory metadata in the summary.
- [ ] AC5: The sync summary identifies files skipped because their mode scope
      does not apply to the resolved repository role.
- [ ] AC6: Divergent local file changes are reported before any overwrite or
      apply step in every repository role.
- [ ] AC7: Unknown mode-scope values fail closed before file changes are applied.
- [ ] AC8: Tests or fixtures prove that hub and product repository modes produce
      different selected file sets from the same manifest.
- [ ] AC9: Default dry-run and fixture validation for product repository mode do
      not require private hub repositories, product credentials, or live GitHub
      App credentials.

## Out of Scope (MVP)

- Automatically migrating downstream repositories from single-repository mode to
  workflow-hub mode.
- Editing product repository business code during sync-template.
- Requiring live private product repository access for default tests.
- Designing a new manifest schema version beyond the existing mode-scope
  metadata required for role selection.
- Changing release or retrospective behavior after a sync PR merges.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Read workflow mode and mode-specific sync categories during sync-template. | AC1, AC2, AC4, AC5 |
| In `workflow_hub` mode, sync workflow protocols, agents, scripts, and framework docs to the hub. | AC1 |
| In `product_repo` mode, sync only product repository injection files and CI-bound declared files. | AC2, AC3 |
| Preserve current behavior for `single_repo` mode. | AC4 |
| Report divergent local changes before overwriting. | AC6 |
| Support hub-only and product-repo-injection scopes in the sync manifest. | AC1, AC2, AC5, AC7 |
| Keep single-repo sync output unchanged except for documented metadata additions. | AC4 |
| Prevent product repo sync from copying hub-owned tracker, spec, and plan artifacts. | AC3 |
| Provide tests or fixtures that prove different output sets for hub and product repo modes. | AC8, AC9 |
