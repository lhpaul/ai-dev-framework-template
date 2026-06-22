# Human-Checkpoint Policy Model for Delegated `/run-epic` — Implementation Plan

**Spec**: [`1_1020-human-checkpoint-policy-model_specs.md`](./1_1020-human-checkpoint-policy-model_specs.md)

---

## Summary

**Approach**: Item #1020 delivers the policy **model** in spec form only. No
runtime scripts change in this item. This plan maps the spec to four follow-up
implementation items (#1021–#1024) that extend the existing run-epic/guardrails
policy path: recommender output, PR readiness labels, delegated/batch merge
enforcement, and comprehensive docs/tests. Each sub-item owns a narrow slice so
the epic can land incrementally on
`develop-run-epic-human-checkpoints`.

**Estimated complexity**: S (plan-only for #1020; aggregate M across #1021–#1024)

**Rationale**: The spec already defines checkpoint fields, stage-order blocking
rules (`spec` → `plan` → `implementation`), label semantics, and audit
handoff. Implementation is deliberately split so policy recommendation (#1021),
lifecycle carriers (#1022), gate enforcement (#1023), and documentation/tests
(#1024) can merge independently without a monolithic PR.

**Dependencies**: guardrails config model (#977), run-epic policy recommender
(#949), PR risk classification (#919), guardrails enforcement (#980).

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | on `develop-run-epic-human-checkpoints` after spec PR #1029 merge |
| Existing policy helpers | `ls scripts/development-workflow/run-epic-*.sh` | `run-epic-policy-recommender.sh`, `run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh`, `run-epic-risk-classifier.sh`, `run-epic-scope-resolver.sh` exist |
| PR readiness protocol | `grep -n "ready-for-human-review\|needs-setup" docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | Label definitions live in protocol 92; `human-checkpoint-required` is net-new |
| Orchestrator labeling steps | `grep -n "Step 8a\|ready-for-human-review" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Step 8a/8c own readiness label application |
| Epic protocol policy section | `grep -n "policy-recommender\|delegated-gate" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Policy recommender and delegated gate already documented |
| No existing checkpoint term | `grep -rn "human-checkpoint" docs/ scripts/` | Net-new except epic issue bodies |

---

## Follow-Up Item Breakdown

### #1021 — Recommend upfront human checkpoints in run-epic policy

**Goal**: Extend `run-epic-policy-recommender.sh` to emit `checkpoints[]` per
eligible item using read-only signals from scope resolver output.

**Files to change**:

| File | Change |
| --- | --- |
| `scripts/development-workflow/run-epic-policy-recommender.sh` | Add checkpoint recommendation logic; output `checkpoints[]` with `item_number`, `stage`, `domain`, `reason`, `required_human_action`, `satisfaction_state` (`pending` or `waived` with rationale) |
| `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` | Fixtures for schema/migration default (plan+technical), ambiguity default (spec+product), empty scope, waived-at-selection |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Document checkpoint recommendation step before mutation |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Add checkpoint fields to config→policy mapping table (advisory; checkpoints are epic-policy fields, not `.ai-dev-workflow.yaml` schema) |

**Tests**: Unit fixtures in `test-run-epic-policy-recommender.sh`; no mutation
guards (read-only contract preserved).

---

### #1022 — Carry human checkpoints through PR readiness lifecycle

**Goal**: Apply/remove `human-checkpoint-required` in Protocol 91 alongside
existing readiness labels; record satisfaction transitions in audit comments.

**Files to change**:

| File | Change |
| --- | --- |
| `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | Define `human-checkpoint-required` label, valid combinations, application/removal rules |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Step 8a/8c: evaluate item+stage-order checkpoints; apply label when blocking checkpoints remain `pending` |
| `scripts/development-workflow/run-epic-audit-trail.sh` | Include checkpoint policy and satisfaction in PR disposition / epic ledger renders |
| `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` | Fixtures for checkpoint fields in audit output |

**Tests**: Audit trail unit tests; protocol-level smoke assertions in
`docs/testing/workflow/` (added by #1024).

---

### #1023 — Enforce human checkpoints in delegated and batch merge gates

**Goal**: Block delegated review and delegated merge (and batch merge) when
item-applicable `pending` checkpoints remain (current or earlier stage per spec
BR-4).

**Files to change**:

| File | Change |
| --- | --- |
| `scripts/development-workflow/run-epic-delegated-gate.sh` | Consume `checkpoints[]`; set `mergePermitted=false` and a blocking `decision` (e.g. `human_required`) when checkpoints block |
| `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` | Fixtures: same-item earlier-stage pending blocks implementation PR; other-item ignored; satisfied/waived permits |
| `scripts/development-workflow/batch-merge.sh` (or gate helper it calls) | Honor checkpoint block before merge |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Step 8 delegated-review loop: stop before reviewer dispatch when checkpoints block |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Gate 4 (delegated review): add checkpoint block alongside existing stop checks |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Step 7 / delegated-review entry: honor checkpoint block before internal review dispatch |
| `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` | Document checkpoint gate in batch merge prerequisites |
| `scripts/development-workflow/run-epic-risk-classifier.sh` | Optional: classify `pending` checkpoint as hard blocker (align with #919 `blocked` semantics) |

**Tests**: Delegated gate unit tests; risk classifier interaction test if blocker
added.

---

### #1024 — Document and test the human-checkpoint lifecycle

**Goal**: Authoritative end-user documentation and smoke-test runbook covering
the full lifecycle from policy selection through satisfaction.

**Files to change**:

| File | Change |
| --- | --- |
| `docs/workflow/development-workflow/guardrails.md` | Section relating checkpoints to stop conditions and delegated authority |
| `docs/workflow/development-workflow/README.md` | Index link; short overview in orchestration section |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Final integrated checkpoint lifecycle section (may consolidate #1021 edits) |
| `docs/testing/workflow/1020-human-checkpoint-policy-model.smoke-test.md` | New smoke runbook |
| `CHANGELOG.md` | Entry when implementation items merge (not for spec/plan PRs) |

**Tests**: Smoke runbook manual steps; optional workflow test script mirroring
`949-run-epic-interactive-autonomy-defaults.smoke-test.md` pattern.

---

## Item #1020 Scope Boundary

This item (#1020) is **complete** after:

1. Spec PR merged (PR #1029).
2. Plan PR merged (this document).

No `feature/*` implementation PR is required for #1020. After plan merge, the Work
Item Runner sets tracker status to **Done** (plan-only workflow item; no
implementation stage). The epic runner then advances #1021.

---

## Testing Strategy (epic-level)

| Layer | Coverage |
| --- | --- |
| Policy recommender (#1021) | Unit fixtures for default signals and waiver paths |
| Audit trail (#1022) | Render/apply tests for checkpoint fields |
| Delegated gate (#1023) | Block/permit matrix: item scope, stage order, satisfaction states |
| Batch merge (#1023) | Integration test or smoke step confirming checkpoint blocks merge |
| Docs/smoke (#1024) | Human-executable runbook on a fixture epic |

---

## Rollout Notes

- Introduce `human-checkpoint-required` as a new GitHub label in the template
  repo (or document that adopters must create it) during #1022.
- Checkpoint policy is epic-scoped; single-item `/run-item-work` runs without
  epic policy do not gain checkpoints unless extended in a future item.
- Default high-leverage signals are **recommendations**; humans must explicitly
  waive with `waiver_rationale` — never silent removal.

---

## Acceptance Criteria Mapping

| Spec AC | Plan coverage |
| --- | --- |
| AC1 checkpoint fields | #1021 recommender output shape; #1022 audit fields |
| AC2 pre-mutation selection | #1021 recommender signals |
| AC3 label distinction | #1022 protocol 92 + protocol 91 |
| AC4 label/gate/audit interaction | #1022 + #1023 |
| AC5 existing policy path | All items extend existing helpers, no parallel model |
| AC6 implementation identification | This plan's follow-up breakdown |
