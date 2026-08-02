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
- The recheck applies only to the frozen in-scope PR set selected for the batch,
  whether the batch came from an explicit list, delegated `/run-items`, or
  batch-merge discovery.
- A PR discovered during recheck outside the frozen set is observation-only and
  must not trigger mutation, additional rechecks, or opportunistic advancement.

### Use Case 2: Remaining PR becomes conflicted

**Actor**: Batch merge runner.
**Preconditions**: A sibling PR has merged and at least one remaining in-scope
PR now reports a dirty, blocked, unknown, or otherwise non-clean mergeability
state.

**Steps**:

1. The runner detects the non-clean refreshed state.
2. The runner classifies the refreshed state as retryable or terminal for that
   PR.
3. The runner keeps retryable pending or temporarily unknown states under
   supervision until they become clean, become terminal non-clean, or hit the
   configured timeout.
4. The runner records dirty, blocked, timed-out unknown, failing, or otherwise
   terminal non-clean states as `merge_blocked` for that PR and stops before
   attempting to merge it.
5. The runner preserves the original PR order, skips the blocked PR without
   reordering remaining entries, and continues only with later PRs whose
   independently refreshed evidence is clean and whose existing merge-order
   guardrails remain satisfied.

**Postconditions**: A PR invalidated by a sibling merge is not merged or
reported ready using stale evidence.

**Information shown**:

- The affected PR, refreshed non-clean state, and whether the state is retryable
  or terminal.
- The sibling merge that invalidated prior evidence.
- The required next action, such as resolving conflicts or rerunning readiness.

**Actions available**:

- Resolve the conflict and rerun readiness for the affected PR.
- Continue with later refreshed-clean PRs without reordering the original batch
  when existing merge-order guardrails still allow it.
- Stop the batch when the remaining order or state is no longer safe.

**Considerations**:

- Pending and temporarily unknown states remain supervised until the configured
  polling or retry window ends; they are not terminal while legitimate checks
  are still in progress.
- Dirty, conflicted, blocked, failing, timed-out unknown, or exhausted pending
  states are terminal `merge_blocked` outcomes for that PR until it is updated
  and readiness is rerun.
- A retryable state that changes to dirty, conflicted, blocked, failing, behind,
  or another terminal non-clean state leaves retry supervision immediately and
  is recorded as `merge_blocked`.
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

**Considerations**:

- The same stale-evidence boundary repeats after every successful sibling merge.
- A later recheck can still change a previously refreshed-clean PR to retryable
  or terminal non-clean, and the summary must reflect the latest evidence.

## Business Rules

- A successful sibling PR merge invalidates previously collected mergeability
  evidence for every unmerged PR in the same bounded batch.
- The batch has one frozen in-scope PR set after selection. This applies to
  explicit-list batches, delegated `/run-items` runs, and batch-merge discovery.
- The workflow must re-query authoritative PR state for all remaining in-scope
  PRs before attempting another merge or reporting a final ready state.
- A remaining PR with dirty, blocked, unknown, behind, failing, pending, or
  otherwise non-clean refreshed evidence must not be merged under stale
  readiness.
- Pending and temporarily unknown states are retryable only while checks are
  legitimately in progress and within the configured polling or retry window.
  Record `merge_blocked` immediately if the state becomes terminal non-clean;
  otherwise record `merge_blocked` when the window expires.
- Dirty, conflicted, blocked, failing, or behind states are terminal
  `merge_blocked` for the affected PR unless the existing workflow routes the PR
  into an in-scope fix path before continuing.
- A blocked PR does not by itself stop processing later PRs. The runner must
  preserve the original order, skip the blocked entry, and continue only when
  each later PR has independently refreshed clean evidence and all existing
  merge-order guardrails remain satisfied.
- Per-PR terminal outcomes must reflect refreshed state after the last sibling
  merge that could affect that PR.
- Out-of-scope PRs discovered during recheck are observation-only and must not
  be rechecked for mutation, labeled, merged, or opportunistically advanced.
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
  named terminal outcome of `merge_blocked`, with the required next action.
