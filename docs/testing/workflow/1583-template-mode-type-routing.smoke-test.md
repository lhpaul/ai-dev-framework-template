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
`scan-backlog-no-artifacts-held`, `scan-stale-backlog-with-artifacts-continues`,
`scan-status-unreadable-defers`, `gate-usage-errors`, `prelude-issue-no-folder-stops`,
`stale-backlog-active-fix-branch-continues`, `stale-backlog-merged-fix-pr-continues`,
`backlog-no-folder-no-branch-stops`, `branch-evidence-unavailable-defers`,
`stale-backlog-open-fix-branch-no-pr-continues`, `scan-merged-implementation-pr-continues`,
`prelude-issue-one-folder-uses-its-stage`, `prelude-issue-multiple-folders-passes`,
`guidance-check-planted-violation`,
the nine `lookup-unavailable-*` cases, `framework-lookup-ignores-type-field`,
`consumer-prelude-workflow-unchanged`, `consumer-next-action-workflow-unchanged`,
`consumer-batch-plan-workflow-unchanged`, `consumer-routing-all-classes-unchanged`,
`release-unavailable-continues-unsatisfied`, and `retro-unavailable-continues-unsatisfied`
must be covered by harness or the steps below.)

**Exit-code convention for this runbook**: every command block below fails the smoke test when
it exits non-zero, unless the step says otherwise. Step 4's guidance check is deliberately
**not** written as `! rg …` — a command negated by `!` is exempt from `set -e` in bash and
zsh, so that form would keep going past a real violation. It uses an explicit status
assertion that exits on its own; see Step 4 for the helper and its planted-violation proof.

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
framework items". Exit `0`. This manual step exercises cause 2 only; the full closed list is
nine causes, each with its own `REASON` and its own named automated case:

| # | Cause | `REASON` | Named case |
| --- | --- | --- | --- |
| 1 | Provider is not `github_projects` | `provider_unsupported` | `lookup-unavailable-provider-unsupported` |
| 2 | Project number missing | `project_number_missing` | `lookup-unavailable-project-number-missing` |
| 3 | Project number non-numeric | `project_number_invalid` | `lookup-unavailable-project-number-invalid` |
| 4 | Project owner unresolvable | `project_owner_unresolvable` | `lookup-unavailable-project-owner-unresolvable` |
| 5 | Repository owner/name unresolvable | `repo_unresolvable` | `lookup-unavailable-repo-unresolvable` |
| 6 | `gh issue list` failed (non-zero exit) | `issue_list_failed` | `lookup-unavailable-issue-list-failed` |
| 7 | `gh issue list` succeeded but returned blank or malformed JSON | `issue_list_blank_or_malformed` | `lookup-unavailable-issue-list-blank-or-malformed` |
| 8 | `gh project item-list` failed | `item_list_failed` | `lookup-unavailable-item-list-failed` |
| 9 | Item-list JSON unparseable | `item_list_unparseable` | `lookup-unavailable-item-list-unparseable` |

**Fail if** any of the nine named cases is missing from the harness, or two causes share a
`REASON`: a declared cause without a passing case is an unimplemented claim.

2a. Issue-list response validation (cause 7). Force `gh issue list` to exit `0` with blank
output, then with malformed JSON, and run the wrapper each time.

**Expected**: `STATUS=unavailable` with `REASON=issue_list_blank_or_malformed`, `JSON=[]`,
exit `0`, both times. **Fail if** either run reports `STATUS=empty` — today the primitive
returns `[]` for a blank response (`workflow-lib.sh:3316`), which reads as "no open items" —
or `REASON=item_list_unparseable`, which blames the project item-list request for an
issue-list problem.

2b. Type field independence (`framework-lookup-ignores-type-field`). Point the lookup at a
board whose Type field is renamed, misconfigured, or absent — or use the harness fixture.

