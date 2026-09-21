# Framework-Mode Work-Item Classification — Implementation Plan

**Spec**: [Framework-Mode Work-Item Classification](1_1583-template-mode-type-routing_specs.md)
**Smoke test runbook**: [1583-template-mode-type-routing.smoke-test.md](../../../testing/workflow/1583-template-mode-type-routing.smoke-test.md)

---

## Step 0: Template-Fit Check

**Detection**: `.ai-dev-workflow.yaml` sets `template.is_template: true`, so this check is mandatory.

**Evaluation**: **PASS — generic.** The work changes this template's own workflow tooling
(Bash helpers under `scripts/development-workflow/`, their regression harnesses, and workflow
protocol/agent guidance). It references no downstream application stack. Acceptance criteria are
expressed in repository-mode and tracker-field terms every consumer inherits.

**Action**: continue. No human confirmation required.

---

## Summary

**Approach**: Treat `template.is_template: true` as **framework mode** (reuse
`workflow_template_is_template`, no new config key). Enforce the spec's three enforcement points
in code where deterministic behavior matters — backlog creation refusal, framework-item lookup
semantics, and Backlog routing for Type `Workflow` — and align every mirror surface (protocols,
`AGENTS.md` copies, tracker integration guide) so agents are not instructed toward a class the
same repository refuses.

**Estimated complexity**: **M** (2–4 days).

**Rationale**: Most behavior is classification-gate logic plus documentation parity. The highest
risk is silently conflating "lookup unavailable" with "empty board" in framework mode and
accidentally changing consumer-repository paths; tests must pin both modes explicitly.

