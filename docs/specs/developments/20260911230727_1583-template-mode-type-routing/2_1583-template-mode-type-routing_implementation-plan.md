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
- [ ] Extend `scripts/development-workflow/tests/test-add-backlog-item.sh` with template and
  consumer config fixtures proving: framework mode + `--type Workflow` → exit `1`, no `gh`
  create invocation; consumer config → existing success path unchanged.

### Enforcement point 2 — open "framework items" lookup

- [ ] Refactor `list_open_workflow_type_issues` internals so mode selects filter semantics:
  - **Consumer** ( `workflow_template_is_template` false ): preserve today's Workflow-only
    filter and stderr warning behavior exactly (AC: Consumer repositories are unchanged).
  - **Framework mode**: include every open, non-terminal project item linked to an open repo
    issue, regardless of Type (AC: Open framework items stay discoverable).
- [ ] Add `scripts/development-workflow/list_open_framework_items.sh` as the **only**
  supported entrypoint for release/retrospective "open framework items" reads. Contract
  (always, on stdout, before exit):
  1. `FRAMEWORK_ITEMS_LOOKUP_STATUS=ok|empty|unavailable`
  2. `FRAMEWORK_ITEMS_LOOKUP_REASON=<human-readable text>` (empty when `ok` with items)
  3. `FRAMEWORK_ITEMS_JSON=<compact JSON array>` on the final line
  - **Consumer repositories**: delegate to today's `list_open_workflow_type_issues` behavior;
    print `FRAMEWORK_ITEMS_LOOKUP_STATUS=ok` and emit Workflow-filtered JSON (no new
    unavailable-vs-empty requirement).
  - **Framework mode**: `ok` when at least one open non-terminal item exists; `empty` when the
    lookup completed and the board has none; `unavailable` when the lookup could not be
    performed (preserve stderr detail). Never emit `empty` for a failed read.
  - Keep `list_open_workflow_type_issues` as the consumer-mode primitive; framework mode
    may call it internally only after changing filter semantics behind the wrapper.
- [ ] Update protocols `05` and `06` snippets to call `list_open_framework_items.sh` (not the
  raw lib function).
- [ ] Extend `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` (or
  add `tests/test-framework-mode-type-routing.sh`) with mocked `gh` fixtures for framework
  vs consumer filter differences and framework-mode unavailable vs empty-board cases.

### Enforcement point 3 — Backlog routing for Type `Workflow`

- [ ] Add `scripts/development-workflow/framework-mode-backlog-type-gate.sh` (name may vary)
  that accepts `--issue`, `--status`, `--caller {single|scan}`, optional `--repo-root`, reads
  Type via `get_tracker_type_for_issue`, and prints stable key=value output:
  - Consumer mode or non-Backlog status → `RESULT=pass` (no change).
  - Framework mode + Backlog + Type `Workflow` + caller `single` → `RESULT=stop`,
    `STOP_CONDITION=missing_tracker_context`, human-readable reason + re-classify hint (AC:
    Routing stops instead of guessing).
  - Framework mode + Backlog + Type `Workflow` + caller `scan` → `RESULT=hold` with the same
    reason fields (AC: portfolio scan holds only that item).
  - Framework mode + item already past Backlog (status reconciled to Spec Ready / Writing Plan /
    In Development / etc., same set `workflow-next-action.sh` already treats as pipeline-chosen)
    → `RESULT=pass` even if Type is still Workflow (AC: mid-pipeline items continue).
- [ ] Wire the gate into the **actual** classification paths (not `run-work-router.sh`, which
  only redirects `/run-work` scope):
  - **Single-item runs**: invoke from `scripts/development-workflow/run-bounded-prelude.sh`
    once the target issue and tracker status are known; on `RESULT=stop`, emit prelude output
    that maps to `missing_tracker_context` and abort before stage dispatch (Protocol `91`).
  - **Portfolio / batch proposal**: invoke from `scripts/development-workflow/workflow-next-action.sh`
    when classifying a development folder whose tracker Type is `Workflow`, status reconciles to
    Backlog, and framework mode is active — return a deterministic `NEXT_ACTION` such as
    `hold-misclassified-type` (exact name chosen in implementation) plus stable reason fields
    so `workflow-batch-lanes.sh` categorizes the item under `HELD - not included in proposed
    batch` without stopping the scan.
  - **Mid-pipeline items**: gate returns `pass` when status is past Backlog even if Type is
    still `Workflow` (reuse the same status reconciliation `workflow-next-action.sh` already
    uses).
- [ ] Extend `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` (or dedicated
  gate tests) to prove a Backlog + Workflow item is `held` with misclassification reason while
  a sibling Feature item remains `proposed_batch`.

### Documentation and mirror surfaces (spec Mirror surfaces table)

