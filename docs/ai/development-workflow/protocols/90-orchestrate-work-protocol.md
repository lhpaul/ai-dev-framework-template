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

1. **Issue tracker** (if configured): current status of all issues and the latest brief. See [`integrations/`](../integrations/) for tracker-specific setup and [`integrations/issue-tracker.md`](../integrations/issue-tracker.md) for tracker-agnostic rules.
2. **Development folders**: `docs/specs/developments/` — read the status field of each spec to determine the current stage
3. **Open PRs**: `git branch -r` and/or the repository's PR list — which branches are open and their CI status

Build a mental map of:
- Items in **Backlog** (no spec yet)
- Items in **Spec In Review** (spec PR open, waiting for human to merge — do not re-dispatch)
- Items in **Spec Ready** (spec merged, no plan yet)
- Items in **Plan In Review** (plan PR open, waiting for human to merge — do not re-dispatch)
- Items in **Plan Ready** (plan merged, not yet in development)
- Items **In Development** (feature branch open, PR pending)
- Items with pending review (PRs labeled `agent:ready-for-review`)
- Open PRs with **unresolved automated reviewer comments** (the review platform posted comments after the last push — run Step 8)

When dispatching a subagent for an item, include a short “Issue Tracker Summary” in the handoff:
- What the issue is asking for (from description)
- Any scope changes / decisions in recent comments
- Any flagged ambiguity or conflicts that require human confirmation

---

## Step 2: Determine Eligibility

### What can advance now?

| Current stage | Can advance if... | Next action |
|---|---|---|
| Backlog | Human has requested it | Run `01-generate-specs-protocol.md` |
| Spec In Review | — | **Wait** — spec PR is open, human must review and merge. Do not re-dispatch. |
| Spec Ready | Spec PR is merged | Run `02-generate-implementation-plan-protocol.md` |
| Plan In Review | — | **Wait** — plan PR is open, human must review and merge. Do not re-dispatch. |
| Plan Ready | Plan PR is merged | Run `04-implement-development-protocol.md` |
| In Development (PR open) | CI green, review loop clean | Apply `agent:ready-for-review`, notify human |
| In Development (automated reviewer commented) | Review platform posted comments after last push | Run Step 8 (automated reviewer loop) |
| In Development (feedback received) | Human requested changes on PR | Address feedback, re-push, then run Step 8 |

### Pre-dispatch branch check

Before dispatching any agent, run all three checks below. An existing branch or active worktree means an agent is already working or has worked on this item — even if the work was never pushed.

```bash
# 1. Remote branches (pushed work)
git branch -r | grep "<branch-prefix>/<slug>"

# 2. Local branches (unpushed work)
git branch | grep "<branch-prefix>/<slug>"

# 3. Active worktrees (work in progress in a worktree, may not be pushed or even committed)
git worktree list | grep "<branch-prefix>/<slug>"
```

| Stage about to dispatch | Branch / worktree to check for |
|---|---|
| Write spec (Backlog → Spec In Review) | `spec/[slug]` |
| Write plan (Spec Ready → Plan In Review) | `implementation-plan/[slug]` |
| Implement (Plan Ready → In Development) | `feature/[slug]` |

If any check returns a match: **do not re-dispatch**. Instead, report the item's actual state to the human — including whether a worktree is active, whether the branch has been pushed, and whether a PR is open.

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

Group eligible items into **parallel batches** — items that pass the Step 4 parallelization rules and can run simultaneously. Then dispatch all items in the same batch as concurrent subagents rather than running them sequentially.

**How to parallelize with Claude Code:**

Use the `Task` tool to spawn a subagent for each item in the batch. Launch all subagents in a **single message** so they run simultaneously. For example, if three features are ready for implementation:

```
[Single message with three Task tool calls]
  Task 1: developer agent → feature/user-auth
  Task 2: developer agent → feature/email-notifications
  Task 3: product-manager agent → feature/billing (spec needed)
```

Wait for **all** subagents to complete before moving on to Step 6.

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
If only one item is eligible, or if items must be sequenced (e.g., both have DB migrations), run them one at a time. Document the reason in the summary.

After all subagents finish, collect their outputs and document what each completed in the Step 6 summary.

---

## Step 6: Notify Humans

After completing work, provide a clear summary:

```
## Orchestration Run Summary

### Work Completed
- [Item A]: Spec created → PR opened (spec/item-a)
- [Item B]: Implementation started → PR opened (feature/item-b)

### PRs Ready for Human Review
- [PR link] — [feature name] — [stage] — Automated review: ✅ passed after N cycle(s) / ⏭️ skipped (not configured) / ⚠️ escalated (see Flagged section)

  > **Automated review status legend**: `✅ passed after N cycle(s)` — reviewer ran and found no blocking issues (N = number of fix cycles dispatched; 0 means it passed on the first review). `⏭️ skipped` — Step 8 was not run (no review platform configured). `⚠️ escalated` — loop could not complete autonomously; human action required.

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
5. Run Step 8 (automated reviewer loop)
6. Reapply `agent:ready-for-review` when ready

See `91-pr-readiness-signal-protocol.md` for label definitions.

---

## Step 8: Automated Reviewer Loop

If an automated code review platform is configured (see [`integrations/pr-review-platform.md`](../integrations/pr-review-platform.md)), run this loop after **any push to a PR branch** — whether from a subagent or from the orchestrator directly — to resolve all findings before requesting human review. If no review platform is configured, skip this step and report `⏭️ skipped` in the Step 6 summary.

> **Tool-specific details** (how to trigger a review, poll for a response, and fetch inline comments) live in your review platform's integration doc. See [`integrations/greptile.md`](../integrations/greptile.md) for Greptile.

### Loop parameters

| Parameter | Value | Description |
|---|---|---|
| `poll_interval` | 2 min | Time to wait between review status checks |
| `max_wait` | 20 min | Max wait **per fix cycle** for the reviewer to respond (resets after each push) |
| `max_cycles` | 3 | Max number of times a fixing agent is dispatched before escalating to human |

### Step 8.1 — Trigger the reviewer

Initialize before entering Step 8.1 for the first time: `cycle = 0`.

After each push, record the current timestamp as `last_push_at` in ISO 8601 format, set `elapsed = 0`, then trigger a re-review using your platform's mechanism (see integration doc).

> **Cycle counter**: `cycle` counts how many times a fixing agent has been dispatched. It starts at 0 and increments only when a fixer is dispatched in Step 8.3 — not on the initial push.

### Step 8.2 — Poll for response

Wait `poll_interval` (2 min), add `poll_interval` to `elapsed`, then check whether the reviewer has completed a new review after `last_push_at` using your platform's mechanism (see integration doc).

| Result | Action |
|---|---|
| No review yet and `elapsed < max_wait` | Wait another `poll_interval` and poll again |
| No review yet and `elapsed >= max_wait` | **Escalate to human** — see Step 8.5 (timeout) |
| Reviewer completed a new review | Proceed to Step 8.3 |

### Step 8.3 — Evaluate findings

Fetch new inline comments posted after `last_push_at` using your platform's mechanism (see integration doc).

**Classifying comments — blocking vs. suggestion:**

Treat a comment as a **suggestion** (safe to skip) only if its body starts with clearly soft language, such as:
- "Consider...", "You might...", "An alternative...", "Optionally...", "It could be cleaner to...", "Perhaps...", "Maybe...", "You could...", "One option is...", "Alternatively..."

Treat everything else as **blocking** — including comments describing bugs, failures, or any imperative phrasing ("Use...", "Change...", "Replace..."). When in doubt, treat as blocking.

| Finding | Action |
|---|---|
| No inline comments, or only suggestions | Proceed to Step 8.4 — reviewer is satisfied |
| Blocking issues found and `cycle < max_cycles` | Increment `cycle`. Dispatch fixing agent (see table below), wait for push, go back to Step 8.1 |
| Blocking issues found and `cycle >= max_cycles` | **Escalate to human** — see Step 8.5 (max cycles) |

**Fixing agent by PR branch type:**

| PR branch prefix | Agent to dispatch |
|---|---|
| `spec/*` | `product-manager` |
| `implementation-plan/*` | `tech-lead` |
| `feature/*` / `fix/*` / `hotfix/*` | `code-reviewer` |

### Step 8.4 — Mark PR ready for human review

The reviewer has no remaining blocking issues. Apply the readiness label and proceed to Step 6:

```bash
gh pr edit <pr_number> --add-label "agent:ready-for-review"
```

In the Step 6 summary, report: `Automated review: ✅ passed after N cycle(s)`.

### Step 8.5 — Escalate to human

Triggered when either `max_wait` or `max_cycles` is exceeded. Include in the Step 6 summary:

```
### Flagged for Human Decision
- PR #N ([feature name]): Automated reviewer loop could not complete autonomously.
  - Reason: timeout after `max_wait` waiting for reviewer response / max fixing agent dispatches (`max_cycles`) reached
  - Reviewer's latest comments: [paste inline comment bodies here]
  - Recommended action: human reviews comments and decides how to proceed
```

Do **not** apply `agent:ready-for-review` until the human resolves the escalation.
