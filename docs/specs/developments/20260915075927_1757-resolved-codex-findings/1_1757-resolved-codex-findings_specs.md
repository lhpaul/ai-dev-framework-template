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

- Only unresolved Codex review conversations with evidence applicable to the live pull-request revision may be counted as actionable blockers, with one exception: a current-head submitted Codex review whose GitHub review state is `CHANGES_REQUESTED` is itself an actionable blocker attributed to the review state, even when it carries no finding that maps to an applicable unresolved conversation, because GitHub's structured request-for-changes must fail closed rather than be approved. A conversation is applicable only when its Codex review is current and not dismissed and its review revision equals the live pull-request revision; a merely re-anchored or still-visible comment does not establish live-revision applicability. Conversations attached to dismissed Codex reviews are inapplicable, even if their thread state remains unresolved. The implementation plan records the concrete provider fields and thread identifiers that express these concepts.
- Resolved Codex review conversations are excluded from fallback, existing-finding, and stale-finding blocker counts, even if their comments remain visible or re-anchored on the diff.
- A pull request with zero unresolved Codex review conversations must not receive a `needs_fixes` outcome solely from historical Codex comments.
- A terminal Codex verdict that reports actionable feedback can produce `needs_fixes` only when each actionable finding carries the same stable GitHub review-thread identifier as an unresolved conversation applicable to the live revision. A review-level finding or comment without a review-thread identifier is incomplete evidence, not an actionable blocker.
- If a current terminal verdict contains both a finding correlated to an applicable unresolved conversation and a finding that is uncorrelated or has no identifiable matching thread, the incomplete finding evidence takes precedence. The loop must escalate rather than selectively return `needs_fixes` for the correlated finding.
- If every actionable finding in the current terminal verdict has an identifiable matching Codex review conversation and all of those matching conversations are resolved for the live head, and no other applicable current-head Codex conversation remains unresolved, the finding evidence is fully cleared rather than correlation-missing. The workflow must request or await another current-head review so the reviewer can produce terminal clean evidence for the unchanged head. If any other applicable current-head Codex conversation remains unresolved, that conversation is still an actionable blocker.
- After a pull-request update, a clean readiness path requires terminal Codex evidence for the live revision: either a submitted Codex review whose full commit SHA equals the live head, whose GitHub review state is not `CHANGES_REQUESTED`, and whose body is classified clean, or a Codex root pull-request comment authored after the latest review trigger that names the live head and whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is classified clean. A marker token is a prefix of the live head only when the live head begins with that token at offset zero; a token that occurs elsewhere inside the live head (interior-substring match) or that contains the live head plus extra characters (superstring match) is not a prefix. A root comment with the same timestamp second as that trigger is fresh only when its comment ID orders after the trigger comment. When no live-head review trigger exists yet, the newest marker-pinned clean root comment for that head is the terminal clean evidence for that head only when no newer non-dismissed terminal evidence for the same head exists; repeated clean comments for the head collapse to that single newest one, and two such comments sharing a timestamp resolve to the one whose comment ID orders later. A newer current-head finding, malformed-marker, unrecognized, or incomplete-correlation evidence supersedes it under the newest-evidence rule. If no such marker-pinned clean comment exists for that trigger-less head, the head follows the acknowledgement or pending wait path according to the acknowledgement-precedence rule above: a present acknowledgement signal yields `codex-github-reaction-without-review`, and otherwise — whether the head has only stale or prior-revision review/comment evidence or no such evidence at all — it yields `codex-github-review-pending`. Clean or finding evidence from an older revision, and a root comment without the required freshness boundary, exact reviewed-commit marker, and clean body, are stale or incomplete. A `Reviewed commit` marker that is well-formed but names an older revision is valid prior-revision evidence and follows the stale path (`codex-github-review-pending`), never the malformed-marker path. A marker is well-formed only when all three hold: it contains exactly one hexadecimal commit token, that token resolves unambiguously to a single commit, and that token functions as a standalone commit reference — meaning it is neither an interior substring of the live head nor a superstring containing the live head. Standalone-reference status is part of well-formedness, so a token that resolves to a different commit while occurring inside the live head at a nonzero offset is not a well-formed prior-revision marker. Empty, non-hex, multiple-token, ambiguous, interior-substring, or superstring markers are syntactically unusable revision evidence and escalate with `codex_current_verdict_malformed_revision_marker` rather than authorizing readiness.
- When multiple terminal Codex evidence items cover the live head, the workflow first ignores dismissed Codex reviews and then evaluates only the newest non-dismissed terminal evidence timestamp. Older clean evidence for the same SHA cannot authorize readiness after newer current-head finding, malformed-marker, unrecognized, or incomplete-correlation evidence exists. When multiple current-head evidence items share the newest timestamp, the workflow aggregates them by precedence: malformed-marker escalation, unrecognized-verdict escalation, incomplete-correlation escalation, evidence-unavailable escalation, actionable blocker, availability, cleared-findings wait (`codex-github-review-pending`), then clean. The malformed-marker tier contains only syntactically unusable markers; a well-formed marker that names an older revision is prior-revision evidence and never enters that tier. Evidence that does not cover the live head never competes in the global newest-evidence selection: a live-head clean verdict stays authoritative when later evidence covers only an earlier revision, because the readiness question is decided among live-head-covering items alone and the stale path applies only when no live-head-covering terminal evidence exists. This timestamp selection governs terminal verdict evidence only: an applicable unresolved Codex conversation for the live head remains an actionable blocker regardless of which terminal evidence item is newest, so a later availability response or clean verdict does not erase it. The cleared-findings wait tier covers a terminal finding verdict whose findings are all cleared because every matching conversation is resolved and no other applicable current-head conversation is unresolved; it never covers a `CHANGES_REQUESTED` submitted review, which stays in the actionable-blocker tier above. A tie between a clean terminal review and that cleared-findings verdict resolves to the wait tier, so the loop requests another current-head review instead of claiming clean. Syntactically-unusable-marker root comments are terminal malformed-marker evidence for their referenced live-head review attempt even when no live-head trigger is present; any newer non-dismissed terminal evidence for the same live head — of any tier, not only valid evidence — supersedes earlier malformed-marker evidence, and items sharing the newest timestamp aggregate by the tier order above.
- Every Codex root comment belongs to exactly one head's evidence window, because such a comment is not inherently revision-bound. A comment's window is the live head that was current when the comment was authored: after any review trigger for that head, or — for a trigger-less head — after the previous head's last review trigger or the pull request's creation, whichever is later, and before any later head becomes current. A root comment authored while an earlier head was current is stale-head evidence: it never escalates, never authorizes readiness for, and never waits on a later head. When the window boundary cannot be established from the available evidence — an unavailable or ambiguous head-and-trigger chronology for the comment — the attribution is indeterminate and the head escalates with `evidence_unavailable_codex_thread_state` rather than guessing whether the malformed comment belongs to the live head. A syntactically-unusable-marker root comment therefore escalates the current head only when it falls inside that head's window; a malformed comment from an earlier head is ignored for the live head rather than escalated against it. When the newest non-dismissed terminal evidence for the live head's window is a syntactically-unusable-marker comment, the head escalates with `codex_current_verdict_malformed_revision_marker` whether or not a trigger exists for it.
- A review-loop cycle-limit outcome is an explicit escalation for human review only when another review or fix cycle is required after the allowance is exhausted. Canonical terminal clean evidence — whether a submitted current clean verdict or a fresh marker-pinned clean root comment for the live head — received in the final permitted evaluation proceeds to readiness; escalation is never interchangeable with a clean, skipped, or readiness outcome. Cycle allowances resolve independently: each of the per-run and lifetime settings either uses its explicitly configured value or, when omitted or invalid, its documented default (10 per-run, 25 lifetime), with a warning logged for an invalid value. This item does not change configuration-reader semantics, so no presence-versus-empty distinction is required. The cycle-limit escalation takes precedence over the cleared-findings retrigger path: when the allowance is exhausted and the evaluation would require another review cycle — including a cleared-findings retrigger — the loop escalates rather than emitting `waiting_on_reviewer`.
- A root pull-request comment that carries a well-formed `Reviewed commit` marker naming the live head but fails the freshness boundary — authored before the latest live-head trigger, or same-second with a comment ID that does not order after the trigger — is neither acknowledgement evidence nor terminal clean evidence. It is stale evidence for the live head and follows the `codex-github-review-pending` wait path.
- A current terminal verdict is classified clean only by reproducing an approved clean template: a submitted Codex review must additionally carry a non-blocking GitHub review state — a review GitHub marks `CHANGES_REQUESTED` is never clean evidence regardless of body wording, matching the adapter's structured-state short-circuit — and after whitespace normalization (collapsing whitespace runs to a single space and trimming the ends), the entire untruncated body must match one of the literal clean-response templates documented for the Codex GitHub integration, substituting only that template's bounded placeholder slots (the reviewed commit SHA and the flavor phrase). Literal equality against a placeholder-bearing template is not the test. A verdict is classified as reporting findings only when its body carries the blocking markers documented for that same Codex GitHub integration surface (the blocking pattern maintained by the Codex reviewer helper and described in its comments); this spec does not define a new marker vocabulary. A submitted Codex review whose GitHub review state is `CHANGES_REQUESTED` is always finding evidence — an actionable blocker — even when its body would otherwise reproduce a clean template, because GitHub's structured request-for-changes must not be approved from body wording alone; it is never clean and never unrecognized. This structured-state blocker remains subject to the fail-closed correlation rule: when such a review also carries a finding with no stable review-thread identifier or no identifiable matching conversation, the correlation-missing escalation takes precedence. A current terminal verdict that matches neither an approved clean template nor those documented blocking markers is unrecognized evidence, not clean evidence and not an actionable finding — except for a response the shipped adapter already recognizes as an availability outcome (a genuine Codex usage-limit notice, an account-not-connected refusal, or an environment-setup response), and except for a submitted review whose GitHub review state is `CHANGES_REQUESTED`, which is always an actionable blocker by structured state. Recognized availability responses keep their existing shipped handling and reason codes; they are never reclassified as unrecognized and never become a terminal human escalation through this rule. Unrecognized evidence escalates with `codex_current_verdict_unrecognized`, takes precedence over otherwise applicable unresolved conversations, and never licenses a `waiting_on_reviewer` outcome for the unchanged head.
- If the bounded evidence query fails or leaves a conversation's resolution state or live-revision applicability indeterminate after its retry, the workflow emits an explicit evidence-unavailable escalation; it must not claim a clean result or return `needs_fixes` from indeterminate evidence. When that query succeeds, a finding with no review-thread node ID or with no identifiable matching conversation at all instead follows the correlation-missing escalation. A finding whose matching conversation is identifiable but resolved is not correlation-missing: it is cleared evidence under the cleared-findings rule above, except when the review itself carries GitHub review state `CHANGES_REQUESTED`, which remains an actionable blocker attributed to the review state.
- These escalations are the complete fail-closed outcome set for the Codex phase: `evidence_unavailable_codex_thread_state`, `codex_current_verdict_malformed_revision_marker`, `codex_finding_thread_correlation_missing`, and `codex_current_verdict_unrecognized`. Each stops the current run for human review, and none may be converted into `needs_fixes`, `waiting_on_reviewer`, or clean readiness by the loop or its callers. A recognized availability response and a `CHANGES_REQUESTED` submitted review are not in this set: the former keeps its shipped availability handling and the latter returns `needs_fixes` as an actionable blocker.
- Acknowledgement-only evidence for the live-head review attempt — a thumbs-up reaction, a draft review, or a clean-looking root comment that omits any explicit reviewed revision — is not terminal evidence. When no unresolved current conversation exists and no terminal evidence covers the live revision, the loop records `waiting_on_reviewer` with reason `codex-github-reaction-without-review` and awaits or requests terminal evidence for the unchanged head; it does not claim clean and does not dispatch a fixer. This reason takes precedence over `codex-github-review-pending` whenever an acknowledgement signal is present; the pending reason applies when no acknowledgement signal exists for the live-head attempt, including when the only review or root-comment evidence for that head is stale, freshness-failing, prior-revision, or otherwise non-terminal.
- A root comment that carries a `Reviewed commit` field with no value is an empty marker, not an omitted one: it follows the malformed-marker escalation. Only a root comment that never carries the field at all is treated as acknowledgement evidence without an explicit reviewed revision.
- An unresolved conversation that is applicable to the live revision is sufficient current actionable evidence and returns `needs_fixes` even when terminal evidence is stale or absent. Terminal clean evidence for the live revision — either a submitted review with the full live commit SHA, a non-blocking review state, and a clean body, or a fresh Codex root pull-request comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of that SHA and whose body is clean — is required only to classify the no-current-blocker path as clean.