- [ ] `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` —
  classification step + inference table: framework-mode rule; remove/adjust examples that
  show Workflow for this repository.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and
  `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` —
  Backlog (Workflow) rows: framework mode = misclassified stop/hold; consumer = unchanged
  infer-path.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` and
  `06-retrospective-protocol.md` — framework-mode lookup meaning (all open items) + unavailable
  reporting; retrospective item creation must not direct Workflow in framework mode.
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` — Type field table:
  Workflow remains on board but invalid in framework mode; document lookup helper behavior.
- [ ] `AGENTS.md` Tracker Classification section + per-runner mirrors that duplicate that text:
  `.cursor/agents/orchestrator.md`, `.cursor/agents/item-orchestrator.md` (and other agent
  stubs under `.cursor/agents/` that restate tracker Type guidance), plus Codex/Claude skill
  copies under `.agents/skills/` and `.codex/skills/` when they repeat the same paragraph.
- [ ] `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` —
  remove the instruction to set Type `Workflow` when creating issues in framework mode; align
  with `06-retrospective-protocol.md`.
- [ ] Update `docs/testing/workflow/tracker-type-field-classification.smoke-test.md` only if
  its Workflow discovery steps contradict framework-mode semantics (otherwise leave unchanged
  and cover framework mode in the new runbook).

### Release documentation

- [ ] Add under `CHANGELOG.md` → `[Unreleased]` → `### Added` (or `### Fixed` if reviewer
  prefers behavior-fix framing):

  `- **Framework-mode work-item classification** (#1583): refuse Type Workflow on backlog creation in template repositories, stop or hold misclassified Backlog routing, and treat open-framework-item discovery as all open board items with distinguishable lookup-unavailable reporting in framework mode.`

Implementation PR adds a `changelog.d/` fragment instead of editing `CHANGELOG.md` directly.

---

## Classification Decision Matrix

Align implementation and tests with the spec's Decision-Gate Consistency Matrix. Summary for
code/tests:

| Mode | Classification | Stage | Caller | Outcome | Next action |
| --- | --- | --- | --- | --- | --- |
| Framework | Feature/Bug/Refactor | Backlog | any | Route unchanged | Existing pipelines |
| Framework | Workflow | Backlog | single | Stop | `missing_tracker_context`; re-classify |
| Framework | Workflow | Backlog | scan | Hold | Report in HELD / evaluated-not-proposed |
| Framework | Workflow | past Backlog | any | Pass | Continue current pipeline |
| Consumer | Workflow | Backlog | any | Unchanged | Infer path / existing tables |
| Framework | any | n/a | n/a | Lookup | All open items; unavailable ≠ empty |
| Consumer | n/a | n/a | n/a | Lookup | Workflow-filtered; failure behavior unchanged |

---

## Testing Strategy

**Primary automated suites**:

- `scripts/development-workflow/tests/test-add-backlog-item.sh`
- `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` and/or
  `scripts/development-workflow/tests/test-framework-mode-type-routing.sh`
- `scripts/development-workflow/tests/test-run-work-router.sh` (extend for HELD misclassification)

**Key scenarios**:

1. Framework mode refuses `--type Workflow` before issue creation with actionable message.
2. Consumer configs still create Workflow items with identical stdout shape.
3. Framework-mode lookup returns mixed-type open items; consumer returns Workflow-only.
4. Framework mode: stderr/verbose keys distinguish unavailable vs empty vs populated.
5. Gate: Backlog+Workflow stops single runner; scan caller yields hold, not global stop.
6. Gate: Spec Ready + Workflow type passes (pipeline already chosen).

**Quality checks**: ShellCheck on touched scripts; `workflow-shell-guard-lint.py`;
markdown lint on plan/spec/runbook/protocol edits.

**Smoke test runbook**: `docs/testing/workflow/1583-template-mode-type-routing.smoke-test.md`

---

## Implementation Order

1. Add failing regression tests for creation refusal, lookup mode split, and backlog gate.
2. Implement lib + `add-backlog-item.sh` refusal and framework-mode lookup status output.
3. Implement `list_open_framework_items.sh` and wire the backlog gate into
   `run-bounded-prelude.sh` + `workflow-next-action.sh`.
4. Update protocols, integration guide, and `AGENTS.md` mirrors per Mirror surfaces table.
5. Run full touched test suites + smoke runbook; add `changelog.d` fragment.

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Consumer lookup/regression drift | Guard consumer branches with copied fixtures from current green tests before editing shared function |
| Agents still infer Workflow path from stale skills | Update all mirrored classification snippets in the same PR |
| `[]` still read as "no items" in release/retrospective | Require explicit lookup status lines in framework mode protocol steps |
| Mid-pipeline Workflow items blocked | Gate must key off reconciled stage, not Type alone |

---

## Residual Verification Strategy

Before the implementation PR reaches `ready-for-human-review`, every matrix row above must map
to a named passing test or smoke runbook step. Consumer-mode behavior requires diff evidence
that existing Workflow discovery tests are unchanged (or byte-identical outputs) under consumer
fixtures.
