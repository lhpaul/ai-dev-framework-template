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
suites. Named scenarios `creation-refusal-no-bypass`,
`framework-creation-valid-types-preserved`, `consumer-creation-all-classes-unchanged`,
`stop-path-no-mutation`, `reclassify-then-route`, `framework-post-backlog-statuses-pass`,
`scan-misclassified-item-held`, `scan-misclassified-not-informational`,
`scan-uses-tracker-status-not-artifacts`, `scan-status-unreadable-defers`,
`consumer-prelude-workflow-unchanged`, `consumer-next-action-workflow-unchanged`,
`consumer-batch-plan-workflow-unchanged`, `consumer-routing-all-classes-unchanged`,
`release-unavailable-continues-unsatisfied`, and `retro-unavailable-continues-unsatisfied`
must be covered by harness or the steps below.)

**Exit-code convention for this runbook**: every command block below fails the smoke test when
it exits non-zero, unless the step says otherwise. This matters most in Step 4, where the
checks are written as `! rg …`: a surviving match makes `rg` exit `0`, `!` inverts that to a
non-zero exit, and the non-zero exit **is** the smoke failure. Run those blocks under a shell
with `set -e`, or check `$?` after each one; a silently ignored non-zero exit defeats the
check.

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

**Exact key spellings — no glob shorthand.** The three published keys are
`FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, and `FRAMEWORK_ITEMS_JSON`.
The third has **no** `LOOKUP_` segment, so grepping or matching on
`FRAMEWORK_ITEMS_LOOKUP_*` does **not** cover it. Assert the three literals exactly; a check
built on that glob silently skips the JSON key. (Same note appears in the plan's Enforcement
point 2 and Reversal (2).)

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

**Expected**: `RESULT=stop`, `STOP_CONDITION=missing_tracker_context`, `ITEM=#<number>`, and a
`REASON_TEXT` that **names the item** by number, states the class is not valid in a
framework-mode repository, and names the re-classification that unblocks it. A stop that does
not name the item fails this step.

3. Assert **no mutation** on that stop path (`stop-path-no-mutation`): Type and Status on the
   tracker are unchanged; no new branch created for the item. Prefer the harness spy/mock; if
   checking live, record Type/Status/branch before and after the stop and confirm equality.

4. Repeat with `--caller scan`.

**Expected**: `RESULT=hold`, `ITEM=#<number>`, same naming `REASON_TEXT`, and **no**
`STOP_CONDITION` key (a hold is not a stop).

4b. Scan end state (`scan-misclassified-item-held`) — the gate result alone is not enough.
Feed a batch-plan block for that item, plus a sibling Feature item, through
`workflow-batch-lanes.sh`.

**Expected**: for the misclassified item, `DISPATCH=held`, `REPORT_CATEGORY=held`,
`REPORT_LABEL=HELD - not included in proposed batch`, and a `HOLD_REASON` naming the item; for
the sibling, `DISPATCH=proposed` / `REPORT_CATEGORY=proposed_batch`. The script exits `0`.
**Fail if** the misclassified item shows `DISPATCH=proposed` (the pre-change behavior for an
unrecognized `NEXT_ACTION`, which falls through to the review lane) or `REPORT_CATEGORY`
`informational`.

4c. Status source (`scan-uses-tracker-status-not-artifacts`) — the scan must gate on the
**tracker** status, not the artifact-derived one. Use a development folder whose merged spec
and missing plan would make `workflow-next-action.sh` report `Spec Ready`, while the tracker
says Status `Backlog` and Type `Workflow`, then run the scan:

```bash
./scripts/development-workflow/workflow-batch-plan.sh --scan <development-path>
```

**Expected**: the emitted block carries `STATUS=Backlog` (the tracker value),
`NEXT_ACTION=hold-misclassified-type`, `MISCLASSIFIED_TYPE=Workflow`, a
`MISCLASSIFIED_TYPE_REASON` naming the item, and `MISCLASSIFIED_TYPE_CHECK=applied`.
**Fail if** the block shows `STATUS=Spec Ready` or any next action other than the hold — that
is the bypass this step exists to catch.

4d. Unreadable status (`scan-status-unreadable-defers`). Repeat 4c with the tracker status read
returning empty (Linear provider, no `project_number` / `GITHUB_PROJECT_NUMBER`, or an issue
absent from the board).

**Expected**: the item is **not** held — its `NEXT_ACTION` and `DISPATCH` match the pre-feature
baseline for that folder — and the block carries `MISCLASSIFIED_TYPE_CHECK=deferred` with a
reason. **Fail if** the item is held (a false hold on an unread status) **or** if the deferred
marker is absent (a silent claim that the check ran).

5. Pick an item that still shows Type `Workflow` at **any** recognized non-Backlog status —
   check at least two, e.g. `Spec Ready` and `Development in Review`
   (`framework-post-backlog-statuses-pass` covers `Writing Spec` through `Released` in the
   harness).

**Expected**: `RESULT=pass` with `REASON=pipeline_already_chosen`, for every non-Backlog
status. There is no privileged subset of statuses: only reconciled `Backlog` stops or holds.

5b. Run the gate with a status string the board does not recognize, and with an item whose
Type is empty or unreadable.