## Statuses / Enum Values

This feature does not introduce new tracker statuses. The operator-visible reviewer-loop outcomes for the Codex phase are:

| Code value | Display label | Description |
| --- | --- | --- |
| `codex-github-review-pending` | Waiting on Codex review | Shipped pending code, retained unchanged. No terminal Codex evidence for the live head yet, or only stale/cleared evidence; the loop requests or awaits a current-head review without dispatching a fixer |
| `codex-github-reaction-without-review` | Waiting on submitted Codex verdict | Shipped acknowledgement-only code, retained unchanged. Clean-looking or acknowledgement evidence exists for the live-head review attempt, but with no submitted review marker and no explicit reviewed revision |
| `codex_current_verdict_malformed_revision_marker` | Malformed reviewed-commit marker | New code. Root-comment `Reviewed commit` evidence is syntactically unusable: empty, non-hex, multiple-token, ambiguous, interior-substring, or superstring |
| `codex_current_verdict_unrecognized` | Unrecognized Codex verdict | New code. The current terminal verdict reproduces neither an approved clean template nor the documented blocking markers, is not a response the shipped adapter recognizes as an availability outcome, and is not a `CHANGES_REQUESTED` submitted review |
| `codex_finding_thread_correlation_missing` | Codex finding thread correlation missing | New code. A current terminal finding has no stable review-thread identifier or no identifiable matching conversation |
| `evidence_unavailable_codex_thread_state` | Codex thread state unavailable | New code. The bounded evidence query failed or left resolution state or live-revision applicability indeterminate after its retry |

