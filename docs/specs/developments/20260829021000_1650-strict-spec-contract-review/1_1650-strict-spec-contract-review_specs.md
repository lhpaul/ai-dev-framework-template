# Strict Spec Contract Review — Spec

**Depends on**: 1653-split-reviewer-prompts-by-stage

---

## Overview

A specification is a contract, and a contract fails in ways prose does not. Its acceptance criteria can disagree with each other, or state something no test could distinguish. A gate described in sentences can leave a combination of its inputs unmentioned. A way to opt out can have its source of truth named twice, or nowhere. A worked example can demonstrate what the rule beside it forbids. None of these read as errors; they read as a document.

The local reviewer sees spec pull requests today and applies the same contract to them as to everything else. This feature gives it a stricter checklist for specs — the questions above, asked one at a time — and has it report what that checklist found as **labelled, non-blocking findings**.

Non-blocking is the point of the first release. Nobody knows yet how often the strict questions fire, or how many of their answers are worth acting on; a checklist that blocks before that is known will be silenced rather than tuned. The findings are labelled so they can be counted, and the decision to make them blocking is deferred to a later item that will have the counts.

---

## Issue-Objective Traceability

Every objective stated in issue #1650 maps to acceptance criteria and use cases here, or to an explicit entry under **Out of Scope (MVP)** with a deferral note. No objective is dropped.

| # | Objective (from #1650) | Where it is satisfied |
| --- | --- | --- |
| 1 | *Problem* — spec pull requests pass local review while external reviewers find contradictions | Use Cases 1 and 2; AC-1, AC-2, AC-15 |
| 2 | *Outcome* — the local reviewer applies a stricter spec checklist before expensive reviewers run | Use Case 1; AC-1, AC-3, AC-14 |
| 3 | *Scope* — validate acceptance-criterion consistency and testability | Check 1 and Check 2 in Statuses / Enum Values; AC-4, AC-5 |
| 4 | *Scope* — require decision matrices for gate-like behavior | Check 3; AC-6, AC-7 |
| 5 | *Scope* — check opt-out source of truth | Check 4; AC-8 |
| 6 | *Scope* — check trigger semantics | Check 5; AC-9 |
| 7 | *Scope* — check examples against the rules they illustrate | Check 6; AC-10 |
| 8 | *Scope* — check parser and input-surface consistency | Check 7; AC-11 |
| 9 | *Scope* — flag ambiguous phrases that change behavior | Check 8; AC-12, AC-13 |

---

## Use Cases

### Use Case 1: A spec is reviewed strictly

**Actor**: The reviewer loop, running on behalf of the agent or maintainer advancing a pull request.
**Preconditions**: The change is at the spec stage, as the previous item's stage resolution determines.

**Steps**:

1. The loop starts a local review.
2. The reviewer is given the ordinary review contract, the spec checklist, and — new here — the strict spec checks.
3. It applies each check to the specification under review.
4. It reports what it finds: ordinary findings as it does today, and strict-check findings **labelled as such**, each naming the check it came from.
5. The review's overall verdict is decided **without** the strict findings.

**Postconditions**: The pull request carries the strict findings, visibly separated from the blocking ones, and its verdict is what it would have been without them.

**Information shown**:

- Each strict finding, with the check that produced it and where it applies.
- A count of strict findings, so the volume is visible without reading them.

**Considerations**:

- The checks apply **only** at the spec stage. A plan or an implementation change is not a specification, and running spec contract questions against one produces noise that teaches reviewers to ignore the label.
- The strict findings never change the verdict — not to block, and not to unblock. A specification with three strict findings and no blocking ones is clean.

---

### Use Case 2: A maintainer reads the strict findings

**Actor**: A maintainer, or the agent advancing the item.

**Steps**:

1. They open the pull request and see the strict findings grouped and labelled.
2. Each names its check, so the reader can tell an acceptance-criterion contradiction from a missing decision matrix without reading both.
3. They fix what is worth fixing and leave the rest.

**Postconditions**: The specification improves where the reader agreed, and the ignored findings remain recorded.

**Considerations**:

- Ignoring a strict finding must cost nothing: no label, no gate, no reminder. That is what makes the count trustworthy — a reviewer who must justify each dismissal starts dismissing them silently instead.
- The findings stay in the pull request rather than being cleared, so a later reader can see what was raised and not acted on.

---

### Use Case 3: The strict checks find nothing

**Actor**: The local reviewer.

