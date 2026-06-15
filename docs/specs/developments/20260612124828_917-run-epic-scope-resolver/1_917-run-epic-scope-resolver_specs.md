# Run Epic Scope Resolver - Spec

---

## Overview

Agents need a visible, deterministic way to understand what belongs to an epic
or explicit item set before they take delegated ownership of the work. This
feature adds a resolver-only experience for `/run-epic` that accepts an epic or
explicit item list and returns an execution set grouped by current workflow
state. The resolver is intentionally read-only: it makes scope, base branch, and
blocking conditions auditable before any implementation, tracker mutation, or
merge action can begin.

## Brief Objective List

1. Add a `/run-epic` scope resolver for an epic issue.
2. Add a `/run-epic` scope resolver for an explicit item list.
3. Resolve native GitHub sub-issues for an epic when available.
4. Resolve explicit item lists without requiring an epic.
5. Read tracker Status, Type, Priority, dependencies, labels, linked PRs, and
   issue state for every resolved item.
6. Infer the target base branch from a supplied base override, a shared
   integration-branch label, or `develop` when no integration branch is implied.
7. Stop and report ambiguity when items imply different base branches or the
   scope boundary is unclear.
8. Print an execution set grouped as eligible, blocked, already merged, in
   review, ambiguous, or out of scope.
9. Avoid starting Backlog items, mutating statuses, or merging PRs in the
   resolver-only path.
10. Provide a visible and auditable foundation for later delegated epic
    autonomy.

## Use Cases

### Use Case 1: Resolve an epic into an execution set

**Actor**: Workflow operator or AI orchestrator
**Preconditions**: A GitHub issue represents an epic and may have native
sub-issues.

**Steps**:

1. The actor invokes `/run-epic` with an epic issue number.
2. The resolver reads the epic and its native sub-issues when they are
   available.
3. The resolver reads workflow-relevant tracker and repository state for each
   child item.
4. The resolver infers the shared target base branch for the set.
5. The resolver prints an execution set grouped by current workflow state.

**Postconditions**: The actor can see which items belong to the epic, which
items can advance, and which items require a dependency, human decision, or
scope correction before any mutating action is attempted.

**Information shown**:

- Epic issue number and title.
- Resolved child item numbers and titles.
- Status, Type, Priority, dependency state, labels, linked PR state, and issue
  state for each item.
- Inferred base branch and the reason it was selected.
- Execution grouping for every resolved item.

**Actions available**:

- Review the execution set.
- Re-run with an explicit item list when native sub-issue scope is not the
  intended boundary.
- Re-run with a base override when the inferred base branch is ambiguous.
- Stop before delegated review, merge, or backlog start behavior.

**Considerations**:

- If no native sub-issues can be resolved from the epic, the resolver must say
  so clearly rather than silently treating the parent epic as the only item.
- If resolved items imply conflicting integration branches, the resolver must
  report ambiguity and avoid producing a mutating execution plan.

### Use Case 2: Resolve an explicit item list

**Actor**: Workflow operator or AI orchestrator
**Preconditions**: The actor knows the exact issue numbers that should be in
scope.

**Steps**:

1. The actor invokes `/run-epic` with an explicit comma-separated item list.
2. The resolver reads every listed item without requiring a parent epic.
3. The resolver reads tracker and repository state for each listed item.
4. The resolver infers the target base branch from the supplied override, the
   listed items' shared integration branch, or the default base.
5. The resolver prints the grouped execution set.

**Postconditions**: The actor has a bounded, auditable item set and can verify
that no unlisted item will be mutated by later delegated work.

**Information shown**:

- Explicit item numbers requested by the actor.
- Any listed item that could not be found or could not be classified.
- Status, Type, Priority, dependency state, labels, linked PR state, and issue
  state for each found item.
- Inferred base branch and any ambiguity.
- Execution grouping for every listed item.

**Actions available**:

- Confirm the list as the intended scope for a later delegated run.
- Remove invalid or ambiguous items and re-run.
- Add a base override if the listed items do not share a clear base.

**Considerations**:

- Explicit item lists are a hard scope boundary for later delegated work.
- The resolver must not include sibling, parent, or label-matched items unless
  they were explicitly listed.

### Use Case 3: Detect ambiguous scope or base branch

**Actor**: Workflow operator or AI orchestrator
**Preconditions**: The requested epic or item list contains incomplete,
conflicting, or mixed-context state.

**Steps**:

1. The actor invokes the resolver for the epic or item list.
2. The resolver finds conflicting integration-branch labels, missing item data,
   mixed base-branch signals, or an unclear scope boundary.
3. The resolver prints the ambiguity with enough detail for the actor to choose
   a correction.
4. The resolver exits without mutating branches, PRs, tracker status, or issue
   state.

**Postconditions**: The actor knows why delegated work cannot safely proceed
and what input must be clarified.

**Information shown**:

- Each ambiguous item and the specific reason it is ambiguous.
- Conflicting base-branch or scope signals.
- The command input that would make the scope deterministic, such as an
  explicit item list or base override.

**Actions available**:

- Correct tracker labels or dependencies.
- Re-run with a narrower explicit list.
- Re-run with a base override.
- Stop and request a human workflow decision.

**Considerations**:

- Ambiguity is a resolver outcome, not an error to work around silently.
- Later delegated review and merge behavior must be blocked until the resolver
  output is deterministic.

## Business Rules

- The resolver accepts an epic issue or an explicit item list as the initial
  scope source.
- When an epic is provided, native sub-issues are the preferred child-item
  source when available.
- When an explicit item list is provided, only listed items are in scope.
- The resolver must read tracker Status, Type, Priority, dependency state,
  labels, linked PR state, and issue state for every item it reports.