The two waiting codes are the shipped reason codes and keep their existing names and tests; this item adds no parallel wait vocabulary. The escalation codes are newly introduced and are terminal for the current run, requiring human review.

**Valid transitions**: none. Each of these outcomes is decided once per review-loop evaluation of the current head and is not itself a state machine input; a later evaluation for a superseding head re-evaluates from scratch, and a terminal escalation is not transitioned into a waiting, fix, or clean outcome within the same run.

## Operational Visibility

- **Logs**: Reviewer-loop output records the applicable revision, blocker classification, and the reason for a wait, fix path, clean result, or escalation.
- **Notifications**: Existing pull-request summary reporting continues to make actionable findings and escalation outcomes visible to workflow operators.
- **Audit trail**: Regression coverage records a resolved Codex finding that remains visible on a later revision and verifies the `waiting_on_reviewer` classification with reason `codex-github-review-pending`.

## Acceptance Criteria

- [ ] A resolved Codex review conversation is excluded from every existing-finding, stale-finding, and fallback blocker count, except that a current-head submitted review whose GitHub review state is `CHANGES_REQUESTED` remains an actionable blocker attributed to the review state even when every conversation is resolved.
- [ ] When all Codex review conversations are resolved, historical or re-anchored Codex comments alone cannot produce `needs_fixes`; a current-head `CHANGES_REQUESTED` review state is not a comment and still blocks.
- [ ] After a pull-request update, the workflow requires terminal clean Codex evidence for the live revision before permitting a clean readiness path: a submitted review with that full commit SHA, a non-blocking GitHub review state, and a clean body, or a fresh Codex root pull-request comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is clean; a review GitHub marks `CHANGES_REQUESTED` is never clean evidence.
- [ ] A clean or finding verdict from an older revision is reported as stale and cannot authorize readiness for the live revision.
- [ ] Per-run and lifetime cycle-limit outcomes are recorded as explicit escalations when another review or fix cycle is required after the allowance is exhausted, and never as clean or ready outcomes in that case; this escalation takes precedence over the cleared-findings retrigger path. Canonical terminal clean evidence — a submitted current clean verdict or a fresh marker-pinned clean root comment for the live head — received in the final permitted evaluation instead proceeds to readiness, even though a further cycle would exceed the allowance; an exhausted allowance with any remaining actionable finding still escalates.
- [ ] Per-run and lifetime allowances resolve independently: an allowance that is omitted or carries an invalid configured value falls back to its own documented default (10 per-run, 25 lifetime) while the other allowance keeps its explicitly configured value, and an invalid value logs a warning.
- [ ] A current terminal Codex verdict that matches neither an approved clean template nor the documented blocking markers, is not a response the shipped adapter recognizes as an availability outcome, and is not a `CHANGES_REQUESTED` submitted review is recorded as `codex_current_verdict_unrecognized` and the loop stops for human review. A recognized availability response keeps its shipped availability handling instead. A `CHANGES_REQUESTED` submitted review is recorded as an actionable blocker and returns `needs_fixes` instead. A current terminal Codex finding with no stable review-thread identifier or no identifiable matching conversation is recorded as `codex_finding_thread_correlation_missing` and the loop stops for human review. None of these may be converted into a wait or a clean outcome.
- [ ] When every actionable finding in the current terminal verdict is cleared because all of its matching conversations are resolved and no other applicable current-head conversation is unresolved, the loop records `waiting_on_reviewer` with reason `codex-github-review-pending` and requests or awaits another current-head review rather than dispatching a fixer or escalating correlation-missing; a `CHANGES_REQUESTED` submitted review is never treated as cleared this way and stays an actionable blocker.
- [ ] Every fail-closed Codex escalation — `evidence_unavailable_codex_thread_state`, `codex_current_verdict_malformed_revision_marker`, `codex_finding_thread_correlation_missing`, and `codex_current_verdict_unrecognized` — is recorded as a terminal human-review escalation and is never converted into `needs_fixes`, `waiting_on_reviewer`, or clean readiness.
- [ ] When no unresolved current conversation exists and the live-head review attempt shows only acknowledgement evidence — a reaction, a draft review, or a clean-looking root comment without a reviewed revision field — the loop records `waiting_on_reviewer` with reason `codex-github-reaction-without-review` and awaits terminal evidence instead of claiming clean; this reason takes precedence over `codex-github-review-pending` whenever an acknowledgement signal exists.
- [ ] A root comment carrying a `Reviewed commit` field with no value escalates as `codex_current_verdict_malformed_revision_marker`, while a root comment that never carries the field is acknowledgement evidence for the wait path.
- [ ] A root comment whose well-formed `Reviewed commit` marker names the live head but misses the freshness boundary is neither acknowledgement nor clean evidence; the loop records `waiting_on_reviewer` with reason `codex-github-review-pending` instead of escalating malformed-marker.
- [ ] A trigger-less live head that has a marker-pinned clean root comment is clean only when no newer non-dismissed terminal evidence covers that same head; newer finding, malformed-marker, unrecognized, or incomplete-correlation evidence supersedes it, and repeated clean comments for the same head collapse to the newest one (later comment ID on a timestamp tie).
- [ ] A syntactically-unusable-marker root comment escalates the live head with `codex_current_verdict_malformed_revision_marker` only when it falls inside that head's evidence window; a malformed comment authored while an earlier head was current is stale-head evidence that never escalates, waits on, or authorizes readiness for a later head, and an attribution that cannot be established from the available head-and-trigger chronology escalates with `evidence_unavailable_codex_thread_state` instead of guessing.
- [ ] Automated regression coverage reproduces a resolved Codex finding that remains visible after a later revision and verifies `waiting_on_reviewer` with reason `codex-github-review-pending`.
- [ ] The implementation assesses only the comparable CodeRabbit integration already tracked for reuse of the resolved-conversation/current-revision invariant. It records `shared` only when CodeRabbit provides verified conversation resolution and revision correlation, or records `not_applicable` with the missing capability in the regression evidence; no other reviewer integration changes under this item.

