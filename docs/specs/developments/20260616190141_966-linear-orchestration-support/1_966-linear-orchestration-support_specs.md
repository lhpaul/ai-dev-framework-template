# Linear Orchestration Support - Spec

---

## Overview

Teams that track work in Linear cannot use any of the workflow orchestration
commands today. The portfolio orchestrator (`run-work`), the single-item runner
(`run-item-work`), and the epic scope resolver (`run-epic`) all assume a
GitHub-backed tracker, so every discovery, classification, and status-update
step returns empty or refuses to act when the configured tracker is Linear. This
feature brings orchestration to operational parity for Linear teams: the same
commands discover Linear items, batch them, advance a single item, resolve epic
scope, transition Linear item status, and create Linear backlog items. Because
the helper scripts cannot reach the Linear API on their own, the feature defines
a bridge pattern where the orchestrator (the only actor with Linear access)
pre-resolves Linear data and hands it to the scripts, which then behave the same
for Linear as they do for the GitHub tracker.

## Brief Objective List

1. Make `run-work` discover and batch Linear work items end-to-end.
2. Make `run-item-work` advance a single Linear work item end-to-end.
3. Make the `run-epic` scope resolver resolve Linear items into an execution
   set.
4. Make tracker status reads and updates resolve correctly for Linear.
5. Make the backlog-item creation flow create items in Linear when configured.
6. Make type-based routing (Feature, Bug, Refactor) work for Linear items.
7. Update documentation and integration guides to reflect Linear parity.

## Use Cases

### Use Case 1: Discover and batch Linear work items with `run-work`

**Actor**: Workflow operator or Portfolio Orchestrator (the actor with Linear
access)
**Preconditions**: The repository declares `linear` as the configured tracker
provider, the Linear access credential is configured for the orchestrator, and
one or more Linear work items are in an advanceable state.

**Steps**:

1. The actor invokes `run-work`.
2. The orchestrator reads the eligible Linear work items, including each item's
   status, type, priority, dependencies, and identifier, through its Linear
   access.
3. The orchestrator provides this pre-resolved item set to the batch-planning
   step instead of relying on it to query Linear directly.
4. The batch-planning step classifies each item by its current workflow stage
   and groups items into safe parallel and serial batches.
5. The orchestrator dispatches each batched item to a single-item runner.

**Postconditions**: A Linear team can run portfolio orchestration and receive
the same batched execution plan a GitHub team receives, with no items silently
dropped because their status could not be read.

**Information shown**:

- Each discovered Linear item identifier and title.
- The classified workflow stage for each item.
- The parallel and serial batch grouping.
- A clear statement of which items were skipped and why.

**Actions available**:

- Proceed with the proposed batches.
- Narrow the discovered set before dispatch.
- Re-run after correcting Linear item state.

**Considerations**:

- When the orchestrator has no Linear access, the run must stop with an
  actionable message rather than silently producing an empty plan.
- A Linear item that cannot be classified must be reported as such, not skipped
  without explanation.

### Use Case 2: Advance a single Linear work item with `run-item-work`

**Actor**: Workflow operator or Portfolio Orchestrator
**Preconditions**: The tracker provider is `linear`, the actor knows the exact
Linear item to advance, and the orchestrator holds the pre-resolved data for
that item.

**Steps**:

1. The actor invokes `run-item-work` for a specific Linear item.
2. The single-item runner determines the next workflow action from repository
   state and the item's current Linear status.
3. The runner advances the item through its next stage (spec, plan, or
   implementation) and drives the resulting PR toward human-ready.
4. When a stage transition requires a Linear status change that the runner
   cannot perform itself, the runner reports the required transition back to the
   orchestrator instead of failing.
5. The orchestrator applies the reported Linear status transition.

**Postconditions**: A single Linear item advances one stage, the resulting PR
reaches human-ready, and the Linear item's status reflects the new stage.

**Information shown**:

- The resolved next action for the item.
- The branch and PR produced or resumed.
- Any deferred Linear status transition the orchestrator must apply.

**Actions available**:

- Continue to the next stage on a later run.
- Apply the deferred status transition.
- Stop when the item is waiting on human review or merge.

**Considerations**:

- The runner must never claim a Linear status change succeeded when it only
  deferred it to the orchestrator.
- If the deferred transition is not applied, observers must be able to see that
  the Linear item is out of sync, not assume it advanced.

### Use Case 3: Resolve Linear epic scope with `run-epic`

