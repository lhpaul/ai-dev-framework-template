# Workflow Hub Product Repository Sync and Status Scripts - Spec

**Depends on**: 875-shared-local-workflow-config

---

## Overview

Workflow hub operators need a dependable way to inspect and prepare local
product repository checkouts before workflow orchestration changes code, opens
branches, or creates pull requests. This feature adds workflow-hub-only command
surfaces for product repository sync, status, and pull-request visibility. The
commands keep local checkout state explicit, refuse unsafe mutations, and guide
operators toward the exact local configuration entry needed when a checkout
path is missing.

## Brief Objective List

1. Add a product repository sync command.
2. Add a workflow hub status command.
3. Add a product repository pull-request listing command if needed.
4. Support selecting one product repository or all configured product
   repositories where appropriate.
5. Refuse to run outside `workflow_hub` mode.
6. Use shared repository-context behavior.
7. Report the documented default or exact local config entry when a local path
   is missing.
8. Expose command help.
9. Avoid overwriting dirty product repository checkouts.
10. Bootstrap missing local checkout paths into local config only after explicit
    confirmation.
11. Cover success and failure paths with shell validation.

## Use Cases

### Use Case 1: Hub operator views product repository status

**Actor**: Workflow hub operator
**Preconditions**: The current repository is configured as a workflow hub with
one or more product repositories.

**Steps**:

1. The operator asks for hub status across all product repositories or for one
   named product repository.
2. The command resolves the selected product repository context.
3. The command reports whether each selected local checkout exists, which
   branch it is on, whether it has uncommitted changes, and whether its remote
   state can be inspected.
4. The command exits without modifying any product repository checkout.

**Postconditions**: The operator has a current, readable status summary before
running mutating orchestration work.

**Information shown**:

- Resolved workflow mode.
- Selected product repository name.
- Local checkout path or missing-path guidance.
- Current branch when the checkout exists.
- Dirty or clean working tree state.
- Remote visibility or remote-check failure.

**Actions available**:

- Re-run status for one product repository.
- Re-run status for all configured product repositories.
- Fix missing local configuration.
- Stop before orchestration if any checkout is unsafe.

**Considerations**:

- Missing local checkouts must not be treated as clean checkouts.
- Dirty checkouts must be visible enough for an operator to decide whether to
  commit, stash, or abort.

### Use Case 2: Hub operator syncs product repository checkouts

**Actor**: Workflow hub operator
**Preconditions**: The current repository is configured as a workflow hub, and
the selected product repository has a resolvable local checkout path.

**Steps**:

1. The operator asks to sync one product repository or all configured product
   repositories.
2. The command resolves the selected repository context.
3. Before changing anything, the command checks whether each local checkout has
   uncommitted changes.
4. If a checkout is clean, the command updates it according to the documented
   safe sync behavior.
5. If a checkout is dirty, the command refuses to overwrite it and reports the
   path that needs attention.

**Postconditions**: Clean selected checkouts are prepared for workflow hub work,
and dirty checkouts remain untouched.

**Information shown**:

- Product repository name.
- Local checkout path.
- Branch before and after sync when available.
- Whether the repository was synced, skipped, missing, or blocked because it
  was dirty.
- Clear next action for any skipped or blocked repository.

**Actions available**:

- Sync one named product repository.
- Sync all configured product repositories.
- Stop and clean a dirty checkout.
- Add local path configuration when missing.

**Considerations**:

- The command must never hide partial success. If one of several product
  repositories is blocked, the final summary must identify which repositories
  synced and which did not.

### Use Case 3: Hub operator handles a missing local checkout path

**Actor**: Workflow hub operator
**Preconditions**: The workflow hub knows a product repository by stable name,
but no usable local checkout path can be resolved.

**Steps**:

1. The operator runs status or sync for the product repository.
2. The command attempts to resolve a local path from explicit local config or a
   documented default.
3. If no usable local path exists, the command reports the exact local config
   entry the operator should add.
4. If the command supports bootstrapping the missing path, it asks for explicit
   confirmation before writing local config.
5. If the operator declines confirmation, no local config changes are made.

**Postconditions**: The operator knows how to fix local configuration, and local
config is changed only after explicit confirmation.

**Information shown**:

- Product repository name.
- Missing local config location.
- Suggested local path or documented default when one exists.
- Whether any config change was made.

**Actions available**:

- Add local config manually.
- Confirm a supported bootstrap action.
- Decline and leave local files unchanged.

**Considerations**:

- Bootstrap prompts must be explicit because local checkout paths are
  machine-specific.

### Use Case 4: Hub operator lists product repository pull requests

**Actor**: Workflow hub operator
**Preconditions**: The current repository is configured as a workflow hub and
has product repositories with remote identity.

**Steps**:

1. The operator asks for pull-request visibility for one product repository or
   all configured product repositories.
2. The command resolves remote repository identity from repository context.
3. The command lists relevant open pull requests or states that none were
   found.
4. The command reports any repository whose remote pull requests could not be
   inspected.

**Postconditions**: The operator can see product repository pull-request state
from the hub before deciding what to resume or block.

**Information shown**:

- Product repository name.
- Remote repository identity.
- Open pull request number, title, branch, and review-readiness labels when
  available.
