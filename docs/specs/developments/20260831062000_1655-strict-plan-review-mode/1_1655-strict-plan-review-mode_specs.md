# Strict Implementation-Plan Review — Spec

**Depends on**: 1653-split-reviewer-prompts-by-stage, 1650-strict-spec-contract-review

---

## Overview

An implementation plan fails differently from a specification. It can cover every acceptance criterion and still name no test that would fail if one were unmet. It can list steps in an order where one consumes what a later step produces. It can depend on another item without saying whether that item is merged, or what happens if it is not. It can change persisted data or a published contract and never say how the change is undone. And it can carry a step that nothing in the source asked for, which then gets built because it is in the plan and was never specified anywhere.

The local reviewer already has a Plan Review Checklist in `REVIEW.md` and applies it as one section of a long contract. This feature gives the plan stage a **stricter checklist** — seven questions, each asked on its own — and has the reviewer report what it found as **labelled, non-blocking findings**, together with **which of the seven were applied**.

This is #1650's design at the plan stage, and it is deliberately the same design rather than a variation: same three states, same non-blocking rule, same per-pull-request incidence. What it adds is coverage. The plan checks need something the spec checks did not — the plan's own source of truth — and that source is not always reachable, so a round can apply four of the seven rather than all seven. A count that does not say how many checks produced it is not a rate, so the applied set is reported alongside the count.

---

## Issue-Objective Traceability

Every objective stated in issue #1655 maps to acceptance criteria and use cases here, or to an explicit entry under **Out of Scope (MVP)** with a deferral note. No objective is dropped.

| # | Objective (from #1655) | Where it is satisfied |
| --- | --- | --- |
| 1 | *Problem* — a generic local reviewer misses plan-specific defects | Use Cases 1 and 2; AC-1, AC-2 |
| 2 | *Outcome* — the local reviewer applies a plan checklist before expensive reviewers run | Use Case 1; AC-1, AC-3, AC-14 |
| 3 | *Scope* — verify plan traceability to the approved spec or refactor brief | Checks 1, 2 and 3 in Statuses / Enum Values; AC-4, AC-5, AC-6 |
| 4 | *Scope* — check test coverage against acceptance criteria | Check 4; AC-7 |
| 5 | *Scope* — flag phase ordering gaps | Checks 5 and 6; AC-8, AC-9 |
| 6 | *Scope* — flag unclear rollback/migration risk | Check 7; AC-10 |
| 7 | *Scope* — flag implementation hidden in plan-only pull requests | Check 2 for the document-level case (AC-5); the file-level case is already gated deterministically — see **Relationship to checks that already exist** |
| 8 | *Scope* — emit checklist coverage in the summary | Use Case 3; AC-17, AC-18, AC-19, AC-19b, AC-19c |

---

## Relationship to checks that already exist

Two surfaces already ask some of these questions, and this feature neither replaces nor weakens either of them.

**The Plan Review Checklist in `REVIEW.md`** already asks, in eighteen top-level items, that every acceptance criterion be addressed, that ordering be feasible and dependencies explicit, and that testing map back to acceptance criteria. Those items stay exactly as they are, and the findings they produce stay **blocking** exactly as they are today. The strict checks ask sharper versions of some of the same questions — one at a time, each carrying an identifier — and their findings are non-blocking.

The same defect can therefore be reported twice on one review: once as an ordinary blocking finding and once as a labelled strict finding. **That duplication is expected and permitted.** A strict finding's non-blocking status says nothing about the ordinary finding beside it: it does not downgrade it, resolve it, or excuse it. Anyone reading "non-blocking" as a relaxation of the existing checklist has read this feature backwards — the point of non-blocking is that the *new* questions can be sharp without a miscalibrated one being able to stop a pull request before anyone knows how often it fires.

**`check-documentation-stage-alignment.sh`** already fails an `implementation-plan/*` pull request whose changed files fall outside the plan-stage allowlist — the plan document and any plan-stage smoke-test runbook. Implementation smuggled in as *files* on a plan-only pull request is therefore already caught, deterministically, and blocking. Adding a strict check that asks the same question of the same file list would produce a second finding that is always redundant with a gate that already stops the pull request, which is how a label stops being read.

What that gate cannot see is a step **inside** the plan document that nothing in the source asked for. It reads paths, not prose. That residue is check 2, `unspecified_step`, and it is the only part of objective 7 this feature implements.

---

## Use Cases

### Use Case 1: A plan is reviewed strictly