**Actor**: Workflow operator or Portfolio Orchestrator
**Preconditions**: The tracker provider is `linear`, and the actor supplies
either a Linear epic (parent item) or an explicit list of Linear item
identifiers.

**Steps**:

1. The actor invokes the `run-epic` scope resolver with a Linear epic or an
   explicit Linear item list.
2. The orchestrator pre-resolves the in-scope Linear items — child items for an
   epic, or exactly the listed items — together with each item's status, type,
   priority, dependencies, labels, linked PR state, and item state.
3. The resolver consumes this pre-resolved data and groups every item as
   eligible, blocked, already merged, in review, ambiguous, or out of scope.
4. The resolver reports the grouped, read-only execution set.

**Postconditions**: The actor sees a bounded, auditable Linear execution set and
can confirm scope before any delegated or mutating work begins.

**Information shown**:

- The scope source (epic or explicit list) and the resolved Linear item set.
- Status, type, priority, dependency state, labels, linked PR state, and item
  state for each item.
- The execution grouping for every resolved item.
- A read-only guarantee that no Linear mutation occurred during resolution.

**Actions available**:

- Confirm the scope for later delegated work.
- Re-run with a narrower explicit list.
- Stop and request a human decision when scope is ambiguous.

**Considerations**:

- An explicit Linear item list is a hard scope boundary; no sibling, parent, or
  label-matched item may be added unless explicitly listed.
- When a Linear epic resolves to no child items, the resolver must say so rather
  than silently treating the parent as the only item.

### Use Case 4: Transition Linear item status during orchestration

**Actor**: Portfolio Orchestrator (with Linear access)
**Preconditions**: The tracker provider is `linear`, and a stage transition has
occurred that should move a Linear item to a new workflow status.

**Steps**:

1. A workflow step requests a status transition for a Linear item (for example,
   to Writing Spec before dispatch, or to one of the In Review statuses after a
   PR is human-ready).
2. The shell helper detects the Linear provider and, because it cannot reach
   Linear itself, reports the required transition as a deferred action rather
   than failing or silently doing nothing.
3. The orchestrator collects the deferred transition and applies it through its
   Linear access.

**Postconditions**: The Linear item reflects the correct workflow status at the
correct moment, and no orchestration step is blocked by the shell helper's
inability to call Linear directly.

**Information shown**:

- The Linear item identifier and the target status.
- A clear indication that the transition was deferred to the orchestrator.
- Confirmation once the orchestrator applied the transition.

**Actions available**:

- Apply the deferred transition.
- Skip the transition and continue, recording that the item is out of sync.

**Considerations**:

- Status ordering must respect the same stage progression used for the GitHub
  tracker, so a Linear item is never reported as rolled backward.
- A deferred-but-unapplied transition must remain visible so it is not lost.

### Use Case 5: Create a Linear backlog item

**Actor**: Workflow operator or Portfolio Orchestrator
**Preconditions**: The tracker provider is `linear`, the actor has a title and
body for the new item, and the orchestrator holds Linear access.

**Steps**:

1. The actor invokes the backlog-item creation flow with a title, body, and
   optional type and scope labels.
2. The flow resolves the destination as Linear and, because the shell helper
   cannot create the item directly, reports the creation as an action the
   orchestrator must complete.
3. The orchestrator creates the Linear item with the supplied title, body,
   labels, and any configured project association.
4. The orchestrator returns the new Linear item identifier.

**Postconditions**: A new Linear work item exists in the configured team (and
project, when configured) and can immediately enter the orchestration pipeline.

**Information shown**:

- The destination team (and project, when configured).
- The title, body, and labels that will be applied.
- The resulting Linear item identifier after creation.

**Actions available**:

- Confirm and create the item.
- Adjust title, body, or labels before creation.

**Considerations**:

- When the orchestrator has no Linear access, the flow must stop with guidance
  rather than appearing to succeed.
- A configured Linear project association must be honored on creation.

### Use Case 6: Type-based routing for Linear items

**Actor**: Portfolio Orchestrator or single-item runner
**Preconditions**: The tracker provider is `linear`, and a work item carries a
type designation (Feature, Bug, or Refactor).

**Steps**:

1. An orchestration step needs the work-item type to choose the correct path
   (for example, routing a Refactor item directly to plan).
2. The orchestrator reads the Linear item's type and provides it to the step.
3. The step routes the item according to its type using the same routing rules
   applied to the GitHub tracker.

**Postconditions**: Linear Feature, Bug, and Refactor items follow the same
type-driven routing that GitHub-tracked items follow.

