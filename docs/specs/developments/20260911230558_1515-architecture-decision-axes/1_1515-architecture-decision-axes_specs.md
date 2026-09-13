# Axis-Separated Architecture Decision Escalations — Spec

---

## Overview

When a runner reaches a question it cannot safely answer on its own, it stops the run and hands that question to a human under the `architecture_decision` stop condition. Nothing today requires it to first establish which part of the question the workflow specification already answers. A question with one settled part and one genuinely open part can be handed over whole, as "an open architecture decision", and the human then does the separation work the runner was better placed to do.

This feature defines what a well-formed `architecture_decision` escalation must contain. The runner states the question as it was actually asked, breaks it into axes that can each be answered without answering the others, and for every axis records whether a workflow specification line already settles it — with the citation — or whether it is genuinely open, with the reason the specification does not reach it. Every line the runner cites carries a plain declaration of how the runner's own behavior relates to it: Conforms, Departs, Not yet implemented for behavior not yet built, or — where conformance genuinely cannot be determined — a plain statement saying so. The decision put to the human is then narrowed to the axes that are genuinely open.

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
4. For every line it cites, it declares whether the runner's current behavior Conforms to that line, Departs from it, or is Not yet implemented — or, where conformance genuinely cannot be determined, states that plainly instead, per the malformed-input rule.
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
- Overturn an axis the runner marked settled, by deciding that the cited line should change. That is a different question from the one asked, and it enters as a new axis — Genuinely open with the reason Governing line disputed, carrying a proposed amendment for what the line should become — rather than as an answer to this one.

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
4. Where the departed line's axis is Settled by specification, the runner records the departure as a finding about its own work: either an error to correct by conforming, or a reason to ask whether the line itself should change — which is a separate axis, Genuinely open with the reason Governing line disputed, carrying a proposed amendment for what the line should become. Where the departed line instead belongs to an axis that is already Genuinely open for a different reason — such as a conflict between governing lines, per Use Case 5 — the runner reports the departure as part of that axis instead, and does not yet correct its behavior or dispute the line's substance; that choice waits until the axis itself is decided.

**Postconditions**: The contradiction is visible in the runner's own words, at the moment of citation, rather than being discovered later by a reviewer or a human. No citation stands as support for behavior that contradicts it.

**Information shown**:

- The cited line, the declaration, and — where the declaration is Departs — what the behavior does instead and why.

**Actions available**:

- Read the departure and decide whether the behavior or the line is the thing that should change.

**Considerations**:

- The declaration is required in the two surfaces this feature covers — an escalation report and a reply on a review thread — not only inside an escalation report. A review-thread reply is exactly such a surface: a reviewer reads it directly, often before any escalation report exists. A citation in other human-readable rationale, such as a planning artifact, is outside this feature's scope.
- Declaring Departs is not by itself an architecture decision. Where conforming to the cited line is the obvious correction, the axis is settled and the correction is the next action.
- Not yet implemented exists for citations made before the behavior is built — during planning, or about work not yet started. It is never used to avoid declaring a departure in behavior that does exist.

---

### Use Case 4: The operator reads the stop and decides

**Actor**: The operator — the human the run stopped for.
**Preconditions**: A run has stopped under `architecture_decision` and its escalation report is available in the run summary the operator reads, per the existing stop-message contract, and additionally as a durable record on the work item's pull request when one exists.

**Steps**:

1. The operator reads the question as asked and the axes it was broken into.
2. For each settled axis, the operator checks the citation against the axis.
3. For each open axis, the operator reads the reason and decides.
4. The operator records the decision where the runner or the next run will read it.

**Postconditions**: The decision covers the open axes. The operator did not have to reconstruct the decomposition, locate the governing lines, or work out which axis the runner's arguments were about.

**Information shown**:

- The whole report, available in the run summary per the existing stop-message contract, and — where a pull request exists — durable on it, readable after the run ends without opening a session transcript.

**Actions available**:

- Decide the open axes.
- Send the report back as incomplete, naming the missing element.
- Decide that a settled axis should be reopened by changing the cited line, which the next report carries as a new axis under the reason Governing line disputed, with a proposed amendment.

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
- Every Genuinely open axis carries exactly one reason, drawn from the defined reason vocabulary, and the reason is substantiated by what the runner looked for, found, or would change — never merely asserted.
- Where the reason is **No governing line**, the report names the surfaces the runner consulted. An unsearchable claim of absence is not a reason.
- Where the runner cannot tell whether a line reaches an axis, the axis is Genuinely open with the reason **Coverage uncertain**, and the uncertainty is stated as such. Uncertainty is never resolved in favour of settled.
- Where a cited line reaches and covers an axis, and the runner is not uncertain about that, but the runner judges the line's substance to be wrong, that dispute is a new axis, stated separately, Genuinely open with the reason **Governing line disputed**, and the report states a proposed amendment: what the line should become instead. It does not reclassify the axis the line settles; that axis keeps its own coverage verdict, reported together with the conformance declaration against the disputed line. The proposed amendment is required — disputing a line's substance without stating what it should instead say is not a valid use of this reason.
- A citation's substance can also be one that a reviewer or a human has actually put in question without the runner reaching either conclusion available to it: the runner does not judge the line's substance wrong, per the rule above, and it cannot confirm the line's substance is right either. This is not a sixth Genuinely open reason on the citation's axis — deferred for this MVP, Out of Scope item 10 — because the runner has not departed from the line and has no proposed amendment to offer; forcing the case into Governing line disputed would misstate what happened. Where nobody has raised the question, the citation's axis proceeds unquestioned under the settled-axis rules below, exactly as if the judgment had never been formed. Where the question has actually been raised, by a reviewer or a human, and the runner genuinely cannot resolve it, that silence does not apply: a live, unresolved question is a question the runner cannot safely answer alone, and it routes to the `architecture_decision` stop condition directly, under its own unchanged predicate, rather than through this feature's per-axis reason vocabulary.
- Every citation the runner offers in an escalation report or in a reply on a review thread carries a **conformance declaration**: Conforms, Departs, or Not yet implemented. These are the two surfaces this feature covers — anywhere within either that the runner offers a citation as support for a decision a human or reviewer will weigh. A citation in other human-readable rationale, such as a planning artifact, is outside this feature's scope. The one exception is a citation whose conformance genuinely cannot be determined — for behavior that already exists, or because the runner cannot even establish whether the cited line's governed behavior exists yet: that citation carries none of the three declarations. In an escalation report, the report is instead governed by the malformed-input rule in the Decision-Gate Consistency Matrix, which reports the escalation as incomplete rather than well-formed. In a standalone review-thread reply offered outside a full escalation report, the reply states plainly that conformance could not be determined and why, using none of the three declarations, without that alone opening a full `architecture_decision` escalation — the malformed-input rule governs only once that citation's axis is later escalated in a full report.
- A citation whose declaration is Departs is never presented as support for the current behavior. The report states the departure plainly, in the runner's own words, before it asks the human anything.
- A departure is a finding about the runner's own work. It is either an error to correct by conforming to the cited line, or a reason to ask whether the line should change. The second is a new axis, stated separately, Genuinely open with the reason Governing line disputed, and it carries a proposed amendment stating what the line should become. This correct-or-dispute choice applies only where the departed citation's own axis is Settled by specification. Where the departed citation instead belongs to an axis that is already Genuinely open for a different reason — most often Governing lines conflict, per Use Case 5 — correcting to conform would mean departing from whichever other conflicting line the axis has not yet ruled out, and disputing the departed line's substance would prejudge which line governs before the human decides. Neither is required: the departure is reported as part of that already-open axis, exactly as Use Case 5 describes, and correction or a substance dispute on that citation waits until the axis itself is decided.
- Every argument the runner offers is attached to exactly one axis. An argument that addresses a different axis than the one raised is labelled as such and is not presented as an answer to the question asked.
- The **requested decision** covers the genuinely open axes only. Settled axes are reported for checking and are never included in what the human is asked to decide.
- The runner may state a recommendation for an open axis. A recommendation is labelled as one, never presented as the answer, and never narrows the decision the human can make.
- The report never decides an open axis, never proceeds on a provisional answer to one, and never asks the human to ratify an action already taken on one.
- This requirement is a precondition on the **content** of an `architecture_decision` escalation, not on the decision to stop. It adds no new grounds for stopping and removes none. It never authorizes a runner to continue past a question that requires a human decision. Where the runner was about to stop and the coverage analysis then finds every axis settled with a determined, undisputed declaration and no uncertainty, that stop was never genuinely required: the analysis has shown the trigger's own precondition was not met, per the rule below. Continuing past a provisional, about-to-stop judgment the analysis shows was mistaken is not removing a stopping ground this rule protects — only a stop the analysis confirms was genuinely required is protected from removal.
- The coverage analysis is not a way to suppress a stop. Where every axis comes back Settled by specification and the runner is nonetheless unsure whether the cited lines fully answer the question, that uncertainty is itself an open axis and the runner stops.
- Where every axis is settled, every citation on those axes carries a determined declaration of Conforms or Not yet implemented, the runner is not uncertain, and the runner does not dispute any citation's substance, the work does not require a human decision and the `architecture_decision` condition's own trigger is not met. Applying the cited lines is what the specification already required; recognizing that is not a relaxation of the stop condition. A citation whose conformance could not be determined is not covered by this rule; the malformed-input rule governs that case instead, and it never permits continuing. This is not an exception carved out of the canonical `architecture_decision` predicate — it is an instance of it: whether to trust, block on, or otherwise handle a citation whose relationship to the runner's own behavior cannot be established is exactly the kind of choice a runner cannot safely make unaided, the same way an uncertain coverage determination already is. A disputed citation is not covered by this rule either, even where it Conforms or is Not yet implemented: the dispute opens a new Genuinely open axis, per Business Rules above, and the run stops for that axis exactly as it would for any other genuinely open axis. Nor is a citation whose substance a reviewer or a human has actually put in question and that the runner genuinely cannot resolve either way: that live, unresolved question is not covered by "the runner does not dispute any citation's substance" above merely because the runner formed no affirmative wrongness judgment. It routes to `architecture_decision` directly instead, per the routing rule above, rather than letting the citation's axis proceed as though the question were never asked.
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
| Governing line disputed             | This axis is the dispute itself — a separate axis from the one the cited line settles, never a reclassification of it. It applies where a line reaches and covers that other axis, and the runner is not uncertain about that coverage, but judges the line's substance to be wrong; the other axis keeps its own coverage verdict. Reported with the citation and a proposed amendment stating what the line should become instead. A proposed amendment is required; disputing a line without one is not a valid use of this reason. |

