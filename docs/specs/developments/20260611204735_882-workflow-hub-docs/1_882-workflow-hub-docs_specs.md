# Workflow Hub Setup And Operations Docs - Spec

**Depends on**: 874-workflow-hub-operating-model, 875-shared-local-workflow-config, 876-workflow-hub-template-skeletons, 877-workflow-hub-product-repo-sync-status-scripts, 878-workflow-orchestration-product-repo-aware, 879-workflow-agents-product-repo-aware, 880-cross-repo-pr-auth-support, 881-sync-template-workflow-hub-scopes, 883-workflow-hub-smoke-fixtures

---

## Overview

Workflow-hub mode now has operating-model docs, configuration helpers,
product-repository commands, cross-repository PR authentication, smoke
fixtures, and role-aware sync-template scopes. Adopters still need one coherent
documentation path that explains how to set up a hub, inject the product-repo
surface, operate cross-repository PR work, and troubleshoot common failures.
This feature adds adoption-oriented workflow-hub docs that assemble the
existing primitives into concrete setup and operations guides.

## Brief Objective List

1. Document the end-to-end setup path for a workflow hub and product
   repositories.
2. Document where each command runs: hub checkout, product checkout, or
   downstream product repository.
3. Explain versioned `.ai-dev-workflow.yaml` versus local-only
   `.ai-dev-workflow.local.yaml`.
4. Document product-repo injection using the role-aware sync-template scope
   behavior.
5. Document the cross-repository PR flow from hub item selection through product
   PR readiness.
6. Add troubleshooting for missing product checkouts, dirty product repos,
   missing GitHub App credentials, failed CI, and reviewer-loop failures.
7. Link back to the relevant workflow protocols and integration guides.
8. Use a non-secret Faind-like multi-repository example with placeholder
   repository names, fake IDs, and no confidential project names or secrets.
9. Keep the docs aligned with existing repository structure under
   `docs/workflow/development-workflow/`.

## Use Cases

### Use Case 1: Maintainer initializes a workflow hub

**Actor**: Template adopter or workflow maintainer
**Trigger**: The maintainer is converting a repository into a workflow hub.
**Preconditions**: The maintainer has a repository that will coordinate work
for one or more product repositories.

**Steps**:

1. The maintainer reads the workflow-hub setup guide.
2. The guide shows the committed `.ai-dev-workflow.yaml` fields required for
   `mode: workflow_hub`.
3. The guide shows the local `.ai-dev-workflow.local.yaml` fields for checkout
   paths and private credential references.
4. The maintainer runs validation and status commands from the hub checkout.
5. The guide links to the operating model and GitHub App authentication guide
   for deeper details.

**Postconditions**: The maintainer can configure and validate a workflow hub
without storing secrets in versioned files.

**Information shown**:

- Hub repository mode and product repository list.
- Versioned versus local-only configuration examples.
- Commands and expected run locations.
- Links to repository-mode and authentication details.

**Actions available**:

- Validate shared and local workflow config.
- Inspect product checkout status.
- Bootstrap or repair local product checkout paths.

**Considerations**:

- The guide must not require live private repositories for its default example.
- The guide must not include real private repository names, tokens, key paths,
  or secret-manager account details.

### Use Case 2: Product maintainer injects workflow support

**Actor**: Product repository maintainer
**Trigger**: The maintainer is preparing a product repository to receive
hub-routed workflow support.
**Preconditions**: A hub exists and the product repository should receive the
minimal workflow integration surface.

**Steps**:

1. The maintainer reads the product-repo injection guide.
2. The guide explains that product repositories use role-aware sync-template
   selection.
3. The guide shows how product-repo mode selects `shared` and
   `product_repo_injection` entries while skipping `hub_only` entries.
4. The maintainer previews the selected and skipped manifest entries before
   applying changes.
5. The guide identifies which files are versioned and which local files remain
   private or machine-specific.

**Postconditions**: The product repository receives only the documented
injection-safe workflow surface.

**Information shown**:

