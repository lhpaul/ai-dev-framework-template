# Orchestration Command Refactor — Spec

**Epic**: #1047 Refactor orchestration commands (run-item, portfolio run-work, shared bounded prelude)  
**Depends on**: 1020-human-checkpoint-policy-model, 978-run-work-adaptive-entrypoint

---

## Overview

Workflow operators today must choose between `/run-work`, `/run-item-work`, and
`/run-epic` before they understand the framework's internal orchestration model.
Issue #978 made `/run-work` the adaptive entrypoint that routes to portfolio,
single-item, and epic behavior. That helped discovery but blurred command
intent: portfolio batch work, single-item advancement, and epic bounded runs
share one surface.

This feature reframes the command map so **bounded single-item work** and
**bounded epic work** are explicit primary commands (`/run-item` and `/run-epic`),
while **`/run-work` is portfolio parallel orchestration only** (no-target scan
and explicit multi-item lists). A **shared bounded-run prelude** runs before
mutation for `/run-item` and `/run-epic`, applying the same guardrails,
policy recommendation, and human-checkpoint classification path already used by
delegated epic runs — extended to single-item runs.

Documentation and command surfaces teach **`/run-item` and `/run-epic` first**
for bounded work; `/run-work` is for parallel portfolio advancement. `/run-item-work`
remains a deprecated compatibility alias for `/run-item`.

## Brief Objective List

1. Command map: `/run-item`, `/run-epic`, portfolio-only `/run-work`, `/run-item-work` alias.
2. Shared bounded prelude: scope → guardrails → policy recommender → checkpoints → per-item Protocol 91.
3. Protocol 96 narrowing: `/run-work` = `no_target_scan` + `explicit_list` only; redirect single/epic tokens.
4. Parallelism defaults for `/run-work`: stage lanes, default `max_concurrent_implementation: 1`, optional `LOCAL_RUNTIME` classifier concept.
5. Dependency on merged #1019 / #1020 checkpoint schema; extend checkpoints to single-item runs (closes #1020 out-of-scope note for non-epic runs).
6. Child implementation items **#1049–#1052** trace to spec sections.
7. Spec merged under `docs/specs/developments/` on integration branch `develop-orchestration-command-refactor`.

---

## Use Cases

### Use Case 1: Advance one item with `/run-item`

**Actor**: Workflow operator (human or delegating agent) who knows exactly which
item, branch, PR, or development folder to advance  
**Preconditions**: The operator invokes `/run-item <target>` where the target
resolves to a single non-epic workflow item.

**Steps**:

1. The actor runs the **shared bounded prelude** (scope resolution, guardrails,
   policy recommendation, checkpoint classification) before any mutation.
2. The human accepts, customizes, or waives recommended policy and checkpoints.
3. The actor advances the resolved item through the single-item control loop
   (Protocol 91) until a terminal condition.

**Postconditions**: Exactly one item is advanced; prelude policy and checkpoint
state are recorded for audit. No unrelated item is mutated.

**Information shown**:

- Resolved item identity and prelude outputs (policy fields, checkpoint list,
  guardrails consulted).
- Routing confirmation: single-item bounded run (not portfolio, not epic).

**Actions available**:

- Continue after policy/checkpoint confirmation.
- Stop when scope is ambiguous or authority is insufficient.

**Considerations**:

- If the target is epic-like, the actor redirects to `/run-epic` behavior
  (Use Case 4) rather than treating it as a single item.

### Use Case 2: Run a bounded epic with `/run-epic`

**Actor**: Workflow operator who names an epic or explicit item list for a
bounded integration batch  
**Preconditions**: The operator invokes `/run-epic` (or the compatibility
advanced alias with epic flags).

**Steps**:

1. The actor performs read-only scope resolution.
2. The actor runs the **same shared bounded prelude** as `/run-item` (not a
   separate autonomy system).
3. The human accepts, customizes, or waives policy and checkpoints.
4. The actor advances eligible in-scope child items per Protocol 95.

**Postconditions**: Bounded epic execution proceeds with unified prelude output
shape and existing delegated gates.

**Information shown**:

- Resolved child-item groups (eligible, blocked, in review, etc.).
- Prelude policy and checkpoint recommendations.