- Remote-inspection errors.

**Actions available**:

- List pull requests for one product repository.
- List pull requests for all configured product repositories.
- Open or inspect the reported pull requests with the configured VCS tool.

**Considerations**:

- Pull-request listing is read-only.

## Business Rules

- Commands in this feature are valid only in `workflow_hub` mode.
- A command must fail clearly when run from `single_repo` or `product_repo`
  mode.
- Commands must resolve product repository context from the shared
  repository-context behavior defined by #875.
- Operators must be able to target one named product repository where that is
  meaningful.
- Operators must be able to target all configured product repositories where
  that is meaningful.
- Commands must expose help that explains purpose, required mode, target
  selection, and safe-failure behavior.
- Status and pull-request listing commands are read-only.
- Sync must not overwrite a dirty product repository checkout.
- Sync must report partial success and partial failure across multi-repository
  runs.
- Missing local checkout paths must report either the documented default path or
  the exact local config entry to add.
- Missing local checkout paths may be written into local config only after
  explicit operator confirmation.
- Local path bootstrap must not write secrets or private key values.

## Command Experience Rules

- Help output must be available without requiring valid workflow hub
  configuration.
- Failure output must name the selected product repository when selection has
  already succeeded.
- Multi-repository output must end with a summary that separates synced,
  clean/read-only, skipped, blocked, and failed repositories.
- Dirty checkout warnings must include the local checkout path.
- Missing-path guidance must name `.ai-dev-workflow.local.yaml`.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `clean` | Clean | The checkout exists and has no uncommitted changes. |
| `dirty` | Dirty | The checkout exists but has uncommitted changes. |
| `missing_path` | Missing path | No usable local checkout path can be resolved. |
| `missing_checkout` | Missing checkout | A path is resolved, but no checkout exists there. |
| `synced` | Synced | The checkout was updated successfully. |
| `skipped` | Skipped | The command intentionally did not act on the repository. |
| `blocked` | Blocked | The command refused to continue because acting would be unsafe. |
| `failed` | Failed | The command attempted inspection or sync and received an error. |

**Valid transitions**:

- `missing_path` -> `clean` after local config points to an existing clean
  checkout.
- `missing_checkout` -> `clean` after the checkout exists locally and has no
  uncommitted changes.
- `clean` -> `synced` when sync completes successfully.
- `dirty` -> `blocked` when sync would overwrite local changes.
- Any inspected repository -> `failed` when remote or local inspection cannot
  complete.

## Operational Visibility

- **Command output**: Every command prints a human-readable summary of selected
  product repositories and outcomes.
- **Exit status**: Commands return success only when all required selected
  repositories complete the requested safe action or read-only inspection.
- **Failure guidance**: Failures include next-step guidance, especially for
  wrong mode, missing local paths, dirty checkouts, and remote inspection
  errors.

## Acceptance Criteria

- [ ] AC1: Each workflow hub product repository command exposes help output
      that explains purpose, required mode, target selection, and safe-failure
      behavior.
- [ ] AC2: Running any command from outside `workflow_hub` mode fails clearly
      before inspecting or mutating product repository checkouts.
- [ ] AC3: Status can be run for one named product repository and reports local
      path, branch, dirty/clean state, and remote-inspection availability.
- [ ] AC4: Status can be run across all configured product repositories and
      reports a per-repository outcome plus a final summary.
- [ ] AC5: Sync can target one named product repository and refuses to overwrite
      a dirty checkout.
- [ ] AC6: Sync can target all configured product repositories and reports
      partial success and partial failure without hiding blocked repositories.
- [ ] AC7: When a local checkout path is missing, the command reports the
      documented default path or the exact `.ai-dev-workflow.local.yaml` entry
      that must be added.
- [ ] AC8: Any bootstrap action that writes a missing local checkout path to
      local config requires explicit confirmation before writing.
- [ ] AC9: Pull-request listing, if implemented, can target one product
      repository or all configured product repositories and is read-only.
- [ ] AC10: Shell validation covers help output, wrong-mode failure, clean
      status, dirty-checkout refusal, missing local path guidance, and
      multi-repository summary output.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Add a product repository sync command. | AC5, AC6 |
| Add a workflow hub status command. | AC3, AC4 |
| Add a product repository pull-request listing command if needed. | AC9 |
| Support selecting one product repository or all configured product repositories where appropriate. | AC3, AC4, AC5, AC6, AC9 |
| Refuse to run outside `workflow_hub` mode. | AC2 |
| Use shared repository-context behavior. | AC2, AC3, AC5, AC7 |
| Report the documented default or exact local config entry when a local path is missing. | AC7 |
| Expose command help. | AC1 |
| Avoid overwriting dirty product repository checkouts. | AC5, AC6 |
| Bootstrap missing local checkout paths into local config only after explicit confirmation. | AC8 |
| Cover success and failure paths with shell validation. | AC10 |

## Out of Scope (MVP)

- Automatically creating or cloning product repository checkouts.
- Force-updating, stashing, deleting, or otherwise rewriting dirty product
  repository checkouts.
- Opening, merging, or modifying product repository pull requests.
- Implementing cross-repository orchestration decisions beyond sync, status, and
  pull-request visibility.
- Defining the repository-context storage format beyond relying on #875.
