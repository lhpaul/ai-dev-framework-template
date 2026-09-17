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