**Information shown**:

- The resolved work-item type for the Linear item.
- The routing decision derived from that type.

**Actions available**:

- Accept the type-driven route.
- Correct the item's type in Linear and re-run if the type was wrong.

**Considerations**:

- When a Linear item has no resolvable type, the step must fall back to a safe
  default route rather than misclassifying the item.

## Business Rules

- BR-1: The configured tracker provider determines which path each orchestration
  command and helper takes; a `linear` provider routes to the Linear path and a
  GitHub provider keeps its existing behavior.
- BR-2: Only the orchestrator (the actor with Linear access) reads from or writes
  to Linear; helper scripts must never attempt direct Linear API calls.
- BR-3: When a helper script needs Linear data, it consumes data the orchestrator
  has already resolved rather than querying Linear itself.
- BR-4: When a helper script needs a Linear mutation (status change or item
  creation) it cannot perform, it reports a deferred action to the orchestrator
  instead of failing the run or silently doing nothing.
- BR-5: The orchestrator must apply every deferred Linear action it receives, or
  explicitly record that the action was skipped and the item is out of sync.
- BR-6: Discovery for `run-work` and `run-epic` must classify every in-scope
  Linear item; an item that cannot be classified is reported as such and never
  silently dropped.
- BR-7: An explicit Linear item list passed to `run-epic` is a hard scope
  boundary; no unlisted item may be added.
- BR-8: Linear status transitions must follow the same stage progression order
  used for the GitHub tracker, and a Linear item must never be reported as rolled
  backward.
- BR-9: Linear status labels map to workflow stages using the established Linear
  status-to-stage mapping in the Linear integration guide.
- BR-10: Type-based routing must use the Linear item's type (Feature, Bug,
  Refactor) and fall back to a safe default when no type is resolvable.
- BR-11: Backlog-item creation for a Linear provider must honor the supplied
  title, body, and labels, and any configured Linear project association.
- BR-12: When the orchestrator lacks Linear access, any command that depends on
  Linear data must stop with an actionable message rather than produce an empty
  or misleading result.
- BR-13: Existing GitHub-tracker behavior for all orchestration commands and
  helpers must remain unchanged when the provider is not Linear.

## Statuses / Enum Values

Linear work-item statuses map to the same workflow stages used across the
orchestration pipeline. The display labels below are the Linear status names a
team configures, and they map one-to-one to workflow stages.

| Code value (workflow stage) | Display label (Linear status) | Description                                                         |
| --------------------------- | ----------------------------- | ------------------------------------------------------------------- |
| `backlog`                   | Backlog                       | Item is eligible to be selected but no stage work has started.      |
| `writing_spec`              | Writing Spec                  | Spec is being drafted and driven to human-ready.                    |
| `spec_in_review`            | Spec in Review                | Spec PR is human-ready and waiting for review or merge.             |
| `spec_ready`                | Spec Ready                    | Spec PR is merged.                                                  |
| `writing_plan`              | Writing Plan                  | Implementation plan is being drafted and driven to human-ready.     |
| `plan_in_review`            | Plan in Review                | Plan PR is human-ready and waiting for review or merge.             |
| `plan_ready`                | Plan Ready                    | Plan PR is merged.                                                  |
| `in_development`            | In Development                | Implementation PR is in progress toward human-ready.               |
| `development_in_review`     | Development in Review         | Implementation PR is human-ready and waiting for review or merge.   |
| `merged`                    | Merged                        | Implementation PR merged to the integration branch.                |
| `released`                  | Released                      | Item shipped to production.                                        |

**Valid transitions**:

- `backlog` → `writing_spec` when an item is selected for spec work (Refactor
  items may skip directly to `writing_plan`).
- `writing_spec` → `spec_in_review` when the spec PR is human-ready.
- `spec_in_review` → `spec_ready` when the spec PR is merged.
- `spec_ready` → `writing_plan` when the item is selected for plan work.
- `writing_plan` → `plan_in_review` when the plan PR is human-ready.
- `plan_in_review` → `plan_ready` when the plan PR is merged.
- `plan_ready` → `in_development` when the item is selected for implementation.
- `in_development` → `development_in_review` when the implementation PR is
  human-ready.
- `development_in_review` → `merged` when the implementation PR is merged.
- `merged` → `released` when the item ships to production.

## Operational Visibility

- **Deferred-action report**: Whenever a helper cannot perform a Linear mutation
  itself, it reports the exact item identifier and required action so the
  orchestrator can apply it.
