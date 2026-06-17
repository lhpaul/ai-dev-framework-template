# Smoke Test Runbook: Make /run-work the Adaptive Workflow Entrypoint

**Feature**: Make `/run-work` the adaptive workflow entrypoint
**Spec**: [../../specs/developments/20260617083256_978-run-work-adaptive-entrypoint/1_978-run-work-adaptive-entrypoint_specs.md](../../specs/developments/20260617083256_978-run-work-adaptive-entrypoint/1_978-run-work-adaptive-entrypoint_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out with the new files present:
      `scripts/development-workflow/run-work-router.sh`,
      `scripts/development-workflow/tests/test-run-work-router.sh`, and
      `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`.
- [ ] #979 (`979-guardrails-config-model`) is merged into `develop-guardrails` so
      the `guardrails` section and its documented defaults exist.
- [ ] `gh` CLI is authenticated (for the live routing scenarios that resolve real
      targets) — or use the dry-run / mock mode the router exposes for tests.
- [ ] You are running from the repository root.

---

## Test Data

| Item | Value |
| --- | --- |
| Non-epic issue number | `978` (or any open issue without child items) |
| Epic-like issue number | `977` (the guardrails epic, has child items) |
| Two explicit targets | `978 979` |
| Routing helper | `scripts/development-workflow/run-work-router.sh` |
| Routing protocol doc | `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md` |

---

## Smoke Test Steps

### Step 0: Confirm artifacts exist

- Run `ls scripts/development-workflow/run-work-router.sh scripts/development-workflow/tests/test-run-work-router.sh docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
- Verify: all three paths exist.

### Step 1: No-target routing

**Maps to**: AC1, AC10

1. Run the router with no target argument (e.g.
   `./scripts/development-workflow/run-work-router.sh`).
2. Inspect the routing-decision record output.

**Expected result**: The record reports `MODE=no_target_scan` (display label
"No-target scan"), names the items eligible to advance and the items held back
with reasons, and reports which `guardrails` configuration values (autonomy mode
and backlog-start policy) bounded the plan. No artifact is mutated.

### Step 2: Single-target routing (non-epic)

**Maps to**: AC2

1. Run the router with one non-epic target (e.g. `... 978`).

**Expected result**: `MODE=single_item`, the resolved item identity is shown, and
the record indicates the request advances only that one item with no unrelated
mutation.

### Step 3: Explicit multi-target routing

**Maps to**: AC3

1. Run the router with two or more targets (e.g. `... 978 979` and again with
   `... 978,979`).

**Expected result**: `MODE=explicit_list` for both space- and comma-separated
forms; the record shows the exact bounded scope and states that out-of-scope items
encountered are logged and not mutated.

### Step 4: Epic-target routing

**Maps to**: AC4

1. Run the router with an epic target (e.g. `... 977` or the epic flag form).

**Expected result**: `MODE=epic`; the record states that read-only scope
resolution runs before any item is created, reviewed, merged, or cleaned up.

### Step 5: Single epic-like target routes to epic, not single

**Maps to**: AC5

1. Run the router with a single target that is itself epic-like (e.g. `... 977`).

**Expected result**: `MODE=epic` (not `single_item`) — the `single_item` → `epic`
transition is applied.

### Step 6: Aliases still work

**Maps to**: AC6

1. Confirm `.claude/commands/run-item-work.md` still points to Protocol 91 and
   `.claude/commands/run-epic.md` still points to Protocol 95.
2. (If running live) invoke `/run-item-work <target>` and `/run-epic --epic <n>`
   and confirm behavior matches what `/run-work` routes to for the equivalent
   target.

**Expected result**: Both lower-level commands behave exactly as before; nothing
that previously worked breaks.

### Step 7: User-facing language is consistent

**Maps to**: AC7

1. Read the Workflow Commands sections of `README.md`, `AGENTS.md`, `GEMINI.md`,
   and `docs/workflow/development-workflow/README.md`, plus the three command
   wrappers and the three Codex alias skills.

**Expected result**: `/run-work` is presented as the primary adaptive entrypoint;
`/run-item-work` and `/run-epic` are presented as compatibility/advanced aliases,
with consistent wording across all surfaces.

### Step 8: Routing logic is documented deterministically

**Maps to**: AC8

1. Read `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`.

**Expected result**: The doc contains a deterministic routing table mapping
(input + discovered state + configuration) → routing mode for all five modes.

### Step 9: Unit tests cover the routing decisions

**Maps to**: AC9

1. Run `bash scripts/development-workflow/tests/test-run-work-router.sh`.

**Expected result**: The suite passes and includes cases for no target, one
target, multiple targets, and an epic target (plus negative/ambiguous cases).

### Step 10: Ambiguous request stops with no mutation

**Maps to**: AC11

1. Run the router with an unresolvable token (e.g. a non-existent issue number or
   a mixed list containing an unresolvable token).

**Expected result**: `MODE=ambiguous`, a stop reason is recorded, and no artifact
is mutated.

### Last Step: Validate & shut down

- Verify every assertion in the checklist below is met.
- Confirm `markdownlint-cli2` passes on the new/edited markdown files.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: No-target invocation records `no_target_scan`, proposes the
      configuration-bounded plan, and lists advance/hold-back items.
- [ ] AC2: One non-epic target records `single_item` and advances only that item.
- [ ] AC3: Two+ explicit targets record `explicit_list`, a hard bounded scope,
      and log out-of-scope items without mutating them.
- [ ] AC4: Epic target records `epic` and completes read-only scope resolution
      before any mutation.
- [ ] AC5: A single epic-like target routes to `epic`, not `single_item`.
- [ ] AC6: `/run-item-work` and `/run-epic` invoked directly still work and match
      `/run-work` routing for the equivalent target.
- [ ] AC7: README, AGENTS.md, wrappers, and skill metadata teach `/run-work` first
      and label `/run-item-work` and `/run-epic` as aliases, consistently.
- [ ] AC8: Routing logic is documented deterministically in the workflow
      protocols.
- [ ] AC9: Tests cover routing for no/one/multiple/epic targets.
- [ ] AC10: Every invocation emits a routing-decision record (mode, scope,
      inputs).
- [ ] AC11: An unresolvable request records `ambiguous`, performs no mutation, and
      stops for a human.

---

## Seed Data Reference

No persisted seed data is required. The unit-test suite simulates discovered
state (epic vs non-epic issues, open PRs, branch existence, unresolvable tokens)
via a mock `gh`/`git` on `PATH`, following the established
`test-run-epic-*.sh` pattern.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Mock `gh`/`git` | Routing inputs for each mode + a mutating-call guard | Inline in `scripts/development-workflow/tests/test-run-work-router.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Router cannot resolve a real target | `gh` not authenticated | Run `gh auth status`; authenticate or use the test/mock mode |
| No-target run omits guardrails values | #979 not merged into `develop-guardrails` | Merge #979 first; the `guardrails` section must exist before no-target reporting works |
| `MODE=ambiguous` for a valid target | Token form not covered by the routing table | Re-check the routing table in protocol 96 and the matching case in `test-run-work-router.sh` |

---

## Known Limitations

- This runbook exercises the routing classifier and documentation; it does not
  re-run the full Protocol 90/91/95 stage execution end-to-end (those protocols
  retain their existing, already-tested behavior — BR11).
- Live target-resolution steps require `gh` authentication and real
  issues/branches/PRs; in CI or offline contexts use the unit-test suite
  (Step 9), which mocks discovered state.
