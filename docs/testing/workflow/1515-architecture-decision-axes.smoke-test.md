# Smoke Test Runbook: Axis-Separated Architecture Decision Escalations

**Feature**: Axis-separated architecture decision escalations (#1515)
**Spec**: [`../../specs/developments/20260911230558_1515-architecture-decision-axes/1_1515-architecture-decision-axes_specs.md`](../../specs/developments/20260911230558_1515-architecture-decision-axes/1_1515-architecture-decision-axes_specs.md)
**Plan**: [`../../specs/developments/20260911230558_1515-architecture-decision-axes/2_1515-architecture-decision-axes_implementation-plan.md`](../../specs/developments/20260911230558_1515-architecture-decision-axes/2_1515-architecture-decision-axes_implementation-plan.md)
**Created in**: Plan Ready stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch includes the canonical page, protocol edits,
      agent/skill mirrors, `REVIEW.md` bullet, and test audit extension from
      the plan.
- [ ] You can read Markdown in the repo; no application server is required.

---

## Test Data

| Item | Value |
| --- | --- |
| Canonical page | `docs/workflow/development-workflow/architecture-decision-escalation.md` |
| PR marker | `<!-- architecture-decision-escalation -->` |
| Stop condition token | `architecture_decision` (unchanged trigger) |
| Worked example reference | Spec Examples table (review-cycle / cumulative-effort incident) |

---

## Smoke Test Steps

### Step 1: Canonical page completeness

Open the canonical page and confirm it includes:

- [ ] Scope (escalation reports + supportive citations in review-thread replies).
- [ ] Vocabulary tables matching spec display labels.
- [ ] Report outline with requested decision scoped to open axes only.
- [ ] Optional **Recommendation** element documented as separate from requested
      decision.
- [ ] Prohibition on acting on, pre-answering, or ratifying open axes.
- [ ] **Per-citation declaration rule (mixed reports)** (spec gap 2 resolution).
- [ ] **Raised-question gate** for substance-undetermined incomplete reports
      (spec gap 1 resolution).
- [ ] Worked example with at least one settled axis, one open axis, a `Departs`
      citation, and a mis-attached argument label.

**Expected**: A reader can assemble a well-formed escalation without opening the
full spec matrix.

### Step 2: Stop-message contract alignment

Read `guardrails-enforcement.md` §5 `architecture_decision` subsection.

- [ ] Three baseline stop elements remain required unchanged.
- [ ] Human action for complete reports names open axes only.
- [ ] Incomplete-report human actions reference malformed-input remedies.
- [ ] Substance confirmation is gated on an **actually raised** question.

**Expected**: No wording implies substance confirmation for merely internal
runner uncertainty when nobody raised the question.

### Step 3: Protocol 91 runner stop path

Search Protocol 91 for `architecture_decision` / canonical page link.

- [ ] Coverage analysis is required before the terminal stop summary.
- [ ] PR durability: when a PR exists, instructions require an **upsert** (find
      marker in paginated issue comments, PATCH if present else POST) with the
      HTML marker and `## Architecture decision escalation` heading — same
      idempotency pattern as `find_marker_comment_id` in
      `run-epic-audit-trail.sh`.
- [ ] Continuation when all axes are settled is documented as "trigger not
      met", not as overriding a genuine stop.
- [ ] That continuation is **not** offered when a reviewer or human has raised
      a question about a citation's substance that the runner cannot resolve;
      that case stops as an incomplete `architecture_decision` escalation.

**Expected**: Protocol points to canonical page instead of restating full rules.

### Step 4: Protocol 93 review-thread declarations

Search Protocol 93 for conformance declaration requirement.

- [ ] Reply guidance requires `Conforms` / `Departs` / `Not yet implemented`
      when citing a workflow specification line as support.
- [ ] `Not yet implemented` is never prescribed for behavior that already exists
      in the cited surface (declaration misuse).
- [ ] Undetermined conformance uses plain language without enum values.
- [ ] Escalation to full report references Protocol 91 + canonical page.

**Expected**: Review-thread surface matches spec MVP scope.

### Step 5: Mirror surfaces (agents and skills)

For each path below, confirm a direct requirement (not link-only) and a pointer
to the canonical page:

- [ ] `.cursor/agents/item-orchestrator.md`
- [ ] `.claude/agents/item-orchestrator.md`
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md`
- [ ] `.agents/skills/run-item/SKILL.md`
- [ ] `.cursor/agents/automated-reviewer-loop.md`
- [ ] `.claude/agents/automated-reviewer-loop.md`
- [ ] `.codex/skills/workflow-reviewer-loop/SKILL.md`
- [ ] `.cursor/agents/developer.md`
- [ ] `.claude/agents/developer.md`
- [ ] `.codex/skills/workflow-implementer/SKILL.md`
- [ ] `.cursor/agents/code-reviewer.md`
- [ ] `.claude/agents/code-reviewer.md`
- [ ] `.codex/skills/workflow-code-reviewer/SKILL.md`
- [ ] `.cursor/agents/orchestrator.md` — Protocol 90 parity sentence present, or
      documented as already covered by protocol pointer (Layer H criterion)
- [ ] `.claude/agents/orchestrator.md` — same criterion
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` — same criterion

**Expected**: No mirror describes a well-formed `architecture_decision`
escalation without axis/coverage analysis.

### Step 5b: Protocol 90 batch stop reporting

- [ ] Protocol 90 links the canonical page and requires the batch summary to
      reference the child's canonical escalation report for an
      `architecture_decision` stop.

### Step 6: README index

- [ ] `docs/workflow/development-workflow/README.md` lists the canonical page
      under Tooling And Configuration.

### Step 7: Automated audit extension

```bash
bash scripts/development-workflow/tests/test-worktree-recipe.sh
```

**Expected**: Exit 0; new fixtures covering the canonical escalation surface
pass.

### Step 8: REVIEW.md checklist

- [ ] `REVIEW.md` includes a workflow-doc review bullet for axis separation,
      mixed-report declarations, and open-axis requested decisions.

---

## Acceptance Criteria Traceability

| Acceptance group | Smoke steps |
| --- | --- |
| The escalation names the question and its axes | 1, 3 |
| Every axis carries a verdict | 1, 3 |
| Citations carry a conformance declaration | 1, 4, 5 |
| The requested decision covers only the open axes | 1, 2, 3 |
| The requirement never suppresses a stop | 1, 3 |
| The guidance carries a worked example | 1 |
| Surfaces agree | 2–6, 8 |
