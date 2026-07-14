# May-Merge Policy Terminal Behavior - Spec

---

## Overview

Workflow operators use `/run-item`, `/run-items`, and `/run-epic` to delegate
review and merge work under explicit guardrails. Today, the meaning of a
`--may-merge` grant is not consistently understood by every runner: some agents
stop once a PR is labeled ready, while others continue through the actual merge
and cleanup. This feature makes the policy contract observable and
unambiguous: when merge authority is granted and all gates pass, "ready" is an
intermediate state and the runner continues to merge; when merge authority is
absent, "ready" is the terminal human handoff.

## Brief Objective List

Derived from issue #1177:

1. Make the `--may-merge` grant semantically unambiguous for item runners and
   batch/epic orchestrators.
2. Define that when merge authority is granted, applying readiness labels is not
   the terminal state; the runner continues to execute the approved merge path.
3. Define that when merge authority is not granted, the runner applies readiness
   labels and stops without merging.
4. Express the behavior as an explicit conditional in dispatch and workflow
   instructions rather than relying on implicit agent interpretation.
5. Remove the need for an orchestrator or human to manually identify PRs that
   stalled at "merge-ready" during a delegated merge run.
6. Preserve normal readiness, guardrail, risk, review, CI, cleanup, and tracker
   verification gates before any merge happens.

---

## Use Cases

### Use Case 1: Runner has merge authority and completes the merge

**Actor**: Work Item Runner or Portfolio Orchestrator advancing an in-scope PR
with delegated merge authority.
**Preconditions**: The invocation policy grants merge authority for the PR's
workflow stage, the PR belongs to the resolved scope, and all required review,
CI, readiness, risk, setup, and tracker gates are eligible to pass.

**Steps**:

1. The runner advances the PR through the normal internal review, automated
   reviewer, CI, and readiness checks.
2. The runner applies the readiness labels that mark the PR as automation-clean.
3. The runner treats that ready state as an intermediate milestone because merge
   authority is granted.
4. The runner performs the delegated merge gate and records the merge decision
   evidence required by the workflow.
5. If the gate permits merge, the runner executes the approved repository merge
   path, verifies the PR is merged, performs branch cleanup, and verifies the
   tracker status expected after merge.

**Postconditions**: The PR is merged and cleanup/tracker verification has
completed, or the runner reports the exact gate that blocked merge. The runner
does not stop merely because readiness labels were applied.

**Information shown**:

- The selected merge authority and its source.
- The PR readiness evidence used before merge.
- The delegated merge gate result.
- The final merge, cleanup, and tracker verification outcome.
- If merge is blocked, the named blocker and human action required to unblock.

**Actions available**:

- Continue through the merge when all gates pass.
- Apply deterministic fixes and rerun readiness gates when a fixable blocker is
  found.
- Stop for human action when policy, risk, setup, review, CI, merge state, or
  tracker evidence blocks merge.

**Considerations**:

- Readiness labels remain useful audit signals, but they do not complete a
  merge-authorized run.
- A runner must not widen the authority beyond the selected policy; only the
  resolved in-scope PRs are eligible.

### Use Case 2: Runner lacks merge authority and stops at human handoff

**Actor**: Work Item Runner or Portfolio Orchestrator advancing an in-scope PR
without delegated merge authority.
**Preconditions**: The invocation policy or repository guardrails do not grant
merge authority for the PR's workflow stage.

**Steps**:

1. The runner advances the PR through the normal internal review, automated
   reviewer, CI, and readiness checks.
2. The runner applies readiness labels once the PR is automation-clean.
3. The runner reports that merge authority is absent and stops at the human
   review/merge handoff.
4. The final summary names the exact policy value that prevents an automated
   merge and the expected next human action.

**Postconditions**: The PR is ready for human review or merge, remains unmerged,
and the runner does not attempt a merge command.

**Information shown**:

- The selected merge authority and its source.
- The readiness evidence proving the PR is ready for human action.
- The exact guardrail or invocation policy that prevents delegated merge.
- The recommended next action, such as invoking the merge workflow or rerunning
  with explicit merge authority.

**Actions available**:

- Human reviews and merges the PR through the normal merge workflow.
- Human reruns with merge authority if the repository policy allows it.
- Runner resumes later if review, CI, or tracker state changes.

**Considerations**:

- This is the expected terminal state for two-step workflows where execution and
  merge are intentionally separate.
- The runner must not phrase the stop as a merge-ready completion when the
  operator expected an automated merge.

### Use Case 3: Batch or epic run keeps policy behavior consistent across agents

**Actor**: Portfolio Orchestrator or Epic Orchestrator dispatching multiple item
runners in one approved scope.
**Preconditions**: A bounded batch or epic run has a selected policy that either
grants or denies merge authority for the affected stages.

**Steps**:

1. The orchestrator passes the selected merge authority into every item handoff
   using explicit language for the granted and denied cases.
2. Each item runner follows the same terminal-state contract for its PR.
3. The orchestrator's final batch or epic summary distinguishes PRs merged by
   delegated authority from PRs ready for human merge because authority was
   absent.
4. If any runner stops before the expected terminal state, the orchestrator
   reports the named gate that stopped it, or reports `policy_inconsistent` when
   no valid blocker explains the stop.

**Postconditions**: Agents in the same batch do not interpret the same
`--may-merge` policy differently. The batch has a coherent final state:
merged, ready for human merge, blocked, or escalated for each in-scope PR.

**Information shown**:

- Selected merge policy for the batch or epic.
- Per-PR terminal state and whether merge was expected.
- Any item that stopped before the policy's expected terminal state.

**Actions available**:

- Continue delegated merge for PRs whose policy and gates permit it.
- Stop at human handoff for PRs whose policy denies merge.
- Escalate inconsistent or missing policy evidence.

**Considerations**:

- The policy wording must be durable enough for different agent surfaces to
  follow without extra ad hoc instructions from the orchestrator.

### Use Case 4: Maintainer updates command and protocol surfaces consistently

**Actor**: Template maintainer.
**Preconditions**: The framework changes instructions that describe delegated
merge behavior.

**Steps**:

1. The maintainer updates the canonical workflow protocols that define item,
   batch, and epic terminal behavior.
2. The maintainer updates supported command and skill surfaces that dispatch
   item runners.
3. The maintainer verifies the surfaces use the same granted-versus-denied merge
   wording.

**Postconditions**: Codex, Claude, Cursor, and shared workflow documentation
teach the same terminal behavior for merge-authorized and merge-denied runs.

**Information shown**:

- Which surfaces received the policy wording.
- The condition under which a runner must merge.
- The condition under which a runner must stop for humans.

**Actions available**:

- Invoke any supported workflow surface and receive consistent behavior.
- Compare command wrappers against the canonical protocol language.

**Considerations**:

- Wrapper text should remain thin and should not create a second policy model.

---

## Business Rules

- BR1: A selected policy that grants merge authority means readiness labels are
  not terminal. After readiness is achieved, the runner must continue to the
  delegated merge gate and approved merge path for every in-scope PR whose gates
  pass.
- BR2: A selected policy that denies merge authority means readiness labels are
  terminal for that run. The runner must not execute a merge and must report the
  exact policy value that requires human merge.
- BR3: The workflow must express the merge-authority decision as an explicit
  conditional with separate granted and denied instructions in runner handoffs,
  command wrappers, or protocols that dispatch item work.
- BR4: The granted-merge path must still satisfy the normal readiness and
  safety gates before merge: internal review, automated reviewer loop, CI,
  readiness labels, unresolved-review checks, setup blockers, merge state, risk
  classification, delegated gate, cleanup, and tracker verification as
  applicable to the PR type.