- Product repository mode configuration.
- Role-aware sync-template dry-run command.
- Selected and skipped scope categories.
- Files that must remain local-only.

**Actions available**:

- Preview product-repo sync output.
- Apply approved injection files.
- Validate product-repo mode configuration.

**Considerations**:

- Product repositories must not receive hub-owned tracker state, specs,
  implementation plans, workflow protocols, or hub orchestration scripts.

### Use Case 3: Hub operator routes a cross-repository PR

**Actor**: Hub operator or AI work orchestrator
**Trigger**: A hub-managed work item is ready for product repository
implementation.
**Preconditions**: A hub-managed work item identifies one product repository
target and the product checkout is available locally.

**Steps**:

1. The operator reads the cross-repo PR flow guide.
2. The guide shows how to inspect product repository status from the hub.
3. The guide shows where implementation branches are created.
4. The guide shows how product PR creation, reviewer loop, CI loop, readiness
   labels, merge, and cleanup are targeted to the product repository.
5. The guide explains that tracker/spec/plan status remains hub-owned.

**Postconditions**: The operator can follow the cross-repository PR flow without
confusing hub-owned state with product-owned implementation artifacts.

**Information shown**:

- Command sequence with run locations.
- Ownership table for tracker, spec, plan, implementation branch, PR, CI, and
  cleanup.
- Links to orchestration, reviewer-loop, CI, and batch-merge protocols.

**Actions available**:

- Inspect status across product repositories.
- Sync clean product checkouts.
- Open or dry-run a product PR.
- Run reviewer and CI loops against the correct repository.
- Clean up after merge.

**Considerations**:

- Commands that mutate product repositories must fail before mutation when the
  product target is missing or ambiguous.

### Use Case 4: Operator troubleshoots common workflow-hub failures

**Actor**: Hub operator
**Trigger**: A workflow-hub setup, injection, PR, reviewer, or CI command fails.
**Preconditions**: A setup, injection, PR, reviewer, or CI step failed.

**Steps**:

1. The operator finds a troubleshooting section for the observed failure.
2. The guide names the likely cause and the command to confirm it.
3. The guide gives the safe repair path and states where to run it.
4. The guide links to the relevant protocol or integration guide.

**Postconditions**: The operator can recover or identify a real blocker without
using unsafe fallback behavior.

**Information shown**:

- Missing product checkout diagnosis.
- Dirty product repository diagnosis.
- Missing GitHub App credential diagnosis.
- Failed CI diagnosis.
- Reviewer-loop failure diagnosis.

**Actions available**:

- Validate local config.
- Sync clean product checkouts.
- Resolve local credential references.
- Re-run reviewer and CI loops.
- Stop for human decision when a product checkout is dirty or credentials are
  missing.

**Considerations**:

- Troubleshooting must not recommend force-push, reset-hard, ambient-token
  fallback, or secret material in versioned files.

## Business Rules

- Docs must fit the existing workflow docs tree under
  `docs/workflow/development-workflow/`.
- Docs must include concrete commands and state the checkout where each command
  is run.
- Docs must distinguish versioned `.ai-dev-workflow.yaml` from local-only
  `.ai-dev-workflow.local.yaml`.
- Docs must describe role-aware sync-template product-repo injection after #881.
- Docs must explain that hub-owned tracker/spec/plan state remains in the hub,
  while product implementation branches and product PRs belong to the selected
  product repository.
- Docs must link back to relevant workflow protocols and integration guides.
- Docs must include troubleshooting for missing product checkout, dirty product
  repo, missing app credentials, failed CI, and reviewer-loop failures.
- Examples must use placeholder Faind-like repository names and fake IDs only.
- Docs must not include private repository names, real app IDs, real
  installation IDs, real secret refs, real local paths, tokens, or private key
  material.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `workflow_hub` | Workflow hub | Repository mode for the hub that owns portfolio state and workflow artifacts. |
