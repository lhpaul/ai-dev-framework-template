# Orchestration Command Finalization — Spec

**Epic**: #1072 Finalize orchestration commands
**Supersedes**: parts of spec #1048 (Orchestration Command Refactor) — see "Relationship to Spec #1048"
**Depends on**: Epic #1047 (Refactor orchestration commands) graduated to `develop`

---

## Overview

Spec #1048 reframed the orchestration command map so bounded single-item work
(`/run-item`) and bounded epic work (`/run-epic`) became explicit commands while
`/run-work` retained two portfolio execution modes: a no-target scan that could
proceed straight to mutation and an `explicit_list` mode that executed a named
multi-item batch. In practice that left two unresolved seams. First, `/run-work`
still both *discovers* and *executes* portfolio work, so operators cannot rely on
it as a safe read-only "what should I do next" command. Second, epic execution
was reachable two ways — `/run-epic` and an `--items` style list — which blurred
the line between "advance an epic's native children" and "advance an arbitrary
list of items."

This feature finalizes the command map into three crisp layers — **discover**,
**execute**, **land** — and assigns each command a single role:

- **`/run-work` becomes scan-only.** It is a read-only portfolio discovery
  command that proposes one to three batch options and performs no mutation. It
  no longer executes batches itself.
- **A new `/run-items` command owns explicit multi-item execution.** It takes a
  bounded list of named items, runs the shared bounded prelude, and advances them
  through Protocol 90 `explicit_list` mode straight to `develop` (no integration
  branch).
- **`/run-epic` becomes epic-only.** The user-facing `--items` list form is
  removed; `/run-epic` advances only an epic's native sub-issues via Protocol 95.
  Integration branches are used only when the epic or its items carry an
  `integration-branch:<slug>` label.

Every mutating execute command follows a **two-step lifecycle**: it advances
work only to `ready-for-human-review` and stops; merging is a deliberate second
step performed by `/batch-merge`. Every mutating command also runs the **shared
bounded prelude with always-confirm** — a human confirmation of policy and
checkpoints before any mutation — backed by sensible default `guardrails`
uncommented in `.ai-dev-workflow.yaml`. The `/run-work` router redirects
mis-targeted invocations: two or more tokens redirect to `/run-items`; a single
token redirects to `/run-item` or `/run-epic`.

The `run` command prefix is kept; only the suffix semantics are corrected. The
deprecated execution paths (`/run-epic --items`, `/run-work` execution modes)
redirect to `/run-items` for one transition release.

## Relationship to Spec #1048

Spec #1048 remains the historical record of the command-map refactor delivered
under Epic #1047. This spec supersedes the parts of #1048 that gave `/run-work`
two execution modes and allowed epic execution through an item list:

| #1048 decision (superseded) | #1075 finalization |
| --- | --- |
| `/run-work` modes `no_target_scan` **and** `explicit_list` both execute via Protocol 90 | `/run-work` is **scan-only** (read-only); `explicit_list` execution moves to the new `/run-items` command |
| Explicit multi-item batches run under `/run-work` | Explicit multi-item batches run under `/run-items` |
| Epic execution reachable via `/run-epic` and item-list flag forms | `/run-epic` is **epic-only**; item lists redirect to `/run-items` |
| `/run-work` may proceed to mutation after scan | `/run-work` never mutates; it proposes batch options and hands the operator a copy-ready execute command |

Everything in #1048 not listed above (the shared bounded prelude, `/run-item`,
Protocol 90/91/95 ownership boundaries, parallelism lane defaults) remains in
force and is reused by this spec rather than redefined.

## Brief Objective List