**Expected**: `RESULT=pass` in both cases (`status_unreconciled` / `type_absent_or_unreadable`)
— unchanged from pre-feature behavior. **Fail if** either case stops or holds; the spec has no
acceptance criterion for an absent class or an unreconcilable status, and this feature must not
add one.

6. **Post-reclassification** (`reclassify-then-route`): re-class the item to Feature, then Bug,
   then Refactor; re-run through prelude / next-action. Each class routes as today. For Bug,
   confirm the existing scope check still runs (scope-check failure fixture still blocks
   fast-track).

7. **Consumer fixtures** (`consumer-prelude-workflow-unchanged`,
   `consumer-next-action-workflow-unchanged`, `consumer-batch-plan-workflow-unchanged`,
   `consumer-routing-all-classes-unchanged`): under consumer config, Backlog routing through
   `run-bounded-prelude.sh`, `workflow-next-action.sh`, and `workflow-batch-plan.sh` matches
   pre-feature behavior for **every** class — Feature, Bug, Refactor, Workflow, and no class at
   all (no stop/hold from this gate; `MISCLASSIFIED_TYPE_CHECK=not_applicable`). Harness
   golden/diff evidence required; Workflow-only evidence does not discharge the "every class"
   acceptance criterion.

8. **`workflow-next-action.sh` untouched**: confirm the implementation diff contains no change
   to `scripts/development-workflow/workflow-next-action.sh`. Its status is artifact-derived
   and can never be `Backlog`, which is why the gate is fed from the tracker read in
   `workflow-batch-plan.sh` and from the resolved scope JSON instead. A diff touching that
   script means the gate was wired into the wrong place.

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
13. `docs/testing/workflow/retrospective-protocol.smoke-test.md`
14. `docs/testing/workflow/tracker-type-field-classification.smoke-test.md`
15. `scripts/development-workflow/add-backlog-item.sh` (`--type` help text and exit-code list)

In this repository `CLAUDE.md` and `GEMINI.md` are symlinks to `AGENTS.md`, so rows 8–10 are
one file; the grep below still names all three because `rg` follows a symlink passed as an
explicit argument (it does not follow symlinks during recursion), and downstream repositories
may hold real files there.

1. Spot-check `AGENTS.md` Tracker Classification and protocol `00`.

**Expected**: Framework-mode rule visible; no instruction to file framework work as Workflow in
this repository.

2. Grep check that **must fail** if old framework-mode Workflow guidance survives (run from
   repo root; adjust wrapper if harness owns this).

   **Exit-code semantics**: each block is a negated `rg`. `rg` exits `0` when it finds a
   match and `1` when it finds none, so `! rg …` exits **non-zero exactly when stale guidance
   survives**. A non-zero exit from any of these six commands is a smoke failure — not a
   warning, and not "no output, so fine". Run the block under `set -e` (or inspect `$?` after
   each command); piping these into something that swallows the status makes the check
   vacuous.

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

# Fail if the retrospective runbook still expects the created issue to carry Type Workflow
# without the framework-mode branch (single-match anchor, verified on the pre-change tree):
! rg -n 'with Type `Workflow`' \
  docs/testing/workflow/retrospective-protocol.smoke-test.md

# Fail if the tracker-Type runbook still tells an operator to create a Workflow-typed issue
# here without scoping that step to consumer mode (single-match anchor):
! rg -n 'project Type will be set to `Workflow`' \
  docs/testing/workflow/tracker-type-field-classification.smoke-test.md
```

**Expected**: All six commands exit `0`, which for a negated `rg` means **no matches**. Any
match makes the command exit non-zero, and that non-zero exit is the smoke failure.

3. Instructing-surface sweep (residual completeness evidence for the closed list):

```bash
# grep --include patterns match basenames while recursing, so these single-star forms
# are correct; a '**/' prefix would not mean here what it means to a shell.
# <!-- markdown-heuristic-disable GLOB001 -->
INCLUDES=(--include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml')
grep -rn -E 'Type.{0,15}`?Workflow|--type Workflow|Workflow.{0,15}Type' \
  "${INCLUDES[@]}" . \
  | grep -v '^\./\.git/' | grep -v '^\./docs/specs/developments/'

# The creation script's help text splits "Type" and "Workflow" across two lines, so the
# pattern sweep above cannot see it; check that file directly (closed-list row 15):
grep -n 'Workflow' scripts/development-workflow/add-backlog-item.sh
```

**Expected**: every remaining hit is accounted for by a closed-list row above or by the
out-of-list table in the plan (`workflow-lib.sh`'s unchanged primitive, test fixtures,
`CHANGELOG.md`, historical specs and plans, the legacy-label sentences in protocols `05` /
`90` / `91`). An unaccounted hit is a missing mirror surface and must be added to the closed
list in the same PR.

4. Spot-check the creation script's help text (closed-list row 15):

```bash
./scripts/development-workflow/add-backlog-item.sh --help
```

**Expected**: the `--type` line notes that framework-mode repositories refuse `Workflow`, and
the exit-code list names that refusal alongside the existing exit `1` case.

---

## Pass criteria

All steps match expected behavior; regression harness from Preconditions remains green; named
scenarios listed in Preconditions are evidenced by harness output or the flow-level / routing /
grep steps above.
