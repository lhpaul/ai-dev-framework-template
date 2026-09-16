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

- Review the recorded evidence and resolve the underlying condition. Begin a new run only after a human explicitly authorizes a new cycle allowance.

**Considerations**:

- Escalation is terminal for the current run and must not be converted into a successful readiness signal.

---

## Business Rules

- Only unresolved Codex review conversations with evidence applicable to the live pull-request revision may be counted as actionable blockers. A conversation is applicable only when its Codex review is current and not dismissed and its review revision equals the live pull-request revision; a merely re-anchored or still-visible comment does not establish live-revision applicability. Conversations attached to dismissed Codex reviews are inapplicable, even if their thread state remains unresolved. The implementation plan records the concrete provider fields and thread identifiers that express these concepts.
- Resolved Codex review conversations are excluded from fallback, existing-finding, and stale-finding blocker counts, even if their comments remain visible or re-anchored on the diff.
- A pull request with zero unresolved Codex review conversations must not receive a `needs_fixes` outcome solely from historical Codex comments.
- A terminal Codex verdict that reports actionable feedback can produce `needs_fixes` only when each actionable finding carries the same stable GitHub review-thread identifier as an unresolved conversation applicable to the live revision. A review-level finding or comment without a review-thread identifier is incomplete evidence, not an actionable blocker.
- If a current terminal verdict contains both a finding correlated to an applicable unresolved conversation and a finding that is uncorrelated or has no identifiable matching thread, the incomplete finding evidence takes precedence. The loop must escalate rather than selectively return `needs_fixes` for the correlated finding.
- If every actionable finding in the current terminal verdict has an identifiable matching Codex review conversation and all of those matching conversations are resolved for the live head, and no other applicable current-head Codex conversation remains unresolved, the finding evidence is fully cleared rather than correlation-missing. The workflow must request or await another current-head review so the reviewer can produce terminal clean evidence for the unchanged head. If any other applicable current-head Codex conversation remains unresolved, that conversation is still an actionable blocker.
- After a pull-request update, a clean readiness path requires terminal Codex evidence for the live revision: either a submitted Codex review whose full commit SHA equals the live head and whose body is classified clean, or a Codex root pull-request comment authored after the latest review trigger that names the live head and whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is classified clean. A marker token is a prefix of the live head only when the live head begins with that token at offset zero; a token that occurs elsewhere inside the live head (interior-substring match) or that contains the live head plus extra characters (superstring match) is not a prefix. A root comment with the same timestamp second as that trigger is fresh only when its comment ID orders after the trigger comment. When no live-head review trigger exists yet, the earliest marker-pinned clean root comment for that head is the terminal clean evidence for that head; if none exists, the trigger-less head follows the `codex_current_verdict_pending` wait path. Clean or finding evidence from an older revision, and a root comment without the required freshness boundary, exact reviewed-commit marker, and clean body, are stale or incomplete. A `Reviewed commit` marker that is well-formed but names an older revision is valid prior-revision evidence and follows the stale path (`codex_current_verdict_pending`), never the malformed-marker path. A marker is well-formed only when it contains exactly one hexadecimal commit token that resolves unambiguously to a single commit and functions as a standalone commit reference. Empty, non-hex, multiple-token, ambiguous, interior-substring, or superstring markers are syntactically unusable revision evidence and escalate with `codex_current_verdict_malformed_revision_marker` rather than authorizing readiness.
- When multiple terminal Codex evidence items cover the live head, the workflow first ignores dismissed Codex reviews and then evaluates only the newest non-dismissed terminal evidence timestamp. Older clean evidence for the same SHA cannot authorize readiness after newer current-head finding, malformed-marker, unrecognized, or incomplete-correlation evidence exists. When multiple current-head evidence items share the newest timestamp, the workflow aggregates them by precedence: malformed-marker escalation, unrecognized-verdict escalation, incomplete-correlation escalation, actionable blocker, cleared-findings wait (`codex_current_verdict_pending`), then clean. The malformed-marker tier contains only syntactically unusable markers; a well-formed marker that names an older revision is prior-revision evidence and never enters that tier. The cleared-findings wait tier covers a terminal finding verdict whose findings are all cleared because every matching conversation is resolved and no other applicable current-head conversation is unresolved; a tie between a clean terminal review and that cleared-findings verdict resolves to the wait tier, so the loop requests another current-head review instead of claiming clean. Syntactically-unusable-marker root comments are terminal malformed-marker evidence for their referenced live-head review attempt even when no live-head trigger is present; a later valid terminal evidence item for the same live head supersedes earlier malformed-marker evidence.
- A review-loop cycle-limit outcome is an explicit escalation for human review only when another review or fix cycle is required after the allowance is exhausted. A submitted current clean verdict received in the final permitted evaluation proceeds to readiness; escalation is never interchangeable with a clean, skipped, or readiness outcome. Cycle-allowance configuration keeps the documented contract: an omitted setting uses the documented default (10 per-run, 25 lifetime), and any value that cannot resolve to a valid positive count logs a warning and falls back to that documented default. This item does not change configuration-reader semantics, so no presence-versus-empty distinction is required.
- A current terminal verdict is classified clean only by reproducing an approved clean template: after whitespace normalization (collapsing whitespace runs to a single space and trimming the ends), the entire untruncated body must match one of the literal clean-response templates documented for the Codex GitHub integration, substituting only that template's bounded placeholder slots (the reviewed commit SHA and the flavor phrase). Literal equality against a placeholder-bearing template is not the test. A verdict is classified as reporting findings only when its body carries the blocking markers documented for that same Codex GitHub integration surface (the blocking pattern maintained by the Codex reviewer helper and described in its comments); this spec does not define a new marker vocabulary. A current terminal verdict that matches neither an approved clean template nor those documented blocking markers is unrecognized evidence, not clean evidence and not an actionable finding. It escalates with `codex_current_verdict_unrecognized`, takes precedence over otherwise applicable unresolved conversations, and never licenses a `waiting_on_reviewer` outcome for the unchanged head.
- If the bounded evidence query fails or leaves a conversation's resolution state or live-revision applicability indeterminate after its retry, the workflow emits an explicit evidence-unavailable escalation; it must not claim a clean result or return `needs_fixes` from indeterminate evidence. When that query succeeds, a finding with no review-thread node ID or with no identifiable matching conversation at all instead follows the correlation-missing escalation. A finding whose matching conversation is identifiable but resolved is not correlation-missing: it is cleared evidence under the cleared-findings rule above.
- These escalations are the complete fail-closed outcome set for the Codex phase: `evidence_unavailable_codex_thread_state`, `codex_current_verdict_malformed_revision_marker`, `codex_finding_thread_correlation_missing`, and `codex_current_verdict_unrecognized`. Each stops the current run for human review, and none may be converted into `needs_fixes`, `waiting_on_reviewer`, or clean readiness by the loop or its callers.
- An unresolved conversation that is applicable to the live revision is sufficient current actionable evidence and returns `needs_fixes` even when terminal evidence is stale or absent. Terminal clean evidence for the live revision — either a submitted review with the full live commit SHA and a clean body, or a fresh Codex root pull-request comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of that SHA and whose body is clean — is required only to classify the no-current-blocker path as clean.

