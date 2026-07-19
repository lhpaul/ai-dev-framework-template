# Prevent Unsanctioned Nested Agent PRs - Spec

---

## Overview

Parallel workflow runs need to preserve one visible execution path per assigned
item. When an item runner, stage agent, or nested agent is about to create a
worktree, branch, commit, push, or PR, the parent orchestration context must
remain aware of that action and the action must use the run's explicit base
branch.

This feature prevents silent duplicate forks of in-flight work. It gives
operators a clear stop or warning when a spawned agent would create independent
work for an issue that already has an assigned worktree, branch, or open PR, or
when the spawned agent does not have enough base-branch context to open the PR
against the intended integration branch.

## Brief Objective List

Derived from issue #1200:

1. Require spawned or nested agents to check whether an issue already has an
   assigned worktree, branch, or open PR before creating another one.
2. Block or report duplicate nested work instead of allowing it to proceed
   silently.
3. Require explicit base-branch context in spawned-agent handoffs before branch
   or PR creation.
4. Prevent spawned agents from falling back to the GitHub repository default
   branch when the workflow base is different.
5. Require parent-orchestrator visibility before any nested agent creates extra
   worktrees, branches, commits, pushes, or PRs.
6. Periodically enumerate in-scope worktrees and open PRs during orchestration
   and warn or stop when unexpected forks appear.
7. Preserve the canonical item runner as the source of truth for the assigned
   issue's execution path.

## Use Cases

### Use Case 1: Nested agent receives work for an issue already in progress

**Actor**: Spawned or nested workflow agent.
**Preconditions**: A parent orchestrator has assigned one item to an item runner,
and an issue-scoped worktree, branch, or open PR already exists for that item.

**Steps**:

1. The nested agent receives instructions that could lead to creating a
   worktree, branch, commit, push, or PR for the issue.
2. Before creating new workflow artifacts, the nested agent checks the current
   issue-scoped worktrees, local branches, remote branches, and open PRs.
3. The nested agent detects that another execution path already exists for the
   issue.
4. The nested agent stops before creating duplicate work and reports the
   detected artifact to the parent orchestration context.

**Postconditions**: The nested agent does not create a duplicate branch, push, or
PR for the issue. The parent orchestrator can decide whether to resume the
existing path, close a duplicate, or ask the operator for direction.

**Information shown**:

- Issue number and assigned branch or slug.
- Existing worktree path, branch name, or PR number that caused the stop.
- Whether the discovered artifact is in scope for the current item.
- Required next action for the parent orchestrator or operator.

**Actions available**:

- Resume the existing in-scope branch or PR.
- Stop and ask the operator to choose between competing paths.
- Record an out-of-scope duplicate warning and skip the nested action.

**Considerations**:

- The duplicate check must happen before artifact creation, not after a PR has
  already appeared on GitHub.
- The presence of an assigned worktree or branch is enough to stop silent
  duplicate creation, even if no PR exists yet.

### Use Case 2: Spawned agent lacks explicit base-branch context

**Actor**: Spawned or nested workflow agent.
**Preconditions**: A nested agent is asked to open a branch or PR, but its
handoff does not include the intended workflow base branch.

**Steps**:

1. The nested agent prepares to create a branch or open a PR.
2. The nested agent verifies that the handoff includes the intended base branch
   for the current workflow stage.
3. The base branch is missing, ambiguous, or inconsistent with the parent
   orchestration context.
4. The nested agent refuses to create the branch or PR and reports the missing
   base context to the parent orchestrator.

**Postconditions**: No PR is opened against the repository default branch merely
because the nested agent lacked the workflow base branch.

**Information shown**:

- The issue and stage that needed base-branch context.
- The expected base branch when known from the parent run.
- The observed missing or conflicting base-branch context.
- The human or parent action required to unblock the agent.

**Actions available**:

- Parent orchestrator re-dispatches with explicit base-branch context.
- Operator supplies or corrects the base branch.
- Nested agent stops without mutation when the base cannot be resolved.

