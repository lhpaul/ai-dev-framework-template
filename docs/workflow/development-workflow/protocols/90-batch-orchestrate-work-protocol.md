# Protocol: Orchestrate Portfolio Work

**Agent role**: Portfolio Orchestrator (`orchestrator`)
**Purpose**: Discover what can advance or be started across the portfolio, propose the largest safe batch that fits current priority and parallelization constraints, dispatch deterministic in-flight work through one Work Item Runner (`item-orchestrator`) per item, and supervise dispatched work until each item reaches a real terminal condition

This is a **supporting protocol**. It coordinates multiple workflow items but does not execute any creator or reviewer stage directly. Stage execution belongs to the Work Item Runner (`91-orchestrate-work-protocol.md`) and the stage-specific protocols it invokes.

Humans normally invoke this protocol when they want portfolio-wide advancement rather than targeting one known item directly.

---

## Overview

The Portfolio Orchestrator:

1. Reads the current state of backlog, in-flight development folders, workflow branches, and open PRs
2. Determines which items can safely advance now and which Backlog items can be proposed to start
3. Builds the largest safe batch possible, ordered by priority and constrained by dependencies, tool-fix ordering, and file-level parallelization risk
4. Dispatches one Work Item Runner per item for deterministic in-flight/resume work, or proposes the start batch for human approval when the batch contains new Backlog starts
5. Supervises dispatched work until every item is waiting on a human, blocked, or escalated

### Persistent orchestration contract

A single Portfolio Orchestrator run should keep advancing eligible items until each dispatched item reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- No dispatch-eligible work remains and no Backlog start batch can be proposed
- A largest safe Backlog start batch has been proposed and is waiting for explicit human approval

These are **not** terminal conditions and must not stop the run:

- A batch was merely identified
- Backlog items exist but were not evaluated into a proposed start batch
- A subagent finished one creator or reviewer subroutine
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting on CI or automated review
- One item in a batch finished while others are still running

### When to use this protocol

Use this protocol when the request is portfolio-wide or multi-item, for example:

- "What can advance right now?"
- "Run all work that can safely advance, and propose the next safe start batch"
- "Process everything that can move in parallel"

If the request is explicitly about a single development, branch, or PR, skip this protocol and use `91-orchestrate-work-protocol.md` directly.

---

## Routing Entrypoint

This protocol is entered from two paths:

- **From `/run-work`** (Protocol 96, `no_target_scan` mode): `/run-work` is
  scan-and-propose only. The orchestrator runs **Steps 1–3 only** (scan,
  assess, build batch proposal) and stops without dispatching any items. No
  tracker updates, branch creation, or PR operations occur. The batch proposal
  is presented to the operator; execution begins only when the operator invokes
  `/run-items` (or equivalent) with the recommended targets.
- **From `/run-items`** (Protocol 96, `explicit_list` mode, when implemented):
  Two or more explicit targets were supplied as a hard bounded scope; the
  orchestrator runs that exact bounded set through all steps including dispatch
  (Steps 4–5). When guardrails permit delegated merge, `/run-items` may continue
  after `ready-for-human-review` through Guardrails Enforcement Gate 5 and scoped
  Protocol 94 batch merge per `.agents/skills/run-items/SKILL.md` rule 10. The
  bounded-prelude confirmation recorded for that invocation is the merge gate;
  Step 5.5 below applies to batches proposed by `/run-work`, not to this
  explicit-list execution path.

When the routing mode is `redirect_item`, `redirect_epic`, or `redirect_items`,
`/run-work` performs **no mutation**. The classifier emits `REDIRECT_COMMAND`
pointing to the appropriate bounded command. Use those commands instead.

See `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
for the full routing specification.

---

## Step 0: Load Effective Guardrails

Before any tracker mutation, branch creation, PR operation, or Work Item Runner
dispatch, the Portfolio Orchestrator resolves and reports the **effective
guardrails** for this portfolio run.

See `docs/workflow/development-workflow/guardrails-enforcement.md` for the
complete resolution rules, the config-field → run-epic-policy mapping table,
the named stop conditions, and the audit-evidence rules. This section summarizes
the in-protocol obligations only.

### Resolution

Resolve the effective guardrails by layering three sources (lowest to highest
priority):

1. Repository configuration — the `guardrails` block in `.ai-dev-workflow.yaml`.
2. Session overrides — values set earlier in the same conversation.
3. Invocation overrides — flags supplied with the current invocation.

When no `guardrails` section is present, apply the conservative defaults: mode
`manual`, no delegated merge, backlog starts confirmation-gated. See section 7
of `guardrails-enforcement.md`.

If the `guardrails` block is present but unreadable or internally contradictory,
stop immediately with the `guardrails_config_unreadable` stop condition before
any mutation. See section 6 of `guardrails-enforcement.md`.

### Report in the Portfolio Run Summary

Before Step 1 (Gather Portfolio State), state the following in the run summary:

- Effective autonomy mode.
- Per-stage open/merge permissions (`may_open_pr`, `may_merge_pr`).
- Per-stage maximum merge risk (`max_merge_risk`).
- Backlog-start policy (`backlog_start.allow_without_confirmation`).
- Configured stop conditions.
- Audit requirements.
- Which values were changed by an invocation or session override (if any).

### Pass Effective Guardrails to Dispatched Work Item Runners

When dispatching a Work Item Runner (Step 3), include the portfolio-resolved
effective guardrails in the handoff metadata. Dispatched Work Item Runners
inherit the portfolio-resolved guardrails rather than re-resolving them
independently. Invocation and session overrides resolved at the portfolio level
flow down to the per-item gates without re-prompting.

Also include the portfolio-approved execution base for each dispatched item.
Nested or spawned agents must pass that base to
`run-nested-artifact-guard.sh --approved-base` before branch creation and before
PR creation. If the base is ambiguous, stop before dispatch rather than letting
a child agent infer a PR target.

The Portfolio Orchestrator also owns parent-visible fork enumeration. For each
dispatched item with a positive numeric issue number, run the nested artifact
guard in `audit` mode before child dispatch and again after the child returns
control:

```bash
./scripts/development-workflow/run-nested-artifact-guard.sh \
  --mode audit \
  --issue "$ISSUE_NUMBER" \
  --expected-branch "$EXPECTED_BRANCH" \
  --expected-worktree "$EXPECTED_WORKTREE" \
  --approved-base "$BASE_BRANCH" \
  --repo-root "$ARTIFACT_REPO_ROOT"
```

Use the repository root that owns the item artifacts. In `workflow_hub` mode,
implementation branches and PRs are product-owned, so `ARTIFACT_REPO_ROOT` must
be the selected product checkout; hub-owned spec and plan artifacts use the hub
checkout. Treat `RESULT=unexpected_fork`, `RESULT=wrong_base`,
`RESULT=missing_base`, and `RESULT=scan_failed` as parent-level blockers and
include the guard output in the batch summary.

### Backlog-Start Gate

Before proposing or starting any not-yet-started Backlog item (in Step 2 and
Step 2.5), apply the backlog-start gate:

- If `backlog_start.allow_without_confirmation` is `true` in the effective
  guardrails (or the effective mode is `autonomous`): the orchestrator may
  propose and start eligible Backlog items in the same run after presenting the
  batch to the human.
- Otherwise: the orchestrator must stop before starting any not-yet-started
  Backlog item and ask the human to confirm, naming the items proposed to start.
  In-flight items (any status other than Backlog) are not subject to this gate.

---

## Explicit Item List Scope Guard

**Hard-refuse rule**: When the Portfolio Orchestrator is dispatched with an explicit item list (e.g., `/run-work 143 148 145` or a handoff metadata field `ITEM_LIST=143,148,145`), it **must not** take any artifact-mutating action on items outside that list. This rule applies to **all** of the following artifact mutations:

- Branch creation
- PR opening, labeling, or editing
- Tracker status updates
- Subagent dispatch (Work Item Runner or stage agent)
- CHANGELOG edits

**Detection**: An explicit item list is present when the human invocation or handoff metadata includes a bounded set of issue numbers, tracker IDs, branch names, or PR numbers. An unrestricted invocation ("run everything that can advance") does **not** set the scope guard.

**Out-of-scope item detection**: While gathering portfolio state (Step 1) and during batch supervision (Step 5), if the orchestrator encounters any open PR, branch, or tracker item that is **not** in the explicit list:

1. **Do not touch it** — skip all artifact mutations for that item.
2. **Log a WARNING** (do not silently skip):

   ```text
   WARNING: out-of-scope item detected — [branch/PR/issue identifier] is not in the explicit item list [<list>]. Skipping all actions for this item.
   ```

3. Include all detected out-of-scope items in the Step 6 summary under a dedicated "Out-of-Scope Items Detected (Skipped)" section.

**Corollary — no opportunistic advancement**: When an explicit list is active, the orchestrator must not opportunistically advance an out-of-scope item even if it is clearly ready (e.g., a stale-status correction that would normally proceed automatically). Every such item gets the WARNING log and is skipped.

**Human override**: An explicit human instruction within the same session may expand the scope. The override must be stated explicitly (e.g., "also advance #329"). Log the override in the batch summary.

---

## Step 1: Gather Portfolio State

### 1a. Query the issue tracker (primary source of truth)

When an issue tracker is configured in `.ai-dev-workflow.yaml` (e.g., `issue_tracker.provider: linear`), it is the **primary and authoritative source** for which work items exist and their current status. **Always query the tracker first** — do not infer item status from development folders or git state alone, as those artifacts may be stale or incomplete.

From the tracker, collect for each open item:

- Current status (e.g., Backlog, Writing Spec, Spec Ready, Writing Plan, Plan Ready, In Development, In Review, Done)
- Due date, priority, dependencies, and latest brief/description
- Linked branch or PR identifiers (if the tracker stores them)

**Exclude** items whose tracker status is already `Done`, `Merged`, `Cancelled`, or equivalent — these are not candidates for advancement.

#### Rate-limit awareness for GitHub Projects pagination (Step 1a)

**Problem**: `gh project item-list --limit 10000` fetches all project board items — including closed and merged ones — in paginated GraphQL requests. Repositories with 300+ board items exhaust the 5 000-point GraphQL rate limit, causing a ~3.5-minute hard pause that grows worse as more items accumulate.

**Recommended approach — query open issues directly**:

Instead of paginating the full project board to discover candidates, first fetch all open issues
from the repository (which is state-filtered at the GitHub Issues API level and therefore fast),
then make a single `item-list` call to fetch all project board items and cross-reference them
against the open-issue list client-side:

```bash
# Step 1: list all open issues (only open issues are eligible for dispatch or start proposal)
OPEN_ISSUES=$(gh issue list --state open --limit 1000 --json number,title,labels,createdAt)

# Step 2: fetch all project board items once and filter to only open-issue candidates
gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 10000 --format json \
  | jq --argjson open "$OPEN_ISSUES" \
    '[.items[] | . as $item | ($open[] | select(.number == $item.content.number)) // empty | {number: .number, title: .title, status: $item.status}]'