**Dependencies**: Spec PR #1734 (merged). Bulk re-classification (#1584) is explicitly out of
scope and must not be bundled into this implementation PR.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `3260570` |
| Framework-mode switch | `workflow_template_is_template` in `scripts/development-workflow/workflow-lib.sh` | Existing helper; prints `true` only for affirmative `template.is_template` |
| Creation path | `scripts/development-workflow/add-backlog-item.sh` | Creates issue before Type update; no pre-create Type validation today |
| Framework-item discovery | `list_open_workflow_type_issues` in `workflow-lib.sh` | Filters `item_type == "Workflow"`; warnings on stderr for some failure modes but stdout still `[]` |
| Routing tables (docs) | `rg 'Backlog \\(Workflow\\)' docs/workflow/development-workflow/protocols/{90,91}-*.md` | Both still describe infer-path / batch-start for Workflow |
| Agent guidance | `rg 'Workflow' AGENTS.md` (Tracker Classification) | Still recommends Workflow for framework/process/tooling items |
| Retrospective create path | `06-retrospective-protocol.md` | Instructs `update_tracker_type_best_effort … Workflow` |
| Mirror-check anchor literal 1 | `grep -c 'Use `Workflow` for' AGENTS.md` | **1 match** — verified 2026-09-20 |
| Mirror-check anchor literal 2 | `grep -rn 'update_tracker_type_best_effort "$ISSUE_NUMBER" "Workflow"' .` | **2 matches** — `integrations/github-projects.md:202`, `protocols/06-retrospective-protocol.md:510`; verified 2026-09-20. Note the retrospective match is at `:510`, not the `:124` lookup line |
| Mirror-check anchor literal 3 | `grep -c 'Route by the brief' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | **1 match** — verified 2026-09-20 |
| Mirror-check anchor literal 4 | `grep -ric 'route by brief' docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | **1 match** — verified 2026-09-20 (case-insensitive; the tree's casing differs from the plan's earlier lowercase rendering) |
| `list_open_workflow_type_issues` call sites | `grep -rn 'list_open_workflow_type_issues' scripts docs/workflow docs/testing --include='*.sh' --include='*.md'` (scoped to production scripts, protocols, integrations, and smoke runbooks; excludes `CHANGELOG.md`, `docs/specs/**` history and this plan's own self-references) | Definition (1) + 2 protocol snippets + 9 harness invocation lines in `test-workflow-lib-github-projects.sh` (630, 663, 684, 685, 701, 702, 715, 813, 816; plus a header comment at line 9) + 2 lines in the integration doc + 1 smoke runbook line — enumerated in Enforcement point 2; re-verified 2026-09-20 |
| Lane mapping for an unknown action | `stage_lane_for_next_action` in `workflow-batch-lanes.sh:25`–`:34` | `*)` fallback returns `review`; a new `NEXT_ACTION` name alone is **not** held — verified 2026-09-20 |
| Dispatch default | `workflow-batch-lanes.sh:374` | `dispatch="proposed"` unless a lane cap, exclusivity, or overlap rule fires — verified 2026-09-20 |
| HELD report category precondition | `report_category_for_item` in `workflow-batch-lanes.sh:50`–`:102` | Returns `held` only when `dispatch` is already `held` (`:91`), and the `ready-for-human-review` (`:81`) / in-review-status (`:74`) branches return `informational` first — verified 2026-09-20 |
| Key pass-through in batch plan | `workflow-batch-plan.sh:592`–`:603` (reader) and `:634`–`:649` (emitter) | Fixed `case` allow-list both ways; unlisted keys from `workflow-next-action.sh` are dropped — verified 2026-09-20 |
| Status reconciliation primitive | `workflow_status_order` in `workflow-lib.sh:1610` | `Backlog` → `0`, recognized statuses `Writing Spec`…`Released` → `> 0`, unrecognized → `-1` — verified 2026-09-20 |
| Stop-emission precedent | `emit_guardrails_unreadable_stop` in `run-bounded-prelude.sh:47` | Existing `stopCondition` / `affectedWorkItem` / `humanActionRequired` / `readOnlyGuarantee` shape to reuse — verified 2026-09-20 |
| Backlog items without a development folder | `workflow-batch-plan.sh` scan input; `workflow-batch-lanes.sh --scan` usage (`:12`) | Both take development folder paths, so folderless Backlog items are held by Protocol `90` text, not by these scripts — verified 2026-09-20 |
| Design assets | Spec folder + issue #1583 | No UI scope |

---

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Repository mode | `single_repo` (hub-only routing helpers inactive here) | `.ai-dev-workflow.yaml` | 2026-09-17, `3260570` | Batch items 1757, 1462, 1496, 1515, 1561, 1583, 1529; same-surface open PRs: none | `Verified` |
| Plan artifact base | `develop` | Orchestrator handoff | 2026-09-17 | Same bounded item list | `Verified` |
| Orthogonal batch items | No shared artifact or conflicting gate edits anticipated | Spec "Relationship to Other Work Items" | 2026-09-17 | Same batch list | `Verified` |

---

## Layer-by-Layer Changes

### Shared mode helper (documentation alias)

- [ ] Document in `workflow-lib.sh` (comment above `workflow_template_is_template`) that
  **framework mode** in specs/protocols means `workflow_template_is_template` returns `true`.
  Do not add a second detector or alias function unless a call site needs a shorter name
  (`workflow_framework_mode` wrapper is acceptable if it delegates to the same parser).

### Enforcement point 1 — backlog creation refusal

- [ ] In `scripts/development-workflow/add-backlog-item.sh`, after argument parsing and
  **before** `gh issue create`, when `--type Workflow` (case-normalize like tracker updates)
  and `workflow_template_is_template` is `true`: print a single actionable stderr message
  naming Workflow as invalid and Feature/Bug/Refactor as valid; exit `1`; create nothing
  (AC: Creating an item in framework mode).
- [ ] Mirror the same rule in the Linear `create` handoff path: when type would be Workflow
  and framework mode is true, exit `1` with the same message instead of emitting
  `TRACKER_ACTION_REQUIRED` (agents must not bypass via MCP).
- [ ] Do **not** add any force/confirm/yes flag or override env var that accepts Workflow in
  framework mode. Inventory at plan time: `add-backlog-item.sh` accepts only
  `--title/--body/--body-file/--label/--priority/--size/--type` (no `--force`, `--yes`,
  `--confirm`, `ALLOW_*`, `FORCE_*`, or `SKIP_*`). Implementation must keep that inventory
  empty for bypass paths.
- [ ] Extend `scripts/development-workflow/tests/test-add-backlog-item.sh` with template and
  consumer config fixtures proving:
  - Framework mode + `--type Workflow` → exit `1`, no `gh` create invocation.
  - **Negative bypass suite (named scenario `creation-refusal-no-bypass`)**: for every
    force/confirm/yes-style flag and override env form the script currently accepts (today:
    none — assert the inventory remains empty), refusal still holds; also invoke the Linear
    `create` handoff path with type Workflow in framework mode and assert exit `1` with no
    `TRACKER_ACTION_REQUIRED`. If a future PR adds a bypass flag/env, this scenario must fail
    until the flag is rejected for Workflow in framework mode.
  - **`framework-creation-valid-types-preserved`**: in framework mode, `--type Feature`,
    `--type Bug`, and `--type Refactor` each still create the item and set exactly the
    requested class (AC: "Re-running the same request with Feature, Bug, or Refactor
    succeeds and produces an item classified as asked"). The refusal must not leak into the
    valid classes.
  - **`consumer-creation-all-classes-unchanged`**: under consumer fixtures
    (`template.is_template` absent / `false` / unrecognized value), creation for **every**
    class — `Feature`, `Bug`, `Refactor`, `Workflow`, and no `--type` at all — matches the
    recorded pre-feature stdout/stderr byte-for-byte, with no added framework-mode warning or
    note (AC: Consumer repositories are unchanged).
  - Consumer config → existing success path unchanged.

### Enforcement point 2 — open "framework items" lookup

- [ ] **Do not change `list_open_workflow_type_issues`.** The lib primitive keeps Workflow-only
  filtering in **both** modes (normative note and evidence below). The framework-vs-consumer
  branch is implemented exactly once, in the wrapper `list_open_framework_items.sh`:
  - **Consumer** (`workflow_template_is_template` false): the wrapper delegates to the
    unchanged primitive, preserving today's Workflow-only filter and stderr warning behavior
    exactly (AC: Consumer repositories are unchanged).
  - **Framework mode**: the wrapper performs its own lookup — every open, non-terminal project
    item linked to an open repo issue, regardless of Type — **without** calling the primitive
    (AC: Open framework items stay discoverable).
- [ ] Add `scripts/development-workflow/list_open_framework_items.sh` as the **only**
  supported entrypoint for release/retrospective "open framework items" reads. Contract
  (**always**, on stdout, before exit — **all three keys in every mode**, including consumer):
  1. `FRAMEWORK_ITEMS_LOOKUP_STATUS=ok|empty|unavailable` — `empty` and `unavailable` are
     **framework-mode only**. Consumer mode always prints `STATUS=ok`.
  2. `FRAMEWORK_ITEMS_LOOKUP_REASON=<human-readable text>` — **always emitted**. Empty string
     when framework `STATUS=ok` (items present), framework `STATUS=empty`, or **any** consumer
     `STATUS=ok` including `JSON=[]` (no items and the consumer failure path that today yields
     `[]`). Non-empty only when framework `STATUS=unavailable` (reason text also mirrored on
     stderr when useful).
  3. `FRAMEWORK_ITEMS_JSON=<compact JSON array>` on the final line
  - **Exact key spellings — no glob shorthand.** The three published keys are
    `FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, and
    `FRAMEWORK_ITEMS_JSON`. The third has **no** `LOOKUP_` segment, so a
    `FRAMEWORK_ITEMS_LOOKUP_*` glob does **not** cover it. Wrapper code, protocol `05`/`06`
    snippets, harness assertions, and the smoke runbook must match these literals exactly —
    never a glob. (Repeated verbatim in Reversal (2) and in the smoke runbook, so a reader of
    any one surface gets the warning.)
  - **Exit codes**: framework `ok` / `empty` / `unavailable` → `0`; consumer `ok` → `0`.
    Status is carried only by `FRAMEWORK_ITEMS_LOOKUP_STATUS` so protocol callers under
    `set -e` can capture stdout, branch on STATUS, and continue the release/retrospective
    flow without the wrapper itself aborting the shell. Non-zero is reserved for wrapper
    usage errors (bad args), not for lookup outcomes.
  - **Consumer repositories**: always print all three keys; delegate body to today's
    `list_open_workflow_type_issues` behavior; always `STATUS=ok` and `REASON=` (empty), with
    Workflow-filtered JSON — `JSON=[]` when none **and** on today's failure path (`[]` +
    stderr warning). Do not emit `empty` or `unavailable` in consumer mode. Do not omit
    `FRAMEWORK_ITEMS_LOOKUP_REASON`.
  - **Framework mode**: `ok` when at least one open non-terminal item exists; `empty` when the
    lookup completed and the board has none; `unavailable` when the lookup could not be
    performed (non-empty `REASON`, preserve stderr detail). Never emit `empty` for a failed
    read.
  - **Normative location of the mode branch — the wrapper, not the lib primitive.**
    `list_open_workflow_type_issues` keeps **Workflow-only filtering in both modes** and is
    not changed by this item. The framework-vs-consumer branch lives **entirely** in
    `list_open_framework_items.sh`, which in framework mode performs its own all-open
    non-terminal lookup rather than delegating, and in consumer mode delegates to the
    unchanged primitive. Stated here, in the Decision Matrix, and in Reversal (1) — all
    three must agree.

    Rationale: this repository **is** framework mode, so flipping the lib primitive would
    silently change every existing direct caller. Enumerated call sites of
    `list_open_workflow_type_issues` as of 2026-09-20:

    | Call site | Kind |
    | --- | --- |
    | `scripts/development-workflow/workflow-lib.sh:3265` | Definition |
    | `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md:373` | Protocol snippet — repointed to the wrapper by this item |
    | `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md:124` | Protocol snippet — repointed to the wrapper by this item |
    | `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh:630,663,684,685,701,702,715,813,816` (nine invocations; line 9 is a header comment) | Harness — asserts Workflow-only filtering, unreadable-board, empty-board, and invalid-type behavior; **must keep passing unchanged** |
    | `docs/workflow/development-workflow/integrations/github-projects.md:203,212` | Documentation of the primitive |
    | `docs/testing/workflow/tracker-type-field-classification.smoke-test.md:60` | Smoke runbook |

    The nine harness invocations are the decisive evidence: they encode Workflow-only
    filtering today, and under the rejected reading they would silently begin exercising
    all-open-items semantics in this repo while still passing for the wrong reason.
- [ ] Update protocols `05` and `06` snippets to call `list_open_framework_items.sh` (not the
  raw lib function). For framework-mode `STATUS=unavailable`, each protocol must:
  1. **Continue** the release / retrospective flow (do not treat unavailable as a hard stop).
  2. State in the flow's own output that the lookup was not performed and why (`REASON`).
  3. **Not** record the dependent check as satisfied — release must not claim the
     open-script-bug review ran; retrospective must not claim a finding was matched against
     already-filed items — on the strength of an unavailable lookup.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` (or
  add `tests/test-framework-mode-type-routing.sh`) with mocked `gh` fixtures for framework
  vs consumer filter differences and framework-mode unavailable vs empty-board cases.
- [ ] Add **flow-level** named scenarios (protocol text + harness or smoke assertions) that
  fail if unmet:
  - `release-unavailable-continues-unsatisfied` (protocol `05`): fixture forces
    `STATUS=unavailable`; release flow proceeds past the lookup step; output contains
    unavailable/`REASON`; no "open framework bugs reviewed" / equivalent satisfied marker.
  - `retro-unavailable-continues-unsatisfied` (protocol `06`): same for retrospective
    finding de-duplication — flow continues; finding is not recorded as having no related
    item solely because lookup was unavailable.

### Enforcement point 3 — Backlog routing for Type `Workflow`

- [ ] Add `scripts/development-workflow/framework-mode-backlog-type-gate.sh` (**pinned name** —
  smoke and tests call this path; do not rename)
  that accepts `--issue`, `--status`, `--caller {single|scan}`, optional `--repo-root`, reads
  Type via `get_tracker_type_for_issue`, and prints stable key=value output.

  **Single status contract (one rule, stated once, used everywhere).** The gate fires on
  **exactly one** condition: framework mode **and** reconciled status `Backlog` **and** Type
  reads as `Workflow`. Status reconciliation reuses `workflow_status_order` in
  `workflow-lib.sh` (`Backlog` → `0`; every other recognized status → `> 0`; unrecognized →
  `-1`). Every other combination is `RESULT=pass`, which is what "unchanged from today" means
  for this gate. Nothing fails closed: the spec adds **no** acceptance criterion for an absent
  class or an unreadable status, and its matrix rows for those cases read "Unchanged from
  today" (spec Decision-Gate Consistency Matrix; Out of Scope item 7).

  | Mode | Type read | Reconciled status | Caller | Output |
  | --- | --- | --- | --- | --- |
  | Consumer | any (including unreadable) | any (including unreadable) | any | `RESULT=pass`, `REASON=consumer_mode` |
  | Framework | `Workflow` | `Backlog` (order `0`) | `single` | `RESULT=stop`, `STOP_CONDITION=missing_tracker_context`, `ITEM=#<issue>`, `REASON=misclassified_type`, `REASON_TEXT=<names the item and the re-classification>` |
  | Framework | `Workflow` | `Backlog` (order `0`) | `scan` | `RESULT=hold`, `ITEM=#<issue>`, `REASON=misclassified_type`, `REASON_TEXT=<same text>`, and **no** `STOP_CONDITION` key (a hold is not a stop) |
  | Framework | `Workflow` | any recognized non-`Backlog` status (order `> 0`) | any | `RESULT=pass`, `REASON=pipeline_already_chosen` |
  | Framework | `Workflow` | unrecognized / missing (order `-1`) | any | `RESULT=pass`, `REASON=status_unreconciled` |
  | Framework | `Feature` / `Bug` / `Refactor` | any | any | `RESULT=pass`, `REASON=type_routes_today` |
  | Framework | empty, unset, or unreadable | any | any | `RESULT=pass`, `REASON=type_absent_or_unreadable` |

  - The `REASON` values on `pass` rows are **informational only** — they exist so harness
    assertions can distinguish why the gate passed. No `pass` reason changes any caller's
    behavior, and no `pass` row may be turned into a stop or hold without a new spec AC.
  - **Naming the item is part of the stop contract.** Both `RESULT=stop` and `RESULT=hold`
    must emit `ITEM=#<issue>` and a `REASON_TEXT` that contains the issue number, the statement
    that the class is not valid in a framework-mode repository, and the re-classification that
    unblocks it (spec Operational Visibility; AC: "The stop names the item…"). A stop or hold
    whose text does not name the item is a test failure, not a cosmetic gap.
  - Model the single-item stop emission on the existing
    `emit_guardrails_unreadable_stop` in `run-bounded-prelude.sh:47` — same shape
    (`stopCondition` / `affectedWorkItem` / `humanActionRequired` / `readOnlyGuarantee`),
    with `affectedWorkItem` carrying `#<issue>`.
- [ ] Wire the gate into the **actual** classification paths (not `run-work-router.sh`, which
  only redirects `/run-work` scope):
  - **Single-item runs**: invoke from `scripts/development-workflow/run-bounded-prelude.sh`
    once the target issue and tracker status are known; on `RESULT=stop`, emit prelude output
    that maps to `missing_tracker_context` and abort before stage dispatch (Protocol `91`).
  - **Portfolio / batch proposal**: `NEXT_ACTION=hold-misclassified-type` on its own does
    **not** produce a held item. Verified against the tree at plan time:
    `workflow-batch-lanes.sh:32` maps any unrecognized action to the `review` lane via the
    `*)` fallback, `:374` initializes `dispatch="proposed"`, and
    `report_category_for_item` only returns `held` when `dispatch` is already `held`
    (`:91`). A new action name alone would therefore be **proposed for dispatch in the review
    lane** — the opposite of the spec's hold. The held outcome needs four concrete changes,
    all in this item's scope:
    1. `workflow-next-action.sh`: when framework mode is active, the folder's tracker Type
       reads `Workflow`, and its status reconciles to `Backlog`, emit
       `NEXT_ACTION=hold-misclassified-type` (**pinned**; do not rename) **plus**
       `MISCLASSIFIED_TYPE=Workflow` and `MISCLASSIFIED_TYPE_REASON=<REASON_TEXT naming the
       item>`, and exit `0` so the scan continues.
    2. `workflow-batch-plan.sh`: forward the two new keys. Its reader (`:592`–`:603`) is a
       fixed `case` allow-list and its emitter (`:634`–`:649`) re-prints only known keys, so
       **unforwarded keys are silently dropped** before lanes ever sees them. Use
       `MISCLASSIFIED_TYPE_REASON` (not `HOLD_REASON`) as the transport key: lanes echoes the
       whole input block before printing its own `HOLD_REASON` (`:542`, `:552`), so reusing
       that name would emit a duplicate key with two different values.
    3. `workflow-batch-lanes.sh`, lane assignment loop (`:355`–`:420`): read
       `MISCLASSIFIED_TYPE_REASON` alongside `NEXT_ACTION`, and **before** the
       `stage_lane = none` branch set `dispatch="held"` with
       `hold_reason="$MISCLASSIFIED_TYPE_REASON"` (fallback text if empty) when
       `next_action = hold-misclassified-type`, without consuming a stage-lane cap slot. Add
       an explicit `hold-misclassified-type)` arm to `stage_lane_for_next_action` (`:25`)
       returning `review` rather than relying on the `*)` fallback, and **not** `none` —
       `none` forces `dispatch="skip"`, which reports as `INFORMATIONAL`, not `HELD`.
    4. `workflow-batch-lanes.sh`, `report_category_for_item` (`:50`): add an early
       `hold-misclassified-type` → `held` arm placed **before** the
       `ready-for-human-review` label check (`:81`) and the in-review status check (`:74`),
       so no upstream branch can downgrade a misclassified item to `informational`. The
       existing `dispatch = held` output path then prints `HOLD_REASON` and `HELD_SUMMARY`
       (`:551`–`:556`) unchanged.
    **Required end state** (what the tests assert, not the action name): for that item
    `DISPATCH=held`, `REPORT_CATEGORY=held`, `REPORT_LABEL=HELD - not included in proposed
    batch`, and a non-empty `HOLD_REASON` naming the item and the re-classification — while
    the scan exits `0` and every sibling item keeps its own lane and dispatch.
    **Backlog items with no development folder** are outside this script pipeline entirely
    (`workflow-batch-plan.sh` scans development folders; `workflow-batch-lanes.sh --scan`
    takes development paths). For those, the hold is produced by Protocol `90`'s Backlog
    routing table and its `HELD - not included in proposed batch` report category, which the
    closed mirror list already requires this item to update — the script changes above cover
    the folder-bearing case, and the protocol text covers the rest. Both must be present.
  - **Mid-pipeline items**: the gate returns `pass` whenever the reconciled status is any
    recognized value other than `Backlog` (`workflow_status_order` > `0`) even if Type is
    still `Workflow` — `Writing Spec`, `Spec in Review`, `Spec Ready`, `Writing Plan`,
    `Plan in Review`, `Plan Ready`, `In Development`, `Development in Review`, `Merged`, and
    `Released` alike. There is no shorter privileged subset: the earlier `Spec Ready` /
    `Writing Plan` / `In Development` phrasing was an inconsistency and is not the contract.
    An unrecognized or missing status (`-1`) also passes, as `status_unreconciled` — unchanged
    from today, not a fail-closed stop. Only reconciled `Backlog` stops or holds.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` (or dedicated
  gate tests) with named scenario **`scan-misclassified-item-held`**: a Backlog + Workflow
  item yields `DISPATCH=held`, `REPORT_CATEGORY=held`, `REPORT_LABEL=HELD - not included in
  proposed batch`, and a `HOLD_REASON` naming the item, while a sibling Feature item in the
  same input keeps `DISPATCH=proposed` / `REPORT_CATEGORY=proposed_batch` and the scan exits
  `0`. Add **`scan-misclassified-not-informational`**: the same item still reports `held`
  when the block also carries a `ready-for-human-review` label or an in-review status, proving
  the early `report_category_for_item` arm is ordered ahead of those branches.
- [ ] **Named scenario `framework-post-backlog-statuses-pass`**: the gate returns `RESULT=pass`
  with `REASON=pipeline_already_chosen` for a Type `Workflow` item at **every** recognized
  non-Backlog status — `Writing Spec`, `Spec in Review`, `Spec Ready`, `Writing Plan`,
  `Plan in Review`, `Plan Ready`, `In Development`, `Development in Review`, `Merged`,
  `Released` — not only `Spec Ready`. A separate case asserts `RESULT=pass` with
  `REASON=status_unreconciled` for an unrecognized/missing status (no stop, no hold).
- [ ] **Consumer-fixture routing cases** (AC: Consumer repositories are unchanged) — named
  scenarios that fail if gate wiring alters consumer paths:
  - `consumer-prelude-workflow-unchanged`: under consumer config (`template.is_template` absent
    / false / unrecognized), `run-bounded-prelude.sh` for a Backlog + Workflow item produces
    the same routing outcome shape as today's pre-feature baseline (no stop/hold from this
    gate; infer-path / existing tables).
  - `consumer-next-action-workflow-unchanged`: under the same consumer fixtures,
    `workflow-next-action.sh` for Backlog + Workflow matches today's NEXT_ACTION / lane
    classification (not `hold-misclassified-type`). Diff evidence against recorded baseline
    stdout or golden fixtures is required — batch-lanes framework-mode HELD alone is not
    enough.
  - `consumer-routing-all-classes-unchanged`: under the same consumer fixtures, repeat the two
    scenarios above for **every** class — `Feature`, `Bug`, `Refactor`, `Workflow`, and no
    class at all — at Backlog, and assert each matches the recorded pre-feature baseline. The
    AC is "routing for every class, including Workflow, is identical", so Workflow-only
    evidence does not discharge it.
- [ ] **No-mutation on stop** (named scenario `stop-path-no-mutation`): when framework mode
  + Backlog + Workflow + caller `single` yields `RESULT=stop`, assert zero tracker mutations
  (no Type update, no Status update) and no branch create / checkout side effects from the
  stop path (mock or spy `gh` / git helpers). Gate output strings alone are insufficient.
- [ ] **Post-reclassification routing** (named scenario `reclassify-then-route`): after the
  fixture re-classes the same item to Feature, then Bug, then Refactor, re-run through
  `run-bounded-prelude.sh` / `workflow-next-action.sh` and assert each class routes exactly as
  that class routes today with no extra step from this feature. The Bug case **must** still
  pass through the existing Bug scope check before any fast-track path (assert the scope-check
  hook/function is invoked, or that the known scope-check failure fixture still blocks).

### Documentation and mirror surfaces (spec Mirror surfaces table)

**Closed mirror list** (every path that today restates tracker Type / Workflow creation or
Backlog→pipeline guidance for this feature — update all; do not leave an open-ended "and
others"):

| # | Path | Why it is in scope |
| --- | --- | --- |
| 1 | `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` | Classification step + inference table |
| 2 | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Single-item Backlog routing table |
| 3 | `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Portfolio Backlog routing table |
| 4 | `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` | Open-framework-item lookup |
| 5 | `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` | Lookup + create/classify |
| 6 | `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` | Create/classify with Workflow today |
| 7 | `docs/workflow/development-workflow/integrations/github-projects.md` | Type field table |
| 8 | `AGENTS.md` | Tracker Classification section |
| 9 | `CLAUDE.md` | Same Tracker Classification paragraph |
| 10 | `GEMINI.md` | Same Tracker Classification paragraph |
| 11 | `.cursor/agents/orchestrator.md` | Tracker Classification section |
| 12 | `.claude/agents/orchestrator.md` | Tracker Classification section |

Out of list (verified no duplicate Tracker Classification / "file as Workflow" paragraph at
plan time): `.cursor/agents/item-orchestrator.md`, `.agents/skills/**`, `.codex/skills/**`.
If implementation discovers a new duplicate, add it to this table in the same PR.

- [ ] Update every row in the closed mirror list per AC Guidance surfaces agree.
- [ ] Add a **grep-based check** (harness step in `test-framework-mode-type-routing.sh` or
  smoke Step 4) that **fails** if any surviving framework-mode Workflow instruction remains.
  Minimum failing patterns (adjust wording to match pre-change text, but the check must be
  red on today's tree and green after mirrors are updated):
  - `Use \`Workflow\` for` in `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
    `.cursor/agents/orchestrator.md`, `.claude/agents/orchestrator.md`
  - Exact pre-change assignment `update_tracker_type_best_effort "$ISSUE_NUMBER" "Workflow"`
    in protocols `06` / `06b` (do not match mere mentions of Type Workflow in refusal text)
  - Exact pre-change routing phrases `Route by the brief's concrete path` (protocol `91`) and
    `route by brief: full pipeline` (protocol `90`) on Backlog (Workflow) rows — not a generic
    `infer.*Workflow` pattern, which also matches "do not infer"
  Command sketch (implementation may wrap in a small script): fail if `rg` still matches those
  pre-change strings on the closed list after updates.
- [ ] Update `docs/testing/workflow/tracker-type-field-classification.smoke-test.md` only if
  its Workflow discovery steps contradict framework-mode semantics (otherwise leave unchanged
  and cover framework mode in the new runbook).

### Release documentation

- [ ] Implementation PR adds a `changelog.d/` fragment (do **not** edit `CHANGELOG.md`
  directly). Suggested fragment body:

  `- **Framework-mode work-item classification** (#1583): refuse Type Workflow on backlog creation in template repositories, stop or hold misclassified Backlog routing, and treat open-framework-item discovery as all open board items with distinguishable lookup-unavailable reporting in framework mode.`

---

## Classification Decision Matrix

This feature modifies **three** gates, and all three are enumerated here: the creation gate,
the routing gate, and the framework-item lookup. Rows mirror the spec's Decision-Gate
Consistency Matrix one-for-one; where the spec says "Unchanged from today", this plan says
`pass` / "no new behavior" and adds nothing.

### Gate inputs

| Input | Values | Source in this implementation |
| --- | --- | --- |
| Repository mode | framework / consumer | `workflow_template_is_template` in `workflow-lib.sh` (affirmative `template.is_template` only) |
| Item classification | `Feature` / `Bug` / `Refactor` / `Workflow` / empty, unset, or unreadable | `get_tracker_type_for_issue` (`workflow-lib.sh:2293`); for creation, the `--type` argument |
| Item stage | reconciled `Backlog` (`workflow_status_order` = `0`) / recognized non-Backlog (`> 0`) / unrecognized or missing (`-1`) | `workflow_status_order` (`workflow-lib.sh:1610`), the same reconciliation routing uses today |
| Routing caller | `single` (a named single-item run) / `scan` (portfolio proposal) | `--caller` on `framework-mode-backlog-type-gate.sh`; `run-bounded-prelude.sh` passes `single`, the scan path passes `scan` |
| Lookup result | completed with items / completed with no items / could not be performed | `list_open_framework_items.sh` — `FRAMEWORK_ITEMS_LOOKUP_STATUS` |

### Creation gate (`add-backlog-item.sh`, before `gh issue create`)

| Mode | Requested class | Outcome | Required next action |
| --- | --- | --- | --- |
| Framework | `Workflow` | Refused before creation: exit `1`, stderr names Workflow invalid and Feature/Bug/Refactor valid; nothing created, no board entry, no field set | Re-run with `Feature`, `Bug`, or `Refactor`. No flag, env var, or prompt accepts Workflow here (`creation-refusal-no-bypass`) |
| Framework | `Feature` / `Bug` / `Refactor` | Created as today, classified exactly as requested | None — unchanged (`framework-creation-valid-types-preserved`) |
| Framework | none requested | Created as today | None — unchanged; absent class is out of scope (spec Out of Scope 7) |
| Framework | `Workflow` via the Linear `create` handoff | Same refusal: exit `1`, same message, **no** `TRACKER_ACTION_REQUIRED` emitted | Re-run with a valid class; the MCP handoff is not a bypass |
| Consumer | any class, or none | Created as today, byte-identical output | None — unchanged (`consumer-creation-all-classes-unchanged`) |

### Routing gate (`framework-mode-backlog-type-gate.sh` and its two callers)

| Mode | Classification | Stage | Caller | Outcome | Required next action |
| --- | --- | --- | --- | --- | --- |
| Framework | `Feature` / `Bug` / `Refactor` | `Backlog` | any | `pass` (`type_routes_today`) | Existing pipelines; a Bug still goes through the existing scope check first |
| Framework | `Workflow` | `Backlog` | `single` | `stop`, `STOP_CONDITION=missing_tracker_context` | Report the stop naming `#<issue>` and the re-classification; start no pipeline; mutate nothing (`stop-path-no-mutation`) |
| Framework | `Workflow` | `Backlog` | `scan` | `hold` (no `STOP_CONDITION`) | That item only: `DISPATCH=held`, `REPORT_CATEGORY=held`, `HOLD_REASON` naming the item. Scan continues, exits `0`, and still proposes every other valid item |
| Framework | `Workflow` | any recognized non-Backlog status (`Writing Spec` … `Released`) | any | `pass` (`pipeline_already_chosen`) | Continue the pipeline the item already started. The gate stops work being **started** on a mis-typed item; re-classification here is tracker hygiene, not a reason to halt in-flight work |
| Framework | `Workflow` | unrecognized or missing status (`-1`) | any | `pass` (`status_unreconciled`) | None — unchanged from today. The spec adds no AC for an unreconcilable status, so this does not fail closed |
| Framework | empty, unset, or unreadable | any | any | `pass` (`type_absent_or_unreadable`) | None — unchanged from today (spec matrix "Framework / Unset / Unchanged from today"; Out of Scope 7) |
| Consumer | any class, including `Workflow` | any | any | `pass` (`consumer_mode`) | None — existing routing tables, including infer-the-path for Workflow (`consumer-routing-all-classes-unchanged`) |
| Either | any class | already on a pipeline | any | Not re-evaluated | Unchanged — the item continues on the pipeline it started |

### Framework-item lookup gate (`list_open_framework_items.sh`)

| Mode | Lookup result | `STATUS` / `REASON` / `JSON` | Required next action in protocols `05` / `06` |
| --- | --- | --- | --- |
| Framework | Completed; at least one open item on the board | `STATUS=ok`, `REASON=` (empty), `JSON=[…]` — every open non-terminal item, whatever its Type | Review the list as today |
| Framework | Completed; board has no open items | `STATUS=empty`, `REASON=` (empty), `JSON=[]` | Legitimate empty answer; the flow continues and may record the review as performed against an empty board |
| Framework | Could not be performed (tracker unreachable, board or Type field unreadable, tracker does not support the lookup) | `STATUS=unavailable`, `REASON=<non-empty text>`, `JSON=[]` | **Continue** the flow; state in its own output that the lookup was not performed and why; do **not** record the open-script-bug review or the finding de-duplication as satisfied (`release-unavailable-continues-unsatisfied`, `retro-unavailable-continues-unsatisfied`) |
| Consumer | Completed | `STATUS=ok`, `REASON=` (empty), `JSON=` Workflow-filtered items | Unchanged |
| Consumer | Could not be performed | `STATUS=ok`, `REASON=` (empty), `JSON=[]` plus today's stderr warning — unchanged; consumer mode never emits `empty` or `unavailable` | Unchanged — out of scope for this feature (spec: consumer failure behavior is not touched) |
| Any | Wrapper usage error (bad arguments) | Non-zero exit; not a lookup outcome | Fix the call site. Lookup outcomes always exit `0` so `set -e` callers can branch on `STATUS` |

### Mirror surfaces and examples

Mirror surfaces for all three gates are the closed 12-path list in "Documentation and mirror
surfaces" above, which covers every row of the spec's Mirror surfaces table (creation protocol
`00`; routing tables `90` / `91`; scan report categories in `90`; lookup flows `05` / `06`;
create-and-classify flows `06` / `06b`; the tracker integration guide; and the five
agent-guidance copies). The spec's worked examples map row-for-row onto the tables above and
are exercised by the named scenarios in Testing Strategy — creation refusal and retry, the
single-item stop, the ten-item scan that holds three and still proposes the rest, the
unavailable release lookup, the consumer Workflow creation and routing, and the mid-pipeline
Workflow item that continues.

---

## Testing Strategy

**Primary automated suites**:

- `scripts/development-workflow/tests/test-add-backlog-item.sh`
- `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` and/or
  `scripts/development-workflow/tests/test-framework-mode-type-routing.sh`
- `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` — the HELD end state
  (`DISPATCH=held` / `REPORT_CATEGORY=held`) for a `hold-misclassified-type` block, including
  the `MISCLASSIFIED_TYPE_REASON` forwarded by `workflow-batch-plan.sh`
- `scripts/development-workflow/tests/test-run-bounded-prelude.sh` — the single-item stop under
  `missing_tracker_context` and the consumer-fixture no-op

**Key scenarios** (each must fail if unmet — named where noted):

1. Framework mode refuses `--type Workflow` before issue creation with actionable message.
2. **`creation-refusal-no-bypass`**: refusal persists for every force/confirm/env bypass form
   accepted by `add-backlog-item.sh` (inventory empty today) and for the Linear `create`
   handoff path.
3. **`framework-creation-valid-types-preserved`**: framework-mode creation with `Feature`,
   `Bug`, and `Refactor` still succeeds and sets exactly the requested class.
4. **`consumer-creation-all-classes-unchanged`**: consumer fixtures create every class —
   `Feature`, `Bug`, `Refactor`, `Workflow`, and no `--type` — with output identical to the
   pre-feature baseline (no framework-mode warning or note).
5. Framework-mode lookup returns mixed-type open items; consumer returns Workflow-only, via
   the unchanged `list_open_workflow_type_issues` primitive.
6. Framework mode: `list_open_framework_items.sh` emits all three keys
   (`FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, `FRAMEWORK_ITEMS_JSON` —
   exact literals, no glob) and distinguishes unavailable vs empty vs populated; exit codes
   match the contract (`0` for all three statuses). Consumer mode also emits all three keys
   (`REASON` may be empty).
7. **`release-unavailable-continues-unsatisfied`** / **`retro-unavailable-continues-unsatisfied`**:
   unavailable lookup does not stop protocol `05` / `06` and is not recorded as satisfied.
8. Gate: Backlog + Workflow stops the single runner, and the stop text names the item; the
   `scan` caller yields a hold, not a global stop.
9. **`scan-misclassified-item-held`** / **`scan-misclassified-not-informational`**: the scan
   item reaches `DISPATCH=held` + `REPORT_CATEGORY=held` with a naming `HOLD_REASON`, a
   sibling Feature stays `proposed_batch`, and label/status branches cannot downgrade the held
   item to informational.
10. **`framework-post-backlog-statuses-pass`**: Type Workflow passes at every recognized
    non-Backlog status (`Writing Spec` through `Released`), not only `Spec Ready`; an
    unrecognized status also passes as `status_unreconciled`.
11. **`stop-path-no-mutation`**: stop path performs zero tracker/branch mutation.
12. **`reclassify-then-route`**: post-reclassification Feature/Bug/Refactor routing matches
    today, including Bug scope check.
13. **`consumer-prelude-workflow-unchanged`** / **`consumer-next-action-workflow-unchanged`** /
    **`consumer-routing-all-classes-unchanged`**: consumer fixtures for
    `run-bounded-prelude.sh` and `workflow-next-action.sh` keep pre-feature Backlog routing for
    every class, including Workflow.
14. **Guidance mirror grep**: closed mirror list updated; grep check fails on surviving
    framework-mode Workflow instructions. Each grep command is a `! rg …` shell command whose
    **non-zero exit is the failure signal** — a surviving match makes `rg` exit `0`, the `!`
    inverts it to non-zero, and the step fails. Under `set -e` in a harness wrapper, that
    non-zero exit aborts the suite, which is the intended behavior.

**Quality checks**: ShellCheck on touched scripts; `workflow-shell-guard-lint.py`;
markdown lint on plan/spec/runbook/protocol edits.

**Smoke test runbook**: `docs/testing/workflow/1583-template-mode-type-routing.smoke-test.md`

---

## Implementation Order

1. Add failing regression tests for creation refusal (incl. no-bypass and the valid-class and
   consumer-class scenarios), the wrapper's three-status output, flow-level unavailable, and
   the backlog gate (incl. no-mutation, reclassify, post-Backlog statuses, consumer callers).
2. Implement `add-backlog-item.sh` refusal (both the direct and Linear `create` paths) and the
   `workflow-lib.sh` comment documenting `workflow_template_is_template` as framework mode.
   `list_open_workflow_type_issues` is **not** touched.
3. Create `scripts/development-workflow/list_open_framework_items.sh` with the full
   `FRAMEWORK_ITEMS_LOOKUP_STATUS` / `FRAMEWORK_ITEMS_LOOKUP_REASON` / `FRAMEWORK_ITEMS_JSON`
   contract — the wrapper must exist before anything emits or consumes those keys.
4. Repoint protocols `05` / `06` snippets at the wrapper and give each its framework-mode
   `unavailable` handling (continue, report, do not mark satisfied).
5. Add `framework-mode-backlog-type-gate.sh` and wire it into `run-bounded-prelude.sh`
   (`single`) and `workflow-next-action.sh` (`scan`), then land the paired
   `workflow-batch-plan.sh` key forwarding and the `workflow-batch-lanes.sh` lane, dispatch,
   and report-category changes that actually produce `DISPATCH=held`.
6. Update every path on the closed mirror list; land the grep-based guidance check.
7. Run full touched test suites + smoke runbook; add `changelog.d` fragment.

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Consumer lookup/regression drift | Guard consumer branches with copied fixtures from current green tests before editing shared function; named consumer prelude/next-action scenarios |
| Agents still infer Workflow path from stale skills | Closed mirror list + failing grep check in the same PR |
| `[]` still read as "no items" in release/retrospective | Explicit STATUS lines + flow-level unsatisfied scenarios for protocols 05/06 |
| Mid-pipeline Workflow items blocked | Gate must key off reconciled stage, not Type alone; `framework-post-backlog-statuses-pass` covers every recognized non-Backlog status |
| Bypass flag added later | `creation-refusal-no-bypass` inventory assertion |
| Misclassified scan item silently dispatched | A new `NEXT_ACTION` name alone lands in the review lane as `proposed`; the paired `workflow-batch-plan.sh` forwarding + `workflow-batch-lanes.sh` dispatch/report changes are mandatory, and `scan-misclassified-item-held` asserts the end state (`DISPATCH=held`), not the action name |
| Gate over-reach beyond the spec | Only framework mode + reconciled `Backlog` + Type `Workflow` stops or holds; absent/unreadable Type and unreconcilable status `pass`, matching the spec's "Unchanged from today" rows. Any new fail-closed case requires a new spec AC first |

---

## Reversal and Rollback

Four published behavior changes need an explicit undo story — the two lookup contracts, plus
the creation refusal and the routing gate, both of which change what an existing command does
for an existing input:

### (1) Framework-item lookup semantics — primitive unchanged, mode branch in the wrapper

- **What changes**: Nothing in the lib primitive. `list_open_workflow_type_issues` keeps
  Workflow-only filtering in **both** modes; the framework-mode all-open-items lookup lives in
  `list_open_framework_items.sh`. Direct callers of the primitive are therefore unaffected by
  this item, which is why the branch is placed in the wrapper — see the normative location
  note in Enforcement point 2.
- **Rollback**: Revert-safe, and narrower than a filter flip would be. Because the primitive
  never changes, reverting removes only the wrapper's framework-mode branch; no direct caller
  silently changes semantics in either direction. Protocols `05`/`06` that switched to
  `list_open_framework_items.sh` must be reverted in the **same** rollback (or re-pointed to the
  lib function) so release/retrospective do not keep expecting all-open-items semantics after
  the wrapper's branch is removed. Downstream syncs of this template pick up the revert on the next
  `/sync-template` of `scripts/development-workflow/**` and `docs/workflow/**`.

### (2) `FRAMEWORK_ITEMS_LOOKUP_STATUS` / `FRAMEWORK_ITEMS_LOOKUP_REASON` / `FRAMEWORK_ITEMS_JSON` stdout contract

> **Exact key spellings — no glob shorthand.** The three published keys are
> `FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, and
> `FRAMEWORK_ITEMS_JSON`. Note the third has **no** `LOOKUP_` segment, so a
> `FRAMEWORK_ITEMS_LOOKUP_*` glob does not cover it. Protocol `05`/`06` snippets parse these
> literals, so every section of this plan, the smoke runbook, and the protocol snippets must
> use these exact spellings.

- **What changes**: `list_open_framework_items.sh` becomes the only supported entrypoint for
  release/retrospective open-framework-item reads, publishing
  `FRAMEWORK_ITEMS_LOOKUP_STATUS` / `_REASON` / `_JSON` on every invocation.
- **Rollback**: **Not independently revertible** once protocols `05`/`06` (and any synced
  downstream copies) parse those keys. Rolling back the wrapper without a matching protocol
  revert leaves callers looking for keys that no longer exist (or re-reading raw `[]` as empty).
  Stated one-way coupling: undo requires **paired** revert of (a) the wrapper + tests and
  (b) protocol snippets that call it. Until that paired revert, the stdout contract is the
  published interface. Consumer repositories that never adopt the wrapper keep using
  `list_open_workflow_type_issues` and are unaffected by removing the wrapper alone.

### (3) Backlog-creation refusal in framework mode

- **What changes**: `add-backlog-item.sh` (and its Linear `create` handoff) gains a
  pre-create refusal: in framework mode, `--type Workflow` exits `1` and creates nothing. An
  invocation that succeeded before this item now fails, so the change is caller-visible even
  though it adds no new flag or key.
- **Rollback**: Independently revertible and safe in both directions. Reverting restores the
  pre-feature behavior for that one input; no other class is affected, and consumer
  repositories never entered the branch at all. Because the refusal happens **before**
  creation, a revert leaves no half-created items and no tracker state to reconcile — the
  worst case is that Workflow-classed items can be filed again in this repository.
  The mirror-surface updates (protocol `00`, the agent-guidance copies, the tracker
  integration guide) should be reverted in the same rollback so guidance does not keep
  describing a refusal that no longer happens; guidance left stale is a documentation defect,
  not a behavior break.

### (4) Backlog routing gate (stop / hold) in framework mode

- **What changes**: `framework-mode-backlog-type-gate.sh` is new, and three existing surfaces
  begin consulting it: `run-bounded-prelude.sh` (single-item stop under
  `missing_tracker_context`), `workflow-next-action.sh` (new `hold-misclassified-type`
  action plus `MISCLASSIFIED_TYPE` / `MISCLASSIFIED_TYPE_REASON` keys), and the paired
  `workflow-batch-plan.sh` forwarding + `workflow-batch-lanes.sh` dispatch/report handling
  that turns that action into `DISPATCH=held`. A framework-mode Backlog + Workflow run that
  previously started a pipeline now stops.
- **Rollback**: **Paired, not independent.** Reverting the gate alone leaves
  `workflow-next-action.sh` emitting an action that lanes no longer holds — which would put
  misclassified items back into the proposed batch **in the review lane**, a worse state than
  either endpoint. Undo requires reverting, in one change: (a) the gate script and its tests,
  (b) the `run-bounded-prelude.sh` call site, (c) the `workflow-next-action.sh` emission,
  (d) the `workflow-batch-plan.sh` key forwarding, and (e) the `workflow-batch-lanes.sh`
  lane/dispatch/report arms. Protocol `90`/`91` routing-table text reverts with them.
  No durable state is involved: the stop and hold paths are asserted to make zero tracker or
  branch mutations (`stop-path-no-mutation`), so a revert needs no data repair — items simply
  become startable again under their old class.

No durable tracker or board state is written by any of these four changes; rollback is
repository-content only (plus downstream sync).

---

## Document Quality Gate

| Surface | Applicability | Plan coverage |
| --- | --- | --- |
| Database / migrations | Not applicable | No persistent schema |
| External HTTP APIs | Not applicable | GitHub CLI only (existing) |
| Frontend / UI | Not applicable | Docs + shell only |
| Infrastructure / config | Not applicable | Reuses `template.is_template` |
| Parser-risk text grammars | Not applicable | No new free-text parser |
| Concurrent event sources | Not applicable | Synchronous shell helpers |
| Complex workflow decision gate | **Applicable** | Classification Decision Matrix: gate inputs, plus separate tables for the **creation** gate, the **routing** gate, and the **lookup** gate, each with every allowed outcome and its required next action; mirror surfaces and examples mapped at the end of that section |
| Cross-cutting operational assumptions | **Applicable** | Verified table (batch #1757, #1462, #1496, #1515, #1561, #1583, #1529) |
| Agent/skill mirrors | **Applicable** | Closed mirror list (12 paths) + failing grep check |
| Published-contract reversal | **Applicable** | Reversal and Rollback section: (1) lookup primitive/wrapper split, (2) stdout key contract, (3) creation refusal, (4) routing gate paired revert |

Decision-gate matrix rows match the spec's allowed outcomes and required next actions, row for
row, including the "Unchanged from today" rows (absent/unreadable Type, unreconcilable status,
consumer lookup failure) which this plan implements as `pass` rather than as new behavior.
Mirror surfaces are the closed list above (includes `06b`,
`AGENTS.md`/`CLAUDE.md`/`GEMINI.md`, and both orchestrator agent stubs).

**Cross-section consistency self-check** (items appearing more than once, checked after the
final edit pass):

| Repeated item | Single agreed value |
| --- | --- |
| Lookup primitive | `list_open_workflow_type_issues` — unchanged, Workflow-only in both modes (Enforcement point 2, Decision Matrix, Reversal (1), Implementation Order) |
| Mode branch location | `list_open_framework_items.sh` only |
| Published lookup keys | `FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, `FRAMEWORK_ITEMS_JSON` (no `LOOKUP_` in the third; no globs) |
| Gate script name | `framework-mode-backlog-type-gate.sh` |
| Scan action name | `hold-misclassified-type` (transport keys `MISCLASSIFIED_TYPE`, `MISCLASSIFIED_TYPE_REASON`) |
| Stop condition | `missing_tracker_context`, single-item caller only; a `scan` hold emits no stop condition |
| Status contract | stop/hold only at reconciled `Backlog`; every other recognized or unrecognized status is `pass` |
| Absent / unreadable Type | `pass` — never a fail-closed stop |

---

## Residual Verification Strategy

Before the implementation PR reaches `ready-for-human-review`, every matrix row above must map
to a named passing test or smoke runbook step (including the named scenarios in Key scenarios).
Consumer-mode behavior requires diff evidence that:

1. Existing Workflow **discovery** tests are unchanged (or byte-identical outputs) under
   consumer fixtures, **and**
2. Consumer **routing** through `run-bounded-prelude.sh` and `workflow-next-action.sh` matches
   the recorded pre-feature baseline for Backlog at **every** class — Feature, Bug, Refactor,
   Workflow, and none (scenarios `consumer-prelude-workflow-unchanged` /
   `consumer-next-action-workflow-unchanged` / `consumer-routing-all-classes-unchanged`), and
3. Consumer **creation** output is byte-identical for every class
   (`consumer-creation-all-classes-unchanged`).

**Residual sweep evidence.** Two enumerations in this plan claim completeness and must be
re-verified on the implementation branch head before readiness, with the command and its
output pasted into the PR:

- The closed mirror list (12 paths): re-run the guidance greps in Step 4 of the smoke runbook.
  Zero matches is the evidence; any new duplicate found must be added to the table in the same
  PR rather than left out of the list.
- The bypass inventory for `add-backlog-item.sh`: re-run the flag/env inventory assertion in
  `creation-refusal-no-bypass`. An empty inventory is the evidence; a non-empty one must be
  rejected for Workflow in framework mode before the scenario can pass.
