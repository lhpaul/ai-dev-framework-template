# Human-Checkpoint Policy Model for Delegated `/run-epic` — Spec

**Epic**: #1019 Add human checkpoints to delegated run-epic work  
**Depends on**: guardrails configuration model (#977), run-epic policy recommender (#949), PR risk classification (#919)

---

## Overview

Delegated `/run-epic` runs can decide review and merge authority up front through
guardrails and invocation policy, but they lack a first-class way to declare
that a specific item must pause for human product or technical feedback when its
pull request becomes automation-clean. Today, complex or ambiguous work relies
on ad hoc judgment late in the run — after reviewer loops, CI, and readiness
labels are already green — which makes it easy for an agent to treat
`ready-for-human-review` as permission to continue delegated review or merge.

This feature defines a **human-checkpoint policy model** that sits on the
existing run-epic/guardrails policy path. It does not introduce a parallel
autonomy system. Instead, it adds checkpoint metadata and a distinct readiness
signal so orchestration can distinguish:

- **Automation clean** — CI green, internal review gate satisfied, automated
  reviewers clean or skipped (`ready-for-human-review` semantics).
- **Human checkpoint still required** — automation is clean, but the epic run
  must stop and wait for explicit human feedback or approval before delegated
  review, delegated merge, or batch merge may continue.

The model is classified **before mutation** (during epic scope resolution and
policy recommendation), carried through PR readiness, and enforced at delegated
gates. Follow-up work items (#1021–#1024) implement the recommender, lifecycle
carriers, enforcement gates, and documentation/tests; this spec defines the
policy shape those items must implement.

---

## Brief Objective List

1. Define checkpoint record fields: stage, domain, reason, required human action,
   and satisfaction state.
2. Define how checkpoint intent is selected before mutation from item complexity,
   ambiguity, and known high-leverage signals.
3. Document database/schema/migration changes as a default plan-stage checkpoint
   signal.
4. Specify how checkpoints interact with `ready-for-human-review`,
   `needs-fixes`, `needs-setup`, delegated review, delegated merge, and audit
   comments.
5. Keep the model on the existing run-epic/guardrails policy path — one policy
   surface, not two.
6. Identify the documentation and implementation surfaces for follow-up
   sub-items.

---

## Use Cases

### Use Case 1: Epic runner classifies checkpoint intent before mutation

**Actor**: Portfolio Orchestrator or Work Item Runner operating under a
delegated `/run-epic` session  
**Preconditions**: Epic scope is resolved. Guardrails and invocation policy are
known or recommended. No artifact-mutating work has started for the item.

**Steps**:

1. The actor evaluates each eligible item using read-only signals: tracker
   type, title/body keywords, dependency references, ambiguity markers, and
   known high-leverage categories (schema, migration, architecture, product
   ambiguity).
2. For each item that needs a human checkpoint, the actor records one or more
   checkpoint records with stage, domain, reason, and required human action.
3. The recommended policy output includes checkpoint metadata alongside existing
   fields (`delegate-review`, `may-merge`, `may-start-backlog`, `max-risk`).
4. The human accepts, customizes, or rejects checkpoint recommendations before
   mutation begins.

**Postconditions**: Every in-scope item has zero or more declared checkpoints
with a deterministic satisfaction state of `pending`. The epic ledger can record
original, recommended, selected, and effective checkpoint policy.

**Information shown**:

- Per-item checkpoint list (may be empty).
- Why each checkpoint was recommended.
- Which stage and domain each checkpoint applies to.
- What the human must do to satisfy each checkpoint.

**Actions available**:

- Accept the recommended checkpoints.
- Add, remove, or edit checkpoints before work starts.
- Proceed without checkpoints when none are recommended and none are required.

**Considerations**:

- Checkpoint classification is read-only until the human confirms policy.
- Absence of a checkpoint does not remove baseline stop conditions from
  guardrails.

---

### Use Case 2: Automation-clean PR still blocks delegated merge

**Actor**: Work Item Runner advancing an item under delegated `/run-epic`  
**Preconditions**: The item has a `pending` checkpoint for the current stage
(e.g., `plan`). The PR has passed internal review, automated review, and CI.

**Steps**:

1. The runner applies `ready-for-human-review` because automation gates are
   clean.
2. The runner also applies `human-checkpoint-required` (or equivalent distinct
   signal) because a declared checkpoint for this stage is still `pending`.
3. Delegated review and delegated merge gates treat the checkpoint as blocking
   even though the PR is automation-clean.
4. The human provides the required feedback or approval documented in the
   checkpoint record.
5. The runner records checkpoint satisfaction (`satisfied`) with who satisfied
   it and when.
6. The runner removes `human-checkpoint-required` and may continue delegated
   review or merge if all other gates permit.

**Postconditions**: Delegated automation cannot bypass a declared checkpoint
merely because readiness labels are green.

**Information shown**:

- `ready-for-human-review` — automation is clean.
- `human-checkpoint-required` — explicit human feedback still required.
- Checkpoint reason, domain, and required human action on the PR and/or epic
  ledger.
- Satisfaction state transitions (`pending` → `satisfied` or `waived`).

**Actions available**:

- Human satisfies the checkpoint with review comments or explicit approval.
- Human waives the checkpoint with documented rationale (when policy permits).
- Agent fixes issues if human feedback converts the PR to `needs-fixes`.

**Considerations**:

- `ready-for-human-review` and `human-checkpoint-required` are orthogonal.
  Both may be present simultaneously.
- Satisfying a checkpoint does not by itself authorize merge; risk, audit, and
  other gates still apply.

---

### Use Case 3: Plan-stage checkpoint for schema or migration work

**Actor**: Policy recommender during epic scope resolution  
**Preconditions**: An eligible item's plan scope will include database schema,
migration, or persistent data-model changes (detected from issue body, labels,
or explicit human declaration).

**Steps**:

1. The recommender assigns a default **plan-stage** checkpoint with domain
   `technical` (or `both` when product impact is unclear).
2. The reason cites schema/migration/data-model impact.
3. The required human action asks for technical review of the proposed data
   model before implementation proceeds.
4. The checkpoint remains `pending` until the plan PR is reviewed and the human
   satisfies the checkpoint.

**Postconditions**: Schema- or migration-touching work cannot flow into
implementation under delegated merge without an explicit plan-stage human
checkpoint unless the human waived it up front.

**Information shown**:

- Default signal: plan stage, technical domain.
- Reason template referencing schema/migration/data model.
- Required action: human review/approval of plan before implementation branch
  work.

**Actions available**:

- Accept the default plan-stage checkpoint.
- Narrow domain to `product` when only product semantics are in question.
- Waive before mutation if the human explicitly accepts risk.

**Considerations**:

- This is a **default signal**, not an absolute rule — humans may waive at
  policy selection time.
- Implementation-stage checkpoints may still be added separately for the same
  item.

---

### Use Case 4: Checkpoint interaction with `needs-fixes` and `needs-setup`

**Actor**: Work Item Runner managing PR labels through a review cycle  
**Preconditions**: A PR carries `human-checkpoint-required` and one or more
other readiness labels.

**Steps**:

1. When CI fails or reviewers block, the runner applies `needs-fixes` and
   removes `ready-for-human-review` per existing protocol.
2. `human-checkpoint-required` persists while the checkpoint remains `pending`
   and the declared stage still applies.
3. When automation is clean again, the runner reapplies
   `ready-for-human-review`.
4. If infrastructure dependencies are detected, `needs-setup` may coexist with
   `ready-for-human-review` and `human-checkpoint-required`.
5. Delegated merge remains blocked until the checkpoint is `satisfied` or
   `waived`, regardless of `needs-setup` removal.

**Postconditions**: Checkpoint state survives ordinary fix cycles and coexists
correctly with existing label semantics.

**Information shown**:

- Valid label combinations and their meanings (see Business Rules).
- Which label changes do and do not affect checkpoint satisfaction.

**Actions available**:

- Fix code and rerun automation without satisfying the checkpoint.
- Satisfy checkpoint only after automation is clean unless policy defines an
  earlier satisfaction point.

**Considerations**:

- `needs-fixes` addresses automation/reviewer failures; checkpoints address
  human judgment requirements beyond automation cleanliness.

---

## Business Rules

### Checkpoint record shape

Each checkpoint is a structured record with these fields:

| Field | Type | Description |
| --- | --- | --- |
| `stage` | `spec` \| `plan` \| `implementation` | Workflow stage the checkpoint applies to. |
| `domain` | `product` \| `technical` \| `both` | Whether product judgment, technical judgment, or both are required. |
| `reason` | string | Human-readable explanation of why the checkpoint exists. |
| `required_human_action` | string | What the human must do (e.g., "approve plan data model", "confirm UX copy", "acknowledge architecture decision"). |
| `satisfaction_state` | `pending` \| `satisfied` \| `waived` | Whether the checkpoint is open, completed, or explicitly waived. |
| `satisfied_by` | string (optional) | Actor who satisfied or waived the checkpoint. |
| `satisfied_at` | timestamp (optional) | When satisfaction or waiver occurred. |
| `waiver_rationale` | string (optional) | Required when `satisfaction_state` is `waived`. |

An item may have zero or more checkpoints. An epic run carries the union of
per-item checkpoints in its effective policy.

### Checkpoint selection before mutation

- Checkpoint intent is selected **before any artifact-mutating action** for the
  item (branch creation, tracker transition beyond read-only, PR open, doc
  edit on feature branch).
- Selection inputs include: item type, title/body ambiguity, open questions,
  dependency on architecture or data-model decisions, explicit `Depends on`
  references, human-supplied policy overrides, and known high-leverage signals.
- Known high-leverage signals **default** to checkpoints:
  - **Plan stage + technical domain**: database schema, migration, or
    persistent data-model changes.
  - **Plan or implementation stage + both domains**: ambiguous product and
    technical tradeoffs called out in the issue.
  - **Spec stage + product domain**: unresolved product requirements or
    acceptance-criteria ambiguity when starting from Backlog.
- The policy recommender proposes checkpoints; the human selects effective
  checkpoints before mutation. Silent auto-waiver is not permitted for defaulted
  high-leverage signals unless the human explicitly waives with rationale at
  policy selection time.

### Readiness labels vs checkpoint signal

| Label / signal | Meaning |
| --- | --- |
| `ready-for-human-review` | Automation is clean: CI green, internal review gate satisfied, automated reviewers clean or skipped. Does **not** mean delegated review or merge may proceed when a **stage-applicable** checkpoint is `pending`. |
| `human-checkpoint-required` | A declared checkpoint whose `stage` matches the PR's current workflow stage is `pending`. Human feedback or approval named in `required_human_action` is still required. Checkpoints for future stages do not block the current PR. |
| `needs-fixes` | Automation or reviewer feedback requires code/doc fixes. Independent of checkpoint satisfaction except that fixes may be how a human responds. |
| `needs-setup` | Infrastructure setup is required. May coexist with `ready-for-human-review` and `human-checkpoint-required`. Does not satisfy a checkpoint. |

**Invariants**:

- **BR-1**: `ready-for-human-review` means automation-clean only.
- **BR-2**: `human-checkpoint-required` means a stage-applicable checkpoint is
  still open (`pending`) for the PR's current workflow stage.
- **BR-3**: A PR may carry both `ready-for-human-review` and
  `human-checkpoint-required` simultaneously when a stage-applicable checkpoint
  is `pending`.
- **BR-4**: Delegated review, delegated merge, and batch merge must treat
  `pending` checkpoints whose `stage` matches the PR's current workflow stage
  as blocking even when `ready-for-human-review` is present. Future-stage
  checkpoints declared up front do not block earlier-stage PRs.
- **BR-5**: Removing `human-checkpoint-required` requires
  `satisfaction_state` of `satisfied` or `waived` with audit evidence.
- **BR-6**: `needs-fixes` removal does not imply checkpoint satisfaction.
- **BR-7**: Checkpoint metadata must appear in epic audit output (PR
  disposition and epic ledger) alongside existing policy fields.

### Policy path integration

- Checkpoints extend the **existing** run-epic policy object consumed by
  `run-epic-policy-recommender.sh`, `run-epic-delegated-gate.sh`, and
  `run-epic-audit-trail.sh`. They do not replace guardrails `mode`,
  `stages.*`, `stop_conditions`, or risk classification.
- Guardrails `stop_conditions` (e.g., `architecture_decision`,
  `unclear_requirements`) remain baseline human-stops. Checkpoints add
  **stage-scoped, item-specific** human stops declared up front for delegated
  epic runs.
- Mapping placement (for follow-up implementation):
  - Recommender output → `checkpoints[]` on effective policy.
  - Delegated gate → block when any stage-applicable checkpoint (matching the
    PR's current workflow stage) is `pending`.
  - Audit trail → record original, recommended, selected, effective checkpoints
    and per-PR satisfaction transitions.

### Satisfaction and waiver

- Only a human (or an explicitly delegated human approval channel documented in
  the run) may set `satisfied` or `waived`.
- `waived` requires `waiver_rationale` in audit evidence.
- Satisfying a checkpoint for stage X does not satisfy checkpoints for other
  stages on the same item.

---

## Statuses / Enum Values

### `satisfaction_state`

| Code value | Display label | Description |
| --- | --- | --- |
| `pending` | Pending | Checkpoint declared; required human action not yet completed. |
| `satisfied` | Satisfied | Human completed the required action; delegated gates may proceed if all other gates pass. |
| `waived` | Waived | Human explicitly waived the checkpoint with documented rationale at or before satisfaction time. |

**Valid transitions**:

- `pending` → `satisfied` when the human completes the required action.
- `pending` → `waived` when the human explicitly waives with rationale.
- `satisfied` and `waived` are terminal for that checkpoint instance on that
  PR/stage cycle. A new PR cycle for a later stage may introduce new
  checkpoints.

### `domain`

| Code value | Display label | Description |
| --- | --- | --- |
| `product` | Product | Product judgment, UX, requirements, or acceptance criteria. |
| `technical` | Technical | Architecture, data model, migrations, security, or implementation approach. |
| `both` | Product and technical | Both domains must weigh in. |

---

## Operational Visibility

- **Policy recommendation summary**: Before mutation, show recommended
  checkpoints per item with reasons and required actions.
- **PR label pair**: When automation-clean but checkpoint pending, show both
  `ready-for-human-review` and `human-checkpoint-required`.
- **PR disposition audit**: Include checkpoint list, satisfaction states, and
  waiver rationales in `<!-- run-epic:pr-disposition -->` comments.
- **Epic ledger audit**: Include original, recommended, selected, and effective
  checkpoint policy in `<!-- run-epic:epic-ledger -->` comments.
- **Stop messages**: Delegated gate stop output must name the blocking checkpoint
  (`stage`, `domain`, `reason`, `required_human_action`).

---

## Acceptance Criteria

- [ ] AC1: The spec defines checkpoint fields (`stage`, `domain`, `reason`,
      `required_human_action`, `satisfaction_state`) and optional satisfaction
      metadata.
- [ ] AC2: The spec defines pre-mutation checkpoint selection from complexity,
      ambiguity, and high-leverage signals including schema/migration defaults at
      plan stage.
- [ ] AC3: The spec distinguishes `ready-for-human-review` (automation clean)
      from `human-checkpoint-required` (human feedback still required).
- [ ] AC4: The spec documents interaction with `needs-fixes`, `needs-setup`,
      delegated review, delegated merge, batch merge, and audit comments.
- [ ] AC5: The spec requires checkpoints on the existing run-epic/guardrails
      policy path without a parallel autonomy model.
- [ ] AC6: Follow-up implementation plan (#1020 plan stage) identifies files and
      tests for items #1021–#1024.

---

## Documentation Deliverables (for follow-up items)

The following authoritative docs must describe the checkpoint lifecycle after
the epic is implemented. This spec is the source requirement; item #1024 owns
final comprehensive documentation and tests. Intermediate items update targeted
sections:

| Document | Required content |
| --- | --- |
| `95-run-epic-protocol.md` | When checkpoints are recommended, how policy carries them, and gate behavior before delegated review/merge. |
| `guardrails.md` / `guardrails-enforcement.md` | How checkpoints relate to `stop_conditions`, delegated authority, and audit — without duplicating the policy schema. |
| `92-pr-readiness-signal-protocol.md` | `human-checkpoint-required` label definition, valid combinations with existing labels, application/removal rules. |

---

## Out of Scope (this spec / #1020)

- Implementing the policy recommender logic (#1021).
- Applying or removing PR labels in automation (#1022).
- Enforcing checkpoints in delegated gate or batch merge scripts (#1023).
- Comprehensive documentation edits and test fixtures (#1024).
- Non-epic single-item runs (`/run-item-work` without epic policy) unless later
  extended explicitly.
- Replacing guardrails `stop_conditions` or PR risk classification.

---

## Follow-Up Item Mapping

| Issue | Scope | Primary surfaces |
| --- | --- | --- |
| #1021 | Recommend upfront human checkpoints in run-epic policy | `run-epic-policy-recommender.sh`, recommender tests, protocol 95 policy section |
| #1022 | Carry checkpoints through PR readiness lifecycle | Protocol 91 Step 8a/8c, protocol 92, item-orchestrator labeling steps |
| #1023 | Enforce checkpoints in delegated and batch merge gates | `run-epic-delegated-gate.sh`, batch-merge gate, risk classifier interaction |
| #1024 | Document and test the human-checkpoint lifecycle | Workflow docs, smoke tests, fixture coverage |

---

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Define checkpoint fields | Checkpoint record shape, Statuses / Enum Values, AC1 |
| Pre-mutation selection from complexity and signals | Use Case 1, Business Rules (selection), AC2 |
| Schema/migration default plan-stage signal | Use Case 3, AC2 |
| Interaction with labels, delegated gates, audit | Use Case 2, Use Case 4, Business Rules (labels), AC3, AC4 |
| Existing policy path only | Business Rules (policy path), AC5 |
| Implementation identification for follow-up | Follow-Up Item Mapping, Documentation Deliverables, AC6 |