**Steps**:

1. The reviewer applies all eight checks and none matches.
2. It reports a strict-finding count of zero.

**Postconditions**: The count is zero and is reported. A specification that produced no strict findings is distinguishable from one where the checks did not run.

**Considerations**:

- **Silence and zero are different**, and the distinction is the feature's only defence against quietly not working. A run where the checks did not fire — wrong stage, missing checklist, an older reviewer — must not look like a run where they fired and found nothing.

---

### Use Case 4: The strict checklist is unavailable

**Actor**: The reviewer loop.
**Preconditions**: The checklist cannot be supplied — the document is missing, or the stage could not be resolved.

**Steps**:

1. The reviewer runs its ordinary review.
2. It records that the strict checks did not run, and why.

**Postconditions**: The review completed and its verdict is unaffected. The record says the strict checks were absent.

**Considerations**:

- The review is never failed for this. The strict checks are an addition to a review, not a precondition for one.
- What must not happen is the silent case: a review that reports no strict findings because none ran.

---

### Use Case 5: A later item decides whether to block

**Actor**: A maintainer, reading accumulated counts.

**Steps**:

1. They read strict-finding counts across many pull requests, and how many were acted on.
2. They decide whether any check has earned the right to block.

**Postconditions**: A decision informed by data rather than by expectation.

**Considerations**:

- This feature makes that decision possible and does not take it. The blocking behaviour, and the per-check granularity it would need, are deferred.

---

## Business Rules

- The strict checks run **only** at the spec stage.
- Strict findings are **non-blocking**. They never change a review's verdict in either direction.
- Every strict finding names the check that produced it.
- Every review at the spec stage reports a strict-finding **count**, including zero.
- A review where the checks did not run reports that fact and its reason, and is distinguishable from a review where they ran and found nothing.
- A strict finding that a maintainer ignores has no consequence: no label, no gate, no repetition of the demand.
- Each check answers a question that can be **wrong**, not one that is a matter of taste. A check whose finding is a preference produces noise, and noise is what makes a label stop being read.
- The checks are a fixed, enumerated set. Adding one is a change to this contract, not a change to a prompt.

---

## UX Rules

Not applicable — there is no user interface. The reader-facing surfaces are the pull request's review comments and the reviewer's recorded output, both covered under Operational Visibility.

---

## Statuses / Enum Values

### The eight strict checks

Each is stated as the question it asks and the shape of a finding it produces. The identifiers are the labels a finding carries.

| # | Check | The question | A finding looks like |
| --- | --- | --- | --- |
| 1 | `ac_consistency` | Do any two acceptance criteria contradict each other, or does one contradict a business rule? | two criteria that cannot both hold |
| 2 | `ac_testability` | Could a test distinguish this criterion being met from its being unmet? | a criterion whose outcome no observation would differ on |
| 3 | `gate_matrix` | Does behavior described as depending on several inputs enumerate every combination of them? | a described gate with a combination of inputs unmentioned |
| 4 | `opt_out_source` | Does each way of disabling or bypassing behavior name exactly one source of truth? | an opt-out named in two places, or in none |
| 5 | `trigger_semantics` | Does each condition that starts behavior say what happens when its inputs are absent, empty or malformed? | a trigger with no stated behavior for a missing input |
| 6 | `example_contradiction` | Does each worked example do what the rule beside it requires? | an example demonstrating what its rule forbids |
| 7 | `parser_surface` | Is each statement about how input is recognised consistent with the syntax the document requires elsewhere, and with the stated tooling? | a matching rule the stated tool cannot express |
| 8 | `ambiguous_phrase` | Does any phrase whose meaning is unsettled — *next update*, *absence of evidence*, *as needed*, *where appropriate* — determine behavior? | an unsettled phrase load-bearing in a rule |

**Check 8 is bounded to phrases that change behavior.** The same words in a rationale or an aside are not findings. A check that flagged every occurrence would produce a finding on most documents and be switched off within a week — which is the failure mode this whole feature is designed around.

### Strict-check states

| State | Meaning |
| --- | --- |
| `applied` | The checks ran; the count is what they found, and may be zero |
| `not_applicable` | The change is not at the spec stage |
| `unavailable` | The checks could not run — the checklist is missing, or the stage could not be resolved |

Three states, and `applied` with a count of zero is deliberately not the same as `unavailable`.

---

## Decision Matrix

The complete gate, from a review starting to strict findings existing or not. Rows are evaluated in order and the first match decides.

