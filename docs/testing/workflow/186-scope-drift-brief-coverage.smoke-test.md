# Smoke Test Runbook: Scope Drift Brief Coverage (Issue #186)

**Feature**: Detect and surface scope drift (brief ↔ spec, spec ↔ repo at plan time)  
**Spec**: [`docs/specs/developments/20260420153000_scope-drift-brief-coverage/1_scope-drift-brief-coverage_specs.md`](../../specs/developments/20260420153000_scope-drift-brief-coverage/1_scope-drift-brief-coverage_specs.md)  
**Created in**: Plan Ready stage  
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation PR for issue **#186** is merged or available on a branch
- [ ] You can run `rg` (ripgrep) from the repository root
- [ ] You have read the issue brief ([GitHub #186](https://github.com/lhpaul/ai-dev-framework-template/issues/186)) for context

---

## Test Data

| Item | Value |
|---|---|
| Spec protocol | `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` |
| Plan protocol | `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Review contract | `REVIEW.md` |
| AC5 fixture | `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md` (created during implementation) |

---

## Smoke Test Steps

### Step 1: Spec protocol — brief coverage mechanics

**Maps to**: **AC3**, **AC2**, **AC1** (synthetic three-objective scenario)

1. Open `01-generate-spec-protocol.md`.
2. Verify the document defines all of: **Brief Objective List**, **Coverage Matrix** (mapping each objective to AC ids or `## Out of Scope (MVP)`), and a requirement that the **draft PR body** includes a Coverage Matrix summary before human-ready automation.
3. Verify **Deferral Note** behavior is documented for objectives placed under Out of Scope (visible in spec and PR description / alignment stand-in).

**Expected result**: A new agent session could follow the protocol without reading the full narrative spec.

### Step 2: Spec protocol — synthetic three-objective mental walkthrough

**Maps to**: **AC1**

1. Imagine a GitHub issue brief with three numbered required objectives.
2. Trace the protocol: confirm it requires each objective to appear in the matrix as mapped ACs or explicit out-of-scope rows before the draft spec PR is opened.

**Expected result**: No step allows a brief objective to be omitted without an explicit row.

### Step 3: Plan protocol — live search vs frozen enumeration

**Maps to**: **AC4**

1. Open `02-generate-implementation-plan-protocol.md`.
2. Verify it states when **live repository search at plan-write time** is mandatory vs when a **spec-frozen** subset is allowed (with quoting the authorizing spec section).
3. Verify it requires a **Verification Log** in implementation plans (command, repo revision, and how outputs drive Summary / Documentation Updates counts).

**Expected result**: Plan writers cannot treat stale AC enumerations as authoritative when the spec implies pattern completeness.

### Step 4: Fixture + live count (stale enumeration vs pattern)

**Maps to**: **AC5**

1. Open `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md`.
2. Run the exact search command documented in that fixture (or in the implementation PR description) from the repo root.
3. Compare the **live result count** to the **stale list length** embedded in the fixture.

**Expected result**: Live count is strictly greater than the stale enumerated list (proving the mismatch the plan-writer rules must catch).

### Step 5: `REVIEW.md` — internal gates

**Maps to**: **AC6**, **AC7**

1. Under **Spec Review Checklist**, verify at least one bullet instructs reviewers to verify **brief-to-spec coverage** when a tracker issue is linked.
2. Under **Plan Review Checklist**, verify at least one bullet instructs reviewers to verify **enumerated counts/paths against the plan’s Verification Log** when pattern-based completeness applies.

**Expected result**: Both bullets are present and read as **blocking**-class checks (same severity class as contradictory acceptance criteria per spec BR-6).

### Step 6: Optional agent / skill discoverability

**Maps to**: Supporting traceability for **AC3**, **AC4**

1. If agent files were updated, open `.cursor/agents/product-manager.md` and `.cursor/agents/tech-lead.md` (and `.claude/agents/*` mirrors) and confirm they reference the new protocol sections.
2. If Codex skills were updated, confirm `workflow-spec-writer` / `workflow-plan-writer` skills mention the new mandatory checks.

**Expected result**: No broken relative links; references point to real headings or sections.

### Last Step: Validate & Shut Down

- Confirm every assertion in the checklist below is satisfied
- No local-only files were required for the smoke test beyond the repository

---

## Assertions Checklist

- [ ] **AC1**: Protocol 01 documents Coverage Matrix behavior for multi-objective briefs before draft PR open
- [ ] **AC2**: Protocol 01 documents Deferral Notes for out-of-scope brief objectives in human-visible surfaces
- [ ] **AC3**: Protocol 01 alone is sufficient for a cold-start agent to perform brief coverage without reading the feature spec narrative
- [ ] **AC4**: Protocol 02 documents live search vs freeze + Verification Log
- [ ] **AC5**: Fixture exists; live search count contradicts stale enumeration as documented
- [ ] **AC6**: `REVIEW.md` spec checklist includes brief-to-spec coverage bullet
- [ ] **AC7**: `REVIEW.md` plan checklist includes Verification Log vs enumeration bullet

---

## Seed Data Reference

| Entity | Scenario | How to load |
|---|---|---|
| Fixture markdown | Stale list vs pattern | Read `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `rg` count matches stale list | Fixture path or pattern too narrow | Widen pattern in fixture to a stable directory as defined in implementation PR |
| Cannot find new headings | Implementation on different branch | Check out the feature branch that merged #186 |

---

## Known Limitations

- This smoke test does not execute the full spec-writer or plan-writer agents; it validates **documentation and fixture correctness** only.
