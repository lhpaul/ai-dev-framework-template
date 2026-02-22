# Protocol: Orchestrate Work

**Agent role**: Orchestrator
**Purpose**: Discover what developments can advance, run safe parallel work, notify humans when outputs are ready for review

This is a **supporting protocol** — the orchestrator does not own a workflow stage but coordinates across stages.

---

## Overview

The orchestrator:
1. Reads the current state of all in-flight and backlog items
2. Determines what can be safely advanced to the next stage
3. Executes parallel work where safe
4. Signals humans when PRs are ready for review

---

## Step 1: Gather State

Read from the following sources (in priority order):

1. **Issue tracker** (if configured): current status of all issues. See [`integrations/`](../integrations/) for tracker-specific setup.
2. **Development folders**: `docs/specs/developments/` — read the status field of each spec to determine the current stage
3. **Open PRs**: `git branch -r` and/or the repository's PR list — which branches are open and their CI status

Build a mental map of:
- Items in Backlog (no spec yet)
- Items in Spec Ready (spec merged, no plan yet)
- Items in Plan Ready (plan merged, not yet in development)
- Items In Development (feature branch open, PR pending)
- Items with pending review (PRs labeled `agent:ready-for-review`)

---

## Step 2: Determine Eligibility

### What can advance now?

| Current stage | Can advance if... | Next action |
|---|---|---|
| Backlog | Human has requested it | Run `01-generate-specs-protocol.md` |
| Spec Ready | Spec PR is merged | Run `02-generate-implementation-plan-protocol.md` |
| Plan Ready | Plan PR is merged | Run `04-implement-development-protocol.md` |
| In Development (PR open) | CI green, review loop clean | Apply `agent:ready-for-review`, notify human |
| In Development (feedback received) | Human requested changes on PR | Address feedback, re-push |

### Dependency check

Before advancing any item, check its spec's `Depends on` field. If any dependency is not yet Merged or Released, skip this item and report the blocked state to the human.

---

## Step 3: Prioritization

When multiple items are eligible, prioritize as follows:

1. **Due date** — items due within 2 weeks take precedence over priority; sort by earliest due date
2. **Priority** — Urgent → High → Normal → Low
3. **Creation date** — earlier items first within the same priority

If a due date conflicts with priority ordering (e.g., a Low priority item is due tomorrow but a High priority item is due in 3 weeks), **flag it to the human** rather than silently choosing. Present both options.

---

## Step 4: Parallelization Rules

Multiple items can be advanced simultaneously, with restrictions:

**Safe to parallelize**:
- Spec creation for multiple items simultaneously
- Plan creation for multiple items simultaneously
- Implementation of items that touch different parts of the codebase

**Avoid parallelizing**:
- Two implementations that both require database schema migrations (apply sequentially to avoid conflicts)
- Two items where one depends on the other

When in doubt about whether parallelization is safe, ask the human.

---

## Step 5: Execute

For each eligible item (within safe parallelization rules):
1. Follow the appropriate protocol for the next stage
2. Document what you started and why in a summary at the end

---

## Step 6: Notify Humans

After completing work, provide a clear summary:

```
## Orchestration Run Summary

### Work Completed
- [Item A]: Spec created → PR opened (spec/item-a)
- [Item B]: Implementation started → PR opened (feature/item-b)

### PRs Ready for Human Review
- [PR link] — [feature name] — [stage]

### Blocked Items
- [Item C]: blocked by [Item D] (not yet Merged)

### Flagged for Human Decision
- [Item E]: Due date (2025-03-01) conflicts with Low priority — should I prioritize it over High priority [Item F] (due 2025-04-01)?
```

---

## Step 7: Feedback Loop

When a human requests changes on a PR:

1. Remove `agent:ready-for-review` label
2. Add `agent:needs-fixes` label
3. Address the feedback
4. Push fixes
5. Reapply `agent:ready-for-review` when ready

See `91-pr-readiness-signal-protocol.md` for label definitions.