**Actor**: The reviewer loop, running on behalf of the agent or maintainer advancing a pull request.
**Preconditions**: The change is at the plan stage, as #1653's stage resolution determines, and it changes at least one implementation-plan document.

**Steps**:

1. The loop starts a local review.
2. The reviewer is given the ordinary review contract, and — new here — the strict plan checklist, the full text of every implementation-plan document the pull request changes, and the plan's declared source of truth when that source is in the repository.
3. It applies each applicable check to each of those plan documents.
4. It reports what it finds: ordinary findings as it does today, and strict-check findings **labelled as such**, each naming the check it came from and the plan document it applies to.
5. The review's overall verdict is decided **without** the strict findings.

**Postconditions**: The pull request carries the strict findings, visibly separated from the blocking ones, and its verdict is what it would have been without them.

**Information shown**:

- Each strict finding, with the check that produced it and the document it applies to.
- The count of strict findings, and the set of checks that produced them.
- The set of checks that were **applied**, which is what makes the count a fraction of something known.

**Considerations**:

- The checks apply **only** at the plan stage. A spec change is #1650's business and an implementation change is neither's; running plan questions against either produces noise that teaches reviewers to ignore the label.
- The strict findings never change the verdict — not to block, and not to unblock. A plan with four strict findings and no blocking ones is clean.
- **At most one strict checklist is ever applied to a review.** A change has one stage, so #1650's spec checks and this item's plan checks cannot both run on the same review. The cost of this feature is therefore bounded by one strict pass per review, the same bound #1650 already established.

---

### Use Case 2: A maintainer reads the strict findings

**Actor**: A maintainer, or the agent advancing the item.

**Steps**:

1. They open the pull request and see the strict findings grouped and labelled.
2. Each names its check and its document, so an ordering gap can be told from a missing test without reading both.
3. They fix what is worth fixing and leave the rest.

**Postconditions**: The plan improves where the reader agreed, and the ignored findings remain recorded.

**Considerations**:

- Ignoring a strict finding must cost nothing: no workflow label on the pull request, no gate, no reminder. That is what makes the count trustworthy — a reviewer who must justify each dismissal starts dismissing them silently instead.
- The findings stay in the pull request rather than being cleared, so a later reader can see what was raised and not acted on.

---

### Use Case 3: A plan is reviewed with part of the checklist

**Actor**: The local reviewer.
**Preconditions**: The change is at the plan stage and no approved spec is present in the plan's development directory — because the item is a Refactor whose brief is the tracker issue, or because the spec the plan needs is not there.

**Steps**:

1. The reviewer applies each check that needs no source document: `source_declaration`, `phase_ordering`, `dependency_state` and `reversal_risk`.
2. It does not apply the checks that compare the plan against its source — `unspecified_step`, `spec_traceability` and `ac_test_coverage` — because the source text is not in the repository, whichever of the three reasons put it out of reach.
3. It reports the state, the findings, and **the set of checks it applied**.

**Postconditions**: The review is complete and unaffected. A reader can tell that three checks did not run on this pull request, and which three.

**Considerations**:

- **A count without its denominator is not a rate**, and this is the case that forces the point. Two plans each reporting one finding are not comparable if one was asked seven questions and the other four. #1657 computes incidence per check, and a check that was never applied belongs in neither the numerator nor the denominator.
- Partial coverage is **not** a failure state. Nothing is retried, nothing is gated, and the review's verdict is what it would be with all seven applied. It is an ordinary outcome for an ordinary kind of item, and the only thing required of it is that it be visible.
- **Partial coverage has exactly one cause**: no approved spec is present in the plan's development directory. Nothing about the plan's own text enters this; the three source-dependent checks have nothing to compare against, and that is the whole of it.
- **Coverage and fault are different axes, and this specification keeps them apart.** The applied set records *what was asked*. `source_declaration` records *whether the plan named its source correctly*. A Refactor plan with a partial set and no finding is in good order; a plan with a full set and a `source_declaration` finding is not. Reading a partial applied set as an accusation gets the two crossed.
- **A plan that declares nothing is still checked against a spec that is there.** The source-dependent checks compare a plan to a document, and the document's presence is what decides whether they can. Withholding an available spec to penalise a missing declaration would review the plan less thoroughly *because* it has a defect — and that defect is already reported, by check 1.

---

### Use Case 4: The strict checks find nothing

**Actor**: The local reviewer.

**Steps**:

