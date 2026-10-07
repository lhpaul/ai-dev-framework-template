# GraphQL budget-aware delegated merging — Spec

**Issue**: [#1890](https://github.com/lhpaul/ai-dev-framework-template/issues/1890)

## Overview

Delegated single-item, epic, and batch merge operations must check the available
GraphQL quota before changing remote workflow state. An operation whose projected
cost plus reserve exceeds the remaining budget defers without merging any PR.
If concurrent activity or a service failure interrupts admitted work, the
operator receives a recorded account of completed and unfinished steps.

The operator is a maintainer or an authorized workflow agent. Existing review,
CI, risk, checkpoint, and merge permissions continue to govern admission.
This feature adds a budget requirement; it does not grant merge authority.

## Use Cases

### Use Case 1: Complete an affordable delegated merge

**Actor**: Authorized workflow operator.
**Preconditions**: A bounded PR set and merge policy have been selected.

**Steps**:

1. Start the delegated merge workflow for that set.
2. Receive a budget assessment covering the planned gate, merge, cleanup,
   audit, and tracker reconciliation work.
3. If the budget and existing readiness gates allow it, complete the workflow.
4. Read the result for each selected PR and its reconciliation state.

**Postconditions**: Eligible PRs are merged and their required follow-up is
reported; existing policy stops remain effective.

**Information shown**: Initial remaining points, projected cost, reserve,
reset time, final available budget when readable, and per-PR outcomes.

**Actions available**: Inspect the result or resolve an existing readiness stop.

**Considerations**: Available points equal to projected cost plus reserve pass
the budget check. Passing this check alone never permits a merge.

### Use Case 2: Defer an unaffordable or unreadable operation

**Actor**: Authorized workflow operator.
**Preconditions**: This attempt has not reached its first mutating step. A fresh
sequence contains unmerged PRs; recovery can include already merged PRs.

**Steps**:

1. Start the delegated merge workflow.
2. Receive a deferred result because the quota is insufficient or cannot be
   assessed reliably.
3. Inspect the reason and every PR's known state, including PRs left unmerged.
4. Retry explicitly after the reported reset, or after resolving unreadable
   budget evidence.

**Postconditions**: No new merge or workflow mutation occurred in this attempt.
Fresh deferral leaves all selected PRs unmerged. Recovery deferral preserves
previously verified merged, unmerged, uncertain, and pending follow-up states;
unavailable live reads are marked as unavailable rather than overwriting them.
The workflow does not poll or retry until the reset.

**Information shown**: Remaining points and reset time when available; otherwise
an explicit unavailable indication, reason, and operator recovery action.

**Actions available**: Retry later or repair the unavailable budget source.

**Considerations**: Missing, malformed, failed, or internally inconsistent quota
evidence cannot be replaced by REST quota or assumed sufficient budget.

### Use Case 3: Recover an interrupted admitted sequence

**Actor**: Authorized workflow operator.
**Preconditions**: A sequence passed admission and began changing state.

**Steps**:

1. Encounter quota exhaustion or another failure during the sequence.
2. Inspect a durable progress record identifying completed steps, the failed or
   uncertain step, and pending cleanup, audit, and tracker reconciliation.
3. Resume from verified live state after quota or service access recovers.

**Postconditions**: Interruption is reported explicitly; completed merges are
never described as unmerged, and pending reconciliation is never called complete.

**Information shown**: PR identities, last verified merge state, completed and
pending follow-up, reset time when readable, and the recovery action.

**Actions available**: Inspect live state and resume the outstanding workflow.

**Considerations**: A failed response can leave a mutation's outcome uncertain.
The record must distinguish uncertainty from a verified failure. Recording
progress must remain possible when the remote API is unavailable.

## Business Rules

1. Sample the GraphQL budget before the first workflow mutation, including
   remote audit or readiness changes made by the merge operation itself.
2. Admission requires readable budget evidence and a bounded projection for the
   whole selected sequence plus a valid nonnegative reserve. Missing, malformed,
   or negative resolved reserve values defer without mutations. Configuration
   defaults may supply an omitted setting; a valid resolved reserve is still
   required. Cost estimation and configuration mechanics belong in the plan.
3. Insufficient or unknown budget defers the complete selected set before any
   merge. A batch must not admit an affordable prefix of an unaffordable set.
4. The initial sample is not an exclusive reservation: concurrent consumers can
   spend points. Reports must not claim guaranteed atomicity across remote merges.
5. Once work starts, keep durable progress evidence across merge and follow-up
   boundaries. Stop starting additional merges on an interruption; report all
   unfinished work rather than silently dropping cleanup or reconciliation.
6. Recovery verifies live state before repeating a potentially completed action.
   Its admission projection covers only verified outstanding work. Unknown
   outstanding work defers; no deferral changes previously recorded PR states.
7. Preserve existing permissions, risk classification, review freshness,
   readiness checks, checkpoint policy, and tracker ownership in consumers.

## Operational Visibility

Budget outcomes are **Admitted**, **Deferred**, **Completed**, and **Interrupted**.
Admitted work can become Completed or Interrupted. Deferred work starts no
mutations. An explicit retry re-assesses budget and existing gates; it does not
reuse old admission evidence. Interrupted work retains a recovery record.

Reports distinguish verified merged PRs, verified unmerged PRs, and uncertain
outcomes. Report points spent as an observed sample difference only when both
samples are readable, describe the same quota window and limit, and final
remaining points do not exceed the initial value. A reset, changed limit, or
increased balance makes spend unavailable; show the individual readable samples
and the reason instead. Concurrent consumption must not be attributed solely
to this run.
An unavailable final sample is visible and does not erase recorded progress.
No new notification channel or analytics system is required.

## Decision Matrix

Evaluate rows 1–3 once for initial admission, before the first mutation. Only
one of those rows can match. A recovery attempt uses the same admission rows for
outstanding work while preserving its recorded PR and follow-up states. After
admission, evaluate rows 4–6 for execution
outcomes; the initial budget rows do not reclassify completed or interrupted
work. Existing readiness stops also apply to admitted work.

| Row | Budget / execution input | Outcome | Required next action |
| --- | --- | --- | --- |
| 1 | Before admission; initial evidence or work projection unreadable, or resolved reserve invalid | Deferred | Report reason and recovery action; no new mutation; fresh PRs stay unmerged, recovery retains recorded states |
| 2 | Before admission; readable evidence, valid reserve, and remaining points below projection plus reserve | Deferred | Report budget, reset, and PR states; no new mutation; fresh PRs stay unmerged, recovery retains recorded states |
| 3 | Before admission; readable evidence, valid reserve, and remaining points at least projection plus reserve | Admitted | Apply existing gates and record progress before execution |
| 4 | Admitted; existing readiness gate denies execution | Existing policy stop | Report the existing stop and actual PR state; no unauthorized merge |
| 5 | Admitted; execution and follow-up complete | Completed | Report verified merge and reconciliation outcomes |
| 6 | Admitted; execution fails or outcome becomes uncertain | Interrupted | Record completed, uncertain, and pending steps; no additional merges; report recovery |

Example budget values are illustrative: remaining 1,200, cost 200, and reserve
1,000 admit the operation; remaining 1,199 defers the entire set. An admitted
two-PR sequence interrupted after the first merge records that PR as merged,
its pending follow-up explicitly, and the second PR's verified unmerged state.

**Mirror surfaces**: Delegated gate and risk-classification callers; batch merge
Protocol 94; canonical delegated merge guidance and command/skill surfaces that
describe affected outcomes. The plan enumerates exact consumers and sync/test
coverage. Portfolio scan behavior is outside this feature.

## Acceptance Criteria

- [ ] AC1: Mocked sufficient quota permits the existing gates to proceed only
  after budget evidence is sampled and before the first mutation.
- [ ] AC2: Mocked insufficient quota, including one point below the boundary,
  produces Deferred and reset time with zero new workflow mutation calls. Fresh
  admission reports every selected PR unmerged; recovery deferral preserves
  already merged, unmerged, uncertain, and pending follow-up states.
- [ ] AC3: Exact equality admits; projected cost covers the complete bounded
  sequence including gate, merge, cleanup, audit, and tracker reconciliation.
- [ ] AC4: Unreadable quota or unknown projection defers with an explicit reason
  and no mutations; missing, malformed, or negative resolved reserves also defer;
  REST budget cannot substitute for GraphQL evidence.
- [ ] AC5: Mocked interruption after a merge preserves durable completed,
  uncertain, and pending step evidence even when all remote calls fail.
- [ ] AC6: Interrupted work starts no additional merges, reports pending
  reconciliation, and can resume after verifying live state without duplicating
  a completed merge.
- [ ] AC7: Reports show projected cost, reserve, initial remaining points, reset
  time when available, and final points/spend when comparable; unavailable final
  evidence and concurrent consumption are visible. A reset, changed limit, or
  increased remaining balance shows samples and unavailable spend with a reason.
- [ ] AC8: Mocked coverage exercises delegated single-item/epic and batch paths,
  preserving current risk, review, CI, audit, and tracker gates.

## Out of Scope (MVP)

- Implementing #1505's portfolio scan, changing its reserve or running a live
  portfolio scan. Reuse available budget-reading conventions without requiring
  its unimplemented scan coordinator.
- Atomic rollback of remote merges, global quota locking, automatic waiting
  until reset, or unrelated API-call optimization.
- Raising merge permissions, bypassing existing gates, changing tracker states,
  adding notification services, or deleting operator-owned progress history.

## Brief Coverage

| Brief objective | Coverage | Disposition |
| --- | --- | --- |
| Read remaining GraphQL points before mutation | AC1, AC4 | In scope |
| Defer below projected cost plus reserve and report reset/unmerged PRs | AC2, AC3 | In scope |
| Never abandon merge/cleanup/reconciliation without recorded state | AC5, AC6 | In scope |
| Mocked rate-limit suite | AC1–AC8 | In scope |
| Reuse available #1505 budget-reading approach | AC7; Out of Scope boundary | Conventions reused; scan implementation excluded |

**Deferral Notes**: None of #1890's brief objectives are deferred.
