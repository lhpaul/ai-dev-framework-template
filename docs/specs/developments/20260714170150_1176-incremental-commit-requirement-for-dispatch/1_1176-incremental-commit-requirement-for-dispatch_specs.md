# Incremental Commit Requirement for Dispatch — Spec

---

## Overview

Long-running workflow agents can lose useful partial work when a runner dies
before its final end-of-run commit. This feature makes incremental commits an
explicit dispatch requirement for item-level agents doing substantial work, so
completed logical sub-parts are recoverable even when concurrent load, provider
disconnects, or watchdog stalls interrupt a run. The requirement should be
visible before the agent starts work and should guide recovery operators toward
committed partial progress rather than empty or ambiguous worktrees.

This changes an existing workflow capability: item dispatch and recovery
expectations for the AI development framework. It does not change the staged
spec-plan-implementation lifecycle, reviewer-loop requirements, or human merge
policy.

## Brief Objective List

1. Add a pre-dispatch instruction that item agents must commit immediately after
   each completed logical sub-part of long-running work.
2. Prevent agents from batching all completed work into a single end-of-run
   commit when the work naturally has multiple completed sub-parts.
3. Make crash recovery safer by ensuring a recovery operator can inspect the
   item branch or worktree and find committed partial progress when any
   sub-part completed before interruption.
4. Keep the requirement scoped to recoverability; do not weaken review, CI,
   readiness labels, or human merge gates.
5. Consider whether a maximum-safe concurrency guideline should be documented
   for heavy code-change agents.

## Use Cases

### Use Case 1: Dispatch a long-running item agent

**Actor**: Portfolio Orchestrator or Work Item Runner dispatching an item-level
agent.
**Preconditions**: A human-approved single-item, multi-item, or epic-scoped run
has selected a work item whose next stage may involve substantial or multi-part
work.

**Steps**:

1. The actor prepares the dispatch instructions for the selected item and stage.
2. The dispatch instructions explicitly tell the receiving agent to commit after
   each completed logical sub-part of the work.
3. The dispatch instructions explicitly prohibit waiting until the end of the
   run to commit all completed work when multiple completed sub-parts exist.
4. The receiving agent starts work with that recoverability expectation visible
   in its task context.

**Postconditions**: The agent has clear, pre-work instructions to create
recoverable checkpoints as logical sub-parts complete.

**Information shown**:

- The work item and stage being dispatched.
- The current worktree or branch context, when worktree isolation is active.
- The incremental commit requirement and the reason it exists: crash recovery
  for completed partial work.

**Actions available**:

- Commit a completed logical sub-part before starting the next sub-part.
- Continue working after each commit when more in-scope work remains.
- Stop and report when no coherent sub-part can be completed safely.

**Considerations**:

- The requirement applies to completed sub-parts, not arbitrary partial edits.
  Agents should not commit broken intermediate states merely to satisfy a timer.
- Single-step work may still have one final commit when there is no meaningful
  completed sub-part before the end.

### Use Case 2: Recover after an interrupted agent run

**Actor**: Recovery operator or orchestrator resuming an interrupted item run.
**Preconditions**: An item agent stalled, disconnected, or died while assigned
  work was in progress.

**Steps**:

1. The actor inspects the item branch, PR, and worktree associated with the
   interrupted run.
2. If the interrupted agent completed any logical sub-part, the actor can find a
   corresponding commit on the item branch.
3. The actor resumes from the latest committed checkpoint rather than
   reconstructing completed work from uncommitted edits.
4. If no sub-part was completed, the actor can treat the absence of commits as
   evidence that no recoverable completed work exists.

**Postconditions**: Recovery has a deterministic starting point: either a
committed completed sub-part or a clear absence of completed work.

**Information shown**:

- The latest committed checkpoint for the item, when one exists.
- Any remaining uncommitted edits in the worktree, when recovery starts.
- The work item stage and next deterministic action.

**Actions available**:

- Resume the item from the latest committed sub-part.
- Preserve or reconcile uncommitted edits when they are relevant and safe.
- Re-run the stage from the last clean checkpoint when no completed sub-part was
  committed.

**Considerations**:

- Incremental commits improve recoverability but do not replace ordinary
  validation. Later reviewer and CI gates still decide whether the PR is ready.
- Recovery must remain scoped to the assigned item and must not touch sibling
  agents' worktrees or branches.

### Use Case 3: Maintain review and readiness guarantees

**Actor**: Work Item Runner advancing the PR after incremental commits have
  accumulated.
**Preconditions**: The item branch contains one or more incremental commits from
  completed sub-parts.

**Steps**:

1. The actor continues the normal stage lifecycle after the agent finishes or
   after recovery resumes the work.
2. Internal review, automated reviewer loop, CI, readiness labels, and tracker
   transitions run against the final PR state.
3. Human merge remains required unless the run has explicit merge authority.

**Postconditions**: Incremental commits have not bypassed any review,
validation, or merge checkpoint.