- **Final batch summary**: The final report distinguishes merged PRs from PRs
  held after refreshed mergeability changed.
- **Outcome contract**: For delegated `/run-items` merge supervision, refreshed
  rechecks use the existing terminal outcomes: `merged`, `merge_blocked`,
  `policy_inconsistent`, `ready_human_merge`, and `out_of_scope`. In scoped
  Protocol 94 batch-merge output, `merge_blocked` maps to the existing
  skipped-or-held conflict/not-ready outcome while preserving the more specific
  refreshed-state reason in the summary.

## Acceptance Criteria

- [ ] After any PR in a multi-PR batch merges, the workflow rechecks
      authoritative mergeability and required check state for every remaining
      in-scope PR before the next merge attempt.
- [ ] Previously collected clean evidence for remaining PRs is treated as stale
      after the approved base branch changes.
- [ ] A remaining PR whose refreshed state is dirty, blocked, unknown, behind,
      failing, pending, or otherwise non-clean is not merged under the prior
      clean result.
- [ ] Pending and temporarily unknown states remain supervised while checks are
      legitimately in progress, become terminal `merge_blocked` immediately if
      the refreshed state changes to terminal non-clean, and otherwise become
      terminal `merge_blocked` only after the configured polling or retry window
      is exhausted.
- [ ] The blocked PR's summary names the sibling merge that invalidated the
      previous evidence and the refreshed state that prevents merge.
- [ ] Refreshed-clean PRs can continue through the batch merge sequence without
      a new human approval when the original delegated policy still applies.
- [ ] The original PR order is preserved when a PR becomes blocked; the blocked
      PR is skipped, not reordered, and later PRs merge only after independent
      refreshed-clean evidence and existing merge-order guardrails pass.
- [ ] Frozen batch scope is preserved: out-of-scope PRs are observation-only and
      are not rechecked for mutation, labeled, merged, or opportunistically
      advanced during the recheck.
- [ ] The final batch summary reports per-PR terminal outcomes based on the
      latest post-sibling-merge evidence.
- [ ] Regression coverage simulates two initially clean sibling PRs where the
      first merge makes the second dirty, and verifies the second is held rather
      than merged or reported clean.

## Recheck Consistency Matrix

| Refreshed state after sibling merge | Required outcome | Information shown | Next action |
| --- | --- | --- | --- |
| Clean and required checks still pass | Continue | PR number, refreshed clean state, next merge candidate | Merge according to current order and guardrails |
| Pending checks still legitimately in progress | Retryable supervision | PR number, invalidating sibling merge, pending checks | Continue polling until clean, failing, or timeout |
| Temporarily unknown state within retry window | Retryable supervision | PR number, invalidating sibling merge, unavailable evidence | Re-query until evidence is available or timeout expires |
| Dirty or conflicted | `merge_blocked` | PR number, invalidating sibling merge, dirty state | Preserve order, skip this PR, resolve conflicts or rerun readiness after update |
| Blocked, behind, failing, timed-out unknown, or exhausted pending | `merge_blocked` | PR number, refreshed terminal non-clean state, reason it cannot merge now | Preserve order, skip this PR, route to fixes or stop with blocker |
| Out-of-scope PR discovered during recheck | `out_of_scope` observation | Identifier and frozen batch boundary | Skip all mutations and do not add it to the recheck set |

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Recheck remaining PRs | Use Case 1, Business Rules, AC1 |
| 2. Prevent stale clean evidence reuse | Use Cases 1-2, Business Rules, AC2-AC4 |
| 3. Stop or route non-clean PRs | Use Case 2, Operational Visibility, AC3-AC6 |
| 4. Keep summaries accurate | Operational Visibility, AC8 |
| 5. Add regression coverage | Acceptance Criteria AC9 |

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

See [Out of Scope (MVP)](#out-of-scope-mvp) for the canonical deferral list.
