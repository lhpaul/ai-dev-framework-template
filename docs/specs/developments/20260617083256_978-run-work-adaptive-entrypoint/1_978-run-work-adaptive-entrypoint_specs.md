# Make /run-work the Adaptive Workflow Entrypoint - Spec

**Depends on**: 979-guardrails-config-model

---

## Overview

`/run-work` should become the single, intuitive command a person reaches for when
they want the workflow to move work forward, regardless of whether the request
concerns one item, several items, or a whole epic. Today the framework exposes
`/run-work`, `/run-item-work`, and `/run-epic` as three separate user-facing
choices, which forces new users to understand the internal orchestration model
before they can confidently ask the agent to act. This feature reframes
`/run-work` as the primary adaptive entrypoint that inspects the request, the
tracker and repository state, and repository configuration, then routes to the
appropriate underlying behavior — while keeping the existing portfolio, item, and
epic protocols intact as the supporting machinery they already are. The routing
decision is documented, testable, and surfaced to the human so they can see what
the command inferred.

## Brief Objective List

1. `/run-work` with no target inspects tracker and repo state, then proposes the
   largest safe plan.
2. `/run-work <one target>` resolves and advances exactly one issue, branch, PR,
   or development folder.
3. `/run-work <multiple targets>` treats the list as a hard bounded scope and
   does not mutate out-of-scope items.
4. `/run-work <epic-like target>` performs read-only scope resolution before
   mutation.
5. `/run-item-work` and `/run-epic` remain available as compatibility or advanced
   aliases, but docs teach `/run-work` first.
6. README, AGENTS.md, the Claude/Cursor/Codex command wrappers, and skill
   metadata use consistent user-facing language.
7. Tests or fixtures cover routing decisions for no target, one target, multiple
   targets, and epic target.
8. Keep the existing Protocol 90, 91, and 95 responsibilities intact unless a
   later plan proves a deeper merge is necessary.

## Use Cases

### Use Case 1: Run /run-work with no target

**Actor**: Workflow operator (human or delegating agent) who wants work to move
forward but has not named a specific item
**Preconditions**: The operator invokes `/run-work` with no target argument. A
tracker may or may not be configured for the repository.

**Steps**:

1. The actor reads the current repository configuration to learn what autonomy
   the repository allows for unattended starts.
2. The actor inspects tracker and repository state to discover items that can
   advance now (in-progress items, ready-but-unstarted items, and open PRs).
3. The actor proposes the largest safe plan that the configuration permits — the
   set of items it intends to advance — and records why each item is included or
   held back.
4. The actor surfaces the proposed plan and the routing decision to the human
   before mutating anything that the configuration does not pre-authorize.
5. The actor advances the in-scope items through the existing portfolio
   orchestration behavior.

**Postconditions**: The operator has a clear, configuration-bounded plan and a
visible record of what `/run-work` inferred from the empty target, and eligible
items advance within that plan.

**Information shown**:

- The inferred routing mode (no-target / portfolio scan).
- The set of items eligible to advance and the set held back, each with a short
  reason.
- The repository configuration values that bounded the plan (for example,
  whether unstarted backlog items may be started without a human prompt).
- The largest safe plan the actor proposes to execute.

**Actions available**:

- Advance the proposed in-scope items.
- Hold items that the configuration or dependencies do not allow to start.
- Stop and ask the human when the configuration does not authorize the inferred
  plan.

**Considerations**:

- When no tracker is configured, the actor scans repository state (workflow
  branches, development folders, open PRs) instead of tracker status and reports
  that tracker status was unavailable.
- Starting not-yet-started backlog items without an explicit target is governed
  by repository configuration, not by the command alone.

### Use Case 2: Run /run-work with one target

**Actor**: Workflow operator who names exactly one item, branch, PR, or
development folder
**Preconditions**: The operator invokes `/run-work <one target>` where the target
resolves to a single issue, workflow branch, open PR, or development folder.

**Steps**:

1. The actor recognizes that the request resolves to exactly one workflow item.
2. The actor routes the request to single-item advancement behavior.
3. The actor advances that one item through its next deterministic action until
   it reaches a terminal condition.

**Postconditions**: Exactly one item is advanced; no unrelated item is mutated.

**Information shown**:

- The inferred routing mode (single-item).
- The resolved item identity (issue, branch, PR, or development folder).
- The next deterministic action taken for that item.

**Actions available**:

- Advance the single resolved item.
- Stop when the request cannot be resolved to exactly one item.

**Considerations**:

- A single-target invocation is self-scoping: the actor confirms that any open
  PR or branch it touches belongs to the same resolved item.
- If the single target is itself epic-like (it has child items), the actor
  routes to the epic behavior in Use Case 4 rather than treating it as one item.

### Use Case 3: Run /run-work with multiple targets

**Actor**: Workflow operator who names two or more explicit targets
**Preconditions**: The operator invokes `/run-work <target> <target> ...` with a
bounded list of issues, branches, PRs, or development folders.

**Steps**:

1. The actor recognizes that the request resolves to more than one explicit
   target.