A citation's substance can also be one nobody — including the runner — can resolve: coverage is certain, there is no conflict, and the runner can neither conclude the line's substance is wrong nor confirm it is right. This is not a sixth reason (Out of Scope, item 10; Business Rules above). Where the question has actually been raised, by a reviewer or a human, and the runner genuinely cannot resolve it, it routes to the `architecture_decision` stop condition directly, under its own unchanged predicate, rather than through this table.

Conformance declaration, recorded with every citation:

| Display label       | Description                                                                                                                            |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Conforms            | The runner's current behavior matches the cited line.                                                                                   |
| Departs             | The runner's current behavior does not match the cited line. Reported with what the behavior does instead and why.                       |
| Not yet implemented | The cited line governs behavior that does not exist yet, so there is nothing to conform to or depart from. Never used where behavior exists. |

The one exception is a citation whose conformance genuinely cannot be determined — for behavior that already exists, or because the runner cannot even establish whether the cited line's governed behavior exists yet: it carries none of the three declarations above. In an escalation report, that case is governed by the malformed-input rule in the Decision-Gate Consistency Matrix, not by this table; in a standalone reply on a review thread, offered outside a full escalation report, the reply states the same thing plainly instead, without that alone opening a full escalation, per Business Rules.

---

## Operational Visibility

- **Escalation report**: emitted wherever the stop itself is reported — in the run summary the operator reads, per the existing stop-message contract, and as a durable record on the work item's pull request when one exists. This feature changes only the report's content, not where it is routed (Out of Scope, item 7): it adds no new durable destination for a run that stops before any pull request exists; that report's durability remains whatever the existing stop-message contract already provides. Where a pull request exists, the report is readable on it without opening an agent session transcript.
- **Stop message**: unchanged in its three existing elements. For a complete report, the required human action names the genuinely open axes — and, separately, any conformance evidence to supply — rather than the question as a whole. For an incomplete report under the malformed-input rule, the required human action instead supplies what that rule names — the missing question or its source, a redone decomposition, or the missing conformance evidence — since such a report may have no open axis yet to name.
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
| Whether the runner judges a covered, non-uncertain citation's substance to be correct | The runner's own judgment of the cited line, distinct from whether its behavior conforms to it | **Added by this feature.** A citation the runner judges wrong opens a new dispute axis instead of leaving the axis it covers unquestioned. This judgment has no separate "cannot determine" reason within this feature's own vocabulary — a sixth reason for it is deferred, Out of Scope item 10 — so absent an affirmative conclusion that the line's substance is wrong, the axis the line covers is unquestioned and proceeds under the settled-axis rules exactly as if the judgment had never been made. That default holds only where nobody raised the question. Where a reviewer or a human actually put a covered, non-uncertain citation's substance in question and the runner genuinely cannot resolve it, the question does not fall into that default; it routes to `architecture_decision` directly instead, per Business Rules above |

### Triggers

Triggers are events. They decide when this gate runs, and none of them is read as an input.

| Trigger                                                                          | Why it fires                                                                                |
| -------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| The runner is about to stop under `architecture_decision`                        | The gate's normal entry point                                                                |
| A reviewer finding asks the runner to change behavior the specification may govern, and the runner has independently judged — under the unchanged `architecture_decision` predicate — that the question needs a human decision | The case where a settled axis is most likely to be mistaken for an open one. This trigger never substitutes for that predicate: a reviewer finding the specification does not happen to cover is not, by itself, an architecture decision — an ordinary review comment stays ordinary review handling. The coverage analysis that follows only narrows or settles a question the runner was already going to escalate; it never manufactures a new one |
| The runner is about to cite a workflow specification line in an escalation report or a reply on a review thread | Fires the conformance declaration alone, without requiring a full escalation report          |
| A previously escalated item is resumed and the question is still open            | The report is restated for the question as it now stands, rather than reused unexamined      |
| A reviewer or a human has put a covered, non-uncertain citation's substance in question, and the runner genuinely cannot resolve it either way | The question is one the runner cannot safely answer alone, the same as any other question that fires this condition. It is governed by the unchanged `architecture_decision` predicate directly — not by this feature's per-axis reason vocabulary, per Business Rules above and Out of Scope, item 10 |

