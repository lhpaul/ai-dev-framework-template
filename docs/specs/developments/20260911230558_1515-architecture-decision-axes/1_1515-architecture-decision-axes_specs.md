# Axis-Separated Architecture Decision Escalations — Spec

---

## Overview

When a runner reaches a question it cannot safely answer on its own, it stops the run and hands that question to a human under the `architecture_decision` stop condition. Nothing today requires it to first establish which part of the question the workflow specification already answers. A question with one settled part and one genuinely open part can be handed over whole, as "an open architecture decision", and the human then does the separation work the runner was better placed to do.

This feature defines what a well-formed `architecture_decision` escalation must contain. The runner states the question as it was actually asked, breaks it into axes that can each be answered without answering the others, and for every axis records whether a workflow specification line already settles it — with the citation — or whether it is genuinely open, with the reason the specification does not reach it. Every line the runner cites carries a plain declaration of whether the runner's own behavior conforms to that line or departs from it. The decision put to the human is then narrowed to the axes that are genuinely open.

The change is to framing, not to judgment. It does not make a runner stop where it would not have stopped, and it does not let a runner continue past a question that needs a human. It changes what the human receives when the runner does stop: a question already separated into the part the workflow answers and the part only a person can.

The defect is on record. In the run that produced this item, a reviewer asked the runner to reset a counter at one boundary; the workflow specification answered that exact boundary in a line the runner had quoted in its own code comment, immediately above an implementation doing the opposite. The runner defended a different boundary — correctly, but about the other axis — and escalated the whole thing as open. A real open axis did exist underneath, so stopping was right; the human simply had to find it unaided.

---

## Use Cases

### Use Case 1: A question with one settled axis and one genuinely open axis

**Actor**: The runner driving the work item.
**Preconditions**: A question has been put to the runner — by an automated reviewer finding, a human comment, or the runner's own analysis — and the runner has judged that it cannot resolve the question alone. It is about to stop under `architecture_decision`.

**Steps**:

1. The runner states the question as it was asked, and names who or what raised it.
2. It separates the question into axes, each stated so that it can be answered without answering any other.
3. For each axis it looks for a workflow specification line that settles it, and records a coverage verdict: Settled by specification with the citation, or Genuinely open with a reason.
4. For every line it cites, it declares whether the runner's current behavior Conforms to that line, Departs from it, or is Not yet implemented.
5. It states the decision it is asking the human to make, covering the genuinely open axes only, and stops with the report attached.

**Postconditions**: The run has stopped under `architecture_decision`. The human has a question already split into the part the workflow settles and the part that is open, and is being asked to decide only the open part. Nothing was decided for the human, and nothing that the specification settles was presented as open.

**Information shown**:

- The question as asked, and its source.
- Each axis, with its coverage verdict.
- For each settled axis, the citation that settles it and how that line answers the axis.
- For each open axis, the reason the specification does not settle it.
- For each citation, the conformance declaration.
- The decision requested, naming the open axes it covers.
- The existing stop elements: the stop condition name, the affected work item, and the action required of the human.

**Actions available**:

- Answer the open axis or axes, which is the requested decision.
- Reject the decomposition and ask the runner to redo it.
- Overturn an axis the runner marked settled, by deciding that the cited line should change. That is a different question from the one asked, and it enters as a new axis rather than as an answer to this one.

**Considerations**:

- A single question rarely has many axes. Two or three is the normal shape; the point is separation, not exhaustiveness.
- An argument the runner offers in support names the one axis it addresses. An argument about a neighbouring axis is not an answer to the axis raised, and saying so is part of the report rather than something the human has to notice.

---

### Use Case 2: A question the workflow specification does not answer at all

**Actor**: The runner driving the work item.
**Preconditions**: A question has been raised, the runner cannot resolve it alone, and it has found nothing in the workflow specification that bears on it.

**Steps**:

1. The runner states the question and its source.
2. It finds that the question has one axis, because no part of it can be answered separately from the rest.
3. It records that axis as Genuinely open with the reason No governing line, and states which surfaces it consulted in looking.
4. It states the requested decision and stops.

**Postconditions**: The run has stopped with a report containing one axis. The human can see that the absence of governing guidance was established rather than assumed.

**Information shown**:

- One axis, its verdict, its reason, and the surfaces consulted.
- The requested decision and the existing stop elements.

**Actions available**:

- Answer the open question.
- Point the runner at a surface it did not consult, and have it redo the coverage analysis.

**Considerations**:

- One axis is a valid decomposition. The report is not padded with invented axes to look thorough.
- "The specification does not answer this" is a claim about a search. Naming where the runner looked is what makes the claim checkable; without it the human is back to doing the search themselves.

---

### Use Case 3: The runner's own behavior departs from the line it wants to cite

**Actor**: The runner driving the work item.
**Preconditions**: The runner is about to cite a workflow specification line in support of its current behavior, in an escalation report or in a reply on a review thread.

**Steps**:

1. The runner identifies the line it intends to cite.
2. Before offering it, it declares whether its current behavior Conforms to that line or Departs from it.
3. Finding that the behavior departs, it states the departure plainly and does not present the line as support.
4. It records the departure as a finding about its own work: either an error to correct by conforming, or a reason to ask whether the line itself should change — which is a separate axis, genuinely open.

**Postconditions**: The contradiction is visible in the runner's own words, at the moment of citation, rather than being discovered later by a reviewer or a human. No citation stands as support for behavior that contradicts it.

**Information shown**:

- The cited line, the declaration, and — where the declaration is Departs — what the behavior does instead and why.

**Actions available**:

- Read the departure and decide whether the behavior or the line is the thing that should change.

**Considerations**:

- The declaration is required wherever the citation appears in a rationale a human or reviewer will read, not only inside an escalation report. A review-thread reply is exactly such a surface: a reviewer reads it directly, often before any escalation report exists.
- Declaring Departs is not by itself an architecture decision. Where conforming to the cited line is the obvious correction, the axis is settled and the correction is the next action.
- Not yet implemented exists for citations made before the behavior is built — during planning, or about work not yet started. It is never used to avoid declaring a departure in behavior that does exist.

---

### Use Case 4: The operator reads the stop and decides

**Actor**: The operator — the human the run stopped for.
**Preconditions**: A run has stopped under `architecture_decision` and its escalation report is available on the work item.

**Steps**:

1. The operator reads the question as asked and the axes it was broken into.
2. For each settled axis, the operator checks the citation against the axis.
3. For each open axis, the operator reads the reason and decides.
4. The operator records the decision where the runner or the next run will read it.

**Postconditions**: The decision covers the open axes. The operator did not have to reconstruct the decomposition, locate the governing lines, or work out which axis the runner's arguments were about.

**Information shown**:

- The whole report, durable on the work item rather than only in a session transcript.

**Actions available**:

- Decide the open axes.
- Send the report back as incomplete, naming the missing element.
- Decide that a settled axis should be reopened by changing the cited line.

**Considerations**:

- A report missing any required element is incomplete, and the operator can tell that by reading the report alone.
- The operator is never asked to confirm a settled axis as a precondition for the open one being answered. Settled axes are reported so they can be checked, not so they can be re-decided.

---

### Use Case 5: Two specification lines answer the same axis differently

**Actor**: The runner driving the work item.
**Preconditions**: The runner has found more than one workflow specification line bearing on a single axis, and they do not agree.

**Steps**:

1. The runner records the axis as Genuinely open with the reason Governing lines conflict.
2. It cites every line it found for that axis, with a conformance declaration for each.
3. It states what each line would require, so the conflict is legible without the human opening the documents.
4. It stops with the requested decision covering that axis.

**Postconditions**: The conflict is reported as the reason the axis is open. The runner has not chosen between the conflicting lines on its own.

**Information shown**:

