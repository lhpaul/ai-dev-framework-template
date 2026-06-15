# Workflow Orchestration Product Repository Awareness - Spec

**Depends on**: 875-shared-local-workflow-config

---

## Overview

Workflow hub mode changes where implementation work happens. The workflow hub
continues to own tracker, spec, plan, and portfolio coordination artifacts, but
implementation branches, implementation pull requests, reviewer checks, CI
checks, and cleanup may belong to a selected product repository. This feature
defines how existing orchestration commands should recognize a selected product
repository, preserve current single-repository behavior, and fail clearly when
an implementation action needs a product target but none is available.

## Brief Objective List

1. Make workflow discovery product-repository aware.
2. Make next-action planning product-repository aware.
3. Make batch planning product-repository aware.
4. Make automated reviewer loops target the product repository for
   implementation pull requests.
5. Make CI loops target the product repository for implementation pull
   requests.
6. Make post-merge cleanup operate on the correct repository context.
7. Update project status/type helper paths where they infer repository context.
8. Accept or infer a selected product repository in `workflow_hub` mode.
9. Preserve current behavior in `single_repo` mode.
10. Mention missing repository selection when selection is required.
11. Keep tracker, spec, and plan operations targeting the workflow hub where
    documented.
12. Cover at least one multi-product selection path and one single-repository
    regression path with tests.

## Use Cases

### Use Case 1: Orchestrator discovers workflow state in single-repository mode

**Actor**: Workflow orchestrator
**Preconditions**: The repository is operating in the existing
`single_repo` mode or has no explicit mode declaration.

**Steps**:

1. The orchestrator runs workflow discovery.
2. The workflow resolves repository context.
3. Because the mode is `single_repo`, the current repository remains the
   workflow and implementation repository.
4. Discovery reports the same categories of branches, worktrees, specs, plans,
   pull requests, and tracker status it reports today.

**Postconditions**: Existing adopters see no product-repository selection
requirement and no changed single-repository behavior.

**Information shown**:

- Resolved mode.
- Current repository as the implementation context.
- Existing workflow state summary.

**Actions available**:

- Continue normal single-repository orchestration.
- Add workflow hub configuration later without changing this mode.

**Considerations**:

- Missing mode must not force adopters to provide a product repository target.

### Use Case 2: Orchestrator plans implementation work for a selected product repository

**Actor**: Workflow orchestrator
**Preconditions**: The current repository is a workflow hub and a work item is
ready for implementation in a product repository.

**Steps**:

1. The orchestrator reads the work item and repository-context configuration.
2. The orchestrator identifies the selected product repository for
   implementation work.
3. Discovery and next-action planning inspect implementation branches and open
   implementation pull requests in the selected product repository.
4. Tracker, spec, and plan state continue to be read from the workflow hub.
5. The orchestrator reports which repository owns each next action.

**Postconditions**: Implementation work is routed to the product repository
without moving hub-owned planning artifacts out of the hub.

**Information shown**:

- Selected product repository name.
- Product repository local path or remote identity.
- Whether the next action is hub-owned or product-repository-owned.
- Any missing or ambiguous product repository selection.

**Actions available**:

- Continue with product repository implementation work when selection is clear.
- Stop and fix repository selection when it is missing or ambiguous.

**Considerations**:

- The same work item can have hub-owned spec/plan state and product-owned code
  state. Output must not collapse those into one repository by accident.

### Use Case 3: Reviewer and CI loops inspect an implementation pull request in a product repository

**Actor**: Workflow orchestrator
**Preconditions**: The workflow hub is managing an implementation pull request
that lives in a selected product repository.

**Steps**:

1. The orchestrator starts the reviewer loop or CI loop for the implementation
   pull request.
2. The loop resolves the pull request repository context.
3. The loop reads comments, review summaries, labels, checks, and mergeability
   from the product repository pull request.
4. The loop reports results back to the workflow run with the product
   repository clearly named.

**Postconditions**: Reviewer and CI readiness reflects the product repository
pull request, not a pull request in the hub.

**Information shown**:

- Product repository name and remote identity.
- Pull request number and branch.
- Reviewer-loop result.
- CI result.
- Any repository-context error.

**Actions available**:

- Re-run review or CI loops for the same product repository pull request.
- Stop and fix repository context when the target is missing.

**Considerations**:

- Spec and plan pull requests still belong to the workflow hub unless a later
  workflow document explicitly changes that ownership.

### Use Case 4: Post-merge cleanup runs in the correct repository context

**Actor**: Workflow orchestrator
**Preconditions**: A product repository implementation pull request has merged,
or a hub-owned spec/plan pull request has merged.

**Steps**:

1. The orchestrator determines whether the merged work was hub-owned or
   product-repository-owned.
2. For product implementation work, cleanup updates the product repository
   branch/worktree state.
3. For hub-owned spec or plan work, cleanup updates the workflow hub branch
   state.
4. Tracker state is updated from the workflow hub context according to the
   documented workflow state transition.

**Postconditions**: Cleanup does not delete or switch branches in the wrong
repository, and tracker state remains hub-owned.

**Information shown**:

- Repository where cleanup ran.
- Branch or worktree cleaned.
- Tracker update target.
- Any skipped cleanup because repository context was missing.

**Actions available**:

- Complete cleanup when context is clear.
- Stop before cleanup when context is missing or ambiguous.

**Considerations**:

- Cleanup is safety-sensitive and must fail closed when repository ownership is
  ambiguous.

## Business Rules

- Missing mode or explicit `single_repo` mode preserves current
  single-repository orchestration behavior.
- In `workflow_hub` mode, implementation actions that mutate code, inspect
  implementation pull requests, poll implementation CI, or clean
  implementation branches require a selected product repository.
- In `workflow_hub` mode, tracker, spec, and plan operations remain hub-owned
  unless a workflow document explicitly says otherwise.
- Missing product repository selection must be reported before a script
  performs product-repository implementation actions.
- Ambiguous product repository selection must fail clearly instead of guessing.
- Every user-facing summary for cross-repository work must identify whether an
  action is hub-owned or product-repository-owned.
- Product repository context must come from the shared repository-context
  behavior defined by #875.
- Multi-product workflows must allow a work item to select one product
  repository for implementation work.
- Existing single-repository users must not be required to pass new product
  repository flags or config.

## Command Experience Rules

- Product-repository-aware commands must expose the selected product repository
  in their output when operating in `workflow_hub` mode.
- Errors caused by missing selection must mention that a product repository
  target is required.
- Single-repository output should stay familiar and should not introduce
  product repository terminology as a required operator choice.
- Cross-repository summaries should separate hub-owned state from
  product-repository-owned state.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `hub_owned` | Hub owned | The action or artifact belongs to the workflow hub repository. |
| `product_repo_owned` | Product repository owned | The action or artifact belongs to a selected product repository. |
| `selection_missing` | Selection missing | A product repository target is required but unavailable. |
| `selection_ambiguous` | Selection ambiguous | More than one product repository could apply and none was selected. |
| `single_repo_context` | Single repository context | The current repository owns workflow and implementation artifacts. |

**Valid transitions**:

- `selection_missing` -> `product_repo_owned` after the work item or command
  identifies exactly one product repository.
- `selection_ambiguous` -> `product_repo_owned` after the operator or work item
  resolves the ambiguity.
- `single_repo_context` remains valid when no workflow hub mode is configured.

## Operational Visibility

- **Discovery output**: Reports the resolved mode and selected product
  repository for implementation work when applicable.
- **Next-action output**: Names the repository that owns the recommended next
  action.
- **Reviewer and CI output**: Names the product repository when inspecting a
  product implementation pull request.
- **Cleanup output**: Names the repository where branch/worktree cleanup is
  being performed and separately reports tracker updates in the hub.

## Acceptance Criteria

- [ ] AC1: In missing-mode or `single_repo` mode, workflow discovery,
      next-action planning, batch planning, reviewer loop, CI loop, and cleanup
      retain current single-repository behavior without requiring product repo
      selection.
- [ ] AC2: In `workflow_hub` mode, implementation next-action planning can
      resolve one selected product repository and reports that repository in
      the action summary.
- [ ] AC3: In `workflow_hub` mode, implementation next-action planning fails
      clearly when a product repository selection is required but missing or
      ambiguous.
- [ ] AC4: Discovery and batch planning distinguish hub-owned tracker/spec/plan
      state from product-repository-owned implementation branch and pull
      request state.
- [ ] AC5: Reviewer-loop checks for implementation pull requests target the
      selected product repository and report that repository in their output.
- [ ] AC6: CI-loop checks for implementation pull requests target the selected
      product repository and report that repository in their output.
- [ ] AC7: Post-merge cleanup performs branch or worktree cleanup in the
      repository that owns the merged work and keeps tracker updates hub-owned.
- [ ] AC8: Project status/type helper paths that infer repository context use
      the workflow hub for tracker operations and do not accidentally target a
      product repository tracker unless explicitly configured.
- [ ] AC9: Error messages for missing or ambiguous product repository selection
      name the missing selection and avoid performing product-repository
      mutations.
- [ ] AC10: Tests cover at least one multi-product selection path and one
      single-repository regression path.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Make workflow discovery product-repository aware. | AC1, AC4 |
| Make next-action planning product-repository aware. | AC1, AC2, AC3 |
| Make batch planning product-repository aware. | AC1, AC4 |
| Make automated reviewer loops target product repositories for implementation pull requests. | AC5 |
| Make CI loops target product repositories for implementation pull requests. | AC6 |
| Make post-merge cleanup operate on the correct repository context. | AC7 |
| Update project status/type helper paths where they infer repository context. | AC8 |
| Accept or infer a selected product repository in `workflow_hub` mode. | AC2, AC3 |
| Preserve current behavior in `single_repo` mode. | AC1 |
| Mention missing repository selection when selection is required. | AC3, AC9 |
| Keep tracker, spec, and plan operations targeting the workflow hub where documented. | AC4, AC7, AC8 |
| Cover at least one multi-product selection path and one single-repository regression path with tests. | AC10 |

## Out of Scope (MVP)

- Changing where spec and plan pull requests are opened.
- Changing tracker ownership or adding new tracker fields.
- Implementing product repository sync/status commands; those are covered by
  #877.
- Implementing workflow agent prompt changes; those are covered by a separate
  workflow-hub item.
- Supporting implementation work that spans multiple product repositories in
  one work item.
- Automatically creating product repository local checkouts.
