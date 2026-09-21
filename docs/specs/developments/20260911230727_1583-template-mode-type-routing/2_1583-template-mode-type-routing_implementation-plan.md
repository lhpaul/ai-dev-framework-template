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

## Decisions and Change Log

| Date | Decision | Effect | Approval state |
| --- | --- | --- | --- |
| 2026-09-21 | **Explicit-list and epic scopes cut from this item.** Only the two routing callers the spec names are implemented: the single-item runner stop and the portfolio-scan hold | `--items` / `/run-items` and `--epic` / `/run-epic` keep today's behavior; deferred to `#1779` | Approved by the human on 2026-09-21; recorded in Scope and Out of Scope below |
| 2026-09-21 | **Spec amended** — `1_1583-template-mode-type-routing_specs.md` reworded so a framework-mode `unavailable` lookup covers only the enumerated read failures, and states that the framework-mode lookup does not read Type, so the classification field's readability is not an input | Removes the contradiction between the spec's unavailable causes and a lookup that ignores Type; the plan already matched the amended wording | **Stage exception granted by the human on 2026-09-21** (REVIEW.md normally restricts an implementation-plan branch to the plan and its smoke runbook): the spec amendments — the `unavailable` wording and the explicit-list/epic caller boundary (spec Out of Scope item 8, tracked in #1779) — ship on this plan branch, and approval of this PR is their re-approval. The spec change ships on this plan branch and must be re-reviewed before the implementation PR proceeds |
| 2026-09-21 | **Issue-list response validation added** as a distinct lookup failure (`issue_list_blank_or_malformed`) | A `gh issue list` that exits `0` with blank or malformed JSON is `unavailable`, never `empty` and never `item_list_unparseable`; closed cause list grows to nine | Approved by the human on 2026-09-21 |
| 2026-09-21 | **Branch/PR evidence added as a third gate input.** Equating "no development folder" with "no work" was false for fast-track items: `workflow-next-action.sh:601` states that `fix/` and `hotfix/` branches use no development folder, so an item with an open fix branch or a merged hotfix PR is already on a pipeline and has no folder | The gate holds only when the folder artifacts **and** the branch/PR evidence are both empty. Evidence comes from sources that already match fix and hotfix heads — `pullRequests` in the scope JSON for the single-item path, `open_implementation_pr_metadata` for the scan — and unreadable evidence passes as `branch_evidence_unavailable` with `MISCLASSIFIED_TYPE_CHECK=deferred`. New scenarios: `stale-backlog-active-fix-branch-continues`, `stale-backlog-merged-fix-pr-continues`, `backlog-no-folder-no-branch-stops`, `branch-evidence-unavailable-defers` | Reviewer finding, 2026-09-21 |
| 2026-09-21 | **Gate input corrected to the effective stage.** The gate had keyed off the raw tracker status, so a stale `Backlog` on an item that already had a spec or plan would have been held — contradicting the spec's "reconciled against work already completed for it" and its rule that items already on a pipeline are not re-evaluated | The gate now requires reconciled `Backlog` **and** an empty artifact stage from `workflow-next-action.sh`; a stale Backlog with artifacts passes as `stale_backlog_reconciled`. This **reverses** the earlier scenario `scan-uses-tracker-status-not-artifacts`, which asserted that a tracker-Backlog item with a merged spec is held; it is replaced by `scan-backlog-no-artifacts-held` and `scan-stale-backlog-with-artifacts-continues`. The earlier finding that prompted it still holds in its valid half — artifacts alone cannot identify a Backlog item, so the tracker read stays a required input. The scan's gate call also moves **after** the next-action call, since that call supplies the artifact stage | Reviewer finding, 2026-09-21 |

---

## Scope and Out of Scope

**In scope — the two routing callers the spec defines:**

- The **single-item runner stop**: the bounded prelude's `item` scope, using the `status` and
  `type` the scope resolver already puts in the scope JSON.
- The **portfolio-scan hold**: the `workflow-batch-plan.sh` → `workflow-batch-lanes.sh` path,
  ending in `DISPATCH=held` for that item while the scan continues.
- Backlog-creation refusal, the framework-item lookup contract, and the mirror surfaces.

**Out of scope — explicit-list and epic scopes:**

- **Explicit-list (`--items`, `/run-items`) and epic (`--epic`, `/run-epic`) scopes are not
  changed by this item; deferred to backlog issue `#1779`.** Those runs keep
  today's behavior exactly: no gate call, no hold key, no new stop. The spec's routing
  requirements name a single-item run and a portfolio scan, and giving a multi-item run a
  per-item hold would need a disposition `run-epic-scope-resolver.sh` does not have today —
  its `ambiguous` group makes the whole resolution terminal (`:730`–`:732`, `:983`–`:990`).
  That design belongs to its own item rather than being improvised here.
- Bulk re-classification of existing items (#1584), and everything in the spec's own Out of
  Scope list.

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
| Mirror-check anchor literal 5 | `grep -c 'with Type `Workflow`' docs/testing/workflow/retrospective-protocol.smoke-test.md` | **1 match** (`:88`) — verified 2026-09-20 |
| Mirror-check anchor literal 6 | `grep -c 'project Type will be set to `Workflow`' docs/testing/workflow/tracker-type-field-classification.smoke-test.md` | **1 match** (`:32`) — verified 2026-09-20 |
| Instructing-surface sweep | The three commands recorded under the closed mirror list (pattern sweep over `*.md`/`*.sh`/`*.yaml`/`*.yml`, the `docs/testing/` classification sweep, and a direct `grep -n 'Workflow' scripts/development-workflow/add-backlog-item.sh` — the last is needed because that file's help text splits "Type" and "Workflow" across lines `:40`–`:41`) | Yielded closed-list rows 13–15 (`retrospective-protocol.smoke-test.md:88`, `tracker-type-field-classification.smoke-test.md:32`, `add-backlog-item.sh:41`). Remaining hits are `workflow-lib.sh`'s unchanged primitive, test fixtures, `CHANGELOG.md`, and historical specs/plans — excluded with reasons in the out-of-list table — verified 2026-09-20 |
| Runner-guidance symlinks | `ls -l AGENTS.md CLAUDE.md GEMINI.md` | `CLAUDE.md` and `GEMINI.md` are symlinks to `AGENTS.md`; one edit updates all three, and recursive greps report only `AGENTS.md` — verified 2026-09-20 |
| `list_open_workflow_type_issues` call sites | `grep -rn 'list_open_workflow_type_issues' scripts docs/workflow docs/testing --include='*.sh' --include='*.md'` (scoped to production scripts, protocols, integrations, and smoke runbooks; excludes `CHANGELOG.md`, `docs/specs/**` history and this plan's own self-references) | Definition (2 lines: header comment 3245 + function 3265) + 2 protocol snippets + 9 harness invocation lines in `test-workflow-lib-github-projects.sh` (630, 663, 684, 685, 701, 702, 715, 813, 816; plus a header comment at line 9) + 2 lines in the integration doc + 1 smoke runbook line — enumerated in Enforcement point 2; re-verified 2026-09-20 |
| Lane mapping for an unknown action | `stage_lane_for_next_action` in `workflow-batch-lanes.sh:25`–`:34` | `*)` fallback returns `review`; a new `NEXT_ACTION` name alone is **not** held — verified 2026-09-20 |
| Dispatch default | `workflow-batch-lanes.sh:374` | `dispatch="proposed"` unless a lane cap, exclusivity, or overlap rule fires — verified 2026-09-20 |
| HELD report category precondition | `report_category_for_item` in `workflow-batch-lanes.sh:50`–`:102` | Returns `held` only when `dispatch` is already `held` (`:91`), and the `ready-for-human-review` (`:81`) / in-review-status (`:74`) branches return `informational` first — verified 2026-09-20 |
| Key pass-through in batch plan | `workflow-batch-plan.sh:592`–`:603` (reader) and `:634`–`:649` (emitter) | Fixed `case` allow-list both ways; unlisted keys from `workflow-next-action.sh` are dropped — which is why the scan hold is emitted by batch-plan itself rather than forwarded — verified 2026-09-20 |
| `workflow-next-action.sh` status source | `:677`–`:696` (status derivation), `:670`–`:676` (comment), `:43`–`:77` (arg parser) | Status is derived from spec/plan files and branch state only; possible values are `Spec Ready`, `Plan Ready`, `In Development`, `Done`, `Unknown` — **never `Backlog`**. No `--issue` / `--status` option exists, and the script's own comment forbids using its STATUS to override the tracker — verified 2026-09-20 |
| Authoritative tracker status in the scan | `workflow-batch-plan.sh:516` (issue number), `:542` (`get_tracker_status_for_issue`), `:554`–`:557` (terminal skip), `:569`–`:571` (next-action call), `:639` (emitted STATUS) | Batch-plan reads the tracker status but uses it only for the terminal skip and Linear deferral; it does not pass it to next-action and emits next-action's artifact-derived STATUS instead — the gap this item closes — verified 2026-09-20 |
| Tracker status failure modes | `get_tracker_status_for_issue` in `workflow-lib.sh:2250`–`:2285` | Returns empty string with exit `0` for Linear deferral, missing project config, missing project item, and unparseable JSON; never non-zero, so callers cannot distinguish them — verified 2026-09-20 |
| Tracker Type failure modes | `get_tracker_type_for_issue` in `workflow-lib.sh:2293`–`:2325` | Empty string for non-`github_projects` providers, missing project config, or missing item; **non-zero** only when item JSON exists but Type cannot be parsed — verified 2026-09-20 |
| Authoritative status + Type on the single-item path | `run-epic-scope-resolver.sh:678` (status) and `:687` (Type), which `run-item-scope-resolver.sh` delegates to; consumed via the scope JSON `run-bounded-prelude.sh` writes at `:460`–`:481` | Both values are already resolved and carried in the scope JSON, so the single-item gate needs no additional tracker call; `:687`–`:689` hard-fails on an unparseable Type before the gate is reached — verified 2026-09-20 |
| Other prelude scope modes exist | `run-bounded-prelude.sh:404`–`:411` (mode selection) and `:460`–`:481` (resolver dispatch) | The prelude also resolves `items` (`--items`) and `epic` (`--epic`). This item wires **only** the `item` scope; the other two are recorded here so the boundary is deliberate rather than an oversight — verified 2026-09-20 |
| Why multi-item disposition is deferred | `run-epic-scope-resolver.sh:730`–`:732` (`ambiguous` for missing/unrecognized status) and `:983`–`:990` (non-empty `ambiguous` → terminal `missing_tracker_context`) | A single `ambiguous` member already makes the **whole** epic/items resolution terminal, so a per-item hold there needs a new disposition the resolver does not have today. Designing it is its own item (`#1779`), not a side effect of this one — verified 2026-09-20 |
| Linear deferred scope placeholder | `run-item-scope-resolver.sh:375`, `:396`–`:397` | Emits `trackerReadDeferred: true` with a literal `status: "Backlog"` and `type: ""`; the gate must key off `trackerReadDeferred`, not the placeholder — verified 2026-09-20 |
| Cost of reading Status and Type | `workflow_github_project_item_for_issue` (`workflow-lib.sh:1781`) selects both fields, but `get_tracker_status_for_issue` (`:2250`) and `get_tracker_type_for_issue` (`:2293`) call it separately; caches exist only for the project id (`:1641`–`:1643`), field metadata (`:1644`–`:1648`), and named fields (`:1651`–`:1652`) | **No item-level cache**, so two reads of the same item are two GraphQL requests. The scan path therefore costs one extra request per scanned non-terminal folder in framework mode; no "single read" guarantee is claimed — verified 2026-09-20 |
| How routing reconciles a stale tracker status today | `workflow-batch-plan.sh:542` (tracker read, used only for the terminal skip) vs `:639` (emits next-action's artifact-derived `STATUS`); `workflow-next-action.sh:677`–`:696` | The scan already lets artifacts override a stale tracker status in its own report — the mechanism this item reuses for the effective stage instead of inventing one — verified 2026-09-21 |
| Artifact-absence signal | `workflow-next-action.sh:559`–`:562` (folder missing) and `:578`–`:581` (neither spec nor plan) both `exit 66`; `workflow-batch-plan.sh:571`–`:582` treats that as "no merged spec/plan PR yet" and emits an abbreviated block | A non-zero next-action is the existing, verifiable "no folder artifacts" signal, so the gate needs no new artifact detector — verified 2026-09-21 |
| Fast-track work has no development folder | `workflow-next-action.sh:601` ("fix/ and hotfix/ don't use development folders"); its branch and merged-PR probes are scoped to the `feature`/`refactor` `dev_prefix` (`:596`–`:660`) | A missing folder therefore does **not** mean an unstarted item: an open `fix/` branch or a merged `hotfix/` PR is a pipeline already chosen. Branch/PR evidence is required as a third gate input — verified 2026-09-21 |
| Branch/PR evidence, single-item path | `run-epic-scope-resolver.sh:397` and `:411` select PRs by head ref `^(spec\|implementation-plan\|feature\|fix\|refactor\|hotfix)/<team-prefix>?<issue>(-\|$)`; `:709` filters merged implementation PRs with `^(feature\|fix\|refactor\|hotfix)/`; `:769` emits `pullRequests` per item | Fix and hotfix are already covered, keyed on the issue number, and already in the scope JSON — no new query and no new pattern — verified 2026-09-21 |
| Branch/PR evidence, scan path | `open_implementation_pr_metadata` (`workflow-batch-plan.sh:363`–`:433`) matches `feature\|fix\|refactor\|hotfix/<slug>` and `…/<issue>-<slug-core>` heads, and reports its own failures as `PR_METADATA_STATUS=unavailable` with `gh_unavailable` / `gh_pr_list_failed` / `jq_parse_failed` (`:374`–`:402`) | Existing matcher **and** an existing unreadable-evidence convention to map onto `--branch-pr-evidence unavailable` — verified 2026-09-21 |
| Branch-name to issue convention | `workflow-next-action.sh:102`: `^(feature\|fix\|refactor\|hotfix)/([A-Za-z]{2,8}-)?([0-9]+)($\|-)` | The existing convention for reading an issue number out of an implementation branch; this item introduces no new pattern — verified 2026-09-21 |
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
  **before** `gh issue create`, when `--type` is exactly `Workflow` (**exact, case-sensitive
  comparison** — no new normalization: `update_tracker_type_best_effort` looks the option up
  exactly, so a variant such as `workflow` is not refused here and keeps today's behavior;
  a named test `framework-creation-type-exact-match` asserts `Workflow` is refused and
  `workflow` is not newly rejected) and `workflow_template_is_template` is `true`: print a single actionable stderr message
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
  - **Detectable `unavailable` causes — a closed list of nine, each with its own `REASON` and
    its own named test.** The framework-mode lookup reads the same surfaces the primitive
    reads, so it can detect exactly the failures that are already distinct early returns in
    `list_open_workflow_type_issues`. Every row here is mandatory: a cause without a passing
    named case is an unimplemented claim.

    | # | Cause | Code site | `REASON` | Named case |
    | --- | --- | --- | --- | --- |
    | 1 | Configured provider is not `github_projects` — the tracker does not support this lookup | `workflow-lib.sh:3273` | `provider_unsupported` | `lookup-unavailable-provider-unsupported` |
    | 2 | Project number missing | `:3280` | `project_number_missing` | `lookup-unavailable-project-number-missing` |
    | 3 | Project number non-numeric | `:3286` | `project_number_invalid` | `lookup-unavailable-project-number-invalid` |
    | 4 | Project owner unresolvable | `:3297` | `project_owner_unresolvable` | `lookup-unavailable-project-owner-unresolvable` |
    | 5 | Repository owner/name unresolvable | `:3305` | `repo_unresolvable` | `lookup-unavailable-repo-unresolvable` |
    | 6 | `gh issue list` failed (non-zero exit) | `:3312` | `issue_list_failed` | `lookup-unavailable-issue-list-failed` |
    | 7 | `gh issue list` **succeeded** but returned blank or malformed JSON | `:3316` (blank → `[]`), and malformed output reaching the `jq --argjson open` at `:3330` | `issue_list_blank_or_malformed` | `lookup-unavailable-issue-list-blank-or-malformed` |
    | 8 | `gh project item-list` failed | `:3322` | `item_list_failed` | `lookup-unavailable-item-list-failed` |
    | 9 | Item-list JSON could not be parsed | `:3361` | `item_list_unparseable` | `lookup-unavailable-item-list-unparseable` |

    Each named case asserts `STATUS=unavailable`, its own non-empty `REASON`, `JSON=[]`, and
    exit `0`. Where the primitive warns and returns `[]`, the framework-mode wrapper returns
    `STATUS=unavailable` with the corresponding `REASON` — that substitution *is* this item's
    change, and it is why the wrapper cannot simply delegate in framework mode.
  - **Cause 7 needs its own validation step, because a successful command is not a usable
    response.** Verified in the primitive: a blank `gh issue list` result is checked only for
    emptiness and returned as `[]` (`:3316`–`:3318`), so today a blank response is
    indistinguishable from "the repository has no open issues"; and a non-blank but malformed
    response is not validated at all — it reaches `jq --argjson open "$open_issues"` at
    `:3330`, whose failure is reported by the message at `:3361` about **project items**. The
    framework-mode wrapper must therefore validate the issue-list response before using it:
    non-blank, and parseable as a JSON array. A blank or malformed response is
    `STATUS=unavailable` with `REASON=issue_list_blank_or_malformed` — **never** `empty`
    (which would claim the board has no open items) and **never**
    `item_list_unparseable` (which would blame the wrong request). The named case asserts all
    three: the status, the distinct reason, and that neither of the two wrong answers is
    produced.
  - **There is no Type-unreadable case in framework mode.** The framework-mode lookup returns
    every open non-terminal item *regardless of Type*, so it never reads the classification
    field and that field's readability cannot change its result. The spec lists an unreadable
    classification field among the things that may make a lookup unperformable; in framework
    mode that particular cause cannot arise, because the field is never consulted. A
    misconfigured or renamed Type field therefore does **not** produce `unavailable` here, and
    no fixture or `REASON` string is defined for it. (The primitive's existing
    "Cannot distinguish 'no open Workflow items' from 'Type field unreadable'" warning at
    `:3373` stays exactly where it is, serving consumer mode, unchanged — consumer mode reports
    `STATUS=ok` in every case by contract, so it gains no new reporting from this feature.)
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
  vs consumer filter differences, a framework-mode empty-board case, and **all nine** named
  cases from the closed cause list above — `lookup-unavailable-provider-unsupported`,
  `-project-number-missing`, `-project-number-invalid`, `-project-owner-unresolvable`,
  `-repo-unresolvable`, `-issue-list-failed`, `-issue-list-blank-or-malformed`,
  `-item-list-failed`, and `-item-list-unparseable` — each asserting `STATUS=unavailable` with
  its own distinct non-empty `REASON`, `JSON=[]`, and exit `0`. The
  `-issue-list-blank-or-malformed` case additionally asserts the two wrong answers are **not**
  produced: not `STATUS=empty`, and not `REASON=item_list_unparseable`. Nine causes, nine
  cases: any cause left
  without a case must be deleted from the closed list instead of being claimed. Do **not** add
  a Type-unreadable fixture for framework mode: the framework-mode
  lookup does not read Type, so such a fixture could only pass by asserting behavior the
  implementation does not have. A fixture whose board carries a renamed Type field must assert
  the opposite — `STATUS=ok` (or `empty`) with the board's open items — proving the
  framework-mode result is independent of the classification field. The existing consumer-mode
  Type-key assertions in `test-workflow-lib-github-projects.sh` stay unchanged.
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
  and prints stable key=value output.

  **CLI contract — arguments are validated before any routing decision.**

  | Flag | Required | Accepted values | Notes |
  | --- | --- | --- | --- |
  | `--issue` | yes | positive integer, with or without a leading `#` | Used in `ITEM=` and the reason text |
  | `--status` | yes | any string, **including the empty string** | Empty means the tracker status could not be read; it is a value, not a missing argument |
  | `--artifact-stage` | yes | empty string, or one of `Spec Ready`, `Plan Ready`, `In Development`, `Done`, `Unknown` | Empty means no **development-folder** artifacts — it says nothing about branches or PRs, which `--branch-pr-evidence` carries. Required **and** empty-able: the caller must state the stage it observed, so a forgotten flag can never be read as "no work" |
  | `--branch-pr-evidence` | yes | `none`, `present`, or `unavailable` | The caller states what it observed about implementation branches/PRs for the item. Required and never defaulted, for the same reason as `--artifact-stage`: a forgotten flag must not read as "no work" |
  | `--caller` | yes | `single` or `scan` | Any other value is a usage error |
  | `--type` | no | any string | When omitted, the gate reads Type itself; see "Tracker-read cost" |
  | `--repo-root` | no | existing directory | Defaults to `workflow_repo_root` |

  - **Usage errors are not routing outcomes.** A missing required flag, a flag without a
    value, an unknown flag, a non-numeric `--issue`, or an unrecognized `--caller` /
    `--artifact-stage` value → print the usage message to **stderr**, exit **`64`** (matching
    `run-item-scope-resolver.sh:47` and `workflow-next-action.sh:40`), and print **no**
    `RESULT=` line at all. A caller must never be able to mistake a malformed invocation for a
    `pass`. Routing outcomes — `pass`, `hold`, `stop` — always exit `0`, so a caller under
    `set -e` branches on `RESULT` rather than on the exit status.
  - **Every documented invocation passes all five required flags**, including
    `--artifact-stage ''` and an explicit `--branch-pr-evidence` value. The smoke runbook's
    invocations use that exact form.
  - Named test **`gate-usage-errors`**: for each of missing `--issue`, missing `--status`,
    missing `--artifact-stage`, missing `--caller`, `--caller bogus`,
    `--artifact-stage Frobnicated`, missing `--branch-pr-evidence`, `--branch-pr-evidence maybe`,
    `--issue abc`, a flag with no value, and an unknown flag, assert exit `64`, a usage message
    on stderr, and **no** `RESULT=` in stdout. A companion
    assertion checks that `--status ''` and `--artifact-stage ''` are accepted values that
    produce a normal routing outcome with exit `0`.

  `--type` is an accepted value, not a saving mechanism: it avoids a tracker read only for a
  caller that already holds the Type (the single-item path, which takes it from the scope
  JSON), and the scan path does not — see "Tracker-read cost". When `--type` is omitted the
  gate reads Type via `get_tracker_type_for_issue`.

  **Effective stage, not raw status (one rule, stated once, used everywhere).** The spec's gate
  input is the item's board status *"reconciled against work already completed for it, exactly
  as routing reconciles a stale status today"*, and items already on a pipeline are not
  re-evaluated. `workflow_status_order` maps a literal status string and reconciles nothing, so
  it is **not** sufficient on its own. The gate therefore takes **three** inputs and holds only
  on their conjunction:

  1. **Tracker status** reconciled through `workflow_status_order` (`workflow-lib.sh:1610`):
     `Backlog` → `0`; any other recognized status → `> 0`; unrecognized → `-1`.
  2. **Artifact stage** — the same artifact-derived stage routing already uses to override a
     stale tracker status. `workflow-next-action.sh` computes it from the item's development
     folder (`:677`–`:696`: spec file present, plan file present, feature branch live or
     merged) and exits `66` when the folder is missing (`:559`–`:562`) or holds neither a spec
     nor a plan (`:578`–`:581`) — which `workflow-batch-plan.sh` already reads as "no merged
     spec/plan PR yet" (`:571`–`:582`). The gate consumes that value through
     `--artifact-stage`.
  3. **Branch / PR evidence** — because a missing development folder does **not** mean no work.
     `workflow-next-action.sh:601` states it outright: *"fix/ and hotfix/ don't use development
     folders"*, and its branch and merged-PR probes are scoped to the `feature`/`refactor`
     `dev_prefix` only (`:596`–`:660`). A fast-track item with an open `fix/` branch, or one
     whose `hotfix/` PR has already merged, is **on a pipeline and has no folder** — treating
     that as "no artifacts" would stop live work. The gate consumes this through
     `--branch-pr-evidence {none|present|unavailable}`.

  **Effective "no artifacts" therefore means both**: no matching development folder carrying a
  spec or plan, **and** no active or merged implementation branch/PR for the item. Evidence
  sources, both pre-existing:

  | Caller | Where branch/PR evidence comes from |
  | --- | --- |
  | Single-item (prelude `item` scope) | The scope JSON the resolver already produced: `pullRequests.open[]` and `pullRequests.merged[]` (`run-epic-scope-resolver.sh:769`), which are selected by head ref `^(spec\|implementation-plan\|feature\|fix\|refactor\|hotfix)/<team-prefix>?<issue>(-\|$)` at `:397` and `:411` — fix and hotfix included. `present` when any entry's head matches an implementation prefix (`^(feature\|fix\|refactor\|hotfix)/`), the same filter `:709` already uses for `merged_impl_count`. No extra API call |
  | Portfolio scan | `open_implementation_pr_metadata` (`workflow-batch-plan.sh:363`–`:433`), which matches `feature\|fix\|refactor\|hotfix/<slug>` and `…/<issue>-<slug-core>` heads. It already reports its own failures as `PR_METADATA_STATUS=unavailable` with `gh_unavailable` / `gh_pr_list_failed` / `jq_parse_failed` (`:374`–`:402`) — those map straight to `--branch-pr-evidence unavailable` |

  The branch-name–to-issue convention is the existing one
  (`workflow-next-action.sh:102`: `^(feature|fix|refactor|hotfix)/([A-Za-z]{2,8}-)?([0-9]+)($|-)`);
  no new pattern is introduced.

  The gate holds or stops on **exactly one** combination: framework mode **and** Type reads as
  `Workflow` **and** reconciled tracker status is `Backlog` **and** `--artifact-stage` is empty
  **and** `--branch-pr-evidence` is `none`. A **stale Backlog** — tracker still says `Backlog`
  while artifacts show `Spec Ready`, `Plan Ready`, `In Development`, or `Done`, **or** while a
  `fix`/`hotfix`/`feature`/`refactor` branch or PR exists for the item — **continues**, because
  its pipeline has already been chosen and the spec forbids re-evaluating it. Every other
  combination is `RESULT=pass`, which is what "unchanged from today" means for this gate.
  Nothing fails closed: unreadable evidence passes, matching the existing rule for an unreadable
  status or Type, and the spec adds **no** acceptance criterion for an absent class or an
  unreadable input (spec Decision-Gate Consistency Matrix; Out of Scope item 7).

  | Mode | Type read | Reconciled status | Artifact stage | Branch/PR evidence | Caller | Output |
  | --- | --- | --- | --- | --- | --- | --- |
  | Consumer | any (including unreadable) | any (including unreadable) | any | any | any | `RESULT=pass`, `REASON=consumer_mode` |
  | Framework | `Workflow` | `Backlog` (order `0`) | empty — no folder, or next-action exit `66` | `none` | `single` | `RESULT=stop`, `STOP_CONDITION=missing_tracker_context`, `ITEM=#<issue>`, `REASON=misclassified_type`, `REASON_TEXT=<names the item and the re-classification>` |
  | Framework | `Workflow` | `Backlog` (order `0`) | empty | `none` | `scan` | `RESULT=hold`, `ITEM=#<issue>`, `REASON=misclassified_type`, `REASON_TEXT=<same text>`, and **no** `STOP_CONDITION` key (a hold is not a stop) |
  | Framework | `Workflow` | `Backlog` (order `0`) | `Spec Ready` / `Plan Ready` / `In Development` / `Done` | any | any | `RESULT=pass`, `REASON=stale_backlog_reconciled` — the tracker status is stale; the pipeline was already chosen and this gate does not re-decide it |
  | Framework | `Workflow` | `Backlog` (order `0`) | empty | `present` — an open or merged `feature`/`fix`/`refactor`/`hotfix` branch or PR for this item | any | `RESULT=pass`, `REASON=branch_or_pr_in_flight` — fast-track work has no development folder by design, so the folder's absence is not evidence of an unstarted item |
  | Framework | `Workflow` | `Backlog` (order `0`) | empty | `unavailable` — `gh` missing, `gh pr list` failed, or its JSON could not be parsed | any | `RESULT=pass`, `REASON=branch_evidence_unavailable`, and the caller records `MISCLASSIFIED_TYPE_CHECK=deferred`. Fail open, and say the check did not run |
  | Framework | `Workflow` | any recognized non-`Backlog` status (order `> 0`) | any | any | any | `RESULT=pass`, `REASON=pipeline_already_chosen` |
  | Framework | `Workflow` | unrecognized / missing (order `-1`) | any | any | any | `RESULT=pass`, `REASON=status_unreconciled` |
  | Framework | `Feature` / `Bug` / `Refactor` | any | any | any | any | `RESULT=pass`, `REASON=type_routes_today` |
  | Framework | **missing or empty** — no Type set, provider not `github_projects`, no project configured, or the issue is not on the board (`get_tracker_type_for_issue` prints empty and exits `0`) | any | any | any | any | `RESULT=pass`, `REASON=type_absent` |
  | Framework | **parse failure** — item JSON exists but Type cannot be parsed (`get_tracker_type_for_issue` warns at `workflow-lib.sh:2321` and exits **non-zero**) | any | any | any | `scan` | `RESULT=pass`, `REASON=type_unreadable`, and the caller records `MISCLASSIFIED_TYPE_CHECK=deferred`. The gate must capture the helper's non-zero exit (`set +e` / `|| true`) so it does not inherit the failure under `set -e` |
  | Framework | **parse failure** (same condition) | any | any | any | `single` | **The gate is never reached.** `run-epic-scope-resolver.sh:687` already `error_exit`s with "failed to read tracker type for issue #N" during scope resolution — today's behavior on the single-item path, not introduced or changed by this item |

  - **Why the parse-failure row splits by caller.** The two callers obtain Type differently, so
    they meet its failure differently, and this plan changes neither. On the single-item path
    the Type is read during scope resolution (`run-epic-scope-resolver.sh:687`–`:689`), where
    an unparseable value already aborts the run before any gate exists; the gate therefore
    never sees that state and needs no handling for it. On the scan path the gate performs the
    read itself, so it does see the
    non-zero exit and treats it as a `pass` — consistent with the single status contract, which
    stops only on a Type that positively reads `Workflow`. `run-item-scope-resolver.sh` inherits
    the resolver behavior because it delegates to `run-epic-scope-resolver.sh` for GitHub
    items; its Linear branch never reads Type at all and is covered by the
    `trackerReadDeferred` rule below. **Do not change the resolver** to soften its hard failure:
    that is pre-existing behavior for a genuinely corrupt tracker read, and altering it is
    outside this item's spec.
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
- [ ] **Status data flow — the gate needs the tracker status *and* the artifact stage, and
  neither alone.** Verified at plan time. `workflow-next-action.sh` cannot host this gate: its
  `status_line` is computed purely from repository artifacts — spec file present, plan file
  present, feature branch exists or merged (`:677`–`:696`) — so it emits `Spec Ready`,
  `Plan Ready`, `In Development`, `Done`, or `Unknown` and **can never emit `Backlog`**; its
  own comment (`:670`–`:676`) states the VCS-derived status is a heuristic that must not
  override the tracker; and its argument parser (`:43`–`:77`) accepts only
  `--branch` / `--pr` / `--development` / `--repo` / `--repo-root` — there is no `--issue` or
  `--status`. Only the tracker can say `Backlog`. But the tracker status alone is not the
  spec's input either: the spec reconciles it against work already completed, which is exactly
  what the artifact stage records. So the tracker supplies condition 1 and next-action supplies
  condition 2. The authoritative status reader is `workflow-batch-plan.sh`, which resolves the
  issue number (`extract_github_issue_number`, `:516`) and reads the tracker status
  (`get_tracker_status_for_issue`, `:542`) — but today it uses that value only for the
  terminal-status skip (`:554`–`:557`) and the Linear deferred flag (`:547`–`:553`), and emits
  the artifact-derived `STATUS` from next-action's output instead (`:639`). That emission *is*
  today's reconciliation: artifacts already override a stale tracker status in the scan's own
  report. The data flow this item establishes:

  | Path | Who supplies each input | How they reach the gate | What the gate call looks like |
  | --- | --- | --- | --- |
  | Portfolio scan | Tracker status: `workflow-batch-plan.sh:542`. Artifact stage: the `STATUS` line of the `workflow-next-action.sh` call batch-plan already makes at `:569`–`:582` (empty when that call exits non-zero — the "no merged spec/plan PR yet" branch). Branch/PR evidence: `open_implementation_pr_metadata` (`:363`–`:433`), whose existing `PR_METADATA_STATUS=unavailable` reasons map to `--branch-pr-evidence unavailable`. Type: the gate's own `get_tracker_type_for_issue` read, since batch-plan retains no Type | In-process shell variables `$issue_number` / `$tracker_status` / the parsed `$status`; no new env var, no file | `framework-mode-backlog-type-gate.sh --issue "$issue_number" --status "$tracker_status" --artifact-stage "$status" --branch-pr-evidence "$pr_evidence" --caller scan --repo-root "$repo_root"`, invoked **after** the next-action call (`:582`) and before the block is printed (`:634`). Costs one extra GraphQL request per scanned non-terminal folder — see "Tracker-read cost" below |
  | Single-item run (bounded prelude scope `item` only) | Tracker status and Type: `run-epic-scope-resolver.sh:678` / `:687`, which `run-item-scope-resolver.sh` delegates to. Artifact stage: `workflow-next-action.sh --development <folder>` for the item's development folder, or empty when the item has no folder. Branch/PR evidence: `pullRequests.open[]` / `pullRequests.merged[]` already in the scope JSON (`run-epic-scope-resolver.sh:769`) | The resolved scope JSON that `run-bounded-prelude.sh` writes to `$scope_file` (`:460`–`:481`), whose item object already carries `status` and `type` (`:766`), plus the next-action call for the folder | Same script with `--caller single`, `--status` / `--type` / `--branch-pr-evidence` from `$scope_file` and `--artifact-stage` from next-action — **no extra tracker API call**. The `items` and `epic` scope modes are **not** wired to this gate; see Out of Scope |

  - **Ordering: the gate runs after `workflow-next-action.sh`, not before it.** An earlier
    revision of this plan placed the gate before the next-action call and skipped next-action
    for held folders; that is no longer possible, because next-action is what supplies the
    artifact stage the gate reconciles against. The scan therefore keeps its existing sequence
    — terminal-status skip, tool-fix classification, next-action — and evaluates the gate on
    the results.
  - **Scan hold is emitted by `workflow-batch-plan.sh`, not by `workflow-next-action.sh`.** On
    `RESULT=hold` the batch-plan loop prints the item block itself — `TARGET`,
    `DEVELOPMENT_PATH`, `SLUG`, `TOOL_FIX` (already computed at `:562`), the **tracker**
    `STATUS` (`Backlog`, not the artifact-derived value),
    `NEXT_ACTION=hold-misclassified-type` (**pinned**; do not rename),
    `MISCLASSIFIED_TYPE=Workflow`, and `MISCLASSIFIED_TYPE_REASON=<REASON_TEXT naming the
    item>` — replacing the `STATUS` / `NEXT_ACTION` pair it would otherwise have emitted from
    next-action's output. Both of batch-plan's emission branches need this: the normal block at
    `:634`–`:649`, and the abbreviated block on the next-action failure path (`:571`–`:582`),
    which is precisely the no-artifacts case a hold is most likely to hit. Consequences, all
    deliberate: `workflow-next-action.sh` is **not modified by this item** (so its consumers
    and its artifact-only contract are untouched), and the `case`-allow-list key-forwarding
    problem at `:592`–`:603` / `:634`–`:649` never arises, because the keys originate in
    batch-plan rather than passing through it.
  - **Fallback when the tracker status cannot be read.** `get_tracker_status_for_issue`
    (`workflow-lib.sh:2250`–`:2285`) returns an **empty string and exit `0`** for every
    failure mode: Linear provider (after emitting `TRACKER_ACTION_REQUIRED=read_status`), no
    project configured, issue not on the board, and unparseable item JSON. It never signals
    failure by exit code, so the caller cannot distinguish them. The gate is therefore called
    with `--status ""`, returns `pass` (`status_unreconciled`) per the single status contract,
    and the item continues down today's next-action path **unchanged**. No stop, no hold, no
    fail-closed behavior.
  - **Deferred checks are reported, not silently treated as clean.** When the gate passes only
    because the status or the Type could not be read, batch-plan emits
    `MISCLASSIFIED_TYPE_CHECK=deferred` with a short reason (alongside the existing
    `TRACKER_STATUS_DEFERRED` key it already prints for Linear at `:638`); when both reads
    succeeded it emits `MISCLASSIFIED_TYPE_CHECK=applied`, and in consumer mode
    `not_applicable`. This is a **report field only** — it changes no lane, no dispatch, and
    no routing decision; it exists so the scan report and Protocol `90` can say the
    misclassification check did not run, and so the orchestrator knows to re-apply the gate
    for a Linear item once it has resolved that item's status and Type from its own context.
  - **Linear placeholder must not be mistaken for a real Backlog.** `run-item-scope-resolver.sh`
    emits a deferred scope object with `trackerReadDeferred: true` (`:375`) and a literal
    `status: "Backlog"` / `type: ""` (`:396`–`:397`, repeated in the `items[]` copy). The
    single-item wiring must check
    `trackerReadDeferred` first and skip the gate (recording `deferred`) rather than reading
    that placeholder as an authoritative Backlog; the empty `type` would pass anyway, but the
    check must not depend on that coincidence.
  - **Tracker-read cost, stated accurately.** On the **scan** path this gate adds **one extra
    GraphQL request per scanned non-terminal folder in framework mode**. Status and Type do
    live in the same project item JSON (`workflow_github_project_item_for_issue` selects both),
    but `get_tracker_status_for_issue` and `get_tracker_type_for_issue` each call it
    separately, and there is **no item-level cache** — `workflow-lib.sh` caches only the
    project id (`:1641`–`:1643`), the Status/Type field metadata (`:1644`–`:1648`), and named
    field lookups (`:1651`–`:1652`). Nothing in this plan changes that, so the second read is
    real and must be budgeted rather than claimed away. The optional `--type` argument helps
    only where the caller **already holds** the value — the single-item path, which reads it
    from the scope JSON — and it does not prevent a second request on the scan path, where
    batch-plan retains only the status string. Reducing the scan to a single read would mean
    calling `workflow_github_project_item_for_issue` directly and parsing both fields, which
    bypasses the two public helpers and their failure semantics; that is a separate
    optimization, deliberately **not** part of this item. Given this repository's history of
    tracker rate limits during batch scans, the mitigation that actually applies here is
    placement, not caching: the gate is invoked only in framework mode, only after the
    terminal-status skip, and never for folders the scan already discarded.
  - **Single-item stop**: for the bounded prelude's `item` scope — the spec's single-item
    runner path — `RESULT=stop` makes `run-bounded-prelude.sh` emit stop output that maps to
    `missing_tracker_context`, names the item, and aborts before stage dispatch (Protocol
    `91`). The status and Type come from the scope JSON the resolver already produced, so the
    stop costs no extra tracker call. This is the only routing behavior this item adds to the
    prelude; the `items` and `epic` scope modes are untouched (see Out of Scope).
  - **Resolving the item's development folder (single-item path).** The scope JSON carries no
    development path for the `--issue`, `--branch`, and `--pr` selectors — only the
    `--development` selector names a folder outright (`run-item-scope-resolver.sh:145`–`:148`
    recognizes a `docs/specs/developments/*` token, and `run-work-router.sh:502` does the
    same). Neither resolver maps an issue number **to** a folder. The mapping that does exist
    is the reverse one, and this item reuses it rather than adding a second convention:
    1. **Relocate, do not rewrite.** Move `extract_github_issue_number` from
       `workflow-batch-plan.sh:318`–`:356` into `workflow-lib.sh` **verbatim**. Batch-plan
       already sources the lib at its `:7`, so its existing call at `:516` is unchanged and
       the function's behavior — `**Issue**: #NNN` in the folder's markdown first, then the
       leading digits of the slug (`:346`–`:352`) — is the single definition of the mapping.
    2. **Enumerate folders the way the scan already does**: `find docs/specs/developments
       -mindepth 1 -maxdepth 1 -type d | sort` (`workflow-batch-plan.sh:478`–`:481`). A folder
       matches when `extract_github_issue_number "$folder"` equals the target issue.
    3. **Zero matches** → `--artifact-stage ''`, but that is **not** on its own a decision.
       Fast-track work has no development folder by design
       (`workflow-next-action.sh:601`), so the prelude must then read
       `pullRequests.open[]` / `pullRequests.merged[]` from the scope JSON and pass
       `--branch-pr-evidence present` when any entry's head matches
       `^(feature|fix|refactor|hotfix)/`. Only when both are empty does the stop fire — an item
       with no folder **and** no branch or PR has genuinely not been started
       (`prelude-issue-no-folder-stops`, `stale-backlog-active-fix-branch-continues`).
    4. **Exactly one match** → run `workflow-next-action.sh --development <folder>` and pass
       its `STATUS` as `--artifact-stage`; a non-zero exit means no folder artifacts, so pass
       the empty string and still supply the branch/PR evidence
       (`prelude-issue-one-folder-uses-its-stage`).
    5. **Two or more matches** → `RESULT=pass` with `REASON=artifact_stage_ambiguous`, and
       name every matching folder in the message. Deterministic and non-destructive: duplicate
       folders for one issue mean work exists somewhere, and holding on an ambiguity the spec
       never asks about would stop work for a bookkeeping problem. The message reports the
       newest folder first — the last entry of the `sort` above, which is chronological
       because folders are `<14-digit-timestamp>_<slug>` — so the operator can find it
       (`prelude-issue-multiple-folders-passes`).
    A stale-Backlog item whose folder already holds a spec or plan therefore continues here
    exactly as it continues in the scan.
- [ ] **Lane wiring — `NEXT_ACTION=hold-misclassified-type` alone does not hold anything.**
  Verified against the tree at plan time: `workflow-batch-lanes.sh:32` maps any unrecognized
  action to the `review` lane via the `*)` fallback, `:374` initializes `dispatch="proposed"`,
  and `report_category_for_item` returns `held` only when `dispatch` is already `held` (`:91`).
  The new action name alone would therefore be **proposed for dispatch in the review lane** —
  the opposite of the spec's hold. Three concrete changes are required:
  1. `workflow-batch-lanes.sh`, lane assignment loop (`:355`–`:420`): read
     `MISCLASSIFIED_TYPE_REASON` alongside `NEXT_ACTION`, and **before** the
     `stage_lane = none` branch set `dispatch="held"` with
     `hold_reason="$MISCLASSIFIED_TYPE_REASON"` (fallback text if empty) when
     `next_action = hold-misclassified-type`, without consuming a stage-lane cap slot.
  2. Add an explicit `hold-misclassified-type)` arm to `stage_lane_for_next_action` (`:25`)
     returning `review` rather than relying on the `*)` fallback, and **not** `none` — `none`
     forces `dispatch="skip"`, which reports as `INFORMATIONAL`, not `HELD`.
  3. `report_category_for_item` (`:50`): add an early `hold-misclassified-type` → `held` arm
     placed **before** the `ready-for-human-review` label check (`:81`) and the in-review
     status check (`:74`), so no upstream branch can downgrade a misclassified item to
     `informational`. The existing `dispatch = held` output path then prints `HOLD_REASON` and
     `HELD_SUMMARY` (`:551`–`:556`) unchanged.
  `MISCLASSIFIED_TYPE_REASON` is deliberately **not** named `HOLD_REASON`: lanes echoes the
  whole input block (`:542`) before printing its own `HOLD_REASON` (`:552`), so reusing that
  name would emit a duplicate key with two different values.
  **Required end state** (what the tests assert, not the action name): for that item
  `DISPATCH=held`, `REPORT_CATEGORY=held`, `REPORT_LABEL=HELD - not included in proposed
  batch`, and a non-empty `HOLD_REASON` naming the item and the re-classification — while the
  scan exits `0` and every sibling item keeps its own lane and dispatch.
  **Backlog items with no development folder** are outside this script pipeline entirely
  (`workflow-batch-plan.sh` scans development folders; `workflow-batch-lanes.sh --scan` takes
  development paths). For those, the hold is produced by Protocol `90`'s Backlog routing table
  and its `HELD - not included in proposed batch` report category, which the closed mirror
  list already requires this item to update — the script changes above cover the folder-bearing
  case, and the protocol text covers the rest. Both must be present.
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
    / false / unrecognized), `run-bounded-prelude.sh` in scope `item` for a Backlog + Workflow
    item produces the same routing outcome shape as today's pre-feature baseline (no stop/hold
    from this gate; infer-path / existing tables).
  - `consumer-next-action-workflow-unchanged`: `workflow-next-action.sh` output for the same
    folder matches today's NEXT_ACTION / lane classification byte-for-byte. Because this item
    does not modify that script at all, the scenario doubles as a regression guard that the
    gate was never wired into it — in **either** mode. Diff evidence against recorded baseline
    stdout or golden fixtures is required.
  - `consumer-batch-plan-workflow-unchanged`: under consumer fixtures,
    `workflow-batch-plan.sh --scan` for a Backlog + Workflow folder emits the pre-feature
    block (same `STATUS`, same `NEXT_ACTION`), with `MISCLASSIFIED_TYPE_CHECK=not_applicable`
    and no `MISCLASSIFIED_TYPE*` hold keys. This is the scenario that fails if the new gate
    call leaks into consumer mode.
  - `consumer-routing-all-classes-unchanged`: under the same consumer fixtures, repeat the
    three scenarios above for **every** class — `Feature`, `Bug`, `Refactor`, `Workflow`, and
    no class at all — at Backlog, and assert each matches the recorded pre-feature baseline.
    The AC is "routing for every class, including Workflow, is identical", so Workflow-only
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
| 7 | `docs/workflow/development-workflow/integrations/github-projects.md` | Type field table (`:97`, `:107`–`:110`), the setup step that tells an operator to verify open framework items carry `Type = Workflow` (`:138`), and the retrospective create snippet that assigns it (`:202`) |
| 8 | `AGENTS.md` | Tracker Classification section |
| 9 | `CLAUDE.md` | Same Tracker Classification paragraph |
| 10 | `GEMINI.md` | Same Tracker Classification paragraph |
| 11 | `.cursor/agents/orchestrator.md` | Tracker Classification section |
| 12 | `.claude/agents/orchestrator.md` | Tracker Classification section |
| 13 | `docs/testing/workflow/retrospective-protocol.smoke-test.md` | Step 5 (`:88`) instructs the operator to confirm the retrospective-created issue carries Type `Workflow`, and the step's Expected result (`:93`) repeats it — this is exactly the create-and-classify path protocol `06` changes, so leaving it makes the runbook assert the behavior this item removes. Its "Related existing item" check (`:86`) is also fed by the framework-item lookup, so it must state that in framework mode an unavailable lookup is reported as unavailable and never as "No existing backlog item found" |
| 14 | `docs/testing/workflow/tracker-type-field-classification.smoke-test.md` | Steps 1–2 (`:32`–`:48`) direct an operator to create an issue in this repository and set its Type to `Workflow`, and Step 4 (`:68`–`:77`) asserts that a Backlog Workflow item routes as discoverable framework work — which in framework mode is now a misclassification hold. Step 3 (`:55`–`:66`) stays valid as written **because** `list_open_workflow_type_issues` keeps Workflow-only filtering; scope the creation and routing steps to consumer mode (or to a consumer fixture) and state the framework-mode outcome instead of deleting the coverage |
| 15 | `scripts/development-workflow/add-backlog-item.sh` (`--help` text, `:40`–`:41`) | The usage text lists `Workflow` among the valid `--type` values with no note that a framework-mode repository refuses it, so an agent reading `--help` is still pointed at the class the same command rejects. The exit-code list immediately below (from `:43`) documents `1` only as a Priority-resolution failure and must also name the framework-mode Workflow refusal, since this plan pins that refusal to exit `1` |

Out of list, each with the reason it is excluded (re-verified 2026-09-20 by the live search
recorded below; if implementation finds a new instructing surface, add it to this table in the
same PR):

| Path or glob | Why it is not a mirror surface |
| --- | --- |
| `.cursor/agents/item-orchestrator.md`, `.agents/skills/**`, `.codex/skills/**` | No Tracker Classification paragraph and no "file as Workflow" instruction; the tree-wide `Type…Workflow` search returns zero hits under these paths |
| `scripts/development-workflow/tests/**` | Fixtures and assertions, not guidance. `test-workflow-lib-github-projects.sh` deliberately encodes Workflow-typed fixtures to pin the unchanged primitive and **must keep passing**; changing them would hide the regression they exist to catch |
| `docs/specs/developments/**` (other items' specs and plans), `CHANGELOG.md` | Historical records of past decisions, not live instructions. Rewriting them would falsify the record |
| `docs/testing/workflow/native-github-projects-issue-type.smoke-test.md` | Covers Type **resolution precedence** (native vs custom fields), not how to classify an item; no instruction to set Workflow |
| `scripts/development-workflow/workflow-lib.sh` (9 sweep hits) | Implementation of the unchanged primitive: the `item_type(.) == "Workflow"` filter (`:3345`) and its "cannot discover Workflow Type issues" warnings. It is code, not guidance, and this item explicitly does not change it |
| `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md:368`, `.../90-…:473`, `.../91-…:448` | These only say the project Type field replaces the legacy `workflow` **label**; they are already in scope through rows 2–4 for their routing and lookup text, and no separate change is needed for the label sentence |

**Symlink note (do not "fix")**: in this repository `CLAUDE.md` and `GEMINI.md` are symlinks
to `AGENTS.md`, so rows 8–10 are one file and a single edit satisfies all three. They stay
listed separately because downstream repositories created from this template may hold real
files, and because the grep check names all three paths explicitly — `rg` and `grep` follow a
symlink given as an explicit argument but do **not** follow symlinks found during recursion,
which is why a recursive search reports only `AGENTS.md`.

**Live search that produced rows 13–15** (re-run before readiness; see Residual Verification):

```bash
# grep --include patterns match basenames while recursing, so these single-star forms
# are correct; a '**/' prefix would not mean here what it means to a shell.
# <!-- markdown-heuristic-disable GLOB001 -->
INCLUDES=(--include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml')
grep -rn -E 'Type.{0,15}`?Workflow|--type Workflow|Workflow.{0,15}Type' \
  "${INCLUDES[@]}" . \
  | grep -v '^\./\.git/' | grep -v '^\./docs/specs/developments/'
grep -rn -E -- '--type|Type `|Type =|type field|Tracker Classification' docs/testing/
# The creation script's help text splits "Type" and "Workflow" across two lines, so the
# pattern sweep above cannot see it; check that file directly:
grep -n 'Workflow' scripts/development-workflow/add-backlog-item.sh
```

Hits from the first two commands resolve to closed-list rows 1, 5, 6, 7, 13, 14 and this
plan's own runbook, plus the out-of-list rows above (`workflow-lib.sh`,
`scripts/development-workflow/tests/**`, `CHANGELOG.md`, `docs/specs/developments/**`). The
third command yields the single `add-backlog-item.sh:41` hit that is row 15.

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
  - Exact pre-change runbook strings on rows 13–14: `with Type \`Workflow\`` in
    `docs/testing/workflow/retrospective-protocol.smoke-test.md` and
    `project Type will be set to \`Workflow\`` in
    `docs/testing/workflow/tracker-type-field-classification.smoke-test.md` — both are
    single-match anchors verified on today's tree, so the check is red before the runbooks are
    updated and green after
  **Form of the check — fail-closed, not `! rg`.** Implement it as the `assert_absent` helper
  in the smoke runbook: run `rg`, capture its status, and exit the script from inside the
  assertion. `rg` status `0` (a match survives) and status `2` or higher (`rg` itself errored)
  are both failures; only status `1` passes. Do **not** write `! rg …`: under `set -e` a
  negated command is exempt from errexit in bash and zsh, so that form silently continues past
  a real violation and the guard can never fail. Land the planted-violation proof
  (`guidance-check-planted-violation`) with the check.
- [ ] **Row 13 — `docs/testing/workflow/retrospective-protocol.smoke-test.md`** (unconditional;
  this runbook contradicts framework mode today):
  - Step 5 (`:88`) and its Expected result (`:93`): state that in framework mode the
    retrospective creates the item with `Feature`, `Bug`, or `Refactor` — never `Workflow` —
    and keep the consumer-repository expectation (Type `Workflow`, or the configured label
    convention for GitHub Issues-only setups) as the other branch.
  - "Related existing item" (`:86`): add that in framework mode an unavailable lookup is
    reported as unavailable with its reason and must not be recorded as
    "No existing backlog item found" (AC: Open framework items stay discoverable).
- [ ] **Row 14 — `docs/testing/workflow/tracker-type-field-classification.smoke-test.md`**
  (unconditional; replaces the earlier "only if it contradicts" note, which this plan's live
  search resolved — it does contradict):
  - Steps 1–2 (`:32`–`:48`): scope the "create an issue and set Type `Workflow`" instructions
    to a consumer-mode fixture or repository, and state that in a framework-mode repository
    the creation command refuses that class.
  - Step 4 (`:68`–`:77`): keep the consumer expectation and add the framework-mode outcome —
    a Backlog Workflow item is held as misclassified rather than routed as discoverable
    framework work.
  - Step 3 (`:55`–`:66`) and the `list_open_workflow_type_issues` call at `:60`: leave
    unchanged, and say why — the primitive keeps Workflow-only filtering in both modes, so
    this step remains a correct test of it. Framework-mode discovery is covered by the new
    runbook's wrapper steps instead.
  - Assertions checklist (`:96`–`:99`): mark the Workflow-discovery and Backlog-routing
    assertions as consumer-mode, and add the framework-mode counterparts.
- [ ] **Row 15 — `scripts/development-workflow/add-backlog-item.sh` help text**: update the
  `--type` usage lines (`:40`–`:41`) so the valid-value list notes that framework-mode
  repositories refuse `Workflow`, and add the refusal to the exit-code list (from `:43`), where
  `1` currently documents only a Priority-resolution failure. Both edits land with the
  Enforcement point 1 refusal, in the same PR.

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
| Item classification | `Feature` / `Bug` / `Refactor` / `Workflow` / missing or empty (helper exits `0`) / parse failure (helper exits non-zero) | `get_tracker_type_for_issue` (`workflow-lib.sh:2293`), read by the gate on the scan path and by `run-epic-scope-resolver.sh:687` on the single-item path; for creation, the `--type` argument |
| Item stage (**effective**, not raw) | Tracker status reconciled to `Backlog` (`workflow_status_order` = `0`) / recognized non-Backlog (`> 0`) / unrecognized or missing (`-1`), **combined with** artifact stage: empty (no folder, or next-action exit `66`) / `Spec Ready` / `Plan Ready` / `In Development` / `Done` | `workflow_status_order` (`workflow-lib.sh:1610`) for the status, and `workflow-next-action.sh` (`:677`–`:696`, exits `66` at `:559`–`:562` and `:578`–`:581`) for the artifacts — the same artifact-over-stale-status reconciliation the scan already applies when it emits next-action's `STATUS` at `workflow-batch-plan.sh:639` |
| Routing caller | `single` (a named single-item run) / `scan` (portfolio proposal) | `--caller` on `framework-mode-backlog-type-gate.sh`; the bounded prelude's `item` scope passes `single`, the portfolio scan path passes `scan`. No other caller is wired by this item |
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

Callers: the bounded prelude's `item` scope (`single`) and the portfolio scan (`scan`). The
`items` and `epic` scope modes are not callers of this gate — see Out of Scope.

"Stage" below is the **effective stage**: the reconciled tracker status together with the
artifact stage from `workflow-next-action.sh`, per the spec's "reconciled against work already
completed for it". Raw tracker status alone never decides a row.

| Mode | Classification | Stage (tracker + artifacts) | Caller | Outcome | Required next action |
| --- | --- | --- | --- | --- | --- |
| Framework | `Feature` / `Bug` / `Refactor` | any | any | `pass` (`type_routes_today`) | Existing pipelines; a Bug still goes through the existing scope check first |
| Framework | `Workflow` | `Backlog`, **no folder artifacts and no branch/PR** for the item | `single` | `stop`, `STOP_CONDITION=missing_tracker_context` | Report the stop naming `#<issue>` and the re-classification; start no pipeline; mutate nothing (`stop-path-no-mutation`) |
| Framework | `Workflow` | `Backlog`, **no folder artifacts and no branch/PR** | `scan` | `hold` (no `STOP_CONDITION`) | That item only: `DISPATCH=held`, `REPORT_CATEGORY=held`, `HOLD_REASON` naming the item. Scan continues, exits `0`, and still proposes every other valid item (`scan-backlog-no-artifacts-held`) |
| Framework | `Workflow` | `Backlog` **but artifacts show `Spec Ready` / `Plan Ready` / `In Development` / `Done`** — a stale tracker status | any | `pass` (`stale_backlog_reconciled`) | Continue: the pipeline was already chosen, and the spec does not re-evaluate an item already on one. Re-typing it is tracker hygiene (`scan-stale-backlog-with-artifacts-continues`) |
| Framework | `Workflow` | `Backlog`, no folder, **but an open or merged `feature`/`fix`/`refactor`/`hotfix` branch or PR exists** — fast-track work, which uses no development folder (`workflow-next-action.sh:601`) | any | `pass` (`branch_or_pr_in_flight`) | Continue: the item is already on a pipeline (`stale-backlog-active-fix-branch-continues`, `stale-backlog-merged-fix-pr-continues`) |
| Framework | `Workflow` | `Backlog`, no folder, branch/PR evidence **unreadable** (`gh` missing, `gh pr list` failed, unparseable JSON) | any | `pass` (`branch_evidence_unavailable`) + `MISCLASSIFIED_TYPE_CHECK=deferred` | Continue and report that the check did not run — same fail-open rule as an unreadable status or Type (`branch-evidence-unavailable-defers`) |
| Framework | `Workflow` | any recognized non-Backlog status (`Writing Spec` … `Released`) | any | `pass` (`pipeline_already_chosen`) | Continue the pipeline the item already started. The gate stops work being **started** on a mis-typed item; re-classification here is tracker hygiene, not a reason to halt in-flight work |
| Framework | `Workflow` | unrecognized or missing status (`-1`) | any | `pass` (`status_unreconciled`) | None — unchanged from today. The spec adds no AC for an unreconcilable status, so this does not fail closed |
| Framework | missing or empty (helper exits `0`) | any | any | `pass` (`type_absent`) | None — unchanged from today (spec matrix "Framework / Unset / Unchanged from today"; Out of Scope 7) |
| Framework | parse failure (helper exits non-zero) | any | `scan` | `pass` (`type_unreadable`), caller records `MISCLASSIFIED_TYPE_CHECK=deferred` | None for routing — the item proceeds as today; the deferred marker says the check did not run |
| Framework | parse failure (helper exits non-zero) | any | `single` | Gate not reached | Unchanged from today: `run-epic-scope-resolver.sh:687`–`:689` already aborts scope resolution with "failed to read tracker type for issue #N". This item neither introduces nor softens that failure |
| Consumer | any class, including `Workflow` | any | any | `pass` (`consumer_mode`) | None — existing routing tables, including infer-the-path for Workflow (`consumer-routing-all-classes-unchanged`) |
| Either | any class | already on a pipeline | any | Not re-evaluated | Unchanged — the item continues on the pipeline it started |

### Framework-item lookup gate (`list_open_framework_items.sh`)

| Mode | Lookup result | `STATUS` / `REASON` / `JSON` | Required next action in protocols `05` / `06` |
| --- | --- | --- | --- |
| Framework | Completed; at least one open item on the board | `STATUS=ok`, `REASON=` (empty), `JSON=[…]` — every open non-terminal item, whatever its Type | Review the list as today |
| Framework | Completed; board has no open items | `STATUS=empty`, `REASON=` (empty), `JSON=[]` | Legitimate empty answer; the flow continues and may record the review as performed against an empty board |
| Framework | Could not be performed — one of the nine detectable causes, each with its own `REASON` and named case: `provider_unsupported`, `project_number_missing`, `project_number_invalid`, `project_owner_unresolvable`, `repo_unresolvable`, `issue_list_failed`, `issue_list_blank_or_malformed`, `item_list_failed`, `item_list_unparseable` | `STATUS=unavailable`, `REASON=<one of the nine, non-empty>`, `JSON=[]` | **Continue** the flow; state in its own output that the lookup was not performed and why; do **not** record the open-script-bug review or the finding de-duplication as satisfied (`release-unavailable-continues-unsatisfied`, `retro-unavailable-continues-unsatisfied`) |
| Framework | Classification field renamed, misconfigured, or otherwise unreadable | **Not an outcome of this gate.** The framework-mode lookup never reads Type, so the field's readability cannot affect its result: the answer is `ok` or `empty` on the board's open items exactly as if the field were fine | None — no `REASON`, no fixture, and no detection mechanism is defined for this case in framework mode |
| Consumer | Completed | `STATUS=ok`, `REASON=` (empty), `JSON=` Workflow-filtered items | Unchanged |
| Consumer | Could not be performed | `STATUS=ok`, `REASON=` (empty), `JSON=[]` plus today's stderr warning — unchanged; consumer mode never emits `empty` or `unavailable` | Unchanged — out of scope for this feature (spec: consumer failure behavior is not touched) |
| Any | Wrapper usage error (bad arguments) | Non-zero exit; not a lookup outcome | Fix the call site. Lookup outcomes always exit `0` so `set -e` callers can branch on `STATUS` |

### Mirror surfaces and examples

Mirror surfaces for all three gates are the closed 15-path list in "Documentation and mirror
surfaces" above, which covers every row of the spec's Mirror surfaces table (creation protocol
`00`; routing tables `90` / `91`; scan report categories in `90`; lookup flows `05` / `06`;
create-and-classify flows `06` / `06b`; the tracker integration guide; the five agent-guidance
copies; the two smoke runbooks that assert the old classification behavior; and the creation
script's own help text). The spec's worked examples map row-for-row onto the tables above and
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
  (`DISPATCH=held` / `REPORT_CATEGORY=held`) for a `hold-misclassified-type` block carrying
  `MISCLASSIFIED_TYPE_REASON`
- `scripts/development-workflow/tests/test-run-bounded-prelude.sh` — the `item`-scope stop
  under `missing_tracker_context`, the `trackerReadDeferred` skip, and the consumer-fixture
  no-op
- A `workflow-batch-plan.sh` scan fixture (new file, or a section of
  `test-framework-mode-type-routing.sh`) — the tracker-status data flow: mocked
  `get_tracker_status_for_issue` / `get_tracker_type_for_issue` returning `Backlog` +
  `Workflow` for a folder whose artifacts would otherwise read `Spec Ready`

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
6b. **Nine named unavailable cases, one per declared cause**:
    `lookup-unavailable-provider-unsupported`, `lookup-unavailable-project-number-missing`,
    `lookup-unavailable-project-number-invalid`,
    `lookup-unavailable-project-owner-unresolvable`, `lookup-unavailable-repo-unresolvable`,
    `lookup-unavailable-issue-list-failed`,
    `lookup-unavailable-issue-list-blank-or-malformed`,
    `lookup-unavailable-item-list-failed`, and
    `lookup-unavailable-item-list-unparseable`. Each yields `STATUS=unavailable` with its own
    distinct `REASON` (`provider_unsupported`, `project_number_missing`,
    `project_number_invalid`, `project_owner_unresolvable`, `repo_unresolvable`,
    `issue_list_failed`, `issue_list_blank_or_malformed`, `item_list_failed`,
    `item_list_unparseable`), `JSON=[]`, and exit `0`.
6d. **`lookup-unavailable-issue-list-blank-or-malformed` negative assertions**: a `gh issue
    list` that exits `0` with blank output, and one that exits `0` with malformed JSON, each
    produce `STATUS=unavailable` / `REASON=issue_list_blank_or_malformed` — and **neither**
    produces `STATUS=empty` (today's silent outcome for the blank case at
    `workflow-lib.sh:3316`) nor `REASON=item_list_unparseable` (which would blame the project
    item-list request for an issue-list problem).
6c. **`framework-lookup-ignores-type-field`**: with the board's Type field renamed or absent,
    the framework-mode lookup still returns the open items (`STATUS=ok`, or `empty` on an
    empty board) — **not** `unavailable`. This is the fixture that keeps the criteria, the
    matrix, and the implementation agreeing that framework mode never reads Type.
7. **`release-unavailable-continues-unsatisfied`** / **`retro-unavailable-continues-unsatisfied`**:
   unavailable lookup does not stop protocol `05` / `06` and is not recorded as satisfied.
8. Gate: Backlog + Workflow stops the single runner, and the stop text names the item; the
   `scan` caller yields a hold, not a global stop.
9. **`scan-misclassified-item-held`** / **`scan-misclassified-not-informational`**: the scan
   item reaches `DISPATCH=held` + `REPORT_CATEGORY=held` with a naming `HOLD_REASON`, a
   sibling Feature stays `proposed_batch`, and label/status branches cannot downgrade the held
   item to informational.
9b. **`scan-backlog-no-artifacts-held`**: tracker status `Backlog`, Type `Workflow`, and no
    completed work — the folder holds neither spec nor plan, so `workflow-next-action.sh`
    exits `66` and `--artifact-stage` is empty. The item is held: the abbreviated block carries
    `STATUS=Backlog` (the tracker value), `NEXT_ACTION=hold-misclassified-type`, and a naming
    `MISCLASSIFIED_TYPE_REASON`. This is the case the feature exists for.
9b-ii. **`scan-stale-backlog-with-artifacts-continues`**: the same tracker status `Backlog` and
    Type `Workflow`, but the folder already holds a merged spec, so next-action reports
    `Spec Ready`. The item is **not** held — its `NEXT_ACTION` and `DISPATCH` match the
    pre-feature baseline, and the gate records `REASON=stale_backlog_reconciled`. A stale
    tracker status must not re-decide a pipeline that has already started (spec: items already
    on a pipeline are not re-evaluated). Repeat with `Plan Ready` and `In Development` fixtures.
    **This scenario replaces an earlier one that asserted the opposite**; see the Decisions and
    Change Log.
9c. **`scan-status-unreadable-defers`**: with the tracker status read returning empty (Linear
    deferral, missing project config, or missing board item), the same item is **not** held —
    it proceeds down today's path with `MISCLASSIFIED_TYPE_CHECK=deferred` and its reason, and
    `DISPATCH` matches the pre-feature baseline for that folder. Asserts both halves: no false
    hold, and no silent claim that the check ran.
9d. **`gate-usage-errors`**: every malformed invocation (missing required flag, flag without a
    value, unknown flag, non-numeric `--issue`, bad `--caller` / `--artifact-stage` value)
    exits `64` with a usage message and **no** `RESULT=` line; `--status ''`,
    `--artifact-stage ''` and `--branch-pr-evidence none` are accepted values that yield a
    routing outcome with exit `0`.
9e. **`prelude-issue-no-folder-stops`** / **`prelude-issue-one-folder-uses-its-stage`** /
    **`prelude-issue-multiple-folders-passes`**: single-item folder resolution — zero matching
    development folders **and** no branch/PR evidence stops a Backlog + Workflow item, exactly
    one match supplies its next-action stage, and two or more matches pass with
    `REASON=artifact_stage_ambiguous` while naming every match.
9f. **`stale-backlog-active-fix-branch-continues`**: tracker `Backlog`, Type `Workflow`, no
    development folder, but an **open** `fix/<issue>-<slug>` branch or PR for the item →
    `RESULT=pass`, `REASON=branch_or_pr_in_flight`, nothing stopped or held. Fast-track work
    uses no development folder, so the folder's absence must not be read as "never started".
9g. **`stale-backlog-merged-fix-pr-continues`**: the same item with a **merged** `fix/` or
    `hotfix/` PR instead of an open one → same `pass` outcome. Covers the post-merge window in
    which the branch is gone but the work is done.
9h. **`backlog-no-folder-no-branch-stops`**: tracker `Backlog`, Type `Workflow`, no folder and
    no branch or PR of any implementation prefix → still `stop` for `single` and `hold` for
    `scan`. This is the case the feature exists for, and it must survive the two scenarios
    above.
9i. **`branch-evidence-unavailable-defers`**: with `gh` unavailable or `gh pr list` failing,
    the same no-folder item **passes** with `REASON=branch_evidence_unavailable` and the caller
    records `MISCLASSIFIED_TYPE_CHECK=deferred` — fail open, and say the check did not run.
10. **`framework-post-backlog-statuses-pass`**: Type Workflow passes at every recognized
    non-Backlog status (`Writing Spec` through `Released`), not only `Spec Ready`; an
    unrecognized status also passes as `status_unreconciled`.
11. **`stop-path-no-mutation`**: stop path performs zero tracker/branch mutation.
12. **`reclassify-then-route`**: post-reclassification Feature/Bug/Refactor routing matches
    today, including Bug scope check.
13. **`consumer-prelude-workflow-unchanged`** / **`consumer-next-action-workflow-unchanged`** /
    **`consumer-batch-plan-workflow-unchanged`** / **`consumer-routing-all-classes-unchanged`**:
    consumer fixtures for `run-bounded-prelude.sh`, `workflow-next-action.sh`, and
    `workflow-batch-plan.sh` keep pre-feature Backlog routing for every class, including
    Workflow. `workflow-next-action.sh` is not modified by this item, so its scenario doubles
    as a regression guard that the gate was not wired into it.
14. **Guidance mirror grep**: closed mirror list updated — including the two smoke runbooks and
    the `add-backlog-item.sh` help text — and the check fails on surviving framework-mode
    Workflow instructions. Each check is an explicit status assertion, **not** `! rg …`: under
    `set -e` a command negated by `!` is exempt from errexit in bash and zsh, so a `! rg` that
    finds stale guidance returns non-zero and execution continues, leaving a guard that can
    never fail. The assertion captures `rg`'s status and exits itself, treating `0` (match) as
    a failure, `1` (no match) as the only pass, and `2` or higher (`rg` errored) as a failure
    too, because a check that did not run must not report clean. See the smoke runbook for the
    exact `assert_absent` helper.
14b. **`guidance-check-planted-violation`**: re-introduce one pre-change string and assert the
    check exits non-zero and names that check; revert and assert it passes again. Required
    evidence — a guard that has never failed is not known to work.

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
   contract — the wrapper must exist before anything emits or consumes those keys. Its
   framework-mode branch maps each of the nine detectable read failures to its own `REASON`
   and reads no Type field.
4. Repoint protocols `05` / `06` snippets at the wrapper and give each its framework-mode
   `unavailable` handling (continue, report, do not mark satisfied).
5. Add `framework-mode-backlog-type-gate.sh` and wire it into the two paths that hold the
   authoritative tracker status: `run-bounded-prelude.sh` (`single`, reading `status` / `type`
   from the resolved scope JSON) and `workflow-batch-plan.sh` (`scan`, after its tracker-status
   read and terminal skip). `workflow-next-action.sh` is not modified. Land the
   `workflow-batch-lanes.sh` lane, dispatch, and report-category changes in the same change,
   since the emitted `hold-misclassified-type` action is inert without them.
6. Update every path on the closed mirror list — including the two smoke runbooks (rows 13–14)
   and the `add-backlog-item.sh` help text (row 15) — and land the grep-based guidance check.
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
| Misclassified scan item silently dispatched | A new `NEXT_ACTION` name alone lands in the review lane as `proposed`; the `workflow-batch-lanes.sh` dispatch/report changes are mandatory, and `scan-misclassified-item-held` asserts the end state (`DISPATCH=held`), not the action name |
| Gate keys off raw status and stops in-flight work | `workflow_status_order` reconciles nothing, so a stale `Backlog` on an item that already has a spec or plan would halt work the spec says must continue. The gate therefore requires a reconciled `Backlog` **and** an empty artifact stage **and** no branch/PR evidence; `scan-stale-backlog-with-artifacts-continues` fails if a stale Backlog with artifacts is held |
| Fast-track work stopped because it has no folder | `fix/` and `hotfix/` items use no development folder at all (`workflow-next-action.sh:601`), so "no folder" alone would stop live fast-track work. Branch/PR evidence is a required third input, read from sources that already match fix and hotfix heads; `stale-backlog-active-fix-branch-continues` and `stale-backlog-merged-fix-pr-continues` fail if either is held |
| Gate keys off artifacts alone and misses a real Backlog | `workflow-next-action.sh` can never emit `Backlog`, so artifacts alone cannot identify the case the feature exists for. The tracker status stays a required input, read from `get_tracker_status_for_issue` in `workflow-batch-plan.sh` and from the scope JSON on the single-item path; `scan-backlog-no-artifacts-held` fails if a genuine Backlog item with no work is dispatched |
| Unreadable tracker status read as clean | The status read returns empty with exit `0` for four different failure modes, so silence is indistinguishable from success. The gate passes (no fail-closed), but the block carries `MISCLASSIFIED_TYPE_CHECK=deferred` with its reason, and `scan-status-unreadable-defers` asserts both the absence of a false hold and the presence of the deferred marker |
| Runbooks assert the pre-feature classification | `docs/testing/workflow/retrospective-protocol.smoke-test.md` and `docs/testing/workflow/tracker-type-field-classification.smoke-test.md` are closed-list rows 13–14 with single-match grep anchors, so the guidance check fails while either still directs a framework-mode operator to Type `Workflow` |
| Gate over-reach beyond the spec | Only framework mode + reconciled `Backlog` + Type `Workflow` stops or holds; absent/unreadable Type and unreconcilable status `pass`, matching the spec's "Unchanged from today" rows. Any new fail-closed case requires a new spec AC first |
| Extra tracker read on every scanned folder | Accepted and budgeted, not claimed away: no item-level cache exists, so the scan's Type read is a second GraphQL request. Contained by placement — framework mode only, after the terminal-status skip, never for discarded folders. A single-read refactor of the two lib helpers is explicitly out of scope for this item |
| Lookup claims an unavailability it cannot detect | The framework-mode `unavailable` causes are a closed list of nine real read failures, each with its own `REASON` and its own named case; the classification field is not among them because framework mode never reads Type, and `framework-lookup-ignores-type-field` asserts a renamed Type field still yields `ok`/`empty` |
| Multi-item scopes silently inherit the gate | `--items` and `--epic` are explicitly out of scope and must stay unwired; `consumer-prelude-workflow-unchanged` plus the Out of Scope entry keep the boundary visible, and the deferred item `#1779` owns the multi-item disposition |

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
  `FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, and
  `FRAMEWORK_ITEMS_JSON` on every invocation. Spelled out rather than abbreviated: a
  `_REASON` / `_JSON` shorthand reads as a shared `FRAMEWORK_ITEMS_LOOKUP_` prefix, and
  `FRAMEWORK_ITEMS_LOOKUP_JSON` does not exist.
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
  begin consulting it: `run-bounded-prelude.sh` (**`item` scope only**, fed from the resolved
  scope JSON — the single-item stop under `missing_tracker_context`; the `items` and `epic`
  scope modes are not wired), `workflow-batch-plan.sh` (scan
  hold — it now uses the tracker status it already reads at `:542`, together with the artifact
  stage from the `workflow-next-action.sh` call it already makes at `:569`–`:582`, for a
  routing decision. Next-action still runs first, exactly as today; when the gate holds,
  batch-plan **replaces the `STATUS` / `NEXT_ACTION` pair it would have emitted** with the
  tracker `STATUS` and `NEXT_ACTION=hold-misclassified-type`, plus `MISCLASSIFIED_TYPE` /
  `MISCLASSIFIED_TYPE_REASON` / `MISCLASSIFIED_TYPE_CHECK`), and `workflow-batch-lanes.sh`
  (dispatch/report handling
  that turns that action into `DISPATCH=held`). `workflow-next-action.sh` is deliberately
  untouched. A framework-mode Backlog + Workflow run that previously started a pipeline now
  stops.
- **Rollback**: **Paired, not independent.** Reverting the gate alone leaves
  `workflow-batch-plan.sh` emitting an action that lanes no longer holds — which would put
  misclassified items back into the proposed batch **in the review lane**, a worse state than
  either endpoint. Undo requires reverting, in one change: (a) the gate script and its tests,
  (b) the `run-bounded-prelude.sh` `item`-scope call site, (c) the `workflow-batch-plan.sh`
  gate call and block emission, and (d) the `workflow-batch-lanes.sh` lane/dispatch/report
  arms. Protocol `90`/`91` routing text reverts with them. Because `workflow-next-action.sh`
  and `run-epic-scope-resolver.sh` never changed, and the `items` / `epic` scope modes were
  never wired, nothing outside these four surfaces is affected in either direction.
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
| Agent/skill mirrors | **Applicable** | Closed mirror list (15 paths, incl. two smoke runbooks and the creation script's help text) + failing grep check, with the out-of-list exclusions and the live search that produced them recorded |
| Published-contract reversal | **Applicable** | Reversal and Rollback section: (1) lookup primitive/wrapper split, (2) stdout key contract, (3) creation refusal, (4) routing gate paired revert |

Decision-gate matrix rows match the spec's allowed outcomes and required next actions, row for
row, including the "Unchanged from today" rows (absent/unreadable Type, unreconcilable status,
consumer lookup failure) which this plan implements as `pass` rather than as new behavior.
Mirror surfaces are the closed list above (includes `06b`,
`AGENTS.md`/`CLAUDE.md`/`GEMINI.md` — one file behind two symlinks — both orchestrator agent
stubs, the retrospective and tracker-Type smoke runbooks, and the `add-backlog-item.sh` help
text).

**Cross-section consistency self-check** (items appearing more than once, checked after the
final edit pass):

| Repeated item | Single agreed value |
| --- | --- |
| Lookup primitive | `list_open_workflow_type_issues` — unchanged, Workflow-only in both modes (Enforcement point 2, Decision Matrix, Reversal (1), Implementation Order) |
| Mode branch location | `list_open_framework_items.sh` only |
| Published lookup keys | `FRAMEWORK_ITEMS_LOOKUP_STATUS`, `FRAMEWORK_ITEMS_LOOKUP_REASON`, `FRAMEWORK_ITEMS_JSON` (no `LOOKUP_` in the third; no globs) |
| Gate script name | `framework-mode-backlog-type-gate.sh` |
| Scan action name | `hold-misclassified-type`, emitted by `workflow-batch-plan.sh` (keys `MISCLASSIFIED_TYPE`, `MISCLASSIFIED_TYPE_REASON`, `MISCLASSIFIED_TYPE_CHECK`) |
| Effective-stage inputs | Three: tracker status from `get_tracker_status_for_issue` (`workflow-batch-plan.sh:542` for the scan, scope JSON for a single-item run), artifact stage from `workflow-next-action.sh`, and branch/PR evidence (`pullRequests` in the scope JSON for single-item; `open_implementation_pr_metadata` for the scan). The gate holds only when all three say Backlog-with-no-work |
| `workflow-next-action.sh` | Not modified by this item, on any path |
| Scan tracker-read cost | Two reads (status, then Type) = two GraphQL requests; no single-read guarantee, and `--type` saves a read only for the single-item path |
| Framework-mode `unavailable` causes | The closed list of nine read failures, each with a `REASON` and a named case; the classification field is **not** one of them, because framework mode never reads Type |
| Gate call sites | Exactly two: `run-bounded-prelude.sh` for the `item` scope, and `workflow-batch-plan.sh` for the portfolio scan — in both cases **after** the artifact stage is known |
| `--caller` values | `single` (single-item run) and `scan` (portfolio scan). No other value, and no other caller |
| Multi-item scopes | `--items` / `/run-items` and `--epic` / `/run-epic` are unchanged by this item; deferred to `#1779` |
| Unparseable Type | The `single` caller never reaches the gate — `run-epic-scope-resolver.sh:687` already aborts resolution (unchanged); the `scan` caller passes as `type_unreadable` with `MISCLASSIFIED_TYPE_CHECK=deferred` |
| Unreadable status or Type | `pass` plus `MISCLASSIFIED_TYPE_CHECK=deferred` (a report field only; no routing effect) |
| Closed mirror list size | 15 paths, with an explicit out-of-list table |
| Stop condition | `missing_tracker_context`, single-item caller only; a `scan` hold emits no stop condition |
| Status contract | stop/hold only at reconciled `Backlog` **with an empty artifact stage and no branch/PR evidence**; a stale `Backlog` carrying spec/plan artifacts passes as `stale_backlog_reconciled`, one with a `feature`/`fix`/`refactor`/`hotfix` branch or PR passes as `branch_or_pr_in_flight`, unreadable evidence passes as `branch_evidence_unavailable`, and every other recognized or unrecognized status passes |
| Absent / unreadable Type | `pass` — never a fail-closed stop |

---

## Residual Verification Strategy

Before the implementation PR reaches `ready-for-human-review`, every matrix row above must map
to a named passing test or smoke runbook step (including the named scenarios in Key scenarios).
Consumer-mode behavior requires diff evidence that:

1. Existing Workflow **discovery** tests are unchanged (or byte-identical outputs) under
   consumer fixtures, **and**
2. Consumer **routing** through `run-bounded-prelude.sh`, `workflow-next-action.sh`, and
   `workflow-batch-plan.sh` matches the recorded pre-feature baseline for Backlog at **every**
   class — Feature, Bug, Refactor, Workflow, and none (scenarios
   `consumer-prelude-workflow-unchanged` / `consumer-next-action-workflow-unchanged` /
   `consumer-batch-plan-workflow-unchanged` / `consumer-routing-all-classes-unchanged`), and
3. Consumer **creation** output is byte-identical for every class
   (`consumer-creation-all-classes-unchanged`).

**Residual sweep evidence.** Three enumerations in this plan claim completeness and must be
re-verified on the implementation branch head before readiness, with the command and its
output pasted into the PR:

- The closed mirror list (15 paths): re-run the guidance greps in Step 4 of the smoke runbook.
  Zero matches is the evidence; any new duplicate found must be added to the table in the same
  PR rather than left out of the list.
- The instructing-surface sweep that produced rows 13–15: re-run the three commands recorded
  under the closed mirror list. Every remaining hit must be accounted for by a closed-list row
  or by a row of the out-of-list table; an unaccounted hit is a missing mirror surface, not
  noise.
- The bypass inventory for `add-backlog-item.sh`: re-run the flag/env inventory assertion in
  `creation-refusal-no-bypass`. An empty inventory is the evidence; a non-empty one must be
  rejected for Workflow in framework mode before the scenario can pass.
