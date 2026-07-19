# Reviewer Loop Retry History Preservation - Spec

---

## Overview

Reviewer-loop summaries should preserve enough structured history for
retrospectives to reconstruct how many review/fix cycles happened before a PR
became clean. Today the final stable summary can show only the terminal clean
state, which makes retry metrics unavailable even when the live run clearly had
review churn. This feature requires durable, machine-readable iteration history
for automated reviewer-loop runs while preserving the current clean terminal
summary and readiness gates.

## Brief Objective List

1. Preserve reviewer-loop iteration history for each PR in a durable,
   machine-readable form.
2. Let retrospectives reconstruct retry counts, run outcomes, blocker counts,
   and timestamps after the final reviewer-loop summary has been updated.
3. Keep the final reviewer-loop summary useful for humans while retaining
   historical run data.
4. Avoid losing significant review churn when the final state is clean.
5. Preserve existing reviewer-loop, CI, readiness-label, and merge behavior.

## Use Cases

### Use Case 1: Reviewer loop records multiple iterations

**Actor**: Automated reviewer-loop runner.
**Preconditions**: A PR enters the automated reviewer loop and one or more
review/fix iterations occur before the PR is clean.

**Steps**:

1. The reviewer loop starts an iteration and records its timestamp.
2. The loop records the iteration outcome, reviewer result, blocker count, and
   any retry-relevant status.
3. If fixes are required, the loop continues to the next iteration and appends a
   new history entry.
4. When the PR becomes clean, the loop records the final clean iteration without
   deleting prior iteration history.

**Postconditions**: The PR retains structured evidence for every relevant
review-loop iteration in addition to the final clean state.

**Information shown**:

- Iteration number.
- Timestamp or run ordering evidence.
- Reviewer-loop result.
- Blocking finding count or equivalent blocker signal.
- Final terminal outcome.

**Actions available**:

- Continue the existing fix-and-rerun loop.
- Preserve history when the summary is updated.
- Report history as unavailable only when the loop could not read or write the
  durable record, with a visible reason.

**Considerations**:

- The history should be compact enough that it does not bury the human-readable
  terminal summary.
- The history should be resilient across summary-comment updates.

### Use Case 2: Retrospective reads retry metrics after merge

**Actor**: Retrospective runner or human reviewer analyzing a merged batch.
**Preconditions**: A PR has completed reviewer-loop processing and may already
be merged.

**Steps**:

1. The retrospective reads the PR's durable reviewer-loop history.
2. It extracts retry count, run outcomes, blocker counts, and timestamps.
3. It reports exact metrics when history is available.
4. If history is absent or unreadable, it reports a specific unavailable reason
   rather than silently treating retries as zero.

**Postconditions**: Retrospective metrics reflect actual reviewer-loop churn or
clearly explain why exact metrics cannot be reconstructed.

**Information shown**:

- Number of reviewer-loop iterations.
- Number of retry loops before clean.
- Per-iteration result and blocker count.
- Any unavailable-history reason.

**Actions available**:

- Use exact retry metrics in batch retrospectives.
- Flag missing history as a workflow instrumentation gap.
- Continue reading the final clean summary for human context.

**Considerations**:

- Metrics should remain available after PR merge and branch cleanup.
- The retrospective should not depend on transient terminal output from the
  original runner session.

### Use Case 3: Single clean reviewer-loop run stays simple

**Actor**: Automated reviewer-loop runner.
**Preconditions**: A PR enters the reviewer loop and the first completed
iteration is clean.

**Steps**:

1. The reviewer loop records one history entry.
2. The final summary shows the clean terminal result.
3. Retrospective tooling reads one iteration and reports zero retries.

**Postconditions**: Clean PRs still have structured history without adding noise
or implying unnecessary churn.

**Information shown**:

- One clean iteration.
- Zero retry loops.

**Actions available**:

- Proceed through normal readiness and CI gates.

**Considerations**:

- The history mechanism must handle both high-churn and no-churn PRs.

## Business Rules

- Every completed reviewer-loop iteration must preserve structured history with
  enough information to reconstruct retry metrics later.
- Reviewer-loop history must include at least an iteration order, terminal or
  intermediate result, blocker count or equivalent blocker signal, and timestamp
  or stable ordering evidence.
- Updating the final reviewer-loop summary must not discard prior iteration
  history.
- A PR that reaches clean on the first loop must still record one history entry
  so retrospectives can report zero retries confidently.
- If history cannot be read or written, the workflow must expose a specific
  unavailable reason rather than silently dropping metrics.
- Reviewer-loop history must not weaken blocking-review handling: unresolved
  blocking findings still prevent readiness.
- Reviewer-loop history must not change CI requirements, readiness labels,
  tracker transitions, or merge authority.

## Operational Visibility

- **PR evidence**: A PR exposes durable reviewer-loop history that can be read
  after the final clean summary is posted.
- **Retrospective evidence**: Retrospectives can distinguish exact retry counts
  from unavailable metrics with a reason.
- **Human summary**: The final reviewer-loop summary remains readable and focused
  on the current terminal state.
- **Failure signal**: Missing or unreadable history is visible as an
  instrumentation gap, not hidden as a clean zero-retry run.

## Acceptance Criteria

- [ ] AC1: Given a PR with multiple reviewer-loop iterations, the durable
      history records each completed iteration before the PR is marked clean.
- [ ] AC2: Given a final reviewer-loop summary is updated to show a clean state,
      prior iteration history remains available for retrospective reads.
- [ ] AC3: Given a retrospective analyzes a PR with preserved history, it can
      report exact retry count, per-iteration result, blocker count, and
      timestamp or stable ordering evidence.
- [ ] AC4: Given a PR reaches clean on the first reviewer-loop iteration, the
      history records one clean iteration and retrospectives report zero
      retries.
- [ ] AC5: Given reviewer-loop history is missing or unreadable, retrospective
      output reports a specific unavailable reason instead of treating the retry
      count as zero.
- [ ] AC6: Given reviewer-loop history is preserved, existing blocking-review,
      CI, readiness-label, tracker-status, and merge-authority gates continue to
      behave as before.
- [ ] AC7: Given humans inspect the final reviewer-loop summary, the summary
      remains focused on the current terminal state while still providing access
      to the preserved history.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Preserve reviewer-loop iteration history in durable, machine-readable form | Use Case 1, Business Rules | AC1, AC2 |
| 2. Let retrospectives reconstruct retry counts, outcomes, blocker counts, and timestamps | Use Case 2, Operational Visibility | AC3, AC5 |
| 3. Keep the final summary useful while retaining history | Use Cases 1 and 3, Operational Visibility | AC2, AC7 |
| 4. Avoid losing significant review churn when final state is clean | Overview, Use Cases 1 and 2 | AC1, AC2, AC3 |
| 5. Preserve existing reviewer-loop, CI, readiness, and merge behavior | Business Rules | AC6 |

## Out of Scope (MVP)

- Selecting the exact persistence mechanism for the history record.
- Changing reviewer severity mapping or blocker classification.
- Changing reviewer-loop retry budgets.
- Changing CI requirements, readiness labels, tracker transitions, or merge
  authority.
- Backfilling exact retry history for PRs completed before this feature ships.
