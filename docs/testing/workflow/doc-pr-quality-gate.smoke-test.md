# Document PR Quality Gate Smoke Test

**Feature**: Doc PR quality gate
**Spec**: [1_doc-pr-quality-gate_specs.md](../../specs/developments/20260606094538_doc-pr-quality-gate/1_doc-pr-quality-gate_specs.md)

## Purpose

Verify that spec and implementation-plan PRs include a compact document quality
gate before reviewer readiness loops begin.

## Preconditions

- A test tracker issue exists with a short brief and at least one acceptance
  criterion.
- The workflow is run from a branch that can open draft PRs.
- The changed documentation has been linted with `markdownlint-cli2`.

## Scenario 1: Spec Gate

1. Run Protocol 01 for the test issue.
2. Before opening the draft PR, inspect the generated spec.
3. Verify the spec covers each brief objective through acceptance criteria or
   explicit out-of-scope deferrals.
4. Verify the draft PR description contains a `Document Quality Gate` section
   with checked or not-applicable entries.

Expected result: the spec PR is not considered ready for Step 7a until the gate
log is present and current.

## Scenario 2: Plan Gate

1. Run Protocol 02 for the same item after the spec is approved.
2. Inspect the implementation plan before opening the draft PR.
3. Verify implementation order, file lists, verification evidence, and testing
   coverage are internally consistent.
4. Verify the draft PR description contains a `Document Quality Gate` section
   with checked or not-applicable entries.

Expected result: the plan PR is not considered ready for Step 7a until the gate
log is present and current.

## Scenario 3: Review Contract

1. Review a spec or plan PR whose description lacks the gate log.
2. Apply `REVIEW.md` to the PR.

Expected result: the missing log is an important finding by default, and it is
blocking when the PR claims unchecked coverage or contradicts the document.

## Scenario 4: Long Review Cycle

1. On a spec or plan PR with repeated automated reviewer cycles, inspect the gate
   log, latest reviewer-loop summary, advisory dispositions, and remaining
   reviewer findings.
2. Confirm every remaining finding is addressed, dispositioned, or escalated.

Expected result: stale or contradictory gate evidence is fixed before another
automated reviewer cycle, unless the next action is human escalation.

## Scenario 5: Existing Gates Remain Authoritative

1. Continue the PR through internal review, automated review, CI, labels, and
   tracker update per Protocol 91.
2. Confirm the gate log does not bypass reviewer or CI requirements.

Expected result: the gate is pre-submission evidence only; PR readiness still
requires the normal internal review, automated reviewer loop, CI, labels, and
tracker transitions.

## Scenario 6: Agent Guidance

1. Inspect the Claude and Cursor product-manager agent docs.
2. Verify they point spec authors to Protocol 01's Document Quality Gate.
3. Inspect the Claude and Cursor tech-lead agent docs.
4. Verify they point plan authors to Protocol 02's Document Quality Gate.
5. Inspect the Codex spec-writer and plan-writer skills.
6. Verify they delegate to Protocol 01/02 and do not define contradictory local
   gate behavior.

Expected result: agent-facing summaries route to the same canonical gate
behavior as the protocols.
