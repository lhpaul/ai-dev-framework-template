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

**Cross-check merged PRs**: Tracker statuses can be stale (e.g., a prior batch merged PRs but never updated the tracker). Before accepting a tracker status as authoritative, cross-check each candidate item against merged PRs:

```bash
# For each candidate issue number, check if a merged PR already exists
gh pr list --state merged --limit 1000 --search "<issue-number>" --json number,title,headRefName \
  --jq ".[] | select(.headRefName | test(\"/<issue-number>($|-)\"))"
```

If a merged PR is found for an item whose tracker status is not already terminal:
1. Inspect the `headRefName` of the merged PR to determine its branch type
2. Apply the appropriate status transition per Step 10 of `91-orchestrate-work-protocol.md`:
   - `spec/*` → Set tracker status to `Spec Ready`
   - `implementation-plan/*` → Set tracker status to `Plan Ready`
   - `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` → Set tracker status to `Merged`
3. Close the issue **only if it was an implementation branch** (feature/fix/refactor/hotfix)
4. Exclude the item from the candidate list **only if it was an implementation branch** (a merged spec or plan PR means the item should advance to the next stage, not be excluded)
5. Report the stale status to the human: `⚠️ Issue #N was already merged (PR #M) but tracker showed [old_status]. Updated to [new_status].`

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

## Step 2.5: Pre-Dispatch Tracker Status Update

Before building parallel batches, update the tracker to reflect that eligible items are now actively being worked on. This step runs after Step 2 (eligibility determination) and before Step 3 (batch building).

### Purpose

Without this step, items remain in a stale tracker status (e.g., `Backlog`, `Spec Ready`, `Plan Ready`) while agents are already working on them. The Batch 3 retro identified this as a source of confusion for humans monitoring portfolio progress and for Work Item Runners that check tracker status when resuming.

### Procedure

For each item that passed the Step 2 eligibility check:

1. **Ensure the item is on the project board**: check whether the item already exists in the configured project board. If it is missing, add it. Log the result (`already present` / `added to board`).

2. **Update tracker status to the appropriate in-flight value** based on the next action that will be dispatched:

   | Next action to dispatch | Tracker status to set |
   |---|---|
   | Write Spec | `Writing Spec` |
   | Write Plan | `Writing Plan` |
   | Implement (feature/fix/refactor/hotfix branch) | `In Development` |
   | Resume in-progress stage (status already `Writing Spec`, `Writing Plan`, or `In Development`) | No change — skip |

   For resume items (the last row), the status is already correct — do not reset it. This keeps the update idempotent.

3. **Log each result** for transparency:

   ```text
   ✅ #N [slug]: already on board; status Writing Plan → no change (already in-flight)
   ✅ #M [slug]: added to board; status Plan Ready → In Development
   ✅ #K [slug]: already on board; status Backlog → Writing Plan
   ```

4. **Tracker unavailability**: if the tracker API is unreachable, log a warning and continue without blocking the batch — matching the "warn and fall back" pattern established in Steps 1a–1c.

### Ordering: updates first, then dispatch

All tracker status updates for the batch must complete **before** any Work Item Runner is dispatched. This ensures observers see the correct in-flight status from the moment work starts, not retroactively after the creator stage finishes.

### Routing: CLI vs. MCP

How to perform tracker updates depends on the configured `issue_tracker.provider` in `.ai-dev-workflow.yaml`:

- **GitHub Projects** (`provider: github_projects`): use `gh` CLI via Bash. No MCP server required. See `docs/workflow/development-workflow/integrations/github-projects.md` for ready-to-use CLI patterns.
- **Other providers** (Linear, Jira, etc.): use the configured MCP server. The Portfolio Orchestrator always has MCP access, so these updates can be performed directly here at Step 2.5.

### Orchestrator ownership of tracker transitions for non-CLI providers

For issue tracker providers where no CLI equivalent exists (e.g., Linear via MCP), subagent Work Item Runners **cannot** update tracker status because MCP servers are not available in subagent execution contexts. In these cases:

- The **Portfolio Orchestrator owns all tracker status transitions** for the batch — both pre-dispatch (this step) and post-readiness (the `Development in Review` / `Spec in Review` / `Plan in Review` transitions that happen after a PR reaches `ready-for-human-review`).
- Subagents will return a `TRACKER_UPDATE_REQUIRED:` line in their summary when they could not perform the update themselves (see Step 8b of `91-orchestrate-work-protocol.md`).
- After each Work Item Runner returns, the Portfolio Orchestrator must scan its summary for `TRACKER_UPDATE_REQUIRED:` lines and apply those transitions via MCP before moving on to the next item.

