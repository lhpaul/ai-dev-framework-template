# Protocol: Orchestrate Work

**Agent role**: Orchestrator
**Purpose**: Discover what can advance, execute the next deterministic action, and keep each item moving until it reaches a real terminal condition

This is a **supporting protocol** — the orchestrator does not own a workflow stage but coordinates across stages.

---

## Overview

The orchestrator:
1. Reads the current state of all in-flight and backlog items
2. Determines what can be safely advanced to the next stage
3. Executes creator, reviewer, PR, CI, and automated-review work as one continuous control loop
4. Stops only when an item is truly waiting on a human, blocked, or escalated

### Persistent orchestration contract

A single orchestration run should keep advancing an item until it reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- No eligible work remains

These are **not** terminal conditions and must not stop the run:

- A creator stage finished drafting its output
- A reviewer found fixable issues
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting for CI or automated review to finish
- Automated review found blocking issues that the matching fixer agent can address

---

## Step 1: Gather State

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands. They work with any model or tool (Codex, Cursor, Claude Code, etc.).

Read from the following sources (in priority order):

1. **Issue tracker** (if configured): current status of all issues and the latest brief. See [`integrations/`](../integrations/) for tracker-specific setup and [`integrations/issue-tracker.md`](../integrations/issue-tracker.md) for tracker-agnostic rules.
2. **Development folders**: `docs/specs/developments/` — use `workflow-next-action.sh --development <path>` (or the issue tracker when it is the source of truth) to determine the current stage; the spec file's status field is optional when the tracker is used
3. **Open PRs**: `git branch -r` and/or the repository's PR list — which branches are open, their labels, and CI status

If available, run:

```bash
./scripts/development-workflow/discover-workflow-state.sh
```

to collect the current branch, relevant local/remote branches, worktrees, development folders, and open PRs in one pass.

Use these helpers while gathering state:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

Build a mental map of:
- Items in **Backlog** (no spec yet)
- Items in **Spec In Review** (spec PR open, waiting for human to merge — do not re-dispatch)
- Items in **Spec Ready** (spec PR merged, no plan yet)
- Items in **Plan In Review** (plan PR open, waiting for human to merge — do not re-dispatch)
- Items in **Plan Ready** (plan PR merged, not yet in development)
- Items with a **pushed workflow branch but no PR yet**
- Items with an **open PR that still lacks a readiness label**
- Items with **pending human review** (`agent:ready-for-review`)
- Items with **pending fixes** (`agent:needs-fixes`)

When dispatching a subagent for an item, include a short “Issue Tracker Summary” in the handoff:
- What the issue is asking for
- Any scope changes / decisions in recent comments
- Any flagged ambiguity or conflicts that require human confirmation

---

## Step 2: Determine Eligibility

### What can advance now?

| Current state | Can advance if... | Next action |
|---|---|---|
| Backlog | Human has requested it | Run `01-generate-specs-protocol.md` |
| Spec In Review | — | **Wait** — PR is open and waiting on human review / merge |
| Spec branch pushed, no PR yet | Branch exists on remote | Run `01-review-specs-protocol.md`, open the PR, then finish PR readiness |
| Spec Ready | Spec PR is merged | Run `02-generate-implementation-plan-protocol.md` |
| Plan In Review | — | **Wait** — PR is open and waiting on human review / merge |
| Plan branch pushed, no PR yet | Branch exists on remote | Run `02-review-implementation-plan-protocol.md`, open the PR, then finish PR readiness |
| Plan Ready | Plan PR is merged | Run `04-implement-development-protocol.md` |
| Dev branch pushed, no PR yet | Branch exists on remote | Run `04-review-implemented-development-protocol.md`, open the PR, then finish PR readiness |
| PR open, no readiness label | PR exists and latest push has not fully cleared | Run Step 7 and Step 8 until clean or escalated |
| PR labeled `agent:needs-fixes` | Human or automated systems requested changes | Address feedback, push, then run Step 7 and Step 8 |
| PR labeled `agent:ready-for-review` | — | **Wait** — human review / merge required |