2. The actor treats the supplied list as a hard, bounded scope.
3. The actor advances each in-scope item through portfolio orchestration
   behavior.
4. The actor refuses to mutate any item not named in the supplied list and logs
   every out-of-scope item it skips.

**Postconditions**: Only the items in the supplied list are advanced; items
outside the list are never mutated, only logged when encountered.

**Information shown**:

- The inferred routing mode (explicit multi-item list).
- The exact bounded scope (the list of named targets).
- Any out-of-scope item the actor encountered and skipped, with a reason.

**Actions available**:

- Advance each in-scope item.
- Skip and log out-of-scope items.
- Stop on an ambiguous list that cannot be resolved to concrete targets.

**Considerations**:

- The bounded list is exact: the actor does not expand siblings, parent epics,
  labels, or linked issues from an explicit list.
- Duplicate targets in the list may be collapsed.

### Use Case 4: Run /run-work with an epic-like target

**Actor**: Workflow operator who names an epic or an epic-like target
**Preconditions**: The operator invokes `/run-work <epic-like target>` where the
target is a native epic or otherwise resolves to a set of child items.

**Steps**:

1. The actor recognizes the target as epic-like.
2. The actor performs read-only scope resolution to determine which child items
   are eligible, blocked, already merged, in review, ambiguous, or out of scope —
   without mutating anything.
3. The actor surfaces the resolved scope and any required autonomy authority to
   the human.
4. The actor advances eligible in-scope child items only after scope resolution
   is complete.

**Postconditions**: A bounded execution set and a clear authority context exist
before any child item is created, reviewed, merged, or cleaned up.

**Information shown**:

- The inferred routing mode (epic).
- The resolved child-item scope, grouped by eligibility.
- The authority context that governs delegated review, merge, and backlog starts
  for the run.

**Actions available**:

- Advance eligible in-scope child items.
- Skip out-of-scope items.
- Stop on ambiguous scope or insufficient authority.

**Considerations**:

- Read-only scope resolution must complete before any mutating stage begins.
- Delegated review, merge, risk, and audit behavior for epic runs remains owned
  by the existing epic protocol; this feature only routes into it.

### Use Case 5: Use a compatibility or advanced alias

**Actor**: Experienced operator or downstream automation that already depends on
the lower-level commands
**Preconditions**: The operator invokes `/run-item-work` or `/run-epic` directly.

**Steps**:

1. The actor accepts the lower-level command as a still-supported entrypoint.
2. The actor performs the same behavior that `/run-work` would route to for the
   equivalent target.

**Postconditions**: Existing `/run-item-work` and `/run-epic` invocations behave
exactly as they do today; nothing that previously worked breaks.

**Information shown**:

- Confirmation that the command is a supported compatibility or advanced
  specialist alias.
- The same routing-decision record `/run-work` would produce for the equivalent
  target.

**Actions available**:

- Run the lower-level command directly.
- Be guided by documentation toward `/run-work` as the recommended first command.

**Considerations**:

- The lower-level commands are documented as compatibility or advanced aliases,
  not as the recommended starting point.
- The underlying Protocol 90, 91, and 95 responsibilities remain intact.

## Business Rules

- `/run-work` is the primary, recommended entrypoint; `/run-item-work` and
  `/run-epic` remain available as compatibility or advanced aliases and must not
  be removed in this pass.
- `/run-work` routing is determined by the request input, tracker and repository
  state, and repository configuration — not by requiring the user to know which
  underlying protocol applies.
- With no target, `/run-work` proposes the largest plan that repository
  configuration deems safe; it does not exceed configuration-granted autonomy.
- With one target, `/run-work` resolves and advances exactly one item and mutates
  no unrelated item.
- With multiple explicit targets, the supplied list is a hard bounded scope;
  items outside the list are never mutated and are logged when encountered.
- With an epic-like target, read-only scope resolution must complete before any
  mutation.
- The routing decision (inferred mode, resolved scope, and the inputs that drove
  it) must be recorded so the human can see what was inferred.
- The routing logic must be documented in the workflow protocols and expressed in
  a way that is testable.
- Starting not-yet-started backlog items without an explicit target is governed
  by repository configuration; it is not enabled by default for existing
  repositories.
- Existing human-stop conditions (unclear requirements, architecture decisions,
  failed CI, high-risk changes) remain in force regardless of routing mode.
- The existing Protocol 90 (portfolio), Protocol 91 (single item), and Protocol
  95 (epic) responsibilities remain authoritative for stage execution; this
  feature routes into them rather than reimplementing them.

## Statuses / Enum Values

These are the user-facing routing modes `/run-work` infers and reports. They are
descriptive routing labels, not persisted entity states.

| Code value         | Display label          | Description                                                                                       |
| ------------------ | ---------------------- | ------------------------------------------------------------------------------------------------- |
| `no_target_scan`   | No-target scan         | No target was supplied; the command scans tracker and repository state and proposes a safe plan.  |
| `single_item`      | Single item            | Exactly one item, branch, PR, or development folder was resolved; the command advances only that. |
| `explicit_list`    | Explicit list          | Two or more explicit targets were supplied; the list is a hard bounded scope.                     |
| `epic`             | Epic                   | The target is epic-like; read-only scope resolution runs before any mutation.                     |
| `ambiguous`        | Ambiguous              | The request cannot be resolved to a routing mode and is escalated to the human.                   |