- Every conflicting citation, what each requires, and the runner's conformance declaration against each.

**Actions available**:

- Decide which line governs, which typically also means deciding that the other should change.

**Considerations**:

- Picking whichever line supports the current behavior, and citing only that one, is the failure this reason exists to prevent.
- A conflict the runner is unsure about is still a conflict. Where it cannot tell whether two lines genuinely disagree, the reason is Coverage uncertain instead, and the uncertainty is stated.

---

## Business Rules

- An **axis** is one independently decidable component of the question raised. Two proposed axes that cannot be answered separately are one axis. An axis that the specification settles only in part is split until every axis carries exactly one coverage verdict.
- Every axis carries exactly one coverage verdict: **Settled by specification** or **Genuinely open**. There is no partial verdict.
- An axis is Settled by specification only when a specific, cited workflow specification line answers it. A general principle, an inference from neighbouring guidance, or the runner's own past behavior is not a settling citation.
- Every Genuinely open axis carries exactly one reason, drawn from the defined reason vocabulary, and the reason is stated in terms of what was looked for rather than asserted.
- Where the reason is **No governing line**, the report names the surfaces the runner consulted. An unsearchable claim of absence is not a reason.
- Where the runner cannot tell whether a line reaches an axis, the axis is Genuinely open with the reason **Coverage uncertain**, and the uncertainty is stated as such. Uncertainty is never resolved in favour of settled.
- Every citation offered anywhere in the runner's rationale carries a **conformance declaration**: Conforms, Departs, or Not yet implemented. This holds in escalation reports and in replies on review threads — anywhere the runner offers a citation as support for a decision a human or reviewer will weigh.
- A citation whose declaration is Departs is never presented as support for the current behavior. The report states the departure plainly, in the runner's own words, before it asks the human anything.
- A departure is a finding about the runner's own work. It is either an error to correct by conforming to the cited line, or a reason to ask whether the line should change. The second is a new axis, stated separately, and is Genuinely open.
- Every argument the runner offers is attached to exactly one axis. An argument that addresses a different axis than the one raised is labelled as such and is not presented as an answer to the question asked.
- The **requested decision** covers the genuinely open axes only. Settled axes are reported for checking and are never included in what the human is asked to decide.
- The runner may state a recommendation for an open axis. A recommendation is labelled as one, never presented as the answer, and never narrows the decision the human can make.
- The report never decides an open axis, never proceeds on a provisional answer to one, and never asks the human to ratify an action already taken on one.
- This requirement is a precondition on the **content** of an `architecture_decision` escalation, not on the decision to stop. It adds no new grounds for stopping and removes none. It never authorizes a runner to continue past a question that requires a human decision.
- The coverage analysis is not a way to suppress a stop. Where every axis comes back Settled by specification and the runner is nonetheless unsure whether the cited lines fully answer the question, that uncertainty is itself an open axis and the runner stops.
- Where every axis is settled and the runner is not uncertain, the work does not require a human decision and the `architecture_decision` condition's own trigger is not met. Applying the cited lines is what the specification already required; recognizing that is not a relaxation of the stop condition.
- The existing stop-message elements — the exact stop condition name, the affected work item, and the concrete human action required — are unchanged and still present. The escalation report is additional to them, never a replacement for any of them.
- The report is written for the current question. A report carried over from an earlier escalation is restated against the question actually being asked now.
- Every workflow surface that tells a runner how to escalate an architecture decision must agree with the canonical statement of this requirement. No surface may state a lighter requirement, and none may describe an escalation without the coverage analysis as well-formed.

---

## Statuses / Enum Values

These are report vocabulary. The escalation report is read by people, so the display label below is the value that appears; no machine-readable code values are introduced.

Coverage verdict, recorded once per axis:

| Display label            | Description                                                                                                                       |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Settled by specification | A specific cited workflow specification line answers this axis. No human decision is needed on it.                                 |
| Genuinely open           | No cited line settles this axis. Always accompanied by exactly one reason from the table below.                                     |