1. The reviewer applies every applicable check and none matches.
2. It reports a strict-finding count of zero, alongside the set of checks it applied.

**Postconditions**: The count is zero and is reported. A plan that produced no strict findings is distinguishable from one where the checks did not run.

**Considerations**:

- **Silence and zero are different**, and the distinction is this feature's only defence against quietly not working. A round where the checks did not fire — wrong stage, no plan document changed, a missing checklist, or an attempt that failed — must not look like a round where they fired and found nothing.

---

### Use Case 5: The strict checks produce no result

**Actor**: The reviewer loop.
**Preconditions**: The checks reach no verdict, for one of three reasons — the stage could not be resolved, the checklist is missing or unreadable, or the checks were attempted and did not complete.

**Steps**:

1. The reviewer runs its ordinary review.
2. It records that the strict checks produced no result, and which of the three causes applies.

**Postconditions**: The review completed and its verdict is unaffected. The record says the strict checks reached no verdict, and says why.

**Considerations**:

- **Two of the causes mean the checks never started; the third means they started and did not finish.** The outcome for the review is identical — no findings, no verdict change, nothing gated — and the outcome for whoever has to fix it is not. A missing checklist is a repository defect; a pass that fails is a defect in the reviewer command or its environment, and it is the only one of the three that can appear and disappear between two rounds of the same pull request.
- The review is never failed for this, whichever cause applies. The strict checks are an addition to a review, not a precondition for one — and that has to hold for a failure *inside* them as much as for their absence, or an unrelated defect in the reviewer command starts blocking pull requests that had no findings.

---

### Use Case 6: A later item decides whether to block

**Actor**: A maintainer, reading accumulated counts.

**Steps**:

1. They read, per check, **on how many pull requests it fired at least once**, over **how many pull requests it was applied to**.
2. They decide whether any check has earned the right to block.

**Postconditions**: A decision informed by incidence data rather than by expectation.

**Considerations**:

- **The data is incidence, not compliance.** This feature records how often each check fires and how often it was applied. It does **not** record which findings were acted on, and cannot: it has no per-finding identity and no acknowledgement mechanism, both excluded under Out of Scope for the reason that tracking dismissals would make ignoring a finding cost something — after which the counts measure obedience rather than incidence.
- **Frequency is counted per pull request**, never by summing rounds. Rounds repeat the same unresolved finding by design, so a sum would make a check look more frequent the longer its pull request took to merge.
- The denominator is per check, not per pull request, because the three source-dependent checks are applied to fewer pull requests than the four others. A single denominator would understate all three.

---

## Business Rules

- The strict plan checks run **only** at the plan stage, and only when the pull request changes at least one implementation-plan document.
- Strict findings are **non-blocking**. They never change a review's verdict in either direction, and they never alter the status of an ordinary finding that reports the same defect.
- Every strict finding names the check that produced it and the plan document it applies to.
- The checks are applied to the **full text of each changed plan document at the reviewed head**, and to the full text of its source when that source is in the repository — not to the pull request's diff. A plan amended in a later pull request has most of its content outside that diff, and checks run over hunks would report absences that are artifacts of where the diff happens to end.
- Every review reports the strict-plan **state**. The **count**, the set of **checks that produced findings**, and the set of **checks that were applied** accompany it only when the state is `applied` — the count including when it is zero — and are empty otherwise.
- The set of applied checks is reported whenever the state is `applied`, including when it is all seven. A reader must never have to infer coverage from the spec's text and the round's date.
- **Partial coverage has exactly one cause**: no approved spec is present in the plan's development directory. It is decided by what is present and never by what the plan declares — the two are independent, and a round can have full coverage and a `source_declaration` finding at once, or partial coverage and none. There is no separate field recording the cause, because a second place to state one fact is a second place for two statements to disagree; the applied set and check 1's finding are the record.
- The state of each strict checklist is reported **independently**. A review at the spec stage reports the plan checklist as `not_applicable` and the spec checklist as `applied`, and the reverse holds at the plan stage. #1650's contract is unchanged by this item.
- At most one strict checklist reaches the `applied` state on any review, because a change has one stage.
- Incidence is measured **per pull request**, never by summing rounds: a check fired on a plan if any of its rounds reported that check, and was applied to that plan if any of its rounds applied it.
- A review where the checks did not run reports that fact and its reason, and is distinguishable from a review where they ran and found nothing.
- A strict finding that a maintainer ignores has no consequence: no **workflow label** on the pull request, no gate, no escalation, no repetition of the demand beyond the ordinary re-reporting of an unresolved finding. Every strict finding still carries its **check identifier**, which is what makes it readable and countable; that identifier is part of the finding, not a mark against the pull request.
- Each check answers a question that can be **wrong**, not one that is a matter of taste.
- The checks are a fixed, enumerated set. Adding one, removing one, or moving one between the source-dependent and source-independent groups is a change to this contract, not a change to a prompt.
- **A plan document whose text is retrieved is examined, whatever that text is.** Empty, truncated, malformed or incoherent prose is not a state of its own: the applicable checks are applied and report what they find, which for a document declaring no source is at least a `source_declaration` finding. A document a reader cannot make sense of is a defect in the plan and belongs in the findings, not in a state.
- **A plan document whose text cannot be retrieved at all** — the file is listed as changed and its bytes do not arrive — is the checks failing to complete, reported as `unavailable` with reason `strict_pass_failed`. It gets no reason of its own: the review's outcome and the owner of the fix are the same as for any other failed attempt, and a fourth reason would divide one thing to fix into two.
- The word *unreadable* appears in exactly one reason, `checklist_unreadable`, and refers to the checklist rather than to any plan document.
- **There is no way to disable the strict plan checks by themselves.** They run when the local reviewer runs and the conditions above hold; disabling the local reviewer is the single mechanism that stops them, and it is the only one.

