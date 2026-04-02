# Protocol: Orchestrate Portfolio Work

**Agent role**: Portfolio Orchestrator (`orchestrator`)
**Purpose**: Discover what can advance across the portfolio, group eligible items into safe parallel batches, dispatch one Work Item Runner (`item-orchestrator`) per item, and supervise the batch until each item reaches a real terminal condition

This is a **supporting protocol**. It coordinates multiple workflow items but does not execute any creator or reviewer stage directly. Stage execution belongs to the Work Item Runner (`91-orchestrate-work-protocol.md`) and the stage-specific protocols it invokes.

Humans normally invoke this protocol when they want portfolio-wide advancement rather than targeting one known item directly.

---

## Overview

The Portfolio Orchestrator:

1. Reads the current state of backlog, in-flight development folders, workflow branches, and open PRs
2. Determines which items can safely advance now
3. Groups eligible items into explicit parallel batches
4. Dispatches one Work Item Runner per item in the batch
5. Supervises until every dispatched item is waiting on a human, blocked, or escalated

### Persistent orchestration contract

A single Portfolio Orchestrator run should keep advancing eligible items until each dispatched item reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- No eligible work remains

These are **not** terminal conditions and must not stop the run:

- A batch was merely identified
- A subagent finished one creator or reviewer subroutine
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting on CI or automated review
- One item in a batch finished while others are still running

### When to use this protocol

Use this protocol when the request is portfolio-wide or multi-item, for example:

- "What can advance right now?"
- "Run all eligible work"
- "Process everything that can move in parallel"

If the request is explicitly about a single development, branch, or PR, skip this protocol and use `91-orchestrate-work-protocol.md` directly.

---

## Step 1: Gather Portfolio State

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands.

Read from the following sources:

1. **Issue tracker** (if configured): current status, due date, priority, dependencies, and latest brief
2. **Development folders**: `docs/specs/developments/`
3. **Workflow branches / PRs**: local branches, remote branches, active worktrees, open PRs

If available, run:

```bash
./scripts/development-workflow/discover-workflow-state.sh
./scripts/development-workflow/workflow-batch-plan.sh
```

Use these helpers while gathering detail:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

Build a portfolio map of:

- Backlog items that a human explicitly requested to start
- Work items in **Writing Spec** / **Writing Plan** / **In Development** (PR not yet human-ready), or branches/PRs still in PR-readiness loops
- Work items in **Spec in Review** / **Plan in Review** / **Implementation in Review**, or PRs labeled `ready-for-human-review` (human merge queue unless `needs-fixes`)
- Development folders that are `Spec Ready`, `Plan Ready`, or already in development
- Branches that were pushed but still have no PR
- PRs that still need readiness work or fix loops

When available, use `workflow-batch-plan.sh` as the initial candidate list for development folders, then enrich it with tracker and PR data.

When an issue tracker is configured and accessible, use it to pre-filter the candidate list: exclude items whose tracker status is already `Done`, `Merged`, `Cancelled`, or equivalent before calling `workflow-next-action.sh --development`. This is an optional optimization — the script performs its own VCS-level check to detect merged items, but skipping them at the tracker layer avoids unnecessary `gh` calls in large portfolios.

---

## Step 2: Determine Eligibility and Priority

### What can advance now?

