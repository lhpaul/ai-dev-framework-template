# Plan-Authoring Rigor Smoke Test

**Feature**: Plan-authoring rigor for factual claims in implementation plans
**Spec**:
[1_1496-plan-authoring-rigor_specs.md](../../specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md)
**Plan**:
[2_1496-plan-authoring-rigor_implementation-plan.md](../../specs/developments/20260911230253_1496-plan-authoring-rigor/2_1496-plan-authoring-rigor_implementation-plan.md)

## Purpose

Verify that plan authors receive portable authoring obligations, plan reviewers
receive the matching backstop check, and plan pull requests carry a current
per-rule outcome record without introducing automated rule enforcement.

## Preconditions

- Scenarios execute during implementation QA on the feature branch for #1496, before merge into `develop`.
- A test tracker issue exists with an approved spec suitable for a short plan
  exercise (or reuse a docs-only refactor brief).
- Markdown lint passes on changed workflow documents.

## Scenario 1: Canonical rules surface

1. Open `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`.
2. Confirm it states all six rules with trigger, required evidence, and pass
   condition using the spec's outcome labels (`Satisfied`, `Not applicable`,
   `Unsatisfied`).
3. Grep mirror surfaces listed in the implementation plan's mirror table.

Expected result: no mirror surface adds a seventh rule or weakens a pass
condition relative to the canonical file.

## Scenario 2: Authoring guidance routing

