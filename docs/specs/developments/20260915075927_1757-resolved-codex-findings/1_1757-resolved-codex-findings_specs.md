# Resolved Codex findings no longer block the reviewer loop — Spec

## Overview

The automated reviewer loop must treat a Codex finding as actionable only while its corresponding review conversation remains unresolved and the evidence applies to the pull request's current revision. This prevents operators from spending additional fix cycles on historical findings that have already been resolved, while preserving a fail-closed path whenever the loop cannot establish current review evidence.

The change applies to workflow operators and to repositories that use the template's Codex GitHub review integration. It makes loop outcomes explainable: actionable feedback leads to a fix path, clean current evidence can advance to readiness, and cycle limits or incomplete evidence produce an explicit escalation rather than a misleading clean signal.

## Use Cases

### Use Case 1: Operator reruns review after resolving Codex feedback

**Actor**: Workflow operator
**Preconditions**: A pull request has historic Codex feedback, its associated review conversations have been resolved, and the pull request has a current revision.

**Steps**:

1. The operator starts or resumes the automated reviewer loop.
2. The loop evaluates Codex feedback together with the live resolution state of the related review conversations.
3. The loop evaluates whether terminal Codex evidence applies to the current pull-request revision.

**Postconditions**: Resolved historical feedback does not by itself send the pull request back to fixes. The loop proceeds using current actionable evidence only.

**Information shown**:

- The loop outcome identifies whether it found actionable feedback, current clean evidence, incomplete evidence, or an escalation.
- When review evidence is stale or incomplete, the outcome identifies that the pull request cannot advance yet.

**Actions available**:

- Address actionable feedback and rerun the loop.
- Trigger or wait for a current Codex review when current terminal evidence is absent.
- Escalate to a human when the loop reaches its configured cycle limit or cannot establish the required evidence.

**Considerations**:

- A finding that remains visible after its conversation is resolved is historical feedback, not a new blocker.
- A reply without a resolved conversation does not make the feedback non-actionable.

---

### Use Case 2: Operator evaluates readiness after a pull-request update

**Actor**: Workflow operator
**Preconditions**: A pull request has been updated after a prior Codex review or review-loop outcome.

**Steps**:

1. The operator runs the reviewer loop for the live pull-request revision.
2. The loop requires a terminal Codex review result that applies to that revision before it classifies the Codex phase as clean.
3. The normal readiness gates consume the loop outcome.

**Postconditions**: A review result from an earlier revision cannot authorize readiness for a later revision.

**Information shown**:

- The loop records the revision that its Codex evidence covers.
- A stale review is reported as requiring a current review rather than as a clean result.

**Actions available**:

- Request or await a current review.
- Continue to the normal CI and readiness gates only after current terminal evidence is available.

**Considerations**:

- A terminal review can be either a clean result or a result containing actionable feedback; both must be tied to the live revision before the loop can make a decision.

---

### Use Case 3: Operator reaches a configured review-cycle limit

**Actor**: Workflow operator
**Preconditions**: The reviewer loop has consumed its configured per-run or lifetime allowance while actionable review work remains or the required review evidence cannot be established.

**Steps**:

1. The loop detects that the applicable cycle limit has been reached.
2. The loop records an escalation outcome with the limit reason and remaining context.
3. Downstream readiness handling receives the escalation outcome.

**Postconditions**: The pull request is not classified as clean or ready for human review solely because the loop stopped.

**Information shown**:

- The escalation identifies whether the per-run or lifetime limit was reached.
- The operator can see that a human review or intervention is required.

**Actions available**:

- Review the recorded evidence, resolve the underlying condition, and begin a new authorized run when appropriate.

**Considerations**:

- Escalation is terminal for the current run and must not be converted into a successful readiness signal.

---

## Business Rules

- Only unresolved Codex review conversations with evidence applicable to the live pull-request revision may be counted as actionable blockers. A conversation is applicable only when its Codex review is submitted and its review commit SHA equals the live pull-request head SHA; `isOutdated: false`, a visible comment, or a re-anchored diff position alone does not establish live-revision applicability.
- Resolved Codex review conversations are excluded from fallback, existing-finding, and stale-finding blocker counts, even if their comments remain visible or re-anchored on the diff.
- A pull request with zero unresolved Codex review conversations must not receive a `needs_fixes` outcome solely from historical Codex comments.
- A terminal Codex verdict that reports actionable feedback can produce `needs_fixes` only when each actionable finding carries the same GitHub GraphQL review-thread node ID as an unresolved conversation applicable to the live revision. A review-level finding or comment without a review-thread node ID is incomplete evidence, not an actionable blocker.
- After a pull-request update, a clean readiness path requires a submitted terminal Codex verdict for the live revision; clean or finding evidence from an older revision is stale.
- A review-loop cycle-limit outcome is an explicit escalation for human review. It is never interchangeable with a clean, skipped, or readiness outcome.
- If the workflow cannot determine a conversation's resolution state, live-revision applicability, or review-thread node ID, it retries the bounded evidence query and then emits an explicit evidence-unavailable escalation; it must not claim a clean result or return `needs_fixes` from the indeterminate evidence.
- An unresolved conversation that is applicable to the live revision is sufficient current actionable evidence and returns `needs_fixes` even when a terminal verdict is stale or absent. A submitted terminal verdict for the live revision is required only to classify the no-current-blocker path as clean.

## Operational Visibility

