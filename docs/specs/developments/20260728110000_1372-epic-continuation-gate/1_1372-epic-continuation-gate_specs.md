# Epic Continuation Gate - Spec

---

## Overview

Workflow operators need an epic run to remain accountable for every approved
child item, not just the child pull request that happened to finish most
recently. When an epic contains more work after a child reaches a terminal
decision, the runner must make the remaining work visible and either continue
it or state the real boundary that prevents progress.

This change makes the epic lifecycle explicit after every child terminal
decision. Operators receive one of three clear outcomes: continue with named
remaining work, verify a fully completed epic, or resolve a named blocker
before ending the run.

## Brief Objective List

Derived from issue #1372:

1. Prevent an epic from ending after one merged child while eligible children
   remain.
2. Classify remaining work after every child terminal decision as continue,
   complete, or needs resolution.
3. Continue eligible or in-review work; only report completion when every
   resolved child is merged.
4. Require the named-stop contract for unresolved scope.
5. Add regression coverage for merged-plus-eligible, all-merged, empty-scope,
   and whitespace-only-input cases.
6. Keep the protocol and all applicable runner instruction surfaces aligned.

## Use Cases

### Use Case 1: Continue an epic after one child finishes

**Actor**: Workflow operator running an approved epic.
**Preconditions**: One child item has reached a terminal decision and at least
one other in-scope child remains eligible or is awaiting review.

**Steps**:

1. The runner completes the terminal handling for the child item.
2. The runner refreshes the epic scope.
3. The continuation result identifies the remaining child items.
4. The runner records the remaining item and advances it using the approved
   invocation policy.

**Postconditions**: The completed child is recorded as complete, but the epic
continues until its remaining work reaches a valid terminal outcome.

**Information shown**:

- The continuation outcome.
- The named remaining child item or items.
- The next action under the current invocation policy.

**Actions available**:

- Continue the next in-scope item.
- Address any normal review or execution step for an item awaiting review.

**Considerations**:

- A completed child pull request is not, by itself, evidence that the epic is
  complete.

---

### Use Case 2: Verify a completed epic

**Actor**: Workflow operator closing an epic after its child decisions.
**Preconditions**: Every resolved in-scope child is merged.

**Steps**:

1. The runner refreshes the epic scope after the final child decision.
2. The continuation result reports completion.
3. The runner verifies the live child states before reporting or closing the
   epic.

**Postconditions**: The epic is reported complete only after live verification
confirms that every resolved child is merged.

**Information shown**:

- The completion outcome.
- Live child-state verification evidence.

**Actions available**:

- Complete the epic lifecycle.
- Escalate if live state disagrees with the refreshed scope.

---

### Use Case 3: Stop safely for unresolved scope

**Actor**: Workflow operator handling an epic with ambiguous, blocked, or
otherwise unresolved remaining work.
**Preconditions**: The refreshed scope cannot safely continue or prove that
every child is merged.

**Steps**:

1. The runner refreshes the epic scope after a child terminal decision.
2. The continuation result reports that resolution is needed.
3. The runner verifies the actual blocker.
4. The runner reports the exact stop condition, affected child, and the human
   action required to unblock it.

**Postconditions**: The runner does not infer epic completion from a child
decision or from incomplete scope information.

**Information shown**:

- The unresolved outcome and affected child items.
- The named stop condition and required human action.

**Actions available**:

- Resolve tracker ambiguity.
- Provide required backlog-start or other workflow authority.
- Address a verified external dependency.

## Business Rules

- Every child terminal decision requires a refreshed epic-scope result before
  the runner may produce an epic summary.
- Remaining eligible or in-review children require the epic to continue under
  the approved invocation policy.
- An epic may be reported complete only when it has at least one resolved child
  and every resolved child is merged.
- An epic with no resolved children remains unresolved; it must not be
  auto-completed.
- Any ambiguous, blocked, out-of-scope, or authority-constrained remaining
  state requires explicit resolution rather than inferred completion.
- A final unresolved stop message names the exact stop condition, affected work
  item, and concrete human action required to unblock it.

## Operational Visibility

- **Continuation result**: The resolver presents the outcome, terminal state,
  next action, and grouped remaining child items in both machine-readable and
  operator-readable output.
- **Epic record**: The run record identifies the remaining child when the epic
  continues and records live verification when it completes.
- **Stop evidence**: An unresolved epic summary includes the named-stop
  information needed for a human to resume it safely.

## Acceptance Criteria

- [ ] After every child terminal decision, the runner refreshes epic scope and
      evaluates a continuation result before producing an epic summary.
- [ ] A merged child with an eligible sibling produces a non-terminal continue
      outcome that identifies the sibling as remaining work.
- [ ] Remaining eligible and in-review children keep the epic active under the
      approved invocation policy.
- [ ] A non-empty scope whose children are all merged produces the sole
      terminal complete outcome and requires live child-state verification
      before epic completion is reported.
- [ ] An empty epic scope and every other unresolved scope produce a
      needs-resolution outcome rather than a completion outcome.
- [ ] An unresolved final stop names the exact stop condition, affected item,
      and concrete human action needed to unblock the epic.
- [ ] Resolver tests cover merged-plus-eligible, all-merged, empty-scope, and
      whitespace-only explicit-item input behavior.
- [ ] The epic protocol and applicable Codex, Claude, and Cursor runner
      instructions describe the same continuation outcomes and next actions.

## Continuation Gate Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Regression example |
| --- | --- | --- | --- | --- |
| Eligible non-Backlog child remains | Continue | Name and advance the remaining child under the invocation policy. | Resolver, Protocol 95, Codex skill metadata, Claude and Cursor commands. | One merged child plus one eligible sibling. |
| Eligible Backlog child remains and backlog start is authorized | Continue | Name and start the remaining child under the invocation policy. | Same as above. | Remaining Backlog child with authority. |
| Child is in review | Continue | Keep the epic active and advance the applicable review path. | Same as above. | A child awaiting review after a sibling finishes. |
| Every resolved child is merged and scope is non-empty | Complete | Verify live child states, then report or close the epic. | Resolver and Protocol 95; runner instructions summarize the requirement. | All-merged scope. |
| Empty, ambiguous, blocked, authority-constrained, or otherwise unresolved scope | Needs resolution | Verify the blocker and use the named-stop contract before ending the run. | Resolver, Protocol 95, Codex skill metadata, Claude and Cursor commands. | Empty scope and remaining Backlog work without authority. |

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Prevent premature ending | Use Case 1, Business Rules, AC1-AC3 |
| 2. Classify continuation outcomes | Use Cases 1-3, Operational Visibility, AC1, AC4-AC5 |
| 3. Continue or complete correctly | Use Cases 1-2, AC2-AC4 |
| 4. Require named-stop handling | Use Case 3, Business Rules, AC5-AC6 |
| 5. Add regression coverage | AC7 and the matrix regression examples |
| 6. Align runner surfaces | Operational Visibility, AC8, continuation matrix |

## Out of Scope (MVP)

- Changing the existing delegated-review, delegated-merge, or graduation
  authority models.
- Automatically resolving tracker ambiguity, external dependencies, or missing
  authority.
- Changing non-epic batch or single-item continuation behavior.