For GitHub Projects, subagents CAN perform their own Step 8b update via `gh` CLI, so the orchestrator does not need to collect and replay those transitions. The `TRACKER_UPDATE_REQUIRED:` pattern only arises for providers without CLI support.

See `docs/workflow/development-workflow/integrations/github-projects.md` for the tracker API details used to add items to the project board and update their status.

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

### Same-batch tool-fix ordering hazard

**Definition**: A **tool-fix item** is any work item whose spec or implementation plan document
references modifications to any of the following canonical workflow tool files (relative to the
repository root):

- `scripts/development-workflow/pr-review-loop.sh`
- `scripts/development-workflow/pr-ci-loop.sh`
- `scripts/development-workflow/batch-merge.sh`
- `scripts/development-workflow/post-merge-cleanup.sh`
- Any file matching `docs/workflow/development-workflow/protocols/*.md`
- `.ai-dev-workflow.yaml`

A **consumer item** is any non-tool-fix item in the same candidate batch that is not already
`ready-for-human-review` before batch dispatch begins.

**Detection sources**: `workflow-batch-plan.sh` emits `TOOL_FIX=yes|no|unknown` per item based
on spec/plan document evidence (delimiter-aware regex scan of all `*.md` files in the development
folder). The `TOOL_FIX_FILES=<comma-separated paths>` line is also emitted when `TOOL_FIX=yes`.
The orchestrator may additionally classify from tracker title/description. If tracker-derived
classification conflicts with script output (the script emits `TOOL_FIX=no` but the tracker
title or description references a file from the canonical tool list), the orchestrator takes
the **conservative path** and treats the item as a hazard candidate.

**`TOOL_FIX=unknown` handling**: `unknown` is emitted when no spec or plan document exists in
the development folder (e.g., the item is still in `Writing Spec` state). Treat `unknown` the
same as `yes` — apply the serialize-first strategy (conservative default). `TOOL_FIX_FILES` is
omitted when `TOOL_FIX` is `no` or `unknown`; parsers must treat a missing `TOOL_FIX_FILES` as
an empty set.

**Serialize-first rule**: When a tool-fix item and any consumer item appear in the same candidate
batch, the tool-fix item **must** be dispatched alone in its own serial sub-batch first. The
consumer items are held until the tool-fix PR is merged. After the tool-fix item reaches
`ready-for-human-review`, the orchestrator pauses and reports the situation to the human: the
tool-fix must be merged before the remaining consumer items are dispatched, because those items
may invoke the affected tool during their own PR readiness loops. The batch summary must identify
held consumer items and their reason (e.g., `held — pending tool-fix merge for item #N`).

**Multiple tool-fix items**: When two or more tool-fix items appear in the same candidate batch,
each is serialized into its own serial sub-batch dispatched one at a time before any consumer
item is dispatched. The ordering among multiple tool-fix items follows the standard priority
order — due date within 2 weeks (earliest first), then priority (Urgent → High → Normal → Low),
then creation date (earliest first) — mirroring the Step 2 priority rules.

**Already-waiting tool-fix**: If the tool-fix item is already `ready-for-human-review`, `Spec in
Review`, or `Plan in Review` (already waiting for merge) before batch dispatch, the orchestrator
reports it as a "pending tool-fix" blocker for the consumer items and holds those items without
redispatching the tool-fix item.

**Human override**: The orchestrator must **never** autonomously skip the serialize-first gate.
Only an explicit human instruction enables parallel dispatch when an ordering hazard has been
detected. When a human instructs override, the orchestrator logs the override and annotates the
batch summary with a warning: "Human override: tool-fix ordering hazard acknowledged for item
#N. Dispatching in parallel."

**Codex fallback**:

If the runner cannot execute multiple Work Item Runners concurrently, preserve the same batching decision but process that batch sequentially. Report the fallback explicitly in the summary.

For each item in the batch, prepare a short handoff:

- Item identifier: development path, branch, PR, or tracker ID
- Current brief / tracker summary
- Current next action
- Priority context
- Parallelization notes or serialization reason
- `BATCH_CONTEXT=true` — required for parallel batches so the Work Item Runner (protocol 91) activates worktree isolation
- Each item adds its own CHANGELOG entry as normal (see Step 3.6 for conflict resolution strategy)