```

This pattern avoids the need to call `item-list` once per open issue. A single `item-list` fetch
is unavoidable (GitHub Projects v2 has no server-side open-issue filter on the items node), but
by pre-filtering the candidate set to open GitHub Issues first, the downstream processing only
touches relevant items and the orchestrator does not spend query points scoring closed board entries.

**Alternative — client-side post-filter when item-list is unavoidable**:

If a full `item-list` call is unavoidable (e.g., to obtain project-specific field values not available from `gh issue list`), add a client-side filter to exclude terminal-status items immediately after fetching:

```bash
# Fetch all items but filter out terminal statuses client-side
gh project item-list "$PROJECT_NUMBER" --owner "$PROJECT_OWNER" --limit 10000 --format json \
  | jq '[.items[] | select(.status != null and (.status | IN("Done","Merged","Released","Cancelled")) | not)]'
```

This does not reduce the number of GraphQL pages fetched, but it reduces the size of the result set that downstream processing operates on. Prefer the open-issue query approach (above) to avoid the page-count problem entirely.

**Rate-limit check**: Before and after any large pagination operation, check remaining GraphQL quota:

```bash
gh api rate_limit --jq '.resources.graphql | {limit, remaining, used, reset: (.reset | todate)}'
```

If `remaining` falls below 1 000 points after Step 1a, warn the human before dispatching Work Item Runners:

```text
WARNING: GraphQL rate limit low after portfolio discovery — <N> points remaining (limit: 5000).
Further GraphQL calls (tracker updates, PR queries) may hit the limit and block for up to <reset-time>.
Consider waiting until the rate limit resets before dispatching the batch.
```

The rate limit resets once per hour. When `remaining` is critically low (< 200 points), pause dispatch and report the reset time to the human.

#### Linear provider (Step 1a)

When `issue_tracker.provider` is `linear`, the orchestrator is the only actor
with Linear access. Apply the following discovery flow instead of the GitHub
Projects pagination approach above:

0. **Resolve the project filter** — before querying, check whether
   `issue_tracker.custom_fields.project` is set in `.ai-dev-workflow.yaml`. If
   it is set, record the project ID and use it to scope all discovery queries to
   that project only (step 1 below). If it is absent, emit a visible warning and
   fall back to the unscoped team query:

   > **WARNING**: `issue_tracker.custom_fields.project` is not set in
   > `.ai-dev-workflow.yaml`. Linear item discovery will query all open items
   > visible to the API token, which may include items from other codebases or
   > projects. To restrict discovery to the correct project, set
   > `issue_tracker.custom_fields.project` to the Linear project ID for this
   > repository. See `docs/workflow/development-workflow/integrations/linear.md`
   > for setup instructions.

1. **Query Linear via MCP** — call the Linear MCP `issues` or `team.issues`
   query for open items. **When a project ID was resolved in step 0**, pass it
   as a project-scoped filter (e.g., `project: { id: { eq: "<project-id>" } }`)
   so only items belonging to the configured project are returned. When no
   project ID is available (fallback mode), query all open items in the
   configured team. For each item, collect: status (workflow stage label), type
   (Feature, Bug, Refactor), priority, parent epic (if applicable), and
   dependency relationships.

2. **Format item context** — for each item, record the status as a structured
   context value (`ITEM_STATUS=<status>`) that the batch-planning step can
   consume. For items whose status maps to a terminal stage (Merged, Released,
   Cancelled), exclude them from the candidate set immediately.

3. **Pass context to `workflow-batch-plan.sh`** — run the script for each
   development folder as usual. When the script emits a
   `TRACKER_STATUS_DEFERRED=<issue>` line, use the item's pre-resolved status
   from step 1 to determine the workflow stage instead of treating the item as
   unknown.

4. **Classify items** — apply the same stage-to-action mapping used for GitHub
   (e.g., `Plan Ready` → dispatch implementation). An item whose Linear status
   cannot be mapped must be reported as unclassifiable, not silently skipped.

**If Linear MCP is unavailable**: stop with a clear message such as:

> Linear tracker is configured but Linear MCP is not available. Portfolio
> discovery cannot proceed without Linear item status. Configure the Linear MCP
> server and re-run, or provide the item list manually.

Do not silently produce an empty plan.

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

When gathering VCS state, also collect the set of open `develop-<slug>` integration branches: `git branch -r | grep "^  origin/develop-"`. For each integration branch found, look up any issues labeled `integration-branch:<slug>` to match the branch to its epic. Record the integration branch name against each matching sub-item in the portfolio map.

#### Graduation eligibility check (AC-11, AC-12)

After collecting the set of open `develop-<slug>` branches, run a graduation eligibility check for each integration branch found (see `05b-graduate-development-protocol.md` for the full graduation ceremony):

1. For each `develop-<slug>` found, query all sub-items labeled `integration-branch:<slug>`:

   ```bash
   gh issue list --label "integration-branch:<slug>" --state all \
     --json number,title,state,labels \
     --jq '.[] | {number, title, state, labels: [.labels[].name]}'
   ```

2. Separate sub-items into **planned** (not explicitly deferred or cancelled — i.e., state is not `closed` with a cancellation label, and no `wont-do` or `deferred` label present) and **optional/deferred** (explicitly marked as lower-priority or not in scope for this graduation).

3. For each planned sub-item, check whether a merged implementation PR exists targeting `develop-<slug>`:

   ```bash
   gh pr list --state merged --base "develop-<slug>" \
     --json number,headRefName,mergedAt \
     --jq '[.[] | select(.headRefName | test("^(feature|fix|refactor)/<issue-number>(-|$)"))]'
   ```

4. **If all planned sub-items have merged implementation PRs**: mark the integration branch as **graduation-eligible** in the portfolio map.

5. **Surface the eligibility to the human** with the following information:
   - Integration branch name: `develop-<slug>`.
   - A bulleted list of all planned sub-items with issue number, title, and implementation PR number.
   - A note on any open optional/deferred sub-items that were not included.
   - A prompt: "This integration branch is eligible for graduation. Run `/graduate-development <slug>` (Protocol 05b) to proceed — graduation requires explicit human approval before any PR is opened."

6. **Do not auto-graduate** (AC-12): the Portfolio Orchestrator must not initiate the graduation ceremony autonomously. It surfaces the eligibility, then waits for the human to invoke `05b-graduate-development-protocol.md` explicitly. Graduation requires human approval (BR-1 of the graduation spec).

7. If graduation is not yet eligible (some planned sub-items have no merged PR), record the integration branch in the portfolio map with its current status (e.g., "2 of 4 planned sub-items merged") and report it as "graduation not yet eligible."

### 1c. Build the portfolio map

Combine tracker and VCS data into a portfolio map of:

- Backlog items that are candidates for a proposed start batch in unrestricted portfolio mode
- Backlog items that a human explicitly requested to start in targeted or explicit-list mode
- Work items in **Writing Spec** / **Writing Plan** / **In Development** (PR not yet human-ready), or branches/PRs still in PR-readiness loops
- Work items in **Spec in Review** / **Plan in Review** / **Development in Review**, or PRs labeled `ready-for-human-review` (human merge queue unless `needs-fixes`)
- Items that are **Spec Ready** or **Plan Ready** per the tracker
- Branches that were pushed but still have no PR
- PRs that still need readiness work or fix loops
- Integration branches (`develop-<slug>`) that are **graduation-eligible** (all planned sub-items merged) — human decision required; do not auto-graduate

---

## Step 2: Determine Eligibility and Priority

### What can advance now?

Use the **tracker status** as the canonical state for each item. VCS signals (branch existence, PR labels) provide supplementary detail but do not override the tracker. When no tracker is configured, fall back to VCS-derived status.

Unrestricted portfolio mode has two candidate classes:

- **Dispatch-eligible**: in-flight or resume work whose next deterministic action can proceed without a new human prioritization decision.
- **Proposal-eligible**: Backlog work that can be assembled into the largest safe start batch for human approval. Backlog items are not silently started unless the human explicitly named the item(s) or approves the proposed batch in the same session.

When no dispatch-eligible work exists, the orchestrator must still evaluate proposal-eligible Backlog items and present the largest safe start batch instead of reporting that no eligible work remains.

| Portfolio item state (per tracker)                                                  | Can advance if...                                                   | Dispatch target                                                                 |
| ----------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Backlog (Feature)                                                                   | Human explicitly requested it, or unrestricted portfolio mode is building a proposed start batch and tracker Type/brief classifies it as Feature | Work Item Runner on the tracker item / brief after approval (starts at spec stage) |
| Backlog (Bug)                                                                       | Human explicitly requested it as a bug / fast-track item, or unrestricted portfolio mode is building a proposed start batch and tracker Type/brief classifies it as Bug | Work Item Runner on the tracker item / brief after approval (starts at fast-track scope check) |
| Backlog (Refactor)                                                                  | Human explicitly requested it as a Refactor, or unrestricted portfolio mode is building a proposed start batch and tracker Type/brief classifies it as Refactor | Work Item Runner on the tracker item / brief after approval (starts at plan stage, skips spec) |
| Backlog (Workflow)                                                                  | Human explicitly requested it, or unrestricted portfolio mode is building a proposed start batch and tracker Type/brief classifies it as Workflow | Work Item Runner on the tracker item / brief after approval (route by brief: full pipeline, refactor, or fast-track) |
| Writing Spec                                                                        | Tracker **Writing Spec**; spec PR not yet human-ready               | Work Item Runner on the tracker item / branch / PR                              |
| Writing Plan                                                                        | Tracker **Writing Plan**; plan PR not yet human-ready               | Work Item Runner on the tracker item / branch / PR                              |
| In Development                                                                      | Tracker **In Development**; feature/fix PR not yet human-ready      | Work Item Runner on the tracker item / branch / PR                              |
| Spec Ready                                                                          | Tracker **Spec Ready**                                              | Work Item Runner on the development folder                                      |
| Plan Ready                                                                          | Tracker **Plan Ready**                                              | Work Item Runner on the development folder                                      |
| Pushed workflow branch, no PR yet                                                   | Branch exists on local/remote/worktree (VCS supplementary)          | Work Item Runner on the branch                                                  |
| PR open, no readiness label                                                         | PR exists and latest push has not fully cleared (VCS supplementary) | Work Item Runner on the PR                                                      |
| PR labeled `needs-fixes`                                                            | Human or automated systems requested changes (VCS supplementary)    | Work Item Runner on the PR                                                      |
| Spec in Review / Plan in Review / Development in Review or `ready-for-human-review` | —                                                                   | Wait; do not redispatch (unless human feedback requires a fix loop)             |

### Priority order

When multiple items are eligible or proposal-eligible, prioritize as follows:

1. Due date within 2 weeks, earliest first
2. Priority: Urgent → High → Normal → Low
3. Creation date, earlier first

If a due date conflicts with the abstract priority order, flag it to the human rather than silently choosing.

For GitHub Projects, the project **Type** field is authoritative for Backlog
route classification. Repository labels such as `workflow`, `bug`,
`enhancement`, and `type:*` are legacy classification hints only; do not rely on
them when Type is available.

### Largest safe start-batch rule

For unrestricted portfolio runs, the orchestrator must maximize useful parallel work within the current safety constraints:

1. Start from all non-terminal open tracker items.
2. Separate dispatch-eligible in-flight/resume items from proposal-eligible Backlog items.
3. Apply the dependency gate to both classes.
4. Sort remaining candidates by the priority order above.
5. Build the largest batch whose items can safely run together:
   - Spec-creation Backlog items are generally parallel-safe unless they share an explicit dependency or the brief says they are alternatives.
   - Refactor Backlog items require a plan before implementation and can be proposed together when their briefs do not indicate overlapping ownership or dependency.
   - Implementation/resume items must still pass tool-fix ordering and file-level conflict checks below.
6. If a lower-priority item blocks a higher-priority item because of dependency, tool-fix ordering, or file conflicts, report the reason and keep the higher-priority feasible set as large as possible.
7. Present the proposed batch with item number, title, priority, type, next stage, and parallelization notes. If Backlog items are included, stop for explicit human approval before Step 2.5 mutates tracker status or before any Work Item Runner is dispatched for those Backlog starts.

This rule changes the default `/run-work` behavior from "only resume already-started items" to "resume deterministic work and, when there is no deterministic work or spare capacity remains, propose the biggest safe set of Backlog items to start next."

### Dependency gate

Before batching an item, check its `Depends on` field or tracker dependency data. If any dependency is not yet `Merged` or `Released`, skip the item and record it as blocked.

### Stale `In Development` correction (AC-6, AC-7, AC-8, AC-10)

> **Scan-only mode gate (`/run-work`)**: When the routing entrypoint is `/run-work` (scan-only mode), this section is **skipped entirely** — no tracker mutations occur during the scan-and-propose phase. This correction runs only when executing a full portfolio run via `/run-items` or an equivalent dispatch entrypoint.

After building the initial candidate list from the eligibility table above and after the dependency gate, but **before** Step 2.5 (pre-dispatch tracker updates), scan each candidate item whose tracker status is exactly `In Development`:

1. **Guard — skip if issue number is invalid**: Before running the branch and PR checks, verify that `ISSUE_NUMBER` is a non-empty positive integer. An empty or non-numeric value would cause `git ls-remote` to search for patterns like `refs/heads/feature/-*` or `refs/heads/feature/abc-*`, potentially matching unintended branches. GitHub issue numbers are always positive integers, so a non-integer value indicates a data problem in the candidate list:

   ```bash
   if ! echo "${ISSUE_NUMBER:-}" | grep -qE '^[1-9][0-9]*$'; then
     echo "WARNING: invalid ISSUE_NUMBER '${ISSUE_NUMBER:-}' for candidate item — skipping stale detection."
     continue  # move to the next candidate in the eligibility loop
   fi
   ```

2. **Check for an existing implementation branch or open PR** (fail-open: skip stale correction if either check is unreliable):

   ```bash
   # Only check implementation-stage branches (feature/fix/refactor/hotfix).
   # spec/* and implementation-plan/* branches persist on the remote after merge
   # and must not be treated as evidence that implementation is active.
   # git ls-remote globs use bare-number forms only (feature/123-slug,
   # feature/123). Tracker-prefixed forms (feature/ENG-123-slug) are detected
   # by the more-precise gh pr list regex below; broad globs like
   # *-123-* would false-positive on unrelated branches containing the
   # issue number in their slug (e.g. feature/456-add-123-logs).
   # Use pipefail so a network/auth failure propagates; on failure, skip stale
   # detection (fail-open — treat as genuinely in progress, do not reset).
   HAS_BRANCH=$(set -o pipefail; git ls-remote origin \
     "refs/heads/feature/${ISSUE_NUMBER}-*" \
     "refs/heads/feature/${ISSUE_NUMBER}" \
     "refs/heads/fix/${ISSUE_NUMBER}-*" \
     "refs/heads/fix/${ISSUE_NUMBER}" \
     "refs/heads/refactor/${ISSUE_NUMBER}-*" \
     "refs/heads/refactor/${ISSUE_NUMBER}" \
     "refs/heads/hotfix/${ISSUE_NUMBER}-*" \
     "refs/heads/hotfix/${ISSUE_NUMBER}" \
     2>/dev/null | wc -l | tr -d ' ') || {
     echo "WARNING: git ls-remote failed for issue #${ISSUE_NUMBER} — skipping stale detection (treating as genuinely in progress)."
     continue
   }

   # The jq regex includes an optional tracker-prefix group ([A-Z][A-Z0-9]*-)
   # to match both feature/123-slug and feature/ENG-123-slug forms.
   # Do NOT use || echo 0: a gh failure must not be interpreted as "no PR exists".
   # On failure, skip stale detection (fail-open).
   HAS_PR=$(gh pr list --state open --limit 1000 \
     --json number,headRefName \
     --jq "[.[] | select(.headRefName | test(\"^(feature|fix|refactor|hotfix)/([A-Z][A-Z0-9]*-)?${ISSUE_NUMBER}(-|\$)\"))] | length" \
     2>/dev/null) || {
     echo "WARNING: gh pr list failed for issue #${ISSUE_NUMBER} — skipping stale detection (treating as genuinely in progress)."
     continue
   }
   ```

3. **If both checks return zero** (no branch, no PR): the "In Development" status is stale (BR-5). Apply the correction:
   - Log a `STALE_STATUS_CORRECTION:` line to the run output (BR-10, AC-10):

     ```text
     STALE_STATUS_CORRECTION: issue #<N> tracker shows 'In Development' but no branch or PR found. Correcting to 'Plan Ready'.
     ```

   - Update the tracker status to `Plan Ready` using `update_tracker_status_best_effort` (BR-6):

     ```bash
     update_tracker_status_best_effort "$ISSUE_NUMBER" "Plan Ready"
     ```

   - Re-classify the item as `Plan Ready` in the candidate list so it follows the `Plan Ready` dispatch path in Step 2.5 and Step 3.

4. **If either check returns non-zero** (branch or PR found): the item is genuinely in progress — do not reset the status (BR-5 inverse; AC-8).

5. **Duplicate dispatch prevention** (BR-8): once the corrected item enters dispatch via Step 2.5, the pre-dispatch status update immediately advances the tracker to `In Development` (the `Implement` row). On any subsequent eligibility pass within the same run the item will no longer show `Plan Ready`, so it cannot be re-dispatched. No additional tracking mechanism is required.

6. **Scope** (BR-7): this correction applies only within a Portfolio Orchestrator run (this protocol). Items whose tracker status was set outside an orchestrated run are not in scope; those require human correction or a new orchestrated run to detect them.

---

## Step 2.5: Pre-Dispatch Tracker Status Update

> **Scan-only mode gate (`/run-work`)**: When the routing entrypoint is `/run-work` (scan-only mode), this entire step is **skipped** — no tracker status updates occur during the scan-and-propose phase. Step 2.5 runs only when executing a full portfolio run via `/run-items` or an equivalent dispatch entrypoint.

Before building parallel batches, update the tracker to reflect that eligible items are now actively being worked on. This step runs after Step 2 (eligibility determination) and before Step 3 (batch building).

### Purpose

Without this step, items remain in a stale tracker status (e.g., `Backlog`, `Spec Ready`, `Plan Ready`) while agents are already working on them. The Batch 3 retro identified this as a source of confusion for humans monitoring portfolio progress and for Work Item Runners that check tracker status when resuming.

### Procedure

For each item that passed the Step 2 eligibility check:

1. **Ensure the item is on the project board**: check whether the item already exists in the configured project board. If it is missing, add it. Log the result (`already present` / `added to board`). Use `ensure_on_project_board` from `scripts/development-workflow/workflow-lib.sh`:

   ```bash
   # Source workflow-lib.sh to get ensure_on_project_board
   # shellcheck source=scripts/development-workflow/workflow-lib.sh
   source scripts/development-workflow/workflow-lib.sh
   ensure_on_project_board "$ISSUE_NUMBER" "$INITIAL_STATUS"
   ```

   Where `$INITIAL_STATUS` is the in-flight status appropriate to the next action (e.g., `"Writing Spec"`, `"Writing Plan"`, or `"In Development"`). For resume items the call is still idempotent — the function detects the item is already on the board and returns without modifying the existing status.

2. **Update tracker status to the appropriate in-flight value** based on the next action that will be dispatched:

   | Next action to dispatch                                                                       | Tracker status to set |
   | --------------------------------------------------------------------------------------------- | --------------------- |
   | Write Spec                                                                                    | `Writing Spec`        |
   | Write Plan                                                                                    | `Writing Plan`        |
   | Implement (feature/fix/refactor/hotfix branch)                                                | `In Development`      |
   | Resume in-progress stage (status already `Writing Spec`, `Writing Plan`, or `In Development`) | No change — skip      |

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

#### Deferred-action collection loop (Linear provider)

After each Work Item Runner returns, the orchestrator must scan the runner's
complete output for `TRACKER_ACTION_REQUIRED=` and `TRACKER_UPDATE_REQUIRED:`
signals and apply each one via Linear MCP before proceeding to the next item:

```
for each line in Work Item Runner output:
  case line:
    "TRACKER_ACTION_REQUIRED=set_status issue=<id> target_status=<status>":
      status = strip_single_quotes(<status>)   # values with spaces are single-quoted
      call Linear MCP updateIssue(id, status=status)
      # Priority drift detection: read back the issue and compare priority
      # against the dispatch-time value recorded in Step 1a.
      # Emit PRIORITY_DRIFT_WARNING if the values differ.
      # See linear.md "Priority Drift Detection" for the full protocol.
    "TRACKER_ACTION_REQUIRED=create_item title=<title>":
      title = strip_single_quotes(<title>)     # values with spaces are single-quoted
      call Linear MCP createIssue(title=title, teamId=<team>)
    "TRACKER_UPDATE_REQUIRED: set issue #<N> status to \"<status>\"":
      call Linear MCP updateIssue(id=<N>, status=<status>)
      # Priority drift detection applies here too — see linear.md.