| Portfolio item state | Can advance if... | Dispatch target |
|---|---|---|
| Backlog (Feature) | Human explicitly requested it | Work Item Runner on the tracker item / brief (starts at spec stage) |
| Backlog (Refactor) | Human explicitly requested it as a Refactor | Work Item Runner on the tracker item / brief (starts at plan stage, skips spec) |
| Writing Spec | Tracker **Writing Spec**; spec PR not yet human-ready | Work Item Runner on the tracker item / branch / PR |
| Writing Plan | Tracker **Writing Plan**; plan PR not yet human-ready | Work Item Runner on the tracker item / branch / PR |
| In Development | Tracker **In Development**; feature/fix PR not yet human-ready | Work Item Runner on the tracker item / branch / PR |
| Spec Ready | Spec PR is merged | Work Item Runner on the development folder |
| Plan Ready | Plan PR is merged | Work Item Runner on the development folder |
| Pushed workflow branch, no PR yet | Branch exists on local/remote/worktree | Work Item Runner on the branch |
| PR open, no readiness label | PR exists and latest push has not fully cleared | Work Item Runner on the PR |
| PR labeled `needs-fixes` | Human or automated systems requested changes | Work Item Runner on the PR |
| Spec in Review / Plan in Review / Implementation in Review or `ready-for-human-review` | — | Wait; do not redispatch (unless human feedback requires a fix loop) |

### Priority order

When multiple items are eligible, prioritize as follows:

1. Due date within 2 weeks, earliest first
2. Priority: Urgent → High → Normal → Low
3. Creation date, earlier first

If a due date conflicts with the abstract priority order, flag it to the human rather than silently choosing.

### Dependency gate

Before batching an item, check its `Depends on` field or tracker dependency data. If any dependency is not yet `Merged` or `Released`, skip the item and record it as blocked.

---

## Step 3: Build Parallel Batches

Group eligible items into explicit batches.

**Safe to batch together**:

- Multiple spec-creation items
- Multiple plan-creation items
- Resume/readiness work for unrelated PRs
- Implementations that clearly touch different areas of the codebase

**Do not batch together**:

- Two implementations that both require database schema migrations
- Two items where one depends on the other
- Two implementations whose overlap is unclear and cannot be resolved cheaply

**Codex fallback**:

If the runner cannot execute multiple Work Item Runners concurrently, preserve the same batching decision but process that batch sequentially. Report the fallback explicitly in the summary.

For each item in the batch, prepare a short handoff:

- Item identifier: development path, branch, PR, or tracker ID
- Current brief / tracker summary
- Current next action
- Priority context
- Parallelization notes or serialization reason

---

## Step 4: Dispatch Work Item Runners

Dispatch exactly one Work Item Runner per item in the current batch.

**Preferred handoff target by runner**:

| Runner | Handoff target |
|---|---|
| Claude Code | `item-orchestrator` agent |
| Cursor | `/item-orchestrator` or `/run-item-work` |
| Codex | `workflow-item-orchestrator` skill |

If the runner supports true concurrent subagents, launch the full batch in parallel.

If the runner does **not** support Work Item Runner handoff natively, continue in the current session by following `91-orchestrate-work-protocol.md` for each item one at a time.

---

## Step 5: Supervise Until Terminal

The Portfolio Orchestrator remains responsible for the batch after dispatch.

After a Work Item Runner returns:

1. Re-check the item with `workflow-next-action.sh` when a branch, PR, or development folder exists
2. If the next action is still deterministic because the Work Item Runner returned early or was interrupted, redispatch / resume that same item
3. Stop supervising that item only when it is waiting on a human, blocked, or escalated

Do not consider the batch complete until every dispatched item has reached a real terminal condition.

---

## Step 6: Notify Humans

After all currently eligible items have reached a terminal condition, provide a consolidated summary:

```markdown
## Batch Orchestration Summary

### Batches Executed
- Batch 1 (parallel): [Item A], [Item B]
- Batch 2 (serialized): [Item C] — serialized because both items touch schema migrations

### Ready for Human Review
- [PR link] — [item] — [stage] — Automated review: ✅ / ⏭️ / ⚠️

### Waiting on Human
- [Item D]: architecture decision needed
- [Item E]: PR already open and waiting to be merged

### Blocked / Escalated
- [Item F]: blocked by [Item G]
- [Item H]: reviewer loop escalated after max cycles
```

Call out any sequential fallback caused by runner limitations so humans can distinguish a workflow constraint from a product dependency.