- **Logs**: Reviewer-loop output records the applicable revision, blocker classification, and the reason for a wait, fix path, clean result, or escalation.
- **Notifications**: Existing pull-request summary reporting continues to make actionable findings and escalation outcomes visible to workflow operators.
- **Audit trail**: Regression coverage records a resolved Codex finding that remains visible on a later revision and verifies its non-blocking classification.

## Acceptance Criteria

- [ ] A resolved Codex review conversation is excluded from every existing-finding, stale-finding, and fallback blocker count.
- [ ] When all Codex review conversations are resolved, historical or re-anchored Codex comments alone cannot produce `needs_fixes`.
- [ ] After a pull-request update, the workflow requires a submitted terminal Codex verdict for the live revision before permitting a clean readiness path.
- [ ] A clean or finding verdict from an older revision is reported as stale and cannot authorize readiness for the live revision.
- [ ] Per-run and lifetime cycle-limit outcomes are recorded as explicit escalations and never as clean or ready outcomes.
- [ ] Automated regression coverage reproduces a resolved Codex finding that remains visible after a later revision and verifies the expected non-blocking terminal classification.
- [ ] The implementation assesses only the CodeRabbit integration tracked by #1578 for reuse of the resolved-conversation/current-revision invariant. It records `shared` only when CodeRabbit provides verified conversation resolution and revision correlation, or records `not_applicable` with the missing capability in the regression evidence; no other reviewer integration changes under this item.

## Out of Scope (MVP)

- Changing Codex GitHub App rate limits, usage limits, polling budgets, or external service availability behavior.
- Redesigning the broader reviewer-loop lifecycle or readiness labels beyond the classification and evidence guarantees in this spec.
- Retrofitting historical downstream pull requests; the change governs future loop evaluations.

## Brief Objective List

1. Exclude resolved Codex review threads from existing, stale, and fallback blocker counts.
2. Prevent historical Codex comments from producing `needs_fixes` when no Codex threads remain unresolved.
3. Require a submitted terminal Codex verdict for the live revision after a push.
4. Treat per-run and lifetime cycle-limit outcomes as terminal escalations, never clean readiness.
5. Add a regression case for a resolved Codex finding that remains visible on a later revision.
6. Reuse the resolved-thread/current-revision invariant with comparable reviewer handling where safe, without conflating rate-limit behavior.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Exclude resolved threads from blocker counts | Acceptance criteria 1-2; Business Rules 1-3 |
| Avoid `needs_fixes` from historical comments | Acceptance criterion 2; Use Case 1 |
| Require live-revision terminal evidence | Acceptance criteria 3-4; Use Case 2 |
| Escalate at cycle limits | Acceptance criterion 5; Use Case 3 |
| Add resolved-finding regression coverage | Acceptance criterion 6; Operational Visibility |
| Share the invariant without rate-limit coupling | Acceptance criterion 7; Out of Scope |

## Deferral Notes

- No brief objective is deferred. Changes to platform-specific rate limits and polling behavior are intentionally out of scope because they are not required to correct blocker classification.

## Complex Workflow Decision-Gate Matrix

The loop evaluates inputs in this order: cycle limits first; then whether the
resolution, revision, and review-thread identifiers can be established; then
whether an unresolved conversation applies to the live revision; then whether
each finding in a current terminal verdict is associated with that conversation.
A higher-precedence outcome cannot be overridden by a later input. An unresolved
conversation from an earlier revision is historical evidence, not an actionable
blocker for the live revision; without a current submitted terminal verdict, it
produces the same wait outcome as any other stale evidence. A current applicable
unresolved conversation is the exception: it is sufficient to route to fixes;
the submitted-terminal-verdict requirement applies only before a clean result.

| Gate input | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Per-run or lifetime cycle limit reached, regardless of conversation or verdict state | Explicit escalation | Stop the current run for human review; never label ready | Reviewer loop, PR summary, downstream readiness signals | Repeated retries reach `max_total_cycles_exceeded` |
| Resolution state, live-revision applicability, or review-thread node ID is unavailable or ambiguous | Evidence-unavailable escalation | Retry the bounded evidence query; if still unavailable, stop the current run for human review; do not claim clean or return `needs_fixes` | GitHub GraphQL adapter, reviewer loop, PR summary | The API omits a thread node ID for a review-level finding |
| Unresolved Codex conversation applies to the live revision, regardless of a clean, stale, or absent terminal verdict | Actionable blocker | Return `needs_fixes` and route to the fix loop | Reviewer-loop classification, summary output, regression tests | A current Codex finding remains unresolved while an earlier clean verdict is visible |
| No unresolved current conversation; current terminal verdict contains a finding that cannot be associated with one | Incomplete evidence | Wait for or reconcile current review evidence; do not claim clean or return `needs_fixes` | Codex review adapter, reviewer loop, readiness checks | A submitted finding remains after its associated conversation was resolved |
| No unresolved current conversation; submitted terminal clean verdict covers the live revision | Clean current evidence | Continue to readiness | Codex review adapter, reviewer loop, readiness checks | A current submitted clean review authorizes the Codex phase |
| No unresolved current conversation; current terminal clean verdict is not submitted | Incomplete evidence | Wait for or trigger a submitted current review; do not claim clean | Codex review adapter, reviewer loop, readiness checks | A draft review is visible but has not been submitted |
| Resolved or unresolved historic conversation; terminal verdict is absent or covers an earlier revision | Stale or incomplete evidence | Wait for or trigger a current review; do not claim clean | Codex review adapter, reviewer loop, readiness checks | A push occurs after the last Codex review |