### Worktree isolation requirement

**When batching items for parallel dispatch**: Each item in a parallel batch **must** run in its own isolated worktree (or checked-out copy) to prevent branch contamination, PR cross-pollution, and shared-state conflicts between concurrent agents.

Do **not** dispatch multiple Work Item Runners to operate in the same working directory.

---

## Step 3.5: Pre-Flight Worktree Check (Parallel Batches Only)

Before dispatching a parallel batch, validate that each item can be isolated.

For each item in the batch:

```bash
# Check if the item's branch already has a worktree (exact branch match)
git worktree list --porcelain \
  | awk '/^worktree / { wt=$2 } /^branch / { b=$2; sub("^refs/heads/","",b); if (b=="<branch-name>") print wt "\t" b }'

# If no output, the pre-flight check passes for this item.
# The Work Item Runner (Step 4, protocol 91) will create the worktree.

# If output is found and points to an active worktree, verify cleanliness:
# git -C <worktree-path> status --porcelain
# - If empty output (clean) and same branch: it is safe to reuse
# - If non-empty output (dirty) or on a different branch: the pre-flight fails
```

**Failure handling**:

If the pre-flight check finds an active worktree that is dirty or on a conflicting branch:

1. Stop the batch dispatch
2. Report to the human which item(s) have conflicting worktrees
3. Ask the human to either:
   - Remove the conflicting worktree (`git worktree remove <path>`)
   - Or manually run the item serially after the batch completes

Proceed with batch dispatch only when all pre-flight checks pass.

---

## Step 3.6: CHANGELOG Conflict Mitigation for Parallel Batches

When multiple PRs in a parallel batch touch `CHANGELOG.md`, merge conflicts are expected because they all add entries to the same `[Unreleased]` section.

### Strategy: Per-PR Entries with Batch-Merge Auto-Resolution

Each PR in a parallel batch adds its own CHANGELOG entry as normal during implementation. CHANGELOG merge conflicts are resolved at merge time by the batch-merge auto-resolution (protocol 94 Step 4.3), which combines entries from both sides without dropping any.

**Why not consolidate into a single PR?** External reviewers (e.g., Devin, CodeRabbit) enforce per-PR diff scope and will flag CHANGELOG entries for work not present in the PR's diff as phantom/incorrect entries. Additionally, agents do not reliably parse `SKIP_CHANGELOG` metadata. The batch-merge auto-resolution handles CHANGELOG conflicts cleanly, making consolidation unnecessary.

**Implementation**:

1. **Do not pass `SKIP_CHANGELOG`** in handoff metadata. Each item adds its own CHANGELOG entry per the standard protocol 03 rules.
2. **At merge time** (Step 5.5 or `/batch-merge`): the batch-merge protocol auto-resolves CHANGELOG conflicts by combining entries from both `HEAD` and the incoming branch. No entries are dropped.
3. **If batch-merge is not used** (e.g., human merges manually): CHANGELOG conflicts are trivial to resolve — accept both sides' entries under the appropriate section.

### Special Cases

**Spec-only or plan-only PRs**: These are exempt from CHANGELOG updates per the project's changelog policy (`docs/best-practices/2-version-control.md`). Spec and plan PRs do not trigger the conflict problem because they do not modify CHANGELOG at all.

**Single item in batch**: If a batch has only one implementation item, it updates CHANGELOG normally (no conflict possible).

---

## Step 3.7: CodeRabbit Rate Limits in Parallel Batches

CodeRabbit enforces a per-hour rate limit on automated reviews. When multiple PRs are created within a short window (e.g., 3+ PRs within seconds of each other in a parallel batch), CodeRabbit may rate-limit reviews on some PRs and post a "rate limit" comment instead of a full review.

`pr-review-loop.sh` detects this automatically: when a rate-limit comment is found, it waits 3 minutes and retries with `@coderabbitai review` (up to 2 retries, configurable via `CODERABBIT_RATE_LIMIT_MAX_RETRIES` and `CODERABBIT_RATE_LIMIT_WAIT`). No manual intervention is needed in most cases.

