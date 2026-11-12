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
  (steps 3, 4, 5, 7, 8 and 9). Never edit the real `.ai-dev-workflow.yaml` or any
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
or, without one, the whole repository, and lists each detected and missing
capability (record them); the epic sweep uses the detected hierarchy or
reports `no aplica` for it; when a priority field is detected, Gate 2 shows the
order with the tracker's own priority values and names which of them the
dispatcher recognizes, as in step 2; otherwise the priority-dependent checks
and the order reconstruction report `no aplica` naming the priority
capability.

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

1. In the step 2 run (or a new one), answer a range or class whose members are
   only cancel or duplicate-merge findings, for example `C1-C3 sí`. Never
   include a `LISTO PARA CONFIRMAR` status, classification, priority or label
   finding in that range, because a range authorizes those writes.
2. Answer `recomendación` to a question whose recommendation is a body edit.

When Gate 1 proposes no cancel, duplicate-merge or body-edit finding, record
the sub-step as not exercisable on this backlog instead of passing it.

**Expected result**: the run refuses to treat the range as authority for the
cancel or merge and asks for the explicit per-item or per-group form; the body
edit stays proposed text under `PENDIENTE DE TI`. Then answer `no` to finish
without writes.

### Step 7: Scope stop

**Maps to**: AC13

In the scratch copy, run `/review-backlog` once per case:

1. A project identifier that does not exist.
2. The project configuration with no project identifier configured.
3. Two configured scope identifiers naming different projects (or different
   milestones), in whichever configuration the protocol's scope section names
   as configured scope.

**Expected result**: each run stops before reading any item and asks once:
naming the identifier it could not resolve (case 1), asking which project to
use or accepting an explicit widen-to-all-projects instruction (case 2), and
asking which of the two named identifiers governs (case 3). Scope is never
widened silently.

### Step 8: Early end delivers pending items

**Maps to**: AC17, BR15

1. In the scratch copy with the project configuration, tell the runner to treat
   the item-closure capability as not exposed, and run `/review-backlog`.
2. Explicitly confirm one cancel finding by its identifier, answer `no` to
   every other finding, and decline to rank as-is.

**Expected result**: the confirmed cancellation is not performed and is listed
under `PENDIENTE DE TI` naming the item-closure capability; the run ends at
the Gate 1 close, whose report prints `PENDIENTE DE TI` and any precedent
lines; Gate 2 is not opened. When Gate 1 proposes no cancel finding, record
the step as not exercisable on this backlog.

### Step 9: Budget and write outcomes (simulated)

**Maps to**: AC17

In the scratch copy with the project configuration, run `/review-backlog` once
per case below, telling the runner which tracker response to simulate. For the
write cases, confirm exactly one `LISTO PARA CONFIRMAR` finding and tell the
runner to simulate the write and its readback without sending them to the
tracker; answer `no` to everything else.

| Case | Simulated response | Expected result |
| --- | --- | --- |
| a | measured budget below the cost of listing the scope | coverage `deferred`; budget and reset reported; nothing proposed; run ends before Gate 1 |
| b | listing cut short after part of the scope | coverage `partial`; ledger of what was read with the unlisted remainder declared unread; no queue; run ends at the Gate 1 close |
| c | no readable budget surface | coverage `full (sin presupuesto)`; admission reported as unmetered; not `no aplica` |
| d | measured budget below the projected cost of the confirmed set | nothing written; projected cost and reset reported; Gate 2 not opened |
| e | tracker rejects the write | item `not applied` with the reason; recovery step reported; Gate 2 not opened |
| f | readback returns a different value | item `drift` with the observed value; recovery step reported; Gate 2 not opened |
| g | readback fails | treated as a rejection: item `not applied`; Gate 2 not opened |
| h | board re-read after the Gate 2 writes is cut short (nothing confirmed in Gate 1 or Gate 2) | Gate 3 opens with the final backlog state marked `partial` and the omitted items named |

### Step 10: Distribution and guides

**Maps to**: AC8–AC12

1. Confirm `/review-backlog` is listed by the runner and resolves to the
   protocol.
2. Run `python3 scripts/development-workflow/check-sync-manifest-coverage.py`.
3. Run `bash scripts/development-workflow/changelog-fragments.sh validate`.

**Expected result**: the command resolves; the coverage check reports
`RESULT=clean`; the changelog fragment validates; the workflow guide states
that the review complements `/run-work`.