---

## UX Rules

Not applicable — there is no user interface. The reader-facing surfaces are the pull request's review comments and the reviewer's recorded output, both covered under Operational Visibility.

---

## Statuses / Enum Values

### The seven strict plan checks

Each is stated as the question it asks and the shape of a finding it produces. The identifiers are the labels a finding carries. **Source** says whether the check needs the plan's source of truth — the approved spec — to be readable.

| # | Check | Source needed | The question | A finding looks like |
| --- | --- | --- | --- | --- |
| 1 | `source_declaration` | No | Does the plan name its source of truth — the approved spec it implements, or the tracker brief for a Refactor item — and, when it names a spec, is that spec present in the same development directory? | a plan naming no source, or naming a spec that is not there |
| 2 | `unspecified_step` | Yes | Does every step trace to an acceptance criterion or use case in the source, or, tracing to neither, declare itself an addition and say why it is needed? | a step nothing in the source asks for, presented as though it did |
| 3 | `spec_traceability` | Yes | Does every acceptance criterion in the source have at least one step that would satisfy it, or an explicit statement that it is handled elsewhere? | an acceptance criterion no step addresses |
| 4 | `ac_test_coverage` | Yes | Does every acceptance criterion have at least one named test, scenario or proof that would **fail** if the criterion were unmet? | a criterion covered by a test that passes whether or not it holds, or by none |
| 5 | `phase_ordering` | No | Does every step that consumes something another step produces come after that step, in the order the plan states? | a step using a file, function or field a later step creates |
| 6 | `dependency_state` | No | Does every dependency on another item state that item's current state — merged, implemented, open — and what this plan does if that state does not hold when implementation starts? | a dependency named without its state, or with no stated consequence |
| 7 | `reversal_risk` | No | Does every step that changes persisted data, a published contract or a deployed surface state how the change is undone, or state that it cannot be undone? | a migration or contract change with no stated reversal and no statement that none exists |

**Check 2 asks the direction the existing checklist does not.** `REVIEW.md` asks whether the spec's criteria are covered by the plan; check 2 asks whether the plan's steps are asked for by the spec. A step that nothing requires is how work reaches implementation without ever having been specified, and it is the document-level half of objective 7.

**Check 4 asks for falsifiability, not for a mapping.** A plan that lists a test beside every criterion satisfies the existing checklist item and can still name tests that would pass with the behaviour absent. The question is whether the named test distinguishes the criterion holding from its not holding.

**Check 6 is phase ordering between items**, where check 5 is ordering within one plan. It is the same defect at a larger scale, and this epic produced an instance of it: #1650's plan depends on #1653's *implementation*, not only its merged plan, and had to record that as an unresolved conflict with a named owner rather than a bullet.

**Check 7 accepts "it cannot be undone" as an answer.** The check is not a demand for a rollback path; it is a demand that the plan say which it is. An irreversible step declared as irreversible passes.

### Strict-plan states

| State | Meaning |
| --- | --- |
| `applied` | The checks ran to completion; the count is what the applied checks found, and may be zero |
| `not_applicable` | The checks do not apply to this change |
| `unavailable` | The checks did not produce a result |

