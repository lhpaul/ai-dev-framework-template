# Smoke Test Runbook: Deprecate Direct Item-Orchestrator Command for Cursor Runs

**Feature**: Deprecate direct item-orchestrator command for Cursor runs (#1190)
**Spec**: [1_1190-deprecate-direct-item-orchestrator-cursor-runs_specs.md](../../specs/developments/20260713211636_1190-deprecate-direct-item-orchestrator-cursor-runs/1_1190-deprecate-direct-item-orchestrator-cursor-runs_specs.md)
**Implementation plan**: [2_1190-deprecate-direct-item-orchestrator-cursor-runs_implementation-plan.md](../../specs/developments/20260713211636_1190-deprecate-direct-item-orchestrator-cursor-runs/2_1190-deprecate-direct-item-orchestrator-cursor-runs_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

This feature changes workflow guidance and thin command/agent surfaces. The smoke
test is performed by repository inspection on the implementation branch.

- [ ] The implementation branch for #1190 is checked out.
- [ ] A terminal at the repository root is available.
- [ ] `rg`, `git`, and `markdownlint-cli2` are available.

---

## Test Data

| Item | Value |
| --- | --- |
| Cursor command | `.cursor/commands/run-item.md` |
| Cursor orchestrator agent | `.cursor/agents/item-orchestrator.md` |
| Shared guidance | `AGENTS.md` |
| Model-routing guidance | `docs/workflow/development-workflow/agent-model-config.md` |
| Mirrored run-item surfaces | `.claude/commands/run-item.md`, `.agents/skills/run-item/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md` |

---

## Smoke Test Steps

### Step 1: Confirm Cursor canonical command guidance

**Maps to**: AC1

1. Read `AGENTS.md`.
2. Read `.cursor/commands/run-item.md`.
3. Confirm both identify `/run-item <target>` as the normal Cursor path for a
   single non-epic workflow item.

**Expected result**: Cursor users are directed to `/run-item`, not to direct
`/item-orchestrator` invocation, for normal single-item advancement.

### Step 2: Classify remaining direct item-orchestrator references

**Maps to**: AC2, AC3

Run:

```bash
rg -n "Invoke them directly|/item-orchestrator|Cursor.*item-orchestrator|item-orchestrator.*Cursor" \
  AGENTS.md .cursor .claude .agents .codex docs/workflow/development-workflow docs/testing/workflow
```

For every remaining hit, classify it as one of:

- internal handoff / internal dispatch,
- legacy compatibility,
- historical smoke-test context,
- or a defect.

**Expected result**: No current Cursor-facing guidance presents direct
`/item-orchestrator` invocation as the normal user-facing path. Any remaining
reference is clearly internal, compatibility-oriented, or historical.

### Step 3: Verify Cursor handoff contract

**Maps to**: AC4, AC5

1. Read `.cursor/commands/run-item.md`.
2. Confirm it states that `/run-item` runs the bounded prelude first.
3. Confirm it states that internal handoff preserves confirmed scope and selected
   policy.
4. Confirm it states that the receiving internal orchestration context must not
   duplicate the bounded prelude or re-prompt for the same confirmed policy.

**Expected result**: The Cursor `/run-item` command describes a single prelude
and a no-duplicate-prompt internal handoff.

### Step 4: Verify stage-specific model-routing intent

**Maps to**: AC6, AC8

1. Read `docs/workflow/development-workflow/agent-model-config.md`.
2. Confirm the Cursor model defaults still pin stage-specific agents such as
   `item-orchestrator`, `product-manager`, `tech-lead`, `developer`, and
   `code-reviewer`.
3. Confirm the updated guidance explains that `/run-item` can use internal
   handoff so these configured roles/models are preserved.

**Expected result**: Model-routing intent is explicit and tied to `/run-item`
internal handoff, not to direct manual `/item-orchestrator` invocation.

### Step 5: Verify mirrored run-item surfaces stay aligned

**Maps to**: AC7

Inspect:

```bash
rg -n "canonical single-item|bounded prelude|RUN_ITEM_POLICY_CONFIRMED|item-orchestrator|/run-item" \
  .cursor/commands/run-item.md \
  .cursor/agents/item-orchestrator.md \
  .claude/commands/run-item.md \
  .claude/agents/item-orchestrator.md \
  .agents/skills/run-item/SKILL.md \
  .codex/skills/workflow-item-orchestrator/SKILL.md
```

**Expected result**: The surfaces agree that `/run-item` is canonical, the
bounded prelude remains first, and any `item-orchestrator` wording is compatible
with the internal role.

### Last Step: Validate markdown

Run markdown lint on changed markdown files, including this runbook.

**Expected result**: Markdown lint exits successfully.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: Cursor command guidance presents `/run-item <target>` as canonical.
- [ ] AC2: Cursor-facing docs do not instruct users to directly invoke
      `/item-orchestrator` as the normal workflow path.
- [ ] AC3: Remaining direct `item-orchestrator` references are internal,
      compatibility, or historical.
- [ ] AC4: Cursor `/run-item` runs the bounded prelude before internal handoff.
- [ ] AC5: Internal handoff does not duplicate the prelude or re-prompt for the
      same confirmed policy.
- [ ] AC6: Stage-specific handoff guidance covers configured Cursor agents.
- [ ] AC7: Mirrored `/run-item`, `/run-item-work`, and `item-orchestrator`
      surfaces remain aligned.
- [ ] AC8: Smoke or documentation coverage verifies canonical Cursor path and
      model-routing intent.

---

## Seed Data Reference

No seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| None | Repository workflow guidance inspection | Not applicable |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Search still finds `/item-orchestrator` in user-facing prose | A guidance file still advertises direct invocation | Reword it to point users to `/run-item` and describe `item-orchestrator` as internal or compatibility-only |
| Markdown lint reports broken links | Relative path depth from `docs/testing/workflow/` is wrong | Use `../../specs/developments/...` for spec and plan links |
| Model-routing assertion is unclear | `agent-model-config.md` does not connect pinned Cursor agents to `/run-item` handoff | Add a short note tying internal handoff to configured Cursor subagent model assignments |

---

## Known Limitations

- This smoke test verifies repository guidance and command surfaces. It does not
  launch a live Cursor session or prove Cursor's runtime dispatch behavior.
