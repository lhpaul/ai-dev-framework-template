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
  - Consumer config → existing success path unchanged.

### Enforcement point 2 — open "framework items" lookup

- [ ] Refactor `list_open_workflow_type_issues` internals so mode selects filter semantics:
  - **Consumer** ( `workflow_template_is_template` false ): preserve today's Workflow-only
    filter and stderr warning behavior exactly (AC: Consumer repositories are unchanged).
  - **Framework mode**: include every open, non-terminal project item linked to an open repo
    issue, regardless of Type (AC: Open framework items stay discoverable).
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
  - Keep `list_open_workflow_type_issues` as the consumer-mode primitive; framework mode
    may call it internally only after changing filter semantics behind the wrapper.
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
  Type via `get_tracker_type_for_issue`, and prints stable key=value output:
  - Consumer mode → `RESULT=pass` (no change), including when Type or status cannot be read.
  - Framework mode + Type empty, unset, or Type read failed → `RESULT=stop` (caller `single`)
    or `RESULT=hold` (caller `scan`), `STOP_CONDITION=missing_tracker_context`,
    `REASON=type_unknown` (fail closed; do not pass).
  - Framework mode + `--status` missing or not reconcilable to a tracker Status →
    `RESULT=stop` / `RESULT=hold` as above, `REASON=status_unknown` (fail closed).
  - Framework mode + Backlog + Type `Workflow` + caller `single` → `RESULT=stop`,
    `STOP_CONDITION=missing_tracker_context`, human-readable reason + re-classify hint (AC:
    Routing stops instead of guessing).
  - Framework mode + Backlog + Type `Workflow` + caller `scan` → `RESULT=hold` with the same
    reason fields (AC: portfolio scan holds only that item).
  - Framework mode + item already past Backlog (status reconciled to exactly `Spec Ready`,
    `Writing Plan`, or `In Development` — the pipeline-chosen set `workflow-next-action.sh`
    already treats as past Backlog for this gate)
    → `RESULT=pass` even if Type is still Workflow (AC: mid-pipeline items continue).
- [ ] Wire the gate into the **actual** classification paths (not `run-work-router.sh`, which
  only redirects `/run-work` scope):
  - **Single-item runs**: invoke from `scripts/development-workflow/run-bounded-prelude.sh`
    once the target issue and tracker status are known; on `RESULT=stop`, emit prelude output
    that maps to `missing_tracker_context` and abort before stage dispatch (Protocol `91`).
  - **Portfolio / batch proposal**: invoke from `scripts/development-workflow/workflow-next-action.sh`
    when classifying a development folder whose tracker Type is `Workflow`, status reconciles to
    Backlog, and framework mode is active — return `NEXT_ACTION=hold-misclassified-type`
    (**pinned**; do not rename) plus stable reason fields
    so `workflow-batch-lanes.sh` categorizes the item under `HELD - not included in proposed
    batch` without stopping the scan.
  - **Mid-pipeline items**: gate returns `pass` when status is past Backlog even if Type is
    still `Workflow` (reuse the same status reconciliation `workflow-next-action.sh` already
    uses).
- [ ] Extend `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` (or dedicated
  gate tests) to prove a Backlog + Workflow item is `held` with misclassification reason while
  a sibling Feature item remains `proposed_batch`.
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

Align implementation and tests with the spec's Decision-Gate Consistency Matrix. Summary for
code/tests:

| Mode | Classification | Stage | Caller | Outcome | Next action |
| --- | --- | --- | --- | --- | --- |
| Framework | Feature/Bug/Refactor | Backlog | any | Route unchanged | Existing pipelines |
| Framework | Workflow | Backlog | single | Stop | `missing_tracker_context`; re-classify |
| Framework | Workflow | Backlog | scan | Hold | Report in HELD / evaluated-not-proposed |
| Framework | Workflow | Spec Ready / Writing Plan / In Development | any | Pass | Continue current pipeline |
| Framework | empty / unset / Type read failed | any | single | Stop | `type_unknown`; fail closed |
| Framework | empty / unset / Type read failed | any | scan | Hold | `type_unknown`; fail closed |
| Framework | any | status missing / unreconcilable | single | Stop | `status_unknown`; fail closed |
| Framework | any | status missing / unreconcilable | scan | Hold | `status_unknown`; fail closed |
| Consumer | Workflow | Backlog | any | Unchanged | Infer path / existing tables |
| Framework | any | n/a | n/a | Lookup | All open items; unavailable ≠ empty |
| Consumer | n/a | n/a | n/a | Lookup | Workflow-filtered; failure behavior unchanged |

---

## Testing Strategy

**Primary automated suites**:

- `scripts/development-workflow/tests/test-add-backlog-item.sh`
- `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` and/or
  `scripts/development-workflow/tests/test-framework-mode-type-routing.sh`
- `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` (HELD misclassification via
  `workflow-next-action.sh` output)

**Key scenarios** (each must fail if unmet — named where noted):

1. Framework mode refuses `--type Workflow` before issue creation with actionable message.
2. **`creation-refusal-no-bypass`**: refusal persists for every force/confirm/env bypass form
   accepted by `add-backlog-item.sh` (inventory empty today) and for the Linear `create`
   handoff path.