**Valid transitions**:

- A request resolves to exactly one of `no_target_scan`, `single_item`,
  `explicit_list`, or `epic` based on the input and discovered state.
- `single_item` → `epic` when the single resolved target turns out to be
  epic-like (it has child items).
- Any mode → `ambiguous` when the request cannot be deterministically resolved;
  an `ambiguous` outcome stops for a human decision and performs no mutation.

## Operational Visibility

- **Routing-decision record**: Every `/run-work` invocation emits a record of the
  inferred routing mode, the resolved scope, and the inputs that drove the
  decision (target argument, tracker/repository state, and the repository
  configuration values consulted).
- **Held-back items**: For no-target and explicit-list runs, the record names any
  item the command chose not to advance and the reason (out of scope, blocked
  dependency, or configuration boundary).
- **Stop reason**: When `/run-work` stops without advancing (ambiguous request,
  insufficient autonomy, blocked dependency), the record states the reason so the
  human can act.

## Acceptance Criteria

- [ ] AC1: Given `/run-work` invoked with no target, the command inspects tracker
      and repository state, proposes the largest plan the repository configuration
      allows, and records the inferred `no_target_scan` mode with the items it
      will advance and the items it holds back.
- [ ] AC2: Given `/run-work` invoked with exactly one target that resolves to one
      issue, branch, PR, or development folder, the command records `single_item`
      mode and advances exactly that item without mutating any unrelated item.
- [ ] AC3: Given `/run-work` invoked with two or more explicit targets, the
      command records `explicit_list` mode, treats the list as a hard bounded
      scope, advances only the listed items, and logs any out-of-scope item it
      encounters without mutating it.
- [ ] AC4: Given `/run-work` invoked with an epic-like target, the command records
      `epic` mode and completes read-only scope resolution before any item is
      created, reviewed, merged, or cleaned up.
- [ ] AC5: Given a single target that is itself epic-like, the command routes to
      `epic` mode rather than treating the target as a single item.
- [ ] AC6: Given `/run-item-work` or `/run-epic` invoked directly, each command
      still works and produces the same behavior `/run-work` would route to for
      the equivalent target.
- [ ] AC7: Given the workflow documentation, README, AGENTS.md, and the
      Claude/Cursor/Codex command wrappers and skill metadata, `/run-work` is
      presented as the primary entrypoint and `/run-item-work` and `/run-epic` are
      presented as compatibility or advanced aliases, using consistent
      user-facing language.
- [ ] AC8: Given the routing logic, it is documented in the workflow protocols in
      a deterministic, testable form (input + discovered state + configuration →
      routing mode).
- [ ] AC9: Given tests or workflow fixtures, they cover the routing decision for
      each of: no target, one target, multiple targets, and an epic target.
- [ ] AC10: Given any `/run-work` invocation, a routing-decision record is
      produced showing the inferred mode, the resolved scope, and the inputs that
      drove the decision.
- [ ] AC11: Given a request that cannot be deterministically resolved to a routing
      mode, the command records `ambiguous`, performs no mutation, and stops for a
      human decision.

## Out of Scope (MVP)

- Merging Protocol 90, 91, or 95 into a single protocol, or removing any of them;
  this pass keeps their responsibilities intact and only adds routing on top.
- Defining the repository guardrails configuration model itself — the modes,
  stage permissions, merge/risk limits, stop conditions, and audit requirements —
  which is owned by issue #979 (`979-guardrails-config-model`). This spec
  references the guardrails concept and depends on it but does not specify its
  schema or defaults.
- Enforcing guardrails during delegated `/run-work` execution, which is owned by
  issue #980.
- Making autonomous backlog starts the default behavior for existing
  repositories.
- Weakening any existing human-stop condition for unclear requirements,
  architecture choices, failed CI, or high-risk changes.

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| `/run-work` with no target inspects state and proposes the largest safe plan. | Use Case 1, BR3, AC1, AC10 |
| `/run-work <one target>` resolves and advances exactly one item. | Use Case 2, BR4, AC2, AC5 |
| `/run-work <multiple targets>` is a hard bounded scope with no out-of-scope mutation. | Use Case 3, BR5, AC3 |
| `/run-work <epic-like target>` runs read-only scope resolution before mutation. | Use Case 4, BR6, AC4, AC5 |
| `/run-item-work` and `/run-epic` remain available; docs teach `/run-work` first. | Use Case 5, BR1, AC6, AC7 |
| README, AGENTS.md, command wrappers, and skill metadata use consistent language. | BR1, AC7 |
| Tests or fixtures cover routing for no/one/multiple/epic targets. | BR8, AC8, AC9 |
| Keep Protocol 90, 91, and 95 responsibilities intact. | BR11, Out of Scope |