1. Command map and operator cheat sheet across three layers (discover → execute → land).
2. Protocol ownership boundaries: scan vs Protocol 90 `explicit_list` vs Protocol 91 vs Protocol 95 epic-only.
3. Deprecation: `/run-epic --items` → `/run-items`; `/run-work` execution modes → `/run-items`.
4. Two-step lifecycle: execute commands stop at `ready-for-human-review`; merge via `/batch-merge`.
5. Defaults with always-confirm: sensible `guardrails` uncommented; every mutating command confirms policy and checkpoints before mutation.
6. No integration branch for `/run-items` — straight to `develop`.
7. Router redirects: two-plus tokens → `/run-items`; single token → `/run-item` or `/run-epic`.
8. Acceptance criteria tracing to implementation children **#1076–#1080**.

---

## Command Map (operator cheat sheet)

| Layer | Command | Role | Mutates? | Protocol |
| ----- | ------- | ---- | -------- | -------- |
| Discover | `/run-work` | Read-only portfolio scan — proposes 1–3 batch options; emits copy-ready execute commands | No | Protocol 96 scan |
| Execute | `/run-item <target>` | One non-epic item; bounded prelude then single-item advancement | Yes (to ready) | Protocol 91 |
| Execute | `/run-items <list>` | Explicit multi-item list; bounded prelude then bounded batch; base `develop` | Yes (to ready) | Protocol 90 `explicit_list` |
| Execute | `/run-epic --epic <n>` | Native epic sub-issues only; integration branch only when items carry `integration-branch:<slug>` | Yes (to ready) | Protocol 95 |
| Land | `/batch-merge` | Merge ready PRs after human confirms the merge plan | Yes (merges) | Protocol 94 |

---

## Use Cases

### Use Case 1: Discover work with scan-only `/run-work`

**Actor**: Workflow operator who wants to know what can safely advance without
committing to mutation yet
**Preconditions**: The operator invokes `/run-work` with or without a target.

**Steps**:

1. The actor inspects tracker and repository state (read-only).
2. The actor proposes one to three candidate batch options, each with its scope,
   stage lanes, held-back items, and rationale.
3. For each proposed option, the actor emits the copy-ready execute command the
   operator would run next (`/run-items <list>`, `/run-item <target>`, or
   `/run-epic --epic <n>`).
4. The actor stops without mutating.

**Postconditions**: No tracker status, branch, PR, or merge state changes. The
operator holds one or more proposed batches and the exact execute command for
each.

**Information shown**:

- Routing mode `scan`.
- Proposed batch options (1–3) with scope, lane assignments, and held-back items.
- The recommended execute command per option.

**Actions available**:

- Choose an option and run its execute command.
- Decline and stop.

**Considerations**:

- `/run-work` never executes a batch itself. Selecting an option is a separate,
  deliberate execute step (Use Cases 3–5).

### Use Case 2: Router redirect from `/run-work` to an execute command

**Actor**: Operator who invokes `/run-work` with concrete targets expecting it to
run them
**Preconditions**: The operator supplies one or more target tokens to `/run-work`.

**Steps**:

1. The router classifies the invocation.
2. If two or more tokens resolve, the router records a redirect to `/run-items`
   with the resolved list and performs no mutation.
3. If exactly one non-epic token resolves, the router redirects to `/run-item`.
4. If exactly one epic-like token (or `--epic`) resolves, the router redirects to
   `/run-epic`.
5. The operator re-invokes the recommended execute command.

**Postconditions**: No mutation occurs under `/run-work`; the operator receives a
clear redirect naming the execute command and its target tokens.

**Information shown**:

- Redirect reason and the recommended command plus target tokens.

**Actions available**:

- Re-invoke `/run-items`, `/run-item`, or `/run-epic`.
- Stop if the operator declines.

**Considerations**:

- A two-plus-token redirect points to `/run-items` (not to portfolio execution
  under `/run-work`, which no longer exists).

### Use Case 3: Advance one item with `/run-item`

**Actor**: Operator who knows exactly which single non-epic item, branch, PR, or
development folder to advance
**Preconditions**: The operator invokes `/run-item <target>` resolving to one
non-epic item.

**Steps**:

1. The actor runs the **shared bounded prelude** (scope resolution, guardrails,
   policy recommendation, checkpoint classification) before any mutation.
2. The human confirms, customizes, or waives the recommended policy and
   checkpoints (**always-confirm**).
3. The actor advances the resolved item through Protocol 91 until it reaches
   `ready-for-human-review`, then stops.

**Postconditions**: Exactly one item advances to `ready-for-human-review`. The PR
is not merged. Prelude policy and checkpoint state are recorded for audit.

**Information shown**:

- Resolved item identity and prelude outputs (policy fields, checkpoint list,
  guardrails consulted).
- Routing confirmation: single-item bounded run.

**Actions available**:

- Continue after confirmation.
- Stop when scope is ambiguous or authority is insufficient.

**Considerations**:

- Merging is a separate step performed later by `/batch-merge`.
- An epic-like target redirects to `/run-epic` rather than being treated as one
  item.

### Use Case 4: Advance an explicit list with `/run-items`

**Actor**: Operator who names two or more explicit targets for a bounded batch
**Preconditions**: The operator invokes `/run-items <list>` with a bounded list
of issues, branches, PRs, or development folders.

**Steps**:

1. The actor treats the list as a hard scope boundary.
2. The actor runs the **shared bounded prelude** and the human confirms policy and
   checkpoints (**always-confirm**).
3. The actor advances only the listed items through Protocol 90 `explicit_list`
   mode, using base branch `develop` (no integration branch).
4. The actor advances each item only to `ready-for-human-review`, logs and skips
   any out-of-scope encounters, then stops.

**Postconditions**: Routing mode `explicit_list`; no scope expansion beyond the
supplied list. Each listed item reaches `ready-for-human-review` against
`develop`. No PR is merged.

**Information shown**:

- Exact bounded scope and lane assignments.
- Items held for implementation serialization or runtime exclusivity.
- Out-of-scope items detected and skipped.

**Actions available**:

- Dispatch parallel-safe lanes.
- Hold implementation items when defaults require serialization.

**Considerations**:

- `/run-items` is the new home for the explicit-list execution that previously
  ran under `/run-work`.
- `/run-items` never creates a `develop-<slug>` integration branch; integration
  branches are an epic concern (Use Case 5).

### Use Case 5: Run an epic with epic-only `/run-epic`

**Actor**: Operator who names an epic for a bounded run of its native children
**Preconditions**: The operator invokes `/run-epic --epic <n>`.

**Steps**:

1. The actor performs read-only scope resolution over the epic's native
   sub-issues.
2. The actor runs the **shared bounded prelude** and the human confirms policy and
   checkpoints (**always-confirm**).
3. The actor advances eligible in-scope child items per Protocol 95, each only to
   `ready-for-human-review`.
4. The actor uses an integration branch (`develop-<slug>`) **only** when the epic
   or its items carry an `integration-branch:<slug>` label; otherwise children
   target `develop`.

**Postconditions**: Only the epic's native sub-issues are advanced. No PR is
merged. Integration-branch usage is label-driven.

**Information shown**:

- Resolved child-item groups (eligible, blocked, in review).
- Prelude policy and checkpoint recommendations.
- Whether an integration branch applies and why.

**Actions available**:

- Advance eligible items after confirmation.
- Stop on ambiguous scope or blocked dependencies.

**Considerations**:

- The user-facing `--items` list form is removed. An item-list invocation
  redirects to `/run-items` (Use Case 6).

### Use Case 6: Use a deprecated execution path

**Actor**: Operator or automation using a deprecated invocation —
`/run-epic --items <list>` or a `/run-work` execution-mode form
**Preconditions**: A deprecated invocation is supplied during the one transition
release.

**Steps**:

1. The command recognizes the deprecated form.
2. It emits a deprecation notice and redirects to `/run-items` with the
   equivalent list, performing no mutation under the deprecated path.
3. The operator re-invokes `/run-items`.