If the retry budget is exhausted and no CodeRabbit inline review has appeared, `pr-review-loop.sh` first checks whether CodeRabbit posted a **SUCCESS commit-status context** for the current HEAD SHA (via `GET /repos/{owner}/{repo}/commits/{sha}/statuses`). During rate-limit windows, CodeRabbit sometimes signals a clean result via a commit status rather than an inline review comment. When a CodeRabbit `SUCCESS` commit-status is found, the script exits immediately with `RESULT=clean` and `REASON=coderabbit_status_success_fallback` — no human intervention is required and the PR advances to the CI loop normally. The fallback reason is included in the automated reviewer loop summary comment on the PR.

Only when no SUCCESS commit-status is found does the script fall through to stale-findings recovery, which may yield `RESULT=skipped` / `REASON=no_review`. The PR can still advance to `ready-for-human-review` in that case as well. When all PRs in the batch reach their individual reviewer-loop terminal states, Step 5.3 re-triggers CodeRabbit on any PR whose reviewer loop summary indicates `skipped (no_review)` for CodeRabbit and re-runs the reviewer loop for those PRs before the batch is declared complete.

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

## Step 4.1: Subagent Permission-Denial Detection and Inline Fallback

After each Work Item Runner subagent returns, check its output for permission-denial signals before proceeding to Step 5 supervision.

### Detection (AC1)

Check whether the subagent output contains the substring `SUBAGENT_PERMISSION_DENIAL:`. If it does:

1. Extract the denied tool name(s) from the message.
2. Log: `[PERMISSION_DENIAL] Item #N: subagent denied access to [tools]. Switching to inline execution.`

### No-redispatch rule (AC1)

Do **not** redispatch the same subagent for the same item in the same batch run. The inline fallback is the only recovery path.

### Inline fallback (AC2)

Execute the item from the main session. If the worktree was already created during dispatch, use that path. If the denial occurred before the worktree was created (early preflight failure in Protocol 91 Step 3.5), create it first:

```bash
git worktree add <path> <branch>
```

Re-evaluate item state from scratch:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch <branch-name>
```

Do not assume any progress from the failed subagent — treat the item as if newly dispatched. Follow `91-orchestrate-work-protocol.md` inline from the current session for the re-evaluated action.

### Batch summary entry (AC3)

In the final batch summary (Step 6), mark the item with execution path `inline fallback (permission denial: [tools])` rather than `subagent`. The summary must distinguish items completed via subagent dispatch from items completed via inline fallback.

### Double-failure path (AC6)

If the inline fallback itself encounters a permission denial on any tool, mark the item as `blocked` in the batch summary and notify the human:

```text
[BLOCKED] Item #N: both subagent and inline fallback were denied [DENIED_TOOL] access. Human intervention required.
```

Do not retry further. Do not loop.

### No `needs-fixes` label on permission failures

A permission denial is an **infrastructure failure**, not a content failure. Do **not** apply `needs-fixes` on any permission-denial path, including the double-failure path above.

---

## Step 5: Supervise Until Terminal

The Portfolio Orchestrator remains responsible for the batch after dispatch.

After a Work Item Runner returns:

1. **Re-check tracker status first** when an issue tracker is configured — query the tracker for the item's current status before consulting VCS state. Do not rely solely on `workflow-next-action.sh` to determine whether an item should advance, as VCS-derived status cannot reliably distinguish certain states (e.g., a spec PR awaiting review vs. one already merged). Use `workflow-next-action.sh` only for VCS-level enrichment (branch existence, PR labels) after the tracker status is known.
2. If the tracker is unavailable, fall back to `workflow-next-action.sh` but flag to the human that status may be stale.
3. If the next action is still deterministic because the Work Item Runner returned early or was interrupted, redispatch / resume that same item.
4. Stop supervising that item only when it is waiting on a human, blocked, or escalated.
5. **Collect deferred tracker transitions**: scan the Work Item Runner's summary for any `TRACKER_UPDATE_REQUIRED:` lines. These are transitions that the subagent could not perform (e.g., because the provider requires MCP and MCP is not available in the subagent context). Apply each deferred transition now via MCP before moving on to the next item. For GitHub Projects, subagents use `gh` CLI directly and do not emit `TRACKER_UPDATE_REQUIRED:` — this step only applies to providers without CLI support (e.g., Linear).
6. **When a human confirms PRs have been merged**: run post-merge status transitions per the table in Step 10 of `91-orchestrate-work-protocol.md` — set tracker status to `Spec Ready`, `Plan Ready`, or `Merged` depending on the branch type of the merged PR — and clean up local branches and worktrees associated with the merged PRs.

### Step 5.1: Post-Dispatch PR Verification

Before reporting any PR as ready for human review, **independently verify the actual PR state** via `gh pr view`. Do not trust Work Item Runner self-reports alone. Run this check for every PR that a Work Item Runner reports as ready:

```bash
gh pr view <pr_number> --json baseRefName,isDraft,labels,statusCheckRollup,comments
```

For the `reviewThreads` resolution check, `gh pr view --json` does not expose `reviewThreads`; use the GraphQL API directly:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$number) {
        reviewThreads(first: 100) {
          nodes { isResolved comments(first: 1) { nodes { author { login } } } }
        }
      }
    }
  }' -F owner=<owner> -F repo=<repo> -F number=<pr_number>
```