Reason, recorded with every Genuinely open verdict:

| Display label                       | Description                                                                                                                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| No governing line                   | Nothing in the workflow specification bears on this axis. Reported with the surfaces the runner consulted.                                    |
| Governing lines conflict            | More than one line bears on this axis and they do not agree. Reported with every conflicting citation and what each would require.            |
| Governing line covers a different case | A line looks applicable but governs a neighbouring case rather than this axis. Reported with the citation and why it does not reach the axis. |
| Coverage uncertain                  | The runner cannot tell whether a line reaches this axis. Reported with the citation in doubt and what is unclear about it — or, where no candidate citation can even be tested because the axis itself is unclear, with what is ambiguous about the axis instead. |

Conformance declaration, recorded with every citation:

| Display label       | Description                                                                                                                            |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Conforms            | The runner's current behavior matches the cited line.                                                                                   |
| Departs             | The runner's current behavior does not match the cited line. Reported with what the behavior does instead and why.                       |
| Not yet implemented | The cited line governs behavior that does not exist yet, so there is nothing to conform to or depart from. Never used where behavior exists. |

---

## Operational Visibility

- **Escalation report**: emitted wherever the stop itself is reported — in the run summary the operator reads, and as a durable record on the work item's pull request when one exists. It is readable without opening an agent session transcript.
- **Stop message**: unchanged in its three existing elements, with the required human action naming the genuinely open axes rather than the question as a whole.
- **Citation declarations outside the report**: where a runner cites a workflow specification line in a reply on a review thread, the conformance declaration appears in that reply, so a reviewer reading the thread sees it without opening the escalation report.
- **Incompleteness**: an escalation report missing a required element is identifiable as incomplete from the report alone, without reconstructing what the runner did.

---

## Decision-Gate Consistency Matrix

Raising `architecture_decision` is a workflow decision gate: what the runner does next depends on several inputs, and this feature changes what the gate must produce. The matrix below is the canonical statement of the changed behavior.

### Gate inputs

| Input                                                       | Where it comes from                                                      | Why it matters                                                                    |
| ----------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| The question as raised, and its source                      | A reviewer finding, a human comment, or the runner's own analysis        | The report answers the question actually asked, not a restatement of it            |
| The axis decomposition                                      | The runner, applying the independence rule                               | **Added by this feature.** Decides what the human is asked to settle               |
| The workflow specification lines found for each axis        | The runner's search of the workflow surfaces                             | **Added by this feature.** Supplies the citation behind every settled verdict      |
| Whether the runner's behavior matches each cited line       | The runner's own current behavior or implementation                      | **Added by this feature.** Decides whether a citation can stand as support         |
| Whether the runner can determine coverage for an axis       | The same search                                                          | Unresolvable coverage is an open axis, never a settled one                         |

### Triggers

Triggers are events. They decide when this gate runs, and none of them is read as an input.

| Trigger                                                                          | Why it fires                                                                                |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| The runner is about to stop under `architecture_decision`                        | The gate's normal entry point                                                                |
| A reviewer finding asks the runner to change behavior the specification may govern | The case where a settled axis is most likely to be mistaken for an open one                 |
| The runner is about to cite a workflow specification line in a rationale          | Fires the conformance declaration alone, without requiring a full escalation report          |
| A previously escalated item is resumed and the question is still open            | The report is restated for the question as it now stands, rather than reused unexamined      |

### Allowed outcomes and required next actions