- BR5: A runner must not treat "ready-for-human-review", "ready-for-regression",
  "merge-ready", or equivalent readiness wording as a substitute for executing
  the merge when merge authority is granted and gates pass.
- BR6: A runner must not execute a merge when merge authority is absent, even if
  the PR is ready, low risk, and otherwise mergeable.
- BR7: Batch and epic orchestrators must report inconsistent terminal behavior.
  If a named gate blocks the expected terminal state, the outcome is
  `merge_blocked` or escalated with that blocker; if no valid blocker explains
  the mismatch, the outcome is `policy_inconsistent`.
- BR8: The final summary for each affected PR must state whether merge was
  granted or denied, what terminal state was expected, and what terminal state
  was reached.
- BR9: The policy applies only to resolved in-scope PRs. It must not authorize
  opportunistic merges for out-of-scope PRs discovered during the run.
- BR10: The behavior must be consistent across supported agent surfaces that
  invoke the same workflow path.

---

## Statuses / Enum Values

### Merge authority states

| Code value      | Display label        | Description |
| --------------- | -------------------- | ----------- |
| `merge_granted` | Merge granted        | The selected policy authorizes the runner to merge in-scope PRs that pass all required gates. |
| `merge_denied`  | Merge not granted    | The selected policy does not authorize the runner to merge; ready PRs stop for human action. |

**Valid transitions**:

- `merge_granted` remains in effect for the selected invocation unless a later
  gate blocks, escalates, or narrows authority.
- `merge_denied` remains in effect unless the human starts a new invocation or
  explicitly adjusts the selected policy.

### PR terminal outcomes

| Code value              | Display label              | Description |
| ----------------------- | -------------------------- | ----------- |
| `merged`                | Merged                     | Merge authority was granted, all gates passed, the PR was merged, cleanup ran, and tracker verification completed or was reported. |
| `ready_human_merge`     | Ready for human merge      | Merge authority was absent; the PR is automation-clean and waiting for human review or merge. |
| `merge_blocked`         | Merge blocked              | Merge authority was granted, but a review, CI, risk, setup, merge-state, tracker, or delegated-gate blocker prevented merge. |
| `policy_inconsistent`   | Policy inconsistent        | A runner reached a terminal state that does not match the selected merge policy and no valid blocker was reported. |
| `out_of_scope`          | Out of scope               | The PR is not part of the resolved invocation scope and must not be merged by this run. |

**Valid transitions**:

- A ready PR with `merge_granted` advances to `merged` when all merge gates pass.
- A ready PR with `merge_granted` advances to `merge_blocked` when any required
  merge gate blocks.
- A ready PR with `merge_denied` advances to `ready_human_merge`.
- A PR may resolve to `policy_inconsistent` when the reported terminal state
  contradicts the selected policy and no named blocker explains the stop.
- `out_of_scope` is terminal for that PR in the current run.

---

## Operational Visibility

- **Policy display**: The run summary shows whether merge authority was granted
  or denied, the source of that value, and the stages it applies to.
- **Handoff wording**: Item-runner handoffs include explicit granted and denied
  instructions so the receiving agent knows whether readiness is intermediate or
  terminal.
- **Terminal-state audit**: Final reports distinguish `merged`,
  `ready_human_merge`, `merge_blocked`, `policy_inconsistent`, and
  `out_of_scope`.
- **Blocker evidence**: When merge authority is granted but merge does not
  happen, the runner names the exact gate and human action required.
- **Scope evidence**: Batch and epic summaries identify the in-scope PR list so
  merge authority cannot be applied to unrelated PRs.

---

## Acceptance Criteria

- [ ] AC1: Given a runner handoff where merge authority is granted, the handoff
      explicitly states that after readiness labels are applied, the runner must
      continue through the delegated merge gate and approved merge path rather
      than stop at readiness.
- [ ] AC2: Given a runner handoff where merge authority is not granted, the
      handoff explicitly states that the runner must apply readiness labels when
      eligible, stop, and not execute a merge.
