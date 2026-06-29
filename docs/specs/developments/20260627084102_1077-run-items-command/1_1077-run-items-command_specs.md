# `/run-items` Multi-Item Bounded Execute Command — Spec

**Epic**: #1072 Finalize orchestration commands
**Depends on**: 1048-orchestration-command-refactor

---

## Overview

Workflow operators today have one bounded execute command for a single item
(`/run-item`) and one for a native epic (`/run-epic`). There is no first-class
command for advancing an **explicit list of two or more unrelated items** in a
single bounded batch. The portfolio command `/run-work` previously carried this
behavior, but the locked Epic #1072 command map narrows `/run-work` to a
read-only discovery scan that proposes batch options and never mutates.

This feature introduces `/run-items <list>` as the canonical multi-item bounded
execute command. The operator names a hard-bounded list of items, branches, PRs,
or development folders; the command runs the shared bounded prelude (scope,
guardrails snapshot, policy recommendation, human confirmation) before any
mutation, then advances the listed items as a Protocol 90 `explicit_list` batch.
Stage work (spec, plan, review) runs in parallel lanes; implementation is
serialized by default. All resulting pull requests target the `develop`
integration branch directly — `/run-items` never creates a `develop-<slug>`
integration branch. The command stops when every item's PR is waiting on human
review, and merging is handed off to `/batch-merge` as an explicit second step.

This spec defines `/run-items` behavior and surfaces only. It does not reopen the
broader orchestration command map, which is already specified in
`docs/specs/developments/20260625150000_1048-orchestration-command-refactor/`.

## Brief Objective List

Derived from the Epic #1072 child-3 brief (issue #1077 Scope) and the locked
Epic #1072 command-map decisions:

1. Introduce `/run-items <list>` as the canonical multi-item bounded execute
   command: shared bounded prelude, Protocol 90 `explicit_list`, parallel stage
   lanes, implementation serialization default.
2. Add new command surfaces: `.cursor/commands/run-items.md`,
   `.claude/commands/run-items.md`, `.agents/skills/run-items/`, and the Codex
   skill mirror.
3. Integrate the shared bounded prelude (`run-bounded-prelude.sh`) for the
   multi-item (items list) scope path.
4. Protocol 90 `explicit_list` execution becomes reachable only via `/run-items`,
   not via `/run-work`.
5. All `/run-items` PRs target `develop` directly; no `develop-<slug>`
   integration branch is created.
6. Terminal state is all in-scope PRs at `ready-for-human-review`; document
   `/batch-merge` as the explicit step 2 to land them.
