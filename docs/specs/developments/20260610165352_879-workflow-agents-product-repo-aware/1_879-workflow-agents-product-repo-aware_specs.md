# Workflow Agents and Command Wrappers Product Repository Awareness - Spec

**Depends on**: 874-workflow-hub-operating-model, 875-shared-local-workflow-config

---

## Overview

Workflow agents and command wrappers need to understand whether they are
working in a single repository, a workflow hub, or a product repository. In
workflow hub mode, agents must not silently edit the hub when implementation
work belongs in a selected product repository, and they must not create hub
planning artifacts in a product repository. This feature defines the expected
agent-facing behavior across Claude, Cursor, and Codex workflow surfaces.

## Brief Objective List

1. Make portfolio orchestrator / run-work flows product-repository aware.
2. Make item orchestrator / run-item-work flows product-repository aware.
3. Make product-manager and tech-lead agents mode-aware for spec and plan work.
4. Make developer agents product-repository aware for implementation work.
5. Make spec, plan, and code reviewers mode-aware.
6. Make smoke-tester agents mode-aware.
7. Make reviewer-loop wrappers mode-aware.
8. Agents state the selected product repository before code mutations in
   `workflow_hub` mode.
9. Spec and plan generation happen in the documented owner repository for each
   mode.
10. Developer branches, commits, and pull requests are created in the selected
    product repository in `workflow_hub` mode.
11. Wrappers stay thin and call shared scripts/helpers where possible.
12. `single_repo` prompts remain valid without requiring a `--repo` flag.

## Use Cases

### Use Case 1: Portfolio orchestrator routes work in single-repository mode

**Actor**: Portfolio orchestrator
**Preconditions**: The repository has no explicit mode declaration or is in
`single_repo` mode.

**Steps**:

1. The operator invokes the portfolio workflow.
2. The orchestrator resolves repository mode.
3. Because the mode is `single_repo`, the orchestrator treats the current
   repository as the owner for specs, plans, implementation branches, commits,
   pull requests, reviews, smoke tests, and cleanup.
4. Existing prompts and wrappers continue without requiring a product
   repository selection.

**Postconditions**: Existing single-repository workflow users can continue
using current commands without new flags or product-repository prompts.

**Information shown**:

- Resolved mode when relevant to the workflow summary.
- Existing single-repository next actions.

**Actions available**:

- Continue single-repository workflow orchestration.
- Add workflow hub configuration later if needed.

**Considerations**:

- Product repository terminology must not become a required decision for
  single-repository users.

### Use Case 2: Item orchestrator states product repository context before code work

**Actor**: Item orchestrator
**Preconditions**: The workflow hub is orchestrating implementation work for a
work item with one selected product repository.

**Steps**:

1. The operator invokes the item workflow from the workflow hub.
2. The orchestrator resolves the selected product repository.
3. Before any code mutation, branch creation, commit, or implementation pull
   request action, the orchestrator states the selected product repository.
4. The orchestrator routes implementation work to that selected product
   repository.
5. If selection is missing or ambiguous, the orchestrator stops before code
   mutation.

**Postconditions**: Code work happens only in the selected product repository,
and operators can see the repository context before mutations occur.

**Information shown**:

- Workflow mode.
- Selected product repository name.
- Product repository local path or remote identity when available.
- Which next action will mutate product repository code.

**Actions available**:

- Continue implementation work in the selected product repository.
- Stop and fix missing product repository selection.

**Considerations**:

- The context statement must happen before mutation, not only after a branch or
  commit has already been created.

### Use Case 3: Product-manager and tech-lead agents create hub-owned planning artifacts

**Actor**: Product-manager or tech-lead agent
**Preconditions**: The workflow is running in any supported repository mode.

**Steps**:

1. The planning agent resolves repository mode and artifact ownership.
2. For `single_repo`, the current repository owns spec and plan artifacts.
3. For `workflow_hub`, the hub owns spec and plan artifacts unless workflow
   documentation explicitly says otherwise.