**Considerations**:

- A repository default branch is not a sufficient fallback for workflow PRs.
- The same rule applies to spec, plan, implementation, fix, refactor, and
  hotfix paths, with their existing stage-specific base-branch expectations.

### Use Case 3: Parent orchestrator detects unexpected forks during a run

**Actor**: Parent item runner or portfolio orchestrator.
**Preconditions**: A single-item or parallel batch run is active, and the parent
orchestrator owns the approved issue scope and base branch.

**Steps**:

1. The orchestrator reaches a checkpoint before or after a stage-agent handoff,
   push, PR creation, reviewer loop, or readiness update.
2. The orchestrator enumerates active worktrees and open PRs related to the
   approved item scope.
3. The orchestrator finds an unexpected worktree, branch, or PR that was not
   created by the approved execution path.
4. The orchestrator warns or stops before continuing with conflicting state.

**Postconditions**: The operator or parent orchestrator is notified while the
duplicate fork is still actionable, rather than discovering it through an
external GitHub notification.

**Information shown**:

- Approved item scope for the run.
- Expected worktree, branch, and PR for each in-scope item.
- Unexpected artifact identifier, owner path, head branch, PR base, and current
  state where available.
- Whether the artifact targets the approved base branch.

**Actions available**:

- Continue when no unexpected forks are found.
- Stop and ask the operator to resolve competing work.
- Close or ignore an out-of-scope duplicate only when the parent workflow has
  explicit authority to do so.

**Considerations**:

- Warnings must be visible in the parent run summary and not only in a nested
  agent's private output.
- The audit should stay scoped to the approved batch or item list and must not
  opportunistically advance unrelated work.

### Use Case 4: Operator reviews a stopped duplicate-fork attempt

**Actor**: Workflow operator.
**Preconditions**: A nested agent or orchestrator has stopped because it found a
duplicate artifact, missing base branch, or unexpected fork.

**Steps**:

1. The operator reads the stop message.
2. The operator sees which issue, branch, worktree, PR, and base branch caused
   the stop.
3. The operator decides whether to resume the canonical path, close a duplicate,
   re-dispatch with corrected base context, or split the work deliberately.

**Postconditions**: The workflow continues only after the duplicate or missing
context has been made explicit.

**Information shown**:

- Named stop reason in operator language.
- Affected issue and artifact identifiers.
- Safe next actions.
- Confirmation requirement for any deliberate duplicate or split path.

**Actions available**:

- Confirm that the existing branch or PR is canonical.
- Re-dispatch the nested agent with explicit base context.
- Close or abandon the duplicate work.
- Approve an intentional split path with explicit scope and base branch.

**Considerations**:

- The stop should be actionable without requiring the operator to reconstruct
  the timeline from GitHub notifications.
- Deliberate split work must be visible to the parent orchestration context.

## Business Rules

- A nested or spawned agent must not create a worktree, branch, commit, push, or
  PR for an issue until it has checked for existing issue-scoped worktrees,
  branches, and open PRs.
- When an existing issue-scoped artifact is found, the nested agent must stop or
  report to the parent orchestrator before creating duplicate work.
- Parent-orchestrator handoffs to nested agents must include the intended base
  branch before any branch or PR creation can occur.
- A nested agent must not use the GitHub repository default branch as an
  implicit workflow PR base when the handoff lacks base-branch context.
- PR creation must be blocked when the target base branch is missing,
  ambiguous, or inconsistent with the parent run's approved base.
- Parent orchestrators must have visibility into nested-agent attempts to create
  additional worktrees, branches, commits, pushes, or PRs.
- Parallel batch runs must preserve the explicit in-scope item list and must not
  allow nested agents to create artifacts for out-of-scope items.
- Unexpected forks found during orchestration must be surfaced in parent-visible
  output with enough artifact detail for a human or parent runner to act.
- The canonical item runner remains responsible for the issue's terminal state,
  tracker updates, PR readiness labels, and final run summary.