| Inputs                                                                         | Outcome                     | What the runner does                                                                                     | Operator's next action                                          |
| ------------------------------------------------------------------------------ | --------------------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Every axis Genuinely open                                                      | Escalated                   | Stops with a report listing each axis, its reason, and a requested decision covering all of them           | Decide the open axes                                             |
| At least one axis settled, at least one open                                   | Escalated, scope narrowed   | Stops with the settled axes cited and the requested decision covering the open ones only                   | Decide the open axes; the settled ones need no answer            |
| Every axis settled, the runner conforms, and the runner is not uncertain       | Not an architecture decision | Applies the cited lines and continues; no human decision was required                                      | None                                                             |
| Every axis settled, the runner's behavior departs on one                       | Departure reported          | States the departure plainly and either conforms, or opens a new axis asking whether the line should change | None, unless a new axis was opened — then decide that axis       |
| Every axis settled, but the runner is unsure the lines fully answer the question | Escalated                   | Records the uncertainty as an open axis with the reason Coverage uncertain, and stops                      | Decide the uncertain axis                                        |
| Lines bearing on one axis conflict                                             | Escalated                   | Reports the axis as open with every conflicting citation and what each requires                            | Decide which line governs                                        |
| The question does not separate into more than one independently answerable component, and that one axis is Genuinely open | Escalated                   | Reports the whole question as one axis, per the axis rule in Business Rules — never as zero axes. Where what is ambiguous about the question itself keeps the runner from telling whether any line reaches it, marks that one axis Genuinely open with the reason Coverage uncertain, and states the ambiguity as what is unclear | Decide the axis, or restate the question so the runner can attempt coverage again |
| Every axis settled, coverage certain, and every citation on those axes is Not yet implemented | Not an architecture decision | Proceeds with the work as the cited lines already specify. There is no departure to declare, because the behavior does not exist yet to conform or depart                                     | None                                                             |
| A citation is offered outside an escalation report                             | Declaration required        | Attaches Conforms, Departs, or Not yet implemented to that citation in place                                | None                                                             |

Exactly one row applies to any question. The three settled-axis rows above — the runner conforms, the runner's behavior departs, and every citation is Not yet implemented — read the same way whether the settled axis is the question's only axis or one among several, reaching Not an architecture decision, Departure reported, and Not an architecture decision respectively either way. The "Every axis Genuinely open" row and the "Lines bearing on one axis conflict" row are for questions with more than one axis. Where a question does not separate into more than one axis at all, its single axis is read instead by the row for a question that does not separate when Genuinely open, and by the settled-axis rows above when settled — never by those two multi-axis rows.

No outcome above answers an open axis, acts on a provisional answer to one, or asks the human to ratify an action already taken on one. No outcome changes which stop condition applies to a question, and none suppresses a stop the runner would otherwise have taken.

### Malformed or missing gate inputs

The outcomes above assume each gate input in the Gate inputs table could actually be established. Where establishing one of them fails outright, none of the outcomes above apply; the rows below govern instead, and every one of them fails closed — the escalation is reported as incomplete rather than presented as well-formed, and the runner never treats a missing or malformed input as grounds to skip the stop.

| Missing or malformed input                                                                              | Outcome                        | What the runner does                                                                                                                    | Operator's next action                                                        |
| --------------------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| The question as raised, or its source, cannot be established                                             | Escalated, incomplete           | Stops under `architecture_decision` regardless, records that the question or its source is missing, and does not present the report as complete | Supply the missing question or its source; the escalation cannot close until it does |
| The axis decomposition produces no axis at all                                                           | Escalated, incomplete           | Stops, records that decomposition produced zero axes — which the axis rule in Business Rules never allows, since inseparable components are one axis, not none — and treats this as a defect in the escalation rather than a valid outcome | Have the runner redo the decomposition; at least one axis is required before the report stands |
| A citation's conformance cannot be determined, and the cited line governs behavior that already exists  | Escalated, conformance undetermined | Does not declare Conforms or Departs, and does not use Not yet implemented for behavior that exists. States plainly that conformance could not be determined and why, and reports the axis that citation was meant to settle as Genuinely open with the reason Coverage uncertain | Decide the axis, or point the runner at what would let it determine conformance |

None of these three rows produces "Not an architecture decision" or any other outcome that lets the run continue without a human decision.

### Mirror surfaces

