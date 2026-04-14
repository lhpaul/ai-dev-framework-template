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

When an issue tracker is configured in `.ai-dev-workflow.yaml`, **always query the tracker first** to get the item's current status before relying on VCS state. If the tracker is unavailable (API unreachable, no MCP server), **you MUST immediately warn the human** that status is being inferred from VCS and may be stale — do not silently proceed.

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands.

### Parallel batch indicator

**Check for a parallel batch context**: If this Work Item Runner was dispatched as part of a parallel batch by the Portfolio Orchestrator (`90-batch-orchestrate-work-protocol.md`), the handoff metadata will indicate `BATCH_CONTEXT=true`. Note this indicator; you will use it in Step 3 (Dispatch Strategy) to decide whether worktree isolation is required.

**Check for CHANGELOG skip signal**: If the handoff includes `SKIP_CHANGELOG=true`, this item is a non-last item in a parallel batch, and you **must not** update `CHANGELOG.md` during implementation. The last item in the batch will consolidate all CHANGELOG entries in a single commit. See Step 3 (Dispatch Strategy) for how to instruct stage agents to skip CHANGELOG updates.

Resolve the request to exactly one of the following:

1. **Backlog / tracker work item** — use when a human explicitly requests a not-yet-started item
2. **Development folder** — `docs/specs/developments/<timestamp>_<slug>`
3. **Workflow branch** — `spec/*`, `implementation-plan/*`, `feature/*`, `refactor/*`, `fix/*`, `hotfix/*`
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
- The script uses a VCS-level merged-PR check to distinguish `Plan Ready` (not yet started) from `Done` (branch merged and cleaned up). This is tracker-agnostic and requires only `gh`.
- The script **cannot** distinguish `Spec in Review` / `Plan in Review` from the corresponding merged state. If the target may still be waiting on a spec or plan PR merge, confirm the state via the issue tracker or by inspecting the workflow branch / PR directly before advancing.
- If `NEXT_ACTION=skip` is returned, the item is already done — do not redispatch.

When dispatching a subagent for this item, include a short “Tracker Work Item Summary” in the handoff:

- What the work item is asking for
- Any scope changes / decisions in recent comments
- Any ambiguity or conflict that still requires human confirmation

---

## Step 2: Determine the Next Deterministic Action

### What can advance now?

| Current state / detection | Can advance if... | Next action |
|---|---|---|
| Backlog (Feature) | Human has requested this specific item | Set tracker status to **Writing Spec**, then run `01-generate-spec-protocol.md` |
| Backlog (Refactor) | Human has requested this specific item as a Refactor | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md` (skip spec) |
| Writing Spec | Tracker **Writing Spec** — spec PR not yet human-ready | Continue spec branch/PR work (generate, internal review, reviewer tools, CI) until tracker moves to **Spec in Review** |
| Spec in Review | Tracker **Spec in Review** — spec PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Spec branch pushed, no PR yet | Branch exists on local / remote / worktree | Run the spec review gate via `REVIEW.md` / `01-review-spec-protocol.md`, open the PR, then finish PR readiness |
| Spec Ready | Spec PR is merged | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md` |
| Writing Plan | Tracker **Writing Plan** — plan PR not yet human-ready | Continue plan branch/PR work until tracker moves to **Plan in Review** |
| Plan in Review | Tracker **Plan in Review** — plan PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Plan branch pushed, no PR yet | Branch exists on local / remote / worktree | Run the plan review gate via `REVIEW.md` / `02-review-implementation-plan-protocol.md`, open the PR, then finish PR readiness |
| Plan Ready | Plan PR is merged | Set tracker status to **In Development**, then run `03-implement-development-protocol.md` |
| In Development | Tracker **In Development** — feature/fix PR not yet human-ready | Continue implementation branch/PR work (Step 7a, 7, 8) until tracker moves to **Development in Review** |
| Development in Review | Tracker **Development in Review** — feature/fix PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Dev branch pushed, no PR yet | Branch exists on local / remote / worktree | Open draft PR, run the internal review gate (Step 7a), run `gh pr ready` to convert to non-draft, then run automated reviewer loop (Step 7) and CI loop (Step 8) |
| Draft PR open, internal review pending | PR is draft and the relevant internal review gate has not run yet or has open findings | Run the stage-specific internal review gate (Step 7a); apply fixes, push, repeat until clean. Once APPROVED, run `gh pr ready` to convert to non-draft |
| Non-draft PR open, no readiness label, external review not yet run | PR is non-draft (converted after Step 7a APPROVED), external review not yet run | Run Step 7 (external automated reviewers) and Step 8 (CI) |
| PR open (non-draft), no readiness label | PR exists and latest push has not fully cleared | Run Step 7 and Step 8 until clean or escalated |
| PR labeled `needs-fixes` | Human or automated systems requested changes | Address feedback, push, then run Step 7a, Step 7, and Step 8 |
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
| Implement (Feature) | `feature/[slug]` |
| Implement (Refactor) | `refactor/[slug]` |

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