Three states, and `applied` with a count of zero is deliberately not the same as either of the others. The **count and both check sets accompany `applied` only**: they are empty in the other two states, because a number there would claim the checks reached a verdict they never reached.

Each of `not_applicable` and `unavailable` carries a **reason**, and each reason belongs to exactly one state:

| Reason | State | What happened | Whose |
| --- | --- | --- | --- |
| `stage_unresolved` | `unavailable` | The change's stage could not be classified, so the checks were never attempted | the pull request's shape |
| `stage_not_plan` | `not_applicable` | The stage resolved to something other than `plan` | nobody's — an ordinary change |
| `no_plan_document_changed` | `not_applicable` | The stage is `plan` and the pull request changes no implementation-plan document — a runbook-only plan-stage change, which the stage allowlist permits | nobody's — an ordinary change |
| `checklist_unreadable` | `unavailable` | The stage is `plan`, a plan document changed, and the checklist is missing or unreadable, so the checks were never attempted | the repository's contents |
| `strict_pass_failed` | `unavailable` | The checks were attempted and did not complete — however they failed | the reviewer command or its environment |

**`not_applicable` carries a reason here where #1650's did not**, and the difference is not an inconsistency to be tidied away. At the spec stage there was one way to not apply: the change was not a spec. At the plan stage there are two, and the second — a plan-stage pull request that changes only a smoke-test runbook — would otherwise be indistinguishable from a spec pull request in the record. Both are ordinary, neither is a defect, and #1657 has to be able to exclude them from a denominator it can name.

---

## Decision Matrix

The complete gate, from a review starting to strict findings existing or not. Rows are evaluated in order and the first match decides.

The order asks three questions about the change before either question about the machinery: **what is this change** (rows 1–3), **can the checks run** (rows 4–5), **what did they find** (rows 6–9). An unresolved stage cannot be compared against `plan`; a pull request with no plan document has nothing for a checklist to be applied to; and checks never attempted cannot complete. No row evaluates an input that an earlier answer made unreachable.

**Plan's source** is the sixth input and takes two values, which partition every reachable case:

| Value | Meaning |
| --- | --- |
| `spec present` | An approved spec is present in the plan's development directory |
| `no spec present` | None is |

**The input is what is present, not what the plan declares**, and the distinction is this feature's sharpest line. Whether a plan *named* its source is check 1's question and is answered in a finding; whether a source *exists to compare against* decides what can be checked at all. They are independent, and collapsing them costs something real in both directions:

- A plan that declares nothing while its spec sits beside it is checked against that spec — all seven apply — **and** produces a `source_declaration` finding. Withholding an available source to punish a missing declaration would review the plan less thoroughly as a penalty for a defect the checklist already reports.
- A plan that declares a spec which is absent gets the four, because there is nothing to compare against, **and** produces a `source_declaration` finding for naming a source that is not there.
- A Refactor plan correctly declaring its tracker brief gets the four and produces **no** finding.

An earlier revision of this specification made the input three-valued and keyed it on the declaration. That was a `trigger_semantics` defect of the kind check 5 exists to catch: it stated a gate's input as something the gate cannot observe. It was found while planning the implementation, and it is corrected here rather than worked around there — a plan cannot amend its own spec.

| # | Stage resolves | Stage | Plan doc changed | Checklist available | Checks complete | Plan's source | Findings | State | Reason | Applied checks | Count | Checks that fired |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **No** | — | — | — | not attempted | — | — | `unavailable` | `stage_unresolved` | **empty** | **empty** | **empty** |
| 2 | Yes | not plan | — | — | not attempted | — | — | `not_applicable` | `stage_not_plan` | **empty** | **empty** | **empty** |
| 3 | Yes | plan | **No** | — | not attempted | — | — | `not_applicable` | `no_plan_document_changed` | **empty** | **empty** | **empty** |
| 4 | Yes | plan | Yes | **No** | not attempted | — | — | `unavailable` | `checklist_unreadable` | **empty** | **empty** | **empty** |
| 5 | Yes | plan | Yes | Yes | **No** | — | — | `unavailable` | `strict_pass_failed` | **empty** | **empty** | **empty** |
| 6 | Yes | plan | Yes | Yes | Yes | `spec present` | none | `applied` | none | all seven | `0` | empty list |
| 7 | Yes | plan | Yes | Yes | Yes | `spec present` | one or more | `applied` | none | all seven | *n* | the checks that fired |
| 8 | Yes | plan | Yes | Yes | Yes | `no spec present` | none | `applied` | none | the four needing no source | `0` | empty list |
| 9 | Yes | plan | Yes | Yes | Yes | `no spec present` | one or more | `applied` | none | the four needing no source | *n* | the checks that fired |