**Expected (framework mode)**: `STATUS=ok` with the board's open items (or `empty` on an empty
board) — **not** `unavailable`. Framework mode returns every open non-terminal item regardless
of Type, so it never reads the classification field and that field's readability cannot change
the answer. **Fail if** the lookup reports `unavailable` here: that would mean a Type read was
added, contradicting the criteria and the decision matrix. (Consumer mode is unchanged and
keeps today's behavior, including its existing "Type field unreadable" stderr warning.)

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

2. Run the backlog type gate for a single-item caller. The gate has exactly two callers: the
   bounded prelude's `item` scope (`single`) and the portfolio scan (`scan`). Explicit-list
   (`--items` / `/run-items`) and epic (`--epic` / `/run-epic`) runs are unchanged by this
   item and call no gate — see the plan's Out of Scope.

```bash
./scripts/development-workflow/framework-mode-backlog-type-gate.sh \
  --issue <number> --status Backlog --artifact-stage '' \
  --branch-pr-evidence none --caller single
```

All five flags — `--issue`, `--status`, `--artifact-stage`, `--branch-pr-evidence`,
`--caller` — are **required**, and `--status` / `--artifact-stage` accept the empty string as a
value. Pass `--artifact-stage ''` when the item has no development-folder spec or plan, and
state the branch/PR evidence explicitly (`none` / `present` / `unavailable`). Omitting either
flag is a usage error (exit `64`, no `RESULT=` line), not a shorthand for "no work": fast-track
items use no development folder at all, so the folder's absence alone never justifies a stop.

**Expected**: `RESULT=stop`, `STOP_CONDITION=missing_tracker_context`, `ITEM=#<number>`, and a
`REASON_TEXT` that **names the item** by number, states the class is not valid in a
framework-mode repository, and names the re-classification that unblocks it. A stop that does
not name the item fails this step.

3. Assert **no mutation** on that stop path (`stop-path-no-mutation`): Type and Status on the
   tracker are unchanged; no new branch created for the item. Prefer the harness spy/mock; if
   checking live, record Type/Status/branch before and after the stop and confirm equality.

4. Repeat with `--caller scan` (same four required flags).

**Expected**: `RESULT=hold`, `ITEM=#<number>`, same naming `REASON_TEXT`, and **no**
`STOP_CONDITION` key (a hold is not a stop).

4a. Argument validation (`gate-usage-errors`). Run the gate with each of: a missing `--issue`,
a missing `--status`, a missing `--artifact-stage`, a missing `--caller`, `--caller bogus`,
`--artifact-stage Frobnicated`, a missing `--branch-pr-evidence`, `--branch-pr-evidence maybe`,
`--issue abc`, a flag given with no value, and an unknown flag.

**Expected**: each run exits `64` with a usage message on stderr and prints **no** `RESULT=`
line. Then confirm the empty and `none` forms are accepted values rather than errors:
`--status ''`, `--artifact-stage ''` and `--branch-pr-evidence none` produce a normal routing
outcome and exit `0`. **Fail if** a
malformed invocation produces a `RESULT=` line of any kind — a usage error must never be
readable as a routing decision.

4b. Scan end state (`scan-misclassified-item-held`) — the gate result alone is not enough.
Feed a batch-plan block for that item, plus a sibling Feature item, through
`workflow-batch-lanes.sh`.

**Expected**: for the misclassified item, `DISPATCH=held`, `REPORT_CATEGORY=held`,
`REPORT_LABEL=HELD - not included in proposed batch`, and a `HOLD_REASON` naming the item; for
the sibling, `DISPATCH=proposed` / `REPORT_CATEGORY=proposed_batch`. The script exits `0`.
**Fail if** the misclassified item shows `DISPATCH=proposed` (the pre-change behavior for an
unrecognized `NEXT_ACTION`, which falls through to the review lane) or `REPORT_CATEGORY`
`informational`.

4c. Effective stage, part 1 — Backlog with no work (`scan-backlog-no-artifacts-held`). The gate
takes **two** inputs: the tracker status and the artifact stage from
`workflow-next-action.sh`. Use a development folder that holds neither a spec nor a plan (so
next-action exits `66`), while the tracker says Status `Backlog` and Type `Workflow`:

```bash
./scripts/development-workflow/workflow-batch-plan.sh --scan <development-path>
```

**Expected**: the emitted block carries `STATUS=Backlog` (the tracker value),
`NEXT_ACTION=hold-misclassified-type`, `MISCLASSIFIED_TYPE=Workflow`, a
`MISCLASSIFIED_TYPE_REASON` naming the item, and `MISCLASSIFIED_TYPE_CHECK=applied`.
**Fail if** the item is dispatched: this is the case the feature exists for.

4c-ii. Effective stage, part 2 — stale Backlog with work already done
(`scan-stale-backlog-with-artifacts-continues`). Repeat with a folder whose merged spec makes
next-action report `Spec Ready`, while the tracker still says `Backlog` and Type `Workflow`.

**Expected**: the item is **not** held. Its `NEXT_ACTION` and `DISPATCH` match the pre-feature
baseline, and the gate reports `REASON=stale_backlog_reconciled`. **Fail if** the item is
held — a stale tracker status must not re-decide a pipeline that has already started, and the
spec does not re-evaluate an item already on one. Repeat with `Plan Ready` and
`In Development` folders.

4c-iii. Effective stage, part 3 — fast-track work has no folder
(`stale-backlog-active-fix-branch-continues`, `stale-backlog-merged-fix-pr-continues`,
`backlog-no-folder-no-branch-stops`). `fix/` and `hotfix/` items use no development folder at
all (`workflow-next-action.sh:601`), so "no folder" alone must never justify a stop. For an
issue whose tracker says `Backlog` with Type `Workflow` and which has **no** development
folder, run the single-item path three ways:

1. with an **open** `fix/<issue>-<slug>` branch **and** an open PR for it;
2. with a live `fix/<issue>-<slug>` branch and **no PR at all** — the normal state right after
   a fast-track branch is cut (`stale-backlog-open-fix-branch-no-pr-continues`);
3. with a **merged** `fix/` or `hotfix/` PR and no live branch;
4. with none of the above.

**Expected**: (1), (2) and (3) `RESULT=pass` with `REASON=branch_or_pr_in_flight` — nothing
stopped; (4) `RESULT=stop` (or `hold` for `--caller scan`). **Fail if** (1), (2) or (3) stops:
that is live fast-track work being halted because it does not use a development folder. Case
(2) fails unless the caller runs the branch probe — the scope JSON lists no branches. **Fail
if** (4) passes: that is the case the feature exists for.

4c-iii-b. Scan-side merged PR (`scan-merged-implementation-pr-continues`). For a folder-bearing
item whose only evidence is a **merged** implementation PR — no live branch, no open PR — run
the scan.

**Expected**: the item is **not** held; the gate reports `branch_or_pr_in_flight`. **Fail if**
it is held: `open_implementation_pr_metadata` lists `--state open` only, so this case passes
only when the scan also runs the merged-PR probe.

4c-iv. Unreadable branch/PR evidence (`branch-evidence-unavailable-defers`). Repeat case (3)
with `gh` unavailable or `gh pr list` failing.

**Expected**: `RESULT=pass` with `REASON=branch_evidence_unavailable`, and the caller records
`MISCLASSIFIED_TYPE_CHECK=deferred`. **Fail if** the item is stopped or held on evidence that
could not be read — unreadable inputs fail open here, exactly as an unreadable status or Type
does.

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
Type is missing or empty.

**Expected**: `RESULT=pass` in both cases (`status_unreconciled` / `type_absent`) — unchanged
from pre-feature behavior. **Fail if** either case stops or holds; the spec has no acceptance
criterion for an absent class or an unreconcilable status, and this feature must not add one.

5c. Unparseable Type — different answer per caller, and neither is new behavior. With an item
whose project JSON is present but whose Type cannot be parsed
(`get_tracker_type_for_issue` warns at `workflow-lib.sh:2321` and exits non-zero):

- **Scan caller**: `RESULT=pass` with `REASON=type_unreadable`, and the scan block carries
  `MISCLASSIFIED_TYPE_CHECK=deferred`. The gate must not inherit the helper's non-zero exit.
- **Single caller (prelude `item` scope)**: the gate is never reached —
  `run-epic-scope-resolver.sh:687`–`:689` already aborts scope resolution with "failed to read
  tracker type for issue #N". That is today's behavior; **fail this step if the
  implementation softened or removed that abort**, which is out of scope for this item.

5d. Multi-item scopes are untouched. Run the prelude for an explicit list and for an epic that
each include the misclassified item:

```bash
./scripts/development-workflow/run-bounded-prelude.sh --items "<misclassified>,<valid>,<valid>" --json
./scripts/development-workflow/run-bounded-prelude.sh --epic <epic-with-that-child> --json
```

**Expected**: output identical to the pre-feature baseline for both — no gate call, no stop,
and no misclassification key of any kind. **Fail if** either run gains a hold, a stop, or a new
key: explicit-list and epic scopes are deferred to `#1779` and must not change
here.

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

   **Why this is not written as `! rg …`**: under `set -e`, a command whose status is inverted
   by `!` is exempt from errexit in both bash and zsh, so a `! rg` that finds stale guidance
   returns non-zero and the script **keeps going** — the check reports nothing and passes. The
   assertion below therefore inspects `rg`'s status explicitly and exits itself. It also
   distinguishes `rg`'s three exits: `0` = match found (stale guidance survives → fail),
   `1` = no match (the only passing case), `2` or higher = `rg` itself errored, e.g. a bad
   pattern or an unreadable path (→ fail, because a check that did not run must not report
   clean).

```bash
set -uo pipefail   # deliberately not -e: assert_absent does its own exiting

assert_absent() {
  local label="$1"; shift
  local status=0
  rg -n "$@" || status=$?
  case "$status" in
    0) printf 'FAIL: stale guidance still present (%s)\n' "$label" >&2; exit 1 ;;
    1) printf 'ok: %s\n' "$label" ;;
    *) printf 'FAIL: rg exited %s while checking %s — check did not run\n' \
         "$status" "$label" >&2; exit 1 ;;
  esac
}

# Root agent files must not still recommend Workflow for framework/process work:
assert_absent 'agent-guidance Workflow recommendation' \
  'Use `Workflow` for' AGENTS.md CLAUDE.md GEMINI.md \
  .cursor/agents/orchestrator.md .claude/agents/orchestrator.md

# Retrospective create paths must not still assign Type Workflow (pre-change string only;
# refusal wording that mentions Type Workflow must not match):
assert_absent 'retrospective create assigns Workflow' \
  'update_tracker_type_best_effort "\$ISSUE_NUMBER" "Workflow"' \
  docs/workflow/development-workflow/protocols/06-retrospective-protocol.md \
  docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md

# Protocols 90/91 must not still route Backlog+Workflow by the brief (pre-change phrases
# only; "do not infer" must not match):
assert_absent 'protocol 90 route-by-brief row' \
  'route by brief: full pipeline' \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
assert_absent 'protocol 91 route-by-brief row' \
  "Route by the brief's concrete path" \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md

# The retrospective runbook must not still expect the created issue to carry Type Workflow
# without the framework-mode branch (single-match anchor, verified on the pre-change tree):
assert_absent 'retrospective runbook Workflow expectation' \
  'with Type `Workflow`' \
  docs/testing/workflow/retrospective-protocol.smoke-test.md

# The tracker-Type runbook must not still tell an operator to create a Workflow-typed issue
# here without scoping that step to consumer mode (single-match anchor):
assert_absent 'tracker-Type runbook Workflow creation step' \
  'project Type will be set to `Workflow`' \
  docs/testing/workflow/tracker-type-field-classification.smoke-test.md
```

**Expected**: six `ok:` lines and exit `0`. Any stale match, or any `rg` error, prints `FAIL:`
and exits `1`.

2b. **Planted-violation proof (required).** A check that has never failed is not known to
work. Before accepting the result above, re-introduce one pre-change string — for example
append ``Use `Workflow` for framework work`` to a scratch copy of `AGENTS.md`, or re-add the
`with Type `Workflow`` sentence to the retrospective runbook — and re-run the block.

**Expected**: the run prints `FAIL: stale guidance still present (…)` naming that check and
exits `1`. Revert the planted string and confirm the block returns to six `ok:` lines.
**Fail this step if the planted violation does not produce a non-zero exit** — that means the
guard is decorative, which is exactly the failure mode the `! rg` form had.

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