## Statuses / Enum Values

This feature does not introduce new tracker statuses. The operator-visible reviewer-loop outcomes for the Codex phase are:

| Code value | Display label | Description |
| --- | --- | --- |
| `codex_current_verdict_pending` | Waiting on Codex review | No terminal Codex evidence for the live head yet, or only stale/cleared evidence; the loop requests or awaits a current-head review without dispatching a fixer |
| `codex_current_verdict_unsubmitted` | Waiting on submitted Codex verdict | Clean-looking or acknowledgement evidence exists for the live-head review attempt, but with no submitted review marker and no explicit reviewed SHA |
| `codex_current_verdict_malformed_revision_marker` | Malformed reviewed-commit marker | Root-comment `Reviewed commit` evidence is syntactically unusable: empty, non-hex, multiple-token, ambiguous, interior-substring, or superstring |
| `codex_current_verdict_unrecognized` | Unrecognized Codex verdict | The current terminal verdict matches neither an approved clean template nor the documented blocking markers |
| `codex_finding_thread_correlation_missing` | Codex finding thread correlation missing | A current terminal finding has no stable review-thread identifier or no identifiable matching conversation |
| `evidence_unavailable_codex_thread_state` | Codex thread state unavailable | The bounded evidence query failed or left resolution state or live-revision applicability indeterminate after its retry |