| Surface                                                                       | Relationship                                                                     | Consistency requirement                                                                          |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| The runner-facing escalation guidance for work items                          | **Canonical.** States what an `architecture_decision` escalation must contain     | Carries the axis, verdict, reason, and conformance vocabulary defined here, plus the worked example |
| The escalation guidance for the automated reviewer loop                       | Where reviewer findings become escalations                                        | Must require the same report, or point at the canonical statement without weakening it            |
| The canonical stop-message contract                                           | Defines the three existing stop elements                                          | Unchanged. The report is additional; the three elements remain required                           |
| Runner-facing agent, command, and skill definitions that restate escalation behavior | Restate escalation behavior for individual tools                            | May not describe an escalation without the coverage analysis as well-formed                       |
| The named stop-condition vocabulary                                           | Defines when `architecture_decision` fires                                        | Unchanged. This feature does not alter the condition's trigger or its wording                     |
| The worked example                                                            | Shows a settled axis and an open axis in one report                              | Lives with the canonical guidance, so a runner reading the requirement sees the example           |

### Examples

The opening rows work through the recorded incident.

| Situation                                                                                                       | Verdict or declaration                        | What the report says                                                                                                 |
| ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Reviewer asks the runner to reset a review-cycle counter at the start of each orchestration run                  | Settled by specification                      | The cited line initializes the counter once per orchestration run, so the axis raised is answered — reset at that boundary |
| The same runner's implementation never resets at that boundary                                                   | Departs                                       | The declaration on that citation is Departs, stated plainly; the line is not offered as support for the behavior      |
| The runner's argument that resetting would make the cap ineffective, because the incident had a new head almost every cycle | Attached to a different axis         | Correct about resetting on a new head, which the same line also settles — and labelled as addressing that axis, not the one raised |
| Whether run-scoped counting alone leaves total effort unbounded across many resumed runs                        | Genuinely open — No governing line            | The real decision: no line bears on cumulative effort across runs. This is the only axis put to the human             |
| A question about a behavior no workflow line mentions at all                                                    | Genuinely open — No governing line            | One axis, plus the surfaces consulted in looking for one                                                             |
| Two lines that require different things of the same behavior                                                    | Genuinely open — Governing lines conflict     | Both citations, what each requires, and a declaration against each                                                   |
| A line that governs the draft stage, raised about the ready stage                                               | Genuinely open — Governing line covers a different case | The citation, and why it does not reach the axis                                                            |
| A line the runner cannot tell applies                                                                           | Genuinely open — Coverage uncertain           | The citation in doubt and what is unclear about it; never resolved as settled                                        |
| A citation about behavior the plan has not built yet                                                            | Not yet implemented                           | The declaration says so; it is not used where the behavior exists                                                    |
| Every axis settled, the runner conforms, no uncertainty                                                         | No escalation                                 | The runner applies the cited lines; there was no architecture decision to make                                       |
| Every axis settled, coverage certain, and every citation is Not yet implemented — nothing cited has been built yet | No escalation                                 | The runner proceeds to build what the cited lines specify; there is no departure to declare, because there is no behavior yet to conform or depart                       |

### Coverage Matrix: issue-objective traceability

Acceptance criteria are referenced by group — the sub-headings under **Acceptance Criteria** — because criterion numbers shift during review while group names do not.