### Worktree isolation for parallel batches

**When dispatched as part of a parallel batch** (`BATCH_CONTEXT=true` in the handoff metadata):

1. **Create a dedicated worktree** for this item before executing any stage work. This ensures complete isolation from other concurrent Work Item Runners in the batch.

2. Determine the appropriate base branch for the worktree:

| Item type | Base branch |
|-----------|------------|
| Feature (`feature/`) | `origin/develop` |
| Refactor (`refactor/`) | `origin/develop` |
| Fast Track fix (`fix/`) | `origin/develop` |
| Hotfix (`hotfix/`) | `origin/main` |
| Spec (`spec/`) | `origin/develop` |
| Plan (`implementation-plan/`) | `origin/develop` |

**Note:** Use `origin/<base>` (remote tracking) rather than local `<base>` to avoid git worktree conflicts if the local base branch is already checked out elsewhere.

3. Create the worktree. The command depends on whether the item's branch already exists:

```bash
# Fetch latest remote refs first
git fetch origin

# Case A: New item — branch does not exist yet
git worktree add <worktree-path> -b <branch-prefix>/<slug> origin/<base-branch>

# Case B: Resuming item — branch exists locally
git worktree add <worktree-path> <branch-prefix>/<slug>

# Case C: Resuming item — branch exists only on remote
git worktree add <worktree-path> -b <branch-prefix>/<slug> origin/<branch-prefix>/<slug>

cd <worktree-path>
```

Use the pre-dispatch branch check from Step 2 (`git branch --list`, `git branch -r --list`) to determine which case applies. Case B and C are common when resuming "In Development" items, PRs with `needs-fixes`, or any item with prior work.

**Important — stage protocol compatibility**: When working inside a worktree created with this method, the stage protocol's initial branching steps (`git fetch origin`, `git checkout develop`, `git pull origin develop`, `git checkout -b ...`) are **already satisfied** by the worktree creation above. The stage agent should skip those steps and proceed directly to the implementation work. If the stage agent runs `git checkout develop` inside the worktree, it will fail because `develop` is already checked out in the main working tree and git prevents the same branch from being checked out in multiple worktrees simultaneously.

4. **Suggested worktree path**: `<repo-root>/.claude/worktrees/<item-id>/<branch-prefix>-<slug>` where `<item-id>` is the issue number, tracker ID, or slug.

5. After the item reaches a terminal condition, the cleanup script will remove the worktree:

```bash
# IMPORTANT: Change directory to the main repo root BEFORE deleting the worktree
cd <repo-root>
git worktree remove <worktree-path>
```

**Critical safety rule:** You **must** `cd` to the repository root or any other valid directory **before** executing `git worktree remove`. If the shell's current working directory (CWD) is inside the worktree being deleted, the directory will cease to exist immediately after `git worktree remove` completes. All subsequent bash commands will fail with "directory not found" errors, causing the orchestration to break and requiring manual intervention or agent re-delegation.

After removing the worktree, verify that the CWD is still valid by running a simple command like `pwd` before executing any further shell operations.

**When not in a parallel batch**: Worktree creation is optional but recommended for large development folders or long-running work. If not using a dedicated worktree, ensure the working directory is clean before proceeding.

This protocol stays scoped to one item. It may call different stage agents over time, but it must not start scanning or dispatching unrelated items.

### CHANGELOG skip signal for parallel batches

**When dispatching an implementation agent with `SKIP_CHANGELOG=true`** in the handoff metadata (non-last item in parallel batch):

1. **Before calling protocol 03** (`implement-development-protocol.md`) or any stage agent, extract the signal and pass it forward explicitly. If using a stage agent handoff (e.g., `developer` agent), include the signal in your handoff context as part of the Work Item Runner's instruction:

   ```
   Work Item Runner note: This is item [X] in a parallel batch. 
   Do NOT update CHANGELOG.md during this implementation.
   Protocol 90 Step 3.6 designates item [Y] (the last item) to consolidate 
   all batch CHANGELOG entries. Skip the CHANGELOG step in protocol 03 Step 6.
   ```