Escalation codes in this table are terminal for the current run and require human review; the two `waiting_on_reviewer` codes await or request terminal evidence for the unchanged head.

## Operational Visibility

- **Logs**: Reviewer-loop output records the applicable revision, blocker classification, and the reason for a wait, fix path, clean result, or escalation.
- **Notifications**: Existing pull-request summary reporting continues to make actionable findings and escalation outcomes visible to workflow operators.
- **Audit trail**: Regression coverage records a resolved Codex finding that remains visible on a later revision and verifies the `waiting_on_reviewer` classification with reason `codex_current_verdict_pending`.

## Acceptance Criteria

- [ ] A resolved Codex review conversation is excluded from every existing-finding, stale-finding, and fallback blocker count.
- [ ] When all Codex review conversations are resolved, historical or re-anchored Codex comments alone cannot produce `needs_fixes`.
- [ ] After a pull-request update, the workflow requires terminal clean Codex evidence for the live revision before permitting a clean readiness path: a submitted review with that full commit SHA and a clean body, or a fresh Codex root pull-request comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is clean.
- [ ] A clean or finding verdict from an older revision is reported as stale and cannot authorize readiness for the live revision.
- [ ] Per-run and lifetime cycle-limit outcomes are recorded as explicit escalations when another review or fix cycle is required after the allowance is exhausted, and never as clean or ready outcomes in that case. A submitted current clean verdict received in the final permitted evaluation instead proceeds to readiness. Omitting the settings keeps the documented 10/25 defaults, and an invalid configured value logs a warning and applies those same defaults.
- [ ] A current terminal Codex verdict that matches neither an approved clean template nor the documented blocking markers is recorded as `codex_current_verdict_unrecognized`, and a current terminal Codex finding with no stable review-thread identifier or no identifiable matching conversation is recorded as `codex_finding_thread_correlation_missing`; the loop stops for human review instead of waiting, returning `needs_fixes`, or claiming clean.
- [ ] When every actionable finding in the current terminal verdict is cleared because all of its matching conversations are resolved and no other applicable current-head conversation is unresolved, the loop records `waiting_on_reviewer` with reason `codex_current_verdict_pending` and requests or awaits another current-head review rather than dispatching a fixer or escalating correlation-missing.
- [ ] Every fail-closed Codex escalation — `evidence_unavailable_codex_thread_state`, `codex_current_verdict_malformed_revision_marker`, `codex_finding_thread_correlation_missing`, and `codex_current_verdict_unrecognized` — is recorded as a terminal human-review escalation and is never converted into `needs_fixes`, `waiting_on_reviewer`, or clean readiness.
- [ ] Automated regression coverage reproduces a resolved Codex finding that remains visible after a later revision and verifies `waiting_on_reviewer` with reason `codex_current_verdict_pending`.
- [ ] The implementation assesses only the comparable CodeRabbit integration already tracked for reuse of the resolved-conversation/current-revision invariant. It records `shared` only when CodeRabbit provides verified conversation resolution and revision correlation, or records `not_applicable` with the missing capability in the regression evidence; no other reviewer integration changes under this item.

## Out of Scope (MVP)

- Changing Codex GitHub App rate limits, usage limits, polling budgets, or external service availability behavior.
- Redesigning the broader reviewer-loop lifecycle or readiness labels beyond the classification and evidence guarantees in this spec.
- Retrofitting historical downstream pull requests; the change governs future loop evaluations.