**Postconditions**: Legacy invocations are steered to `/run-items`; no execution
happens through the deprecated path.

**Information shown**:

- Deprecation notice naming the replacement command and the transition-release
  window.

**Actions available**:

- Re-invoke `/run-items`.

**Considerations**:

- The optional later alias `/take-on-items` may be added for `/run-items` in a
  future transition release; it is out of scope here.

### Use Case 7: Land ready work with `/batch-merge`

**Actor**: Operator ready to merge PRs that reached `ready-for-human-review`
**Preconditions**: One or more execute-command runs left PRs at
`ready-for-human-review`.

**Steps**:

1. The actor presents the merge plan for the ready PRs.
2. The human confirms the merge plan.
3. The actor merges the confirmed PRs via Protocol 94.

**Postconditions**: Confirmed ready PRs are merged. Landing is decoupled from
execution (the two-step lifecycle).

**Information shown**:

- The proposed merge plan and any conflicts to auto-resolve.

**Actions available**:

- Confirm the merge plan.
- Decline and leave PRs at `ready-for-human-review`.

**Considerations**:

- Execute commands never merge; `/batch-merge` is the only command in the Land
  layer.

---

## Business Rules

- BR1: `/run-work` is **read-only**. It proposes 1–3 batch options and performs no
  tracker, branch, PR, or merge mutation under any input.
- BR2: `/run-work` with two or more resolvable tokens records a redirect to
  `/run-items` and does not execute.
- BR3: `/run-work` with exactly one non-epic token redirects to `/run-item`; with
  exactly one epic-like token (or `--epic`) it redirects to `/run-epic`.
- BR4: `/run-items` is the canonical command for explicit multi-item execution; it
  advances only the supplied list via Protocol 90 `explicit_list` mode.
- BR5: `/run-items` uses base branch `develop` and never creates or targets a
  `develop-<slug>` integration branch.
- BR6: `/run-epic` is **epic-only**: it advances only an epic's native sub-issues
  via Protocol 95. The user-facing `--items` list form is removed.
- BR7: `/run-epic` uses an integration branch (`develop-<slug>`) only when the
  epic or its items carry an `integration-branch:<slug>` label; otherwise children
  target `develop`.
- BR8: Deprecated paths (`/run-epic --items`, `/run-work` execution modes) emit a
  deprecation notice and redirect to `/run-items` without mutating; they remain
  accepted for one transition release.
- BR9: **Two-step lifecycle** — every execute command (`/run-item`, `/run-items`,
  `/run-epic`) stops at `ready-for-human-review` and never merges. Merging happens
  only through `/batch-merge`.
- BR10: **Always-confirm** — every mutating command runs the shared bounded
  prelude and obtains human confirmation of policy and checkpoints before any
  mutation, regardless of configured autonomy mode.
- BR11: Sensible default `guardrails` are uncommented in `.ai-dev-workflow.yaml`
  so the always-confirm prelude has concrete defaults to present; uncommenting the
  defaults must not weaken the always-confirm requirement.
- BR12: Protocols 90, 91, 94, and 95 remain authoritative for their stages. This
  feature changes command surfaces, scan-only `/run-work`, the new `/run-items`
  command, epic-only `/run-epic`, router redirects, and the two-step lifecycle —
  not the per-stage execution contracts.
- BR13: The `run` command prefix is retained across all commands; only suffix
  semantics are corrected. An optional `/take-on-items` alias for `/run-items` may
  be introduced in a later transition release.
- BR14: Existing human-stop conditions (ambiguous requirements, architecture
  decisions, failed CI, high-risk changes, unsatisfied checkpoints) remain in
  force regardless of command.
- BR15: All operator-facing surfaces (README, AGENTS.md, Claude/Cursor/Codex
  commands and skills) teach the three-layer map (discover → execute → land) and
  the corrected command roles consistently.

---

## Statuses / Enum Values

### `/run-work` routing modes (scan-only discovery surface)