2. **When following protocol 03 directly** (not using a stage agent): At protocol 03 Step 6 (CHANGELOG update), add a pre-check:
   - If `SKIP_CHANGELOG=true` was in the handoff, skip Step 6 entirely and proceed directly to Step 7 (Commit & Push).
   - Document in the commit message or PR body that CHANGELOG is intentionally skipped (e.g., "CHANGELOG: skipped (non-last item in parallel batch per protocol 90 Step 3.6; consolidated by item Y)").

3. **Last item (consolidator)**: The last item in the batch (without `SKIP_CHANGELOG` in its handoff) implements normally and adds consolidated CHANGELOG entries for **all batch items** during protocol 03 Step 6. When dispatching the implementation agent for the last item, include the collected CHANGELOG descriptions from protocol 90 Step 3.6 point 3 in the handoff context:

   ```
   Work Item Runner note: This is the LAST item in a parallel batch.
   When updating CHANGELOG.md in Step 6, add consolidated entries for ALL 
   batch items (not just this one). Here are the entries to include:
   - [Item A]: [CHANGELOG description]
   - [Item B]: [CHANGELOG description]
   - [This item]: [write based on implementation]
   See protocol 90 Step 3.6 for details.
   ```

---

## Step 4: Execute and Re-evaluate

Run the next deterministic action for the selected item, then immediately re-evaluate the item state.

Expected chain:

`creator -> draft PR opened -> internal review gate with all internal reviewers (Step 7a) -> gh pr ready -> automated reviewer loop (Step 7) -> regression label (Step 7b, implementation PRs only) -> CI loop (Step 8) -> readiness label / tracker status -> wait or escalation`

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

**Retrospective suggestion (standalone runs only)**:

If this Work Item Runner was invoked **directly by a human** (i.e., `BATCH_CONTEXT` is not set or is `false`), after presenting the summary, suggest running a retrospective:

> Would you like to run a retrospective on this session's work?

If the human agrees, follow `docs/ai/development-workflow/protocols/06-retrospective-protocol.md`. The retrospective will analyze the PRs from this item run using both GitHub data and the conversation context from this session.

**When `BATCH_CONTEXT=true`** (dispatched by the Portfolio Orchestrator): suppress the retrospective suggestion. The Portfolio Orchestrator will suggest the retrospective at the end of its own Step 6 summary instead, covering the entire batch at once.

---

## Step 7a: Internal Review Gate (Draft PR)

Run this step immediately after opening a draft PR, and again after any push that addresses internal-review findings.

### Determining which reviewers to run

Read the `review.internal_reviewers` list from `.ai-dev-workflow.yaml`. If a `.tmp/template-config.json` file exists in the repository root (this path is gitignored and used for local developer overrides), read its `overrides.review.internal_reviewers` list — that value takes precedence over `.ai-dev-workflow.yaml` for the local environment. This allows developers without access to all configured review tools to run a subset (e.g., only `claude`) without changing the shared config.

Example `.tmp/template-config.json` override format:

```json
{
  "overrides": {
    "review": {
      "internal_reviewers": ["claude"]
    }
  }
}
```

If neither file defines `internal_reviewers`, fall back to running the stage-appropriate reviewer once (default behavior: `claude`).

### Reviewer dispatch map

For each reviewer in the resolved list, dispatch the stage-appropriate agent:

| Reviewer | PR branch prefix | Agent / protocol to dispatch |
|---|---|---|
| `claude` | `spec/*` | `spec-reviewer` or `01-review-spec-protocol.md` |
| `claude` | `implementation-plan/*` | `implementation-plan-reviewer` or `02-review-implementation-plan-protocol.md` |
| `claude` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `code-reviewer` or `03-review-implementation-protocol.md` |
| `codex` | `spec/*` | `workflow-spec-reviewer` Codex skill against `REVIEW.md` |
| `codex` | `implementation-plan/*` | `workflow-plan-reviewer` Codex skill against `REVIEW.md` |
| `codex` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `workflow-code-reviewer` Codex skill against `REVIEW.md` |

### Multi-reviewer execution rules

Run all configured internal reviewers **sequentially** in the order listed. Each reviewer runs against `REVIEW.md`, applies deterministic fixes directly, and commits + pushes if needed.

Initialize `internal_review_cycle = 0` at the start of Step 7a. Increment each time the full reviewer list is restarted. Escalate to human when `internal_review_cycle` reaches `max_internal_review_cycles` (default: 5).