Verify all of the following. If any check fails, the PR is **not ready** — treat it the same as `needs-fixes` and return the item to active supervision:

| Check | Pass condition |
|---|---|
| Base branch | `develop` for `feature/*`, `fix/*`, `refactor/*`, `spec/*`, `implementation-plan/*`; `main` for `hotfix/*` |
| PR is non-draft | `isDraft: false` |
| `ready-for-human-review` label | Present |
| `ready-for-regression` label | Present on `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` PRs; not required for `spec/*`, `implementation-plan/*` |
| No `needs-fixes` label | Absent |
| All automated-reviewer `reviewThreads` resolved | GraphQL `reviewThreads.nodes[].isResolved=true` (or `✅ Addressed` in body) for every thread authored by a configured bot login (skip this check only when Step 7 was `skipped` because no review platforms are configured) |
| Automated reviewer loop summary comment | At least one PR comment containing "Automated Reviewer Loop Summary", "Reviewer Loop Summary", or "No blocking PR feedback" (skip this check only when Step 7 was `skipped` because no review platforms are configured) |
| CI checks | All required status checks are green (`state: SUCCESS` or `conclusion: success`) |

If a check fails:

1. Log the specific failure in your retrospective notes (see "Retrospective notes during supervision" below).
2. Remove `ready-for-human-review` if it is present: `gh pr edit <pr_number> --remove-label "ready-for-human-review"`.
3. Add the `needs-fixes` label to the PR: `gh pr edit <pr_number> --add-label "needs-fixes"`.
4. Redispatch / resume the Work Item Runner for that item to address the gap.
5. Re-run this verification after the next Work Item Runner return.

Do not consider the batch complete until every dispatched item has reached a real terminal condition.

#### Stale / Incomplete PR Detection

A PR may appear "almost ready" — non-draft, with readiness labels applied — but actually be in an incomplete state because the agent timed out before finishing Step 7 (external automated reviewers). The canonical detection heuristic depends on PR type:

**Implementation PRs** (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`):
> non-draft + `ready-for-regression` present + no reviewer loop summary comment = incomplete run

**Spec/plan PRs** (`spec/*`, `implementation-plan/*`):
> non-draft + `ready-for-human-review` present + no reviewer loop summary comment = incomplete run

The reviewer loop summary comment is the only reliable indicator that Step 7 ran to completion. `ready-for-human-review` alone is NOT a reliable completion signal. This check applies only when review platforms are configured — skip it for repos where Step 7 is `skipped` (no platforms configured).

**Pre-label orphaned PR** (early timeout — applies to all PR types):

A distinct failure mode occurs when an agent times out so early that it never reaches the post-review labeling steps. The PR is left non-draft but has **no** `ready-for-human-review` label, **no** `ready-for-regression` label (for implementation PRs), and **no** reviewer loop summary comment. This looks identical to a freshly-opened, unreviewed PR and is invisible to the label-presence heuristics above.

> non-draft + no `ready-for-human-review` + no `ready-for-regression` (implementation PRs) + no reviewer loop summary comment = pre-label orphaned run

Treat any non-draft PR on a workflow branch (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `spec/*`, `implementation-plan/*`) that belongs to a known in-flight item and has none of the above signals as a pre-label orphaned run. Do not assume it is a fresh PR that has not yet entered the reviewer loop.

Use this command to detect the incomplete state for a specific PR:

```bash
gh pr view <pr_number> --json isDraft,labels,comments \
  --jq '{
    isDraft: .isDraft,
    hasRegressionLabel: ([.labels[].name] | any(. == "ready-for-regression")),
    hasReadyLabel: ([.labels[].name] | any(. == "ready-for-human-review")),
    hasReviewSummary: ([.comments[].body] | any(test("Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback")))
  }'
```

**Classification table** (evaluate in order; first matching row wins):

| `isDraft` | `hasRegressionLabel` | `hasReadyLabel` | `hasReviewSummary` | Classification |
|---|---|---|---|---|
| `true` | any | any | any | Draft PR — run Step 7a and convert to non-draft |
| `false` | `true` | any | `false` | Incomplete run (post-regression, pre-Step-7) |
| `false` | any | `true` | `false` | Incomplete run (post-label, pre-Step-7) |
| `false` | `false` | `false` | `false` | **Pre-label orphaned run** — treat as incomplete |
| `false` | `true` | `false` | `true` | Incomplete run (post-regression, post-summary, pre-ready-label) — apply `ready-for-human-review` label, then proceed to Step 5.1 |
| `false` | any | `true` | `true` | Ready (proceed to Step 5.1 full verification) |

For the pre-label orphaned case (`isDraft=false`, no labels, no summary): the PR is not a fresh PR awaiting first dispatch — it is an orphaned in-progress run. Treat it the same as other incomplete states and redispatch the Work Item Runner to resume from Step 7a.

**Expected action when incomplete state is detected**:

1. Log the incomplete PR in your retrospective notes.
2. Remove `ready-for-human-review` if present: `gh pr edit <pr_number> --remove-label "ready-for-human-review"`.
3. Add `needs-fixes`: `gh pr edit <pr_number> --add-label "needs-fixes"`.
4. Redispatch the Work Item Runner with a resume hint to pick up from Step 7a (internal review gate).

This pattern also applies to PRs where an agent timed out mid-CI-loop: detect via `statusCheckRollup` entries in `ERROR` state, or `PENDING` state that has exceeded the configured max-wait threshold (see `pr-ci-loop.sh` timeout), and re-dispatch accordingly. Do not treat `PENDING` alone as a timeout signal — CI checks that are legitimately running will show as `PENDING` until they complete.

### Step 5.2: Post-Agent Main Working Tree Verification (Parallel Batches Only)

**Timing**: Run this check immediately after each Work Item Runner returns — **before** Step 5.1 (PR verification), before dispatching the next Work Item Runner, and before any orchestrator action that assumes the integration branch context (e.g., invoking batch-merge, pushing to `develop`). A leaked branch state in the main working tree can silently corrupt subsequent operations if not caught here.

After each Work Item Runner returns in a **parallel batch**, immediately check the main working tree's branch and cleanliness. Handle all four postcondition states:

```bash
INTEGRATION_BRANCH="develop"  # or read from .ai-dev-workflow.yaml integration_branch field
MAIN_BRANCH=$(git -C <main-repo-root> rev-parse --abbrev-ref HEAD)
MAIN_STATUS=$(git -C <main-repo-root> status --porcelain)

if [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
  # Case 1: Wrong branch + clean — auto-correct
  echo "GUARDRAIL: main working tree was on '$MAIN_BRANCH' after agent for item <item-id> returned. Expected '$INTEGRATION_BRANCH'. Auto-correcting."
  echo "Record as guardrail violation in retrospective notes: item <item-id> left main tree on wrong branch."
  git -C <main-repo-root> switch "$INTEGRATION_BRANCH"
  # Proceed normally after correction

elif [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
  # Case 2: Wrong branch + dirty — halt and escalate
  echo "ERROR: main working tree is on '$MAIN_BRANCH' (expected '$INTEGRATION_BRANCH') AND has uncommitted modifications after agent for item <item-id> returned."
  echo "$MAIN_STATUS"
  echo "Do not dispatch additional agents. Report to the human: the main working tree has leaked branch state and uncommitted changes. The human must inspect, discard or commit these changes, and restore the main tree to '$INTEGRATION_BRANCH' before resuming the batch."
  exit 1

elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
  # Case 3: Correct branch + clean — proceed normally
  :

elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
  # Case 4: Correct branch + dirty — halt and escalate
  echo "WARNING: main working tree is on '$INTEGRATION_BRANCH' but has uncommitted modifications after agent for item <item-id> returned:"
  echo "$MAIN_STATUS"
  echo "Possible cause: a stage agent leaked file writes outside the worktree boundary. Do not discard these changes without human review. Do not dispatch additional agents until the human inspects and resolves these changes."
  exit 1
fi
```

**Postcondition state summary:**

| Main branch | Main cleanliness | Action |
|---|---|---|
| Wrong branch | Clean | Auto-correct: `git switch <integration-branch>`. Log as guardrail violation in retrospective notes — a wrong-branch + clean result typically means the agent ran in the main tree instead of its isolated worktree, or a stage protocol issued a branch-switching command that leaked out of the worktree boundary. Proceed normally after correction. |
| Wrong branch | Dirty | Halt and escalate. Log full `git status --porcelain` output and item ID. Do not dispatch additional agents. |
| Correct branch | Clean | Proceed normally. |
| Correct branch | Dirty | Halt and escalate. Log full `git status --porcelain` output and item ID. Do not dispatch additional agents. |

If the main working tree is clean and on the correct branch (Case 3), proceed normally with Step 5.1 (PR verification) and then with the next Work Item Runner dispatch if any remain in the batch.

### Retrospective notes during supervision

As you supervise the batch, **proactively save issues, human corrections, and anomalies to memory** (e.g., a `project_batchN_retro_notes.md` memory file) as they happen — do not wait until the retrospective to reconstruct what went wrong. Record:

- Which PR was affected
- What went wrong (wrong base branch, missing label, incomplete review loop, etc.)
- What the root cause was (agent skipped a step, protocol gap, timeout, etc.)
- Whether the human had to intervene and how

These notes feed directly into the post-merge retrospective and provide context that GitHub data alone cannot capture.

---

## Step 5.3: Post-Batch CodeRabbit Re-trigger (Parallel Batches Only)

**When to run**: After **all** Work Item Runners in a parallel batch have returned and Step 5.1 verification has completed for each PR. Run this step before Step 5.5 (batch-merge handoff).

**Purpose**: When CodeRabbit exhausts its per-hour rate-limit budget across a parallel batch, some PRs receive a `skipped (no_review)` outcome from the per-PR reviewer loop (Step 3.7). This step detects those PRs, re-triggers CodeRabbit on each, and re-runs the reviewer loop for any affected PR before the batch is declared complete. Without this step, PRs that silently skipped CodeRabbit would require the human to run a second reviewer loop manually.

### Detection

For each PR in the batch, inspect the "Automated Reviewer Loop Summary" comment posted by the orchestrator after the reviewer loop exits and look for a `skipped (no_review)` outcome associated with CodeRabbit. The canonical signal emitted by `pr-review-loop.sh` is `RESULT=skipped` paired with `REASON=no_review` (two separate key-value lines in the script output); in the summary comment table this appears as `skipped (no_review)` in the CodeRabbit row.

```bash
# Check whether a PR's reviewer loop summary indicates CodeRabbit skipped with no_review
gh pr view <pr_number> --json comments \
  --jq '[.comments[].body | select(test("Automated Reviewer Loop Summary"))] | last // ""' \
  | grep -qiE "REASON=no_review|skipped \(no_review\)"
```

If the command exits 0 (match found), the PR requires a CodeRabbit re-trigger.

### Re-trigger procedure

For each PR identified in the detection step:

1. **Remove `ready-for-human-review`** and **remove `ready-for-regression`** (if present — they will be re-applied after the re-triggered review passes):

   ```bash
   gh pr edit <pr_number> --remove-label "ready-for-human-review" --remove-label "ready-for-regression"
   ```

2. **Post `@coderabbitai review`** to request a fresh CodeRabbit review:

   ```bash
   gh pr comment <pr_number> --body "@coderabbitai review"
   ```

3. **Re-run the reviewer loop** for this PR:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

4. **Re-apply labels and run Step 5.1 verification** (same as the standard post-reviewer-loop flow in Step 5):
   - If the re-triggered loop exits `clean`: apply `ready-for-regression` (Step 7b), run `pr-ci-loop.sh` (Step 8), run Step 8a label readiness checklist, and re-apply `ready-for-human-review`.
   - If the loop exits `needs_fixes`: dispatch the matching fixer agent and continue supervising this PR.
   - If the loop exits `escalate` or exhausts `max_cycles`: escalate to human and mark the PR as blocked in the batch summary.

### Skipping conditions

Skip Step 5.3 entirely when any of the following is true:

- CodeRabbit is not listed in `review.platforms` in `.ai-dev-workflow.yaml` — there is no CodeRabbit to re-trigger.
- The batch contained only a single PR — rate-limit budget exhaustion across a batch requires multiple concurrent PRs.
- No PR in the batch has a `skipped (no_review)` CodeRabbit signal in its reviewer loop summary — all PRs received a full or status-fallback review.

### Retry budget

The re-trigger uses the same `max_cycles` counter as the normal reviewer loop (Step 7). If a PR was already close to `max_cycles` during its initial run, count those cycles and do not exceed the limit during re-trigger. When the limit is reached, escalate to human.

---

## Step 5.5: Batch-Merge Handoff (Merge-Ready Parallel Batches)

When **all PRs in a parallel batch** have reached `ready-for-human-review`, the orchestrator may hand off to the batch-merge flow instead of leaving the human to merge manually.

### When to activate this step

All of the following must be true:

- The batch was a **parallel implementation batch** (not a spec-only or plan-only batch).
- Every PR in the batch is labeled `ready-for-human-review`.
- No PR in the batch is labeled `needs-fixes`.

If any PR is still in progress or labeled `needs-fixes`, continue supervising (Step 5) until the condition is met or the item is blocked/escalated.

### How to hand off

1. **Prepare the merge plan**: collect the PR numbers for all batch PRs. Run discovery:

   ```bash
   ./scripts/development-workflow/batch-merge.sh discover --prs <num1,num2,...>
   ```

2. **Revalidate readiness from discovery output**:
   - If any PR returned `PR_READY_LABEL=false`, warn the human and require an explicit include-or-skip decision before proceeding. Remove any skipped PRs from the merge list and carry them forward as `skipped_not_ready` for the final summary. Do not proceed silently with any unready PR.
   - If any PR's `PR_LABELS` still contains `needs-fixes`, stop the handoff and return to Step 5 supervision for that PR. A `needs-fixes` PR must not be merged even if human supervision approved the batch earlier.

3. **Present the validated merge plan to the human** and require explicit approval before any merge starts. The human must confirm before the orchestrator invokes `94-batch-merge-protocol.md`.

4. **Once the human approves**, follow `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` starting from **Step 3.5** (the pre-merge clean-state check and sequential merge loop). The merge plan confirmation (Protocol 94 Step 3) has already been satisfied by Step 5.5.3 above, but Step 3.5 has **not** been satisfied and must still run. Pass only the approved ordered PR list after Step 5.5.2 filtering, and include skipped entries in the final summary.

5. **Include the batch-merge summary** (Step 5 of Protocol 94) in the orchestrator's Step 6 summary output.

### Batch-merge routing rule (mandatory)

When merging a parallel implementation batch, **always** invoke `batch-merge.sh discover --prs <list>` followed by execution of `94-batch-merge-protocol.md`. Direct `gh pr merge` calls are only acceptable for single-PR merges or non-implementation PRs (spec, plan). **Never** use `gh pr merge` individually for parallel implementation batches — it bypasses CHANGELOG auto-resolution (Protocol 94 Step 4.3) and active-worktree awareness.

| Merge scenario | Required tool |
|---|---|
| Parallel implementation batch (2+ PRs) | `batch-merge.sh` + Protocol 94 |
| Single implementation PR | `gh pr merge` is acceptable |
| Spec or plan PR (any count) | `gh pr merge` is acceptable |

Violating this rule causes CHANGELOG merge conflicts that must be resolved manually, as observed in the Batch 4 incident (2026-04-22).

### Governance note

The orchestrator prepares and validates the batch but **does not merge autonomously**. The human's explicit approval at Step 5.5 (above) is the required merge gate. This aligns with the policy in `2_batch-merge_implementation-plan.md`: "The agent executes `git merge` locally, but only after the human explicitly confirms the merge plan."

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

Do **not** suggest a retrospective at this point. The batch is not fully complete yet — PRs that are `ready-for-human-review` still need human review and merge before the work is done.

Instead, suggest the retrospective **after the human confirms the PRs have been merged** (e.g., after running `/batch-merge`, `/post-merge-cleanup`, or an explicit "they're merged" signal). At that point, offer:

> Would you like to run a retrospective on this batch's work?

If the human agrees, follow `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`. The retrospective will analyze the PRs from this batch using both GitHub data and the conversation context from this session.