## Brief Objective List

1. Exclude resolved Codex review threads from existing, stale, and fallback blocker counts.
2. Prevent historical Codex comments from producing `needs_fixes` when no Codex threads remain unresolved.
3. Require terminal clean Codex evidence for the live revision after a push: a submitted review with the full live commit SHA and a clean body, or a fresh Codex root comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is clean.
4. Treat per-run and lifetime cycle-limit outcomes as terminal escalations, never clean readiness.
5. Add a regression case for a resolved Codex finding that remains visible on a later revision.
6. Reuse the resolved-thread/current-revision invariant only for an integration that exposes verified per-conversation resolution and review-head SHA correlation; otherwise record it as `not_applicable` with the missing capability, without conflating rate-limit behavior.
7. Record the fail-closed Codex outcomes — unrecognized verdict and correlation-missing finding — as terminal human-review escalations, never converted into `needs_fixes`, waiting, or clean readiness.
8. Preserve the cleared-findings retrigger path: when every verdict finding is cleared and no other applicable conversation is unresolved, wait for a fresh current-head review instead of dispatching a fixer or escalating.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Exclude resolved threads from blocker counts | Acceptance criteria 1-2; Business Rules 1-3 |
| Avoid `needs_fixes` from historical comments | Acceptance criterion 2; Use Case 1 |
| Require live-revision terminal evidence | Acceptance criteria 3-4; Business Rule 7; Use Case 2 |
| Escalate at cycle limits | Acceptance criterion 5; Business Rule 9; Use Case 3 |
| Add resolved-finding regression coverage | Acceptance criterion 9; Operational Visibility |
| Share the invariant without rate-limit coupling | Acceptance criterion 10; Out of Scope |
| Fail-closed Codex escalations | Acceptance criteria 6, 8; Business Rules 10-12 |
| Cleared-findings retrigger path | Acceptance criterion 7; Business Rule 6; Use Case 1 |

## Deferral Notes

- No brief objective is deferred. Changes to platform-specific rate limits and polling behavior are intentionally out of scope because they are not required to correct blocker classification.

## Complex Workflow Decision-Gate Matrix

