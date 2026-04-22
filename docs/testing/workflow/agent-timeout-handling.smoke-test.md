# Smoke Test Runbook: Agent Timeout Handling

**Feature**: Agent Timeout Handling — protocol and config documentation for timed-out item-orchestrator runs
**Spec**: [`docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md`](../../specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation is complete and merged into `develop`
- [ ] You have access to the three updated files:
  - `docs/workflow/development-workflow/agent-model-config.md`
  - `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  - `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- [ ] No running environment or database is required — this is a documentation review

---

## Test Data

| Item | Value |
|---|---|
| Feature | Agent timeout handling documentation |
| Files under review | See Prerequisites |
| No seed data required | N/A |

---

## Smoke Test Steps

### Step 1: Verify `agent-model-config.md` — Expected Run Durations

**Maps to**: Acceptance Criterion 2

1. Open `docs/workflow/development-workflow/agent-model-config.md`
2. Locate the section covering expected run durations for agents
3. Confirm the section includes documented durations for `item-orchestrator` and `automated-reviewer-loop`
4. Confirm each entry specifies a typical range and a "consider timeout at" threshold

**Expected result**: Both `item-orchestrator` and `automated-reviewer-loop` have documented duration ranges (e.g., "typical: 5–15 min; consider timeout at ~25 min" for item-orchestrator).

---

### Step 2: Verify `agent-model-config.md` — Resume Guide (scannable in ≤ 30 seconds)

**Maps to**: Acceptance Criterion 3

1. Open `docs/workflow/development-workflow/agent-model-config.md`
2. Locate the "Resume a Timed-Out Agent Run" section (or equivalent heading)
3. Within 30 seconds, identify:
   a. The detection checklist (which signals indicate an incomplete run)
   b. The resume command to invoke
   c. The warning not to manually apply `ready-for-human-review`

**Expected result**: All three items (detection checklist, resume command, warning) are present and scannable without reading the full document.

---

### Step 3: Verify `91-orchestrate-work-protocol.md` — Step 8c Reviewer Loop Comment Check

**Maps to**: Acceptance Criterion 1

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
2. Navigate to Step 8c (Post-Label Independent Verification)
3. Locate the verification table
4. Find the row for "Automated reviewer loop summary"
5. Verify the row explicitly states that at least one comment containing `"Automated Reviewer Loop Summary"` or `"No blocking PR feedback"` must be present
6. Verify the row (and any surrounding prose) marks this check as a **required / non-removable hard gate** before `ready-for-human-review` is applied — wording such as "must", "required", "hard gate", or "non-removable" must be present so the check cannot be treated as optional

**Expected result**: The check row is present in the Step 8c table, the wording is explicit, and the check is clearly marked as a non-removable hard gate. Partial implementations that only mention the presence check without the hard-gate wording fail this step.

---

### Step 4: Verify `90-batch-orchestrate-work-protocol.md` — Stale PR Detection Heuristic

**Maps to**: Acceptance Criterion 4

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
2. Navigate to Step 5.1 (Post-Dispatch PR Verification) or the section immediately following it
3. Locate the "Stale / Incomplete PR Detection" subsection (or equivalent heading)
4. Confirm the subsection includes:
   a. The detection heuristic (labels present, summary comment absent → incomplete)
   b. A detection command or approach for the orchestrator to use
   c. The required action (re-dispatch item-orchestrator to resume from Step 7)

**Expected result**: All three items are present and actionable.

---

### Step 5: Confirm Documentation-Only Change

**Maps to**: Acceptance Criterion 5

1. Run `git diff --name-only develop...HEAD` (or review the PR file list)
2. Confirm every changed file is a Markdown (`.md`) file
3. If any non-`.md` file appears in the list, fail this smoke test

**Expected result**: All changed files are Markdown (`.md`) files; no code, scripts, CI, configuration, or non-`.md` asset files appear in the diff.

---

### Last Step: Validate and Record

- Review all assertions in the checklist below
- No environment shutdown required (documentation-only test)

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] **AC1**: Step 8c of `91-orchestrate-work-protocol.md` includes an explicit check for the reviewer loop summary comment (`"Automated Reviewer Loop Summary"` or `"No blocking PR feedback"`) before `ready-for-human-review` is applied, the check is clearly stated as a required / non-removable hard gate, and the hard-gate wording (e.g., "must", "required", "hard gate", "non-removable") is present in the table row or surrounding prose.
- [ ] **AC2**: `agent-model-config.md` documents expected maximum run durations for `item-orchestrator` (e.g., typical 5–15 min; consider timeout at ~25 min) and `automated-reviewer-loop` (e.g., typical 2–10 min; consider timeout at ~20 min).
- [ ] **AC3**: `agent-model-config.md` includes a "Resume a Timed-Out Agent Run" section covering (a) detection signals checklist, (b) resume command, and (c) explicit warning against manually applying `ready-for-human-review`.
- [ ] **AC4**: `90-batch-orchestrate-work-protocol.md` documents the stale/incomplete PR heuristic and the action to re-dispatch item-orchestrator to resume from Step 7.
- [ ] **AC5**: No code, scripts, CI configuration, or non-documentation files were changed.

---

## Seed Data Reference

None required — documentation-only feature.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Section not found in `agent-model-config.md` | Implementation missed an acceptance criterion | Re-run implementation for the missing criterion |
| Step 8c check row present but wording is vague | Implementation confirmed existence without strengthening clarity | Update the row wording to be explicit |
| Stale PR heuristic is described but has no detection command | Implementation incomplete | Add the detection command/approach to the subsection |

---

## Known Limitations

- This smoke test is a manual document review, not an automated test. There is no CI check that verifies the protocol document contents.
- The "30-second scannability" criterion (AC3 UX rule) is subjective; any operator reviewing the section within 30 seconds satisfies it.