**Rows 8 and 9 are not degraded rows 6 and 7.** The plan's source does not gate anything; it partitions the applied set. That is why it is evaluated after completion rather than before: it changes what the checks cover, never whether they run.

**Every one of the four `applied` rows can carry a `source_declaration` finding, and none is required to.** Rows 6 and 7 differ from 8 and 9 in *coverage*, not in fault: a plan whose spec is present may still have named nothing, and a plan whose spec is absent may be a Refactor that named its brief correctly. Reading a partial applied set as an accusation — or full coverage as proof the plan declared properly — gets the two axes crossed. The fired set is where fault is recorded; the applied set is where coverage is.

**The count is empty, not zero, in rows 1 through 5.** `0` means *the applied checks ran and found nothing*, and it is the only thing distinguishing a clean plan from one the checks never examined. Writing `0` for the other rows would put those rounds into the denominator of any later rate as if they had been checked.

**"Checks that fired" is a subset of "applied checks" in every row.** A check that was not applied cannot fire, and a reader who finds an identifier in the fired set that is absent from the applied set is looking at a defect in the record, not at a rare case.

### What each outcome requires, on every surface

The matrix decides the state; this table says what follows from it, so no surface is left to inference:

| State | Next action | Reviewer output | Review comments | Reviewer-loop history |
| --- | --- | --- | --- | --- |
| `unavailable` (rows 1, 4, 5) | none — the review proceeds and its verdict is unchanged | the state and its reason; no count, no check sets | nothing added | the state and its reason; count and both sets empty |
| `not_applicable` (rows 2, 3) | none | the state and its reason; no count, no check sets | nothing added | the state and its reason; count and both sets empty |
| `applied`, count `0` (rows 6, 8) | none | the state, count `0`, and the applied set; fired set empty | nothing added | the state, count `0`, the applied set, and an empty fired set |
| `applied`, count *n* (rows 7, 9) | none that gates — the findings are reported and the verdict is decided without them | the state, the count, the applied set, and the checks that fired | each finding, labelled with its check and its document, grouped apart from blocking findings | the state, the count, the applied set, and the checks that fired |

**"Next action" is empty in every row, and that is the feature.** No state gates, escalates, retries or demands acknowledgement. The only row group with any follow-up is 7 and 9, whose follow-up is to *report* — which is why the column exists rather than being omitted: a reader checking whether some state blocks should find the answer here rather than infer it from silence.

The comment surface is touched in exactly one row group. A reader seeing no strict findings on a pull request cannot tell rows 1 through 6 and row 8 apart from the comments alone, which is why the state is on the reviewer output and in the history for every review.

---

## Operational Visibility

- **Reviewer output**: the strict-plan state on every review, its reason in every `unavailable` and `not_applicable` row, and — when the state is `applied` — the finding count, the set of checks applied, and the set of checks that fired.
- **Cost**: the checks cost time on the reviews that run them, taken from inside the review's existing `--timeout` rather than added to it. A round that runs them is typically slower than one that does not; what it is not is *less bounded*, since both share the same maximum. At most one strict checklist is applied per review, so this feature does not compound with #1650's. No review is gated, retried or decided differently because the checks ran, failed, or exhausted what was left.
- **Review comments**: each strict finding, labelled with its check identifier and the plan document it applies to, grouped separately from blocking findings.
- **Reviewer-loop history**: per round, the state, its reason where it applies, and — where the state is `applied` — the count, the applied set and the fired set.

**The unit of measurement is the pull request, not the round.** A round is not an independent observation: the same unresolved finding is reported again on every later round, which AC-20 requires, so summing per-round counts would count one ordering gap as many. A check fired on a plan when **any** round reports it, and was applied to that plan when **any** round applied it. Both recorded sets make that computable without per-finding identity and without an acknowledgement mechanism.

---

## Acceptance Criteria

