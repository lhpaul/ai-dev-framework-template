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
| Sample item (single) | An open, non-epic, router-resolvable issue number `<N>` the operator picks (a doc-only item is safest); confirm with `./scripts/development-workflow/run-work-router.sh <N>` returning `MODE=redirect_item` |
| Explicit-list batch | Two real, open, non-epic issue numbers `<N1> <N2>`; confirm `./scripts/development-workflow/run-work-router.sh <N1> <N2>` returns `MODE=redirect_items`. The router accepts only positive-integer issue/PR numbers (optionally `#`-prefixed), existing workflow-prefixed branches (`feature/`, `fix/`, `refactor/`, `hotfix/`, `spec/`, `implementation-plan/`, `plan/`) and existing `docs/specs/developments/` folders, splits every argument on commas and removes duplicates. Tracker IDs and comma-containing targets yield `MODE=ambiguous` before any declaration gate, so they are covered as documented-unreachable cases in the fixtures only |
| Epic | A real open epic number `<E>` with native sub-issues; confirm `./scripts/development-workflow/run-work-router.sh --epic <E>` returns `MODE=redirect_epic` |

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
3. Run `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` (exists once the implementation PR is checked out; required).

**Expected result**: Test exits 0; manual spot-check matches.

### Step 3: Guardrails stop conditions

**Maps to**: AC10–AC11

1. Open `docs/workflow/development-workflow/guardrails-enforcement.md` section 4.
2. Confirm rows exist for `dispatch_profile_declaration_missing` and `dispatch_handoff_unavailable`.
3. Confirm `dispatch_profile_declaration_missing` documents `explicit_list_invocation_targets=<t1>,<t2>,...` for pre-branch explicit-list `/run-items` stops, with targets exactly as the router's normalized list holds them (issue or PR numbers with or without `#`, workflow-prefixed branch names, development-folder paths; the router does not accept tracker IDs such as `ENG-123`, and a comma cannot occur inside a target because the router splits on commas), `%`, whitespace and control characters percent-encoded, and duplicates already removed by the router.
4. Confirm the human unblocking action for `dispatch_profile_declaration_missing` requires a **fresh invocation** (the stopped run is not resumed or corrected in place) supplying a valid profile (the facts-assigned one after a mismatch), a named accountable role, and a posture valid for the checkpoint; that `dispatch_handoff_unavailable` gives the move-to-confirmed-environment or accept-read-only action plus the stage-role reachability exception; and that `missing_required_secret_or_permission` gives the grant-and-rerun action plus the structural-restriction path.
5. Confirm coarse-facts mismatch guidance rejects declarations that are either
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
2. Confirm Cursor Desktop vs Remote Control vs Cloud Agents profile **and model** assignments per layer: Desktop native handoff; Remote Control parent orchestrated at every layer; Cloud Agents inline fallback at every layer (initial handoff unconfirmed).
3. Confirm each row is labeled confirmed-by-observation or explicit assumption, for both the profile and the model assignment.

**Expected result**: Remote Control defaults to Parent orchestrated at every layer; Cloud Agents defaults to Inline fallback as an explicit assumption (read-only, `dispatch_handoff_unavailable` on a mutating run) until initial handoff is confirmed by observation; no environment defaults to parent orchestrated without confirmed initial handoff.

### Step 6: Read-only portfolio scan

**Maps to**: AC11, AC12, Use Case 5

1. Read `/run-work` command doc and protocol 90 scan-mode guidance, and run `./scripts/development-workflow/run-work-router.sh` with no target: expect `MODE=no_target_scan`.
2. Confirm scan declares **observing** posture and never escalates into execution.
3. Confirm the command surface states that acting on scan results requires a
   **new bounded run with its own declaration**.

**Expected result**: Acting on scan output requires a new bounded run with its own declaration.

### Step 7: Native handoff desktop path (manual, optional)

**Maps to**: AC6, Use Case 2

1. In Cursor Desktop, invoke `/run-item <N>` (the sample item from Test Data, or a trivial doc-only item on a throwaway branch). The bounded prelude prints read-only scope and policy first.
2. Confirm run output includes the dispatch profile declaration immediately before the first mutating action.

**Expected result**: Declaration visible; orchestration handed off when subagents work.

### Step 8: Parent orchestrated Remote Control `/run-item` (live, REQUIRED at sign-off)

**Maps to**: AC6, AC17, Use Case 3