```

After each `updateIssue` call, perform a post-write re-read to confirm the
status write was reflected. If the returned status does not match the target,
retry once and emit `TRACKER_WRITE_UNCONFIRMED` if the mismatch persists.
See [`linear.md`](../integrations/linear.md) "Priority Drift Detection" for
the `PRIORITY_DRIFT_WARNING` and `TRACKER_WRITE_UNCONFIRMED` formats and
retry rules.

A deferred action that cannot be applied must be logged explicitly:

```
TRACKER_SYNC_SKIPPED: issue=<id> action=<action_type> reason=<reason>
```

Do not silently drop deferred actions — an unapplied transition leaves the
Linear item out of sync with the workflow stage, which breaks future discovery.
See [`linear.md`](../integrations/linear.md) for the full reference table.

---

## Step 3: Build Parallel Batches

Group dispatch-eligible items and approved start-batch items into explicit batches. If Backlog items have only been proposed and not yet approved, do not continue to tracker mutation or dispatch for those items.

### Stage-aware batch lanes (default implementation serialization)

Before tool-fix ordering and file-level conflict checks, assign each candidate item
to a **stage lane** and apply `max_concurrent_by_stage` caps:

| Lane            | Typical `NEXT_ACTION` values                                      | Default max concurrent |
| --------------- | ----------------------------------------------------------------- | ---------------------- |
| `spec`          | `run-spec-review-and-open-pr`                                     | unlimited (`0`)        |
| `plan`          | `write-plan`, `run-plan-review-and-open-pr`                         | unlimited (`0`)        |
| `review`        | PR readiness / review actions (`resolve-pr-readiness`, etc.)      | unlimited (`0`)        |
| `implementation`| `implement`, `resolve-development-pr`                             | **1**                  |

**Helper**: run `workflow-batch-lanes.sh` on `workflow-batch-plan.sh` output (or use
`--scan`) to emit `STAGE_LANE`, `DISPATCH=proposed|held`, `HOLD_REASON`, and
`HELD_SUMMARY` lines per item. The script header reports resolved lane caps
(`MAX_CONCURRENT_*`).

**Configuration** (optional): declare overrides under `guardrails.parallelism` in
`.ai-dev-workflow.yaml` (documented in `guardrails.md`). Example:

```yaml
guardrails:
  parallelism:
    max_concurrent_by_stage:
      spec: 0
      plan: 0
      review: 0
      implementation: 2