- [ ] AC3: Given a merge-authorized in-scope PR with clean review, green CI,
      required labels, acceptable risk, no setup blocker, clean merge state, and
      passing delegated gate evidence, the workflow proceeds to merge, verifies
      the PR is merged, performs branch cleanup, and verifies or reports tracker
      status.
- [ ] AC4: Given a merge-authorized in-scope PR that reaches readiness but fails
      any required merge gate, the runner does not stop as "done"; it reports
      `merge_blocked`, names the failed gate, and states the human action needed
      to unblock.
- [ ] AC5: Given a merge-denied in-scope PR that reaches readiness, the runner
      reports `ready_human_merge`, names the policy value that denies merge, and
      does not call the repository merge path.
- [ ] AC6: Given multiple item runners in the same batch or epic with the same
      selected merge policy, every runner follows the same terminal-state
      contract for readiness and merge.
- [ ] AC7: Given an in-scope PR that stops at readiness during a
      merge-authorized run without a named blocker, the orchestrator identifies
      the outcome as `policy_inconsistent` rather than silently treating it as
      complete.
- [ ] AC8: Given an out-of-scope PR discovered during a merge-authorized run,
      the runner reports it as `out_of_scope` and does not merge it.
- [ ] AC9: Given supported command and skill surfaces for `/run-item`,
      `/run-items`, and `/run-epic`, their instructions use consistent wording
      for merge-granted and merge-denied terminal behavior.
- [ ] AC10: Given final run output for an affected PR, the summary states the
      selected merge authority, expected terminal state, actual terminal state,
      and any blocker or cleanup/tracker verification result.

---

## Out of Scope (MVP)

- Changing the guardrails schema or introducing a new merge-authority field.
- Weakening review, CI, risk, setup, merge-state, tracker, or delegated-gate
  requirements before merge.
- Allowing any automated merge when merge authority is absent.
- Defining a new merge strategy; the implementation must use the repository's
  existing approved merge path.
- Changing human review requirements for workflows that intentionally use the
  two-step execute-then-merge lifecycle.
- Adding new tracker statuses beyond the terminal outcome labels used in run
  summaries.
- Solving unrelated agent timeout, reviewer-loop, CI, or branch cleanup issues.

---

## Implementation Traceability

| Concern | Spec coverage |
| --- | --- |
| Granted merge authority continues past readiness | BR1, BR5, Use Case 1, AC1, AC3 |
| Denied merge authority stops at human handoff | BR2, BR6, Use Case 2, AC2, AC5 |
| Explicit conditional in dispatch wording | BR3, Use Cases 3-4, AC1-AC2, AC9 |
| Preserve readiness and safety gates | BR4, Use Case 1, AC3-AC4 |
| Prevent silent stalled-at-ready outcomes | BR7, Use Case 3, AC6-AC7 |
| Scope boundary for delegated merge | BR9, Use Case 3, AC8 |
| Consistent final summaries | BR8, Operational Visibility, AC10 |
| Cross-surface consistency | BR10, Use Case 4, AC9 |

---

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Make `--may-merge` semantically unambiguous | BR1-BR3, Use Cases 1-3, AC1-AC2, AC6 |
| 2. Merge authority means readiness labels are not terminal | BR1, BR5, Use Case 1, AC1, AC3 |
| 3. No merge authority means apply readiness and stop without merging | BR2, BR6, Use Case 2, AC2, AC5 |
| 4. Express behavior as an explicit conditional | BR3, Use Cases 3-4, AC1-AC2, AC9 |
| 5. Remove manual detection of stalled-at-ready delegated runs | BR7-BR8, Use Case 3, AC6-AC7, AC10 |
| 6. Preserve normal readiness and merge gates | BR4, Use Case 1, AC3-AC4 |

All brief objectives map to acceptance criteria; none are deferred to Out of
Scope, so no Deferral Notes are required.
