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

1. Open each bounded command adapter (`.cursor/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`, plus Claude and `.agents/skills` parity paths).
2. Confirm each references `integrations/cursor-dispatch-profiles.md` and names the declaration requirement.
3. Run `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` if present.

**Expected result**: Test exits 0; manual spot-check matches.

### Step 3: Guardrails stop conditions

**Maps to**: AC10–AC11

1. Open `docs/workflow/development-workflow/guardrails-enforcement.md` section 4.
2. Confirm rows exist for `dispatch_profile_declaration_missing` and `dispatch_handoff_unavailable`.
3. Confirm `dispatch_profile_declaration_missing` documents `explicit_list_invocation_targets=#N1,#N2,...` for pre-branch explicit-list `/run-items` stops.
4. Confirm coarse-facts mismatch guidance rejects declarations that are either
   more permissive or less permissive than the assigned decision-gate outcome.

**Expected result**: Stop names match spec matrix exactly; mismatch check is bidirectional.

### Step 4: Orchestration role no-handoff behavior

**Maps to**: AC13

1. Open `.cursor/agents/orchestrator.md` and `.cursor/agents/item-orchestrator.md`.
2. Confirm both state: when onward handoff is unavailable, return control to the invoking context and perform no inline product work.

**Expected result**: Wording aligns with canonical doc; no contradiction with parent-orchestrated absorb path.

### Step 5: Agent model configuration

**Maps to**: AC15

1. Open `docs/workflow/development-workflow/agent-model-config.md`.
2. Confirm Cursor Desktop vs Remote Control vs Cloud Agents profile **and model** assignments per layer.
3. Confirm each row is labeled confirmed-by-observation or explicit assumption, for both the profile and the model assignment.

**Expected result**: Remote Control defaults to Parent orchestrated; Cloud Agents conservative assumption documented.

### Step 6: Read-only portfolio scan

**Maps to**: AC11, AC12, Use Case 5

1. Read `/run-work` command doc and protocol 90 scan-mode guidance.
2. Confirm scan declares **observing** posture and never escalates into execution.
3. Confirm the command surface states that acting on scan results requires a
   **new bounded run with its own declaration**.

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

### Step 10: Parent-orchestrated inline prohibition + #1746 honesty

**Maps to**: AC19

1. Open the canonical doc, `.cursor/agents/item-orchestrator.md`, and any
   protocol/role surface that mentions inline fallback or stage permission denial.
2. Confirm no document relaxes the parent-orchestrated prohibition on inline
   product work by the absorbing orchestration context.
3. Confirm #1746 remains an explicit Out-of-Scope / unresolved-gap callout (not
   solved by this feature).
4. Confirm `SUBAGENT_PERMISSION_DENIAL` is described as only observably similar
   to stage-role harness denial (Work Item Runner boundary), not as a recovery
   path for stage roles.

**Expected result**: AC19 content present; removing any of the four checks would fail this step.

### Step 11: Accountability postures

**Maps to**: AC20

1. Open the canonical doc accountability-posture section (and declaration
   contract if postures are defined there).
2. Confirm three named postures exist (absorbed / handed-off / observing — exact
   labels per spec).
3. Confirm `observing` is valid only at read-only checkpoints.
4. Confirm posture mismatch (e.g. `observing` at a mutating action, or
   absorbed/handoff at a read-only checkpoint) is treated the same as a missing
   declaration (`dispatch_profile_declaration_missing`).

**Expected result**: AC20 content present; posture mismatch maps to the missing-declaration stop.

---

### Step 12: `/run-item` terminal behavior at current head

**Maps to**: AC6, AC9, AC10, AC17, AC20

1. Record the current head SHA (`git rev-parse HEAD`).
2. Either run `/run-item` in a constrained (or simulated no-handoff) environment
   on a doc-only target, or run
   `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`
   and confirm its `simulate_bounded_paths` branch passes the `/run-item`
   scenarios.
3. Record the declaration block emitted and the terminal outcome (proceeds,
   `dispatch_handoff_unavailable`, or `dispatch_profile_declaration_missing`).

**Expected result**: Terminal outcome matches the canonical decision-gate row for the declared profile; evidence names the head SHA.

### Step 13: `/run-items` explicit-list terminal behavior at current head

**Maps to**: AC9, AC10, AC14, AC17

1. Record the current head SHA.
2. Run `/run-items #A #B` with no declaration in a throwaway clone, or run the
   `simulate_bounded_paths` branch for the `/run-items` scenarios.
3. Confirm exactly **one** `dispatch_profile_declaration_missing` stop is
   reported for the whole invocation with affected item
   `explicit_list_invocation_targets=#A,#B`, before any branch or artifact is
   created.

**Expected result**: Single invocation-level stop with the ordered target string; no per-target stops; no mutation.

### Step 14: `/run-epic` terminal behavior at current head

**Maps to**: AC9, AC10, AC17

1. Record the current head SHA.
2. Run `/run-epic --items #A,#B` under a Parent orchestrated declaration (or the
   `simulate_bounded_paths` branch for `/run-epic`).
3. Confirm the epic layer is declared absorbed, stage work is delegated with
   handoff metadata, and an invalid or missing declaration stops with
   `dispatch_profile_declaration_missing`.

**Expected result**: Terminal condition or named stop matches the canonical doc; evidence names the head SHA.

---

## Pass criteria

- Steps 1-6 and 10-11 must **PASS** (documentation and automated assertions; no
  live Cursor environment required).
- Steps 12, 13, and 14 must each **PASS** with recorded evidence naming the head
  SHA under test. For each bounded path (`/run-item`, `/run-items`, `/run-epic`)
  the evidence is either a live constrained-environment run or the executable
  `simulate_bounded_paths` result for that path. **NOT RUN is not acceptable**
  for these three steps: if live Remote Control is unavailable, the executable
  simulation is mandatory, not optional.
- Manual live steps 7-9 (Desktop, Remote Control, inline fallback) may be
  documented **NOT RUN** with a reason, provided Steps 12-14 passed via
  simulation at the same head SHA.
- Evidence recorded against an older head than the one being merged is stale and
  must be re-run.