| Outcome | Action |
|---|---|
| All reviewers `APPROVED` | Run `gh pr ready <pr_number>` to convert the draft PR to non-draft, then continue to Step 7 (external automated reviewers) |
| Any reviewer returns `NEEDS REVISION` (fixable) and `internal_review_cycle < max_internal_review_cycles` | Fixes already applied by the agent; increment `internal_review_cycle`; re-run **all** internal reviewers from the beginning of the list |
| Any reviewer returns `NEEDS REVISION` (fixable) and `internal_review_cycle >= max_internal_review_cycles` | Escalate to human — internal review is not converging |
| Any reviewer returns `NEEDS REVISION` (product/design decision) | Stop and escalate to human before proceeding |

All internal reviewers must APPROVE before `gh pr ready` is called. If any reviewer finds issues, fix them and re-run ALL internal reviewers.

### Step 7a loop parameters

| Parameter | Default | Description |
|---|---|---|
| `max_internal_review_cycles` | 5 | Max times the full internal reviewer list is restarted before escalating |

Step 7a runs **before** Step 7 (external reviewers). Only proceed to Step 7 once all internal reviewers in Step 7a produce `APPROVED`. After any fixer push triggered by Step 7 (external reviewers), re-run Step 7a (all internal reviewers) to ensure the stage-specific internal review gate is still clean.

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
| `clean` | Continue to Step 7b (implementation PRs) then Step 8 |
| `skipped` | Continue to Step 7b (implementation PRs) then Step 8 |
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
| `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `code-reviewer` |

### Loop parameters

| Parameter | Value | Description |
|---|---|---|
| `poll_interval` | 2 min | Time to wait between review status checks |
| `max_wait` | 20 min | Max wait **per fix cycle** for the reviewer to respond |
| `max_cycles` | 10 | Max number of times a fixing agent is dispatched before escalating |

---

## Step 7b: Regression Label (Implementation PRs Only)

After Step 7 completes with result `clean` or `skipped`, and **before** entering Step 8, apply the `ready-for-regression` label on implementation PRs to trigger label-gated e2e/regression CI checks.

**Applies to**: PRs on branches `feature/*`, `fix/*`, `hotfix/*`, `refactor/*`
**Does not apply to**: PRs on branches `spec/*`, `implementation-plan/*`

```bash
# Only for implementation PRs:
gh pr edit <pr_number> --add-label "ready-for-regression"
```

This label triggers the `e2e-regression.yml` workflow (or project-specific equivalents). Step 8's CI loop (`pr-ci-loop.sh`) will then naturally pick up the e2e check as part of its green/red polling via `statusCheckRollup`.

The `gh pr edit --add-label` command is idempotent — applying a label that already exists is a no-op. When the label is already present from a previous cycle, the `synchronize` event from the latest push will have already re-triggered the workflow.

Skip this step entirely for spec and plan PRs.

See [`integrations/e2e-regression.md`](../integrations/e2e-regression.md) for the full integration guide, including downstream customization.

---

## Step 8: CI Loop

**Only after Step 7 (and Step 7b for implementation PRs) has completed**, wait for required checks to settle.

Prefer the helper script:

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

Interpret the result as follows:

| Result | Action |
|---|---|
| `green` | Proceed to Step 8a (label readiness checklist) |
| `red` | Apply `needs-fixes`, dispatch the matching fixer agent, wait for a push, then return to Step 7 |
| `timeout` | Escalate to human; do not apply `ready-for-human-review` |

---

## Step 8a: Label Readiness Checklist (Hard Gate)

**Before applying `ready-for-human-review`**, verify all required readiness conditions are met. This is a hard gate — do not skip or defer.

Run this checklist for **every PR**:

```bash
PR_NUMBER=<pr_number>
BRANCH=<branch_name>  # e.g., feature/foo, spec/bar, fix/baz

# Determine PR type (implementation vs. spec/plan)
case "$BRANCH" in
  feature/*|fix/*|hotfix/*|refactor/*)
    IS_IMPLEMENTATION_PR=true
    ;;
  spec/*|implementation-plan/*)
    IS_IMPLEMENTATION_PR=false
    ;;
  *)
    IS_IMPLEMENTATION_PR=false
    ;;
esac

# Check 1: PR is non-draft
DRAFT=$(gh pr view "$PR_NUMBER" --json isDraft --jq '.isDraft')
if [ "$DRAFT" = "true" ]; then
  echo "ERROR: PR is still a draft. Run 'gh pr ready $PR_NUMBER' first."
  exit 1
fi

# Check 2: ready-for-regression label applied (implementation PRs only)
if [ "$IS_IMPLEMENTATION_PR" = "true" ]; then
  HAS_REGRESSION_LABEL=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-regression$" || true)
  if [ "$HAS_REGRESSION_LABEL" -eq 0 ]; then
    echo "ERROR: Implementation PR is missing 'ready-for-regression' label. Run Step 7b first."
    exit 1
  fi
fi

# Check 3: needs-fixes label must NOT be present (blocking gate)
HAS_NEEDS_FIXES=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^needs-fixes$" || true)
if [ "$HAS_NEEDS_FIXES" -gt 0 ]; then
  echo "ERROR: PR has 'needs-fixes' label. Address the findings, push fixes, and return to Step 7 before applying 'ready-for-human-review'."
  exit 1
fi

# Check 4: ready-for-human-review label NOT yet applied (we are about to apply it)
HAS_HUMAN_REVIEW_LABEL=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-human-review$" || true)
if [ "$HAS_HUMAN_REVIEW_LABEL" -gt 0 ]; then
  echo "INFO: PR already has 'ready-for-human-review' label. Skipping re-application."
else
  echo "Applying 'ready-for-human-review' label..."
  gh pr edit "$PR_NUMBER" --add-label "ready-for-human-review"
fi

echo "✅ Label readiness checklist passed. PR is ready for human review."
```

**Interpretation**:

- **All checks pass**: Continue to Step 8b (update tracker status) and report the PR as ready
- **Any check fails**: Stop and fix the condition. Do not apply `ready-for-human-review` until all checks pass
  - If `PR is still a draft`: Human error; run `gh pr ready <pr_number>` manually
  - If `missing ready-for-regression` on implementation PR: Re-run Step 7b, then re-check
  - If `needs-fixes` is present (Check 3 fails): Address the findings, push, return to Step 7 — `ready-for-human-review` is never applied while `needs-fixes` is active

This checklist ensures the label sequence is always complete before the PR is declared ready for human review.

---

## Step 8b: Update Tracker Status

After the label readiness checklist passes, update the tracker status to reflect the PR is waiting for human review:

- For **spec PRs** (`spec/*`): set tracker status to `Spec in Review`
- For **plan PRs** (`implementation-plan/*`): set tracker status to `Plan in Review`
- For **implementation PRs** (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`): set tracker status to `Development in Review`

See `docs/ai/development-workflow/integrations/github-projects.md` for tracker API details.

---

## Step 9: Feedback Loop

When a human requests changes on a PR:

1. Remove `ready-for-human-review`
2. Add `needs-fixes`
3. Address the feedback
4. Push fixes
5. Run Step 7a (internal review gate) — all internal reviewers must approve before proceeding
6. Run Step 7 (external automated reviewers)
7. Run Step 7b (implementation PRs only)
8. Run Step 8 (CI loop)
9. Run Step 8a (label readiness checklist) — this is **mandatory** to verify the PR is non-draft, `ready-for-regression` is applied on implementation PRs, and `ready-for-human-review` is applied
10. Run Step 8b (update tracker status)
11. Notify human that feedback has been addressed and the PR is ready again

See `92-pr-readiness-signal-protocol.md` for label definitions.

---

## Step 10: Post-Merge Status Transitions

When a human confirms that a PR has been merged, update the issue tracker and clean up local state according to this table:

| Merged PR branch type | Set tracker status to |
|---|---|
| `spec/*` | Spec Ready |
| `implementation-plan/*` | Plan Ready |
| `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` | Merged |

**Key rules:**

- When a spec or plan PR is merged, set the tracker status to the corresponding **Ready** status (`Spec Ready` or `Plan Ready`) — **not** `Merged`. Only implementation PRs (feature, fix, refactor, hotfix) go to `Merged`.
- The `/post-merge-cleanup` skill and `post-merge-cleanup` command follow this same table when updating tracker status.
- After updating the tracker, clean up local branches and worktrees associated with the merged PR:

```bash
git fetch origin
cd <repo-root>                          # CRITICAL: change to repo root before removing worktree (see Step 3)
git worktree remove <worktree-path>     # remove worktree first (branch is checked out there)
git branch -D <merged-branch>           # force-delete local branch (squash merges need -D)
```

If the item's tracker status is already in a further-advanced state (e.g., already `In Development` when a spec PR merges), do not roll it back — leave it as-is and only clean up local branches/worktrees.