The first trigger names the moment the coverage analysis runs, not a decision already final. It fires while the runner is preparing to stop — before the report is written and the stop is presented to the human — so the analysis is part of establishing whether `architecture_decision`'s own precondition, a question the specification does not already answer, is actually met. Where the analysis finds any axis genuinely open, or any uncertainty about one, the stop proceeds exactly as the runner was about to make it; the analysis has only ever narrowed or formatted the report from there, per the Business Rules above, and never cancels that stop. Where the analysis instead finds every axis settled with no uncertainty, it has shown that no genuinely unanswered question exists — the precondition for `architecture_decision` was never actually met — so applying the cited lines and continuing is not a runner overriding an already-decided stop; there is nothing left in this determination for a human to decide. This holds only where every citation on those settled axes carries a determined declaration, Conforms or Not yet implemented; a citation whose conformance could not be determined instead fails the malformed-input rule below, which the runner checks first and which never permits continuing.

### Allowed outcomes and required next actions

| Inputs                                                                         | Outcome                     | What the runner does                                                                                     | Operator's next action                                          |
| ------------------------------------------------------------------------------ | --------------------------- | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Every axis Genuinely open                                                      | Escalated                   | Stops with a report listing each axis, its reason, and a requested decision covering all of them           | Decide the open axes                                             |
| At least one axis settled, at least one open                                   | Escalated, scope narrowed   | Stops with the settled axes cited and the requested decision covering the open ones only                   | Decide the open axes; the settled ones need no answer            |
| Every axis settled, no citation on those axes Departs, at least one Conforms (the rest, if any, Not yet implemented), the runner is not uncertain, and no reviewer or human has raised a citation's substance in question that the runner cannot resolve | Not an architecture decision, unless the runner disputes any citation's substance or a raised substance question remains unresolved | Applies the cited lines and continues; no human decision was required — unless the runner affirmatively judges any citation's substance wrong, whether that citation Conforms or is Not yet implemented, in which case it keeps that citation's own declaration as stated, opens a new axis — Genuinely open with the reason Governing line disputed and a proposed amendment — asking whether the line should change, and stops pending that decision instead of continuing; or, where a reviewer or human raised a citation's substance in question and the runner genuinely cannot resolve it, stops under `architecture_decision` directly for that question instead of continuing, per Business Rules above | None, unless a new axis was opened, or a raised substance question remains unresolved — then decide that axis or answer the question |
| Every axis settled, the runner's behavior departs on at least one              | Departure reported          | States each departure plainly. For each departed citation independently, the runner either conforms, or opens a new axis — Genuinely open with the reason Governing line disputed and a proposed amendment — asking whether that line should change; different departed citations in the same report can resolve differently, one corrected and another disputed | None, unless at least one new axis was opened — then decide each opened axis |
| Every axis settled, but the runner is unsure the lines fully answer the question | Escalated                   | Records the uncertainty as an open axis with the reason Coverage uncertain, and stops                      | Decide the uncertain axis                                        |
| Lines bearing on one axis conflict                                             | Escalated                   | Reports the axis as open with every conflicting citation and what each requires                            | Decide which line governs                                        |
| The question does not separate into more than one independently answerable component, and that one axis is Genuinely open | Escalated                   | Reports the whole question as one axis, per the axis rule in Business Rules — never as zero axes. Where what is ambiguous about the question itself keeps the runner from telling whether any line reaches it, marks that one axis Genuinely open with the reason Coverage uncertain, and states the ambiguity as what is unclear | Decide the axis, or restate the question so the runner can attempt coverage again |
| Every axis settled, coverage certain, every citation on those axes is Not yet implemented, and no reviewer or human has raised a citation's substance in question that the runner cannot resolve | Not an architecture decision, unless the runner disputes a citation's substance or a raised substance question remains unresolved | Proceeds with the work as the cited lines already specify. There is no departure to declare, because the behavior does not exist yet to conform or depart — unless the runner affirmatively judges a citation's substance wrong even though nothing has been built yet, in which case it opens a new axis — Genuinely open with the reason Governing line disputed and a proposed amendment — asking whether the line should change, and stops pending that decision instead of proceeding; or, where a reviewer or human raised a citation's substance in question and the runner genuinely cannot resolve it, stops under `architecture_decision` directly for that question instead of proceeding, per Business Rules above | None, unless a new axis was opened, or a raised substance question remains unresolved — then decide that axis or answer the question |
| A citation is offered in a reply on a review thread, outside an escalation report, and its conformance can be determined | Declaration required        | Attaches Conforms, Departs, or Not yet implemented to that citation in place                                | None                                                             |
| A citation is offered in a reply on a review thread, outside an escalation report, and the runner cannot determine its conformance | Declaration required, undetermined | States plainly, in that reply, that conformance could not be determined and why — using none of the three declarations, the same content the malformed-input rule requires of such a citation — without opening a full `architecture_decision` escalation for it, since this trigger fires the declaration alone and does not require a full report | None, unless the axis that citation bears on is later escalated in a full report — the malformed-input rule governs it there |