This is the **required live step for `/run-item`** (Step 13 Part B and Step 14
Part B are the required live steps for `/run-items` and `/run-epic`): it
exercises the behavioral guarantee of AC17 (an operator in a constrained
environment runs a bounded command to a terminal condition without human
rescue) that the decision-matrix simulation in Steps 12-14 cannot exercise. It must run in a **real Cursor Remote
Control session**, not a simulated one, on the **implementation PR head**.

1. Record the head SHA under test (`git rev-parse HEAD`) and the environment
   (Cursor Remote Control session identifier or a note of how it was reached).
2. Start `/run-item <N>` on the sample doc-only item from Test Data.
3. Confirm the declaration block names Parent orchestrated, the accountable
   role and the `absorbed` posture before the first mutating action, that
   orchestration is absorbed by the current context, and that every stage of
   product work is delegated to its stage role with handoff metadata (not
   authored inline by the orchestrating context).
4. Let the run continue **without any human intervention mid-orchestration**
   (answering the bounded prelude's policy confirmation before the run starts is
   allowed; rescuing the run afterwards is not).
5. Record the terminal state reached: a real terminal condition (waiting on
   human review or merge, blocked dependency, or escalation) or a named stop
   from the decision matrix, plus the transcript excerpt or PR link.

**Expected result**: The run reaches a terminal condition or a named stop with no human rescue mid-orchestration; evidence names the head SHA and the Remote Control environment. **NOT RUN is not acceptable for this step at implementation sign-off**, and a run that needed a human rescue is a FAIL.

### Step 9: Inline fallback (manual, optional)

**Maps to**: Use Case 4

1. In an environment with no subagent handoff, or one whose initial handoff cannot be confirmed (the Cloud Agents default), invoke `/run-item <N>` (a mutating bounded command).
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

> **Steps 12-14 rule**: two independent kinds of evidence are **both mandatory**
> for the three bounded commands at implementation sign-off.
>
> - **Simulation** (`simulate_bounded_paths`, Steps 12, 13 Part A, 14 Part A):
>   validates the **decision matrix** (every row, both mismatch directions,
>   recovery, unconfirmed handoff). It does not execute the command flows.
> - **Live Cursor Remote Control execution** (Step 8 for `/run-item`, Step 13
>   Part B for `/run-items`, Step 14 Part B for `/run-epic`): validates the
>   **behavioral guarantee** (AC17) that an operator in a constrained
>   environment runs each bounded command to a terminal condition without human
>   rescue. It cannot exercise the recovery, mismatch, or unconfirmed-handoff
>   rows.
>
> Neither substitutes for the other, and NOT RUN blocks sign-off for either.

### Step 12: `/run-item` terminal behavior at current head

**Maps to**: AC6, AC9, AC10, AC17, AC20

1. Record the current head SHA (`git rev-parse HEAD`).
2. **Mandatory**: run
   `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`
   and confirm its `simulate_bounded_paths` branch passes **every** `/run-item`
   scenario marked Y in the plan's scenario table (S1, S3, S5, S7-S10, S10b,
   S11-S19), including unconfirmed initial/onward handoff, profile/fact
   mismatch in both directions, mid-run recovery, and reachable-stage
   credential denial.
3. The live `/run-item` evidence is Step 8 (required, real Remote Control).
   Step 12 covers the simulation only; it never replaces Step 8.

**Expected result**: The simulation passes every `/run-item` scenario; evidence names the head SHA.

### Step 13: `/run-items` explicit-list terminal behavior at current head

**Maps to**: AC9, AC10, AC14, AC17

1. Record the current head SHA.
2. Pick two real, open, non-epic issue numbers `<N1> <N2>` (Test Data; doc-only
   items are safest) and run
   `./scripts/development-workflow/run-work-router.sh <N1> <N2>`; proceed only
   on `MODE=redirect_items`. (Any other MODE, including `ambiguous`, stops
   before the declaration gate; pick different targets.)

**Part A (mandatory, simulation)**: run the `simulate_bounded_paths` branch for
**every** `/run-items` scenario marked Y in the plan's scenario table (same set
as `/run-item`, with pre-branch stops asserting the single invocation-level
affected-item string over router-accepted target forms: numbers with and
without `#`, a workflow-prefixed branch, a development-folder path; tracker IDs
and comma-containing targets are documented-unreachable cases, not accepted
forms). Confirm exactly **one** `dispatch_profile_declaration_missing` stop is
reported for the whole invocation with affected item
`explicit_list_invocation_targets=<N1>,<N2>` (targets as they appear in the
router's normalized list: comma-split, trimmed, deduplicated, in order, no `#`
rewriting), before any branch or artifact is created.

