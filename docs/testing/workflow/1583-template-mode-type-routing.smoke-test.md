# Framework-Mode Work-Item Classification — Smoke Test

**Plan**: [1583 implementation plan](../../specs/developments/20260911230727_1583-template-mode-type-routing/2_1583-template-mode-type-routing_implementation-plan.md)
**Spec**: [1583 spec](../../specs/developments/20260911230727_1583-template-mode-type-routing/1_1583-template-mode-type-routing_specs.md)

Manual smoke checks after the implementation PR merges (or on the feature branch before
readiness). Requires `gh` auth and a GitHub Projects board when exercising live tracker steps;
script-level checks use the regression harness first.

---

## Preconditions

- Repository declares framework mode: `template.is_template: true` in `.ai-dev-workflow.yaml`.
- On `develop` or the implementation branch with this feature applied.
- Regression harness green:

```bash
bash scripts/development-workflow/tests/test-add-backlog-item.sh
bash scripts/development-workflow/tests/test-framework-mode-type-routing.sh
```

(Use `test-workflow-lib-github-projects.sh` instead of the dedicated file if the plan collapses
suites. Named scenarios `creation-refusal-no-bypass`, `stop-path-no-mutation`,
`reclassify-then-route`, `consumer-prelude-workflow-unchanged`,
`consumer-next-action-workflow-unchanged`, `release-unavailable-continues-unsatisfied`, and
`retro-unavailable-continues-unsatisfied` must be covered by harness or the steps below.)

---

## Step 1: Creation refusal (framework mode)

Prefer the automated fixture for CI. Live invocation against this template repo is **optional**
and only safe after the refusal lands — if refusal is missing, the command would create a real
issue (delete it immediately if that happens).

1. Harness (required):

```bash
bash scripts/development-workflow/tests/test-add-backlog-item.sh
```

**Expected**: Framework-mode `--type Workflow` fails before create; scenario
`creation-refusal-no-bypass` passes (no force/confirm/env bypass accepts Workflow; Linear
`create` handoff refuses likewise).

2. Optional live dry-run (only when refusal is already implemented):

```bash
./scripts/development-workflow/add-backlog-item.sh create \
  --title "SMOKE 1583 refuse workflow" \
  --body "Ephemeral smoke — delete if created" \
  --type Workflow
```

**Expected**: Non-zero exit, stderr names Workflow as invalid and lists Feature/Bug/Refactor, no
issue URL on stdout.

3. Optional: repeat with `--type Bug`.

**Expected**: Success (issue URL printed) — delete the smoke issue from the tracker afterward.

---

## Step 2: Framework-item lookup semantics

1. With framework mode enabled, run the documented lookup wrapper:

```bash
./scripts/development-workflow/list_open_framework_items.sh
echo "exit=$?"
```

**Expected**: Stdout always includes all three keys:
`FRAMEWORK_ITEMS_LOOKUP_STATUS=…`, `FRAMEWORK_ITEMS_LOOKUP_REASON=…` (may be empty), and
`FRAMEWORK_ITEMS_JSON=…`. Status is `ok` when open items exist (any Type), `empty` only for a
completed read with no open items, and `unavailable` with a non-empty reason when the tracker
read fails. Exit code is `0` for `ok`, `empty`, and `unavailable`.

2. Temporarily unset `GITHUB_PROJECT_NUMBER` and remove `project_number` from config in a local
   test checkout **or** use the harness fixture for unavailable mode.

**Expected (framework mode)**: `STATUS=unavailable`, non-empty `REASON` — not silent "no
framework items". Exit `0`.

3. Flow-level unavailable (required — harness or manual protocol walkthrough):

- Protocol `05` (`release-unavailable-continues-unsatisfied`): with lookup forced unavailable,
  release flow **continues**; output states lookup was not performed; open-script-bug review is
  **not** recorded as satisfied.
- Protocol `06` (`retro-unavailable-continues-unsatisfied`): same for retrospective — flow
  continues; a finding is **not** recorded as having no related item solely because lookup was
  unavailable.

**Fail if**: either flow stops on unavailable, or marks the dependent check satisfied.

---

## Step 3: Backlog routing gate

1. Identify a Backlog issue classified `Workflow` (or create one in a consumer test repo — not
   in this template repo after Step 1).

2. Run the backlog type gate for a single-item caller:

```bash
./scripts/development-workflow/framework-mode-backlog-type-gate.sh \
  --issue <number> --status Backlog --caller single
```

**Expected**: `RESULT=stop`, `STOP_CONDITION=missing_tracker_context`, message names
re-classification.

3. Assert **no mutation** on that stop path (`stop-path-no-mutation`): Type and Status on the
   tracker are unchanged; no new branch created for the item. Prefer the harness spy/mock; if
   checking live, record Type/Status/branch before and after the stop and confirm equality.

4. Repeat with `--caller scan`.

**Expected**: `RESULT=hold` (not a global stop).

5. Pick an item whose tracker Status is `Spec Ready`, `Writing Plan`, or `In Development` that still shows Type `Workflow`.

**Expected**: `RESULT=pass`.

6. **Post-reclassification** (`reclassify-then-route`): re-class the item to Feature, then Bug,
   then Refactor; re-run through prelude / next-action. Each class routes as today. For Bug,
   confirm the existing scope check still runs (scope-check failure fixture still blocks
   fast-track).

7. **Consumer fixtures** (`consumer-prelude-workflow-unchanged`,
   `consumer-next-action-workflow-unchanged`): under consumer config, Backlog + Workflow through
   `run-bounded-prelude.sh` and `workflow-next-action.sh` matches pre-feature routing (no
   stop/hold from this gate). Harness golden/diff evidence required.

---

## Step 4: Guidance mirror check (closed list + grep)

Closed mirror list (must all agree; see plan):

1. `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`
2. `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
3. `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
4. `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
5. `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`
6. `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`
7. `docs/workflow/development-workflow/integrations/github-projects.md`
8. `AGENTS.md`
9. `CLAUDE.md`
10. `GEMINI.md`
11. `.cursor/agents/orchestrator.md`
12. `.claude/agents/orchestrator.md`

1. Spot-check `AGENTS.md` Tracker Classification and protocol `00`.

**Expected**: Framework-mode rule visible; no instruction to file framework work as Workflow in
this repository.

2. Grep check that **must fail** if old framework-mode Workflow guidance survives (run from
   repo root; adjust wrapper if harness owns this):

```bash
# Fail if root agent files still recommend Workflow for framework/process work:
! rg -n 'Use `Workflow` for' AGENTS.md CLAUDE.md GEMINI.md \
  .cursor/agents/orchestrator.md .claude/agents/orchestrator.md

# Fail if retrospective create paths still assign Type Workflow (pre-change string only;
# refusal wording that mentions Type Workflow must not match):
! rg -n 'update_tracker_type_best_effort "\$ISSUE_NUMBER" "Workflow"' \
  docs/workflow/development-workflow/protocols/06-retrospective-protocol.md \
  docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md

# Fail if protocols 90/91 still route Backlog+Workflow by the brief (pre-change phrases only;
# "do not infer" must not match):
! rg -n 'route by brief: full pipeline' \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
! rg -n "Route by the brief's concrete path" \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
```

**Expected**: All four commands exit 0 (no matches). Any match = smoke failure.

---

## Pass criteria

All steps match expected behavior; regression harness from Preconditions remains green; named
scenarios listed in Preconditions are evidenced by harness output or the flow-level / routing /
grep steps above.
