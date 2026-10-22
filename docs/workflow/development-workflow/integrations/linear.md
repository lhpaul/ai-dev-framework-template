# Integration: Linear (Tracker Work Items)

## Merge-session admission and recovery

After ordinary review/CI/readiness and before any merge-operation audit, hold, bypass, merge or follow-up mutation, follow [Protocol 94 section 3.6](../protocols/94-batch-merge-protocol.md#36-merge-session-admission-and-recovery). Freeze the entire selected ordered set in one authoritative owner-bound session; an unaffordable set admits no prefix. Supply the same `--merge-session` to mutating merge/cleanup helpers, and `--operation merge` to operation-owned audit calls. Direct authorized `gh pr merge` commands run through `workflow-merge-budget.py run-step` with their existing argv unchanged. Read-only risk classification remains separate; delegated merge requires the durable session plus all existing gates.

Deferred reports quota/reset, recorded PR states and pending follow-up without operation-owned remote writes; fresh selected PRs stay unmerged, while recovery deferral retains historical merged/uncertain facts. Waiting records a verified queue/auto-merge submission, stops subsequent selected merges and leaves merge-dependent follow-up pending. Interrupted retains completed/uncertain/pending work locally even if every API fails; stop further selected merges and use explicit verified recovery without duplicate submission or uncertain mutation replay. Completed requires all owned planned follow-up independently verified, including tracker and audit. Budget admission grants no risk, checkpoint, admin or deletion authority. Report the session recovery command together with the existing Ground-Truth Completion Verification before claiming a workflow terminal outcome.

This document describes how to connect the AI development workflow with [Linear](https://linear.app) as the tracker system for workflow work items.

Linear is **optional**. The workflow functions without it — the **Portfolio Orchestrator** simply requires human input to determine what to work on next.

---

## What Linear Adds

- The **Portfolio Orchestrator** can read work item status, priority, and due dates autonomously
- Status fields in Linear map directly to workflow stages
- Labels in Linear map to work item types and scope
- Priority and due date drive automated prioritization
- Agents will read the **current brief** following tracker-agnostic rules in [`issue-tracker.md`](issue-tracker.md)

---

## Work Item Setup

### Status Field → Workflow Stage Mapping

Configure the following statuses in your Linear team settings:

| Linear Status         | Workflow Stage                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| Backlog               | Backlog                                                                                            |
| Writing Spec          | Spec is being drafted and driven to human-ready (draft PR, internal review, reviewer tools, CI)    |
| Spec in Review        | Spec PR is ready for human review / merge                                                          |
| Spec Ready            | Spec PR is merged                                                                                  |
| Writing Plan          | Implementation plan is being drafted and driven to human-ready (same PR-readiness pattern as spec) |
| Plan in Review        | Plan PR is ready for human review / merge                                                          |
| Plan Ready            | Plan PR is merged                                                                                  |
| In Development        | Feature/fix PR in progress (draft through PR readiness, until human-ready)                         |
| Development in Review | Feature/fix PR is ready for human review / merge                                                   |
| Merged                | Feature/fix PR merged to `develop`                                                                 |
| Released              | Released to production                                                                             |

### Labels

**Type labels** (one per work item):

- `Feature` — new capability
- `Bug` — something broken
- `Refactor` — code restructuring or tech-debt cleanup

**Scope labels** (one or more per work item):

- Add labels matching your app/service names (e.g., `Admin Portal`, `API`, `Mobile`)

### Priority

Use Linear's built-in priority field:

- Urgent (1) → Urgent
- High (2) → High
- Medium (3) → Normal
- Low (4) → Low

### Due Date

Set due dates on work items that have a deadline. The **Portfolio Orchestrator** treats work items due within 2 weeks as higher priority than the abstract priority field.

---

## Status: Tracker as Source of Truth

Workflow status (Spec Ready, Plan Ready, In Development) is **not** stored in the spec document. The tracker work item in Linear is the source of truth. The helper script `workflow-next-action.sh --development <path>` derives the next action from **repo state** (presence of implementation plan file, feature branch) so it works without reading a status field from the spec. See `scripts/development-workflow/README.md` and `workflow-next-action.sh` for the logic. Orchestrators and agents with Linear access should read and update work item status in Linear at stage transitions. **Do not call this script for work items in Merged or Released status;** the script cannot distinguish a not-yet-created branch from a deleted one.

---

## Orchestrator Instructions (with Linear)

When the **Portfolio Orchestrator** has Linear access, it should:

1. Read `issue_tracker.custom_fields.project` from `.ai-dev-workflow.yaml` and, if present, scope all item-discovery queries to that project. If absent, emit a warning and fall back to the unscoped team query (see Protocol 90 Step 1a).
2. Query work items by status to find items eligible for advancement
3. Check the `Depends on` field (or linked work item relationships) for dependencies
4. Sort eligible items: due within 2 weeks → priority → creation date
5. Update work item status as stages complete (e.g., set to "In Development" when the feature branch is created)

---

## Bridge Pattern

The shell helper scripts (`workflow-lib.sh`, `workflow-batch-plan.sh`,
`add-backlog-item.sh`, `run-epic-scope-resolver.sh`) cannot reach the Linear API
directly. Instead, they implement a **bridge pattern** so that the orchestrator —
the only actor with Linear access — handles all reads and writes.

### Three-phase flow

1. **Pre-resolve** — Before dispatching any Work Item Runner, the orchestrator
   queries the configured Linear team via MCP to fetch open items with their
   status, type, priority, and dependencies. The orchestrator holds this resolved
   data set and makes it available to each batch step.

2. **Emit deferred action** — When a helper script needs a Linear mutation
   (status change, item creation) or needs to signal that a status read was
   deferred, it prints a structured `TRACKER_ACTION_REQUIRED=` line to stdout
   instead of attempting the operation itself.

3. **Orchestrator applies** — After each Work Item Runner step completes, the
   orchestrator scans the output for `TRACKER_ACTION_REQUIRED=` and
   `TRACKER_UPDATE_REQUIRED:` lines and applies the corresponding Linear
   mutations via MCP.

### `TRACKER_ACTION_REQUIRED=` output format reference

Every deferred-action line follows this structure:

```
TRACKER_ACTION_REQUIRED=<action_type> issue=<issue_id>[ <extra_fields>]
```

| Action type   | Emitted by                           | Extra fields example                     | Description                                               |
| ------------- | ------------------------------------ | ---------------------------------------- | --------------------------------------------------------- |
| `set_status`  | `update_tracker_status_best_effort`  | `target_status='Plan in Review'`         | Linear item status should be moved to `<status>` via MCP. |
| `read_status` | `get_tracker_status_for_issue`       | _(none)_                                 | Status read was deferred; orchestrator supplies the value. |
| `create_item` | `add-backlog-item.sh create`         | `title='My New Feature'`                 | New Linear item should be created via MCP.                |

`set_status` is **forward-only** at the native bridge (same guarantee as
GitHub Projects' `update_tracker_status_best_effort` order check): before
applying, the orchestrator reads the item's current Linear status and skips
the update when the item is already at or beyond the target in
[`tracker-status-mapping.md`](../tracker-status-mapping.md) (e.g. target
`Merged` while the item is `Released`), recording the skip. Helpers may still
emit `TRACKER_ACTION_REQUIRED=set_status` on re-runs; the bridge must not
regress status.

**Quoting convention**: when a field value contains spaces, it is
single-quoted in the output — for example, `target_status='Plan in Review'`
rather than `target_status=Plan in Review`. Single-word values are not
quoted. Strip the surrounding single quotes when reading the value.
Linear status names do not contain single quotes, making this quoting safe
for all controlled-vocabulary values in the workflow.

**Orchestrator collection loop** (pseudocode):

```text
for each Work Item Runner output line:
  if line starts with "TRACKER_ACTION_REQUIRED=":
    parse action_type from "TRACKER_ACTION_REQUIRED=<action_type> ..."
    parse issue from "... issue=<id> ..."
    parse extra_field value (strip single quotes if present)
    if action_type is set_status:
      read current Linear status via MCP
      if current is at or beyond target_status in tracker-status-mapping:
        record skip; do not updateIssue
      else:
        apply via Linear MCP updateIssue
    else:
      apply via Linear MCP (e.g., createIssue)
  if line starts with "TRACKER_UPDATE_REQUIRED:":
    parse issue number and target_status
    apply the same forward-only set_status rule via Linear MCP
```

The `TRACKER_UPDATE_REQUIRED:` format (used in protocol 91 Step 8b) is a
complementary signal emitted by the agent-level summary when a tracker update
could not be performed inline. Both formats must be collected and applied.

### Durable merge-operation bridge

During an admitted merge session, emitting a deferred action is pending work,
not successful reconciliation. Before an authorized Linear MCP mutation,
record its declared tracker step through `before-step` with the same session,
selected repository/PR, issue and expected status. Retain the executor token
and durable intent timestamp. Do not continue to another selected merge while
this bridge is outstanding. A dead executor never authorizes replay of an
uncertain mutation.

After mutation, make an independent MCP issue read against the owning tracker.
Supply normalized proof to `record-provider-result` with the same declared
tracker step and `--evidence <proof.json>`. The proof contains `provider`
(`linear`), `issue`, `repo` (owning tracker repository), `statusName`,
`statusId`, distinct `mutationRequestId` and `readRequestId`, and `observedAt`
after the journaled intent. Preserve the source responses/request identifiers
as reviewable evidence; an echoed mutation response is not an independent read.

For recovery, first request explicit `resume` to establish the current recovery
attempt. If it requires fresh Linear evidence, independently read the owning
issue and submit the normalized proof for the existing declared intent through
`record-provider-result`, then request `resume` again. The journal binds that
proof to the current recovery attempt and permits one continuation. A later
recovery requires a new read; an earlier successful proof is historical evidence,
not current verification or permission to repeat a mutation.

Missing or mismatched issue/owner/status/read evidence records Interrupted and
keeps reconciliation pending. Explicit recovery verifies live state before any
retry. The best-effort "retry once and continue" rule below applies only outside
merge sessions; merge sessions cannot become Completed or advance another
selected merge without verified bridge discharge. No new Linear API client is
introduced.

### Priority Drift Detection

The Linear API can return a stale or drifted priority value when an item is
read back shortly after a write (e.g., a status update applied during
post-merge cleanup). The priority returned in the API response may reflect
a transient race condition between the write and the Linear webhook rather
than an intentional change.

**Detection rule**: After every `updateIssue` MCP call, read back the issue's
current priority from the API response (or issue a follow-up `issue(id:)` query
if the mutation response does not include the priority field). Compare the
returned value against the priority recorded at pre-resolve time (Phase 1).
If the values differ, emit the following warning to the run summary before
continuing:

```
PRIORITY_DRIFT_WARNING: issue=<id> dispatch_priority=<value> current_priority=<value>
  — priority changed between dispatch and post-update read.
  Possible causes: concurrent edit, transient API artifact, or webhook race.
  No workflow action taken. Human should verify the priority in Linear.
```

Do **not** silently accept the drifted value. Do **not** automatically restore
the original priority — a concurrent human edit is a valid reason for the
change. The warning surfaces the discrepancy for human review.

**Outside a merge session, post-write re-read (optional but recommended)**: After applying any
`set_status` mutation, issue a follow-up `issue(id:)` query to confirm the
write was reflected. If the returned status does not match the target status,
emit:

```
TRACKER_WRITE_UNCONFIRMED: issue=<id> target_status=<expected> actual_status=<returned>
  — status not reflected in API read-back after write.
  May be a transient API artifact. Retry the update once; escalate if the
  mismatch persists after retry.
```

Retry the `updateIssue` call once if `TRACKER_WRITE_UNCONFIRMED` fires. If the
re-read still does not reflect the target status after one retry, log
`TRACKER_SYNC_SKIPPED` (using the existing format) with `reason=write_unconfirmed_after_retry`
and continue — do not block the workflow.

---

## Branch Naming with Linear

When a Linear work item exists, use the Linear identifier as the branch slug prefix:

| Branch type         | Pattern                                     | Example                                 |
| ------------------- | ------------------------------------------- | --------------------------------------- |
| Spec                | `spec/[work-item-id]-[slug]`                | `spec/ENG-123-user-auth`                |
| Implementation plan | `implementation-plan/[work-item-id]-[slug]` | `implementation-plan/ENG-123-user-auth` |
| Feature             | `feature/[work-item-id]-[slug]`             | `feature/ENG-123-user-auth`             |
| Refactor            | `refactor/[work-item-id]-[slug]`            | `refactor/ENG-321-extract-auth-service` |
| Bug fix             | `fix/[work-item-id]-[slug]`                 | `fix/ENG-456-login-redirect`            |
| Hotfix              | `hotfix/[work-item-id]-[slug]`              | `hotfix/ENG-789-payment-crash`          |

The `[slug]` is a short kebab-case description derived from the work item title (omit common words like "add", "fix", "update" to keep it short). Linear also auto-suggests a branch name on each work item — use it directly if preferred.

---

## Custom Fields

The `issue_tracker.custom_fields` flat map in `.ai-dev-workflow.yaml` holds provider-specific fields that extend the standard `issue_tracker` configuration. For the Linear provider, the following keys are recognised by workflow scripts:

| Key                    | Format                   | Effect                                                                                                                                                                                                                                                                        |
| ---------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `project`              | Linear project ID string | When set, (1) scopes Portfolio Orchestrator item discovery to this project only — items from other projects are excluded from the candidate list; and (2) associates new issues with this project on creation. The project ID is found in the Linear project URL (`https://linear.app/<team>/projects/<project-id>`) or via the Linear API. |
| `release_field`        | Custom field key/name    | Optional future write target for recording the shipped release on a Linear issue. Shell helpers warn that MCP/API access is required.                                                                                                                                         |
| `release_label_prefix` | Label prefix string      | Label fallback for release stamping. Defaults to `release/`, producing labels like `release/v1.2.0`. Shell helpers warn that MCP/API access is required to apply it.                                                                                                          |

When `project` is absent from `custom_fields` (or `custom_fields` itself is absent), the Portfolio Orchestrator queries all open items visible to the API token — which may include items from other codebases or projects — and emits a visible warning. Issue creation proceeds without a project association. This fallback is fully backward-compatible but is not recommended for multi-project Linear workspaces.

To set a project association, add the following to `.ai-dev-workflow.yaml` under `issue_tracker`:

```yaml
issue_tracker:
  provider: linear
  custom_fields:
    project: my-linear-project-id
    release_label_prefix: release/
```

Read the value in a script using the `workflow_issue_tracker_custom_field` helper:

```bash
source scripts/development-workflow/workflow-lib.sh
project_id=$(workflow_issue_tracker_custom_field project)
```

Unrecognised keys in `custom_fields` are silently ignored by all current scripts.

### Release Stamping

Linear has no global first-class release object. The default workflow release
marker is a label named `release/vX.Y.Z`, using the configurable
`release_label_prefix` above. Teams that maintain a Linear custom field for
release tracking can set `release_field`; an MCP/API-backed implementation can
write that field during release cleanup.

Shell-only cleanup helpers cannot mutate Linear labels or custom fields directly.
They emit release-stamp guidance plus `TRACKER_ACTION=linear_mcp_or_api_required`
and exit non-zero unless `--best-effort` was explicitly accepted. The
orchestrator or a Linear MCP runner must apply the release label/custom field
and then transition every listed `TRACKER_ISSUES` item from `Merged` to
`Released` before reporting the release as complete.

When cleanup is invoked with `--from-changelog`, Linear scope is **not** the set
of IDs matched in the CHANGELOG version section alone (#1982). The canonical
**consistency matrix** (gate inputs, allowed outcomes, required next actions,
and operator signals) lives in
[`05-prepare-release-protocol.md`](../protocols/05-prepare-release-protocol.md)
Step 9.1. The CHANGELOG is only a complement: a missing `CHANGELOG.md` or version section prints
`CHANGELOG_SECTION_UNAVAILABLE version=vX.Y.Z (Linear scope derived from merged
PRs only)` and scope still comes from merged PRs. The helper derives scope from
merged PRs in the release git range (previous tag → verified release tag
`refs/tags/...` or `--release-head`; never checkout `HEAD` or unqualified names
that could resolve a same-named branch): for each commit it resolves associated
PRs only through GitHub `commits/<sha>/pulls` (subject `(#N)` is never
sufficient evidence), against the checkout/component repository (not an
inherited `GH_REPO` override). A well-formed empty JSON array `[]` means the
commit has no associated PR (direct push / local merge): it contributes no
IDs, emits `RELEASE_SCOPE_COMMIT_WITHOUT_PR sha=<short>` once per SHA, and
does **not** make the scope incomplete. Empty response body, non-array JSON,
`[null]`, `[{}]`, or any element missing an integer `number` or a
`merged_at` / `merged` / `mergedAt` field is malformed evidence and produces
`RELEASE_SCOPE_INCOMPLETE` with that SHA listed. A PR is accepted when it is
merged and its merge/head commit is in the range (or the associating range SHA
when those fields are absent), regardless of the PR base branch (including
nested `feature/*` or `develop-<slug>` parents). Documentation-stage head
branches (`spec/*`, `implementation-plan/*`) and release/backport branches are
`RELEASE_SCOPE_SKIPPED` (`documentation_stage_pr_only` /
`release_or_backport_branch_pr`); every other merged prefix (including
`chore/`, `ci/`, `feature/`, `fix/`, …) counts as Released shipping evidence.
Linear IDs come from each PR’s `headRefName` / REST `head.ref` and `title`
(not commit text or PR body). Changelog-only mentions — including
cross-references such as “did not ship LEA-298” and expanded ranges — are
skipped with
`RELEASE_SCOPE_SKIPPED issue=<ID> reason=changelog_mention_without_merged_pr`
(and appear under `release_scope_skipped` in component `--json` output). The
previous-tag boundary first resolves a **canonical SemVer tag namespace** from
local ∪ remote evidence for the bare/`v` spellings of the requested version
(Linear-only requested tag spelling; component prefixes such as `mobile-v…`
have a single spelling). Resolution is **identical with and without
`--release-head`** (never adopt a co-pointing component tag): sole existing
spelling → adopt it (e.g. request `v1.1.0` with only `1.1.0` → namespace
`1.1.0`); both spellings agreeing on one SHA → keep the requested spelling;
local↔remote or bare-vs-`v` SHA conflict →
`RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace` (stderr
`ambiguous_release_tag_namespace version=<requested> (bare/v spellings or
local/remote tag SHAs disagree)`); neither spelling present → keep the
requested spelling (never invent `v-`). Only then does previous-tag selection
use **that namespace’s PREFIX** and SemVer 2.0.0 precedence (prerelease <
release; build metadata ignored); invalid prerelease identifiers are ignored
with `SEMVER_TAG_IGNORED`; `first_release` only when no same-prefix remote tag
is strictly lower. Shallow clones, remote tag-list failures, or a preceding
remote tag whose peeled commit is missing locally or disagrees with a local
tag of the same name emit
`RELEASE_SCOPE_INCOMPLETE reason=previous_release_boundary_unavailable` (the
helper never `git fetch`es during scope resolution — fetch tags and rerun). A
fully resolved range with zero Linear IDs is an empty scope (not incomplete). If
the release ref is unavailable or PR resolution fails for any commit
(including malformed `commits/<sha>/pulls` evidence), the helper emits
`RELEASE_SCOPE_INCOMPLETE` (`reason=release_ref_unavailable` or
`unresolved_shas=...`) and fails closed. Explicit `--issue` / `--issues` are
unioned with the derived scope and are never filtered. The canonical
consistency matrix (including namespace rows) lives in
[`05-prepare-release-protocol.md`](../protocols/05-prepare-release-protocol.md)
Step 9.1.

---

## Graduation Closeout (Linear)

`graduation-closeout.sh` and `graduation-closeout-from-merged-pr.sh` honor
`issue_tracker.provider: linear` the same way post-merge cleanup does (#1930 /
#1984):

- `--epic` must be a native Linear ID with team prefix (e.g. `LEA-326`). A bare
  number fails closed — the helper never treats the numeric suffix as a GitHub
  issue. If `provider: linear` is only visible under a commented
  `issue_tracker:` header, closeout fails closed before mutation — remove the
  trailing comment so the shared tracker bridge can read the provider.

- GitHub `subIssues` / parent GraphQL and `defer-epic-close` label writes are
  skipped. Epic (and other Linear) status transitions are emitted as
  `TRACKER_ACTION_REQUIRED=` deferred actions for the orchestrator MCP bridge.
- GitHub issues are closed **only** via same-repo structured
  `closingIssuesReferences` on merged PRs targeting `develop-<slug>`. Text-only
  references (`Closes #N` in title/body, including fenced or indented examples)
  are reported as `LINEAR_GITHUB_REF_SKIPPED issue=N reason=not_structurally_linked`
  and never mutate GitHub. Foreign-repo structured refs are skipped. GitHub does
  not populate `closingIssuesReferences` for many non-default-branch bases, so on
  integration branches typically **no** GitHub issue is closed — safe by design.
  Decision-gate outcomes are listed in Protocol 05b Step 5 **Graduation closeout
  decision-gate consistency matrix**.
- Both scripts accept `--dry-run` to print planned mutations without applying
  them.

See Protocol 05b Step 5 for the primary operator command.

---

## Workflow: Advancing Statuses

The **Portfolio Orchestrator**, **Work Item Runner**, or stage agent updates the
Linear work item status at each stage transition. The transitions and the
status vocabulary are defined once in
[`tracker-status-mapping.md`](../tracker-status-mapping.md). Resolve the target
with `scripts/development-workflow/tracker-status-for.sh`, then apply it through
the Linear MCP handoff described above.

---

## Linear MCP Server (for Claude Code / Cursor)

To give your AI agent direct Linear access, configure the Linear MCP server:

```json
// .cursor/.mcp.json or equivalent MCP config
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-linear"],
      "env": {
        "LINEAR_API_KEY": "your-linear-api-key"
      }
    }
  }
}
```

With the MCP server, agents can read and update work items directly without the human copying tracker data into the chat.

---

## Without Linear

If you don't use Linear, the **Portfolio Orchestrator** asks the human:

> "What should I work on next? Please provide:
>
> - Feature name and slug
> - Path: Full Pipeline / Refactor / Fast Track / Hotfix
> - Priority context (if any)
> - Dependencies (if any)"

This works fine for small teams or early-stage projects.