The loop evaluates current evidence before applying a cycle limit: it establishes
resolution, revision, and stable review-thread identifiers; determines whether every
finding in a current terminal verdict is associated with an unresolved current
conversation; and determines whether an unresolved conversation applies to the
live revision. If multiple non-dismissed current-head terminal evidence items
exist, the newest terminal-evidence timestamp is canonical; evidence tied at that
timestamp is aggregated by the matrix precedence below. A cycle limit escalates
only when this evaluation requires another review or fix cycle after the
allowance is exhausted; a submitted clean verdict in the final permitted
evaluation proceeds to readiness only when the canonical evidence set is clean.
Within the canonical newest timestamp, a higher-precedence outcome cannot be
overridden by another tied input. Later non-dismissed terminal evidence for the
same live head supersedes earlier current-head evidence before that precedence
ordering is applied. In particular,
incomplete terminal-finding evidence takes precedence
over an otherwise valid unresolved conversation: the loop cannot selectively
route only the correlated finding to fixes. Findings whose matching current-head
conversations are all resolved are different: they are cleared evidence and
request another terminal review instead of escalating as correlation-missing. An unresolved
conversation from an earlier revision is historical evidence, not an actionable
blocker for the live revision; without a current submitted terminal verdict, it
produces the same wait outcome as any other stale evidence. A current applicable
unresolved conversation is the exception: it is sufficient to route to fixes;
the submitted-terminal-verdict requirement applies only before a clean result.
An unrecognized current terminal verdict is neither clean evidence nor an
actionable finding; it escalates explicitly instead of forcing the loop to guess
between waiting and routing a fixer. This unrecognized-terminal-verdict outcome
takes precedence over otherwise applicable unresolved conversations. A verdict
that mixes already-cleared findings with an independent unresolved applicable
conversation is not an incomplete-correlation case: the cleared findings are
excluded from the correlation check, and the remaining applicable unresolved
conversation is the actionable blocker. Incomplete-correlation escalation applies
only to findings that correlate to no conversation at all while their matching
conversations are unresolved or unknown.
For root pull-request comments, the `Reviewed commit` marker proves revision
scope only when it contains exactly one hexadecimal commit token that resolves
unambiguously to a single commit and is an unambiguous prefix of the live head.
A root comment also must be authored after
the latest review trigger that names the live head to authorize readiness. If
GitHub records the trigger and root comment in the same timestamp second, the
root comment is fresh only when its comment ID orders after the trigger comment.
When no such trigger exists, the earliest marker-pinned clean root comment for that
head is canonical only when its marker is valid; when no valid marker-pinned comment
exists for that head, the head follows the `codex_current_verdict_pending` wait path.
Marker evidence splits into
two disjoint cases. A **well-formed marker for a prior revision** — exactly one
unambiguous hexadecimal commit token that resolves to a different commit than the
live head — is valid but stale revision evidence: it follows the stale/pending
path (`codex_current_verdict_pending`) and is never escalated as malformed. A
**malformed marker** — empty, non-hex, multiple-token, ambiguous, interior-substring,
or superstring — is syntactically unusable revision evidence: it escalates
with `codex_current_verdict_malformed_revision_marker`, including when no
live-head review trigger exists. Even with a valid and fresh marker, the comment
body must still be classified clean, and a marker-pinned root comment with
recognizable unthreaded findings follows the incomplete-finding escalation path.
`waiting_on_reviewer` means that the loop has requested or is awaiting a
submitted Codex review for the unchanged live head; it does not dispatch a
fixer. `escalate` is terminal for that run and does not apply `needs_fixes`.
Reason-code names in this spec are externally visible workflow outcomes, not a
mandate for helper or parser structure.