- **Discovery summary**: `run-work` and `run-epic` print which Linear items were
  discovered, how each was classified, and which were skipped with the reason.
- **Status-sync visibility**: When a deferred Linear status transition is not
  applied, the run states that the Linear item is out of sync rather than
  assuming it advanced.
- **Read-only guarantee**: The `run-epic` resolver states that no Linear status,
  branch, PR, merge, or item-close mutation was performed during resolution.
- **No-access stop**: When the orchestrator lacks Linear access, the affected
  command states clearly that Linear access is required and stops.

## Acceptance Criteria

- [ ] AC-1: Given a repository configured with the Linear provider and
      advanceable Linear items, `run-work` discovers those items, classifies each
      by workflow stage, and produces parallel and serial batches without
      silently dropping items whose status could not be read by a helper script.
- [ ] AC-2: Given a specific Linear item, `run-item-work` resolves the next
      action, advances the item one stage to a human-ready PR, and reports any
      Linear status transition it could not apply so the orchestrator can apply
      it.
- [ ] AC-3: Given a Linear epic or an explicit Linear item list, the `run-epic`
      scope resolver reports each in-scope item with status, type, priority,
      dependency state, labels, linked PR state, and item state, grouped as
      eligible, blocked, already merged, in review, ambiguous, or out of scope,
      and includes a read-only guarantee.
- [ ] AC-4: Given a Linear provider and a requested status transition, the status
      helper reports the transition as deferred to the orchestrator, respects the
      stage progression order, never reports a backward transition, and the
      orchestrator applies the transition.
- [ ] AC-5: Given a Linear provider, the backlog-item creation flow reports
      Linear as the destination and the orchestrator creates a Linear item with
      the supplied title, body, labels, and any configured project association.
- [ ] AC-6: Given Linear items typed Feature, Bug, and Refactor, type-based
      routing routes each item the same way the GitHub tracker would, and falls
      back to a safe default when no type is resolvable.
- [ ] AC-7: Given the orchestrator lacks Linear access, every Linear-dependent
      command stops with an actionable message and does not produce an empty or
      misleading result.
- [ ] AC-8: Given a non-Linear provider, every orchestration command and helper
      behaves exactly as it does today, with no change to GitHub-tracker behavior.
- [ ] AC-9: The Linear integration guide and the generic issue-tracker guide
      document the bridge pattern, the orchestrator's ownership of Linear
      reads/writes, and how teams configure Linear access for orchestration.

## Out of Scope (MVP)

- A native Linear command-line tool or a Linear path inside helper scripts that
  bypasses the orchestrator.
- Linear webhooks or any push-based synchronization between Linear and the
  repository.
- Linear-specific release stamping behavior beyond the existing release-label
  and custom-field guidance already documented for Linear.
- New Linear status names or a status model different from the established
  Linear status-to-stage mapping.
- Migrating existing GitHub-tracked repositories to Linear or supporting both
  trackers simultaneously in one repository.
- Jira or any tracker provider other than Linear and the existing GitHub
  provider.

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Make `run-work` discover and batch Linear work items end-to-end. | Use Case 1, BR-1, BR-3, BR-6, AC-1 |
| Make `run-item-work` advance a single Linear work item end-to-end. | Use Case 2, BR-4, BR-5, AC-2 |
| Make the `run-epic` scope resolver resolve Linear items into an execution set. | Use Case 3, BR-3, BR-6, BR-7, AC-3 |
| Make tracker status reads and updates resolve correctly for Linear. | Use Case 4, BR-4, BR-5, BR-8, BR-9, AC-4 |
| Make the backlog-item creation flow create items in Linear when configured. | Use Case 5, BR-11, AC-5 |
| Make type-based routing (Feature, Bug, Refactor) work for Linear items. | Use Case 6, BR-10, AC-6 |
| Update documentation and integration guides to reflect Linear parity. | Operational Visibility, BR-2, AC-9 |

## Deferral Notes

- Native Linear CLI access, Linear webhooks, and Linear-specific release stamping
  are deferred because the approved approach keeps all Linear access with the
  orchestrator through the bridge pattern; adding direct script-level Linear
  access or push synchronization would broaden scope beyond operational parity.
  These remain listed under Out of Scope. Human confirmation is not requested for
  these deferrals.
- Multi-tracker coexistence and tracker migration are deferred because the goal
  is parity for teams that have already chosen Linear, not switching between
  trackers. These remain listed under Out of Scope. Human confirmation is not
  requested for this deferral.
