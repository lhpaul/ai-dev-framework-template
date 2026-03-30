# Protocol: Run One Workflow Item

**Agent role**: Work Item Runner (`item-orchestrator`)
**Purpose**: Advance one workflow item, execute the next deterministic action, and keep that item moving until it reaches a real terminal condition

This is a **supporting protocol**. The Work Item Runner does not own a workflow stage, but it coordinates the stage-specific protocols for one development item at a time.

The portfolio-wide launcher is defined separately in `90-batch-orchestrate-work-protocol.md` as the **Portfolio Orchestrator** (`orchestrator`).

This protocol may be entered in either of two ways:

- A human invokes the Work Item Runner directly for one specific work item, branch, development folder, or PR
- The Portfolio Orchestrator dispatches the Work Item Runner after scanning the broader portfolio

---

## Overview

The Work Item Runner:
1. Resolves the request to exactly one workflow item
2. Determines the next deterministic action for that item
3. Executes creator, review-gate, PR, CI, and automated-review work as one continuous control loop
4. Stops only when the item is truly waiting on a human, blocked, or escalated

### Persistent orchestration contract

A single Work Item Runner run should keep advancing the selected item until it reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- The request cannot be resolved to exactly one workflow item

These are **not** terminal conditions and must not stop the run:

- A creator stage finished drafting its output
- A reviewer found fixable PR feedback
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting for CI or automated review to finish
- Automated review found blocking PR feedback that the matching fixer agent can address

---

## Step 1: Resolve the Target Item

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands.

Resolve the request to exactly one of the following:

1. **Backlog / tracker work item** — use when a human explicitly requests a not-yet-started item
2. **Development folder** — `docs/specs/developments/<timestamp>_<slug>`
3. **Workflow branch** — `spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `hotfix/*`
4. **Open PR**

Use these helpers while resolving and resuming work:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

If the request is portfolio-wide or refers to multiple items, stop using this protocol and switch to `90-batch-orchestrate-work-protocol.md`.

Important for `development folder` targets:

- `workflow-next-action.sh --development` is only reliable once the item is already `Spec Ready`, `Plan Ready`, or `In Development`.
- A development folder by itself cannot distinguish `Spec in Review` / `Plan in Review` from the corresponding merged state.
- If the target may still be waiting on a spec or plan PR merge, confirm the state via the issue tracker or by inspecting the workflow branch / PR directly before advancing.

When dispatching a subagent for this item, include a short “Tracker Work Item Summary” in the handoff:

- What the work item is asking for
- Any scope changes / decisions in recent comments
- Any ambiguity or conflict that still requires human confirmation

---

## Step 2: Determine the Next Deterministic Action

### What can advance now?

| Current state / detection | Can advance if... | Next action |
|---|---|---|
| Backlog | Human has requested this specific item | Set tracker status to **Writing Spec**, then run `01-generate-spec-protocol.md` |
| Writing Spec | Tracker **Writing Spec** — spec PR not yet human-ready | Continue spec branch/PR work (generate, internal review, reviewer tools, CI) until tracker moves to **Spec in Review** |
| Spec in Review | Tracker **Spec in Review** — spec PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Spec branch pushed, no PR yet | Branch exists on local / remote / worktree | Run the spec review gate via `REVIEW.md` / `01-review-spec-protocol.md`, open the PR, then finish PR readiness |
| Spec Ready | Spec PR is merged | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md` |
| Writing Plan | Tracker **Writing Plan** — plan PR not yet human-ready | Continue plan branch/PR work until tracker moves to **Plan in Review** |
| Plan in Review | Tracker **Plan in Review** — plan PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Plan branch pushed, no PR yet | Branch exists on local / remote / worktree | Run the plan review gate via `REVIEW.md` / `02-review-implementation-plan-protocol.md`, open the PR, then finish PR readiness |
| Plan Ready | Plan PR is merged | Set tracker status to **In Development**, then run `03-implement-development-protocol.md` |
| In Development | Tracker **In Development** — feature/fix PR not yet human-ready | Continue implementation branch/PR work (Step 7a, 7, 8) until tracker moves to **Implementation in Review** |
| Implementation in Review | Tracker **Implementation in Review** — feature/fix PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Dev branch pushed, no PR yet | Branch exists on local / remote / worktree | Open draft PR, run the internal review gate (Step 7a), then run automated reviewer loop (Step 7) and CI loop (Step 8), then mark PR as ready |
| Draft PR open, internal review pending | PR is draft and the relevant internal review gate has not run yet or has open findings | Run the stage-specific internal review gate (Step 7a); apply fixes, push, repeat until clean |
| Draft PR open, internal review clean | PR is draft, internal review clean, external review not yet run | Run Step 7 (external automated reviewers) and Step 8 (CI), then mark PR as ready |
| PR open (non-draft), no readiness label | PR exists and latest push has not fully cleared | Run Step 7 and Step 8 until clean or escalated |
| PR labeled `needs-fixes` | Human or automated systems requested changes | Address feedback, push, then run Step 7a (if draft), Step 7, and Step 8 |
| PR labeled `ready-for-human-review` | — | Wait — human review / merge required |

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

| Stage action | Preferred execution path |
|---|---|
| Write spec | `product-manager` |
| Review spec | Native review against `REVIEW.md` or the compatibility wrapper `01-review-spec-protocol.md` |
| Write plan | `tech-lead` |
| Review plan | Native review against `REVIEW.md` or the compatibility wrapper `02-review-implementation-plan-protocol.md` |
| Implement feature | `developer` |
| Review code (post-draft-PR) | `code-reviewer` agent (Claude Code: `/code-review`); for other runners use compatibility wrapper `03-review-implementation-protocol.md` |

This protocol stays scoped to one item. It may call different stage agents over time, but it must not start scanning or dispatching unrelated items.

---

## Step 4: Execute and Re-evaluate

Run the next deterministic action for the selected item, then immediately re-evaluate the item state.

Expected chain:

`creator -> draft PR opened -> internal review gate (Step 7a) -> automated reviewer loop (Step 7) -> CI loop (Step 8) -> gh pr ready -> readiness label / tracker status -> wait or escalation`

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
- If labels indicate `needs-fixes`, enter the fix loop instead of reopening the stage from scratch

The Work Item Runner owns the full control loop for this item until it reaches a terminal condition.

---

## Step 6: Notify Humans

After the selected item reaches a terminal condition, provide a concise summary:

```markdown
## Work Item Runner Summary

- Item: [identifier]
- Final state: ready for human review / waiting on human decision / blocked / escalated
- Path taken: plan written -> reviewed -> PR opened -> automated review clean -> CI green
- Next human action: merge PR / answer architecture question / unblock dependency
```

---

## Step 7a: Internal Review Gate (Draft PR)

Run this step immediately after opening a draft PR, and again after any push that addresses internal-review findings.

Dispatch the stage-appropriate internal reviewer for the draft PR:

| PR branch prefix | Internal reviewer to dispatch |
|---|---|
| `spec/*` | `spec-reviewer` or `01-review-spec-protocol.md` |
| `implementation-plan/*` | `implementation-plan-reviewer` or `02-review-implementation-plan-protocol.md` |
| `feature/*` / `fix/*` / `hotfix/*` | `code-reviewer` or `03-review-implementation-protocol.md` |

The reviewer runs against `REVIEW.md`, applies deterministic fixes directly, and commits + pushes if needed.

| Outcome | Action |
|---|---|
| `APPROVED` | Continue to Step 7 (external automated reviewers) |
| `NEEDS REVISION` (fixable) | Fixes already applied by the agent; re-run Step 7a |
| `NEEDS REVISION` (product/design decision) | Stop and escalate to human before proceeding |

Step 7a runs **before** Step 7 (external reviewers). Only proceed to Step 7 once Step 7a produces `APPROVED`. After any fixer push triggered by Step 7 (external reviewers), re-run Step 7a to ensure the stage-specific internal review gate is still clean.

---

## Step 7: Automated Reviewer Loop

If one or more automated code review platforms are configured (see [`integrations/pr-review-platform.md`](../integrations/pr-review-platform.md)), run this loop after **any push to a PR branch**. If no review platform is configured, skip this step and report `⏭️ skipped` in the Step 6 summary.

**Standalone use:** This step (and Step 8) can be run for a single PR without full orchestration — see [`93-automated-reviewer-loop-protocol.md`](93-automated-reviewer-loop-protocol.md) and the `/run-reviewer-loop` command (Cursor) or `automated-reviewer-loop` agent (Claude Code) or `workflow-reviewer-loop` skill (Codex).

**Important:** Run Step 7 **to completion** and use its result before running Step 8. Do not run Step 7 in the background while proceeding to Step 8. The review loop can take several minutes (poll interval × wait for bot). Only when the script exits with `clean` or `skipped` may you continue to Step 8.

The helper script evaluates configured platforms sequentially. For each platform it checks for **existing** blocking findings from the bot (e.g. from a review that already ran on PR open) before posting a new trigger. If it finds any, it exits with `needs_fixes` without moving on to later platforms — so the fixer addresses them first; after a push, the next run starts again from the first configured platform.

Initialize `cycle = 0` once per orchestration run for the PR. Increment `cycle` each time a fixer agent is dispatched. Do not reset `cycle` after a fixer push; escalate when the run reaches `max_cycles`.

### PR feedback tracking and comments

Maintain a **PR feedback ledger** alongside the cycle counter. Each entry tracks:

| Field | Description |
|---|---|
| `id` | Sequential integer assigned in discovery order |
| `platform` | Review platform name (e.g. `greptile`, `devin`) |
| `path` | File path |
| `line` | Line number (display-only — can shift between commits) |
| `body_snippet` | First 120 chars of the finding body (used as matching key — line-shift-safe) |
| `discovered_cycle` | Cycle when first seen |
| `status` | `open` · `resolved` · `unresolved` |
| `resolved_commit` | Short SHA (set when resolved) |

**Matching key**: `(platform, path, body_snippet)` — not line number, since lines shift after fixes. If a finding looks like a restatement of existing open PR feedback (same platform, same file, similar description), match it rather than creating a duplicate.

**Ledger updates:**

- After each review run with `needs_fixes`: parse `BLOCKING_N_*` output, add new entries or leave existing open ones unchanged.
- After each fixer push + re-review: any open entry whose key no longer appears in the new output is marked `resolved` with the fixer's commit SHA.
- When the loop terminates: any still-open entry is marked `unresolved`.

#### Fix commit comment

Post via `gh pr comment` immediately after updating the ledger following a fixer push:

````markdown
### Automated Fix: commit `<short_sha>`

Addressed **N** finding(s) from cycle M:

| # | Platform | File | Description |
|---|----------|------|-------------|
| 1 | greptile | `src/foo.ts:42` | First 80 chars of body... |

<details><summary>Remaining open findings: K</summary>

| # | Platform | File | Description |
|---|----------|------|-------------|
| 3 | greptile | `src/baz.ts:5` | First 80 chars of body... |

</details>
````

If 0 findings were resolved: post a shorter note — "Pushed fixes for cycle M. 0 findings resolved so far — re-running review to check."

#### Final summary comment

Post via `gh pr comment` when the loop reaches a terminal condition (`clean`, `escalate`, or `max_cycles`):

````markdown
### Automated Reviewer Loop Summary

**Result:** clean | escalated (reason) | max cycles reached
**Cycles:** N / `max_cycles`
**Platforms:** greptile, devin

| # | Platform | File | Line | Description | Status | Resolved In |
|---|----------|------|------|-------------|--------|-------------|
| 1 | greptile | `src/foo.ts` | 42 | First 80 chars... | Resolved | `abc1234` |
| 2 | greptile | `src/baz.ts` | 5 | First 80 chars... | Unresolved | -- |

**Resolved:** 1 / 2 findings
````

- If no findings were ever raised (clean on first run): post a simpler comment — "No blocking PR feedback was raised by any configured reviewer tool."
- If result is `skipped` (no platforms configured): do **not** post a summary comment.

Prefer the helper script (it reads `.ai-dev-workflow.yaml` for the platform list automatically):

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

When an automated review platform returns inline comments, classify them before deciding whether the PR needs fixes.

- Treat a comment as a **soft suggestion** only when every non-empty, non-code line starts with an advisory prefix such as `Consider`, `You might`, `An alternative`, `Optionally`, `It could be cleaner to`, `Perhaps`, `Maybe`, `You could`, `One option is`, or `Alternatively`.
- Treat any other inline comment as **blocking**.
- Treat `CHANGES_REQUESTED` reviews from any automated reviewer as **blocking**. Treat `COMMENTED` reviews from Devin (identified by a `**Devin Review**` body prefix) as **blocking**; for other platforms, `COMMENTED` reviews are not automatically blocking.

Soft suggestions may be reported in summaries, but they do not change the loop result to `needs_fixes`. Any blocking finding does.

**Fixing agent by PR branch type:**

| PR branch prefix | Compatibility fixer to dispatch when direct fixes are needed |
|---|---|
| `spec/*` | `spec-reviewer` |
| `implementation-plan/*` | `implementation-plan-reviewer` |
| `feature/*` / `fix/*` / `hotfix/*` | `code-reviewer` |

### Loop parameters

| Parameter | Value | Description |
|---|---|---|
| `poll_interval` | 2 min | Time to wait between review status checks |
| `max_wait` | 20 min | Max wait **per fix cycle** for the reviewer to respond |
| `max_cycles` | 10 | Max number of times a fixing agent is dispatched before escalating |

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
| `green` | Run `gh pr ready <pr_number>` to convert the draft PR to ready; apply `ready-for-human-review`; update the tracker status to `Spec in Review`, `Plan in Review`, or `Implementation in Review` based on branch type; remove `needs-fixes` if present; and report the PR as ready |
| `red` | Apply `needs-fixes`, dispatch the matching fixer agent, wait for a push, then return to Step 7 |
| `timeout` | Escalate to human; do not apply `ready-for-human-review` |

---

## Step 9: Feedback Loop

When a human requests changes on a PR:

1. Remove `ready-for-human-review`
2. Add `needs-fixes`
3. Address the feedback
4. Push fixes
5. Run Step 7
6. Run Step 8
7. Reapply `ready-for-human-review` only when both loops are clean again

See `92-pr-readiness-signal-protocol.md` for label definitions.