- [ ] **AC-1.** At the plan stage, on a pull request that changes at least one implementation-plan document, the local reviewer applies every applicable check listed in Statuses / Enum Values — `source_declaration`, `unspecified_step`, `spec_traceability`, `ac_test_coverage`, `phase_ordering`, `dependency_state` and `reversal_risk` — naming them rather than counting them, so a check added later cannot be silently omitted by a criterion that still reads as satisfied.
- [ ] **AC-2.** Each strict finding names the check that produced it, using that check's identifier, and the plan document it applies to.
- [ ] **AC-3.** Strict findings are not an input to a review's verdict: a review with strict findings and no blocking findings reports the same verdict as an otherwise identical review whose strict pass produced no result. An ordinary blocking finding reporting the same defect as a strict finding stays blocking. The comparison is against a pass that produced no result, not against a pass switched off, because AC-26 forbids the second — there is no setting to compare with.
- [ ] **AC-4.** A plan that names no source of truth, or that names an approved spec which is not present in its development directory, produces a `source_declaration` finding.
- [ ] **AC-5.** A plan containing a step that no acceptance criterion or use case in its source asks for, and which the plan does not declare as an addition with a stated reason, produces an `unspecified_step` finding.
- [ ] **AC-5a.** A step that the plan **does** declare as an addition, with its reason stated, produces **no** `unspecified_step` finding.
- [ ] **AC-6.** A plan whose source contains an acceptance criterion that no step addresses, and which the plan does not state is handled elsewhere, produces a `spec_traceability` finding.
- [ ] **AC-7.** A plan containing an acceptance criterion whose only named test would pass whether or not the criterion held, or which names no test at all, produces an `ac_test_coverage` finding.
- [ ] **AC-8.** A plan in which a step consumes something a later step produces, under the order the plan states, produces a `phase_ordering` finding.
- [ ] **AC-9.** A plan naming a dependency on another item without that item's current state, or without what the plan does if that state does not hold at implementation start, produces a `dependency_state` finding.
- [ ] **AC-10.** A plan containing a step that changes persisted data, a published contract or a deployed surface without stating how the change is undone, produces a `reversal_risk` finding.
- [ ] **AC-10a.** A step that states it cannot be undone produces **no** `reversal_risk` finding. The check requires an answer, not a rollback path.
- [ ] **AC-11.** A plan that satisfies a check produces no finding from that check, for each of the seven independently.
- [ ] **AC-12.** The checks are applied to the full text of each changed plan document at the reviewed head, and to the full text of its source when that source is in the repository. A pull request amending an existing plan produces the same findings it would produce if the whole document were new, for the parts of the document its diff does not touch.
- [ ] **AC-12a.** A changed plan document whose text is retrieved is examined whatever that text is: an empty document, a truncated one, and one whose prose is incoherent each yield state `applied` and are reported through findings — at minimum `source_declaration` for a document declaring no source. None of the three yields `unavailable`.
- [ ] **AC-12b.** A changed plan document whose text cannot be retrieved at all yields `unavailable` with reason `strict_pass_failed`, the same reason as any other attempt that did not complete, and no reason of its own.
- [ ] **AC-13.** Every strict finding is reported on the plan document it applies to, and a pull request changing two plan documents reports each document's findings against that document.
- [ ] **AC-14.** The strict plan checks do not run outside the plan stage, and the state is `not_applicable` with reason `stage_not_plan`.
- [ ] **AC-15.** A plan-stage pull request that changes no implementation-plan document reports `not_applicable` with reason `no_plan_document_changed`, distinguishable from `stage_not_plan` and from `applied` with count `0`.
- [ ] **AC-16.** When the checklist cannot be supplied, the state is `unavailable` with reason `checklist_unreadable`, the review still runs, and its verdict is unaffected.
- [ ] **AC-16a.** When the checks are attempted and do not complete — however they fail — the state is `unavailable` with reason `strict_pass_failed`, the review still runs, and its verdict, findings and their order are what the same review produces with the checks never attempted. A failure in the checks never **blocks, gates, retries or escalates** a review, and never alters its outcome.
- [ ] **AC-16b.** The checks **share the review's existing time budget** rather than receiving one of their own: a round that runs them is bounded by the reviewer's `--timeout` in total, the same bound as a round that does not. The checks are attempted with whatever remains of that budget once the review has been produced; if nothing remains they produce no result.
- [ ] **AC-16c.** The bound has exactly one source and **no second setting exists**: there is no configuration, environment variable or flag that sets the plan checks' budget separately, capped or otherwise, and none that raises the round's total. Overriding the review's timeout is the only way to change either.
- [ ] **AC-16d.** A budget exhausted before or during the checks is `unavailable` with reason `strict_pass_failed`, and is not distinguished from any other failed attempt: the review is complete, its outcome is unaffected, and *the checks produced no result* is the whole of what a reader needs.
- [ ] **AC-17.** The state appears in the reviewer's output and in the reviewer-loop history for **every** review, at any stage. The count, the applied set and the fired set accompany it only in the `applied` state; in `not_applicable` and `unavailable` all three are **empty**, and the count is never `0`.
- [ ] **AC-18.** In the `applied` state the **set of checks applied** is reported, including when it is all seven, in the reviewer's output and in the reviewer-loop history.
- [ ] **AC-19.** At the plan stage with the checks applied and **no approved spec present** in the plan's development directory, the applied set is exactly those that need no source — `source_declaration`, `phase_ordering`, `dependency_state` and `reversal_risk` — and the state is `applied`, not `unavailable`. This holds whatever the plan declares.
- [ ] **AC-19b.** The applied set is decided by the spec's **presence** alone. A plan that declares no source, or declares one that is not there, and whose development directory nonetheless contains an approved spec, has **all seven** applied — and still produces a `source_declaration` finding.
- [ ] **AC-19c.** Coverage and `source_declaration` vary independently. All four combinations are producible: full coverage with the finding, full coverage without it, partial coverage with it, and partial coverage without it. No combination is reported as an error of the reporting itself.
- [ ] **AC-19a.** The set of checks that fired is a subset of the set of checks applied, on every round in the `applied` state.
- [ ] **AC-20.** Ignoring a strict finding has no effect on any later review: no **workflow label** on the pull request, no gate, no escalation, and the same finding may be reported again on a later round without penalty. The finding's own check identifier, required by AC-2, is unaffected — it identifies the finding and marks nothing about the pull request.
- [ ] **AC-21.** A reader can determine, from the reviewer-loop history alone, **which** checks produced findings on a round and **which** were applied — not only how many findings there were.
- [ ] **AC-22.** Two rounds reporting the same unresolved finding count that check **once** for the pull request, and two rounds applying the same check count it **once** in that check's denominator: both incidence and coverage are per pull request.
- [ ] **AC-23.** A round recorded as `unavailable` or `not_applicable` is distinguishable from one recorded as `applied` with count `0`, by reading the history alone.
- [ ] **AC-24.** The strict-plan state is reported independently of the strict-spec state introduced by #1650: a review at the spec stage reports the plan state as `not_applicable` and leaves #1650's reported values unchanged, and a review at the plan stage reports the spec state as `not_applicable`.
- [ ] **AC-25.** No review reports two strict checklists in the `applied` state.
- [ ] **AC-26.** There is no configuration, environment variable, flag or label that disables the strict plan checks while the local reviewer runs.