1. Inspect Protocol 02 Step 3 quality guardrails and Document Quality Gate.
2. Inspect `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and
   `.codex/skills/workflow-plan-writer/SKILL.md`.

Expected result: each routes plan authors to the canonical rules doc and requires
evidence in the plan document (not pull request comments).

## Scenario 3: Per-rule outcome record on a plan PR

1. Run Protocol 02 for the test issue and open a draft plan PR.
2. Inspect the PR description `Document Quality Gate` section.

Expected result: a `Plan authoring rigor — per-rule outcome record` block lists
all six rules, the plan revision SHA, a rationale beside each `Not applicable`
outcome, and obeys the stale-revision rules from Group H of the spec.

## Scenario 4: Reviewer backstop

1. Apply `REVIEW.md` Plan Review Checklist to the draft plan PR from Scenario 3.
2. Deliberately omit evidence for one firing rule in the plan while recording
   `Satisfied` in the outcome record. Commit and push that mutation, then
   refresh the outcome record's plan revision to the new PR head **keeping the
   intentionally incorrect `Satisfied` label**, so the stale-revision gate does
   not confound the finding.
3. After the finding is observed, restore the omitted evidence, push, and
   refresh the record's revision and label to the new head, so Scenario 7 can
   continue the same PR.

Expected result: the backstop checklist yields a blocking finding naming the
rule and the defect; the finding class matches the spec gate matrix row for that
situation.

## Scenario 5: Verification Log and template

1. Open `docs/workflow/development-workflow/templates/implementation-plan-template.md`.
2. Confirm the template directs authors to record Rule 3/4/5 repository-derived
   evidence in the Verification Log (or linked plan sections) rather than in PR
   comments.

Expected result: the template change is guidance-only; existing merged plans are
not retrofitted.

## Scenario 6: Mirror consistency test harness

1. Run `bash scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`.

Expected result: exit `0`; the harness fails if rule names, outcome labels, or
required mirror paths drift.

## Scenario 7: Existing gates remain authoritative

1. Continue the plan PR through Step 7a, automated review, CI, and readiness
   labels per Protocol 91.

Expected result: the per-rule record supplements — does not replace — internal
review, `REVIEW.md`, strict plan checks, and CI.

## Acceptance traceability matrix

Manual desk-check (or scripted where noted). Each row
names an acceptance theme, the exercise, and the expected gate class.

| ID | Spec focus | Exercise | Expected result |
| --- | --- | --- | --- |
| B1 | Rule 1 — no record | Plan depending on vendor text with zero sampling/contract/enumeration | Blocking — missing sampling record |
| B2 | Rule 1 — two occurrences | Sampling record with two locators only | Blocking — floor not met |
| B3 | Rule 1 — contract fixed set | Design binds to literals with cited producer contract | Check passed — no sampling required |
| B4 | Rule 1 — tolerant open set | No contract; plan states stable part + unseen behavior | Check passed when record complete |
| C1 | Rule 2 — disagreeing duplicate | Same count stated differently in two sections | Blocking — contradiction |
| C2 | Rule 2 — agreeing duplicate | Same fact twice, identical wording | Non-blocking consolidation; Satisfied |
| D1 | Rule 3 — bad partition | Count by subtracting unrelated totals | Blocking — partition not shown |
| D2 | Rule 3 — scope by count | Step uses number without enumeration | Blocking — missing enumeration |
| E1 | Rule 4 — delegated support | "Test exists" from investigation summary only | Blocking — no recorded search |
| E2 | Rule 4 — narrow non-existence | "Helper absent" after searching one directory | Blocking — implausible scope |
| F1 | Rule 5 — unit-only expectation | Delete shared guard; expect new return at unit | Blocking — missing consumer site |
| F2 | Rule 5 — branch removal | Remove branch without reroute statement | Blocking — absorbed inputs |
| G1 | Rule 6 — scopeless conditional | "Required then" with no governed edges | Blocking — missing scope/discharge |
| H1 | Missing outcome record | Plan PR with no per-rule table | Blocking — treated Unsatisfied |
| H2 | Stale record SHA | Record names earlier commit than PR head | Blocking — revision mismatch |
| H3 | Wrong N/A rationale | Rule 3 recorded `Not applicable` while the plan states artifact counts | Blocking — rationale contradicts claim |
| B5 | Rule 1 — short-retention source | Sampling locator only to a deletable log | Blocking — durable copy or retained artifact required |
| B6 | Rule 1 — restricted occurrence | Sampling occurrence contains secrets/PII with raw text pasted | Blocking — must use redacted shape record |
| B7 | Rule 1 — restricted and short-retention | Source is both deletable and access-restricted | Blocking unless both handling requirements are met |
| B8 | Rule 1 — heterogeneous sample adequacy | Population documented as having two producer variants; sample drawn from one; record silent on the other | Blocking — known heterogeneity unaddressed |
| B11 | Rule 1 — unpersuasive adequacy rationale | Same population, record states an adequacy rationale that is complete in form but weak | Non-blocking — recorded as a suggestion; Satisfied |
| B9 | Rule 1 — curated examples | Occurrences are hand-picked examples | Blocking — not a sample of the population |
| B10 | Rule 1 — closed-population enumeration | Enumeration command shown with no closure provenance (nothing shows the set cannot grow), or members not listed | Blocking — enumeration record incomplete |
| E3 | Rule 4 — completeness claim | "All X verified" with no search scope | Blocking — completeness unsupported |
| F3 | Rule 5 — search scope | Consumer enumeration omits searched scope | Blocking — scope not recorded |
| F5 | Rule 5 — hand-recalled consumer list | Consumer list from memory with no recorded search | Blocking — search record missing |
| F4 | Rule 5 — untouched consumer | Untouched consumer omitted, or listed without its post-change outcome | Blocking — consumer or outcome missing |
| H4 | Outcome record — malformed | Record names a nonexistent commit | Blocking — revision does not resolve |
| H5 | Outcome record — label reassessed | Round re-reads recorded finding, label not reassessed | Blocking — label stale |
| H6 | Complete evidence, recorded Unsatisfied | Every rule's evidence is complete but the record says `Unsatisfied` | Blocking — outcome contradicts evidence |
| H7 | Absent trigger recorded Satisfied | Rule's trigger absent, record says `Satisfied` | Blocking — must be `Not applicable` with rationale |
| H8 | Invalid outcome label | Record uses a label outside the three defined | Blocking — invalid label |
| H9 | External-source finding not persisted | Rule 1 outcome cites an inspection with no persisted finding | Blocking — persisted finding missing |
| H10 | Incomplete evidence record | Rule 3/4/5 evidence record missing its revision, command, or result | Blocking — record incomplete |
| H11 | Non-reproducing or population-stale evidence | Recorded command no longer reproduces, or the population changed since gathering | Blocking — evidence not current |
| H12 | Repository-only drift | Repository changed after gathering but no claim the plan makes is affected | Non-outcome — no finding; record unchanged |
| H13 | Evidence only in PR comments | Evidence lives in a PR comment, not in the plan or PR description record | Blocking — evidence not in the durable record |

Scenarios 1–6 above cover wiring; this matrix covers criterion-level outcomes. Every row is a **required** case in implementation verification (executed and recorded in the implementation PR), not optional desk-checking. The matrix is the minimum required set, not a claim that it names every acceptance criterion. The implementation PR must also include a table mapping **every** checkbox of spec Groups A–H to the matrix row, scenario, or mirror-harness assertion that exercises it; any criterion with no exercise gets a new row before implementation is marked done. The rows exercise behavior that wiring alone cannot prove. Before marking implementation complete, execute
every matrix row above (B1–B11, C1–C2, D1–D2, E1–E3, F1–F5, G1, H1–H13), as
the implementation plan Testing Strategy requires, including at least one
blocking and one non-blocking outcome on real or fixture plan text.