```

A value of `0` means unlimited for that lane.

**`LOCAL_RUNTIME` signal**: `workflow-batch-plan.sh` emits `LOCAL_RUNTIME=none|exclusive`
for implementation items based on plan-document heuristics (local dev server, port,
database migration signals). When any proposed implementation item is `exclusive`,
hold additional proposed implementation items with reason `local runtime exclusivity`.
Git worktree isolation does **not** imply port/DB isolation — document this in batch
proposals when implementation items are held.

**Batch proposal output** must list held items with lane-cap, runtime exclusivity,
file-overlap, or tool-fix reasons so operators see why work was deferred.

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

**Spec/plan stage carve-out for `TOOL_FIX=unknown`**: When `TOOL_FIX=unknown` is received for
an item and the item's tracker status is `Writing Spec` or `Writing Plan` (or its `NEXT_ACTION`
is `write-plan`, `run-spec-review-and-open-pr`, or `run-plan-review-and-open-pr`), **treat
`unknown` as `no` for serialization purposes — do not apply the serialize-first rule**.

Rationale: `spec/*` and `implementation-plan/*` branch PRs only write documentation to
`docs/specs/developments/*/`. Their automated reviewer loops (Step 7) do not invoke or depend on
any canonical tool file behavior. The serialize-first rule's intent is to prevent consumer items
from invoking a modified or broken tool during their PR readiness loops — that risk does not
exist at the spec or plan writing stage. The `TOOL_FIX=yes` classification still applies at the
**implementation** stage when the item's plan actually modifies canonical tool files; this
carve-out does not change serialization behavior for implementation-stage dispatches.

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

#### Foundational reviewer-tool merge ordering

Dispatch serialization alone is not enough when one tool-fix repairs reviewer-loop or
reviewer-action behavior that another same-batch tool-fix needs in order to trust its own
reviewer loop.

A **foundational reviewer-tool fix** is a tool-fix item that repairs behavior in a reviewer
loop, reviewer adapter, review-action workflow, reviewer summary guard, reviewer status check,
or related protocol that another same-batch tool-fix will invoke while proving readiness.

A **dependent reviewer-tool fix** is a tool-fix item whose own reviewer loop, CI/review
readiness proof, or prior escalation depends on the foundational fix being present on the
target base branch.

When a foundational/dependent relationship is detected:

1. Dispatch the foundational item first and hold dependent tool-fix items.
2. Do not trust a dependent item's reviewer-loop result until the foundational PR has merged
   to the dependent item's target base branch.
3. After the foundational PR merges, update each dependent branch or PR from the target base
   before rerunning reviewer loop and CI.
4. Treat any dependent reviewer-loop escalation that happened before the foundational merge as
   stale until a fresh post-update reviewer loop runs.
5. Only mark the dependent item ready after the post-update reviewer loop and CI are clean, or
   escalate if fresh post-update findings remain.

The batch summary must list the foundational item, each held dependent item, the merge-ordering
reason, any stale pre-merge escalation being re-evaluated, and the exact resume condition
(for example, `held — merge PR #N, update from develop, rerun reviewer loop and CI`).

This guidance changes sequencing only. The orchestrator must not merge any foundational or
dependent PR autonomously; every PR merge still requires human approval under the repository's
normal merge rules.

**Already-waiting tool-fix**: If the tool-fix item is already `ready-for-human-review`, `Spec in
Review`, or `Plan in Review` (already waiting for merge) before batch dispatch, the orchestrator
reports it as a "pending tool-fix" blocker for the consumer items and holds those items without
redispatching the tool-fix item.

**Human override**: The orchestrator must **never** autonomously skip the serialize-first gate.
Only an explicit human instruction enables parallel dispatch when an ordering hazard has been
detected. When a human instructs override, the orchestrator logs the override and annotates the
batch summary with a warning: "Human override: tool-fix ordering hazard acknowledged for item
#N. Dispatching in parallel."

### Same-batch file-level conflict detection

**Scope** (BR-1): Conflict detection applies only to implementation items — branches with prefix
`feature/`, `fix/`, `refactor/`, or `hotfix/`. Spec and plan items are never subject to
file-level conflict serialization.

**Detection source**: `workflow-batch-plan.sh` emits `FILE_SET=<comma-separated paths>` or
`FILE_SET=unknown` for each implementation item (i.e., items where `NEXT_ACTION=implement` or
`NEXT_ACTION=resolve-development-pr`). The `FILE_SET` value is derived from the explicit file
list in the item's implementation plan document (`2_*_implementation-plan.md`). Items without a
plan document, or whose plan contains no extractable file list, receive `FILE_SET=unknown`.

**Conflict definition** (BR-2): A conflict exists between two items when their declared file
sets share at least one common path. Paths are compared as normalized, repo-root-relative strings
(forward slashes, no leading slash).

**Serialization rule** (BR-4 / BR-5): When a conflict is detected, the lower-priority item is
moved to the next serial sub-batch. The higher-priority item remains in the current batch.
Priority is determined by the orchestrator using the following ordered tiebreakers:

1. Item priority level: Urgent > High > Normal > Low (orchestrator applies from tracker data)
2. Creation date: the older item (earlier creation date) stays in the current batch
   (orchestrator applies from tracker data or development folder timestamp prefix)
3. Branch name lexicographic order: the lexicographically earlier branch name stays
   (this tiebreaker is what `workflow-batch-plan.sh`'s `detect_file_conflicts` helper
   implements; the orchestrator must apply tiers 1 and 2 before delegating to the helper,
   or override the helper's `SERIALIZE` output when tracker data indicates a higher-priority
   item was incorrectly serialized)

The batch summary must list the conflicting item pair, the overlapping file path(s), and the
resulting batch assignment for each item (BR-7).

**Unknown-set handling** (BR-3): Items with `FILE_SET=unknown` are not automatically serialized
but are flagged in the batch summary with a warning noting that file-level conflict detection was
not possible for that item (no plan document, or plan contains no extractable file list). The
batch proceeds as-is with the unknown-set items included.

**Human override** (BR-6): The orchestrator must **never** autonomously dispatch an override.
Only an explicit human instruction enables parallel dispatch when a conflict has been detected.
When a human instructs override, the orchestrator logs the override and annotates the batch
summary with a warning.

**Ordering relative to tool-fix check** (BR-8): Conflict detection runs **after** the tool-fix
ordering check (above). Items already serialized by the tool-fix rule are excluded from the
conflict-detection input set for the current batch. The orchestrator (or the calling code) must
pre-filter tool-fix-serialized items before passing the remaining batch to the
`detect_file_conflicts` helper.

**Codex fallback**:

If the runner cannot execute multiple Work Item Runners concurrently, preserve the same batching decision but process that batch sequentially. Report the fallback explicitly in the summary.

For each item in the batch, prepare a short handoff:

- Item identifier: development path, branch, PR, or tracker ID
- Current brief / tracker summary
- Current next action
- Priority context
- Parallelization notes or serialization reason
- Isolation assignment for mutating explicit-list batches, including sequential
  fallback: item identifier, expected branch, absolute worktree path,
  `isolation: "worktree"`, mutation classification (`mutating` or
  `read_only`), artifact repo root, and base branch
- `BATCH_CONTEXT=true` — required for explicit-list batch dispatch so the Work
  Item Runner (protocol 91) activates worktree isolation
- `BASE_BRANCH=<resolved-base>` — include the bounded-prelude-approved base,
  normally `develop`. Use `develop-<slug>` only when the explicit-list or epic
  scope has one shared `integration-branch:<slug>` label and the owning remote
  branch validation has passed or has been explicitly deferred for a selected
  product repository. When `BASE_BRANCH` is present in the handoff, the Work
  Item Runner (protocol 91) **must** use it as the worktree base instead of the
  default `origin/develop` for all item types (feature, fix, refactor, spec,
  plan). The base-branch table in protocol 91 Step 3 applies only when
  `BASE_BRANCH` is absent from the handoff.
- **Incremental commit requirement**: For substantial or multi-part mutating
  item work, the Work Item Runner must commit immediately after each completed
  logical sub-part so interrupted runs have a recoverable checkpoint. Do not
  intentionally batch all completed sub-parts into one end-of-run commit.
  Single-step work with no meaningful completed intermediate checkpoint may use
  one final commit. Never commit incomplete, failing, or incoherent edits just
  to satisfy this requirement. Keep checkpoint commits scoped to the assigned
  item, branch, and worktree; this does not change review, CI, readiness-label,
  tracker, or merge gates.
- Each item adds its own CHANGELOG entry as normal (see Step 3.6 for conflict resolution strategy)

### Worktree isolation requirement

**When batching items for parallel dispatch**: Each item in a parallel batch **must** run in its own isolated worktree (or checked-out copy) to prevent branch contamination, PR cross-pollution, and shared-state conflicts between concurrent agents.

Do **not** dispatch multiple Work Item Runners to operate in the same working directory.

### Mutating batch dispatch isolation manifest

Before dispatching an explicit-list batch where any Work Item Runner may mutate
files, branches, commits, PRs, labels, or tracker state, the Portfolio
Orchestrator must build a pre-dispatch isolation manifest. This applies to both
concurrent dispatch and the documented sequential fallback for runners that
cannot execute multiple Work Item Runners concurrently. The manifest is part of
the batch evidence and must be visible in the dispatch summary.

Each mutating runner entry must include:

- Work item identifier
- Expected workflow branch
- Absolute worktree path
- `isolation: "worktree"`
- Mutation classification (`mutating`)
- Artifact-owning repo root
- Approved base branch

Pre-dispatch validation is mandatory:

- If any mutating runner is missing `isolation: "worktree"` or an
  absolute worktree path, stop before dispatch with guardrail stop condition
  `unclear_requirements`; name the affected item, the expected branch, the
  missing isolation field, and the human action needed to unblock.
- If two mutating runners are assigned the same worktree path, stop before
  dispatch with guardrail stop condition `unclear_requirements`; name both
  items, the shared path, and the human action needed to unblock.
- A non-isolated runner is allowed only when it is explicitly classified
  `read_only` and will not edit files, switch branches, create commits, push,
  open or update PRs, modify labels, or update tracker state.

This requirement is separate from the unsanctioned nested-agent PR guard in
#1200. The #1200 guard prevents child agents from creating duplicate or
wrong-base PR artifacts. The isolation manifest prevents multiple sanctioned
mutating runners from sharing one checkout or silently mutating the main tree.

The terminal batch summary must record whether the isolation manifest passed,
failed before dispatch, or escalated after detecting possible out-of-worktree
mutation.

### Integration-branch base override

Before dispatching Work Item Runners for an explicit-list batch, use the
bounded prelude's resolved base. Do not let one item's
`integration-branch:<slug>` label select the base for the whole batch.

For explicit-list batches:

- no listed integration labels: use `develop`;
- partial label coverage: use `develop` and emit the prelude warning;
- mixed labels: use `develop` and emit the prelude warning;
- one shared label across every listed item: derive `develop-<slug>` and verify
  it exists on the owning remote before adopting it;
- missing or unverifiable `develop-<slug>`: use `develop` and emit the prelude
  warning.