**Actions available**:

- Advance eligible items after prelude confirmation.
- Stop on ambiguous scope or blocked dependencies.

**Considerations**:

- Epic behavior remains owned by Protocol 95; this feature unifies the prelude
  layer only.

### Use Case 3: Portfolio scan with `/run-work` (no target)

**Actor**: Workflow operator who wants the largest safe parallel batch without
naming specific targets  
**Preconditions**: The operator invokes `/run-work` with no target argument.

**Steps**:

1. The actor inspects tracker and repository state.
2. The actor proposes the largest **configuration-bounded** parallel plan
   (Protocol 90), including stage-aware lanes and default implementation
   serialization (Use Case 6).
3. The human approves the batch proposal when required.
4. The actor dispatches in-scope items through portfolio orchestration.

**Postconditions**: Only portfolio orchestration runs; no single-item or epic
protocol is invoked through `/run-work`.

**Information shown**:

- Routing mode `no_target_scan`.
- Proposed batch with held-back items and parallelism rationale.

**Actions available**:

- Execute approved batch.
- Hold items that fail lane or exclusivity rules.

**Considerations**:

- Starting backlog items without explicit targets remains governed by
  repository guardrails, not enabled by default.

### Use Case 4: Explicit multi-item list with `/run-work`

**Actor**: Workflow operator who names two or more explicit targets for a
parallel batch  
**Preconditions**: The operator invokes `/run-work` with a bounded list of
issues, branches, PRs, or development folders.

**Steps**:

1. The actor treats the list as a hard scope boundary.
2. The actor builds a stage-aware parallel plan (Protocol 90 + Use Case 6).
3. The actor advances only listed items; logs and skips out-of-scope encounters.

**Postconditions**: Routing mode `explicit_list`; no scope expansion beyond the
supplied list.

**Information shown**:

- Exact bounded scope and lane assignments.
- Items held for implementation serialization or runtime exclusivity.

**Actions available**:

- Dispatch parallel-safe lanes.
- Hold implementation items when defaults require serialization.

### Use Case 5: Mis-invoke `/run-work` with a single or epic target

**Actor**: Operator who still uses `/run-work` for one item or an epic  
**Preconditions**: The operator invokes `/run-work` with exactly one target or
an epic-like target.

**Steps**:

1. The router recognizes the invocation is outside portfolio-only scope.
2. The actor emits **redirect guidance** to `/run-item` or `/run-epic` with the
   equivalent target, without mutating through `/run-work`.
3. The operator re-invokes the recommended command (or the runner auto-redirects
   when configured to do so in the implementation plan).

**Postconditions**: No mutation occurs under `/run-work` for single-item or epic
routing; the operator receives a clear redirect.

**Information shown**:

- Redirect reason and the recommended command plus target tokens.

**Actions available**:

- Re-invoke `/run-item` or `/run-epic`.
- Stop if the operator declines.

**Considerations**:

- Redirect behavior replaces internal handoff of `single_item` and `epic` modes
  inside `/run-work` (reversing #978's adaptive routing for those cases).

### Use Case 6: Parallel batch with serialized implementation lane

**Actor**: Portfolio Orchestrator building a `/run-work` batch  
**Preconditions**: Multiple items are eligible across spec, plan, review, and
implementation stages.

**Steps**:

1. The actor assigns items to **stage lanes** allowing parallel dispatch for
   spec/plan/review work.
2. The actor applies default **implementation lane cap of one** concurrent item
   unless guardrails explicitly allow more.
3. When an optional **local runtime exclusivity** signal applies, the actor
   holds additional implementation items that would contend for the same local
   dev server, database, or port-bound resource.
4. The batch proposal explains held items (lane cap, exclusivity, file overlap).

**Postconditions**: Safe parallelism without assuming git worktree isolation
equals runtime isolation.

**Information shown**:

- Per-item lane assignment and hold reasons.
- `max_concurrent_by_stage` defaults (implementation: 1).

**Actions available**:

- Approve batch with holds.
- Override only when guardrails permit.

**Considerations**:

- Per-worktree environment profiles are an adopter setup concern (out of scope).

### Use Case 7: Use deprecated `/run-item-work` alias

**Actor**: Operator or automation with legacy `/run-item-work` invocations  
**Preconditions**: `/run-item-work` is invoked with a target.

**Steps**:

1. The alias resolves to `/run-item` behavior without functional change.
2. Documentation marks `/run-item-work` as deprecated compatibility.

**Postconditions**: Legacy invocations keep working; docs steer new usage to
`/run-item`.

**Information shown**:

- Deprecation notice in command/skill metadata where applicable.

**Actions available**:

- Same as `/run-item`.

---

## Business Rules

- BR1: `/run-item` is the canonical single-item bounded command; `/run-item-work`
  is a deprecated compatibility alias that must not be removed in this epic.
- BR2: `/run-epic` remains the canonical bounded epic command; `/run-epic` advanced
  flags and Protocol 95 behavior stay authoritative for epic execution.
- BR3: `/run-work` supports only portfolio modes `no_target_scan` and
  `explicit_list`; it must not execute single-item or epic protocols internally.
- BR4: Single-target and epic-like invocations of `/run-work` produce redirect
  guidance to `/run-item` or `/run-epic` without mutation.
- BR5: `/run-item` and `/run-epic` share one **bounded prelude** (guardrails,
  policy recommender, checkpoint classification) before mutation — no second
  autonomy system.
- BR6: Human-checkpoint policy from #1020 extends to single-item runs; checkpoint
  records use the same satisfaction semantics as epic runs.
- BR7: Prelude outputs use the same policy field shape as delegated `/run-epic`
  (`delegate-review`, `may-merge`, `may-start-backlog`, `max-risk`, checkpoints).
- BR8: Portfolio batches default to **one concurrent implementation item**;
  higher concurrency requires explicit guardrails configuration.
- BR9: Stage lanes allow parallel spec/plan/review advancement when safe;
  implementation lane defaults remain conservative.
- BR10: Documentation teaches `/run-item` and `/run-epic` as primary bounded
  commands; `/run-work` is taught as portfolio parallel orchestration (reversing
  #978's `/run-work`-first teaching order).
- BR11: Protocol 90, 91, and 95 remain authoritative for stage execution; this
  feature changes command surfaces, prelude sharing, router narrowing, and
  parallelism defaults — not the core per-stage contracts unless a child plan
  proves a minimal wiring change is required.
- BR12: Existing human-stop conditions (ambiguous requirements, architecture
  decisions, failed CI, high-risk changes, unsatisfied checkpoints) remain in
  force regardless of command.

---

## Statuses / Enum Values

### `/run-work` routing modes (portfolio-only surface)

| Code value       | Display label   | Description                                                              |
| ---------------- | --------------- | ------------------------------------------------------------------------ |
| `no_target_scan` | No-target scan  | Portfolio scan proposing a configuration-bounded parallel batch.         |
| `explicit_list`  | Explicit list   | Hard-bounded multi-target portfolio batch.                               |
| `redirect_item`  | Redirect (item) | Single target supplied; `/run-work` redirects to `/run-item`.          |
| `redirect_epic`  | Redirect (epic) | Epic-like target supplied; `/run-work` redirects to `/run-epic`.         |
| `ambiguous`      | Ambiguous       | Cannot resolve; stop for human decision without mutation.                |

**Valid transitions**:

- Portfolio invocations resolve to `no_target_scan` or `explicit_list` only when
  mutation proceeds under `/run-work`.
- Single or epic inputs resolve to `redirect_item` or `redirect_epic` (no
  `/run-work` mutation).
- Any input may resolve to `ambiguous` and stop.

### Bounded prelude confirmation states (shared by `/run-item` and `/run-epic`)

| Code value   | Display label | Description                                                |
| ------------ | ------------- | ---------------------------------------------------------- |
| `pending`    | Pending       | Prelude complete; human has not confirmed policy/checkpoints. |
| `confirmed`  | Confirmed     | Human accepted recommended or customized prelude policy.   |
| `waived`     | Waived        | Human explicitly waived checkpoints with recorded rationale. |

---

## Operational Visibility

- **Prelude record**: Every `/run-item` and `/run-epic` run emits guardrails
  consulted, recommended policy fields, checkpoint list, and human confirmation
  state before mutation.
- **Redirect record**: `/run-work` redirect outcomes name the recommended command,
  target tokens, and reason (single vs epic mis-invocation).
- **Batch proposal record**: `/run-work` portfolio runs show lane assignments,
  implementation holds, and exclusivity holds in the batch summary.
- **Audit alignment**: Prelude and checkpoint state feed the same delegated-gate
  and epic-ledger audit patterns as existing `/run-epic` runs where applicable.

---

## Acceptance Criteria

- [ ] AC1: Given `/run-item <single-target>`, the command runs the shared bounded
      prelude before mutation and advances exactly one item through Protocol 91.
- [ ] AC2: Given `/run-epic`, the command uses the same prelude shape as
      `/run-item` (not a separate autonomy system) before Protocol 95 execution.
- [ ] AC3: Given `/run-work` with no target, routing mode is `no_target_scan` and
      only Protocol 90 portfolio behavior executes.
- [ ] AC4: Given `/run-work` with two or more explicit targets, routing mode is
      `explicit_list` and only the listed items are advanced.
- [ ] AC5: Given `/run-work` with a single non-epic target, the command records
      `redirect_item` and does not mutate; guidance points to `/run-item`.
- [ ] AC6: Given `/run-work` with an epic-like target, the command records
      `redirect_epic` and does not mutate; guidance points to `/run-epic`.
- [ ] AC7: Given human-checkpoint policy from #1020, single-item runs declare and
      enforce checkpoints with the same satisfaction semantics as epic runs.
- [ ] AC8: Given a `/run-work` portfolio batch with mixed stages, spec/plan/review
      items may run in parallel while implementation defaults to one concurrent
      item unless guardrails allow more.
- [ ] AC9: Given documentation and command surfaces (README, AGENTS.md, Claude/Cursor/Codex
      commands and skills), `/run-item` and `/run-epic` are primary for bounded
      work; `/run-work` is portfolio-only; `/run-item-work` is marked deprecated.
- [ ] AC10: Given the spec document, sections trace clearly to implementation
      children **#1049** (shared prelude), **#1050** (`/run-item` command),
      **#1051** (portfolio-only `/run-work` router), and **#1052** (parallel
      implementation policy).
- [ ] AC11: Given `/run-item-work <target>`, behavior matches `/run-item` and
      deprecation is documented.

---

## Out of Scope (MVP)

- Implementing prelude scripts, router code, or command files — owned by #1049–#1052.
- Merging Protocol 90, 91, or 95 into one protocol.
- Product-repository per-worktree environment profiles (adopter setup).
- Changing guardrails schema defaults beyond documenting optional `parallelism`
  and `LOCAL_RUNTIME` concepts (#1052).
- Removing `/run-item-work` or `/run-epic` compatibility surfaces.
- Autonomous backlog starts as the default for all repositories.

---

## Implementation Traceability (child items)

| Child | Spec sections |
| ----- | ------------- |
| **#1049** Shared bounded prelude | BR5–BR7, Use Cases 1–2, Operational Visibility (prelude record), AC1–AC2, AC7 |
| **#1050** `/run-item` command | BR1, BR10, Use Case 1, Use Case 7, AC1, AC9, AC11 |
| **#1051** Portfolio-only `/run-work` | BR3–BR4, BR10, Use Cases 3–5, Statuses (`redirect_*`), AC3–AC6, AC9 |
| **#1052** Parallel implementation policy | BR8–BR9, Use Case 6, Operational Visibility (batch proposal), AC8 |

---

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Command map (`/run-item`, `/run-epic`, portfolio `/run-work`, alias) | BR1–BR2, BR10, Use Cases 1–2, 7, AC9, AC11 |
| Shared bounded prelude | BR5–BR7, Use Cases 1–2, AC1–AC2, AC7, #1049 row |
| Protocol 96 narrowing + redirects | BR3–BR4, Use Cases 3–5, AC3–AC6, #1051 row |
| Parallelism defaults + `LOCAL_RUNTIME` concept | BR8–BR9, Use Case 6, AC8, #1052 row |
| Checkpoint extension to single-item | BR6, AC7 |
| Child items trace to spec | Implementation Traceability, AC10 |
| Spec on integration branch | Step 5 protocol (this artifact), AC10 |