## Out of Scope (MVP)

- Changing Codex GitHub App rate limits, usage limits, polling budgets, or external service availability behavior.
- Redesigning the broader reviewer-loop lifecycle or readiness labels beyond the classification and evidence guarantees in this spec.
- Retrofitting historical downstream pull requests; the change governs future loop evaluations.

## Brief Objective List

1. Exclude resolved Codex review threads from existing, stale, and fallback blocker counts.
2. Prevent historical Codex comments from producing `needs_fixes` when no Codex threads remain unresolved.
3. Require terminal clean Codex evidence for the live revision after a push: a submitted review with the full live commit SHA, a non-blocking review state, and a clean body, or a fresh Codex root comment whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is clean.
4. Treat per-run and lifetime cycle-limit outcomes as terminal escalations when another review or fix cycle is still required after the allowance is exhausted, never as clean readiness; canonical terminal clean evidence — a submitted current clean verdict or a fresh marker-pinned clean root comment for the live head — received in the final permitted evaluation instead proceeds to readiness.
5. Add a regression case for a resolved Codex finding that remains visible on a later revision.
6. Reuse the resolved-thread/current-revision invariant only for an integration that exposes verified per-conversation resolution and review-head SHA correlation; otherwise record it as `not_applicable` with the missing capability, without conflating rate-limit behavior.
7. Record the fail-closed Codex outcomes — unrecognized verdict and correlation-missing finding — as terminal human-review escalations, never converted into `needs_fixes`, waiting, or clean readiness.
8. Preserve the cleared-findings retrigger path: when every verdict finding is cleared and no other applicable conversation is unresolved, wait for a fresh current-head review instead of dispatching a fixer or escalating.
9. Treat acknowledgement-only evidence and trigger-less clean evidence conservatively: an acknowledgement signal waits with `codex-github-reaction-without-review` in preference to `codex-github-review-pending`, an empty reviewed-commit field escalates as malformed, and a trigger-less clean comment is superseded by newer non-dismissed terminal evidence for the same head.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Exclude resolved threads from blocker counts | Acceptance criteria 1-2; Business Rules 1-4 |
| Avoid `needs_fixes` from historical comments | Acceptance criterion 2; Business Rule 3; Use Case 1 |
| Require live-revision terminal evidence | Acceptance criteria 3-4; Business Rules 7-8, 12; Use Case 2 |
| Escalate at cycle limits | Acceptance criteria 5-6; Business Rule 10; Use Case 3 |
| Add resolved-finding regression coverage | Acceptance criterion 15; Operational Visibility |
| Share the invariant without rate-limit coupling | Acceptance criterion 16; Out of Scope |
| Fail-closed Codex escalations | Acceptance criteria 7, 9, 14; Business Rules 5, 13-14, 16 |
| Cleared-findings retrigger path | Acceptance criterion 8; Business Rule 6; Use Case 1 |
| Conservative acknowledgement and trigger-less evidence | Acceptance criteria 10-13; Business Rules 8-9, 11, 15, 17 |

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
allowance is exhausted; canonical terminal clean evidence in the final permitted
evaluation proceeds to readiness only when the canonical evidence set is clean.
Within the canonical newest timestamp, a higher-precedence outcome cannot be
overridden by another tied input. Later non-dismissed terminal evidence for the
same live head supersedes earlier current-head evidence before that precedence
ordering is applied. The escalation tiers themselves are ordered: malformed-marker
first, then unrecognized-verdict, then incomplete-correlation, then
evidence-unavailable; when two escalation-tier items tie, the earliest tier in that
order supplies the recorded reason. Below those escalation tiers, an actionable
blocker outranks a recognized availability response, which in turn outranks the
cleared-findings wait and clean; an availability response never outranks an
escalation or an actionable blocker. The decision-gate matrix below lists rows in
presentational order only; its row order defines no precedence, and the tier order
stated here governs every escalation tie. In particular,
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
takes precedence over otherwise applicable unresolved conversations, and so do the
malformed-marker and evidence-unavailable escalations: when a live-head review
attempt carries syntactically unusable marker evidence or its thread state cannot
be established, the loop escalates for human review even if an applicable
unresolved conversation is also present. The actionable-blocker and cleared-wait
outcomes apply only once no escalation tier matches the current head. A verdict
that mixes already-cleared findings with an independent unresolved applicable
conversation is not an incomplete-correlation case: the cleared findings are
excluded from the correlation check, and the remaining applicable unresolved
conversation is the actionable blocker. Incomplete-correlation escalation applies
only to findings that have no identifiable matching conversation at all; a finding
whose matching conversation is identifiable but unresolved is an actionable
blocker, and an indeterminate conversation state is evidence-unavailable rather
than correlation-missing.
For root pull-request comments, the `Reviewed commit` marker proves revision
scope only when it contains exactly one hexadecimal commit token that resolves
unambiguously to a single commit and is an unambiguous prefix of the live head.
A root comment also must be authored after
the latest review trigger that names the live head to authorize readiness. If
GitHub records the trigger and root comment in the same timestamp second, the
root comment is fresh only when its comment ID orders after the trigger comment.
When no such trigger exists, the newest marker-pinned clean root comment for that
head is canonical — repeated clean comments for the same head collapse to that single
newest one; when two such comments share a timestamp, the one whose comment ID orders
later is canonical — and it authorizes readiness only when its marker is valid and no newer non-dismissed terminal evidence covers that head; when no valid marker-pinned comment exists for that head, the head follows the acknowledgement-precedence wait path: `codex-github-reaction-without-review` when an acknowledgement signal is present, otherwise `codex-github-review-pending`.
Marker evidence splits into
two disjoint cases. A **well-formed marker for a prior revision** — exactly one
unambiguous hexadecimal commit token, functioning as a standalone commit
reference, that resolves to a different commit than the live head — is valid but
stale revision evidence: it follows the stale/pending
path (`codex-github-review-pending`) and is never escalated as malformed. A
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
| Per-run or lifetime allowance is exhausted and current evidence requires another review or fix cycle | Explicit escalation | Stop the current run for human review; never label ready | Protocol 93, Protocol 91 readiness checks, reviewer loop, PR summary | Repeated unresolved findings require a cycle after the lifetime allowance is consumed; canonical terminal clean evidence received in the final permitted evaluation instead continues to readiness |
| Per-run or lifetime allowance is omitted from configuration or resolves to an invalid count | Resolve each allowance independently: the omitted or invalid one uses its documented default (10 per-run, 25 lifetime) and the other keeps its explicitly configured value; log a warning for an invalid value | Apply the resolved per-allowance values and continue the normal evaluation; no configuration-reader semantics change | Reviewer loop, `.ai-dev-workflow.yaml` contract, `pr-review-loop.sh --help` | The shipped template leaves both settings commented out, so the loop runs with 10/25; if only `review.max_cycles` is set, the per-run cap uses that value and the lifetime ceiling stays 25 |
| Newer non-dismissed terminal Codex evidence exists for the live head after an older clean evidence item for the same head | Evaluate only the newest terminal-evidence timestamp, aggregating ties by the matrix precedence below | Ignore superseded same-head clean evidence; do not authorize readiness from an older clean verdict | Protocol 93 verdict classification, `codex-github.md`, reviewer loop | A clean submitted review is followed by a root comment for the same SHA with actionable findings |
| Multiple non-dismissed terminal Codex evidence items share the newest timestamp for the live head | Apply the tie precedence in order, first match wins: malformed-marker escalation, unrecognized-verdict escalation, incomplete-correlation escalation, evidence-unavailable escalation, actionable blocker, availability, cleared-findings wait (`codex-github-review-pending`), then clean | Record the highest-precedence outcome among the tied items; a tie between clean and any higher tier never resolves to clean, and a tie between availability and an escalation or actionable blocker resolves to the higher tier | Protocol 93 verdict classification, `codex-github.md`, reviewer loop | A clean submitted review and a malformed-marker root comment post in the same second for the same head, so the loop escalates as malformed-marker instead of claiming clean |
| Bounded evidence query fails or leaves resolution state or live-revision applicability unavailable or ambiguous after its retry; or the head-and-trigger chronology needed to attribute a trigger-less root comment to a head's evidence window cannot be established | `escalate` with reason `evidence_unavailable_codex_thread_state` | Stop the current run for human review; do not claim clean or return `needs_fixes`, and do not guess a head attribution for the comment | Protocol 93, `codex-github.md`, GitHub GraphQL adapter, reviewer loop, PR summary | The API times out while loading the conversation state, or a trigger-less head's comment cannot be placed relative to the prior head's last trigger |
| Root pull-request comment evidence within the live head's evidence window has a `Reviewed commit` marker that is syntactically unusable: empty, non-hex, contains multiple commit tokens, ambiguous between candidates, resolves to zero commits, or matches the live head only at an interior substring or as a superstring; no newer non-dismissed terminal evidence covers the same live head | `escalate` with reason `codex_current_verdict_malformed_revision_marker` | Stop the current run for human review; do not wait, claim clean, or infer an older-revision verdict from malformed marker evidence | Protocol 93 verdict classification, `codex-github.md`, reviewer loop, PR summary | A root comment says `Reviewed commit: abcdef1` when another candidate shares that prefix, embeds the live OID inside a longer token, or carries one valid-looking 40-character token that resolves to no commit at all; a malformed comment authored while an earlier head was current stays in that head's window and is ignored for the live head |
| Successful bounded evidence query; current terminal verdict contains a finding with no stable review-thread identifier or no identifiable matching conversation for the same reviewer evidence | `escalate` with reason `codex_finding_thread_correlation_missing` | Stop the current run for human review; do not claim clean or return `needs_fixes` for only other correlated findings | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | A submitted verdict has one unresolved-thread finding and one review-level finding with no thread identity |
| Successful bounded evidence query; the current terminal verdict is not a `CHANGES_REQUESTED` submitted review; every actionable finding in the current terminal verdict has an identifiable matching Codex review conversation for the live head, every matching conversation is resolved, no other applicable current-head Codex conversation remains unresolved, and the cycle allowance is not exhausted | `waiting_on_reviewer` with reason `codex-github-review-pending` | Request or await a fresh current-head Codex review through the cleared-findings retrigger path; do not dispatch a fixer, claim clean, or escalate correlation-missing | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | An operator resolves all Codex findings as false positives without changing HEAD and no other current-head Codex thread is open, so the next action is to obtain the clean verdict for that same head |
| Current terminal verdict covers the live revision but matches neither an approved clean template nor the documented blocking markers, is not a response the shipped adapter recognizes as an availability outcome, and is not a submitted review whose GitHub review state is `CHANGES_REQUESTED` | `escalate` with reason `codex_current_verdict_unrecognized` | Stop the current run for human review; do not synthesize `needs_fixes`, wait, or clean from an unparseable terminal verdict | Protocol 93 verdict classification, `codex-github.md`, reviewer loop, PR summary | A submitted Codex review for the live head has the standard footer but no approved-template reproduction and no blocking marker |
| Current terminal evidence is a genuine Codex availability response the shipped adapter already recognizes: a usage-limit notice, an account-not-connected refusal, or an environment-setup response, and no applicable unresolved conversation remains for the live head | Unavailable, with the shipped availability reason code for that response | Keep existing shipped availability handling; never reclassify as `codex_current_verdict_unrecognized` and never convert to clean, `needs_fixes`, or a terminal human escalation | Protocol 93 verdict classification, `codex-github-reviewer.sh`, reviewer loop, regression tests | Codex replies with its usage-limit or account-not-connected notice, and the loop keeps waiting on availability rather than escalating unrecognized |
| A current-head submitted review reports a recognized availability response, but an applicable unresolved Codex conversation for the live head still exists | Actionable blocker | Return `needs_fixes` and route to the fix loop; the unresolved applicable conversation is not erased by the later availability evidence | Protocol 93 verdict classification, reviewer-loop classification, reviewer loop, PR summary | An actionable review leaves one Codex thread unresolved, then a later review for the same head hits the usage limit; the loop still routes to fixes |
| Unresolved Codex conversation applies to the live revision; no current terminal verdict is unrecognized or malformed-marker; the thread state is determinate; every cycle allowance required for another review or fix cycle is not exhausted; and, when a current terminal verdict contains recognizable findings, every finding either correlates to an applicable unresolved conversation or is already cleared because all of its matching conversations are resolved | Actionable blocker | Return `needs_fixes` and route to the fix loop, attributing the blocker to the remaining applicable unresolved conversation; an exhausted allowance escalates instead | Protocol 93, reviewer-loop classification, summary output, regression tests | A current Codex finding remains unresolved while an earlier clean verdict is visible, or the verdict's own finding thread is resolved while a separate applicable current-head Codex thread remains open |
| A current-head submitted Codex review carries GitHub review state `CHANGES_REQUESTED` | Actionable blocker attributed to the review state | Return `needs_fixes` and route to the fix loop even when the review carries no finding mapped to an applicable unresolved conversation; never approve from body wording, and do not record it as unrecognized or clean | Protocol 93 verdict classification, `codex-github-reviewer.sh` structured-state short-circuit, reviewer loop, PR summary | Codex submits a `CHANGES_REQUESTED` review whose body happens to reproduce a clean template, or whose findings all resolve, yet the structured state still blocks readiness |
| A current-head submitted Codex review carries GitHub review state `CHANGES_REQUESTED` and also contains a finding with no stable review-thread identifier or no identifiable matching conversation | `escalate` with reason `codex_finding_thread_correlation_missing` | Stop the current run for human review; the fail-closed correlation rule takes precedence over the structured-state blocker | Protocol 93 verdict classification, `codex-github-reviewer.sh`, reviewer loop, PR summary | A `CHANGES_REQUESTED` review mixes a thread-anchored finding with a review-level finding that has no thread identity |
| No unresolved current conversation; terminal clean evidence covers the live revision as either a submitted Codex review with a non-blocking review state (never `CHANGES_REQUESTED`), the full live commit SHA, and a clean body, or, when a live-head review trigger exists, a Codex root pull-request comment authored after that trigger whose `Reviewed commit` marker contains exactly one hexadecimal commit token that is an unambiguous prefix of the live head and whose body is clean | Clean current evidence | Continue to readiness | Protocol 93, `codex-github.md`, Protocol 91 readiness checks, reviewer loop | A current submitted clean review or fresh marker-pinned clean root comment authorizes the Codex phase; a `CHANGES_REQUESTED` review whose body mimics the clean template does not |
| No live-head review trigger exists yet; a marker-pinned clean root comment for the live head is present and no newer non-dismissed terminal evidence covers that same head | Clean current evidence | Continue to readiness; a newer finding, malformed-marker, unrecognized, or incomplete-correlation item for the same head supersedes this clean state | Protocol 93, `codex-github.md`, reviewer loop | Codex posts a clean SHA-pinned root comment on a head that never received a review trigger |
| No unresolved current conversation; otherwise clean-looking or acknowledgement evidence exists for the live-head review attempt but has no submitted review marker and no explicit reviewed SHA | `waiting_on_reviewer` with reason `codex-github-reaction-without-review` | Await or request terminal evidence for the unchanged head; do not claim clean | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | A draft review is visible, or a root clean comment posted after the latest live-head trigger omits any reviewed SHA |
| No Codex conversations, or only resolved, dismissed, or historic conversations; an acknowledgement signal is absent and no candidate Codex review/comment evidence exists for the live-head review attempt, or no live-head-covering terminal evidence exists and the newest valid submitted or SHA-marked terminal evidence, including a well-formed `Reviewed commit` marker that names a prior commit, covers an earlier revision | `waiting_on_reviewer` with reason `codex-github-review-pending` | Request or await a submitted current review for the unchanged head; do not dispatch a fixer, claim clean, or escalate malformed-marker | Protocol 93, `codex-github.md`, reviewer loop, readiness checks | A newly opened pull request with no acknowledgement, review, or comment has no Codex review yet, a push occurs after the last valid Codex review and no newer current-head evidence exists, or the only valid root clean comment names an older SHA |
| Root pull-request comment carries a well-formed `Reviewed commit` marker naming the live head but misses the freshness boundary (authored before the latest live-head trigger, or same-second without a later ordering comment ID) | `waiting_on_reviewer` with reason `codex-github-review-pending` | Await or request terminal evidence for the unchanged head; do not treat the comment as acknowledgement or clean, and do not escalate malformed-marker | Protocol 93 verdict classification, `codex-github.md`, reviewer loop | Codex posts a SHA-pinned clean root comment just before an operator re-triggers a review on the same head |