Exactly one row applies to any question. Four rows above leave every axis settled: the runner conforms on every citation, the runner's behavior departs on at least one, every citation on those axes is Not yet implemented, and the runner is unsure the cited lines fully answer the question. The first three of those four read the same way whether the settled axis is the question's only axis or one among several, reaching Not an architecture decision, Departure reported, and Not an architecture decision respectively either way. A citation set that mixes Conforms and Not yet implemented, with no Departs among them, is read by the conforms row: nothing has departed, and the all-Not-yet-implemented row is reserved for the case where nothing cited has been built at all.

The fourth of those four — the runner is unsure the cited lines fully answer the question — does not stay all-settled once it fires: recording that uncertainty adds a new axis, Genuinely open with the reason Coverage uncertain. That gives the question the same settled-and-open shape as "At least one axis settled, at least one open," and it is the uncertainty row, not the general one, that applies to it, because the uncertainty row names the reason the general row does not. The outcome is the same either way — Escalated, with the decision scope narrowed to the open axis by the settled ones — so naming the more specific row changes what the report says about that axis, not which outcome it reaches. This precedence holds as long as the uncertainty axis is the report's only reason for being open; where it coexists with an axis or citation governed by a different specific reason, the composition rule below applies instead.

The same precedence holds for "Lines bearing on one axis conflict": whenever an axis's open reason is a conflict between governing lines, that axis is read by the conflict row rather than by "Every axis Genuinely open" or "At least one axis settled, at least one open" — whichever axis count alone would otherwise suggest — because the general rows do not distinguish reasons and the conflict row supplies the citation-by-citation content the report needs. The "Every axis Genuinely open" row and the "Lines bearing on one axis conflict" row are for questions with more than one axis. Where a question does not separate into more than one axis at all, its single axis is read instead by the row for a question that does not separate when Genuinely open, and by the settled-axis rows above when settled — never by those two multi-axis rows, even where that single axis's open reason is itself a conflict between governing lines: the report still carries every conflicting citation and what each requires, because that content requirement belongs to the Governing lines conflict reason itself, per its definition in Statuses / Enum Values, not to the multi-axis conflict row's outcome label. As with the uncertainty row, this precedence holds only while the conflict axis is the report's only reason for being open; the composition rule below governs where it is not.

The departs row carries the same precedence when its second branch fires. Opening a new axis — Genuinely open with the reason Governing line disputed and a proposed amendment — to ask whether the cited line should change gives the question the same settled-and-open shape as "At least one axis settled, at least one open" too, but that new axis is still read by the departs row that produced it, not by the general row: the departs row already names what the new axis asks and what the operator does about it, which the general row does not. The general row governs axes that arrived open from the initial decomposition; it does not re-govern an axis a departure produced. This too holds only while the dispute axis is the report's only reason for being open beyond what the initial decomposition already settled; the composition rule below governs where it is not.

The conforms row and the all-Not-yet-implemented row carry the same second-branch precedence. A runner can affirmatively judge a citation's substance wrong while still conforming to it, or while nothing governed by it has been built yet — the departure row's dispute branch is not the only way that judgment arises. Where it does, the new dispute axis it opens is read by whichever row's branch produced it, not by the general row, for the same reason the departs row's dispute axis is: the row already names what the new axis asks and what the operator does about it.

These precedence rules compose according to one general principle whenever a report ends up with axes or citations governed by **more than one** specific reason at once — for example, a departure on a settled axis found alongside an axis that was already open from the initial decomposition, a departure's dispute axis arising alongside a separate meta-uncertainty axis in an initially all-settled decomposition where the runner is also unsure the cited lines fully answer the question, or a conflict axis found during decomposition alongside a departure on a different, settled axis. In every such case, no single specific-reason row describes the whole report: the report's outcome label is read from whichever general axis-count row matches its settled/open split — "Every axis Genuinely open" if none remain settled, or "At least one axis settled, at least one open" otherwise — while every specific-reason row present still supplies the content required for the axis or citation it concerns, exactly as described above. This is how a departure composes with an already-mixed decomposition: the mixed-axis row supplies the outcome label because the escalation is already required independent of the departure, and the departs row's content still governs the settled axis the departure concerns. Only where every axis in the decomposition is settled, and the report's sole reason for containing an open axis is the one specific-reason row that fired, does that row decide the outcome on its own — Departure reported, or Escalated with that row's named reason — because no other axis already requires escalation. The requested decision spans every open axis the report ends up with, however many specific reasons produced them.