| Code value      | Display label    | Description                                                                                  |
| --------------- | ---------------- | -------------------------------------------------------------------------------------------- |
| `scan`          | Scan             | Read-only portfolio scan proposing 1–3 batch options; no mutation.                           |
| `redirect_items`| Redirect (items) | Two or more tokens supplied; `/run-work` redirects to `/run-items`.                          |
| `redirect_item` | Redirect (item)  | One non-epic token supplied; `/run-work` redirects to `/run-item`.                           |
| `redirect_epic` | Redirect (epic)  | One epic-like token or `--epic` supplied; `/run-work` redirects to `/run-epic`.              |
| `ambiguous`     | Ambiguous        | Cannot resolve deterministically; records stop reason and performs no mutation.              |

**Valid transitions**:

- No-target or scan-intent input resolves to `scan` (read-only proposals only).
- Two-plus resolvable tokens resolve to `redirect_items`.
- One non-epic token resolves to `redirect_item`; one epic-like token resolves to
  `redirect_epic`.
- Any unresolved input resolves to `ambiguous` and stops.

### Bounded prelude confirmation states (shared by all mutating commands)

| Code value  | Display label | Description                                                       |
| ----------- | ------------- | ----------------------------------------------------------------- |
| `pending`   | Pending       | Prelude complete; human has not confirmed policy/checkpoints.     |
| `confirmed` | Confirmed     | Human accepted recommended or customized prelude policy.          |
| `waived`    | Waived        | Human explicitly waived checkpoints with recorded rationale.      |

---

## Operational Visibility

- **Scan proposal record**: Every `/run-work` invocation emits routing mode
  `scan` (or a `redirect_*` mode), the proposed batch options, lane assignments,
  held-back items, and the copy-ready execute command per option.
- **Redirect record**: `/run-work` redirect outcomes name the recommended execute
  command, the resolved target tokens, and the reason (multi-item vs single vs
  epic).
- **Prelude record**: Every mutating command emits guardrails consulted,
  recommended policy fields, checkpoint list, and human confirmation state before
  mutation.
- **Two-step boundary record**: Execute-command summaries state that work stopped
  at `ready-for-human-review` and name `/batch-merge` as the next (Land) step.
- **Base-branch record**: `/run-items` summaries record base `develop`;
  `/run-epic` summaries record whether an integration branch applied and why.

---

## Acceptance Criteria

