# Smoke Test Runbook: Cross-Check Cross-Cutting Plan Assumptions

**Feature**: Cross-Check Cross-Cutting Plan Assumptions (#1201)
**Spec**: [`../../specs/developments/20260723153924_1201-cross-check-cross-cutting-plan-assumptions/1_1201-cross-check-cross-cutting-plan-assumptions_specs.md`](../../specs/developments/20260723153924_1201-cross-check-cross-cutting-plan-assumptions/1_1201-cross-check-cross-cutting-plan-assumptions_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Check out the #1201 implementation branch in its assigned worktree.
- [ ] Confirm Protocols 02, 03, 90, and 91, the implementation-plan template,
      `REVIEW.md`, and the enumerated runner mirrors contain the implemented
      contract.
- [ ] Confirm
      `scripts/development-workflow/tests/test-cross-cutting-plan-assumption-contract.sh`
      exists and is executable.
- [ ] Use a temporary plan fixture or documentation example; do not mutate a
      real unrelated workflow item's approved plan.

> This is a workflow documentation feature. No application server, browser,
> database, cloud project, or seed data is required.

---

## Test Data

| Item | Value |
| --- | --- |
| Applicable assumption | Approved base branch `develop` |
| Authoritative source | Parent batch handoff plus repository workflow ownership rules |
| Consistent related evidence | Current-batch item that touches unrelated workflow behavior |
| Conflict evidence | Related item or PR that changes the approved base to a different value |
| Unverifiable evidence | Recorded source that cannot be read |
| Keyword-only lookalike | Unrelated PR that says "develop" but does not change the approved-base surface |
| Not-applicable plan | Prose-only change with no environment, linked resource, base, or canonical-config dependency |

---

## Smoke Test Steps

### Step 1: Applicable plan records provenance and bounded scope

**Maps to**: AC1, AC2

1. Follow Protocol 02 for the applicable-assumption fixture.
2. Fill the template's operational-assumption evidence row.
3. Inspect the completed row and the planner's bounded cross-check.

**Expected result**: The plan records the assumption value, authoritative
source, verification time, exact current-batch/related-PR scope, and result. The
check is limited to the current batch and plausibly related PRs.

### Step 2: Consistent evidence allows planning to continue

**Maps to**: AC1, AC2, AC8

1. Include one current-batch item that does not change the approved-base
   assumption surface.
2. Include the keyword-only lookalike PR.
3. Classify the evidence.

**Expected result**: Both records remain non-conflicting. Shared terminology is
not sufficient; the result is `Verified` only because the authoritative source
and same-surface evidence agree.

### Step 3: Same-surface conflict blocks implementation

**Maps to**: AC3, AC8

1. Replace the related evidence with the conflict fixture.
2. Record both competing base values and the affected plan statements.
3. Attempt to advance the item from planning toward implementation.

**Expected result**: The plan records `Conflict`, resolution status, and decision
owner. Protocol 91 prevents implementation from starting until the parent
orchestrator records a resolution.

### Step 4: Parent resolves sufficient evidence

**Maps to**: AC3

1. Provide the parent orchestrator with one authoritative owning source.
2. Record the selected interpretation and decision owner.
3. Update the fixture plan and repeat the transition check.

**Expected result**: The outcome becomes `Resolved`; the plan reflects the
authoritative value and may resume its normal review/readiness lifecycle.

### Step 5: Ambiguous conflict requests a human decision

**Maps to**: AC4

1. Use two credible sources with different values and no authoritative ordering.
2. Follow Protocol 90/91 conflict handling.

**Expected result**: The workflow emits the named `unclear_requirements` stop,
identifies the affected item and competing evidence, and asks the human to
select or provide the authoritative source. It does not guess.

### Step 6: Implementation-start re-verification succeeds

**Maps to**: AC5

1. Use a reviewed plan with one applicable assumption and unchanged source.
2. Begin the Full Pipeline or Refactor prep sequence in Protocol 03.
3. Re-read the recorded authoritative source before any implementation file
   edit.

**Expected result**: The implementer records `Still valid` with current evidence
and then proceeds. The plan-time timestamp alone is not accepted as current
proof.

### Step 7: Stale or unverifiable evidence stops before edits

**Maps to**: AC6

1. Repeat Step 6 with a changed source, conflicting in-flight evidence, and then
   the unverifiable-source fixture.
2. Attempt to begin implementation in each case.

**Expected result**: Each case records `Stale or conflicting`, stops before file
edits, and returns the evidence to the parent orchestrator. No implementation
commit is created from the stale assumption.

### Step 8: Not-applicable path avoids portfolio scanning

**Maps to**: AC7

1. Follow Protocol 02 for the not-applicable fixture.
2. Record the concise rationale.
3. Inspect the commands/evidence requested by the workflow.

**Expected result**: The plan records `Not applicable` with a reason and proceeds
without listing or scanning every open PR in the repository.

### Step 9: Automated mirror contract remains aligned

**Maps to**: AC1-AC8

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-cross-cutting-plan-assumption-contract.sh
   ```

2. Inspect the output for Protocols 02/03/90/91, the template, review contract,
   agents, skills, commands, and negative checks.

**Expected result**: The script exits zero and confirms all required evidence
fields, seven outcomes/next actions, bounded-scope rules, parent/human
resolution, and implementation-start re-verification remain represented.

---

## Assertions Checklist

- [ ] AC1: Applicable plan evidence includes assumption, source, and
      verification time.
- [ ] AC2: The planner records the bounded current-batch/related-PR scope and
      result.
- [ ] AC3: Same-surface conflict is recorded and blocks implementation until
      parent resolution.
- [ ] AC4: Unresolvable conflict asks a human instead of guessing.
- [ ] AC5: Plan-backed implementation re-verifies each applicable source before
      implementation edits.
- [ ] AC6: Changed, conflicting, or unverifiable evidence stops and returns to
      the parent.
- [ ] AC7: A not-applicable plan records a reason without an all-open-PR scan.
- [ ] AC8: Shared terminology alone does not create a conflict.

---

## Seed Data Reference

No application seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Workflow fixtures | Applicable, consistent, conflicting, unverifiable, keyword-only, and not-applicable documentation cases | Created temporarily by the contract test or followed manually from **Test Data** |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Applicable row lacks a verification time | The plan used prose instead of the template evidence fields | Add the source and UTC verification time before review |
| Every open PR is listed | The bounded relevance rule was ignored | Restrict scope to the exact current batch and only same-surface related PRs |
| Keyword-only PR is marked conflicting | Relevance was inferred from terminology | Require evidence that the PR changes the same operational assumption surface |
| Implementation starts after a changed source | Protocol 03 re-verification was skipped | Stop before edits and return current evidence to the parent orchestrator |
| Mirror contract test fails on one tool | A role-specific agent, skill, or command drifted | Align that mirror with its canonical protocol without copying unrelated detail |

---

## Known Limitations

- The workflow makes applicable assumptions and detected conflicts visible; it
  does not automatically discover every implicit assumption in prose.
- The bounded related-PR selection remains a reasoned planner decision; the
  feature does not add a repository-wide matching algorithm.
- Parent resolution cannot replace a human decision when authoritative evidence
  is genuinely ambiguous.