| # | Stage | Checklist available | Strict checks run | Findings | State | Verdict affected |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | not spec | — | No | — | `not_applicable` | No |
| 2 | spec | **No** | No | — | `unavailable` | No |
| 3 | spec | Yes | Yes | none | `applied`, count 0 | No |
| 4 | spec | Yes | Yes | one or more | `applied`, count *n* | **No** |

Row 4's last column is the feature's central claim and the one most likely to erode: findings exist, are labelled, are counted, and change nothing about whether the pull request may proceed.

Rows 1 and 2 differ in what a reader can conclude. Row 1 is a change the checks do not apply to; row 2 is a spec the checks could not examine. Reporting both as "no strict findings" would make the second invisible, and the second is a defect.

---

## Operational Visibility

- **Reviewer output**: the strict-check state and the finding count, on every review.
- **Review comments**: each strict finding, labelled with its check identifier, grouped separately from blocking findings.
- **Reviewer-loop history**: the state and the count recorded per round, so counts accumulate across a pull request's life without re-reading comments.

---

## Acceptance Criteria

- [ ] **AC-1.** At the spec stage, the local reviewer applies all eight checks listed in Statuses / Enum Values.
- [ ] **AC-2.** Each strict finding names the check that produced it, using that check's identifier.
- [ ] **AC-3.** Strict findings never change a review's verdict: a review with strict findings and no blocking findings reports the same verdict as the same review with the strict checks disabled.
- [ ] **AC-4.** A specification containing two acceptance criteria that cannot both hold produces an `ac_consistency` finding.
- [ ] **AC-5.** A specification containing an acceptance criterion whose satisfaction no observation could distinguish produces an `ac_testability` finding.
- [ ] **AC-6.** A specification describing behavior that depends on two or more inputs, without enumerating every combination of them, produces a `gate_matrix` finding.
- [ ] **AC-7.** A specification that does enumerate every combination produces **no** `gate_matrix` finding.
- [ ] **AC-8.** A specification naming a way to disable behavior in two places, or in none, produces an `opt_out_source` finding.
- [ ] **AC-9.** A specification whose trigger condition does not say what happens when an input is absent, empty or malformed produces a `trigger_semantics` finding.
- [ ] **AC-10.** A specification containing a worked example that does what its neighbouring rule forbids produces an `example_contradiction` finding.
- [ ] **AC-11.** A specification whose statement about recognising input is inconsistent with the syntax it requires elsewhere, or with the stated tooling, produces a `parser_surface` finding.
- [ ] **AC-12.** A specification in which an unsettled phrase determines behavior produces an `ambiguous_phrase` finding.
- [ ] **AC-13.** The same phrase appearing in a rationale, an aside, or any passage that determines no behavior produces **no** finding.
- [ ] **AC-14.** The strict checks do not run outside the spec stage, and the state is `not_applicable`.
- [ ] **AC-15.** At the spec stage with the checks applied and nothing found, the state is `applied` and the count is `0` — distinguishable from `unavailable` and from `not_applicable`.
- [ ] **AC-16.** When the checklist cannot be supplied, the state is `unavailable`, the review still runs, and its verdict is unaffected.
- [ ] **AC-17.** The state and the count appear in the reviewer's output and in the reviewer-loop history for every review at the spec stage.
- [ ] **AC-18.** Ignoring a strict finding has no effect on any later review: no label, no gate, no escalation, and the same finding may be reported again on a later round without penalty.

---

## Out of Scope (MVP)

1. **Making any check blocking.** Deferred until counts exist. This feature produces the data; the decision needs it, and needs to be taken per check rather than for all eight at once — the checks will not earn it at the same rate.
2. **A report over strict-finding counts.** #1657 owns reporting. This feature records the state and count per round so that report is possible.
3. **Strict checks for plans and implementations.** The same idea applies to a plan, and its questions are different ones. Extending it is a separate item, and doing it here would mean writing three checklists to validate one.
4. **Suppression, acknowledgement or per-finding dismissal.** Ignoring a finding must cost nothing, which is exactly why there is no mechanism for recording that you ignored it. Adding one would make the counts measure compliance rather than incidence.
5. **Automatically fixing what the checks find.** Every one of the eight names a contradiction, and choosing which side is correct is a product decision.
6. **Tuning the checks by measured yield.** The checks ship as written. Retiring or rewording one belongs to the same later item that decides on blocking, with the same data behind it.