### Pre-dispatch branch check

Before dispatching any creator-stage agent, run all three checks below. An existing branch or active worktree means work already exists and should be resumed rather than restarted.

```bash
git branch -r | grep "<branch-prefix>/<slug>"
git branch | grep "<branch-prefix>/<slug>"
git worktree list | grep "<branch-prefix>/<slug>"
```

| Stage about to dispatch | Branch / worktree to check for |
|---|---|
| Write spec | `spec/[slug]` |
| Write plan | `implementation-plan/[slug]` |
| Implement | `feature/[slug]` |

If any check returns a match: **do not re-dispatch**. Instead, resume from the existing branch or PR using:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
```

### Dependency check

Before advancing any item, check its spec's `Depends on` field. If any dependency is not yet `Merged` or `Released`, skip the item and report the blocked state to the human.

---

## Step 3: Prioritization

When multiple items are eligible, prioritize as follows:

1. **Due date** — items due within 2 weeks take precedence over priority; sort by earliest due date
2. **Priority** — Urgent → High → Normal → Low
3. **Creation date** — earlier items first within the same priority

If a due date conflicts with priority ordering, flag it to the human rather than silently choosing.

---

## Step 4: Parallelization Rules

Multiple items can be advanced simultaneously, with restrictions:

**Safe to parallelize**:
- Spec creation for multiple items
- Plan creation for multiple items
- Implementations that touch different parts of the codebase

**Avoid parallelizing**:
- Two implementations that both require database schema migrations
- Two items where one depends on the other

When in doubt, ask the human.

---

## Step 5: Execute

Group eligible items into **parallel batches** — items that pass the Step 4 rules and can run simultaneously. Then dispatch all items in the same batch as concurrent subagents rather than running them sequentially.

**How to parallelize with Claude Code:**

Use the `Task` tool to spawn a subagent for each item in the batch. Launch all subagents in a single message so they run simultaneously.

**How to execute with Codex skills:**

Codex skills are thin wrappers over the same protocol files. If your Codex runner can invoke multiple skills concurrently, group a batch exactly as you would with subagents. If it cannot, process the batch sequentially in the current session, but preserve the same batching decision and state clearly in the summary.

**How to execute with Cursor:**

Use Cursor subagents (defined in `.cursor/agents/`) so each stage runs with the model configured in the agent file. Invoke subagents by name (e.g., `/developer`, `/spec-reviewer`) or delegate from the main Agent. Launch multiple subagents in parallel when a batch is eligible — Cursor supports concurrent subagent execution. Each subagent's model is set via the `model` field in `.cursor/agents/<name>.md` (see `agent-model-config.md` for how to set or override models per agent).

**Subagent assignment by stage:**

| Stage action | Agent to invoke |
|---|---|
| Write spec | `product-manager` |
| Review spec | `spec-reviewer` |
| Write plan | `tech-lead` |
| Review plan | `implementation-plan-reviewer` |
| Implement feature | `developer` |
| Review code | `code-reviewer` |

**Sequential fallback:**
If only one item is eligible, or if items must be sequenced, run them one at a time. Document the reason in the summary.

### Creator stages are subroutines, not end states

After any subagent finishes, immediately determine whether the item still has a deterministic next action:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
./scripts/development-workflow/workflow-next-action.sh --development <path>
```

Expected chain:

`creator -> reviewer -> PR opened -> automated review loop -> CI loop -> readiness label or escalation`

Do not stop after a single creator or reviewer stage if the next action is deterministic.

---

## Step 6: Notify Humans

After all currently eligible work has reached a terminal condition, provide a clear summary:

```markdown
## Orchestration Run Summary

### Work Completed
- [Item A]: Spec created -> reviewed -> PR opened -> ready for human review
- [Item B]: Implementation updated -> reviewer loop clean after 2 cycles -> CI green

### PRs Ready for Human Review
- [PR link] — [feature name] — [stage] — Automated review: ✅ passed after N cycle(s) / ⏭️ skipped / ⚠️ escalated

### Waiting on Human
- [Item C]: plan reviewer surfaced an architecture choice that needs a decision
- [Item D]: spec PR is already open and waiting to be merged

### Blocked Items
- [Item E]: blocked by [Item F] (dependency not yet Merged)
```

---

## Step 7: Automated Reviewer Loop

If an automated code review platform is configured (see [`integrations/pr-review-platform.md`](../integrations/pr-review-platform.md)), run this loop after **any push to a PR branch**. If no review platform is configured, skip this step and report `⏭️ skipped` in the Step 6 summary.

**Standalone use:** This step (and Step 8) can be run for a single PR without full orchestration — see [`92-automated-reviewer-loop-protocol.md`](92-automated-reviewer-loop-protocol.md) and the `/run-reviewer-loop` command (Cursor) or `automated-reviewer-loop` agent (Claude Code) or `workflow-reviewer-loop` skill (Codex).

**Important:** Run Step 7 **to completion** and use its result before running Step 8. Do not run Step 7 in the background while proceeding to Step 8. The review loop can take several minutes (poll interval × wait for bot). Only when the script exits with `clean` or `skipped` may you continue to Step 8.

The helper script checks for **existing** blocking findings from the bot (e.g. from a review that already ran on PR open) before posting a new trigger. If it finds any, it exits with `needs_fixes` without triggering — so the fixer addresses them first; after a push, the next run triggers a fresh review. This avoids starting a new review while ignoring issues already raised.

Initialize `cycle = 0` once per orchestration run for the PR. Increment `cycle` each time a fixer agent is dispatched. Do not reset `cycle` after a fixer push; escalate when the run reaches `max_cycles`.

Prefer the helper script:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
```

Interpret the result as follows:

| Result | Action |
|---|---|
| `clean` | Continue immediately to Step 8 |
| `skipped` | Continue immediately to Step 8 |
| `needs_fixes` and `cycle < max_cycles` | Increment `cycle`, dispatch the matching fixer agent, wait for a push, then run Step 7 again |
| `needs_fixes` and `cycle >= max_cycles` | Escalate to human |
| `escalate` | Escalate to human |

**Fixing agent by PR branch type:**

| PR branch prefix | Agent to dispatch |
|---|---|
| `spec/*` | `spec-reviewer` |
| `implementation-plan/*` | `implementation-plan-reviewer` |
| `feature/*` / `fix/*` / `hotfix/*` | `code-reviewer` |

### Loop parameters

| Parameter | Value | Description |
|---|---|---|
| `poll_interval` | 2 min | Time to wait between review status checks |
| `max_wait` | 20 min | Max wait **per fix cycle** for the reviewer to respond |
| `max_cycles` | 3 | Max number of times a fixing agent is dispatched before escalating |

---

## Step 8: CI Loop

**Only after Step 7 has completed** with result `clean` or `skipped`, wait for required checks to settle.

Prefer the helper script:

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

Interpret the result as follows:

| Result | Action |
|---|---|
| `green` | Apply `agent:ready-for-review`, remove `agent:needs-fixes` if present, and report the PR as ready |
| `red` | Apply `agent:needs-fixes`, dispatch the matching fixer agent, wait for a push, then return to Step 7 |
| `timeout` | Escalate to human; do not apply `agent:ready-for-review` |

---

## Step 9: Feedback Loop

When a human requests changes on a PR:

1. Remove `agent:ready-for-review`
2. Add `agent:needs-fixes`
3. Address the feedback
4. Push fixes
5. Run Step 7
6. Run Step 8
7. Reapply `agent:ready-for-review` only when both loops are clean again

See `91-pr-readiness-signal-protocol.md` for label definitions.
