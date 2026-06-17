# Smoke Test Runbook: Align Cursor Workflow Surfaces for Client Rollout

**Feature**: Align Cursor workflow surfaces for client rollout (#989)
**Spec**: [`../../specs/developments/20260617122852_align-cursor-workflow-surfaces/1_align-cursor-workflow-surfaces_specs.md`](../../specs/developments/20260617122852_align-cursor-workflow-surfaces/1_align-cursor-workflow-surfaces_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

This feature is a documentation and thin-wrapper change with no running
application. The smoke test is performed by inspecting the repository on the
implementation branch.

- [ ] You have the implementation branch checked out (the `feature/*` branch for
  #989, branched from and targeting `develop-cursor-bugbot-integration`).
- [ ] A terminal at the repository root is available.
- [ ] `markdownlint-cli2` is installed (`node_modules/.bin/markdownlint-cli2`).

---

## Test Data

| Item | Value |
| --- | --- |
| New Cursor command (smoke) | `.cursor/commands/smoke-tester.md` |
| New Cursor command (graduation) | `.cursor/commands/graduate-development.md` |
| Smoke canonical protocol | `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` |
| Graduation canonical protocol | `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` |
| Guidance files | `AGENTS.md` (and its symlink `CLAUDE.md`), `README.md`, `docs/testing/README.md` |

---

## Smoke Test Steps

### Step 0: Confirm starting point

- At the repository root, confirm you are on the implementation branch:
  `git branch --show-current`
- Verify: the branch is the `feature/*` branch for #989.

### Step 1: Advertised Cursor entrypoints all resolve

**Maps to**: Acceptance Criterion AC-1

1. Read the **Workflow Commands** table in `AGENTS.md`.
2. For each stage whose Cursor cell names a `/name` entrypoint, confirm a matching
   Cursor surface exists: either `.cursor/commands/<name>.md` or
   `.cursor/agents/<name>.md`.
3. Pay specific attention to the **Smoke Test** and **Graduate Integration Branch**
   rows.

**Expected result**: Every advertised Cursor `/name` resolves to a real Cursor
file. No advertised Cursor stage resolves only to a Claude- or Codex-only name.

### Step 2: Previously missing entrypoints now exist and tables agree both ways

**Maps to**: Acceptance Criterion AC-2

1. Confirm `.cursor/commands/smoke-tester.md` exists.
2. Confirm `.cursor/commands/graduate-development.md` exists.
3. Confirm the `AGENTS.md` **Graduate Integration Branch** row Cursor cell now reads
   `/graduate-development <slug>` (no longer `—`).
4. Confirm no Cursor command file in `.cursor/commands/` for a stage in scope is
   absent from the guidance tables (no shipped-but-undocumented entrypoint).

**Expected result**: The two previously advertised-but-missing/absent entrypoints
are present, and the guidance tables and shipped Cursor surfaces agree in both
directions for the in-scope stages.

### Step 3: New/changed Cursor files are thin and canonically anchored

**Maps to**: Acceptance Criterion AC-3

1. Open `.cursor/commands/smoke-tester.md` and `.cursor/commands/graduate-development.md`.
2. Confirm each references its canonical protocol path and that the path resolves
   (`ls <referenced path>`).
3. Confirm each contains only a short orientation summary — no restated protocol
   steps or duplicated behavior.

**Expected result**: Both new files are thin wrappers that point at an existing
canonical protocol and add no restated behavior.

### Step 4: README and AGENTS Cursor guidance match shipped surfaces

**Maps to**: Acceptance Criterion AC-4

1. Read the **Cursor** section of `README.md` and the Cursor-facing guidance in
   `AGENTS.md`.
2. Confirm the descriptions of rules (`.cursor/rules/` `*.mdc`), subagents
   (`.cursor/agents/`, invoked as `/agent-name`), and commands (`.cursor/commands/`,
   invoked as `/command-name`) match what the repository actually ships.
3. Confirm `docs/testing/README.md` line 7 references `/smoke-tester` and no longer
   references a "run-smoke-test command":
   `grep -n "smoke" docs/testing/README.md`.

**Expected result**: Cursor guidance reflects current Cursor conventions and the
actual shipped surfaces; the testing README smoke command name is corrected.

### Step 5: Skills-mirror decision is explicitly recorded

**Maps to**: Acceptance Criterion AC-5

1. Confirm the spec records the decision (it does — Business Rules and AC-5).
2. Confirm the project guidance (`AGENTS.md` Cursor prose and/or `README.md` Cursor
   section) states explicitly that no Cursor-native skills mirror is shipped, with
   the rationale.

**Expected result**: A reader finds the recorded decision and rationale in prose,
without inferring it from the presence or absence of a `.cursor/skills/` directory.

### Step 6: Project Type is Feature

**Maps to**: Acceptance Criterion AC-6

1. In the issue tracker, open issue #989 and read its Project **Type** field.

**Expected result**: The Type for #989 is **Feature**.

### Last Step: Validate & lint

- Run the Markdown lint gate on the changed files:
  `node_modules/.bin/markdownlint-cli2 ".cursor/commands/smoke-tester.md" ".cursor/commands/graduate-development.md" "AGENTS.md" "README.md" "docs/testing/README.md"`
- Verify all assertions in the checklist below are met.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Every advertised Cursor entrypoint resolves to a real Cursor surface by
  its advertised name.
- [ ] AC-2: `.cursor/commands/smoke-tester.md` and
  `.cursor/commands/graduate-development.md` exist; guidance tables and shipped
  surfaces agree in both directions for in-scope stages.
- [ ] AC-3: Each new/changed Cursor file references an existing canonical protocol
  and restates no protocol behavior beyond a short orientation summary.
- [ ] AC-4: README and AGENTS Cursor guidance match the shipped surfaces; the
  testing README smoke command name is corrected to `/smoke-tester`.
- [ ] AC-5: The Cursor skills-mirror decision and rationale are explicitly recorded
  in the project guidance.
- [ ] AC-6: Issue #989 Project Type is Feature.

---

## Seed Data Reference

No seed data is required — this is a documentation and thin-wrapper change with no
data model.

| Entity | Scenario | How to load |
| --- | --- | --- |
| None | No data required | — |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `markdownlint-cli2` not found | Running outside repo root or deps not installed | Run from the repo root; ensure `node_modules/.bin/markdownlint-cli2` exists |
| Broken relative link reported by lint | Wrong `../` depth in a referenced path | Recount path segments from the file's location and correct |
| AGENTS.md edit not reflected in CLAUDE.md | Editing CLAUDE.md separately | `CLAUDE.md` is a symlink to `AGENTS.md`; edit only `AGENTS.md` (`ls -l CLAUDE.md` to confirm) |

---

## Known Limitations

- This smoke test is a repository-inspection checklist; there is no running
  application or browser flow to exercise.
- AC-6 (Project Type) is verified in the issue tracker UI, not in repository files.
