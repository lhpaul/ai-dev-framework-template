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
- If a current terminal verdict contains both a finding correlated to an applicable unresolved conversation and a finding that is uncorrelated or correlated only to a resolved conversation, the incomplete finding evidence takes precedence. The loop must escalate rather than selectively return `needs_fixes` for the correlated finding.
- After a pull-request update, a clean readiness path requires terminal Codex evidence for the live revision: either a submitted Codex review whose commit SHA equals the live head, or a Codex root pull-request comment that explicitly names that same head SHA. Clean or finding evidence from an older revision, and a root comment without that exact SHA, are stale or incomplete.
- A review-loop cycle-limit outcome is an explicit escalation for human review only when another review or fix cycle is required after the allowance is exhausted. A submitted current clean verdict received in the final permitted evaluation proceeds to readiness; escalation is never interchangeable with a clean, skipped, or readiness outcome.
- If the bounded evidence query fails or leaves a conversation's resolution state or live-revision applicability indeterminate after its retry, the workflow emits an explicit evidence-unavailable escalation; it must not claim a clean result or return `needs_fixes` from indeterminate evidence. When that query succeeds, a finding with no review-thread node ID or no matching applicable unresolved conversation instead follows the correlation-missing escalation.
- An unresolved conversation that is applicable to the live revision is sufficient current actionable evidence and returns `needs_fixes` even when terminal evidence is stale or absent. Terminal evidence for the live revision — either a submitted review with the live commit SHA or a Codex root pull-request comment explicitly naming that SHA — is required only to classify the no-current-blocker path as clean.

## Operational Visibility

- **Logs**: Reviewer-loop output records the applicable revision, blocker classification, and the reason for a wait, fix path, clean result, or escalation.
- **Notifications**: Existing pull-request summary reporting continues to make actionable findings and escalation outcomes visible to workflow operators.
- **Audit trail**: Regression coverage records a resolved Codex finding that remains visible on a later revision and verifies its non-blocking classification.

## Acceptance Criteria

- [ ] A resolved Codex review conversation is excluded from every existing-finding, stale-finding, and fallback blocker count.
- [ ] When all Codex review conversations are resolved, historical or re-anchored Codex comments alone cannot produce `needs_fixes`.
- [ ] After a pull-request update, the workflow requires terminal Codex evidence for the live revision before permitting a clean readiness path: a submitted review with that commit SHA or a Codex root pull-request comment explicitly naming it.
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
6. Reuse the resolved-thread/current-revision invariant only for an integration that exposes verified per-conversation resolution and review-head SHA correlation; otherwise record it as `not_applicable` with the missing capability, without conflating rate-limit behavior.

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

The loop evaluates current evidence before applying a cycle limit: it establishes
resolution, revision, and review-thread identifiers; determines whether every
finding in a current terminal verdict is associated with an unresolved current
conversation; and determines whether an unresolved conversation applies to the
live revision. A cycle limit escalates only when this evaluation requires another
review or fix cycle after the allowance is exhausted; a submitted clean verdict in
the final permitted evaluation proceeds to readiness. A higher-precedence outcome
cannot be overridden by a later input. In particular, incomplete terminal-finding evidence takes precedence
over an otherwise valid unresolved conversation: the loop cannot selectively
route only the correlated finding to fixes. An unresolved
conversation from an earlier revision is historical evidence, not an actionable
blocker for the live revision; without a current submitted terminal verdict, it
produces the same wait outcome as any other stale evidence. A current applicable
unresolved conversation is the exception: it is sufficient to route to fixes;
the submitted-terminal-verdict requirement applies only before a clean result.
`waiting_on_reviewer` means that the loop has requested or is awaiting a
submitted Codex review for the unchanged live head; it does not dispatch a
fixer. `escalate` is terminal for that run and does not apply `needs_fixes`.

| Gate input | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Per-run or lifetime allowance is exhausted and current evidence requires another review or fix cycle | Explicit escalation | Stop the current run for human review; never label ready | Reviewer loop, PR summary, downstream readiness signals | Repeated unresolved findings require a cycle after `max_total_cycles` is consumed; a clean verdict received in the final permitted evaluation instead continues to readiness |
| Bounded evidence query fails or leaves resolution state or live-revision applicability unavailable or ambiguous after its retry | `escalate` with reason `evidence_unavailable_codex_thread_state` | Stop the current run for human review; do not claim clean or return `needs_fixes` | GitHub GraphQL adapter, reviewer loop, PR summary | The API times out while loading the conversation state |
| Successful bounded evidence query; current terminal verdict contains a finding with no review-thread node ID, no matching applicable unresolved conversation, or only a resolved-conversation match, including when another finding maps to an applicable unresolved conversation | `escalate` with reason `codex_finding_thread_correlation_missing` | Stop the current run for human review; do not claim clean or return `needs_fixes` for only the correlated finding | Codex review adapter, reviewer loop, readiness checks | A submitted verdict has one unresolved-thread finding and one review-level finding, or a finding remains after its associated conversation was resolved |
| Unresolved Codex conversation applies to the live revision and all findings in any current terminal verdict correlate to applicable unresolved conversations | Actionable blocker | Return `needs_fixes` and route to the fix loop | Reviewer-loop classification, summary output, regression tests | A current Codex finding remains unresolved while an earlier clean verdict is visible |
| No unresolved current conversation; terminal clean evidence covers the live revision as either a submitted Codex review with the live commit SHA or a Codex root pull-request comment explicitly naming that SHA | Clean current evidence | Continue to readiness | Codex review adapter, reviewer loop, readiness checks | A current submitted clean review or SHA-pinned root comment authorizes the Codex phase |
| No unresolved current conversation; terminal clean evidence is a draft or unsubmitted review, or a root comment without the exact live head SHA | `waiting_on_reviewer` with reason `codex_current_verdict_unsubmitted` | Await or request terminal evidence for the unchanged head; do not claim clean | Codex review adapter, reviewer loop, readiness checks | A draft review is visible or a root comment omits the reviewed SHA |
| No Codex conversations, or only resolved or unresolved historic conversations; terminal verdict is absent or covers an earlier revision | `waiting_on_reviewer` with reason `codex_current_verdict_pending` | Request or await a submitted current review for the unchanged head; do not dispatch a fixer or claim clean | Codex review adapter, reviewer loop, readiness checks | A newly opened pull request has no Codex review yet, or a push occurs after the last Codex review |