No outcome above answers an open axis, acts on a provisional answer to one, or asks the human to ratify an action already taken on one. No outcome changes which stop condition applies to a question, and none suppresses a stop the runner would otherwise have taken.

### Malformed or missing gate inputs

The outcomes above assume each gate input in the Gate inputs table could actually be established. Where establishing one of them fails outright, none of the outcomes above apply; the rows below govern instead, and every one of them fails closed — the escalation is reported as incomplete rather than presented as well-formed, and the runner never treats a missing or malformed input as grounds to skip the stop.

| Missing or malformed input                                                                              | Outcome                        | What the runner does                                                                                                                    | Operator's next action                                                        |
| --------------------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| The question as raised, or its source, cannot be established                                             | Escalated, incomplete           | Stops under `architecture_decision` regardless, records that the question or its source is missing, and does not present the report as complete | Supply the missing question or its source; the escalation cannot close until it does |
| The axis decomposition produces no axis at all                                                           | Escalated, incomplete           | Stops, records that decomposition produced zero axes — which the axis rule in Business Rules never allows, since inseparable components are one axis, not none — and treats this as a defect in the escalation rather than a valid outcome | Have the runner redo the decomposition; at least one axis is required before the report stands |
| A citation's conformance cannot be determined — including where the runner cannot even establish whether the governed behavior exists yet, which is itself a form of undetermined conformance | Escalated, conformance undetermined | Does not declare Conforms, Departs, or Not yet implemented, since choosing among them requires knowing whether the behavior exists. States plainly that conformance — including whether the behavior exists — could not be determined and why. Coverage and conformance are separate gate inputs: the axis that citation settles keeps its Settled by specification coverage verdict — an undetermined conformance does not reopen a coverage question the runner already answered | Supply what would let the runner determine conformance, including whether the behavior exists; the coverage verdict itself needs no decision |

These three rows are read in the order listed, because the second and third presuppose what the first checks: decomposition has nothing to decompose until the question and its source are established, and a citation's conformance has nothing to be undetermined about until an axis exists for it to settle. Where the question or its source cannot be established at all, that state is read by the first row alone, not by the second row's zero-axes case as well, even though no axis exists yet in either state.

None of these three rows produces "Not an architecture decision" or any other outcome that lets the run apply the cited lines and continue unaided. What's required from the operator differs by row: the first two require correcting the escalation's content — supplying the missing question or its source, or a redone decomposition — while the third requires supplying evidence rather than deciding anything, per its own Operator's next action above. None of the three is a case the runner resolves on its own.

A report can combine the third row with the settled-axis and open-axis outcomes above: a decomposition can have one axis whose citation's conformance is undetermined alongside other axes that are genuinely open (including an axis whose open reason is Governing lines conflict, if one of the conflicting citations is itself undetermined — the axis keeps its Genuinely open verdict and conflict content while the undetermined citation separately requests evidence), settled with a determined declaration, or subject to a departure. Where it does, the report is incomplete rather than well-formed — the third row's own outcome governs — and the report states the genuinely open axes' requested decision, if any, alongside a separately reported request for the missing conformance evidence for each axis the third row applies to; the evidence request is never merged into the requested decision itself.

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
| A line reaches and covers the axis, the runner is not uncertain, but judges the line's substance wrong          | The axis the line covers stays Settled by specification; a new, separate axis is Genuinely open — Governing line disputed | The citation, and a proposed amendment stating what the line should become instead                                   |
| A line reaches and covers the axis, the runner is not uncertain about coverage, a reviewer or human has asked whether the line's substance is right, and the runner genuinely cannot tell either way | The axis the line covers stays Settled by specification; the question is out of scope for this feature's reason vocabulary (Out of Scope, item 10) | The raised, unresolved question routes to `architecture_decision` directly, under its own unchanged predicate — never treated as a sixth reason, and never treated as though no question had been asked |
| A citation about behavior the plan has not built yet                                                            | Not yet implemented                           | The declaration says so; it is not used where the behavior exists                                                    |
| Every axis settled, the runner conforms, no uncertainty, and the runner does not dispute the citation's substance — and nobody has raised an unresolved substance question the runner cannot answer | No escalation                                 | The runner applies the cited lines; there was no architecture decision to make                                       |
| Every axis settled, coverage certain, every citation is Not yet implemented — nothing cited has been built yet — and the runner does not dispute the citation's substance — and nobody has raised an unresolved substance question the runner cannot answer | No escalation                                 | The runner proceeds to build what the cited lines specify; there is no departure to declare, because there is no behavior yet to conform or depart                       |

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

