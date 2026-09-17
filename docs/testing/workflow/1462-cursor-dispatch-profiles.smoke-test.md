# Smoke Test Runbook: Cursor Dispatch Profiles

**Feature**: Cursor dispatch profiles (#1462)
**Spec**: [Cursor Dispatch Profiles](../../specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20260911230512_1462-cursor-dispatch-profiles/2_1462-cursor-dispatch-profiles_implementation-plan.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] Implementation PR for #1462 is checked out locally
- [ ] `origin/develop` is fetched
- [ ] You can open the template repository in Cursor (Desktop and, if available, Remote Control)

---

## Test Data

| Item | Value |
| --- | --- |
| Canonical doc | `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` |
| Sample item (single) | Any merged-spec workflow item, e.g. `#1462` plan stage on `develop` |
| Explicit-list batch | Two or more issue numbers in `/run-items` explicit_list mode (documentation check only for pre-branch stop) |

---

## Smoke Test Steps

### Step 1: Canonical doc completeness

**Maps to**: AC1–AC8, AC17

1. Open the canonical integration doc.
2. Confirm three profile code values and display labels match the spec enum table.
3. Confirm portfolio / epic / item layers each have perform / hand off / prohibit entries with links to role contracts (not restatements).
4. Confirm at least one worked example per profile exists.

**Expected result**: Doc stands alone for an operator new to Remote Control.

### Step 2: Mirror surface link parity

**Maps to**: AC18

1. Open each bounded command adapter (`.cursor/commands/run-item.md`, `run-items.md`, `run-epic.md`, `run-work.md`).
2. Confirm each references `integrations/cursor-dispatch-profiles.md` and names the declaration requirement.
3. Run `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` if present.

**Expected result**: Test exits 0; manual spot-check matches.

### Step 3: Guardrails stop conditions

**Maps to**: AC10–AC12

1. Open `docs/workflow/development-workflow/guardrails-enforcement.md` section 4.
2. Confirm rows exist for `dispatch_profile_declaration_missing` and `dispatch_handoff_unavailable`.
3. Confirm `dispatch_profile_declaration_missing` documents `explicit_list_invocation_targets=#N1,#N2,...` for pre-branch explicit-list `/run-items` stops.

**Expected result**: Stop names match spec matrix exactly.

### Step 4: Orchestration role no-handoff behavior

**Maps to**: AC13

1. Open `.cursor/agents/orchestrator.md` and `.cursor/agents/item-orchestrator.md`.
2. Confirm both state: when onward handoff is unavailable, return control to the invoking context and perform no inline product work.

**Expected result**: Wording aligns with canonical doc; no contradiction with parent-orchestrated absorb path.

### Step 5: Agent model configuration

**Maps to**: AC15

1. Open `docs/workflow/development-workflow/agent-model-config.md`.
2. Confirm Cursor Desktop vs Remote Control vs Cloud Agents profile assignments per layer.
3. Confirm each row is labeled confirmed-by-observation or explicit assumption.

**Expected result**: Remote Control defaults to Parent orchestrated; Cloud Agents conservative assumption documented.

### Step 6: Read-only portfolio scan

**Maps to**: AC11, Use Case 5

1. Read `/run-work` command doc and protocol 90 scan-mode guidance.
2. Confirm scan declares **observing** posture and never escalates into execution.

**Expected result**: Acting on scan output requires a new bounded run with its own declaration.

### Step 7: Native handoff desktop path (manual)

**Maps to**: AC6, Use Case 2

1. In Cursor Desktop, invoke `/run-item` on a read-only target (e.g. portfolio scan is `/run-work`) or a trivial doc-only item in a test branch.
2. Confirm run output includes dispatch profile declaration before mutation.

**Expected result**: Declaration visible; orchestration handed off when subagents work.

### Step 8: Parent orchestrated Remote Control path (manual)

**Maps to**: AC6, Use Case 3

1. In Cursor Remote Control (or simulated constrained environment), start `/run-item` on one plan/spec item.
2. Confirm profile is Parent orchestrated, orchestration absorbed, stage work delegated (not authored inline by orchestrating context).

**Expected result**: Run reaches terminal condition or a named stop without human rescue mid-orchestration.

### Step 9: Inline fallback (manual)

**Maps to**: Use Case 4

1. In an environment with no subagent handoff, invoke a mutating bounded command.
2. Confirm the run declares **Inline fallback** (`cursor-inline-fallback`) with a
   valid accountable role and **observing** posture at the read-only checkpoint,
   then reaches the first mutating action.
3. Confirm the run stops with named condition `dispatch_handoff_unavailable`
   (not `dispatch_profile_declaration_missing`).

**Expected result**: No artifact mutation; stop reason matches a valid inline-fallback declaration, not a missing declaration.

---

## Pass criteria

All automated steps pass; manual steps 7–9 are **PASS** or documented **NOT RUN**
with reason (e.g. Remote Control unavailable in CI).
