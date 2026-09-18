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

- The feature branch for #1496 is merged into `develop`.
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
   `Satisfied` in the outcome record.

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

Manual desk-check during implementation QA (or scripted where noted). Each row
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

Scenarios 1–6 above cover wiring; this matrix covers criterion-level outcomes
that wiring alone cannot prove. Before marking implementation complete, execute
at least the mandatory rows named in the implementation plan Testing Strategy
(B1, B3, C1, C2, D1, E1, F1, G1, H1, H3), including one blocking and one
non-blocking outcome on real or fixture plan text.