- [ ] AC1: Given `/run-work` with no target, routing mode is `scan`, it proposes
      one to three batch options with copy-ready execute commands, and it performs
      no mutation. (Trace: #1076)
- [ ] AC2: Given `/run-work` with two or more resolvable tokens, it records
      `redirect_items`, performs no mutation, and the guidance points to
      `/run-items` with the resolved list. (Trace: #1076, #1077)
- [ ] AC3: Given `/run-work` with exactly one non-epic token, it records
      `redirect_item` and points to `/run-item`; with one epic-like token or
      `--epic`, it records `redirect_epic` and points to `/run-epic`. (Trace: #1076, #1078)
- [ ] AC4: Given `/run-items <list>`, the command runs the shared bounded prelude,
      advances only the listed items via Protocol 90 `explicit_list` mode against
      base `develop`, and creates no integration branch. (Trace: #1077)
- [ ] AC5: Given `/run-epic --epic <n>`, the command advances only the epic's
      native sub-issues via Protocol 95, and uses a `develop-<slug>` integration
      branch only when an `integration-branch:<slug>` label is present. (Trace: #1078)
- [ ] AC6: Given a deprecated `/run-epic --items <list>` or `/run-work`
      execution-mode invocation, the command emits a deprecation notice, redirects
      to `/run-items`, and performs no mutation under the deprecated path. (Trace: #1078, #1077)
- [ ] AC7: Given any mutating execute command (`/run-item`, `/run-items`,
      `/run-epic`), it stops at `ready-for-human-review` and never merges; merging
      occurs only via `/batch-merge`. (Trace: #1077, #1078)
- [ ] AC8: Given any mutating command, the shared bounded prelude obtains human
      confirmation of policy and checkpoints before any mutation, even when
      configured autonomy would otherwise permit proceeding. (Trace: #1079)
- [ ] AC9: Given `.ai-dev-workflow.yaml`, sensible default `guardrails` are
      uncommented and the always-confirm prelude presents them; the defaults do
      not weaken the always-confirm requirement. (Trace: #1079)
- [ ] AC10: Given operator-facing surfaces (README, AGENTS.md, Claude/Cursor/Codex
      commands and skills), the three-layer command map (discover → execute →
      land) and corrected roles are taught consistently, and `/run-items` is
      documented as the explicit-list command. (Trace: #1080)
- [ ] AC11: Given this spec document, every brief objective maps to an acceptance
      criterion or an explicit Out-of-Scope entry, and each acceptance criterion
      traces to at least one implementation child (#1076–#1080). (Trace: #1075)

---

## Out of Scope (MVP)

- Implementing router code, command/skill files, prelude scripts, or
  `.ai-dev-workflow.yaml` edits — owned by children #1076–#1080.
- Merging Protocol 90, 91, 94, or 95 into one protocol.
- Adding the optional `/take-on-items` alias for `/run-items` (a possible later
  transition-release item, not this epic).
- Removing the deprecated `/run-epic --items` / `/run-work` execution forms before
  the one transition release elapses.
- Changing the guardrails schema beyond uncommenting sensible defaults and wiring
  the always-confirm requirement.
- Autonomous merging from any execute command (landing stays a separate
  `/batch-merge` step).

---

## Implementation Traceability (child items)

| Child | Scope | Spec sections |
| ----- | ----- | ------------- |
| **#1075** This spec | Authoritative finalization spec | Whole document; AC11 |
| **#1076** Scan-only `/run-work` | Read-only scan + router redirects | BR1–BR3, Use Cases 1–2, Statuses (`scan`, `redirect_*`), AC1–AC3 |
| **#1077** `/run-items` command | Explicit-list execution to `develop` | BR4–BR5, BR9, Use Cases 4, 6, AC2, AC4, AC6, AC7 |
| **#1078** Epic-only `/run-epic` | Remove `--items`; native sub-issues only | BR6–BR8, BR9, Use Cases 5, 6, AC3, AC5, AC6, AC7 |
| **#1079** Guardrails + always-confirm | Uncomment defaults; confirm before mutation | BR10–BR11, Use Cases 3–5 (confirm step), Statuses (prelude states), AC8–AC9 |
| **#1080** Surface sync | README/AGENTS.md/command/skill updates | BR13, BR15, Command Map, AC10 |

---

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Command map + operator cheat sheet (discover → execute → land) | Command Map section, BR15, AC10, #1080 row |
| Protocol ownership (scan / Protocol 90 `explicit_list` / Protocol 91 / Protocol 95 epic-only) | BR4, BR6, BR12, Use Cases 1, 3–5, AC4–AC5 |
| Deprecation (`/run-epic --items` and `/run-work` execution modes → `/run-items`) | BR8, Use Case 6, AC6, #1077/#1078 rows |
| Two-step lifecycle (stop at ready; merge via `/batch-merge`) | BR9, Use Cases 3–5, 7, AC7 |
| Defaults + always-confirm | BR10–BR11, Use Cases 3–5, AC8–AC9, #1079 row |
| No integration branch for `/run-items` (base `develop`) | BR5, Use Case 4, AC4 |
| Router redirects (2+ → `/run-items`; single → `/run-item` / `/run-epic`) | BR2–BR3, Use Case 2, Statuses (`redirect_*`), AC2–AC3 |
| Acceptance criteria trace to children #1076–#1080 | Implementation Traceability, AC1–AC11 |
| Supersedes #1072 scope; references Epic #1072 | Header, Relationship to Spec #1048 |
