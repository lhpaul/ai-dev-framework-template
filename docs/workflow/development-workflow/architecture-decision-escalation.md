# Architecture Decision Escalation — Canonical Requirement

**Spec**: [Axis-Separated Architecture Decision Escalations](specs/developments/20260911230558_1515-architecture-decision-axes/1_1515-architecture-decision-axes_specs.md)
(issue #1515). This page is the **canonical** statement of what a well-formed
`architecture_decision` escalation must contain. It does not change when the
`architecture_decision` stop condition fires — see
[`guardrails-enforcement.md`](guardrails-enforcement.md) §4 for the trigger and
§5 for the stop-message contract this page extends.

---

## Scope

This requirement applies to exactly two surfaces:

1. An **escalation report** emitted when a runner stops under
   `architecture_decision`.
2. A **reply on a review thread** (Protocol 93) where the runner cites a
   workflow specification line **as support** for its behavior or for a
   decision a reviewer or human will weigh.

A workflow specification line named only to identify a source, without being
offered as support, carries none of this page's declarations. A citation in
other human-readable rationale (for example, a planning artifact or a source
comment) is **out of scope** for this MVP (spec Out of Scope, item 3).

---

## Vocabulary

Display labels only — no new machine-readable codes are introduced.

### Coverage verdict (recorded once per axis)

| Display label | Description |
| --- | --- |
| Settled by specification | A specific cited workflow specification line answers this axis. No human decision is needed on it. |
| Genuinely open | No cited line settles this axis. Always accompanied by exactly one reason from the table below. |

### Open-axis reason (recorded with every Genuinely open verdict)

| Display label | Description |
| --- | --- |
| No governing line | Nothing in the workflow specification bears on this axis. Reported with the surfaces the runner consulted. |
| Governing lines conflict | More than one line bears on this axis and they do not agree. Reported with every conflicting citation and what each would require. |
| Governing line covers a different case | A line looks applicable but governs a neighbouring case rather than this axis. Reported with the citation and why it does not reach the axis. |
| Coverage uncertain | The runner cannot tell whether a line reaches this axis. Reported with the citation in doubt and what is unclear about it — or, where no candidate citation can even be tested, with what is ambiguous about the axis instead. |
| Governing line disputed | A separate axis from the one the cited line settles — never a reclassification of it. Applies where a line reaches and covers that other axis, coverage is certain, but the runner judges the line's substance wrong. Reported with the citation and a **required** proposed amendment stating what the line should become instead. |

### Conformance declaration (recorded with every citation offered as support)

| Display label | Description |
| --- | --- |
| Conforms | The runner's current behavior matches the cited line. |
| Departs | The runner's current behavior does not match the cited line. Reported with what the behavior does instead and why. Never presented as support for the current behavior. |
| Not yet implemented | The cited line governs behavior that does not exist yet. Never used for behavior the runner has already built. |

**Undetermined exception**: a citation whose conformance genuinely cannot be
determined carries **none** of the three declarations above. It states plainly
that conformance could not be determined and why. In an escalation report, this
makes the report **incomplete** rather than well-formed (see Malformed-input
rows below); in a standalone review-thread reply, the reply states this plainly
without alone opening a full escalation.

---

## Mandatory report outline

A well-formed, complete escalation report contains, in order:

1. **Question and source** — the question as it was asked, and who or what
   raised it (reviewer finding, human comment, or the runner's own analysis).
2. **Axes** — every independently decidable component of the question, each
   stated so a reader can answer it without answering any other listed axis.
   A question with one axis lists exactly one — never zero.
3. **Per-axis verdict** — exactly one coverage verdict per axis, plus (for
   Settled) the citation and how it answers the axis, or (for Genuinely open)
   exactly one reason from the vocabulary above with its required content.
4. **Per-citation conformance declaration** — every determinable citation
   offered as support carries `Conforms`, `Departs`, or `Not yet implemented`.
   See the **Per-citation declaration rule** below for mixed reports.
5. **Arguments tied to one axis** — every argument the report offers names the
   one axis it addresses; an argument about a different axis than the one
   raised is labelled as addressing that other axis, not presented as an
   answer to the axis raised.
6. **Requested decision** — names the **genuinely open axes only**. No axis
   marked Settled by specification appears in the requested decision. Where
   the report has no open axis but a determinable citation is missing evidence
   or a raised substance question is unresolved (see Malformed-input rows),
   the report instead states that request separately — never merged into the
   requested decision itself.
7. **Recommendation (optional, labelled separately)** — the runner may state a
   recommendation for an open axis. It is labelled as a recommendation, never
   presented as the answer, and never narrows the decision the human can make.
   It is **stated separately from the requested decision**, not folded into it.
8. **Incompleteness markers** — where a malformed-input row applies (see
   below), the report states this plainly and is reported as **incomplete**,
   not well-formed.

The report never acts on, pre-answers, or asks for ratification of any axis
marked Genuinely open.

---

## Per-citation declaration rule (mixed reports)

Every determinable citation offered as support carries its declaration **even
when the overall report is incomplete** because a *different* citation
triggered a conformance-undetermined or substance-undetermined malformed-input
row. Composition is per citation, not per report: one undetermined citation
does not excuse a different, determinable citation in the same report from
carrying `Conforms`, `Departs`, or `Not yet implemented`. Undetermined
citations carry none of the three declarations — they state plainly that
conformance (or substance) could not be determined and why.

---

## Raised-question gate (substance-undetermined incomplete reports)

A citation's substance question is treated as an incomplete,
`architecture_decision`, **substance undetermined** escalation **only where a
reviewer or a human has actually raised** that citation's substance in
question and the runner genuinely cannot resolve it either way. Where nobody
has raised the question, the citation's axis proceeds unquestioned under the
settled-axis rules — internal runner uncertainty about a citation's substance,
absent an actual raised question, is not by itself grounds for this
malformed-input row. This gate applies identically to the **Stop-message
contract** in `guardrails-enforcement.md` §5: a substance-confirmation request
in the required human action is stated only where the question was actually
raised.

---

## Malformed or missing gate inputs (summary — spec matrix is authoritative)

| Missing or malformed input | Outcome |
| --- | --- |
| The question or its source cannot be established | Escalated, incomplete |
| Decomposition produces no axis at all | Escalated, incomplete |
| A citation's conformance cannot be determined | Escalated, conformance undetermined — coverage verdict on that axis is unaffected |
| A reviewer or human raised a covered citation's substance and the runner cannot resolve it (raised-question gate above) | Escalated, substance undetermined — coverage verdict on that axis is unaffected |

None of these rows produces "Not an architecture decision" or lets the run
continue unaided. The full outcome, precedence, and composition rules — how
these rows compose with settled/open axes and with each other — live in the
spec's
[Decision-Gate Consistency Matrix](specs/developments/20260911230558_1515-architecture-decision-axes/1_1515-architecture-decision-axes_specs.md#decision-gate-consistency-matrix),
which is authoritative. This page states the requirement; it does not restate
every precedence rule.

---

## Worked example

From the spec's Examples table (review-cycle / cumulative-effort incident):

> **Question (source):** Reviewer asked to reset the review-cycle counter at
> orchestration start (PR review thread).
>
> **Axes:**
>
> 1. Reset boundary for the counter — **Settled by specification** — citation:
>    Protocol 91 `PR_REVIEW_LOOP_RUN_ID` paragraph, which initializes the
>    counter once per orchestration run — **Departs**: the runner's
>    implementation never resets at that boundary; the line is not offered as
>    support for the behavior. **Next action:** conform to the cited line
>    (correction), not an architecture decision.
> 2. Whether run-scoped counting alone bounds total effort across resumed runs
>    — **Genuinely open — No governing line** — surfaces consulted: Protocol 91,
>    `guardrails-enforcement.md`, `REVIEW.md`. **This is the only axis put to
>    the human.**
>
> **Mis-attached argument (labelled):** The argument that resetting would make
> the cap ineffective, because the incident had a new head almost every cycle,
> addresses axis 2 (cumulative effort), not axis 1 (reset boundary) — it is
> labelled as addressing axis 2 and is not an answer to the reset-boundary
> question actually raised.
>
> **Requested decision:** Axis 2 only. Axis 1 is reported for checking, not
> asked about — its correction is the next action, unaffected by axis 2.
>
> **Recommendation (optional, separate):** Prefer documenting cumulative-effort
> policy in `guardrails-enforcement.md` if axis 2 is answered yes.

This example shows: one settled axis alongside one genuinely open axis (visibly
distinguished); a `Departs` citation not used as support; and an argument
labelled as addressing a different axis than the one raised.

---

## Pointer

The spec's
[Decision-Gate Consistency Matrix](specs/developments/20260911230558_1515-architecture-decision-axes/1_1515-architecture-decision-axes_specs.md#decision-gate-consistency-matrix)
is authoritative for gate inputs, triggers, allowed outcomes, malformed-input
rows, precedence, and composition. Consult it directly for any case not
summarized above.

---

## Mirror surfaces

Every workflow surface that restates `architecture_decision` escalation
behavior must agree with this page:
[`guardrails-enforcement.md`](guardrails-enforcement.md) §5, Protocol
[`91`](protocols/91-orchestrate-work-protocol.md),
[`93`](protocols/93-automated-reviewer-loop-protocol.md), and
[`90`](protocols/90-batch-orchestrate-work-protocol.md), plus the
runner-facing agent and skill mirrors listed in those protocols. No surface may
state a lighter requirement, and none may describe an escalation without the
coverage analysis above as well-formed.