| Objective from issue #1515                                                                              | Disposition                                                                                                              |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| State the specific question asked, decomposed into independent axes where it has more than one            | Covered. Group: *The escalation names the question and its axes*                                                          |
| For each axis, state whether a specification line already answers it — with the citation                  | Covered. Group: *Every axis carries a verdict*                                                                            |
| State which axes remain genuinely open, and why the specification does not settle them                    | Covered. Group: *Every axis carries a verdict*                                                                            |
| Where the runner's implementation contradicts a cited line, say so plainly rather than citing it as support | Covered. Group: *Citations carry a conformance declaration*                                                             |
| Partial guard — a quoted specification line in a rationale carries a conform/depart declaration            | Covered for escalation reports and review-thread replies. Group: *Citations carry a conformance declaration*. Source-code comments are Out of Scope, item 3 |
| Escalation guidance requires per-axis coverage analysis before `architecture_decision` is raised            | Covered. Groups: *The escalation names the question and its axes*, *Surfaces agree*. Which guidance document carries the text is an implementation-plan decision |
| Guidance states that a cited specification line must be accompanied by a conform/depart declaration        | Covered. Groups: *Citations carry a conformance declaration*, *Surfaces agree*                                            |
| Include a worked example distinguishing "the specification already answers this" from "genuinely open"     | Covered. Group: *The guidance carries a worked example*                                                                   |
| The defect is framing, not the decision to stop                                                            | Covered. Group: *The requirement never suppresses a stop*, and Out of Scope, item 1                                       |

---

## Acceptance Criteria

### The escalation names the question and its axes

- [ ] An emitted `architecture_decision` escalation report states the question as it was asked and names who or what raised it.
- [ ] The report lists the axes the question was separated into. A question with one axis lists one; a question with more lists each of them.
- [ ] Each listed axis is stated so that a reader can answer it without answering any other listed axis.
- [ ] No axis in an emitted report carries more than one coverage verdict. An axis the specification settles only in part appears as two or more axes, each with one verdict.
- [ ] Each argument the report offers names the one axis it addresses. An argument about a different axis than the one raised is labelled as addressing that other axis.

### Every axis carries a verdict

- [ ] Every axis in an emitted report carries exactly one coverage verdict: Settled by specification or Genuinely open.
- [ ] Every axis marked Settled by specification carries a citation identifying a specific workflow specification line, and says how that line answers the axis.
- [ ] Every axis marked Genuinely open carries exactly one reason: No governing line, Governing lines conflict, Governing line covers a different case, or Coverage uncertain.
- [ ] An axis marked Genuinely open with the reason No governing line names the surfaces the runner consulted.
- [ ] An axis marked Genuinely open with the reason Governing lines conflict cites every conflicting line and states what each would require.
- [ ] An axis the runner could not resolve is reported as Genuinely open with the reason Coverage uncertain, naming the citation in doubt — or, where the axis itself is too ambiguous for any citation to be tested against it, naming what is ambiguous about the axis instead. No report resolves an uncertain axis as settled.

### Citations carry a conformance declaration

- [ ] Every citation in an emitted escalation report carries exactly one declaration: Conforms, Departs, or Not yet implemented.
- [ ] A citation declared Departs is accompanied by a plain statement of what the runner's behavior does instead, and is not presented anywhere in the report as support for that behavior.
- [ ] A citation the runner offers in a reply on a review thread carries the same declaration, visible in that reply.
- [ ] Not yet implemented appears only where the cited line governs behavior that does not exist yet. A report never uses it for behavior the runner has already built.
- [ ] Where a departure is reported and conforming to the cited line is the correction, the axis is reported as Settled by specification and the correction is named as the next action — not put to the human as an architecture decision.
- [ ] Where a departure leads the runner to question the cited line itself, that question appears as a separate axis marked Genuinely open, not as an answer to the axis originally raised.
- [ ] Where every axis is Settled by specification and every citation on those axes is declared Not yet implemented, the runner proceeds with the work the cited lines specify and does not raise an `architecture_decision` escalation for that question.

### The requested decision covers only the open axes

- [ ] An emitted report states the decision requested of the human, and that decision names the genuinely open axes.
- [ ] No axis marked Settled by specification appears in the requested decision.
- [ ] A report that contains at least one settled axis and at least one open axis asks the human about the open axis only, and the human can confirm that by reading the report alone.
- [ ] A recommendation, where the report offers one, is labelled as a recommendation and is stated separately from the requested decision.
- [ ] The report does not act on, pre-answer, or ask for ratification of any axis marked Genuinely open.
- [ ] The emitted stop still carries the exact stop condition name, the affected work item, and the concrete human action required. The required human action names the open axes.
- [ ] The report is readable on the work item after the run ends, without opening an agent session transcript.