- The resolver must infer one target base branch for the execution set.
- A supplied base override takes precedence over inferred labels.
- If every item shares one integration-branch label, the inferred base branch is
  the matching integration branch.
- If no integration branch is implied, the inferred base branch is `develop`.
- Items that imply different base branches make the set ambiguous unless the
  actor supplies a base override.
- The resolver must group all resolved items as eligible, blocked, already
  merged, in review, ambiguous, or out of scope.
- The resolver-only path must not start Backlog items, update tracker status,
  create branches, open PRs, merge PRs, close issues, or delete branches.
- The resolver output must be readable by a human and stable enough for later
  delegated workflow steps to consume.

## Statuses / Enum Values

| Code value       | Display label  | Description                                                       |
| ---------------- | -------------- | ----------------------------------------------------------------- |
| `eligible`       | Eligible       | The item has a deterministic next action within the resolved set. |
| `blocked`        | Blocked        | The item has an unmet dependency or required external condition.  |
| `already_merged` | Already merged | The item is terminal or already represented by a merged PR.       |
| `in_review`      | In review      | The item is waiting for human review or merge.                    |
| `ambiguous`      | Ambiguous      | The item cannot be routed safely without more information.        |
| `out_of_scope`   | Out of scope   | The item was discovered but is outside the requested boundary.    |

**Valid transitions**:

- `ambiguous` -> `eligible` when the actor supplies a deterministic scope or
  base-branch correction.
- `blocked` -> `eligible` when all dependencies and external conditions are
  satisfied.
- `in_review` -> `already_merged` after the related PR is merged and cleanup is
  verified.
- `eligible` remains non-mutating in resolver-only mode; later delegated modes
  may advance it only after a separate authorization step.

## Operational Visibility

- **Resolver summary**: Every run prints the scope source, inferred base branch,
  item counts by group, and the grouped item list.
- **Ambiguity report**: Ambiguous runs print the exact items and state that
  prevented deterministic routing.
- **Read-only guarantee**: Resolver output states that no tracker status,
  branch, PR, merge, issue-close, or cleanup mutation was performed.
- **Audit handoff**: The grouped execution set is suitable for later
  delegated-review, risk, and audit-trail features to reference.

## Acceptance Criteria

- [ ] AC1: Given an epic issue with native sub-issues, the resolver reports the
      epic and each resolved child item with title, Status, Type, Priority,
      dependency state, labels, linked PR state, and issue state.
- [ ] AC2: Given an explicit item list, the resolver reports only the listed
      items and does not include sibling, parent, or label-matched items that
      were not listed.
- [ ] AC3: Given a supplied base override, the resolver reports that base as the
      target base branch for the execution set.
- [ ] AC4: Given items that share one integration-branch label and no supplied
      base override, the resolver reports the matching integration branch as the
      target base branch.
- [ ] AC5: Given items with no integration-branch label and no supplied base
      override, the resolver reports `develop` as the target base branch.
- [ ] AC6: Given items with conflicting base-branch signals and no supplied
      override, the resolver reports the set as ambiguous and identifies the
      conflicting items.
- [ ] AC7: Resolver output groups every resolved item as eligible, blocked,
      already merged, in review, ambiguous, or out of scope.
- [ ] AC8: Resolver-only runs do not start Backlog items, update tracker
      status, create branches, open PRs, merge PRs, close issues, or delete
      branches.
- [ ] AC9: Resolver output includes a read-only guarantee so the actor can tell
      that the run was limited to scope discovery.
- [ ] AC10: If an epic has no resolvable native sub-issues, the resolver reports
      that condition clearly and does not silently treat the parent epic as the
      only child item.

## Out of Scope (MVP)

- Starting Backlog items from the resolved execution set.
- Delegated reviewer-loop triage, risk classification, merge decisions, branch
  cleanup, or tracker closeout.
- Label, milestone, or integration-branch-only scope inputs beyond the initial
  epic and explicit item-list interface.
- Repository-wide autonomy profiles or persistent delegation defaults.
- Changing existing `/run-work`, `/run-item-work`, reviewer-loop, CI-loop,
  batch-merge, or post-merge cleanup behavior.

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Add a `/run-epic` scope resolver for an epic issue. | Use Case 1, BR1-BR3, AC1, AC10 |
| Add a `/run-epic` scope resolver for an explicit item list. | Use Case 2, BR1, BR3, AC2 |
| Resolve native GitHub sub-issues for an epic when available. | Use Case 1, BR2, AC1, AC10 |
| Resolve explicit item lists without requiring an epic. | Use Case 2, BR3, AC2 |
| Read tracker Status, Type, Priority, dependencies, labels, linked PRs, and issue state for every resolved item. | BR4, AC1 |
| Infer the target base branch from a supplied base override, a shared integration-branch label, or `develop` when no integration branch is implied. | BR5-BR9, AC3-AC5 |
| Stop and report ambiguity when items imply different base branches or the scope boundary is unclear. | Use Case 3, BR10, AC6 |
| Print an execution set grouped as eligible, blocked, already merged, in review, ambiguous, or out of scope. | BR11, Statuses / Enum Values, AC7 |
| Avoid starting Backlog items, mutating statuses, or merging PRs in the resolver-only path. | BR12, Operational Visibility, AC8, AC9 |
| Provide a visible and auditable foundation for later delegated epic autonomy. | Overview, Operational Visibility, BR13 |

## Deferral Notes

- Label, milestone, and integration-branch-only scope inputs are deferred
  because the approved first implementation focuses on epic and explicit
  item-list support. They remain listed under Out of Scope for future-compatible
  expansion.
- Delegated review, merge, risk classification, and audit-trail behavior is
  deferred to sibling items in the same epic so this foundational resolver can
  remain read-only and auditable.