**Information shown**:

- Normal PR readiness evidence and reviewer summaries.
- The final item state after the standard gates complete.

**Actions available**:

- Fix reviewer or CI findings and add another commit.
- Mark the PR ready for human review only after the normal gates pass.
- Stop for human review, blocked dependency, or escalation as usual.

**Considerations**:

- Incremental commits are a crash-safety pattern, not a shortcut around the
  staged workflow.

## Business Rules

- Dispatch instructions for long-running item work must require an immediate
  commit after each completed logical sub-part.
- Dispatch instructions must state that agents must not intentionally batch all
  completed sub-parts into one end-of-run commit.
- A logical sub-part is complete only when it forms a coherent checkpoint that
  can be resumed from later without knowingly preserving a broken state.
- The requirement applies to item-level work where multiple completed sub-parts
  can exist, including explicitly batched, epic-scoped, and other long-running
  item dispatches.
- The requirement does not force extra commits for truly single-step work with
  no meaningful intermediate checkpoint.
- Incremental commits must stay scoped to the assigned item and branch or
  worktree.
- Incremental commits do not change PR readiness requirements: internal review,
  external reviewer loops, CI, readiness labels, tracker status, and human merge
  policy remain authoritative.
- Recovery guidance must treat committed sub-parts as the preferred recovery
  boundary and must still inspect live branch, PR, and worktree state before
  deciding the next action.

## Operational Visibility

- **Dispatch visibility**: The incremental commit requirement is visible in the
  instructions the receiving agent sees before it starts work.
- **Recovery visibility**: A recovery operator can inspect commit history and
  worktree state to identify the latest completed checkpoint.
- **Review visibility**: Reviewers see normal PR commits and reviewer-loop
  evidence; no separate readiness label or tracker state is introduced for
  incremental commits.

## Acceptance Criteria

- [ ] AC1: Given a long-running item dispatch, the receiving agent's
      instructions explicitly require committing immediately after each
      completed logical sub-part of work.
- [ ] AC2: Given a long-running item dispatch, the receiving agent's
      instructions explicitly say not to batch all completed sub-parts into one
      end-of-run commit.
- [ ] AC3: Given work that has no meaningful completed intermediate sub-part, the
      workflow permits a single final commit and does not require artificial
      broken-state checkpoints.
- [ ] AC4: Given a crashed or disconnected run after at least one logical
      sub-part completed, a recovery operator can inspect the item branch or
      worktree and find committed partial progress for the completed sub-part.
- [ ] AC5: Given a crashed or disconnected run with no completed sub-part, the
      absence of an incremental commit is acceptable recovery evidence that no
      completed checkpoint existed.
- [ ] AC6: Given a PR with incremental commits, the PR must still pass the
      normal internal review, automated reviewer loop, CI, readiness-label, and
      tracker-transition gates before it is reported ready for human review.
- [ ] AC7: Given a dispatch in a concurrent batch or epic-scoped run, the
      incremental commit requirement remains scoped to the assigned item and
      must not authorize edits, commits, or recovery actions in sibling
      worktrees or branches.
- [ ] AC8: Given the dispatch and recovery guidance is updated, a reviewer can
      find the incremental commit expectation before work starts and the
      recovery expectation when resuming an interrupted run.

## Out of Scope (MVP)

- Enforcing a wall-clock commit interval or timer-based checkpoint policy.
- Requiring commits for incomplete, failing, or incoherent partial edits.
- Automatically squashing, rewriting, or force-pushing incremental commits.
- Changing reviewer-loop, CI-loop, readiness-label, tracker-status, or merge
  authority requirements.
- Defining a numeric maximum-safe concurrency limit for heavy agents.

## Deferral Notes

- Objective 5 (maximum-safe concurrency guideline) is deferred to Out of Scope
  for this MVP. Rationale: the issue provides an example guideline, but the
  durable product requirement is recoverability under interruption; a numeric
  concurrency cap should be based on broader runner capacity evidence and may
  vary by agent type, repository, and workload. Human confirmation requested:
  no, because the incremental commit requirement can ship independently without
  deciding a universal concurrency number.

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| B1: Add a pre-dispatch instruction that item agents must commit immediately after each completed logical sub-part of long-running work. | Use Case 1, Business Rules, AC1, AC8 |
| B2: Prevent agents from batching all completed work into a single end-of-run commit when the work naturally has multiple completed sub-parts. | Use Case 1, Business Rules, AC2 |
| B3: Make crash recovery safer by ensuring a recovery operator can inspect the item branch or worktree and find committed partial progress when any sub-part completed before interruption. | Use Case 2, Business Rules, Operational Visibility, AC4, AC5, AC8 |
| B4: Keep the requirement scoped to recoverability; do not weaken review, CI, readiness labels, or human merge gates. | Use Case 3, Business Rules, AC6 |
| B5: Consider whether a maximum-safe concurrency guideline should be documented for heavy code-change agents. | Out of Scope (MVP), Deferral Notes |
