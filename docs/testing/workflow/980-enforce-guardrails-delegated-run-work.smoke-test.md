# Smoke Test Runbook: Enforce Guardrails in Delegated /run-work Execution

**Feature**: Enforce Guardrails in Delegated /run-work Execution (#980)
**Spec**: [`../../specs/developments/20260617083237_980-enforce-guardrails-delegated-run-work/1_980-enforce-guardrails-delegated-run-work_specs.md`](../../specs/developments/20260617083237_980-enforce-guardrails-delegated-run-work/1_980-enforce-guardrails-delegated-run-work_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] #979 (guardrails config model) is merged into `develop-guardrails`, so the
      `guardrails` block in `.ai-dev-workflow.yaml` and
      `docs/workflow/development-workflow/guardrails.md` exist.
- [ ] This feature's branch is checked out with the edited Protocols 90/91/95,
      the new `guardrails-enforcement.md`, the updated agents/skills/commands, and
      the updated `REVIEW.md`.
- [ ] `gh` is authenticated and the existing run-epic helpers
      (`run-epic-risk-classifier.sh`, `run-epic-delegated-gate.sh`,
      `run-epic-audit-trail.sh`) are executable.
- [ ] You can read protocol text and, where noted, run the existing
      reviewer-loop / CI-loop / run-epic helper scripts against a test PR.

> This is a documentation-and-protocol feature. Each step verifies that the
> protocol text (and, where applicable, the reused run-epic helper behavior)
> produces the required decision. No application server is started.

---

## Test Data

| Item | Value |
| --- | --- |
| Conservative config fixture | `guardrails` section absent (or `mode: manual`) |
| Delegated config fixture | `mode: delegated`; `stages.{spec,plan,implementation}.may_merge_pr: true` within risk limits |
| Per-stage fixture | `stages.implementation.may_open_pr: false` |
| Risk-limit fixture | `stages.implementation.max_merge_risk: medium`, `required_evidence: [regression]` |
| Contradictory config fixture | a `guardrails` block that is unreadable or internally contradictory |
| Reference page | `docs/workflow/development-workflow/guardrails-enforcement.md` |

---

## Smoke Test Steps

### Step 0: Confirm the dependency gate and reference page

- Confirm `guardrails-enforcement.md` exists and defines: the three-layer
  resolution order, the config-field → run-epic-policy mapping table, the named
  stop conditions, the stop-message contract, the unreadable-config rule, the
  conservative-defaults statement, and the audit-evidence rules.
- Confirm Protocol 91 has a "Step 0: Load Effective Guardrails" subsection and
  that Protocols 90/91/95 link to `guardrails-enforcement.md` rather than
  restating the mapping.

**Expected result**: All sections present; no inline duplication of the mapping.

### Step 1: Run summary reports effective guardrails (with override)

**Maps to**: AC run-summary-with-override.

1. With the delegated config fixture plus an invocation override, follow the
   Protocol 91 (and Protocol 90) load+report behavior.

**Expected result**: The run summary states the effective autonomy mode, per-stage
open/merge permissions, per-stage max merge risk, the backlog-start policy, and
the stop conditions — and notes which values an override changed.

### Step 2: No config → conservative defaults reported

**Maps to**: AC no-config-defaults.

1. With the `guardrails` section absent, follow the load+report behavior.

**Expected result**: The run summary states conservative defaults are in effect
(no delegated merge; backlog starts confirmation-gated).

### Step 3: Backlog-start policy — confirmation required

**Maps to**: AC backlog-start-confirmation.

1. With `backlog_start.allow_without_confirmation` absent/false, attempt to start
   a not-yet-started backlog item.

**Expected result**: Orchestration stops before starting and asks the human to
confirm, naming the items proposed to start.

### Step 4: Backlog-start policy — allowed without confirmation

**Maps to**: AC backlog-start-allowed.

1. With `backlog_start.allow_without_confirmation: true`, start an eligible
   not-yet-started item.

**Expected result**: The item starts without a confirmation prompt.

### Step 5: PR-open gate per stage

**Maps to**: AC stage-open-forbidden.

1. With `stages.implementation.may_open_pr: false`, reach the implementation
   PR-open point.

**Expected result**: No PR is opened; the run reports the exact `may_open_pr`
guardrail that blocked it.

### Step 6: Delegated review authority absent → wait for human

**Maps to**: AC no-delegated-review.

1. With guardrails that do not grant delegated review authority for a stage,
   reach that stage's review handoff.

**Expected result**: The PR remains waiting for human review; orchestration does
not make the review decision itself.

### Step 7: Allowed delegated merge

**Maps to**: AC allowed-merge.

1. With merge authority granted, a clean reviewer loop and CI, required labels
   present, clean merge state, no unresolved blocking thread, recorded audit
   evidence, and classified risk at/below the stage maximum, reach the merge
   decision (assemble the evidence object and run
   `run-epic-risk-classifier.sh` + `run-epic-delegated-gate.sh`).

**Expected result**: The delegated gate returns `merge_allowed` and the PR is
merged through the repository-approved path.

### Step 8: Blocked merge — one evidence item missing

**Maps to**: AC blocked-merge-missing-evidence.

1. Repeat Step 7 but remove one evidence item (CI not green, or a missing
   required label, or an unresolved blocking thread, or missing audit evidence).

**Expected result**: The merge does not happen and the run reports the exact
missing evidence.

### Step 9: High-risk stop

**Maps to**: AC high-risk-stop.

1. With `stages.implementation.max_merge_risk: medium`, present a PR the risk
   classifier rates high.

**Expected result**: No merge; orchestration stops naming the risk guardrail
(`high_risk_change` / stage `max_merge_risk`).

### Step 10: Unclear-requirements stop

**Maps to**: AC unclear-requirements-stop.

1. Present a work item whose requirements are unclear and reach a decision point
   that needs the missing information.

**Expected result**: Orchestration stops, names `unclear_requirements` (or the
configured equivalent), and states the human action required.

### Step 11: Audit record exists and rerun updates it

**Maps to**: AC audit-record.

1. After a delegated merge or block decision, inspect the PR for the disposition
   audit record (and the item ledger when a parent/epic exists). Re-run the
   decision path.

**Expected result**: An audit record covers the original command, resolved scope,
effective guardrails, risk rationale, reviewer/CI outcome, and final decision;
the rerun updates the existing record (stable marker) rather than duplicating it.
No secrets/credentials/tokens/local-only paths appear in the record.

### Step 12: Unreadable / contradictory config stops before mutation

**Maps to**: AC unreadable-config.

1. With the contradictory config fixture, run the load step at run start.

**Expected result**: Orchestration stops before any artifact-mutating action and
reports the config problem (`guardrails_config_unreadable`) as the stop cause.

### Step 13: Single policy path and baseline-stop preservation

**Maps to**: AC verifiable-with-existing-harness; baseline-stop Business Rules.

1. Confirm Protocols 90/91/95 all route risk/merge/audit through the same
   run-epic helpers (no second policy model) and that `guardrails-enforcement.md`
   and `REVIEW.md` state guardrails may only add stops, never weaken the baseline
   human-stops.

**Expected result**: One policy path is documented; baseline stops are preserved.

### Last Step: Validate

- Verify all assertions in the checklist below are met.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Run summary states effective guardrails and notes override-changed values.
- [ ] No-config run states conservative defaults (no delegated merge, backlog
      confirmation-gated).
- [ ] Backlog-start confirmation-required policy stops and names the items.
- [ ] Backlog-start allow-without-confirmation policy starts without asking.
- [ ] PR-open gate blocks a forbidden stage and names the `may_open_pr` guardrail.
- [ ] No delegated review authority leaves the PR waiting for human review.
- [ ] Allowed delegated merge merges via the repository-approved path.
- [ ] Missing-evidence merge is blocked and names the missing evidence.
- [ ] High risk above the stage maximum stops and names the risk guardrail.
- [ ] Unclear-requirements stop names the condition and the human action.
- [ ] Audit record exists and a rerun updates it; secrets are redacted.
- [ ] Unreadable/contradictory config stops before any mutation and reports it.
- [ ] One run-epic policy path; baseline human-stops are preserved.

---

## Seed Data Reference

The following fixtures must be available (inline `guardrails` config blocks, no
committed fixture files):

| Entity | Scenario | How to load |
| --- | --- | --- |
| Conservative config | `manual` / no section | Remove or set `mode: manual` in `.ai-dev-workflow.yaml` |
| Delegated config | spec/plan/impl merges within risk limits | Set `mode: delegated` and `stages.*.may_merge_pr: true` |
| Per-stage forbid | implementation may not open PR | Set `stages.implementation.may_open_pr: false` |
| Risk-limit config | implementation medium + regression evidence | Set `stages.implementation.max_merge_risk: medium`, `required_evidence: [regression]` |
| Contradictory config | unreadable/contradictory block | Introduce a malformed/contradictory `guardrails` block |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Run summary omits guardrails | Load+report step not reached or config not loaded | Confirm Protocol 91 Step 0 and the Work Item Runner Summary edit are present |
| Gate field mismatch | #979 field names differ from the plan mapping | Re-confirm field names against the merged `guardrails.md` and update the mapping table |
| Stop emitted without a named cause | Stop-message contract not applied | Confirm `guardrails-enforcement.md` stop-message contract is referenced at the decision point |
| Two policy paths observed | Enforcement re-implemented instead of reusing run-epic helpers | Route risk/merge/audit through `run-epic-risk-classifier.sh` / `run-epic-delegated-gate.sh` / `run-epic-audit-trail.sh` |

---

## Known Limitations

<!-- Known issues with the smoke test itself (not the feature) -->

- Verification is documentation/protocol-level plus existing run-epic helper
  behavior; there is no application UI to exercise.
- Steps 7–9 and 11 depend on a real or fixture PR and the existing
  reviewer-loop / CI-loop / run-epic helpers being runnable in the environment.