- [ ] A complete emitted `architecture_decision` escalation report states the question as it was asked and names who or what raised it. Where the question or its source cannot be established, the report instead records that fact and is reported as incomplete, per the malformed-input rule.
- [ ] A complete report lists the axes the question was separated into. A question with one axis lists one; a question with more lists each of them. Where decomposition produces no axis at all, the report instead records that defect and is reported as incomplete, per the malformed-input rule.
- [ ] Each listed axis is stated so that a reader can answer it without answering any other listed axis.
- [ ] No axis in an emitted report carries more than one coverage verdict. An axis the specification settles only in part appears as two or more axes, each with one verdict.
- [ ] Each argument the report offers names the one axis it addresses. An argument about a different axis than the one raised is labelled as addressing that other axis.

### Every axis carries a verdict

- [ ] Every axis in an emitted report carries exactly one coverage verdict: Settled by specification or Genuinely open.
- [ ] Every axis marked Settled by specification carries a citation identifying a specific workflow specification line, and says how that line answers the axis.
- [ ] Every axis marked Genuinely open carries exactly one reason: No governing line, Governing lines conflict, Governing line covers a different case, Coverage uncertain, or Governing line disputed.
- [ ] An axis marked Genuinely open with the reason No governing line names the surfaces the runner consulted.
- [ ] An axis marked Genuinely open with the reason Governing line covers a different case carries the citation the runner found and states why that line governs a different case rather than reaching this axis.
- [ ] An axis marked Genuinely open with the reason Governing lines conflict cites every conflicting line and states what each would require.
- [ ] An axis whose coverage the runner cannot tell — whether a candidate line actually reaches or applies to it — is reported as Genuinely open with the reason Coverage uncertain, naming the citation in doubt — or, where the axis itself is too ambiguous for any citation to be tested against it, naming what is ambiguous about the axis instead. This is distinct from a confirmed conflict between governing lines, which carries the reason Governing lines conflict instead. No report resolves an uncertain axis as settled.
- [ ] An axis marked Genuinely open with the reason Governing line disputed carries the citation and a proposed amendment stating what the cited line should become instead. The reason is never used without a proposed amendment, and it is reported as a new axis separate from the axis the disputed line settles.

### Citations carry a conformance declaration

- [ ] Every citation in a complete emitted escalation report carries exactly one declaration: Conforms, Departs, or Not yet implemented. The one exception — a citation whose conformance cannot be determined — is covered by its own criterion below and does not count as a fourth declaration.
- [ ] Where a citation's conformance cannot be determined — for behavior that already exists, or because the runner cannot even establish whether the governed behavior exists yet — the report declares neither Conforms, Departs, nor Not yet implemented for that citation. It states plainly that conformance could not be determined and why, and the escalation is reported as incomplete rather than presented as well-formed, per the malformed-input rule. The axis that citation settles keeps its Settled by specification coverage verdict; coverage and conformance are separate gate inputs, and an undetermined conformance does not reopen a coverage question the runner already answered.
- [ ] A citation declared Departs is accompanied by a plain statement of what the runner's behavior does instead, and is not presented anywhere in the report as support for that behavior.
- [ ] A citation the runner offers in a reply on a review thread carries the same declaration, visible in that reply — or, where its conformance cannot be determined, that reply states so plainly instead, using none of the three declarations, without opening a full `architecture_decision` escalation for that citation on that account.
- [ ] Not yet implemented appears only where the cited line governs behavior that does not exist yet. A report never uses it for behavior the runner has already built.
- [ ] Where a departure is reported and conforming to the cited line is the correction, the axis is reported as Settled by specification and the correction is named as the next action — not put to the human as an architecture decision.
- [ ] Where a departure leads the runner to question the cited line itself, that question appears as a separate axis marked Genuinely open with the reason Governing line disputed, carrying a proposed amendment, not as an answer to the axis originally raised.
- [ ] Where the runner affirmatively judges a citation's substance wrong while still Conforming to it, or while the citation is declared Not yet implemented, that dispute is not silently dropped: it appears as the same separate Genuinely open axis with the reason Governing line disputed, carrying a proposed amendment, exactly as it would if the citation had instead been declared Departs.
- [ ] Where every axis is Settled by specification and every citation on those axes is declared Not yet implemented, and the runner does not dispute any of those citations' substance, the runner proceeds with the work the cited lines specify and does not raise an `architecture_decision` escalation for that question — unless a reviewer or a human has raised an unresolved substance question about one of those citations that the runner cannot answer, in which case the routing rule in Business Rules applies instead.