| `product_repo` | Product repository | Repository mode for a product repository that receives hub-routed implementation work. |
| `single_repo` | Single repository | Compatibility mode where one repository owns all workflow artifacts. |
| `shared` | Shared sync scope | Manifest entries that apply across supported repository roles. |
| `hub_only` | Hub-only sync scope | Manifest entries selected for workflow hubs and skipped for product repositories. |
| `product_repo_injection` | Product-repo injection sync scope | Manifest entries selected for product repositories and skipped for hub-only sync. |

**Valid transitions**:

- A hub setup flow starts with a repository in missing or `single_repo` mode and
  documents the change to `workflow_hub`.
- A product-repo injection flow starts from a product repository and documents
  the change to `product_repo`.
- A cross-repo PR flow starts from hub-owned planning state and transitions
  implementation work to the selected product repository.
- Troubleshooting can return the operator to setup, injection, or PR flow after
  the failure condition is resolved.

## Operational Visibility

- **Setup docs**: Show which config fields are versioned, local-only, optional,
  or required.
- **Injection docs**: Show selected and skipped sync-template scopes for
  `product_repo`.
- **Operations docs**: Show command sequences and repository ownership for each
  stage.
- **Troubleshooting docs**: Show failure symptoms, likely causes, safe repair
  commands, and escalation conditions.
- **Examples**: Use a placeholder topology such as `faind-workflow-hub`,
  `faind-mobile-app`, and `faind-admin-portal` with fake GitHub App IDs and no
  secrets.

## Acceptance Criteria

- [ ] AC1: Documentation includes a workflow-hub setup path with concrete
      commands and the checkout where each command runs.
- [ ] AC2: Documentation explains versioned `.ai-dev-workflow.yaml` versus
      local-only `.ai-dev-workflow.local.yaml`.
- [ ] AC3: Documentation includes a product-repo injection path that describes
      role-aware sync-template selection for `product_repo`.
- [ ] AC4: Documentation includes a cross-repository PR flow from hub item
      routing through reviewer loop, CI, readiness labels, merge, and cleanup.
- [ ] AC5: Documentation explains which artifacts are hub-owned and which are
      product-repo-owned during cross-repo implementation work.
- [ ] AC6: Documentation includes troubleshooting for missing product checkout,
      dirty product repo, missing app credentials, failed CI, and reviewer-loop
      failures.
- [ ] AC7: Documentation links to relevant workflow protocols and integration
      guides.
- [ ] AC8: Examples use a Faind-like multi-repository setup without
      confidential project names, real app IDs, real installation IDs, tokens,
      private key paths, or secret values.
- [ ] AC9: Documentation avoids unsafe recovery instructions such as
      `git reset --hard`, force-push, ambient credential fallback, or committing
      secret material.
- [ ] AC10: Docs are discoverable from the workflow-hub operating model or the
      development-workflow README.

## Objective Coverage Matrix

| Objective | Covered by |
| --- | --- |
| 1. Document the end-to-end setup path for a workflow hub and product repositories. | AC1, AC2, AC10 |
| 2. Document where each command runs. | AC1, AC4 |
| 3. Explain versioned `.ai-dev-workflow.yaml` versus local-only `.ai-dev-workflow.local.yaml`. | AC2 |
| 4. Document product-repo injection using role-aware sync-template scopes. | AC3 |
| 5. Document the cross-repository PR flow from hub item selection through product PR readiness. | AC4, AC5 |
| 6. Add troubleshooting for common workflow-hub failures. | AC6, AC9 |
| 7. Link back to relevant workflow protocols and integration guides. | AC7 |
| 8. Use a non-secret Faind-like multi-repository example. | AC8 |
| 9. Keep docs aligned with the existing workflow docs tree. | AC10 |

## Out of Scope (MVP)

- Building a new executable setup wizard.
- Creating live product repositories or GitHub Apps.
- Automatically injecting files into downstream repositories during this docs
  change.
- Changing workflow-hub routing behavior, reviewer-loop behavior, or
  sync-template implementation behavior.
- Documenting a real private customer topology or any real secret-manager
  account.