| Gate input | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Per-run or lifetime allowance is exhausted and current evidence requires another review or fix cycle | Explicit escalation | Stop the current run for human review; never label ready | Protocol 93, Protocol 91 readiness checks, reviewer loop, PR summary | Repeated unresolved findings require a cycle after the lifetime allowance is consumed; a clean verdict received in the final permitted evaluation instead continues to readiness |
| Per-run or lifetime allowance is omitted from configuration | Use the documented defaults (10 per-run, 25 lifetime) without escalation | Apply the resolved default allowance and continue the normal evaluation | Reviewer loop, `.ai-dev-workflow.yaml` contract, `pr-review-loop.sh --help` | The shipped template leaves `review.max_cycles` and `review.max_total_cycles` commented out, so the loop runs with 10/25 |
| Per-run or lifetime allowance resolves to an invalid count | Log a warning and apply the documented defaults (10 per-run, 25 lifetime) | Continue the normal evaluation with the default allowance; no configuration-reader semantics change | Reviewer loop, `.ai-dev-workflow.yaml` contract, `pr-review-loop.sh --help` | An operator sets a non-numeric value and the loop warns and runs with 10/25 |
| Newer non-dismissed terminal Codex evidence exists for the live head after an older clean evidence item for the same head | Evaluate only the newest terminal-evidence timestamp, aggregating ties by the matrix precedence below | Ignore superseded same-head clean evidence; do not authorize readiness from an older clean verdict | Protocol 93 verdict classification, `codex-github.md`, reviewer loop | A clean submitted review is followed by a root comment for the same SHA with actionable findings |
| Bounded evidence query fails or leaves resolution state or live-revision applicability unavailable or ambiguous after its retry | `escalate` with reason `evidence_unavailable_codex_thread_state` | Stop the current run for human review; do not claim clean or return `needs_fixes` | Protocol 93, `codex-github.md`, GitHub GraphQL adapter, reviewer loop, PR summary | The API times out while loading the conversation state |
| Root pull-request comment evidence has a `Reviewed commit` marker that is syntactically unusable: empty, non-hex, contains multiple commit tokens, ambiguous between candidates, or matches the live head only at an interior substring or as a superstring; no newer valid terminal evidence covers the same live head | `escalate` with reason `codex_current_verdict_malformed_revision_marker` | Stop the current run for human review; do not wait, claim clean, or infer an older-revision verdict from malformed marker evidence | Protocol 93 verdict classification, `codex-github.md`, reviewer loop, PR summary | A root comment says `Reviewed commit: abcdef1` when another candidate shares that prefix, or embeds the live OID inside a longer token |
| Successful bounded evidence query; current terminal verdict contains a finding with no stable review-thread identifier or no identifiable matching conversation for the same reviewer evidence | `escalate` with reason `codex_finding_thread_correlation_missing` | Stop the current run for human review; do not claim clean or return `needs_fixes` for only other correlated findings | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | A submitted verdict has one unresolved-thread finding and one review-level finding with no thread identity |
| Successful bounded evidence query; every actionable finding in the current terminal verdict has an identifiable matching Codex review conversation for the live head, every matching conversation is resolved, and no other applicable current-head Codex conversation remains unresolved | `waiting_on_reviewer` with reason `codex_current_verdict_pending` | Request or await a fresh current-head Codex review through the cleared-findings retrigger path; do not dispatch a fixer, claim clean, or escalate correlation-missing | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | An operator resolves all Codex findings as false positives without changing HEAD and no other current-head Codex thread is open, so the next action is to obtain the clean verdict for that same head |
| Current terminal verdict covers the live revision but matches neither an approved clean template nor the documented blocking markers | `escalate` with reason `codex_current_verdict_unrecognized` | Stop the current run for human review; do not synthesize `needs_fixes`, wait, or clean from an unparseable terminal verdict | Protocol 93 verdict classification, `codex-github.md`, reviewer loop, PR summary | A submitted Codex review for the live head has the standard footer but no approved-template reproduction and no blocking marker |
| Unresolved Codex conversation applies to the live revision; no current terminal verdict is unrecognized; and, when a current terminal verdict contains recognizable findings, every finding either correlates to an applicable unresolved conversation or is already cleared because all of its matching conversations are resolved | Actionable blocker | Return `needs_fixes` and route to the fix loop, attributing the blocker to the remaining applicable unresolved conversation | Protocol 93, reviewer-loop classification, summary output, regression tests | A current Codex finding remains unresolved while an earlier clean verdict is visible, or the verdict's own finding thread is resolved while a separate applicable current-head Codex thread remains open |
| No unresolved current conversation; terminal clean evidence covers the live revision as either a submitted Codex review with the full live commit SHA and a clean body or a fresh Codex root pull-request comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is clean | Clean current evidence | Continue to readiness | Protocol 93, `codex-github.md`, Protocol 91 readiness checks, reviewer loop | A current submitted clean review or fresh marker-pinned clean root comment authorizes the Codex phase |
| No unresolved current conversation; otherwise clean-looking or acknowledgement evidence exists for the live-head review attempt but has no submitted review marker and no explicit reviewed SHA | `waiting_on_reviewer` with reason `codex_current_verdict_unsubmitted` | Await or request terminal evidence for the unchanged head; do not claim clean | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | A draft review is visible, or a root clean comment posted after the latest live-head trigger omits any reviewed SHA |
| No Codex conversations, or only resolved, dismissed, or historic conversations; no candidate Codex review/comment evidence exists for the live-head review attempt, or the newest valid submitted or SHA-marked terminal evidence covers an earlier revision, including a well-formed `Reviewed commit` marker that names a prior commit | `waiting_on_reviewer` with reason `codex_current_verdict_pending` | Request or await a submitted current review for the unchanged head; do not dispatch a fixer, claim clean, or escalate malformed-marker | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | A newly opened pull request has no Codex review yet, a push occurs after the last valid Codex review, or the newest valid root clean comment names an older SHA |