### The requested decision covers only the open axes

- [ ] Where an emitted report contains at least one genuinely open axis, it states the decision requested of the human, and that decision names the genuinely open axes only. Where every axis is settled but a citation's conformance could not be determined, the report requests no decision — since there is no open axis to decide — and instead separately states, as its own element, a request for the missing conformance evidence; the axis that citation was meant to settle stays Settled by specification and is never listed as genuinely open on that account.
- [ ] No axis marked Settled by specification appears in the requested decision.
- [ ] A report that contains at least one settled axis and at least one open axis asks the human about the open axis only, and the human can confirm that by reading the report alone. A separately reported conformance-evidence request, where one applies, is additional to the requested decision and does not count as asking about a settled axis.
- [ ] A recommendation, where the report offers one, is labelled as a recommendation and is stated separately from the requested decision.
- [ ] The report does not act on, pre-answer, or ask for ratification of any axis marked Genuinely open.
- [ ] The emitted stop still carries the exact stop condition name, the affected work item, and the concrete human action required. Where the report has at least one genuinely open axis, the required human action names those axes and, separately, any conformance evidence to supply for an axis whose citation's conformance could not be determined. Where the report is incomplete under the malformed-input rule and has no open axis to name — the question or its source could not be established, decomposition produced no axis, or every axis is settled but a citation's conformance could not be determined — the required human action instead supplies what that rule names: the missing question or its source, a redone decomposition, or the missing conformance evidence.
- [ ] Where the escalation occurs on a pull request, the report is readable on that pull request after the run ends, without opening an agent session transcript. Durability for a run that stops before any pull request exists is whatever the existing stop-message contract already provides; this feature adds no new routing for that case (Out of Scope, item 7).

### The requirement never suppresses a stop

- [ ] The guidance introduced by this feature states that the coverage analysis is a requirement on escalation content and does not change when a runner stops.
- [ ] No guidance introduced by this feature permits a runner to continue past a question it would otherwise have escalated merely because the analysis found axes settled. The cases where continuing is correct — every axis settled, every citation on those axes carrying a determined declaration of Conforms or Not yet implemented (never Departs, and never a citation whose conformance could not be determined), the runner is not uncertain whether the cited lines fully answer the question, the runner does not dispute any citation's substance, and nobody has raised an unresolved substance question the runner cannot answer — are not suppression: per Business Rules, the `architecture_decision` trigger was never actually met in those cases, because applying the cited lines is what the specification already required. A disputed citation stops the run for the new axis the dispute opens, even where it Conforms or is Not yet implemented. A citation's substance a reviewer or human has raised and the runner genuinely cannot resolve stops the run under `architecture_decision` directly, per Business Rules and the criterion below, rather than being absorbed into this rule's silence.
- [ ] Where the runner is uncertain whether the cited lines fully answer the question, the guidance requires it to record that uncertainty as an open axis and stop.
- [ ] The named stop conditions, their triggers, and the choice of which condition applies to a question are unchanged by this feature.
- [ ] A question that does not separate into more than one independently answerable component is still reported as one axis — never as zero — per the axis rule in Business Rules. Where what is ambiguous about the question keeps the runner from telling whether any line reaches it, that one axis is marked Genuinely open with the reason Coverage uncertain, and the report names the ambiguity as what is unclear.
- [ ] Where a reviewer or a human has put a covered, non-uncertain citation's substance in question and the runner genuinely cannot resolve it either way, that question is not silently absorbed into "the runner does not dispute any citation's substance" just because the runner formed no affirmative wrongness judgment. It is not represented as a sixth Genuinely open reason either (Out of Scope, item 10). It routes to the `architecture_decision` stop condition directly, under its own unchanged predicate, rather than through this feature's per-axis reason vocabulary.

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

10. **A sixth Genuinely open reason for a citation whose coverage is certain, with no conflict, and whose substance the runner can neither confirm nor conclude is wrong.** Deferral rationale: the five reason values, together with the conformance declarations they compose with, answer the question "why did you depart from this cited line" — they are departure reasons. A runner that cannot determine whether a covered, undisputed line is substantively correct is not departing from it; it is conforming while holding an open question, and representing that state as a departure reason would be a category error. The asymmetry with Governing line disputed demonstrates it: that reason requires both an affirmative judgment that the line's substance is wrong and a concrete proposed amendment for what it should become instead, and a genuinely undetermined runner can honestly supply neither. Deferring the sixth value does not leave this case unhandled: where the question has actually been raised, by a reviewer or a human, and the runner genuinely cannot resolve it, the question routes to the existing `architecture_decision` stop condition, governed by that predicate directly — per Business Rules and Statuses / Enum Values above — rather than through this feature's per-axis reason vocabulary, and it is never treated as though no dispute existed. No human confirmation requested; decided in review of this item.
