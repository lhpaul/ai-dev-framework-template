# Smoke Test Runbook: Structured Retro Metrics and Meta-Retrospective Protocol

**Feature**: Structured Retro Metrics and Meta-Retrospective Protocol (#458)
**Spec**: [docs/specs/developments/20260504142608_structured-retro-metrics/1_structured-retro-metrics_specs.md](../../specs/developments/20260504142608_structured-retro-metrics/1_structured-retro-metrics_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out locally
- [ ] `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` has been updated with Step 3d
- [ ] `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` exists
- [ ] `docs/workflow/retro-metrics.md` exists with column headers
- [ ] Agent and skill files have been updated

---

## Test Data

| Item | Value |
|---|---|
| Protocol under test (retrospective) | `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` |
| Protocol under test (meta) | `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` |
| Metrics log file | `docs/workflow/retro-metrics.md` |
| Agent file (Claude Code) | `.claude/agents/retrospective.md` |
| Agent file (Cursor) | `.cursor/agents/retrospective.md` |
| Skill file (Codex) | `.codex/skills/workflow-retrospective/SKILL.md` |

---

## Smoke Test Steps

### Step 1: Verify metrics block is defined in `06-retrospective-protocol.md`

**Maps to**: Acceptance Criterion 1, 2

1. Open `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`.
2. Locate Step 3d (Metrics Block) — it should appear between Steps 3c and Step 4.
3. Confirm Step 3d defines all six required fields: batch identifier, human interventions count, Step 5.2 violations count, automated-reviewer retry loops count, escalations count, and prior action item recurrence assessment.
4. Confirm each field has a clear, unambiguous definition (not just a label).
5. Confirm the "unavailable" rule is stated (BR-7).
6. Confirm that a value of zero is explicitly noted as valid.

**Expected result**: Step 3d is present; all six fields are defined with descriptions; "unavailable" rule and zero-validity are stated.

---

### Step 2: Verify metrics block is included in Step 4 output format

**Maps to**: Acceptance Criterion 2

1. In the same file, locate Step 4 (Present Findings).
2. Confirm the metrics block is included in the structured output format shown in Step 4.

**Expected result**: Step 4 output format includes the metrics block section alongside improvement opportunities.

---

### Step 3: Verify append instruction is in Step 6

**Maps to**: Acceptance Criterion 3

1. In the same file, locate Step 6 (Close).
2. Confirm Step 6 instructs the analyst to append the finalized metrics block to `docs/workflow/retro-metrics.md` after completing Step 5 actions.
3. Confirm the append instruction specifies the table row format.

**Expected result**: Step 6 references `docs/workflow/retro-metrics.md` and specifies how to format the appended row.

---

### Step 4: Verify "See also" reference to meta-retrospective protocol

**Maps to**: Acceptance Criterion 8

1. Scroll to the end of `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`.
2. Confirm a "See also" section or equivalent closing reference to `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` exists.
3. Confirm the recommended cadence (every 5 batches) is mentioned.

**Expected result**: Closing reference to `06b-meta-retrospective-protocol.md` exists with cadence note.

---

### Step 5: Verify `docs/workflow/retro-metrics.md` exists and has correct headers

**Maps to**: Acceptance Criterion 7

1. Open `docs/workflow/retro-metrics.md`.
2. Confirm the file exists and has a Markdown table header row.
3. Confirm column names match the six required fields from Step 3d exactly.
4. Confirm no data rows exist (initial state — headers only).

**Expected result**: File exists; table headers present; column names match required fields; no data rows.

---

### Step 6: Verify `06b-meta-retrospective-protocol.md` exists and has all required sections

**Maps to**: Acceptance Criteria 4, 5, 6

1. Open `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`.
2. Confirm the file exists.
3. Confirm the following sections are present: scope resolution (reading the metrics log), trend analysis step, classification step with all three outcomes ("Verified fixed", "Partially fixed", "Still recurring"), escalation step for "Still recurring" items, human-approval gate step, backlog update step.
4. Confirm the default analysis window of 5 entries is documented.
5. Confirm documentation on how to override the window.
6. Confirm the escalation severity for "Still recurring" items is stated as "high".
7. Confirm the protocol states that trend data is directional and the analyst must not overstate confidence.
8. Confirm the constraint that the meta-retrospective must not edit historical entries in `docs/workflow/retro-metrics.md`.

**Expected result**: All required sections present; window default = 5; override documented; "Still recurring" → severity high; directional-only confidence note; no-edit constraint stated.

---

### Step 7: Verify graceful handling of fewer-than-window entries

**Maps to**: Acceptance Criterion 6, 9

1. In `06b-meta-retrospective-protocol.md`, locate the scope resolution step (Step 1).
2. Confirm it states that when fewer entries than the window size are available, the analyst uses all available entries and explicitly notes the limited data.
3. Confirm it does not require a minimum of 3 entries (or any minimum) to proceed.

**Expected result**: Protocol permits running with any number of available entries (including 1); limited-data note is required but does not block execution.

---

### Step 8: Verify agent files reference metrics block

**Maps to**: Acceptance Criterion 1 (agent-level enforcement)

1. Open `.claude/agents/retrospective.md`.
2. Confirm it references the metrics block step as part of the retrospective flow.
3. Confirm it references `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`.
4. Open `.cursor/agents/retrospective.md` and confirm the same additions are present.
5. Open `.codex/skills/workflow-retrospective/SKILL.md` and confirm it references the metrics block and the append-to-log step.

**Expected result**: All three agent/skill files reference the metrics block and meta-retrospective protocol.

---

### Step 9: Verify AGENTS.md and README.md reference meta-retrospective

**Maps to**: Acceptance Criterion 8 (discoverability)

1. Open `AGENTS.md` (or `CLAUDE.md` — they are symlinked).
2. Confirm `06b-meta-retrospective-protocol.md` is referenced in the Workflow Commands section.
3. Open `docs/workflow/development-workflow/README.md`.
4. Confirm `06b-meta-retrospective-protocol.md` is referenced in the Workflow Commands table.

**Expected result**: Both files reference the meta-retrospective protocol in their command reference sections.

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met
- No application to shut down — this is a documentation-only feature

---

## Assertions Checklist

- [ ] `06-retrospective-protocol.md` Step 3d exists between Steps 3c and Step 4 with all six required fields defined
- [ ] The "unavailable" rule and zero-validity are stated in Step 3d
- [ ] Step 4 output format includes the metrics block
- [ ] Step 6 instructs appending the finalized metrics block to `docs/workflow/retro-metrics.md` with a table row format
- [ ] Step 6 or closing section references `06b-meta-retrospective-protocol.md` with recommended cadence
- [ ] `docs/workflow/retro-metrics.md` exists with column headers matching the six required fields and no data rows
- [ ] `06b-meta-retrospective-protocol.md` exists with all required sections (scope, trend, classify, escalate, human gate, backlog update)
- [ ] Default analysis window of 5 is documented in `06b-meta-retrospective-protocol.md`
- [ ] Fewer-than-window handling documented (uses available entries, notes limited data, no minimum required)
- [ ] "Still recurring" escalation severity stated as "high" in `06b-meta-retrospective-protocol.md`
- [ ] No-edit constraint on historical entries stated in `06b-meta-retrospective-protocol.md`
- [ ] `.claude/agents/retrospective.md` references metrics block and meta-retrospective protocol
- [ ] `.cursor/agents/retrospective.md` same
- [ ] `.codex/skills/workflow-retrospective/SKILL.md` references metrics block and append step
- [ ] `AGENTS.md` and `README.md` reference `06b-meta-retrospective-protocol.md`

---

## Seed Data Reference

Not applicable — no application seed data. The `docs/workflow/retro-metrics.md` file is created with headers only.

| Entity | Scenario | How to load |
|---|---|---|
| Metrics log | Initial state (headers only) | Created by implementation; no action needed |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Step 3d not found in `06-retrospective-protocol.md` | Implementation missed inserting the step | Re-read the protocol and insert Step 3d after Step 3c |
| `docs/workflow/retro-metrics.md` missing | Implementation forgot to create the initial file | Create the file with column headers per Implementation Order Step 1 |
| `06b-meta-retrospective-protocol.md` missing | Implementation did not create the new protocol file | Create the file per Implementation Order Step 2 |
| Column headers in `retro-metrics.md` do not match `06-retrospective-protocol.md` Step 3d fields | Cross-section consistency check not performed | Run Step 9 (consistency check) from the Implementation Order and align field names |
| Agent files not updated | Implementation skipped Steps 4–6 | Update `.claude/agents/retrospective.md`, `.cursor/agents/retrospective.md`, `.codex/skills/workflow-retrospective/SKILL.md` |

---

## Known Limitations

- The smoke test is manual; it verifies the presence and correctness of documentation content rather than exercising a running application.
- The accuracy of the metrics block fields (e.g., human interventions count) depends on the analyst's judgment and available GitHub data — this cannot be smoke-tested automatically.
