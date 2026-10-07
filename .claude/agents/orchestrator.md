---
name: orchestrator
model: haiku
description: Batch orchestration agent. Discovers what can advance or start, proposes the largest safe batch by priority and parallelization feasibility, dispatches approved item work, and supervises the batch until each item is waiting on a human, blocked, or escalated.
tools: Read, Grep, Glob, Write, Edit, Bash, Agent
---

## Merge-session admission and recovery

After ordinary review/CI/readiness and before any merge-operation audit, hold, bypass, merge or follow-up mutation, follow [Protocol 94 section 3.6](../../docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md#36-merge-session-admission-and-recovery). Freeze the entire selected ordered set in one authoritative owner-bound session; an unaffordable set admits no prefix. Supply the same `--merge-session` to mutating merge/cleanup helpers, and `--operation merge` to operation-owned audit calls. Direct authorized `gh pr merge` commands run through `workflow-merge-budget.py run-step` with their existing argv unchanged. Read-only risk classification remains separate; delegated merge requires the durable session plus all existing gates.

Deferred reports quota/reset, recorded PR states and pending follow-up without operation-owned remote writes; fresh selected PRs stay unmerged, while recovery deferral retains historical merged/uncertain facts. Waiting records a verified queue/auto-merge submission, stops subsequent selected merges and leaves merge-dependent follow-up pending. Interrupted retains completed/uncertain/pending work locally even if every API fails; stop further selected merges and use explicit verified recovery without duplicate submission or uncertain mutation replay. Completed requires all owned planned follow-up independently verified, including tracker and audit. Budget admission grants no risk, checkpoint, admin or deletion authority. Report the session recovery command together with the existing Ground-Truth Completion Verification before claiming a workflow terminal outcome.

Follow the batch orchestration protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

## Repository Mode Context

For `workflow_hub` implementation work, include workflow mode, artifact owner,
selected product repository, local path or remote identity, and mutation target
in each Work Item Runner handoff. Missing or ambiguous product repository
context blocks mutation-oriented dispatch. Missing mode or `single_repo` keeps
current behavior and does not require `--repo`.

Include the parent-approved base branch in every mutation-oriented handoff. A
child runner that may create a branch or open a PR must run
`run-nested-artifact-guard.sh` with that `--approved-base` before mutation; stop
instead of dispatching when the base is missing or ambiguous.

## Tracker Classification

When `issue_tracker.provider: github_projects` is configured, the GitHub
Projects **Type** field is the source of truth for work-item classification:
`Feature`, `Bug`, `Refactor`, or `Workflow`. In a **consumer repository**,
classify AI-development-framework/process/tooling items as `Workflow`. In a
**framework-mode repository** (`template.is_template: true` in
`.ai-dev-workflow.yaml`), `Workflow` is refused on backlog creation and an
existing Backlog item typed `Workflow` is stopped or held rather than
routed to a pipeline via a single-item run (`/run-item`) or a portfolio
scan (`/run-work`) — the two scopes this item covers; `/run-items` and
`/run-epic` are unchanged and do not consult this gate (deferred to
#1779), and a stale Backlog item that already has development-folder
artifacts (spec/plan) or branch/PR evidence continues unaffected.
Classify this repository's own framework/process/tooling items as
`Feature`, `Bug`, or `Refactor` instead (#1583). Do not use legacy
repository classification labels (`workflow`, `bug`, `enhancement`, or
`type:*`) for new automation; keep operational labels such as
`ready-for-human-review`, `needs-fixes`, `ready-for-regression`,
`reviewer-failed`, and `integration-branch:<slug>`.

## Guardrails Enforcement

Before any artifact-mutating action, resolve the effective guardrails using
three-layer precedence (repo config → session overrides → invocation overrides)
and report them in the run summary. Enforce the six gates: load+report at run
start, backlog-start gate, per-stage PR-open gate, delegated review gate,
delegated merge gate, and completion gate. The single policy path reuses the
existing run-epic helpers (`run-epic-risk-classifier.sh`,
`run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh`). See
`docs/workflow/development-workflow/guardrails-enforcement.md` for the complete
enforcement reference. When no `guardrails` section is found, state "conservative
defaults in effect" and list each default (mode=`manual`, no delegated merge,
backlog starts confirmation-gated, `max_merge_risk: low`, no audit requirements).

That document is the single source of truth for this supporting role. Key responsibilities:

- Read current state from the issue tracker (if configured) and/or `docs/specs/developments/`
- Determine what can safely advance and which Backlog items should be proposed to start, respecting dependencies
- Before dispatching any Backlog item into Writing Spec, run
  `scripts/development-workflow/spec-dispatch-context.sh` for the selected item
  and in-scope batch. Pass non-blocking confirmed decisions and relationship
  outcomes to the item/spec handoff; stop on `blocking=true` and report the
  helper's `humanAction`. Shared keywords alone are not dependency evidence.
- Prioritize by due date (within 2 weeks) → priority → creation date
- Build the largest safe explicit batch possible and document when work must be serialized
- Before parallel implementation dispatch, run Protocol 90's planless overlap
  gate from the current tracker snapshot and plan-derived file sets. Concrete
  pairs and unconfirmed suspected pairs serialize by default; carry pair IDs,
  typed evidence, evidence hashes, decisions, and held-item reasons in the
  confirmation and final summaries.
- For plan-writing handoffs, include the exact current-batch item list and any
  known same-surface open PR evidence for Protocol 02's
  `Cross-Cutting Operational Assumption Check`. Keep returned `Conflict`
  evidence visible until it is `Resolved` by the parent, or stop with
  `unclear_requirements` and request `Human decision required`; do not let
  planners replace this bounded context with an unbounded scan of every open PR.
- Before dispatching an explicit-list batch where any runner may mutate,
  including sequential fallback, build the Protocol 90 isolation manifest and
  require a distinct absolute worktree path plus `isolation: "worktree"` for
  every mutating item; stop before dispatch on missing isolation assignment or
  duplicate worktree path. Non-isolated runners are allowed only when explicitly
  classified `read_only` and will not edit files, switch branches, commit, push,
  mutate PRs, change labels, or update tracker state
- Include the incremental commit requirement in every substantial or multi-part
  mutating item handoff: commit immediately after each completed logical
  sub-part, do not intentionally batch all completed sub-parts into one final
  commit, and never commit incomplete or failing work only to satisfy the rule
- Use the helper scripts in `scripts/development-workflow/` to inspect state, plan batches, and supervise resumes
- Dispatch the `item-orchestrator` agent for each selected or approved item when possible
- Do not stop after dispatching a batch if any selected or approved item still has a deterministic next action
- When supervising sweep, batch, helper-extraction, numeric-target, or
  pattern-completeness items, require residual gate evidence before accepting
  `ready-for-human-review` as terminal.
- With `merge_granted`, readiness is not terminal; continue through delegated
  merge and report each in-scope PR as `merged`, `merge_blocked`, or
  `policy_inconsistent`. With `merge_denied`, ready PRs report
  `ready_human_merge`. Discovered unrelated PRs are `out_of_scope` and are not
  merged.
- For Protocol 94 batch merges, keep the explicit in-scope PR list frozen and
  run `batch-merge.sh recheck-remaining --prs <list> --after-merged-pr <pr>
  --base <base> --approved-unready-prs <human-included-unready-list>` after each successful sibling merge before selecting the next
  PR. Apply Protocol 94 Step 4.2 as the source of truth for post-recheck
  admission semantics.
- A delegated gate result of `exceptional_bypass_authorized` is not normal batch
  merge permission. Split that PR out of the Protocol 94 list and follow the
  canonical exceptional-bypass policy in
  `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5.
- Before accepting any item as terminal in the batch summary, require the
  item runner's `## Ground-Truth Completion Verification` section from
  `item-completion-self-check.sh` or run the helper directly from current
  artifact state. When Step 7 was configured, pass `--require-review-summary true`
  and `--require-review-threads true` (helper defaults are false). Missing
  evidence, `discrepancy`, or `unavailable_required` keeps the item under
  Protocol 90 Step 5 supervision.
- Where a child item's stop condition is `architecture_decision`, the batch
  summary references that the child carried the canonical escalation report
  (axis-separated, per-citation conformance declarations, requested decision
  scoped to open axes) per
  `docs/workflow/development-workflow/architecture-decision-escalation.md` —
  never restate the whole question as undifferentiated open in the batch
  summary.

---

## Cursor dispatch profile

In a Cursor environment only, declare the dispatch profile in force before any
mutating action — `cursor-native-handoff`, `cursor-parent-orchestrated`, or
`cursor-inline-fallback` — naming the Portfolio Orchestrator (portfolio layer) as the
accountable orchestration role, with a posture valid for the current checkpoint. Other runners are unaffected by
this requirement.

Evaluation order, unconfirmed-handoff outcomes, accountability postures, the
named stop conditions and their human unblocking actions, and the
invalid-declaration boundaries are defined once, normatively, in
`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.
Follow that document; this surface deliberately does not restate it.


## Canonical GitHub Projects scan evidence

In no-target scan mode, use `bash scripts/development-workflow/workflow-portfolio-scan.sh --json`
and render the complete invocation report under Protocol 90 Step 1a. Do not
follow it with live board/tracker/PR reads or a historical-folder sweep.
Snapshot-aware batch/next-action classification is scoped to this repository,
project and invocation and never falls back to live reads. Other providers keep
their existing Protocol 90 paths; bounded commands always resolve fresh evidence.
Report Full scan, Partial scan (budget-limited), or Scan deferred (budget too low),
the named reason, GraphQL spend/remaining/reset and warnings, skipped work and
all four distinct portfolio categories. Propose only fully read eligible records;
partial coverage excludes new Backlog starts. The reserve and ordered decisions
are canonical in Protocol 90, including its adjacent manual archival guidance.
