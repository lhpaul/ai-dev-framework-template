# Enforce Guardrails in Delegated /run-work Execution — Spec

**Depends on**: 979-guardrails-config-model

---

## Overview

The framework is moving from human-reviewed merges at every stage toward delegated agent operation. A guardrails configuration only delivers value if orchestration consistently reads it and obeys it. Today, delegated behavior lives mainly in the `/run-epic` policy flags and its risk and audit helpers, while normal `/run-work` (portfolio orchestration) and `/run-item-work` (single-item orchestration) still assume a human merge gate at every stage.

This feature teaches orchestration to load the effective guardrails at the start of a run and enforce them at every decision point: before starting backlog work, before opening a pull request at any stage, before making a delegated review decision, before merging a pull request, and before marking an item complete. The guardrails describe what the agent may do automatically, what evidence it must collect, and where it must stop for a human. When the agent stops, it must name the exact guardrail that stopped it. This work generalizes the proven `/run-epic` risk-classification, delegated-gate, and audit concepts so that one consistent enforcement path serves both the epic command and ordinary orchestration, rather than creating a second, conflicting policy model.

This spec assumes the guardrails configuration model defined in issue #979 already exists. It describes which guardrail fields and modes this enforcement reads and how each is applied; it does not define the configuration schema itself. Implementation of this feature depends on #979 being merged first.

---

## Use Cases

### Use Case 1: Orchestrator loads and reports effective guardrails at run start

**Actor**: Orchestration runner (portfolio orchestrator or work item runner) acting on a human's `/run-work` request
**Preconditions**: A human invokes orchestration. The repository may or may not declare a guardrails configuration. The human may add invocation overrides; a previous turn in the same session may have set session overrides.

**Steps**:

1. The runner resolves the effective guardrails by layering three sources in priority order: repository configuration as the base, then session overrides set earlier in the same conversation, then overrides supplied with the current invocation.
2. The runner resolves the effective autonomy mode, the per-stage permissions (open PR, merge PR, maximum merge risk), the backlog-start policy, the required evidence, the configured stop conditions, and the audit requirements.
3. The runner states the effective guardrails in the run summary before taking any artifact-mutating action.

**Postconditions**: The run summary states the effective autonomy mode, what the agent may do at each stage, the maximum risk it may merge, the backlog-start policy, and which guardrails will stop the run. The effective guardrails are recorded so they can be cited in later stop messages and audit evidence.

**Information shown**:

- The effective autonomy mode (in user-facing terms).
- Per-stage permissions for spec, plan, and implementation: whether the agent may open a pull request, whether it may merge, and the maximum merge risk allowed.
- The backlog-start policy.
- The list of stop conditions that will halt the run.
- The source of each effective value when it differs from the repository default (which override changed it).

**Considerations**:

- When the repository declares no guardrails configuration, the runner applies the conservative defaults defined by #979 (no delegated merge, backlog starts confirmation-gated) and states that defaults are in effect.
- When the guardrails configuration is present but unreadable or internally contradictory, the runner treats this as a stop condition (see Use Case 7) rather than guessing a permissive value.
- Invocation overrides may only narrow or widen authority within what the repository configuration and autonomy mode permit; an override may not grant authority the mode forbids.

---

### Use Case 2: Enforce backlog-start policy before starting new work

**Actor**: Orchestration runner
**Preconditions**: The effective guardrails are loaded. The next deterministic action would start a not-yet-started backlog item (move it into Writing Spec, Writing Plan, or In Development for the first time).

**Steps**:

1. The runner reads the backlog-start policy from the effective guardrails.
2. If the policy allows starting backlog work without confirmation, the runner proceeds to start the item.
3. If the policy requires confirmation, the runner stops before starting the item and asks the human to confirm.

**Postconditions**: A backlog item is started only when the backlog-start policy permits it, or after the human confirms. Items already in flight are unaffected by this gate.

**Information shown**:

- Which backlog items are eligible to start.
- Whether the backlog-start policy permits starting them automatically.
- When confirmation is required, a clear request naming the items proposed to start.

**Considerations**:

- Backlog starts remain confirmation-gated unless the guardrails explicitly allow them, preserving the epic non-goal that autonomous backlog starts are not the default for existing repositories.
- This gate applies only to the transition from a not-yet-started state into an active stage. Resuming an item that is already in progress is not a backlog start.

---

### Use Case 3: Enforce stage permission before opening a pull request

**Actor**: Orchestration runner
**Preconditions**: The effective guardrails are loaded. A work item has produced output for a stage (spec, plan, or implementation) and the next deterministic action would open the pull request for that stage.

**Steps**:

1. The runner identifies the stage of the pull request about to be opened (spec, plan, or implementation).
2. The runner reads the stage permission for opening a pull request at that stage.
3. If opening is permitted, the runner proceeds to open the pull request through the normal stage flow.
4. If opening is not permitted, the runner stops before opening the pull request and reports the exact guardrail that blocked it.

**Postconditions**: A pull request is opened at a stage only when the effective guardrails permit opening at that stage. When opening is blocked, no pull request is created and the run reports the blocking guardrail.

**Information shown**:

- The stage of the pull request.
- Whether opening is permitted for that stage.
- When blocked, the name of the stage permission that prevented opening.

**Considerations**:

- This gate is independent of the merge gate. A configuration may allow opening a pull request at a stage while still forbidding an automatic merge of it.
- The default behavior (no guardrails configured) preserves the existing flow where opening pull requests proceeds and merges remain human-gated.

---

### Use Case 4: Make a delegated review decision under guardrails

**Actor**: Orchestration runner with delegated review authority
**Preconditions**: The effective guardrails grant delegated review authority for the relevant stage. A pull request has reached the review handoff point with reviewer-loop and CI results available.

**Steps**:

1. The runner confirms the effective guardrails permit it to make the review decision for this stage rather than waiting for a human.
2. The runner inspects the latest reviewer-loop result, the configured automated PR reviewers' outcomes, and the unresolved-thread state.
3. If blocking findings are present, the runner removes readiness, applies deterministic fixes through the normal fix loop, re-runs validation and the reviewer loop, and reassesses.
4. For advisory findings, the runner makes an explicit fix-or-accept decision per finding and records the rationale.
5. The runner restores readiness only after the reviewer loop, CI, and unresolved-thread checks are clean.

**Postconditions**: A delegated review decision is made only when the guardrails grant the authority. Blocking findings are resolved before readiness is restored. Each advisory finding has a recorded fix-or-accept rationale.

**Information shown**:

- Whether delegated review authority applies for this stage.
- The reviewer-loop result, CI result, and unresolved-thread count.
- For advisory findings, the per-finding fix-or-accept decision and rationale.

**Considerations**:

- When the guardrails do not grant delegated review authority for the stage, the pull request remains waiting for human review at its normal handoff point.
- This use case reuses the existing delegated review-and-fix behavior; it does not introduce a second review loop.

---

### Use Case 5: Make a delegated merge decision under guardrails, risk, and audit checks

**Actor**: Orchestration runner with delegated merge authority
**Preconditions**: The effective guardrails grant merge authority for the stage. The pull request has passed the delegated review decision and carries the required readiness evidence.

**Steps**:

1. The runner confirms the effective guardrails permit merging at this stage.
2. The runner confirms the required evidence is present: a clean reviewer-loop result, green CI with no pending or ambiguous required checks, the required readiness labels for the stage (including the regression label when the guardrails require regression for implementation pull requests), a clean merge state, no unresolved blocking review thread, and an acceptable reviewer disposition.
3. The runner classifies the current risk of the pull request and confirms it does not exceed the maximum merge risk allowed for the stage.
4. The runner confirms the audit evidence required by the guardrails has been recorded for the reviewed change.
5. The runner merges the pull request through the repository-approved merge path only when every check above passes.

**Postconditions**: A pull request is merged automatically only when stage merge permission, current risk within the stage limit, complete reviewer and CI evidence, required labels, a clean merge state, no unresolved blocking thread, and the required audit evidence are all satisfied. Otherwise the merge does not happen.

**Information shown**:

- Whether merge authority applies for the stage.
- Each required-evidence check and its result.
- The classified risk level and the stage maximum.
- Whether the required audit evidence is present.
- The final merge decision (merged, fix required, waiting on human, or blocked).

**Considerations**:

- A risk classified above the stage maximum stops the run; the runner does not silently widen its authority.
- A medium-risk delegated merge requires a complete "why safe to merge" explanation covering scope, tests, reviewer outcome, CI outcome, and rollback or cleanup risk; missing this explanation blocks the merge.
- High-risk changes are never merged automatically by default; they require explicit human selection of a high maximum risk for the stage.
- This use case reuses the existing `/run-epic` risk-classification and delegated-gate concepts rather than introducing a parallel merge gate.

---

### Use Case 6: Enforce stage permission before marking an item complete

**Actor**: Orchestration runner
**Preconditions**: A pull request for a stage has merged, or the runner is about to record an item as complete for the stage.

**Steps**:

1. The runner confirms the stage outcome that justifies completion (the stage pull request is merged, or the configured completion condition is met).
2. The runner confirms the configured audit evidence for the item has been recorded.
3. The runner updates the item's tracker status and records the run-complete evidence only when both conditions hold.