Before dispatching any Work Item Runner for an epic sub-item, check whether the item carries an `integration-branch:<slug>` label:

```bash
gh issue view <issue-number> --json labels --jq '.labels[].name | select(startswith("integration-branch:"))'
```

If an `integration-branch:<slug>` label is found:

1. **Derive the integration branch name**: `develop-<slug>`.
2. **Verify the branch exists on the remote** using
   `git ls-remote --exit-code --heads`. Exit `0` means the branch exists, exit
   `2` means it is missing, and any other non-zero status means validation
   failed:

   ```bash
   set +e
   git ls-remote --exit-code --heads origin develop-<slug> >/dev/null 2>&1
   BRANCH_STATUS=$?
   set -e
   if [ "$BRANCH_STATUS" -ne 0 ] && [ "$BRANCH_STATUS" -ne 2 ]; then
     echo "WARNING: failed to verify whether develop-<slug> exists on origin; skipping auto-create for this item."
     continue
   fi
   ```

3. **If the branch does not exist** (`BRANCH_STATUS` is `2`), create and push it from `develop`:

	   ```bash
	   set -euo pipefail
	   git fetch origin develop
	   git checkout -B develop-<slug> origin/develop
	   git push -u origin develop-<slug>
   git switch develop  # return to develop immediately after creation
   ```

   Log: `INFO: created integration branch develop-<slug> from origin/develop for epic sub-item #<issue-number>.`

4. **Pass the base branch override to the Work Item Runner handoff**: include `BASE_BRANCH=develop-<slug>` in the handoff metadata so the Work Item Runner and stage agents open PRs against `develop-<slug>` instead of `develop`.

### Repository-mode handoff context

Before dispatching implementation work, resolve repository mode using the shared
repository-context helpers. In `single_repo`, the current repository remains the
artifact owner and no product repository selector is required. In `workflow_hub`,
specs, plans, tracker updates, and hub-only workflow changes stay hub-owned; a
product-code implementation handoff must include workflow mode, artifact owner,
selected product repository name, local path or remote identity when available,
and mutation target. If product repository context is missing or ambiguous, stop
before dispatching mutation-oriented work. Do not let command wrappers invent
their own selection rules; pass context through to `workflow-next-action.sh`,
`workflow-batch-plan.sh`, reviewer-loop scripts, and cleanup helpers.

---

## Step 3.3: Pre-Dispatch Environment Validation (Parallel Batches Only)

When `WORKFLOW_MODE` is `workflow_hub`, run product-repository preflight before
dispatching Work Item Runners for implementation work in configured product
repositories:

```bash
./scripts/development-workflow/hub-preflight-product-repos.sh --all --repo-root <hub-root>
```

This bootstraps workflow readiness labels on each product GitHub repository and
validates `ci_policy` (`required` vs explicit `none`) so delegated merge gates do
not fail only after implementation PRs are otherwise clean. Fix preflight failures
before dispatch or record an explicit `ci_policy: none` exception in hub config.

Before building the worktree per-item pre-flight (Step 3.5), run three portfolio-wide environment checks. Check 1 and Check 2 must both pass (or be explicitly acknowledged by the human) before any Work Item Runner is dispatched. Check 3 is non-blocking — surface its findings alongside the others but do not hold dispatch waiting on stale local branch cleanup.

### Check 1: Stale orphaned worktrees

Scan the full worktree list for orphaned entries — worktrees whose branch is either merged, closed, or no longer needed by the current batch. These lock the `.git` index against concurrent operations and prevent clean worktree creation for items in the new batch.

```bash
# List all registered worktrees and their branches, excluding the main worktree
# (Resolve REPO_ROOT to an absolute path; use exact awk comparison to avoid
# prefix-match false exclusions for nested worktrees under the repo root)
REPO_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
git worktree list --porcelain \
  | awk -v root="$REPO_ROOT" '/^worktree / { wt=$2 } /^branch / { b=$2; sub("^refs/heads/","",b); if (wt != root) print wt "\t" b }'
```

For each worktree found, check whether its branch has already been merged to the integration branch (i.e., the PR is merged and the branch is no longer active):

```bash
# For each candidate worktree branch <branch>:
# A branch is "stale" if its PR was merged and no matching open PR exists any more
gh pr list --state merged --head <branch> --json number,mergedAt --jq '.[0] | .number'
# Non-empty output → merged; the worktree is stale and safe to remove
```

**Stale detection criteria** (a worktree is stale when **any** of the following is true):

- Its branch has a merged PR (`gh pr list --state merged --head <branch>` returns a result)
- Its branch has a closed PR with no open successor (`gh pr list --state all --head <branch>` shows only closed PRs)
- Its branch no longer exists on the remote and is not part of the current batch (`git ls-remote --exit-code origin <branch>` returns non-zero)

**Action when stale worktrees are found:**

1. List every stale worktree with its path and branch name.
2. Report them to the human with suggested cleanup commands:

   ```bash
   git worktree remove --force <worktree-path>   # use --force only when the worktree is locked
   ```

3. **Do not auto-remove** worktrees without human confirmation — a locked worktree may contain in-progress work that the human has not discarded yet.
4. If the human confirms cleanup, remove each stale worktree and then continue.
5. If the human cannot confirm at this time, **hold the batch dispatch** and report the blocking condition. Do not attempt to create new worktrees until the stale ones are resolved, as locked worktrees can interfere with subsequent `git worktree add` calls.

**Worktrees that belong to the current batch**: Do not flag an active worktree as stale if its branch is one of the branches about to be dispatched. Those are handled by the per-item Step 3.5 check.

### Check 2: Unsynced or diverged integration branch

Before dispatching any Work Item Runner, verify that the local integration branch is in sync with `origin`. New feature/fix branches are cut from the local integration branch; if the local branch has commits that are not yet on `origin`, those commits will appear in every new implementation PR's diff, causing incorrect diffs and confusing reviewers. Conversely, if `origin` has commits that are not on the local branch, new branches will be cut from a stale base.

```bash
# Derive the integration branch from the batch's BASE_BRANCH context if set.
# When items in this batch carry integration-branch:<slug> labels, BASE_BRANCH will be
# "develop-<slug>" and this check verifies that branch (not always "develop").
# Fall back to "develop" when no integration-branch override is present.
INTEGRATION_BRANCH="${BASE_BRANCH:-develop}"  # BASE_BRANCH from batch handoff metadata; defaults to "develop"

# Fetch latest remote state (idempotent, safe to run at the start of every batch)
git fetch origin

# Count commits in each direction
AHEAD=$(git rev-list --count "origin/${INTEGRATION_BRANCH}..${INTEGRATION_BRANCH}" 2>/dev/null || echo "0")
BEHIND=$(git rev-list --count "${INTEGRATION_BRANCH}..origin/${INTEGRATION_BRANCH}" 2>/dev/null || echo "0")

echo "Integration branch '${INTEGRATION_BRANCH}': ${AHEAD} commit(s) ahead of origin, ${BEHIND} commit(s) behind origin."
```

**Four divergence states and required actions:**

**State 1 — In sync** (`AHEAD=0, BEHIND=0`): Safe to proceed. Continue to Step 3.5.

**State 2 — Local ahead only** (`AHEAD>0, BEHIND=0`): The local integration branch has commits not yet pushed to `origin`. New branches cut from this state will carry those unpushed commits into every PR diff.

1. Report to the human: the local `<integration-branch>` is `N` commits ahead of `origin/<integration-branch>`.
2. Show the top commits on the local side:
   ```bash
   git log --oneline "origin/${INTEGRATION_BRANCH}..${INTEGRATION_BRANCH}"
   ```
3. Ask the human to push the pending commits before batch dispatch:
   ```bash
   git push origin <integration-branch>
   ```
4. **Block batch dispatch** until either:
   - The human pushes the pending commits (re-run the check after push; `AHEAD` must be `0`)
   - The human explicitly acknowledges the risk and instructs the orchestrator to proceed anyway (log this override in retrospective notes)

**State 3 — Local behind only** (`AHEAD=0, BEHIND>0`): `origin` has commits the local branch does not have. A fast-forward pull is safe.

1. Report to the human: the local `<integration-branch>` is `N` commits behind `origin/<integration-branch>`. A fast-forward pull is available.
2. Show the top commits on the remote side:
   ```bash
   git log --oneline "${INTEGRATION_BRANCH}..origin/${INTEGRATION_BRANCH}"
   ```
3. Suggest the safe resolution:
   ```bash
   git pull origin <integration-branch>   # fast-forward safe (no local diverging commits)
   ```
4. **Block batch dispatch** until either:
   - The human pulls the pending commits (re-run the check after pull; `BEHIND` must be `0`)
   - The human explicitly acknowledges the risk and instructs the orchestrator to proceed anyway (log this override in retrospective notes)

**State 4 — True divergence** (`AHEAD>0, BEHIND>0`): Both the local branch and `origin` have commits the other does not. This is the most dangerous state — new branches cut from local will carry diverging commits into PRs, and a simple pull or push would create a merge commit on a shared branch.

1. Report to the human: the local `<integration-branch>` has `N` commit(s) not on `origin` and `M` commit(s) from `origin` not applied locally (true divergence).
2. Show the top commits on each side:
   ```bash
   # Local-only commits (what local has that origin does not)
   git log --oneline "origin/${INTEGRATION_BRANCH}..${INTEGRATION_BRANCH}"
   # Origin-only commits (what origin has that local does not)
   git log --oneline "${INTEGRATION_BRANCH}..origin/${INTEGRATION_BRANCH}"
   ```
3. Present the resolution options to the human — **do not choose automatically**:

   | Option                   | Command                                        | When to use                                                                                |
   | ------------------------ | ---------------------------------------------- | ------------------------------------------------------------------------------------------ |
   | Rebase local onto origin | `git rebase origin/<integration-branch>`       | Local commits are unpublished or belong to you; you want a linear history                  |
   | Merge origin into local  | `git merge origin/<integration-branch>`        | You want to preserve both histories with a merge commit                                    |
   | Reset local to origin    | `git reset --hard origin/<integration-branch>` | Local commits are safe to discard (e.g., already merged via another path); **destructive** |

4. **Block batch dispatch** until the human selects and applies one of the above options and the check re-runs with `AHEAD=0, BEHIND=0` (or `AHEAD>0, BEHIND=0` if the human chose rebase/merge and still needs to push). Require explicit human choice — do not auto-apply any resolution.

**Safe condition**: `AHEAD=0, BEHIND=0` — the integration branch is fully in sync with `origin`. Proceed to Step 3.5.

### Check 3: Stale local branches

Scan local branches for two categories of stale / orphaned entries that clutter `git branch` output and can cause worktree conflicts on re-use:

**Category A — Workflow-prefix branches whose upstream PR has been merged**

Workflow branches (`feature/`, `fix/`, `refactor/`, `hotfix/`, `spec/`, `implementation-plan/`) that were used for a PR which has since merged are safe to delete but are not cleaned up automatically by `post-merge-cleanup.sh` when other PRs in the same batch merge later.

```bash
# List all local branches matching workflow prefixes
git branch --list \
  'feature/*' 'fix/*' 'refactor/*' 'hotfix/*' 'spec/*' 'implementation-plan/*' \
  | sed 's/^[* ]*//'
```

For each branch found, check whether its upstream PR has been merged:

```bash
# For each candidate branch <branch>:
gh pr list --state merged --head <branch> --json number,mergedAt \
  --jq '.[0] | "PR #\(.number) merged at \(.mergedAt)"'
# Non-empty output → merged; the local branch is stale and safe to delete
```