- Any deliberate split into multiple execution paths for the same issue requires
  explicit parent-orchestrator or human approval and explicit base-branch
  context for each path.

## Operational Visibility

- **Nested handoff visibility**: Parent run output shows whether a nested agent
  received item scope, worktree path, branch, PR target, and base branch before
  mutation-oriented work.
- **Duplicate detection visibility**: Stops and warnings identify the existing
  worktree, branch, or PR that caused duplicate prevention.
- **Base-branch visibility**: Branch and PR creation attempts show the intended
  base branch and whether it came from the parent run, a direct operator value,
  or an unresolved context.
- **Unexpected-fork audit**: The parent orchestrator can list unexpected
  worktrees and open PRs related to the approved item scope at key checkpoints.
- **Run summary visibility**: Terminal summaries include any duplicate-fork
  warnings, skipped out-of-scope artifacts, blocked nested-agent attempts, and
  required human actions.

## Acceptance Criteria

- [ ] **AC1**: A nested or spawned agent checks for existing issue-scoped worktrees,
      local branches, remote branches, and open PRs before creating a new
      worktree, branch, commit, push, or PR.
- [ ] **AC2**: When an existing issue-scoped artifact is found, the nested agent stops or
      reports to the parent orchestrator before creating duplicate work.
- [ ] **AC3**: Nested-agent handoffs include the intended base branch for any action that
      can create a branch or PR.
- [ ] **AC4**: A nested agent refuses to create a branch or PR when base-branch context is
      missing, ambiguous, or inconsistent with the parent run.
- [ ] **AC5**: PR creation is rejected before submission when the target base branch does
      not match the parent run's approved workflow base.
- [ ] **AC6**: The workflow does not fall back to the GitHub repository default branch
      for spec, plan, or implementation PRs when explicit base context is
      missing.
- [ ] **AC7**: Parent orchestrators enumerate in-scope worktrees and open PRs at
      documented checkpoints and surface unexpected forks as warnings or stops.
- [ ] **AC8**: Duplicate-fork warnings include the affected issue, expected branch or
      worktree, discovered branch or PR, observed PR base when available, and
      required next action.
- [ ] **AC9**: Parallel batch runs preserve the explicit approved item scope when
      checking for forks and do not mutate artifacts for out-of-scope items.
- [ ] **AC10**: The item runner's final summary reports duplicate-fork stops or warnings,
      skipped out-of-scope artifacts, base-branch context failures, and the
      canonical branch or PR that remains active.
- [ ] **AC11**: Deliberately split work for the same issue is allowed only when explicit
      parent-orchestrator or human approval and explicit base branch are both
      present.
- [ ] **AC12**: Workflow smoke or regression coverage verifies duplicate-artifact
      detection, missing-base refusal, wrong-base refusal, and parent-visible
      fork warnings.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Require existing artifact checks before creating new nested work | AC1, AC2 |
| 2. Block or report duplicate nested work | AC2, AC8, AC10 |
| 3. Require explicit base-branch context in spawned handoffs | AC3, AC4 |
| 4. Prevent default-branch fallback | AC5, AC6 |
| 5. Require parent-orchestrator visibility before extra artifacts | AC7, AC8, AC10 |
| 6. Enumerate in-scope worktrees and open PRs during orchestration | AC7, AC8, AC9 |
| 7. Preserve canonical item runner as source of truth | AC9, AC10, AC11 |

## Out of Scope (MVP)

- Cleaning up or reopening historical duplicate PRs that were created before
  this behavior exists.
- Changing the repository's GitHub default branch.
- Granting automatic merge authority for duplicate cleanup PRs or unexpected
  forks.
- Designing the exact helper function names, shell implementation, or storage
  format for parent-child handoff metadata.
- Changing workflow status names or adding a new tracker stage for duplicate
  fork handling.
- Broadly preventing multiple legitimate PRs for one issue when a parent
  orchestrator or human has explicitly approved separate scopes and base
  branches.
