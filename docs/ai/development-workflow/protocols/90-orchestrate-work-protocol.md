# Protocol: Orchestrate One Workflow Item

**Agent role**: Item Orchestrator
**Purpose**: Advance one workflow item, execute the next deterministic action, and keep that item moving until it reaches a real terminal condition

This is a **supporting protocol**. The item orchestrator does not own a workflow stage, but it coordinates the stage-specific protocols for one development item at a time.

The portfolio-wide batch launcher is defined separately in `89-batch-orchestrate-work-protocol.md`.

---

## Overview

The item orchestrator:
1. Resolves the request to exactly one workflow item
2. Determines the next deterministic action for that item
3. Executes creator, reviewer, PR, CI, and automated-review work as one continuous control loop
4. Stops only when the item is truly waiting on a human, blocked, or escalated

### Persistent orchestration contract

A single item-orchestration run should keep advancing the selected item until it reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- The request cannot be resolved to exactly one workflow item

These are **not** terminal conditions and must not stop the run:

- A creator stage finished drafting its output
- A reviewer found fixable issues
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting for CI or automated review to finish
- Automated review found blocking issues that the matching fixer agent can address

---

## Step 1: Resolve the Target Item

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands.

Resolve the request to exactly one of the following:

1. **Backlog / issue tracker item** — use when a human explicitly requests a not-yet-started item
2. **Development folder** — `docs/specs/developments/<timestamp>_<slug>`
3. **Workflow branch** — `spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `hotfix/*`
4. **Open PR**

Use these helpers while resolving and resuming work:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

If the request is portfolio-wide or refers to multiple items, stop using this protocol and switch to `89-batch-orchestrate-work-protocol.md`.

Important for `development folder` targets:

- `workflow-next-action.sh --development` is only reliable once the item is already `Spec Ready`, `Plan Ready`, or `In Development`.
- A development folder by itself cannot distinguish `Spec In Review` / `Plan In Review` from the corresponding merged state.
- If the target may still be waiting on a spec or plan PR merge, confirm the state via the issue tracker or by inspecting the workflow branch / PR directly before advancing.

When dispatching a subagent for this item, include a short “Issue Tracker Summary” in the handoff:

- What the issue is asking for
- Any scope changes / decisions in recent comments
- Any ambiguity or conflict that still requires human confirmation

---

## Step 2: Determine the Next Deterministic Action

### What can advance now?

| Current state / detection | Can advance if... | Next action |
|---|---|---|
| Backlog | Human has requested this specific item | Run `01-generate-specs-protocol.md` |
| Spec In Review | Spec PR is still open | Wait — spec PR is open, pending human review / merge |
| Spec branch pushed, no PR yet | Branch exists on local / remote / worktree | Run `01-review-specs-protocol.md`, open the PR, then finish PR readiness |
| Spec Ready | Spec PR is merged | Run `02-generate-implementation-plan-protocol.md` |
| Plan In Review | Plan PR is still open | Wait — plan PR is open, pending human review / merge |
| Plan branch pushed, no PR yet | Branch exists on local / remote / worktree | Run `02-review-implementation-plan-protocol.md`, open the PR, then finish PR readiness |
| Plan Ready | Plan PR is merged | Run `04-implement-development-protocol.md` |
| Dev branch pushed, no PR yet | Branch exists on local / remote / worktree | Run `04-review-implemented-development-protocol.md`, open the PR, then finish PR readiness |
| PR open, no readiness label | PR exists and latest push has not fully cleared | Run Step 7 and Step 8 until clean or escalated |
| PR labeled `agent:needs-fixes` | Human or automated systems requested changes | Address feedback, push, then run Step 7 and Step 8 |
| PR labeled `agent:ready-for-review` | — | Wait — human review / merge required |

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

If any check returns a match: **do not re-dispatch**. Resume from the existing branch or PR with `workflow-next-action.sh`.

### Dependency check

Before advancing the item, check its spec's `Depends on` field. If any dependency is not yet `Merged` or `Released`, stop and report the blocked state to the human.

---

## Step 3: Dispatch Strategy

Use the matching workflow agent / skill for the next stage when your runner supports handoff. Otherwise continue in the current session by following the referenced stage protocol directly.

**Subagent assignment by stage:**

| Stage action | Agent to invoke |
|---|---|
| Write spec | `product-manager` |
| Review spec | `spec-reviewer` |
| Write plan | `tech-lead` |
| Review plan | `implementation-plan-reviewer` |
| Implement feature | `developer` |
| Review code | `code-reviewer` |

This protocol stays scoped to one item. It may call different stage agents over time, but it must not start scanning or dispatching unrelated items.

---

## Step 4: Execute and Re-evaluate

Run the next deterministic action for the selected item, then immediately re-evaluate the item state.

Expected chain:

`creator -> reviewer -> PR opened -> automated review loop -> CI loop -> readiness label or escalation`

After any subagent finishes, determine whether the item still has a deterministic next action:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
./scripts/development-workflow/workflow-next-action.sh --development <path>
```

Do not stop after a single creator or reviewer stage if the next action is deterministic.

---

## Step 5: Resume Rules

When work already exists, resume rather than restart.

- If a development folder already maps to `Spec Ready`, `Plan Ready`, or `In Development`, continue from that state
- If a workflow branch already exists, use `workflow-next-action.sh --branch <branch>`
- If a PR already exists, use `workflow-next-action.sh --pr <number>`
- If labels indicate `agent:needs-fixes`, enter the fix loop instead of reopening the stage from scratch

The item orchestrator owns the full control loop for this item until it reaches a terminal condition.

---

## Step 6: Notify Humans

After the selected item reaches a terminal condition, provide a concise summary:

```markdown
## Item Orchestration Summary

- Item: [identifier]
- Final state: ready for human review / waiting on human decision / blocked / escalated
- Path taken: plan written -> reviewed -> PR opened -> automated review clean -> CI green
- Next human action: merge PR / answer architecture question / unblock dependency
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

### Blocking vs. suggestion classification

When the automated review platform returns inline comments, classify them before deciding whether the PR needs fixes.

- Treat a comment as a **soft suggestion** only when every non-empty, non-code line starts with an advisory prefix such as `Consider`, `You might`, `An alternative`, `Optionally`, `It could be cleaner to`, `Perhaps`, `Maybe`, `You could`, `One option is`, or `Alternatively`.
- Treat any other inline comment as **blocking**.
- Treat `CHANGES_REQUESTED` reviews from the automated reviewer as **blocking**.

Soft suggestions may be reported in summaries, but they do not change the loop result to `needs_fixes`. Any blocking finding does.

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
