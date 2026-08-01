# Batch PR Mergeability Recheck - Spec

---

## Overview

Batch merge operators need the workflow to treat mergeability as fresh evidence
after every sibling PR merge. A PR that was clean before another PR merged can
become conflicted immediately afterward, so the batch must recheck the remaining
PRs before reporting readiness or attempting the next merge.

This change makes stale mergeability evidence invalid after each sibling merge.
It is orthogonal to issue #1423, which covers unauthorized force-push behavior;
this item focuses only on post-merge revalidation of remaining PRs in the same
batch.

## Brief Objective List

Derived from issue #1424:

1. Recheck every remaining in-scope batch PR after each sibling PR is merged.
2. Prevent stale clean/mergeable evidence from being reused after the approved
   base branch changes.
3. Stop or route to conflict handling when a remaining PR becomes dirty,
   blocked, unknown, or otherwise no longer mergeable.
4. Keep the batch summary and terminal outcomes accurate after each recheck.
5. Add regression coverage for a sibling merge that invalidates a previously
   clean PR.

## Actors

- **Batch operator**: approves a bounded multi-PR merge or delegated batch run.
- **Portfolio orchestrator**: supervises the in-scope PR list and must refresh
  remaining PR state after each merge.
- **Batch merge runner**: performs the merge sequence and reports per-PR
  terminal outcomes.

## Use Cases

### Use Case 1: Recheck remaining PRs after a sibling merge

**Actor**: Portfolio orchestrator.
**Preconditions**: A bounded batch contains multiple in-scope PRs, all current
pre-merge checks have passed, and one PR has just merged into the approved
base.

**Steps**:

1. The orchestrator records the merged PR outcome.
2. The orchestrator treats prior mergeability evidence for unmerged sibling PRs
   as stale.
3. The orchestrator re-queries authoritative PR mergeability and required check
   state for each remaining in-scope PR.
4. The orchestrator continues only with PRs whose refreshed evidence is clean.

**Postconditions**: Every subsequent merge decision uses evidence collected
after the latest base-branch change.

**Information shown**:

- The PR that was just merged.
- The remaining PRs that were rechecked.
- The refreshed mergeability outcome for each remaining PR.

**Actions available**:

- Continue merging refreshed-clean PRs.
- Hold or route conflicted PRs to the appropriate recovery path.

**Considerations**:

- The recheck must happen even when all PRs were clean at the start of the
  batch.
- The recheck applies only to the explicit in-scope PR list for the batch.

### Use Case 2: Remaining PR becomes conflicted

**Actor**: Batch merge runner.
**Preconditions**: A sibling PR has merged and at least one remaining in-scope
PR now reports a dirty, blocked, unknown, or otherwise non-clean mergeability
state.

**Steps**:

1. The runner detects the non-clean refreshed state.
2. The runner stops before attempting to merge that PR.
3. The runner records the PR as merge-blocked or routes it to the established
   conflict-resolution flow when that is available and in scope.
4. The runner continues only with other remaining PRs whose refreshed evidence
   is clean and whose order remains valid.

**Postconditions**: A PR invalidated by a sibling merge is not merged or
reported ready using stale evidence.

**Information shown**:

- The affected PR and refreshed non-clean state.
- The sibling merge that invalidated prior evidence.
- The required next action, such as resolving conflicts or rerunning readiness.

**Actions available**:

- Resolve the conflict and rerun readiness for the affected PR.
- Continue with other refreshed-clean PRs when safe.
- Stop the batch when the remaining order or state is no longer safe.

**Considerations**:

- A non-clean recheck is a real terminal or routing condition for that PR, not a
  transient state to ignore.
- The summary must not claim the PR is ready or merged unless refreshed evidence
  supports that claim.

### Use Case 3: Rechecked PRs remain clean

**Actor**: Batch merge runner.
**Preconditions**: A sibling PR has merged, and refreshed evidence shows all
remaining in-scope PRs are still clean and eligible.

**Steps**:

1. The runner records the refreshed-clean state for each remaining PR.
2. The runner proceeds to the next merge candidate according to the current
   batch order and guardrails.
3. The same recheck repeats after each successful sibling merge until no
   unmerged in-scope PRs remain.

**Postconditions**: The batch completes using current mergeability evidence at
each step.

**Information shown**:

- The refreshed-clean result for remaining PRs.
- The next PR selected for merge.
- The final per-PR outcome after the batch ends.

**Actions available**:

- Continue the batch merge sequence.
- Stop if any later refreshed state changes.

## Business Rules

- A successful sibling PR merge invalidates previously collected mergeability
  evidence for every unmerged PR in the same bounded batch.