7. Portfolio supervision: verify CI and the automated reviewer loop (Protocol 93)
   before declaring batch execute complete (aligns with #1074).
8. Per-item handoff: the item-orchestrator runs Protocol 93 before applying
   `ready-for-human-review` (aligns with #1071).
9. Router behavior: `/run-work` with two or more tokens redirects to
   `/run-items`; single token redirects to `/run-item` or `/run-epic`.
10. `/run-epic --items` is deprecated and redirects users to `/run-items`;
    `/run-epic` resolves native epic sub-issues only.

---

## Use Cases

### Use Case 1: Advance an explicit multi-item batch with `/run-items`

**Actor**: Workflow operator (human or delegating agent) who knows exactly which
two or more non-epic items to advance together.
**Preconditions**: The operator invokes `/run-items <list>` where `<list>` is two
or more whitespace- or comma-separated tokens, each resolving to a known issue,
workflow branch, PR, or development folder.

**Steps**:

1. The operator supplies the bounded list as a hard scope boundary.
2. The command runs the shared bounded prelude (scope resolution, repository
   guardrails snapshot, policy recommendation, checkpoint classification) before
   any mutation.
3. The human accepts, customizes, or waives the recommended policy and
   checkpoints (always-confirm default).
4. The command builds a Protocol 90 `explicit_list` plan: stage-aware lanes for
   spec/plan/review work and a serialized implementation lane.
5. The command advances each in-scope item; each item's per-item handoff runs the
   automated reviewer loop and CI to completion before the item's PR is labeled
   `ready-for-human-review`.
6. The command stops when every in-scope item is at its terminal state, reporting
   the batch outcome.

**Postconditions**: Only the listed items are advanced. Each produces a PR
targeting `develop` at `ready-for-human-review`, or is reported as held, blocked,
or escalated. No item outside the list is mutated.

**Information shown**:

- Resolved bounded scope and per-item lane assignment.
- Prelude outputs: guardrails consulted, recommended policy fields, checkpoint
  list, and human confirmation state.
- Per-item terminal state and any held/blocked/escalation reasons.
- Reminder that landing the batch is a separate `/batch-merge` step.

**Actions available**:

- Continue after policy/checkpoint confirmation.
- Hold implementation items that exceed the serialization cap.
- Stop when scope is ambiguous, a dependency is blocked, or authority is
  insufficient.

**Considerations**:

- If any token resolves to an epic-like item, the command stops and directs the
  operator to `/run-epic --epic <n>` for that item rather than treating it as a
  list member.
- A list of exactly one token is out of scope for `/run-items` (Use Case 5).

### Use Case 2: Parallel stage lanes with serialized implementation

**Actor**: Workflow operator running a `/run-items` batch that spans multiple
workflow stages.
**Preconditions**: The bounded list contains items at mixed stages (for example,
some need a spec, some a plan, some implementation).

**Steps**:

1. The command assigns items to **stage lanes**, allowing parallel dispatch for
   spec, plan, and review work.
2. The command applies the default **implementation lane cap of one** concurrent
   item unless repository guardrails explicitly allow more.
3. Implementation items beyond the cap are held with a stated reason and advanced
   after a lane slot frees up.
4. The batch report explains every held item (lane cap, file overlap, or runtime
   exclusivity).

**Postconditions**: Stage work proceeds in parallel where safe; implementation
items run within the configured concurrency limit.

**Information shown**:

- Per-item lane assignment and hold reasons.
- Effective implementation concurrency limit and its source (default vs.
  guardrails override).

**Actions available**:

- Approve the batch with holds.
- Override the implementation cap only when guardrails permit.

**Considerations**:

- Git worktree isolation is not assumed to equal runtime isolation; the
  serialized implementation default protects shared local resources.

### Use Case 3: `/run-work` redirects a two-or-more-token invocation to `/run-items`

**Actor**: Operator who still passes an explicit multi-item list to `/run-work`.
**Preconditions**: The operator invokes `/run-work` with two or more resolvable
tokens.

**Steps**:

1. The read-only router classifies the invocation as an explicit multi-item list.
2. The command emits **redirect guidance** naming `/run-items <list>` with the
   same tokens, without mutating under `/run-work`.
3. The operator re-invokes `/run-items` (or the runner auto-redirects when the
   implementation plan wires that behavior).

**Postconditions**: No mutation occurs under `/run-work` for a multi-item list;
the operator receives a clear redirect to `/run-items`.

**Information shown**:

- Redirect reason and the recommended `/run-items` command with the resolved
  token list.

**Actions available**:

- Re-invoke `/run-items`.
- Stop if the operator declines.

### Use Case 4: `/run-epic --items` is deprecated and redirects to `/run-items`

**Actor**: Operator or automation using the legacy `/run-epic --items <list>`
form.
**Preconditions**: `/run-epic` is invoked with the deprecated `--items` flag.

**Steps**:

1. The command recognizes `--items` as deprecated.
2. The command emits redirect guidance to `/run-items <list>` with the same
   tokens and does not run epic resolution for the list.

**Postconditions**: Explicit item lists are handled only by `/run-items`;
`/run-epic` resolves native epic sub-issues only.

**Information shown**:

- Deprecation notice and the recommended `/run-items` command.

**Actions available**:

- Re-invoke `/run-items`.

**Considerations**:

- The deprecation is a redirect, not a hard removal, so legacy callers receive a
  clear migration path rather than a silent failure.

### Use Case 5: Mis-invoke `/run-items` with zero or one target

**Actor**: Operator who passes `/run-items` no tokens or exactly one token.
**Preconditions**: The operator invokes `/run-items` with fewer than two
resolvable tokens.

**Steps**:

1. The command recognizes the invocation is outside its two-or-more-item scope.
2. For one token, the command redirects to `/run-item <target>` (or
   `/run-epic --epic <n>` when the single token is epic-like).
3. For zero tokens, the command directs the operator to `/run-work` for a
   read-only portfolio scan.

**Postconditions**: No multi-item batch mutation occurs for a sub-two-item
invocation; the operator receives a clear redirect.

**Information shown**:

- Redirect reason and the recommended command.

**Actions available**:

- Re-invoke the recommended command.
- Stop if the operator declines.

### Use Case 6: Hand off the ready batch to `/batch-merge`

**Actor**: Operator whose `/run-items` batch has reached terminal state.
**Preconditions**: Every in-scope item's PR is at `ready-for-human-review`, or
held/blocked items are reported.

**Steps**:

1. The command reports the batch as execute-complete only after confirming each
   ready PR has green CI and a clean automated reviewer loop (Protocol 93).
2. The command names `/batch-merge` as the explicit step 2 to land the ready PRs.
3. The human confirms the merge plan under `/batch-merge`.

**Postconditions**: `/run-items` never merges PRs itself; landing is a separate,
human-confirmed `/batch-merge` step.

**Information shown**:

- Per-item readiness state (CI status, reviewer-loop verdict, label).
- The recommended `/batch-merge` invocation.

**Actions available**:

- Proceed to `/batch-merge`.
- Re-run `/run-items` for items that are still held or blocked.

---

## Business Rules

- BR1: `/run-items` is the canonical command for advancing an explicit list of
  **two or more** non-epic items in one bounded batch.
- BR2: `/run-items` runs the shared bounded prelude (guardrails snapshot, policy
  recommendation, checkpoint classification) before any mutation — the same
  prelude path used by `/run-item` and `/run-epic`, with no second autonomy
  system.
- BR3: `/run-items` executes the Protocol 90 `explicit_list` mode; the supplied
  list is a hard scope boundary and the batch must not expand beyond it.
- BR4: Protocol 90 `explicit_list` execution is reachable only through
  `/run-items`. `/run-work` is read-only and must not run `explicit_list`
  mutation itself.
- BR5: All `/run-items` PRs target the `develop` integration branch directly.
  `/run-items` must not create or target a `develop-<slug>` integration branch.
- BR6: Stage lanes allow parallel spec, plan, and review advancement when safe;
  the implementation lane defaults to **one** concurrent item and only exceeds it
  when repository guardrails explicitly allow more.
- BR7: Each item's per-item handoff (item-orchestrator) runs the automated
  reviewer loop (Protocol 93) and CI to completion before that item's PR is
  labeled `ready-for-human-review` (aligns with #1071).
- BR8: `/run-items` declares the batch execute-complete only after verifying that
  every in-scope ready PR has green CI and a clean reviewer loop (Protocol 93)
  (aligns with #1074).
- BR9: The terminal state of a `/run-items` execute run is every in-scope PR at
  `ready-for-human-review` (plus any reported held/blocked/escalated items).
  `/run-items` must not merge PRs; merging is the separate `/batch-merge` step.
- BR10: An epic-like token in the list causes the entire `/run-items` invocation
  to stop; the command directs the operator to `/run-epic --epic <n>` for each
  epic-like token encountered and does not advance any other listed items. Epics
  are never advanced as `/run-items` list members.
- BR11: `/run-items` invoked with fewer than two resolvable tokens does not run a
  batch: one token redirects to `/run-item` (or `/run-epic` when epic-like), and
  zero tokens redirect to `/run-work`.
- BR12: `/run-work` invoked with two or more resolvable tokens redirects to
  `/run-items` without mutation; `/run-work` invoked with one token redirects to
  `/run-item` or `/run-epic`.
- BR13: `/run-epic --items` is deprecated and redirects to `/run-items`;
  `/run-epic` resolves native epic sub-issues only.
- BR14: Policy defaults are always-confirm: the human confirms (accepts,
  customizes, or waives) recommended policy and checkpoints before any mutation.
- BR15: Existing human-stop conditions (ambiguous scope, architecture decisions,
  failed CI, high-risk changes, unsatisfied checkpoints, blocked dependencies)
  remain in force under `/run-items`.
- BR16: Protocol 90 remains authoritative for batch execution and Protocol 91 for
  each item's control loop; this feature adds the `/run-items` surface and the
  multi-item prelude wiring, not new per-stage contracts.

---

## Statuses / Enum Values

### `/run-items` per-item terminal states (batch report)

| Code value     | Display label  | Description                                                                                |
| -------------- | -------------- | ------------------------------------------------------------------------------------------ |
| `ready`        | Ready          | Item advanced to a PR at `ready-for-human-review` with green CI and clean reviewer loop.   |
| `held`         | Held           | Item not advanced this cycle (implementation lane cap, file overlap, or runtime exclusivity). |
| `blocked`      | Blocked        | Item cannot advance due to an unsatisfied dependency.                                       |
| `escalated`    | Escalated      | Item stopped for a human decision (ambiguous scope, architecture, high risk, failed CI).   |
| `out_of_scope` | Out of scope   | Token encountered during execution that is not a member of the supplied list; logged and skipped. |

**Valid transitions**:

- An in-scope item is `held` or `blocked` until its lane slot or dependency
  clears, then advances toward `ready` or `escalated`.
- An item resolves to `escalated` at any point a human-stop condition is hit.
- `out_of_scope` is terminal for that token within the run; it is never advanced.

### `/run-items` invocation routing outcomes

| Code value      | Display label   | Description                                                                       |
| --------------- | --------------- | --------------------------------------------------------------------------------- |
| `explicit_list` | Explicit list   | Two or more resolvable tokens; bounded multi-item execute proceeds.               |
| `redirect_item` | Redirect (item) | One non-epic token; redirect to `/run-item`.                                      |
| `redirect_epic` | Redirect (epic) | One epic-like token, or an epic-like token in the list; redirect to `/run-epic`.  |
| `redirect_scan` | Redirect (scan) | Zero tokens; redirect to `/run-work` for a read-only portfolio scan.              |
| `ambiguous`     | Ambiguous       | One or more tokens cannot be resolved; stop for human clarification, no mutation. |

**Valid transitions**:

- Mutation proceeds only on `explicit_list`.
- `redirect_item`, `redirect_epic`, and `redirect_scan` emit guidance with no
  mutation.
- Any unresolvable token resolves the whole invocation to `ambiguous` and stops.

---

## Operational Visibility

- **Prelude record**: Every `/run-items` run records guardrails consulted,
  recommended policy fields, checkpoint list, and human confirmation state before
  mutation.
- **Batch plan record**: The run shows the resolved bounded scope, per-item lane
  assignment, the effective implementation concurrency limit and its source, and
  every held item with its reason.
- **Per-item readiness record**: For each in-scope item, the run records CI
  status, the automated reviewer-loop verdict, and whether
  `ready-for-human-review` was applied.
- **Redirect record**: Redirect outcomes (`redirect_item`, `redirect_epic`,
  `redirect_scan`, and `/run-work` two-or-more-token redirects) name the
  recommended command, the resolved tokens, and the reason.
- **Handoff record**: When the batch is execute-complete, the run names
  `/batch-merge` as the landing step and lists the ready PRs it should consider.

---

## Acceptance Criteria

- [ ] AC1: Given `/run-items <two-or-more-targets>`, the command runs the shared
      bounded prelude before any mutation and reports the prelude outputs
      (guardrails, policy, checkpoints, confirmation state).
- [ ] AC2: Given a confirmed `/run-items` batch, only the listed items are
      advanced and no item outside the supplied list is mutated.
- [ ] AC3: Given a `/run-items` batch, execution runs the Protocol 90
      `explicit_list` mode, and `explicit_list` mutation is not reachable through
      `/run-work`.
- [ ] AC4: Given any `/run-items` batch, every resulting PR targets `develop`
      and no `develop-<slug>` integration branch is created.
- [ ] AC5: Given a `/run-items` batch spanning multiple stages, spec/plan/review
      items may run in parallel while implementation defaults to one concurrent
      item unless guardrails allow more; held implementation items are reported
      with reasons.
- [ ] AC6: Given each in-scope item, the per-item handoff runs the automated
      reviewer loop (Protocol 93) and CI to completion before that item's PR is
      labeled `ready-for-human-review`.
- [ ] AC7: Given a `/run-items` run, the batch is declared execute-complete only
      after every in-scope ready PR is confirmed to have green CI and a clean
      reviewer loop, and the report names `/batch-merge` as the explicit landing
      step.
- [ ] AC8: Given `/run-items` with an epic-like token, the command stops the
      entire invocation and directs the operator to `/run-epic --epic <n>` for
      each epic-like token; no other listed items are advanced.
- [ ] AC9: Given `/run-items` with exactly one token, the command redirects to
      `/run-item` (or `/run-epic` when epic-like); given zero tokens, it redirects
      to `/run-work`. No batch mutation occurs in either case.
- [ ] AC10: Given `/run-work` with two or more resolvable tokens, the command
      redirects to `/run-items` without mutation; given one token, it redirects to
      `/run-item` or `/run-epic`.
- [ ] AC11: Given `/run-epic --items <list>`, the command reports the flag as
      deprecated and redirects to `/run-items <list>`; `/run-epic` continues to
      resolve native epic sub-issues only.
- [ ] AC12: Given the repository, the command surfaces exist and teach the same
      behavior: `.claude/commands/run-items.md`, `.cursor/commands/run-items.md`,
      `.agents/skills/run-items/`, and the Codex skill mirror.
- [ ] AC13: Given the workflow documentation (AGENTS.md/CLAUDE.md command tables
      and the development-workflow README/command map), `/run-items` is listed as
      the multi-item bounded execute command with base `develop`, and the
      two-step execute-then-`/batch-merge` lifecycle is documented.

---

## Out of Scope (MVP)

- Implementing the prelude scripts, router code, scope resolver, or command/skill
  files — those are owned by the implementation plan and its child work items.
- Changing Protocol 90, 91, 93, or 95 stage contracts beyond the minimal wiring
  needed to route `explicit_list` through `/run-items` and run the per-item
  reviewer loop before labeling.
- Merging PRs: landing the batch is the separate `/batch-merge` command and is
  not performed by `/run-items`.
- Integration-branch (`develop-<slug>`) batches: `/run-items` always targets
  `develop`. Integration-branch grouping remains a `/run-epic` concern when
  epics or items carry an `integration-branch:<slug>` label.
- Removing the `/run-work`, `/run-item`, `/run-epic`, or `/run-item-work`
  surfaces; this feature adds `/run-items` and adjusts routing/redirect behavior
  only.
- Changing guardrails schema defaults beyond consuming the existing parallelism
  concepts already specified for the orchestration refactor.
- Hard removal of `/run-epic --items`; this feature deprecates and redirects it
  rather than deleting it.

---

## Implementation Traceability

| Concern | Spec coverage |
| ------- | ------------- |
| `/run-items` command + surfaces | BR1, Use Case 1, AC1–AC2, AC12–AC13 |
| Shared bounded prelude (multi-item scope) | BR2, BR14, Use Case 1, AC1 |
| Protocol 90 `explicit_list` only via `/run-items` | BR3–BR4, Use Case 1, Use Case 3, AC3 |
| Base `develop`, no `develop-<slug>` | BR5, AC4 |
| Parallel stage lanes + implementation serialization | BR6, Use Case 2, AC5 |
| Per-item Protocol 93 before ready (#1071) | BR7, Use Case 1, AC6 |
| Portfolio supervision: CI + Protocol 93 (#1074) | BR8, Use Case 6, AC7 |
| Terminal state + `/batch-merge` step 2 | BR9, Use Case 6, AC7 |
| Epic-like token handling | BR10, Use Case 1, AC8 |
| Sub-two-item redirects | BR11, Use Case 5, AC9 |
| `/run-work` two-plus-token redirect | BR12, Use Case 3, AC10 |
| `/run-epic --items` deprecation | BR13, Use Case 4, AC11 |

---

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Introduce `/run-items` (prelude, `explicit_list`, lanes, serialization) | BR1–BR3, BR6, Use Cases 1–2, AC1–AC5 |
| 2. New command surfaces (Claude, Cursor, Codex skill + mirror) | Use Case 1, AC12 |
| 3. `run-bounded-prelude.sh` multi-item scope integration | BR2, AC1 |
| 4. Protocol 90 `explicit_list` only via `/run-items` | BR4, Use Case 3, AC3 |
| 5. PRs target `develop`, no `develop-<slug>` | BR5, AC4 |
| 6. Terminal state all `ready-for-human-review`; `/batch-merge` step 2 | BR9, Use Case 6, AC7 |
| 7. Portfolio supervision: CI + Protocol 93 (#1074) | BR8, Use Case 6, AC7 |
| 8. Item-orchestrator Protocol 93 before ready (#1071) | BR7, Use Case 1, AC6 |
| 9. Router two-plus tokens → `/run-items`; single → `/run-item`/`/run-epic` | BR12, Use Case 3, AC10 |
| 10. `/run-epic --items` deprecated → `/run-items` | BR13, Use Case 4, AC11 |
| Documentation surfaces updated (command map/tables) | AC13 |

All brief objectives map to acceptance criteria; none are deferred to Out of
Scope, so no Deferral Notes are required.