### The requirement never suppresses a stop

- [ ] The guidance introduced by this feature states that the coverage analysis is a requirement on escalation content and does not change when a runner stops.
- [ ] No guidance introduced by this feature permits a runner to continue past a question it would otherwise have escalated on the grounds that the analysis found axes settled.
- [ ] Where the runner is uncertain whether the cited lines fully answer the question, the guidance requires it to record that uncertainty as an open axis and stop.
- [ ] The named stop conditions, their triggers, and the choice of which condition applies to a question are unchanged by this feature.
- [ ] A question that does not separate into more than one independently answerable component is still reported as one axis — never as zero — per the axis rule in Business Rules. Where what is ambiguous about the question keeps the runner from telling whether any line reaches it, that one axis is marked Genuinely open with the reason Coverage uncertain, and the report names the ambiguity as what is unclear.

### The guidance carries a worked example

- [ ] The guidance includes a worked example in which at least one axis is Settled by specification and at least one is Genuinely open, and the two are visibly distinguished.
- [ ] The worked example shows a citation whose declaration is Departs, and shows that citation not being used as support.
- [ ] The worked example shows an argument attached to an axis other than the one raised, and labelled as such.
- [ ] The example appears alongside the requirement, so a runner reading the requirement reaches the example without following a reference elsewhere.

### Surfaces agree

- [ ] The axis, coverage verdict, open-axis reason, and conformance declaration vocabulary is stated consistently across the canonical guidance and every workflow surface that restates escalation behavior.
- [ ] No workflow surface describes an `architecture_decision` escalation without the coverage analysis as well-formed.
- [ ] No workflow surface states a lighter version of the conformance declaration requirement than the canonical one.
- [ ] The canonical stop-message contract still requires its three existing elements, and no surface presents the escalation report as a replacement for any of them.

---

## Out of Scope (MVP)

1. **Changing when a runner stops.** The recorded defect is in how an escalation is framed, not in the decision to escalate. The `architecture_decision` trigger, the named stop-condition list, and the rule that a repository cannot configure its way out of a stop are all untouched. Deferral rationale: the issue states plainly that stopping was correct in the incident. No human confirmation requested.

2. **Extending per-axis coverage analysis to the other named stop conditions.** `unclear_requirements`, `high_risk_change`, `unresolved_blocking_review`, and the rest keep their current reporting requirements. Deferral rationale: the evidence on record is specific to architecture decisions, and imposing the analysis on every stop would add ceremony where no defect has been observed. No human confirmation requested; a later item can revisit it if the same failure appears elsewhere.

3. **Conformance declarations in source-code comments.** The incident's contradiction first appeared in a code comment quoting the line its own implementation contradicted, so this is a real candidate surface. Deferral rationale: the MVP covers the surfaces a human or reviewer reads when judging a decision — escalation reports and review-thread replies — where a single declaration would have surfaced the same contradiction. Extending it to comments is a code-style requirement with much broader reach. Human confirmation requested.

4. **Automated validation that an escalation report is complete.** The MVP is a guidance requirement that a human can check by reading the report. Deferral rationale: a checker needs a settled report shape to check against, and this spec's vocabulary is that shape's first version. No human confirmation requested.

5. **Changing the existing stop-message contract.** Its three elements keep their current meanings and remain required.

6. **Re-deciding the outcome of the incident that produced this item.** The counter behavior settled on that pull request stands. This item is about how the question should have been presented, not about which answer was right.

7. **Changing how escalations are routed, who is notified, or how a human records an answer.** Only the content of the escalation changes.

8. **Reworking escalations raised before this lands.** The requirement applies to escalations raised from the change forward.

9. **Requiring the runner to resolve a genuinely open axis.** The runner may recommend; deciding stays with the human.