- The workflow must re-query authoritative PR state for all remaining in-scope
  PRs before attempting another merge or reporting a final ready state.
- A remaining PR with dirty, blocked, unknown, behind, failing, pending, or
  otherwise non-clean refreshed evidence must not be merged under stale
  readiness.
- Per-PR terminal outcomes must reflect refreshed state after the last sibling
  merge that could affect that PR.
- Out-of-scope PRs must not be rechecked for mutation or opportunistic
  advancement under an explicit-list batch.
- The recheck requirement applies to delegated `/run-items` merges and scoped
  batch-merge flows that process more than one PR against the same base.
- Conflict recovery must preserve the repository's no-force-push policy; any
  destructive branch-history recovery remains governed by #1423 and separate
  explicit authorization.

## Operational Visibility

- **Post-merge recheck log**: After each sibling merge, the runner reports the
  remaining in-scope PRs that were refreshed and their current mergeability
  states.
- **Stale evidence boundary**: The summary identifies that pre-merge clean
  evidence was invalidated by a base-branch update.
- **Blocked PR outcome**: A conflicted or non-clean remaining PR receives a
  named terminal outcome such as `merge_blocked`, with the required next action.
- **Final batch summary**: The final report distinguishes merged PRs from PRs
  held after refreshed mergeability changed.

## Acceptance Criteria

- [ ] After any PR in a multi-PR batch merges, the workflow rechecks
      authoritative mergeability and required check state for every remaining
      in-scope PR before the next merge attempt.
- [ ] Previously collected clean evidence for remaining PRs is treated as stale
      after the approved base branch changes.
- [ ] A remaining PR whose refreshed state is dirty, blocked, unknown, behind,
      failing, pending, or otherwise non-clean is not merged under the prior
      clean result.
- [ ] The blocked PR's summary names the sibling merge that invalidated the
      previous evidence and the refreshed state that prevents merge.
- [ ] Refreshed-clean PRs can continue through the batch merge sequence without
      a new human approval when the original delegated policy still applies.
- [ ] Explicit-list scope is preserved: out-of-scope PRs are not mutated,
      labeled, merged, or opportunistically advanced during the recheck.
- [ ] The final batch summary reports per-PR terminal outcomes based on the
      latest post-sibling-merge evidence.
- [ ] Regression coverage simulates two initially clean sibling PRs where the
      first merge makes the second dirty, and verifies the second is held rather
      than merged or reported clean.

## Recheck Consistency Matrix

| Refreshed state after sibling merge | Required outcome | Information shown | Next action |
| --- | --- | --- | --- |
| Clean and required checks still pass | Continue | PR number, refreshed clean state, next merge candidate | Merge according to current order and guardrails |
| Dirty or conflicted | Merge blocked | PR number, invalidating sibling merge, dirty state | Resolve conflicts or rerun readiness after update |
| Unknown, blocked, behind, pending, or failing | Merge blocked or keep supervising when checks are still legitimately in progress | PR number, refreshed state, reason it is not mergeable now | Re-query until terminal, route to fixes, or stop with blocker |
| Out-of-scope PR discovered during recheck | Out of scope | Identifier and explicit-list boundary | Skip all mutations for that PR |

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Recheck remaining PRs | Use Case 1, Business Rules, AC1 |
| 2. Prevent stale clean evidence reuse | Use Cases 1-2, Business Rules, AC2-AC4 |
| 3. Stop or route non-clean PRs | Use Case 2, Operational Visibility, AC3-AC4 |
| 4. Keep summaries accurate | Operational Visibility, AC6-AC7 |
| 5. Add regression coverage | Acceptance Criteria AC8 |

## Out of Scope (MVP)

- Automatically resolving merge conflicts for every file type. **Deferral
  Note**: the MVP requires detection and correct routing; conflict-resolution
  mechanics remain governed by existing merge and fix flows.
- Changing the batch item-selection algorithm. **Deferral Note**: this item
  operates after a bounded PR list already exists.
- Revalidating or mutating out-of-scope PRs. **Deferral Note**: explicit-list
  scope remains authoritative for batch execution.
- Preventing unauthorized force-push recovery paths. **Deferral Note**: issue
  #1423 covers that orthogonal branch-history safety guard.

## PR-Visible Deferral Notes

- **Universal conflict repair**: Deferred because the core requirement is to
  prevent stale mergeability use and route invalidated PRs correctly.
- **Batch selection changes**: Deferred because the feature applies during
  merge supervision, after the in-scope PR list is known.
- **Out-of-scope PR handling**: Deferred to existing explicit-list scope
  guardrails; rechecks must not widen the batch.
- **Force-push prevention**: Deferred to #1423, which is an orthogonal sibling
  workflow-safety item from the same retrospective.
