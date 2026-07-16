# Smoke Test Runbook: Prevent False Dependencies From Keyword Overlap

**Feature**: Prevent false dependencies from keyword overlap
**Spec**: [docs/specs/developments/20260714170339_1182-prevent-false-dependencies-from-keyword-overlap/1_1182-prevent-false-dependencies-from-keyword-overlap_specs.md](../../specs/developments/20260714170339_1182-prevent-false-dependencies-from-keyword-overlap/1_1182-prevent-false-dependencies-from-keyword-overlap_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in a clean checkout of the implementation branch.
- [ ] `gh`, `jq`, and standard POSIX shell tools are available.
- [ ] The helper tests pass locally:
  `bash scripts/development-workflow/tests/test-spec-dispatch-context.sh`.
- [ ] No real tracker mutations are performed during this smoke test; use
  helper fixtures or dry-run orchestration evidence.

---

## Test Data

| Item | Value |
| ---- | ----- |
| Selected issue fixture | Internal state switcher within one public-site component instance |
| Peer issue fixture | Allow multiple instances of the same public-site component type |
| Dependent fixture | Issue text with explicit `depends on #N` evidence |
| Unclear fixture | Issue text with coupling language but no concrete prerequisite |
| Decision fixture | Human-confirmed design decision JSONL or issue comment |

---

## Smoke Test Steps

### Step 1: Verify Orthogonal Keyword Overlap

**Maps to**: AC-1, AC-5, AC-6

1. Run the helper against the issue #1182-style fixtures.
2. Inspect the selected item's relationship output.
3. Confirm the shared `public site components` terminology is listed as overlap
   evidence but not as dependency evidence.

**Expected result**: The relationship outcome is `Orthogonal`; the dispatch
context does not tell the spec writer to assume a prerequisite, shared data
model, or shared implementation path.

### Step 2: Verify Confirmed Decision Preservation

**Maps to**: AC-2

1. Run the helper with a confirmed-decision fixture for the selected item.
2. Inspect `confirmedDecisions[]` in the helper output.
3. Confirm the summary is concise and includes source context when available.

**Expected result**: The spec-dispatch context includes the human-confirmed
decision before spec writing begins.

### Step 3: Verify Dependent Evidence

**Maps to**: AC-3

1. Run the helper against a selected item and peer item where one issue
   explicitly references the other as `depends on #N`, `blocked by #N`,
   `requires #N`, or `waiting on #N`.
2. Inspect the relationship output and evidence list.

**Expected result**: The relationship outcome is `Dependent`, and the output
includes the concrete evidence that supports the dependency.

### Step 4: Verify Unclear Stop Behavior

**Maps to**: AC-4

1. Run the helper against fixtures that share terminology and contain coupling
   language but do not provide concrete dependency or independence evidence.
2. Inspect the helper output.
3. Confirm the orchestration protocol evidence would stop before spec dispatch.

**Expected result**: The helper emits `Unclear`, `blocking=true`, and a
`humanAction` message naming the missing relationship decision.

### Step 5: Verify Workflow-Level Coverage

**Maps to**: AC-7, AC-8

1. Inspect the implementation diff for Protocol 90 and Protocol 91.
2. Confirm both paths require the spec-dispatch context before Backlog spec
   starts.
3. Inspect the spec-writer guidance and confirm it consumes the context without
   turning implementation mechanics into spec requirements.

**Expected result**: Batch and single-item spec-dispatch paths are covered, and
the implementation mechanism is the plan-selected helper plus ephemeral JSON
data model.

---

## Assertions Checklist

- [ ] AC-1: Shared product-area terminology alone does not create a dependency.
- [ ] AC-2: Human-confirmed design decisions are included in spec-dispatch
  context.
- [ ] AC-3: `Dependent` relationships cite concrete evidence.
- [ ] AC-4: `Unclear` relationships that could affect scope stop dispatch.
- [ ] AC-5: `Orthogonal` dispatch context avoids false dependency language.
- [ ] AC-6: The issue #1182 example classifies as `Orthogonal`.
- [ ] AC-7: Workflow-level verification covers `Dependent`, `Orthogonal`, and
  `Unclear` outcomes.
- [ ] AC-8: The implementation uses the plan-selected helper, data model,
  matching algorithm, and no persistent storage.

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
| ------ | -------- | ----------- |
| Shell fixtures | Orthogonal, Dependent, Unclear, confirmed decision, and issue #1182 regression | Created inside `scripts/development-workflow/tests/test-spec-dispatch-context.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Helper output has no relationship rows | Fixture overlap is below the meaningful-overlap threshold | Add at least two significant shared terms or one shared phrase to the fixture. |
| Orthogonal case becomes Dependent | Dependency phrase detector is matching a negative lookalike | Check the negative-lookalike unit test and tighten the evidence matcher. |
| Unclear case dispatches anyway | Protocol 90 or 91 did not check `blocking=true` before spec dispatch | Update the protocol step and mirrored agent guidance. |

---

## Known Limitations

- This runbook validates workflow behavior through helper output and protocol
  evidence. It does not perform live tracker mutations.