3. Consumer configs still create Workflow items with identical stdout shape.
4. Framework-mode lookup returns mixed-type open items; consumer returns Workflow-only.
5. Framework mode: `list_open_framework_items.sh` emits all three keys (`STATUS`, `REASON`,
   `JSON`) and distinguishes unavailable vs empty vs populated; exit codes match the contract
   (`0` for all three statuses). Consumer mode also emits all three keys (REASON may be empty).
6. **`release-unavailable-continues-unsatisfied`** / **`retro-unavailable-continues-unsatisfied`**:
   unavailable lookup does not stop protocol `05` / `06` and is not recorded as satisfied.
7. Gate: Backlog+Workflow stops single runner; scan caller yields hold, not global stop.
8. Gate: Spec Ready + Workflow type passes (pipeline already chosen).
9. **`stop-path-no-mutation`**: stop path performs zero tracker/branch mutation.
10. **`reclassify-then-route`**: post-reclassification Feature/Bug/Refactor routing matches
    today, including Bug scope check.
11. **`consumer-prelude-workflow-unchanged`** / **`consumer-next-action-workflow-unchanged`**:
    consumer fixtures for `run-bounded-prelude.sh` and `workflow-next-action.sh` keep pre-feature
    Workflow Backlog routing.
12. **Guidance mirror grep**: closed mirror list updated; grep check fails on surviving
    framework-mode Workflow instructions.

**Quality checks**: ShellCheck on touched scripts; `workflow-shell-guard-lint.py`;
markdown lint on plan/spec/runbook/protocol edits.

**Smoke test runbook**: `docs/testing/workflow/1583-template-mode-type-routing.smoke-test.md`

---

## Implementation Order

1. Add failing regression tests for creation refusal (incl. no-bypass), lookup mode split,
   flow-level unavailable, backlog gate (incl. no-mutation + reclassify + consumer callers).
2. Implement lib + `add-backlog-item.sh` refusal and framework-mode lookup status output.
3. Implement `list_open_framework_items.sh` and wire the backlog gate into
   `run-bounded-prelude.sh` + `workflow-next-action.sh`.
4. Update every path on the closed mirror list; land the grep-based guidance check.
5. Run full touched test suites + smoke runbook; add `changelog.d` fragment.

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Consumer lookup/regression drift | Guard consumer branches with copied fixtures from current green tests before editing shared function; named consumer prelude/next-action scenarios |
| Agents still infer Workflow path from stale skills | Closed mirror list + failing grep check in the same PR |
| `[]` still read as "no items" in release/retrospective | Explicit STATUS lines + flow-level unsatisfied scenarios for protocols 05/06 |
| Mid-pipeline Workflow items blocked | Gate must key off reconciled stage, not Type alone |
| Bypass flag added later | `creation-refusal-no-bypass` inventory assertion |

---

## Reversal and Rollback

Two published-contract changes need an explicit undo story:

### (1) `list_open_workflow_type_issues` filter semantics in framework mode

- **What changes**: In framework mode the shared lib function returns all open non-terminal
  items instead of Workflow-only. Consumer-mode behavior of the same function stays byte-compatible
  with today's filter.
- **Rollback**: Revert-safe. Callers that still invoke the lib primitive directly regain
  Workflow-only filtering when the merge commit is reverted (or when filter selection is
  restored to Workflow-only). Protocols `05`/`06` that switched to
  `list_open_framework_items.sh` must be reverted in the **same** rollback (or re-pointed to the
  lib function) so release/retrospective do not keep expecting all-open-items semantics after
  the filter flip is undone. Downstream syncs of this template pick up the revert on the next
  `/sync-template` of `scripts/development-workflow/**` and `docs/workflow/**`.

### (2) `FRAMEWORK_ITEMS_LOOKUP_*` stdout contract

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

No durable tracker or board state is written by these contracts; rollback is repository-content
only (plus downstream sync).

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
| Complex workflow decision gate | **Applicable** | Classification Decision Matrix + closed mirror list |
| Cross-cutting operational assumptions | **Applicable** | Verified table (batch #1757, #1462, #1496, #1515, #1561, #1583, #1529) |
| Agent/skill mirrors | **Applicable** | Closed mirror list (12 paths) + failing grep check |
| Published-contract reversal | **Applicable** | Reversal and Rollback section (filter + stdout contract) |

Decision-gate matrix rows match the spec's allowed outcomes and required next actions. Mirror
surfaces are the closed list above (includes `06b`, `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`, and
both orchestrator agent stubs).

---

## Residual Verification Strategy

Before the implementation PR reaches `ready-for-human-review`, every matrix row above must map
to a named passing test or smoke runbook step (including the named scenarios in Key scenarios).
Consumer-mode behavior requires diff evidence that:

1. Existing Workflow **discovery** tests are unchanged (or byte-identical outputs) under
   consumer fixtures, **and**
2. Consumer **routing** through `run-bounded-prelude.sh` and `workflow-next-action.sh` matches
   the recorded pre-feature baseline for Backlog + Workflow (scenarios
   `consumer-prelude-workflow-unchanged` / `consumer-next-action-workflow-unchanged`).
