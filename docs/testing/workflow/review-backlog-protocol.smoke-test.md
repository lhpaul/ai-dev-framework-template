# Smoke Test Runbook: Backlog review protocol (`/review-backlog`)

**Feature**: Tracker-agnostic backlog review (Protocol 09)
**Spec**: [1_2155-review-backlog-protocol_specs.md](../../specs/developments/20261112062645_2155-review-backlog-protocol/1_2155-review-backlog-protocol_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] A checkout of this repository on the implementation branch, with `gh`
  authenticated for read access to the repository and its project board.
- [ ] A runner that exposes workflow commands (Claude Code, Cursor, Codex or
  DSH).
- [ ] A disposable scratch copy of the checkout for configuration variants
  (steps 3 and 4). Never edit the real `.ai-dev-workflow.yaml` or any
  `.ai-dev-workflow.local.*` file.
- [ ] Answer every gate with a rejection (`no` to every finding) unless a
  step says otherwise, so no real tracker item changes.

---

## Test Data

| Item | Value |
| --- | --- |
| Tracker configurations | this repository's own (project board), a scratch copy set to repository issues without a project, a scratch copy set to no tracker |
| Simulated capability gaps | stated to the runner as "treat capability X as not exposed" in the scratch copy run |
| Evidence to keep | the run header, each gate's output, and the final answer per step |

---

## Smoke Test Steps

### Step 1: Contract suite

**Maps to**: AC1, AC2, AC6–AC9, AC13–AC17

1. Run `bash scripts/development-workflow/tests/test-review-backlog-protocol.sh`.

**Expected result**: every case passes and each planted-violation proof prints
`FAIL at` followed by `PASS after repair`.

### Step 2: Project-board configuration

**Maps to**: AC4, AC6, AC7, AC15, AC16

1. Run `/review-backlog` from the runner on this repository unchanged.
2. Read the header and Gate 1, then answer `no` to everything.

**Expected result**:

- The header names the resolved scope (the configured project), lists each
  detected capability, the coverage value, and the budget.
- The epic sweep lists children through the detected hierarchy, or reports
  `no aplica` naming the hierarchy capability.
- Gate 1 shows `LISTO PARA CONFIRMAR`, `SOLO REPORTE` and
  `NECESITA TU CRITERIO`; every question carries `Recomiendo`, `Por qué`,
  `Si no` and `Confianza`.
- The landed-work sweep lists each candidate with the artifact found or "no
  claim".
- With nothing confirmed, Gate 2 shows the order the dispatcher would produce
  using the board's own priority values and names which of them the
  dispatcher recognizes. No item changed (spot-check one item's status).

### Step 3: Repository-issues configuration (no project)

**Maps to**: AC4, AC13

1. In the scratch copy, set the tracker to repository issues without a project
   number, and run `/review-backlog`.

**Expected result**: the header states the scope as the configured milestone
or, without one, the whole repository; the epic sweep uses the detected
hierarchy or reports `no aplica` for it; the priority-dependent checks report
`no aplica` naming the priority capability when no priority field is
detected.

### Step 4: No tracker

**Maps to**: AC3

1. In the scratch copy, set the tracker to none and run `/review-backlog`.

**Expected result**: the header declares repository-only mode and the coverage
field reads `n/a (sin tracker)`; every tracker-dependent check reports
`no aplica` naming its capability; Gate 2 reports `no aplica`; Gate 3 closes
Gate 1 alone; nothing is written and the run does not fail.

### Step 5: Missing capabilities

**Maps to**: AC5

1. In the scratch copy with the project configuration, tell the runner to treat
   the hierarchy, the unsettable priority, and the labels capabilities as not
   exposed (one run each, or one run with all three).

**Expected result**: each dependent check reports `no aplica` naming that
capability; every other check still runs; the run does not fail.

### Step 6: Confirmation boundaries

**Maps to**: AC7

1. In the step 2 run (or a new one), answer a range that includes a cancel or
   duplicate-merge finding, for example `C1-C3 sí`.
2. Answer `recomendación` to a question whose recommendation is a body edit.

**Expected result**: the run refuses to treat the range as authority for the
cancel or merge and asks for the explicit per-item or per-group form; the body
edit stays proposed text under `PENDIENTE DE TI`. Then answer `no` to finish
without writes.

### Step 7: Scope stop

**Maps to**: AC13

1. In the scratch copy, configure a project identifier that does not exist and
   run `/review-backlog`.

**Expected result**: the run stops before reading any item and asks once,
naming the identifier it could not resolve.

### Step 8: Early end delivers pending items

**Maps to**: AC17, BR15

1. In the step 2 run, before Gate 1 closes, answer that a confirmed
   cancellation is outstanding and decline to rank as-is.

**Expected result**: the run ends at the Gate 1 close and the close report
prints `PENDIENTE DE TI` and any precedent lines; Gate 2 is not opened.

### Step 9: Distribution and guides

**Maps to**: AC8–AC12

1. Confirm `/review-backlog` is listed by the runner and resolves to the
   protocol.
2. Run `python3 scripts/development-workflow/check-sync-manifest-coverage.py`.
3. Run `bash scripts/development-workflow/changelog-fragments.sh validate`.

**Expected result**: the command resolves; the coverage check reports
`RESULT=clean`; the changelog fragment validates; the workflow guide states
that the review complements `/run-work`.