**Postconditions**: An item is marked complete for a stage only after the stage outcome is confirmed and the required audit evidence is recorded. An item is never marked complete from stale memory, a branch name, or prior resolver output alone.

**Information shown**:

- The confirmed stage outcome.
- Whether the required audit evidence is present.
- The tracker status transition applied.

**Considerations**:

- This preserves the existing rule that completion is verified against live state, not inferred.
- When audit requirements are not satisfied, the runner treats the missing audit as a stop condition (see Use Case 7) rather than marking the item complete.

---

### Use Case 7: Stop and name the guardrail that halted the run

**Actor**: Orchestration runner
**Preconditions**: At any decision point, a configured stop condition is met or required state is missing.

**Steps**:

1. The runner detects that a stop condition applies: unclear requirements, an architecture decision is required, CI is failing, an unresolved blocking review remains, the change is high risk above the allowed limit, a destructive action would be required, tracker context is missing, a required secret or permission is missing, the guardrails configuration is unreadable or contradictory, or the required audit evidence cannot be produced.
2. The runner stops before taking the action the stop condition guards.
3. The runner reports the exact guardrail or stop condition that halted the run, names the specific work item, and states what a human must do to unblock it.

**Postconditions**: When the runner stops, the stop message names the exact guardrail that stopped it and the specific unblocking action. The runner does not silently proceed past any configured stop condition.

**Information shown**:

- The exact stop condition or guardrail name that halted the run.
- The work item affected.
- The action a human must take to unblock the run.

**Considerations**:

- The configured stop conditions never weaken below the framework's existing human-stop conditions for unclear requirements, architecture choices, failing CI, high-risk changes, and destructive actions. Guardrails may add stop conditions but may not remove these baseline stops.
- A stop is a terminal condition for the affected item, not a silent skip; the run summary records every stop with its named cause.

---

### Use Case 8: Record audit evidence for each delegated decision

**Actor**: Orchestration runner making delegated review or merge decisions
**Preconditions**: The effective guardrails require audit evidence. A delegated review, fix, merge, block, or escalation decision was made for a pull request or item.

**Steps**:

1. After a delegated decision, the runner records the audit evidence required by the guardrails.
2. The runner writes a per-pull-request disposition record and, when configured, an item-level ledger record.
3. The runner reuses the existing stable audit markers so reruns update the existing records instead of creating duplicates.

**Postconditions**: Each pull request that reached a delegated decision has an audit record covering the original command, the resolved scope, the effective guardrails, the risk rationale, the reviewer and CI outcome, and the final decision. Reruns update existing records rather than duplicating them.

**Information shown**:

- Original command and resolved scope.
- Effective guardrails in force for the decision.
- Risk classification and rationale.
- Reviewer-loop and CI outcome.
- Final decision and any protocol deviations.

**Considerations**:

- Audit records are evidence only; they do not by themselves grant merge authority.
- Secrets, credentials, tokens, and local-only paths are redacted before any audit record is written.
- This reuses the existing `/run-epic` audit-trail concept and markers rather than defining a new audit format.

---

## Business Rules

- Orchestration must resolve effective guardrails by layering repository configuration, then session overrides, then invocation overrides, before any artifact-mutating action in a run.
- When no guardrails configuration is present, orchestration applies the conservative defaults defined by #979: no delegated merge and backlog starts confirmation-gated.
- An invocation or session override may narrow or widen authority only within what the repository configuration and the effective autonomy mode permit; it may never grant authority the mode forbids.
- A backlog item may be started without human confirmation only when the backlog-start policy explicitly allows it.
- A pull request may be opened at a stage only when the stage permission for opening permits it.
- A delegated review decision may be made only when the guardrails grant delegated review authority for that stage; otherwise the pull request waits for human review.
- A pull request may be merged automatically only when all of the following hold: the stage merge permission allows it; the classified current risk is at or below the stage maximum; the reviewer-loop result is clean; CI is green with no pending, failing, unavailable, or ambiguous required check; the required readiness labels for the stage are present; the merge state is clean; no unresolved blocking review thread remains; the reviewer disposition is acceptable; and the required audit evidence has been recorded.
- A medium-risk delegated merge requires a complete "why safe to merge" explanation covering scope, tests, reviewer outcome, CI outcome, and rollback or cleanup risk.
- A high-risk change is never merged automatically under default guardrails; merging it requires explicit human selection of a high maximum merge risk for the stage.
- The configured stop conditions may add to, but may never remove, the framework's baseline human-stop conditions: unclear requirements, architecture decisions, failing CI, unresolved blocking review, high-risk changes, and destructive actions.
- When orchestration stops, the stop message must name the exact guardrail or stop condition that halted the run, the affected work item, and the human action required to unblock it.
- An item may be marked complete for a stage only after the stage outcome is confirmed against live state and the required audit evidence is recorded; completion must never be inferred from stale memory, branch names, or prior resolver output.
- Risk classification, the delegated merge gate, and audit recording must reuse or generalize the existing `/run-epic` concepts and must not create a second, conflicting policy path.
- An unreadable or internally contradictory guardrails configuration is a stop condition; orchestration must not assume a permissive value.
- Secrets, credentials, tokens, and local-only paths must be redacted before any audit record is written.