4. For `product_repo`, the agent either follows product-repo ownership guidance
   or reports that planning should happen in the workflow hub when configured.
5. The agent opens spec and plan pull requests in the documented owner
   repository.

**Postconditions**: Specs and plans are created in the correct repository for
the active mode.

**Information shown**:

- Resolved mode.
- Artifact owner for spec or plan work.
- Target repository for the spec or plan pull request.

**Actions available**:

- Continue planning in the documented owner repository.
- Stop when ownership is ambiguous.

**Considerations**:

- Planning agents must not create duplicate specs or plans in product
  repositories when the workflow hub owns planning artifacts.

### Use Case 4: Developer agent creates product repository implementation PRs

**Actor**: Developer agent
**Preconditions**: The workflow hub has an approved plan for a work item whose
implementation belongs in one selected product repository.

**Steps**:

1. The developer agent receives the work item and selected product repository
   context.
2. The agent states the selected product repository before creating or changing
   files.
3. The agent creates the implementation branch in the selected product
   repository.
4. The agent commits implementation changes in the selected product repository.
5. The agent opens the implementation pull request in the selected product
   repository.
6. The workflow hub remains the owner of tracker, spec, and plan state.

**Postconditions**: Implementation code changes and implementation PRs are in
the selected product repository, while hub-owned artifacts stay in the hub.

**Information shown**:

- Selected product repository.
- Implementation branch target.
- Implementation pull request target.
- Hub-owned tracker/spec/plan context.

**Actions available**:

- Continue implementation when product repository context is clear.
- Stop before mutation when context is missing or ambiguous.

**Considerations**:

- Branch, commit, and PR operations are safety-sensitive because a wrong
  repository target can put code changes in the hub.

### Use Case 5: Review and smoke-test agents use the correct repository owner

**Actor**: Spec reviewer, plan reviewer, code reviewer, reviewer-loop wrapper,
or smoke-tester agent
**Preconditions**: A spec, plan, code PR, or smoke-test runbook exists for a
workflow item.

**Steps**:

1. The review or smoke-test agent resolves the artifact type and repository
   owner.
2. For specs and plans, the agent reviews hub-owned artifacts where documented.
3. For implementation code PRs in workflow hub mode, the agent reviews or tests
   the selected product repository PR.
4. The agent reports which repository it reviewed or tested.

**Postconditions**: Review and test feedback applies to the correct artifact
owner.

**Information shown**:

- Artifact type.
- Repository owner for the artifact.
- Pull request or runbook under review.
- Any missing repository context.

**Actions available**:

- Continue review or smoke test in the correct repository.
- Stop when the artifact owner cannot be resolved.

**Considerations**:

- Reviewer-loop wrappers should remain thin and rely on shared context helpers
  rather than duplicating selection logic.

## Business Rules

- Missing mode or explicit `single_repo` mode preserves current prompts and
  command wrapper usage without requiring `--repo`.
- In `workflow_hub` mode, agents must state the selected product repository
  before code mutation, branch creation, commit, or implementation PR creation.
- In `workflow_hub` mode, implementation branches, commits, and implementation
  pull requests belong in the selected product repository.
- In `workflow_hub` mode, tracker, spec, and plan artifacts remain hub-owned
  unless documentation explicitly says otherwise.
- Product-manager and tech-lead agents must create spec and plan artifacts in
  the documented owner repository for the active mode.
- Reviewers and smoke testers must report which repository and artifact they
  evaluated.
- Wrappers across Claude, Cursor, and Codex must stay thin and call shared
  scripts or helpers where possible.
- Missing or ambiguous product repository context must stop mutation-oriented
  agents before they mutate files or create branches.
- Product repository context must come from shared repository-context behavior,
  not from each wrapper inventing its own selection rules.

## Command Experience Rules

- Orchestrator summaries in workflow hub mode must include the selected product
  repository for implementation work.
- Developer-agent handoff text must include the selected product repository
  before any mutation instruction.
