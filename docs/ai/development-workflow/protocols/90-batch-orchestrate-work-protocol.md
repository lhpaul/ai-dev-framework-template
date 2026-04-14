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

### 1a. Query the issue tracker (primary source of truth)

When an issue tracker is configured in `.ai-dev-workflow.yaml` (e.g., `issue_tracker.provider: linear`), it is the **primary and authoritative source** for which work items exist and their current status. **Always query the tracker first** — do not infer item status from development folders or git state alone, as those artifacts may be stale or incomplete.

From the tracker, collect for each open item:

- Current status (e.g., Backlog, Writing Spec, Spec Ready, Writing Plan, Plan Ready, In Development, In Review, Done)
- Due date, priority, dependencies, and latest brief/description
- Linked branch or PR identifiers (if the tracker stores them)

**Exclude** items whose tracker status is already `Done`, `Merged`, `Cancelled`, or equivalent — these are not candidates for advancement.

**If the tracker is unavailable** (no provider configured, API unreachable, or no MCP server available), **you MUST immediately warn the human** with a clear message such as:

> ⚠️ **Issue tracker unavailable** — could not reach the configured tracker (`<provider>`). Falling back to VCS-based status inference, which may be stale or inaccurate. Statuses shown below are best-effort only.

Do **not** silently proceed as if VCS-derived status is authoritative. After displaying the warning, fall back to the VCS-based discovery in Step 1b below.

### 1b. Enrich with VCS state (supplementary detail)

Use the helper scripts in `scripts/development-workflow/` for deterministic VCS state inspection:

```bash
./scripts/development-workflow/discover-workflow-state.sh
./scripts/development-workflow/workflow-batch-plan.sh
```

Use these helpers to gather detail on specific items:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

These scripts read from development folders (`docs/specs/developments/`), workflow branches, worktrees, and open PRs. Use their output to **enrich** tracker data with VCS-level detail (e.g., whether a branch exists, whether a PR is open, PR labels), but **do not use VCS-derived status to override the tracker status**. Development folders contain spec and plan documents but are not reliable indicators of item status — items may be completed, cancelled, or reorganized in the tracker without corresponding changes to these folders.

### 1c. Build the portfolio map

Combine tracker and VCS data into a portfolio map of:

- Backlog items that a human explicitly requested to start
- Work items in **Writing Spec** / **Writing Plan** / **In Development** (PR not yet human-ready), or branches/PRs still in PR-readiness loops
- Work items in **Spec in Review** / **Plan in Review** / **Development in Review**, or PRs labeled `ready-for-human-review` (human merge queue unless `needs-fixes`)
- Items that are **Spec Ready** or **Plan Ready** per the tracker
- Branches that were pushed but still have no PR
- PRs that still need readiness work or fix loops

---

## Step 2: Determine Eligibility and Priority

### What can advance now?

Use the **tracker status** as the canonical state for each item. VCS signals (branch existence, PR labels) provide supplementary detail but do not override the tracker. When no tracker is configured, fall back to VCS-derived status.

| Portfolio item state (per tracker) | Can advance if... | Dispatch target |
|---|---|---|
| Backlog (Feature) | Human explicitly requested it | Work Item Runner on the tracker item / brief (starts at spec stage) |
| Backlog (Refactor) | Human explicitly requested it as a Refactor | Work Item Runner on the tracker item / brief (starts at plan stage, skips spec) |
| Writing Spec | Tracker **Writing Spec**; spec PR not yet human-ready | Work Item Runner on the tracker item / branch / PR |
| Writing Plan | Tracker **Writing Plan**; plan PR not yet human-ready | Work Item Runner on the tracker item / branch / PR |
| In Development | Tracker **In Development**; feature/fix PR not yet human-ready | Work Item Runner on the tracker item / branch / PR |
| Spec Ready | Tracker **Spec Ready** | Work Item Runner on the development folder |
| Plan Ready | Tracker **Plan Ready** | Work Item Runner on the development folder |
| Pushed workflow branch, no PR yet | Branch exists on local/remote/worktree (VCS supplementary) | Work Item Runner on the branch |
| PR open, no readiness label | PR exists and latest push has not fully cleared (VCS supplementary) | Work Item Runner on the PR |
| PR labeled `needs-fixes` | Human or automated systems requested changes (VCS supplementary) | Work Item Runner on the PR |
| Spec in Review / Plan in Review / Development in Review or `ready-for-human-review` | — | Wait; do not redispatch (unless human feedback requires a fix loop) |

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
- `BATCH_CONTEXT=true` — required for parallel batches so the Work Item Runner (protocol 91) activates worktree isolation
- `SKIP_CHANGELOG=true` — for all non-last items in parallel batches that touch implementation; omit for last item so it consolidates CHANGELOG entries (see Step 3.6)

### Worktree isolation requirement

**When batching items for parallel dispatch**: Each item in a parallel batch **must** run in its own isolated worktree (or checked-out copy) to prevent branch contamination, PR cross-pollution, and shared-state conflicts between concurrent agents.

Do **not** dispatch multiple Work Item Runners to operate in the same working directory.

---

## Step 3.5: Pre-Flight Worktree Check (Parallel Batches Only)

Before dispatching a parallel batch, validate that each item can be isolated.

For each item in the batch:

```bash
# Check if the item's branch already has a worktree
git worktree list | grep -F "<branch-name>"

# If no match, the pre-flight check passes for this item.
# The Work Item Runner (Step 4, protocol 91) will create the worktree.

# If a match is found and points to an active worktree:
# - If the worktree is on the same branch and clean, it is safe to reuse
# - If the worktree is on a different branch or dirty, the pre-flight fails
```

**Failure handling**:

If the pre-flight check finds an active worktree on a conflicting branch or in a dirty state:

1. Stop the batch dispatch
2. Report to the human which item(s) have conflicting worktrees
3. Ask the human to either:
   - Remove the conflicting worktree (`git worktree remove <path>`)
   - Or manually run the item serially after the batch completes

Proceed with batch dispatch only when all pre-flight checks pass.

---

## Step 3.6: CHANGELOG Conflict Mitigation for Parallel Batches

When multiple PRs in a parallel batch touch `CHANGELOG.md`, merge conflicts are inevitable: the first PR to merge will update the `[Unreleased]` section, causing subsequent merges to fail on merge conflicts until they manually rebase or re-resolve.

### Strategy: Only the Last-Merged Item in a Batch Updates CHANGELOG

To prevent cascading CHANGELOG conflicts, only the **last item to be merged in a parallel batch** should modify `CHANGELOG.md`. Other items in the batch **must not** touch the CHANGELOG.

**Implementation**:

1. **Identify which item will merge last** during this batch planning phase (Step 3). This is typically:
   - The item with the longest expected review/fix cycle (high complexity, many reviewers)
   - The item with the lowest priority (if review cycles are equal)
   - By default, the last item in the batch list if review complexity is similar

2. **Instruct Work Item Runners** (when dispatching in Step 4):
   - For all items **except the last**: Pass `SKIP_CHANGELOG=true` in the handoff metadata so the implementation phase skips adding CHANGELOG entries
   - For the last item only: Implement and add CHANGELOG entries for **all work in the batch** in a single consolidated commit

3. **Collect CHANGELOG descriptions** from earlier items:
   - As each non-last item's PR reaches `ready-for-human-review`, the Work Item Runner or human can post a comment with the intended CHANGELOG entry text
   - Document these in a consolidated list accessible to the last item's orchestrator (e.g., a summary comment on the PR dashboard or in the orchestrator's context)

4. **Last item's CHANGELOG consolidation**:
   - When the last item reaches implementation, gather the CHANGELOG descriptions from all batch items
   - Add all entries under the appropriate section (Added, Changed, Fixed, etc.) in a single commit on the last item's branch
   - Use consistent wording and avoid duplication

### Special Cases

**Spec-only or plan-only PRs**: These are exempt from CHANGELOG updates per the project's changelog policy (`docs/best-practices/2-version-control.md`). Spec and plan PRs do not trigger the conflict problem because they do not modify CHANGELOG at all.

**Hotfixes**: Hotfixes require a new CHANGELOG entry immediately (they fix released code). If multiple hotfixes are in the same batch:
- Apply the same "last item" strategy above
- Or serialize the hotfixes (run them sequentially) to avoid conflicts

**Single item in batch**: If a batch has only one implementation item, it updates CHANGELOG normally.

### Example Batch Scenario

**Parallel batch**: Feature A (spec + plan + implementation), Feature B (spec + plan + implementation), Fix C (implementation)

1. **Dispatch phase** notifies:
   - Feature A: skip CHANGELOG during implementation
   - Feature B: skip CHANGELOG during implementation
   - Fix C (last item): will consolidate CHANGELOG for all three items

2. **Execution phase**:
   - Features A and B implement without touching CHANGELOG.md; push PRs marked `ready-for-human-review`
   - Fix C implements, and before reaching `ready-for-human-review`, adds a single consolidated CHANGELOG entry for all three items:
     ```markdown
     - **Feature A**: [description]
     - **Feature B**: [description]
     - **Fix C**: [incident/reason] 
     ```

3. **Merge phase**:
   - Features A and B merge cleanly (no CHANGELOG conflict)
   - Fix C merges last with the consolidated CHANGELOG entry

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

1. **Re-check tracker status first** when an issue tracker is configured — query the tracker for the item's current status before consulting VCS state. Do not rely solely on `workflow-next-action.sh` to determine whether an item should advance, as VCS-derived status cannot reliably distinguish certain states (e.g., a spec PR awaiting review vs. one already merged). Use `workflow-next-action.sh` only for VCS-level enrichment (branch existence, PR labels) after the tracker status is known.
2. If the tracker is unavailable, fall back to `workflow-next-action.sh` but flag to the human that status may be stale.
3. If the next action is still deterministic because the Work Item Runner returned early or was interrupted, redispatch / resume that same item.
4. Stop supervising that item only when it is waiting on a human, blocked, or escalated.
5. **When a human confirms PRs have been merged**: run post-merge status transitions per the table in Step 10 of `91-orchestrate-work-protocol.md` — set tracker status to `Spec Ready`, `Plan Ready`, or `Merged` depending on the branch type of the merged PR — and clean up local branches and worktrees associated with the merged PRs.

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

After presenting the summary, suggest running a retrospective:

> Would you like to run a retrospective on this session's work?

If the human agrees, follow `docs/ai/development-workflow/protocols/06-retrospective-protocol.md`. The retrospective will analyze the PRs from this batch using both GitHub data and the conversation context from this session.