**Category B — `worktree-agent-*` branches with no remote counterpart and no open/merged PR**

Agents create `worktree-agent-*` branches when spinning up git worktrees. These branches accumulate without a corresponding remote branch or open/merged PR and are never cleaned up automatically.

```bash
# Detect local branches with no upstream tracking ref or a gone upstream
git branch -vv | grep -E 'worktree-agent-' \
  | grep -E '(\[gone\]|^[^[]*$)' \
  | sed 's/^[* ]*//' | awk '{print $1}'
```

For each candidate `worktree-agent-*` branch, confirm no associated PR exists (open or merged):

```bash
# For each candidate branch <branch>:
gh pr list --state all --head <branch> --json number,state --jq '.[0] | .number'
# Empty output → no PR exists; branch is orphaned and safe to delete
```

**Action when stale or orphaned branches are found:**

1. List every stale / orphaned branch with its category and a suggested cleanup command:

   ```bash
   # Category A — stale workflow branch (upstream PR merged):
   git branch -D <branch>

   # Category B — orphaned worktree-agent branch (no remote, no PR):
   git branch -D <branch>
   ```

2. Report the list to the human **before** proceeding to Step 3.5 — do not auto-delete without confirmation.
3. This check is **non-blocking**: if no stale branches are found, or after the human reviews and acts (or explicitly chooses to defer cleanup), continue to the next check and batch dispatch. Unlike Check 1 (stale worktrees) and Check 2 (integration branch sync), stale local branches do not block new worktree creation or corrupt PR diffs — they are operational noise only. Surface the list and let the human decide.

**Branches that belong to the current batch**: Do not flag as stale any branch that is one of the branches about to be dispatched in the current batch.

### Check ordering and gating

Run Check 1, Check 2, and Check 3 in parallel. Check 1 and Check 2 must both pass (or be explicitly acknowledged by the human) before proceeding to the per-item Step 3.5 checks and batch dispatch. Check 3 is non-blocking — surface its findings alongside Check 1 and Check 2 but do not hold batch dispatch waiting for the human to act on stale local branches.

If Check 1 or Check 2 identifies a blocking condition, report **all three** results together so the human can resolve all issues in a single interaction rather than being interrupted multiple times.

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

| Runner      | Handoff target                           |
| ----------- | ---------------------------------------- |
| Claude Code | `item-orchestrator` agent                |
| Cursor      | Internal `item-orchestrator` handoff from `/run-items`; use `/run-item` for standalone single-item runs |
| Codex       | `workflow-item-orchestrator` skill       |

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

Execute the item from the current orchestration session, but operate only inside
the manifest-assigned worktree. If the worktree was already created during
dispatch, use that exact absolute path. If the denial occurred before the
worktree was created (early preflight failure in Protocol 91 Step 3.5), create
it at the manifest-assigned absolute worktree path first. Stop with guardrail
stop condition `unclear_requirements` if the manifest assignment is missing; do
not substitute a generic path or continue from the main repository checkout.

```bash
git worktree add <manifest-assigned-worktree-path> <branch>
```

Before any inline edit, branch-changing command, commit, push, PR mutation, or
tracker mutation, run the same Protocol 91 pre-mutation isolation self-check:
`BATCH_CONTEXT=true`, expected branch, artifact repo root, approved base branch,
mutation classification, and `isolation: "worktree"` must be present; `pwd -P`
must equal the manifest-assigned worktree path or begin with that path followed
by `/`; and `git rev-parse --abbrev-ref HEAD` must match the expected branch.

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
3. If the next action is still deterministic because the Work Item Runner returned early or was interrupted, redispatch / resume that same item. **Worktree isolation is mandatory on redispatch**: when the original batch used explicit-list dispatch (`BATCH_CONTEXT=true`), every redispatch — including fixer-agent passes triggered by review findings — must carry the full Protocol 90 isolation assignment in the handoff: `BATCH_CONTEXT=true`, resolved absolute worktree path, expected branch, artifact repo root, approved base branch, mutation classification, and `isolation: "worktree"`. Redispatching without the full assignment causes fixer agents to use main-repo file paths in `Read`/`Edit`/`Write` calls while committing via the worktree git context, leaving uncommitted files in the main working tree instead of the isolated branch.
4. Stop supervising that item only when it is waiting on a human, blocked, or escalated.
5. **Collect deferred tracker transitions**: scan the Work Item Runner's summary for any `TRACKER_UPDATE_REQUIRED:` lines. These are transitions that the subagent could not perform (e.g., because the provider requires MCP and MCP is not available in the subagent context). Apply each deferred transition now via MCP before moving on to the next item. For GitHub Projects, subagents use `gh` CLI directly and do not emit `TRACKER_UPDATE_REQUIRED:` — this step only applies to providers without CLI support (e.g., Linear).
6. **When a human confirms PRs have been merged**: run post-merge status transitions per the table in Step 10 of `91-orchestrate-work-protocol.md` — set tracker status to `Spec Ready`, `Plan Ready`, or `Merged` depending on the branch type of the merged PR — and clean up local branches and worktrees associated with the merged PRs.

### Step 5.1: Post-Dispatch PR Verification

> **Artifact-state rule**: The orchestrator's done-report must be built from independently queried artifact state — **never** from agent self-reports alone. A Work Item Runner that claims a PR is "ready" may have timed out before completing all steps, skipped a required action, or simply reported optimistically. The checks below are mandatory queries against `gh` CLI and the GitHub API; they are not optional confirmations of what the agent said it did.

> **Item self-check evidence rule**: The Work Item Runner's terminal report must
> include a `## Ground-Truth Completion Verification` section from
> `scripts/development-workflow/item-completion-self-check.sh`. The Portfolio
> Orchestrator must quote or link that section for each terminal item before
> declaring the batch item complete. Missing self-check evidence, a
> `discrepancy`, or an `unavailable_required` result means the item remains
> under Step 5 supervision even if labels appear ready.

**Batch-complete gate:** `ready-for-human-review` by itself is not a terminal
batch-complete signal. Before declaring an explicit-list or portfolio batch
complete, the orchestrator must verify every in-scope PR has passing required CI
and either a latest automated reviewer-loop summary whose result is clean or
skipped, or explicit evidence that Step 7 was skipped because no review
platforms are configured. Any PR with failing CI, pending reviewer-loop guard,
a missing summary when review platforms are configured, or a non-clean
reviewer-loop result remains in progress and must be redispatched or escalated
instead of included in the done-report.

**In-flight CI/watch states are non-terminal:** A transient watch failure,
cancelled duplicate run, skipped superseded run, pending/queued check, or
incomplete `statusCheckRollup` snapshot does not end a same-session
`/run-items` execution. Re-query the authoritative PR state (`gh pr view` plus
the required GraphQL review-thread read), re-run `pr-ci-loop.sh` when CI evidence
is incomplete or newly triggered, and continue supervising until the PR is green,
blocked by a named stop condition, escalated by the retry/timeout limits, merged
through an allowed delegated path, or handed off because the effective guardrails
forbid merge. Do not hand control back to the human merely because a local
watch command exited early while GitHub still shows work in progress.

Before reporting any PR as ready for human review, independently query the actual PR state via `gh pr view`. Run this check for every PR that a Work Item Runner reports as ready:

```bash
gh pr view <pr_number> --json baseRefName,isDraft,labels,statusCheckRollup,comments,files
```

The `files` field is required to verify CHANGELOG presence independently (see table below). Do not skip it.

For sweep, batch, helper-extraction, or pattern-completeness items, also require
residual-gate evidence from `scripts/development-workflow/scope-residual-gate.sh`
before accepting the PR as `ready-for-human-review`. A `RESULT=block` or
`RESULT=escalate` keeps the item in progress; the batch summary must report the
residual gate outcome instead of counting the item as terminal.

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

Verify all of the following by querying artifact state directly. If any check fails, apply the remediation action in the table below — **do not redispatch the agent for label-only gaps**:

| Check                                           | Pass condition                                                                                                                                                                                                                                                                                                                                                                                                            | Remediation if failing                                                                                                                                                                                                                                                                            |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Base branch                                     | `develop` (or `develop-<slug>` if the batch is targeting an integration branch) for `feature/*`, `fix/*`, `refactor/*`, `spec/*`, `implementation-plan/*`; `main` for `hotfix/*`                                                                                                                                                                                                                                          | Redispatch agent to rebase onto the correct base                                                                                                                                                                                                                                                  |
| PR is non-draft                                 | `isDraft: false`                                                                                                                                                                                                                                                                                                                                                                                                          | Run `gh pr ready <pr_number>` directly; log as protocol deviation                                                                                                                                                                                                                                 |
| `ready-for-human-review` label                  | Present in the `labels` array returned by `gh pr view`                                                                                                                                                                                                                                                                                                                                                                    | Apply directly: `gh pr edit <pr_number> --add-label "ready-for-human-review"` (after all other checks pass)                                                                                                                                                                                       |
| `ready-for-regression` label                    | Present in the `labels` array on `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, and `backport/hotfix/*` PRs; not required for `spec/*`, `implementation-plan/*`, or graduation PRs (head branch `develop-<slug>`, base branch `develop`)                                                                                                                                                                                 | **Apply directly** (primary enforcement point): `gh pr edit <pr_number> --add-label "ready-for-regression"`. Log as protocol deviation: `PROTOCOL_DEVIATION: ready-for-regression was missing on PR #<N> — applied by orchestrator Step 5.1`. **Do not redispatch the agent for this gap alone.** Do not apply this remediation to graduation PRs (`develop-<slug>` → `develop`) — they are explicitly exempt (BR-6 of the graduation spec). |
| No `needs-fixes` label                          | Absent from the `labels` array                                                                                                                                                                                                                                                                                                                                                                                            | Remove: `gh pr edit <pr_number> --remove-label "needs-fixes"` (only after CI and reviews are confirmed clean)                                                                                                                                                                                     |
| CHANGELOG presence                              | `CHANGELOG.md` appears in the `files` array for `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` PRs (i.e., `gh pr view <pr_number> --json files --jq '[.files[].path] \| any(. == "CHANGELOG.md")'` returns `true`); not required for `spec/*`, `implementation-plan/*`, or `backport/hotfix/*` (the versioned CHANGELOG entry already exists in `main` and flows to `develop` via the merge)                              | Redispatch agent to add a CHANGELOG entry and push. Do not accept the PR as ready until `CHANGELOG.md` appears in the PR's file set.                                                                                                                                                              |
| All automated-reviewer `reviewThreads` resolved | GraphQL `reviewThreads.nodes[].isResolved=true` (or `✅ Addressed` in body) for every thread authored by a configured bot login (skip this check only when Step 7 was `skipped` because no review platforms are configured)                                                                                                                                                                                               | Redispatch agent to address unresolved threads                                                                                                                                                                                                                                                    |
| Automated reviewer loop summary comment         | At least one latest PR comment containing "Automated Reviewer Loop Summary", "Reviewer Loop Summary", or "No blocking PR feedback" whose result is `clean` or `skipped` (skip this check only when Step 7 was `skipped` because no review platforms are configured). **`pr-review-loop.sh` posts this comment automatically on clean, needs-fixes, and escalate exits** — a missing comment, stale comment, or comment whose latest result is `needs_fixes`, `escalate`, `timeout`, `pending_timeout`, or any other non-clean terminal state means Step 7 is not complete | Redispatch agent to run Step 7 to completion or escalate the non-clean reviewer-loop result                                                                                                                                                                                                        |
| CI checks                                       | All required status checks are green (`state: SUCCESS` or `conclusion: success`)                                                                                                                                                                                                                                                                                                                                          | Redispatch agent to fix failing checks                                                                                                                                                                                                                                                            |

**`ready-for-regression` direct-apply rule**: This label is the primary enforcement point for the regression CI gate. It applies to **all** implementation PR types: `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, and `backport/hotfix/*`. If the agent applied `ready-for-human-review` but omitted `ready-for-regression` on any of these branch types, the orchestrator:

1. Applies the label directly: `gh pr edit <pr_number> --add-label "ready-for-regression"`
2. Logs the deviation: `PROTOCOL_DEVIATION: ready-for-regression was missing on PR #<N> (<branch-type>) — applied by orchestrator Step 5.1`
3. **Re-polls CI** — the label triggers configured real regression workflows,
   or an explicitly enabled placeholder. The CI check row in this verification
   table was evaluated _before_ the label was applied, so configured e2e checks
   may not yet be in `statusCheckRollup`. After applying the label, wait for CI
   to settle using `pr-ci-loop.sh <pr_number>` before re-running this
   verification. Do not mark the PR ready until the re-polled CI check is green.

> **`refactor/*` is not exempt**: Orchestrators must not skip the `ready-for-regression` check for `refactor/*` PRs. Refactors require regression testing before merge regardless of their content. This check has the same priority and remediation path as for `fix/*` or `feature/*` PRs.

> **Graduation PRs are exempt**: PRs with a head branch matching `^develop-` and base branch `develop` (i.e., graduation PRs from `develop-<slug>` to `develop`) are explicitly exempt from the `ready-for-regression` requirement. Do not flag the absence of this label on a graduation PR as a protocol deviation. Graduation PRs carry no new implementation — all code was already tested via each sub-item's implementation PR. See `05b-graduate-development-protocol.md` Step 4 and BR-6 of the graduation spec.

Do not redispatch the agent for a missing label alone — the label is applied directly here. Redispatching is only required when there are substantive gaps (wrong base branch, unresolved review threads, missing reviewer loop summary, failing CI). A missing reviewer loop summary comment means `pr-review-loop.sh` did not run to completion — redispatch to resume from Step 7.

If a check requires agent redispatch:

1. Log the specific failure in your retrospective notes (see "Retrospective notes during supervision" below).
2. Remove `ready-for-human-review` if it is present: `gh pr edit <pr_number> --remove-label "ready-for-human-review"`.
3. Add the `needs-fixes` label to the PR: `gh pr edit <pr_number> --add-label "needs-fixes"`.
4. Redispatch / resume the Work Item Runner for that item to address the gap. **Worktree isolation is mandatory**: if the original batch used explicit-list dispatch (`BATCH_CONTEXT=true`), the redispatched Work Item Runner must receive the full Protocol 90 isolation assignment: `BATCH_CONTEXT=true`, resolved absolute worktree path, expected branch, artifact repo root, approved base branch, mutation classification, and `isolation: "worktree"`. Do not redispatch without these values — fixer agents that run outside the worktree will use main-repo file paths and leave uncommitted changes in the main working tree.
5. Re-run this verification after the next Work Item Runner return.

Do not consider the batch complete until every dispatched item has reached a real terminal condition.

#### Stale / Incomplete PR Detection

A PR may appear "almost ready" — non-draft, with readiness labels applied — but actually be in an incomplete state because the agent timed out before finishing Step 7 (external automated reviewers). The canonical detection heuristic depends on PR type:

**Implementation PRs** (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`):

> non-draft + `ready-for-regression` present + no reviewer loop summary comment = incomplete run

**Spec/plan PRs** (`spec/*`, `implementation-plan/*`):

> non-draft + `ready-for-human-review` present + no reviewer loop summary comment = incomplete run

The reviewer loop summary comment is the only reliable indicator that Step 7 ran to completion. `ready-for-human-review` alone is NOT a reliable completion signal. This check applies only when review platforms are configured — skip it for repos where Step 7 is `skipped` (no platforms configured).

**Pre-label orphaned PR** (early timeout — applies to all PR types):

A distinct failure mode occurs when an agent times out so early that it never reaches the post-review labeling steps. The PR is left non-draft but has **no** `ready-for-human-review` label, **no** `ready-for-regression` label (for implementation PRs), and **no** reviewer loop summary comment. This looks identical to a freshly-opened, unreviewed PR and is invisible to the label-presence heuristics above.

> non-draft + no `ready-for-human-review` + no `ready-for-regression` (implementation PRs) + no reviewer loop summary comment = pre-label orphaned run

Treat any non-draft PR on a workflow branch (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`, `spec/*`, `implementation-plan/*`) that belongs to a known in-flight item and has none of the above signals as a pre-label orphaned run. Do not assume it is a fresh PR that has not yet entered the reviewer loop.

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

**Summary-comment recency (verifying the summary matches the _latest_ commit)**: The presence checks above confirm a reviewer-loop summary _exists_, but to confirm Step 7 ran against the **current** head commit (e.g., after a fix push or a rebase), compare the summary comment's **`updated_at`** to the latest commit's timestamp — **never `created_at`**. `pr-review-loop.sh` maintains a **single** summary comment and **updates it in place** on each run, so `created_at` reflects the _first_ run and a `created_at`-based freshness check produces false "stale / incomplete" verdicts for PRs whose summary was legitimately refreshed. Fetch `updated_at` via REST (`gh api repos/{owner}/{repo}/issues/{n}/comments`), since `gh pr view --json comments` does not expose it:

```bash
# Newest summary comment's updated_at, normalized to epoch seconds, vs the
# branch's latest commit time.
COMMIT_EPOCH=$(git log -1 --format=%ct "origin/<branch>")
SUMM_UPDATED=$(gh api "repos/<owner>/<repo>/issues/<pr_number>/comments" --paginate \
  --jq '[.[] | select(.body | startswith("### Automated Reviewer Loop Summary"))] | sort_by(.updated_at) | last | .updated_at // ""')
if [ -z "$SUMM_UPDATED" ]; then
  echo "No reviewer-loop summary comment found; Step 7 has not completed for this PR." >&2
  exit 1
fi
SUMM_UPDATED_EPOCH=$(python3 - "$SUMM_UPDATED" <<'PY'
from datetime import datetime
import sys

updated_at = sys.argv[1]
print(int(datetime.fromisoformat(updated_at.replace("Z", "+00:00")).timestamp()))
PY
)
# A summary whose updated_at epoch is >= COMMIT_EPOCH corresponds to the current
# head; an older updated_at means Step 7 has not re-run on the latest commit
# (genuinely stale).
```

**Classification table** (evaluate in order; first matching row wins):

| `isDraft` | `hasRegressionLabel` | `hasReadyLabel` | `hasReviewSummary` | Classification                                                                                                                   |
| --------- | -------------------- | --------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `true`    | any                  | any             | any                | Draft PR — run Step 7a and convert to non-draft                                                                                  |
| `false`   | `true`               | any             | `false`            | Incomplete run (post-regression, pre-Step-7)                                                                                     |
| `false`   | any                  | `true`          | `false`            | Incomplete run (post-label, pre-Step-7)                                                                                          |
| `false`   | `false`              | `false`         | `false`            | **Pre-label orphaned run** — treat as incomplete                                                                                 |
| `false`   | `true`               | `false`         | `true`             | Incomplete run (post-regression, post-summary, pre-ready-label) — apply `ready-for-human-review` label, then proceed to Step 5.1 |
| `false`   | any                  | `true`          | `true`             | Ready (proceed to Step 5.1 full verification)                                                                                    |

For the pre-label orphaned case (`isDraft=false`, no labels, no summary): the PR is not a fresh PR awaiting first dispatch — it is an orphaned in-progress run. Treat it the same as other incomplete states and redispatch the Work Item Runner to resume from Step 7a.

**Expected action when incomplete state is detected**:

1. Log the incomplete PR in your retrospective notes.
2. Remove `ready-for-human-review` if present: `gh pr edit <pr_number> --remove-label "ready-for-human-review"`.
3. Add `needs-fixes`: `gh pr edit <pr_number> --add-label "needs-fixes"`.
4. Redispatch the Work Item Runner with a resume hint to pick up from Step 7a (internal review gate).

This pattern also applies to PRs where an agent timed out mid-CI-loop: detect via `statusCheckRollup` entries in `ERROR` state, or `PENDING` state that has exceeded the configured max-wait threshold (see `pr-ci-loop.sh` timeout), and re-dispatch accordingly. Do not treat `PENDING` alone as a timeout signal — CI checks that are legitimately running will show as `PENDING` until they complete.

### Step 5.2: Post-Agent Main Working Tree Verification (Parallel Batches Only)

**Timing**: Run this check immediately after each Work Item Runner returns — **before** Step 5.1 (PR verification), before dispatching the next Work Item Runner, and before any orchestrator action that assumes the integration branch context (e.g., invoking batch-merge, pushing to `develop`). A leaked branch state in the main working tree can silently corrupt subsequent operations if not caught here.

**CWD safety: always derive `MAIN_REPO_ROOT` using `--git-common-dir`**

After a Work Item Runner completes, the shell's CWD may be inside an isolated worktree directory (`.claude/worktrees/<id>/`). Using `git rev-parse --show-toplevel` from that context returns the _worktree_ path rather than the main repo root, causing every `git -C` command below to run against the wrong tree and producing false results (wrong branch, phantom dirty files, or a spurious Case 1 auto-correct). Use `git rev-parse --git-common-dir` instead — it always resolves to the `.git` directory of the _main_ repo regardless of the current working directory:

```bash
# Always safe — returns an absolute main repo root path even when CWD is inside a worktree
MAIN_REPO_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
```

The `cd ... && pwd` wrapper is required to canonicalize the path to an absolute string: without it, `git rev-parse --git-common-dir` returns `.git` (a relative path) when run from the main repo root, and the resulting `MAIN_REPO_ROOT=".git/.."` resolves relative to wherever the shell's CWD is at the time — defeating the fix if the stored value is used after CWD has changed.

Store `MAIN_REPO_ROOT` before dispatching any Work Item Runner (while CWD is definitely at the main repo root) and reuse it in the check below. If the value was not stored ahead of time, derive it immediately after the runner returns using the `--git-common-dir` form above — **never** use `git rev-parse --show-toplevel` for this purpose inside the Step 5.2 block.

After each Work Item Runner returns in a **parallel batch**, immediately check the main working tree's branch and cleanliness. Handle all four postcondition states:

```bash
# Derive the integration branch from the batch's BASE_BRANCH context if set;
# fall back to "develop" when no integration-branch override is in context.
# When the batch was built with BASE_BRANCH=develop-<slug> in handoff metadata,
# set INTEGRATION_BRANCH accordingly so this check validates against the correct branch.
INTEGRATION_BRANCH="${BASE_BRANCH:-develop}"  # BASE_BRANCH comes from handoff metadata; defaults to "develop"
# MAIN_REPO_ROOT must be an absolute path derived via --git-common-dir (see CWD safety note above)
MAIN_BRANCH=$(git -C "$MAIN_REPO_ROOT" rev-parse --abbrev-ref HEAD)
MAIN_STATUS=$(git -C "$MAIN_REPO_ROOT" status --porcelain)

if [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
  # Case 1: Wrong branch + clean — auto-correct
  echo "GUARDRAIL: main working tree was on '$MAIN_BRANCH' after agent for item <item-id> returned. Expected '$INTEGRATION_BRANCH'. Auto-correcting."
  echo "Record as guardrail violation in retrospective notes: item <item-id> left main tree on wrong branch."
  git -C "$MAIN_REPO_ROOT" switch "$INTEGRATION_BRANCH"
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

| Main branch    | Main cleanliness | Action                                                                                                                                                                                                                                                                                                                                                 |
| -------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Wrong branch   | Clean            | Auto-correct: `git switch <integration-branch>`. Log as guardrail violation in retrospective notes — a wrong-branch + clean result typically means the agent ran in the main tree instead of its isolated worktree, or a stage protocol issued a branch-switching command that leaked out of the worktree boundary. Proceed normally after correction. |
| Wrong branch   | Dirty            | Halt and escalate. Log full `git status --porcelain` output and item ID. Do not dispatch additional agents.                                                                                                                                                                                                                                            |
| Correct branch | Clean            | Proceed normally.                                                                                                                                                                                                                                                                                                                                      |
| Correct branch | Dirty            | Halt and escalate. Log full `git status --porcelain` output and item ID. Do not dispatch additional agents.                                                                                                                                                                                                                                            |

If the main working tree is clean and on the correct branch (Case 3), proceed normally with Step 5.1 (PR verification) and then with the next Work Item Runner dispatch if any remain in the batch.

**Recurrence tracking (post-PR #345):**

> **Serial dispatch note**: Working-tree residuals from serial subagent dispatch are expected and do **not** constitute Step 5.2 violations. In serial dispatch, no worktree isolation is used — the subagent runs in the main working tree and naturally leaves it on the feature branch it just created. Only increment the violation counter when a **parallel** subagent (one that ran in an isolated worktree) leaves the main working tree dirty or on the wrong branch.

PR #345 (merged into `develop`) added a worktree pre-op checklist to `91-orchestrate-work-protocol.md` to prevent agents from running git state-changing commands in the main working tree instead of their isolated worktree. PR #411 followed up by adding a runtime CWD guard script (`scripts/development-workflow/worktree-cwd-guard.sh`) that catches branch-switching commands issued from the wrong directory at execution time rather than only at post-agent inspection. Step 5.2 violations should be rare when both mitigations are active.

When Step 5.2 fires (Case 1 — wrong branch + clean) **in a parallel batch**:

1. Record the violation in the batch's retrospective notes, including the item ID, the branch the main tree was on, and the batch date.
2. **After every 5 batches** following the merge of PR #411, tally the number of Step 5.2 Case 1 violations **from parallel batches only** across those batches. If the count exceeds **1 violation per 5 batches**, escalate to the human with the following message:

   > `ESCALATION: Step 5.2 (branch-leak guardrail) has fired more than once in the last 5 batches. Current count: N. Known root cause: the CWD guard (worktree-cwd-guard.sh) cannot propagate to Claude Code subagents dispatched via the Agent tool — each subagent starts with an independent shell context. Worktree discipline for stage subagents is enforced via system-prompt rules in developer.md / item-orchestrator.md and the "Stage-agent handoff branch-skip requirement" in Protocol 91 Step 3. Investigate whether: (1) the item-orchestrator included the required BATCH_CONTEXT=true branch-skip instruction in the stage-agent handoff, and (2) the developer agent observed the branch-skip rule. If violations persist after these fixes are merged, a new failure mode is present — escalate for human analysis.`

3. Do **not** suppress or defer this escalation — it is a signal that the runtime guard needs to be reviewed or extended to cover the new failure mode.

### Retrospective notes during supervision

As you supervise the batch, **proactively save issues, human corrections, and anomalies to memory** (e.g., a `project_batchN_retro_notes.md` memory file) as they happen — do not wait until the retrospective to reconstruct what went wrong. Record:

- Which PR was affected
- What went wrong (wrong base branch, missing label, incomplete review loop, etc.)
- What the root cause was (agent skipped a step, protocol gap, timeout, etc.)
- Whether the human had to intervene and how
- **Step 5.2 tally**: if Step 5.2 fired (Case 1 — wrong branch + clean) for any **parallel-batch** item, record it explicitly so the recurrence counter above can be maintained across batches. Do **not** count serial-dispatch residuals — those are expected and are not violations.

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
  --jq '[.comments[].body | select(test("Automated Reviewer Loop Summary|Reviewer Loop Summary"))] | last // ""' \
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

- CodeRabbit is not listed in `review.on_draft.github` or `review.on_ready.github` in `.ai-dev-workflow.yaml` — there is no CodeRabbit to re-trigger.
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

   **Integration-branch override**: When all PRs in the batch target an integration branch other
   than `develop` (i.e., the batch was built with `BASE_BRANCH=develop-<slug>`), you **must** pass
   `--base develop-<slug>` to `batch-merge.sh` so it queries and merges against the correct branch:

   ```bash
   ./scripts/development-workflow/batch-merge.sh --base develop-<slug> discover --prs <num1,num2,...>
   ```

   When auto-discovery is used (no explicit `--prs` list), `--base` also determines which branch
   is queried for open ready PRs — omitting it would default to `develop` and miss PRs targeting
   the integration branch.

2. **Revalidate readiness from discovery output**:
   - If any PR returned `PR_READY_LABEL=false`, warn the human and require an explicit include-or-skip decision before proceeding. Remove any skipped PRs from the merge list and carry them forward as `skipped_not_ready` for the final summary. Do not proceed silently with any unready PR.
   - If any PR's `PR_LABELS` still contains `needs-fixes`, stop the handoff and return to Step 5 supervision for that PR. A `needs-fixes` PR must not be merged even if human supervision approved the batch earlier.

3. **Present the validated merge plan to the human** and require explicit approval before any merge starts. The human must confirm before the orchestrator invokes `94-batch-merge-protocol.md`.

4. **Once the human approves**, follow `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` starting from **Step 3.5** (the pre-merge clean-state check and sequential merge loop). The merge plan confirmation (Protocol 94 Step 3) has already been satisfied by Step 5.5.3 above, but Step 3.5 has **not** been satisfied and must still run. Pass only the approved ordered PR list after Step 5.5.2 filtering, and include skipped entries in the final summary.

5. **Include the batch-merge summary** (Step 5 of Protocol 94) in the orchestrator's Step 6 summary output.

### Batch-merge routing rule (mandatory)

When merging a parallel implementation batch, **always** invoke `batch-merge.sh discover --prs <list>` followed by execution of `94-batch-merge-protocol.md`. Direct `gh pr merge` calls are only acceptable for single-PR merges or non-implementation PRs (spec, plan). **Never** use `gh pr merge` individually for parallel implementation batches — it bypasses CHANGELOG auto-resolution (Protocol 94 Step 4.3) and active-worktree awareness.

| Merge scenario                         | Required tool                  |
| -------------------------------------- | ------------------------------ |
| Parallel implementation batch (2+ PRs) | `batch-merge.sh` + Protocol 94 |
| Single implementation PR               | `gh pr merge` is acceptable    |
| Spec or plan PR (any count)            | `gh pr merge` is acceptable    |

Violating this rule causes CHANGELOG merge conflicts that must be resolved manually, as observed in the Batch 4 incident (2026-04-22).

### Governance note

The orchestrator prepares and validates the batch but **does not merge autonomously**. The human's explicit approval at Step 5.5 (above) is the required merge gate. This aligns with the policy in `2_batch-merge_implementation-plan.md`: "The agent executes `git merge` locally, but only after the human explicitly confirms the merge plan."

---

## Step 6: Notify Humans

> **STOP — retrospective timing rule (read before writing the summary):**
> Do **NOT** include a retrospective offer anywhere in the batch summary below. PRs that are `ready-for-human-review` still need human review and merge — the batch is not complete yet. Offer the retrospective only **after** the human signals that the PRs have been merged (e.g., via `/batch-merge`, `/post-merge-cleanup`, or an explicit "they're merged" message). Including the retrospective offer in this summary is a guardrail violation.

After all currently eligible items have reached a terminal condition, provide a consolidated summary.

> **Done-report source rule**: Every field in this summary — labels present, CHANGELOG touched, reviewer loop completed, CI green — must be sourced from the artifact queries run in Step 5.1, not from agent self-reports. If Step 5.1 was not run for a PR, run it now before writing the summary. Never assert that a PR is "ready" based solely on what a Work Item Runner claimed.
>
> **Self-check evidence rule**: For every item listed as terminal, include the
> associated `Ground-Truth Completion Verification` result from the Work Item
> Runner summary or from a fresh `item-completion-self-check.sh` run performed by
> the orchestrator. Do not write the final summary when any in-scope terminal
> claim lacks this evidence, reports `discrepancy`, or reports
> `unavailable_required`.
>
> **No in-flight handoff rule**: Do not write the final summary while any
> in-scope PR still has pending/queued checks, incomplete CI evidence, a stale or
> missing reviewer-loop summary, or an unresolved transient watch failure. Those
> states remain under Step 5 supervision until they become green, blocked,
> escalated, merged, or explicitly held by guardrails.

```markdown
## Batch Orchestration Summary

### Batches Executed

- Batch 1 (parallel): [Item A], [Item B]
- Batch 2 (serialized): [Item C] — serialized because both items touch schema migrations

### Proposed Start Batch

- [Issue #N] — [title] — priority: [Urgent/High/Normal/Low] — next stage: [Spec/Plan] — [parallelization note]
- [Issue #M] — [title] — priority: [Urgent/High/Normal/Low] — next stage: [Spec/Plan] — [parallelization note]

Approval required before tracker status changes or branch/PR work starts for these Backlog items.

### Ready for Human Review

- [PR link] — [item] — [stage] — Automated review: ✅ / ⏭️ / ⚠️ — Ground-truth verification: verified / not_applicable / unavailable_optional

### Waiting on Human

- [Item D]: architecture decision needed
- [Item E]: PR already open and waiting to be merged

### Blocked / Escalated

- [Item F]: blocked by [Item G]
- [Item H]: reviewer loop escalated after max cycles

### Guardrails Stops

- [Item I]: STOP — guardrail `<stop_condition_name>` halted this run — [human action required to unblock]

<!-- DO NOT add a retrospective offer here — see Step 6 timing rule above -->
```

❌ **Do NOT append this to the summary:**

> "Would you like to run a retrospective on this batch's work?"

This offer belongs only after the human confirms PRs have been merged.
Adding it here is a protocol violation even when it feels like a natural closing.

Call out any sequential fallback caused by runner limitations so humans can distinguish a workflow constraint from a product dependency.

**Retrospective timing**: Do **not** suggest a retrospective at this point. The batch is not fully complete yet — PRs that are `ready-for-human-review` still need human review and merge before the work is done.

---

## Step 6.5: Post-Merge Follow-up

**Trigger**: Run this step only after the human confirms that the batch PRs have been merged — for example, via `/batch-merge`, `/post-merge-cleanup`, or an explicit "they're merged" message. Do **not** run this step as part of the Step 6 summary.

After merge is confirmed, offer the retrospective:

> Would you like to run a retrospective on this batch's work?

If the human agrees, follow `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`. The retrospective will analyze the PRs from this batch using both GitHub data and the conversation context from this session.