---

## Out of Scope (MVP)

1. **Making any check blocking.** Deferred until counts exist. This feature produces the data; the decision needs it, and needs to be taken per check rather than for all seven at once — the checks will not earn it at the same rate.
2. **A report over strict-finding counts.** #1657 owns reporting. This feature records the state, the count, the applied set and the fired set per round so that report is possible for the plan checks on the same terms as for #1650's spec checks.
3. **Any measure of whether a finding was acted on.** The recorded data is incidence and coverage, and never disposition. Measuring dismissals would require per-finding identity and an acknowledgement step, and would make ignoring a finding cost something, which Business Rules forbid.
4. **Making the refactor brief available to the reviewer.** The three source-dependent checks do not run on Refactor plans because the brief is a tracker issue rather than a repository file. Fetching it would put a network call inside a local review and make the checks' coverage depend on the tracker being reachable; the deferral is recorded here rather than hidden, and Use Case 3 makes the resulting gap visible in every round instead.
5. **Strict checks for implementation pull requests.** The same idea applies to code, and its questions are different ones. Extending it is a separate item.
6. **Duplicating the file-level plan-artifact gate.** `check-documentation-stage-alignment.sh` already fails a plan-only pull request that changes implementation files, deterministically and blocking. This feature adds no check over the changed-file list; see **Relationship to checks that already exist**.
7. **Suppression, acknowledgement or per-finding dismissal.** Ignoring a finding must cost nothing, which is exactly why there is no mechanism for recording that you ignored it.
8. **Automatically fixing what the checks find.** Six of the seven name a gap and the seventh names a contradiction; closing either is a decision about the plan.
9. **Tuning the checks by measured yield.** The checks ship as written. Retiring or rewording one belongs to the same later item that decides on blocking, with the same data behind it.