**Part B (mandatory, live Cursor Remote Control)**: in a **real Remote Control
session** on the implementation PR head, run `/run-items <N1> <N2>` with a valid
Parent orchestrated declaration (the portfolio layer is absorbed and Protocol 90
Step 4's one-at-a-time fallback applies), and do not intervene mid-run
(answering the bounded prelude's policy confirmation up front is allowed).
Record the environment, the declaration block, and the terminal state. The
terminal condition is, precisely: **either** the completed one-at-a-time run,
meaning every listed item has reached a real terminal condition (waiting on
human review or merge, blocked dependency, or escalation) in sequence, **or** a
named stop from the decision matrix reported with the affected work item. A run
that needed a human rescue mid-orchestration is a FAIL.

**Part C (optional)**: run `/run-items <N1> <N2>` in a throwaway clone with the
declaration deliberately withheld and confirm the single invocation-level
`dispatch_profile_declaration_missing` stop.

**Expected result**: The simulation passes every scenario for this path (Part
A), and the live Remote Control run reaches the completed one-at-a-time run or a
named stop with no human rescue (Part B); evidence names the head SHA and the
Remote Control environment. NOT RUN is not acceptable for Part A or Part B.

### Step 14: `/run-epic` terminal behavior at current head

**Maps to**: AC9, AC10, AC17

1. Record the current head SHA.
2. With a real open epic `<E>` (Test Data; one whose sub-issues are doc-only is
   safest) confirm `./scripts/development-workflow/run-work-router.sh --epic <E>`
   returns `MODE=redirect_epic`. (`--items` is internal-only and is not a
   user-facing option per Protocol 95.)

**Part A (mandatory, simulation)**: run the `simulate_bounded_paths` branch for
**every** `/run-epic` scenario marked Y in the plan's scenario table (S1, S3, S5,
S7-S10, S10b, S11-S19), confirming the epic layer is declared absorbed, stage
work is delegated with handoff metadata, and an invalid or missing declaration
stops with `dispatch_profile_declaration_missing` (affected work item per
`guardrails-enforcement.md` section 4).

**Part B (mandatory, live Cursor Remote Control)**: in a **real Remote Control
session** on the implementation PR head, run `/run-epic --epic <E>` under a
valid Parent orchestrated declaration and do not intervene mid-run. Record the
environment, the declaration block, and the terminal state. The terminal
condition is, precisely: the epic resolver's `continuation` outcome, either
`complete`, or `needs_resolution` with its named `stopCondition` and
`humanAction`, **or** a named stop from the decision matrix reported with the
affected work item; a run that stalled or needed a human rescue
mid-orchestration is a FAIL.

**Expected result**: The simulation passes every scenario for this path (Part
A), and the live Remote Control run reaches a `continuation` terminal outcome or
a named stop with no human rescue (Part B); evidence names the head SHA and the
Remote Control environment. NOT RUN is not acceptable for Part A or Part B.

---

## Pass criteria

- Steps 1-6 and 10-11 must **PASS** (documentation and automated assertions; no
  live Cursor environment required).
- **Live Cursor Remote Control evidence is required for all three bounded
  commands** at implementation sign-off, each on the implementation PR head in a
  **real** Remote Control session with no human rescue mid-orchestration:
  Step 8 (`/run-item`), Step 13 Part B (`/run-items`, terminal condition = the
  completed one-at-a-time run or a named stop), and Step 14 Part B
  (`/run-epic --epic <E>`, terminal condition = a `continuation` outcome of
  `complete`, or `needs_resolution` with its named `stopCondition` and
  `humanAction`, or a named stop). **NOT RUN is not acceptable** for any of the
  three: if a real Remote Control session is unavailable, sign-off is blocked
  rather than waived. A live run that needed a human rescue is a FAIL.
- **The simulation is also mandatory**: Step 12, Step 13 Part A and Step 14 Part
  A (`simulate_bounded_paths`, every scenario the plan's table marks Y for the
  path) validate the **decision matrix** (every row, both mismatch directions,
  recovery, unconfirmed handoff). They do not execute the command flows, so a
  passing simulation alone leaves the AC17 behavioral guarantee unproved, and
  live runs alone cannot exercise the recovery, mismatch, and
  unconfirmed-handoff rows. Neither substitutes for the other.
- Manual live Steps 7 (Desktop) and 9 (inline fallback / Cloud Agents) and
  Step 13 Part C are optional and may be documented **NOT RUN** with a reason,
  provided the required live evidence above and all simulation parts passed at
  the same head SHA.
- Evidence recorded against an older head than the one being merged is stale and
  must be re-run.