- Review and smoke-test summaries must identify the repository whose artifact
  was reviewed or tested.
- Single-repository prompts remain valid and do not require a product
  repository flag.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `single_repo` | Single repository | Current repository owns planning and implementation workflow. |
| `workflow_hub` | Workflow hub | Hub owns coordination while selected product repositories may own implementation work. |
| `product_repo` | Product repository | Product repository participates in workflow hub routed work. |
| `context_declared` | Context declared | Agent has stated the selected product repository before mutation. |
| `context_missing` | Context missing | Agent needs a product repository target but none is available. |
| `context_ambiguous` | Context ambiguous | More than one product repository could apply and none is selected. |

**Valid transitions**:

- `context_missing` -> `context_declared` after exactly one product repository
  is selected.
- `context_ambiguous` -> `context_declared` after ambiguity is resolved.
- `single_repo` remains valid without product repository selection.

## Operational Visibility

- **Agent summaries**: Orchestrators, developers, reviewers, and smoke testers
  state repository mode and repository owner when it affects the action.
- **Handoff text**: Item orchestration handoffs include selected product
  repository context before code mutation.
- **Failure output**: Missing or ambiguous product repository context is visible
  before any mutation occurs.

## Acceptance Criteria

- [ ] AC1: Portfolio orchestrator / run-work flows preserve current
      `single_repo` behavior and do not require a product repository flag when
      no workflow hub mode is configured.
- [ ] AC2: Item orchestrator / run-item-work flows in `workflow_hub` mode state
      the selected product repository before any code mutation, branch,
      commit, or implementation PR operation.
- [ ] AC3: Product-manager and tech-lead agents create specs and plans in the
      documented owner repository for `single_repo`, `workflow_hub`, and
      `product_repo` modes.
- [ ] AC4: Developer agents create implementation branches, commits, and pull
      requests in the selected product repository in `workflow_hub` mode.
- [ ] AC5: Spec, plan, and code reviewers resolve and report the repository
      owner for the artifact under review.
- [ ] AC6: Smoke-tester agents resolve and report the repository owner for the
      runbook or implementation artifact under test.
- [ ] AC7: Reviewer-loop wrappers use shared repository-context behavior and
      report the selected product repository for product implementation PRs.
- [ ] AC8: Claude, Cursor, and Codex workflow wrappers remain thin and do not
      duplicate product repository selection rules.
- [ ] AC9: Missing or ambiguous product repository context stops
      mutation-oriented agents before file mutation, branch creation, commit,
      or implementation PR creation.
- [ ] AC10: `single_repo` prompts remain valid without requiring `--repo` or a
      product repository selection.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Make portfolio orchestrator / run-work flows product-repository aware. | AC1 |
| Make item orchestrator / run-item-work flows product-repository aware. | AC2, AC9 |
| Make product-manager and tech-lead agents mode-aware for spec and plan work. | AC3 |
| Make developer agents product-repository aware for implementation work. | AC4, AC9 |
| Make spec, plan, and code reviewers mode-aware. | AC5 |
| Make smoke-tester agents mode-aware. | AC6 |
| Make reviewer-loop wrappers mode-aware. | AC7 |
| Agents state selected product repository before code mutations in `workflow_hub` mode. | AC2, AC4, AC9 |
| Spec and plan generation happen in the documented owner repository for each mode. | AC3 |
| Developer branches, commits, and pull requests are created in the selected product repository in `workflow_hub` mode. | AC4 |
| Wrappers stay thin and call shared scripts/helpers where possible. | AC7, AC8 |
| `single_repo` prompts remain valid without requiring a `--repo` flag. | AC1, AC10 |

## Out of Scope (MVP)

- Implementing repository-context helper behavior itself; that is covered by
  #875.
- Implementing orchestration script routing itself; that is covered by #878.
- Changing the canonical workflow stages or tracker statuses.
- Supporting implementation work that mutates multiple product repositories in
  one developer-agent run.
- Rewriting wrappers into thick, tool-specific workflows.