---

## Acceptance Criteria

<!-- Each criterion must be testable — a human can verify it by following a smoke test. -->

- [ ] Given a repository with a guardrails configuration and an invocation override, when a human starts orchestration, then the run summary states the effective autonomy mode, the per-stage open and merge permissions, the maximum merge risk per stage, the backlog-start policy, and the list of stop conditions — and notes which values were changed by an override.
- [ ] Given a repository with no guardrails configuration, when a human starts orchestration, then the run summary states that conservative defaults are in effect (no delegated merge, backlog starts confirmation-gated).
- [ ] Given a backlog-start policy that requires confirmation, when orchestration would start a not-yet-started backlog item, then it stops before starting the item and asks the human to confirm, naming the items proposed to start.
- [ ] Given a backlog-start policy that allows starting without confirmation, when orchestration would start an eligible not-yet-started backlog item, then it starts the item without asking for confirmation.
- [ ] Given a stage permission that forbids opening a pull request at the implementation stage, when orchestration reaches the point of opening that implementation pull request, then it does not open the pull request and reports the exact stage permission that blocked it.
- [ ] Given guardrails that do not grant delegated review authority for a stage, when a pull request for that stage reaches the review handoff, then orchestration leaves it waiting for human review and does not make the review decision itself.
- [ ] Given guardrails that grant delegated merge authority, a clean reviewer-loop and CI, the required labels present, a clean merge state, no unresolved blocking thread, recorded audit evidence, and a current risk at or below the stage maximum, when orchestration reaches the merge decision, then it merges the pull request through the repository-approved path.
- [ ] Given the same delegated-merge setup but with one required piece of evidence missing (for example, CI not green, a missing required label, an unresolved blocking thread, or missing audit evidence), when orchestration reaches the merge decision, then it does not merge and reports the exact missing evidence.
- [ ] Given guardrails with an implementation maximum merge risk of medium, when a pull request for that stage is classified as high risk, then orchestration does not merge it and stops, naming the risk guardrail that halted the run.
- [ ] Given a work item whose requirements are unclear, when orchestration reaches a decision point that requires the unclear information, then it stops and names `unclear_requirements` (or the equivalent configured stop condition) as the cause and states the human action required.
- [ ] Given guardrails that require audit evidence, when a delegated merge or block decision is made for a pull request, then an audit record exists for the reviewed change covering the original command, resolved scope, effective guardrails, risk rationale, reviewer and CI outcome, and final decision; a rerun updates the existing record rather than creating a duplicate.
- [ ] Given an unreadable or internally contradictory guardrails configuration, when orchestration loads guardrails at run start, then it stops before any artifact-mutating action and reports the configuration problem as the stop cause.
- [ ] The enforcement behaviors above are verifiable using the existing reviewer-loop and CI-gate infrastructure: an allowed merge, a blocked merge for missing evidence, a high-risk stop, an unclear-requirements stop, and the backlog-start policy can each be exercised through the existing test harness without new external services.

---

## Out of Scope (MVP)

- Defining the guardrails configuration schema, modes, field names, or default values — that is owned by #979 (this spec reads the configuration and documents which fields and modes it consumes).
- Making `/run-work` adapt to no target, one item, multiple items, or epic-like input — that is owned by #978 (the adaptive entrypoint).
- Removing or deprecating the underlying portfolio, item, or epic protocols, or the `/run-item-work` and `/run-epic` commands.
- Changing default repository behavior to allow autonomous backlog starts; existing repositories keep confirmation-gated starts unless they opt in.
- Weakening any existing human-stop condition for unclear requirements, architecture choices, failing CI, unresolved blocking review, high-risk changes, or destructive actions.
- Introducing a new audit record format or risk-classification model distinct from the existing `/run-epic` helpers.
- Cross-repository (`workflow_hub` / `product_repo`) guardrail-scoping behavior beyond the repository-mode ownership rules already enforced by orchestration.
