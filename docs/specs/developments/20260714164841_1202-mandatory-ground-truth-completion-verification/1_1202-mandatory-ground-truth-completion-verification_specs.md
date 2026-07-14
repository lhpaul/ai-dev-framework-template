# Mandatory Ground-Truth Completion Verification - Spec

---

## Overview

Workflow operators need item completion reports to prove the current state of
the repository, worktree, pull request, review, and CI surfaces before the agent
claims an item is done or waiting on a human. The workflow should require agents
to verify final claims against live ground truth instead of reporting from memory
or from the expected result of the last command they ran.

This feature adds a mandatory completion self-check expectation for Work Item
Runner item reports. The report must show current, direct evidence for the
claims it makes, and any mismatch between expected state and observed state must
be reported as a discrepancy rather than as success.

## Brief Objective List

Derived from issue #1202:

1. Require a completion self-check before any item completion or "done" report.
2. Verify branch state, current location, and current HEAD from direct repository
   evidence.
3. Verify worktree state, including signals that could reveal wrong-worktree or
   duplicate-worktree execution in parallel batches.
4. Verify pull request base branch, labels, readiness state, and changed files
   from the live PR surface rather than assumption.
5. Verify CI status from the current PR/check provider before reporting CI as
   passing, pending, or failed.
6. Require direct evidence for external-runtime or environment verification
   claims when an agent reports them.
7. Include raw or verbatim assertion evidence in the completion report in a
   human-auditable form.
8. Flag any disagreement between the agent's expected state and observed state
   to the parent orchestrator or human instead of reporting success.
9. Reduce human re-verification burden in bounded multi-item runs without
   changing merge authority or replacing existing review and CI gates.

## Use Cases

### Use Case 1: Work Item Runner reports a spec, plan, or implementation PR as human-ready

**Actor**: Work Item Runner.
**Preconditions**: The runner believes the item has reached a terminal state
such as ready for human review, blocked, escalated, or waiting on merge.

**Steps**:

1. The runner reaches the point where it would normally produce a final item
   report.
2. Before reporting, the runner performs a completion self-check against the
   current repository, worktree, PR, review, CI, and tracker surfaces that are
   relevant to the reported terminal state.
3. The runner records the observed values and raw evidence excerpts in the final
   report.
4. The runner compares observed values with the state it intends to claim.
5. The runner reports the item as ready only when the observed values support
   the claimed terminal state.

**Postconditions**: The final item report contains enough current evidence for a
human or parent orchestrator to audit the claim without re-running every
verification command from scratch.

**Information shown**:

- Current workflow branch and HEAD SHA.
- Current worktree or workspace location used for item work.
- PR number, base branch, draft/readiness state, labels, and changed-file
  summary when a PR exists.
- Current CI/check result for the PR head.
- Current review-loop and unresolved-review-thread status when those surfaces
  apply.
- Tracker transition attempted and live tracker status when tracker access is
  available.
- Raw or verbatim evidence for each asserted value, or a clearly labeled
  normalized provider value when a raw command transcript is not practical.

**Actions available**:

- Parent orchestrator or human accepts the report and proceeds with human review
  or merge outside this run.
- Parent orchestrator or human requests remediation when the report shows a
  discrepancy, missing evidence, or incomplete readiness.

**Considerations**:

- The self-check is evidence for the completion report; it does not replace the
  existing review, CI, readiness-label, tracker, or merge protocols.
- The report should stay concise enough for batch-level summaries while still
  preserving the ground-truth values behind each claim.

### Use Case 2: Self-check finds a discrepancy before the final report

**Actor**: Work Item Runner and parent orchestrator.
**Preconditions**: The runner expected one state, but direct verification finds a
different current state.

**Steps**:

1. The runner performs the completion self-check.
2. One or more observed values disagree with the intended claim, such as the
   wrong branch, unexpected changed files, missing label, unexpected PR base,
   pending CI, dirty main workspace, or missing tracker update.
3. The runner records the discrepancy with expected and observed values.
4. The runner reports the item as incomplete, blocked, or escalated according to
   the affected workflow gate instead of reporting success.

**Postconditions**: The parent orchestrator or human sees the discrepancy before
the batch is considered complete.

**Information shown**:

- The exact claim that failed verification.
- The expected value and observed value.
- The surface used as ground truth.
- The next action required to continue.

**Actions available**:

- Fix the discrepancy and re-run the relevant workflow gate.
- Escalate to the human when the discrepancy requires a decision or external
  access.
- Leave unrelated items in the batch untouched.

**Considerations**:

- Discrepancy reporting must not silently downgrade evidence into a vague warning
  after the report has already said the item is done.
- If the observed state is ambiguous because a provider is unavailable, the
  report must say the claim is unverified rather than successful.

### Use Case 3: Parallel batch operator audits item completion without re-running every check

**Actor**: Portfolio Orchestrator or human operator supervising a bounded
multi-item run.
**Preconditions**: Multiple Work Item Runners are executing in parallel and each
runner returns a terminal report.

**Steps**:

1. The parent orchestrator receives a completion report from an item runner.
2. The report includes current branch, worktree, PR, CI, review, and tracker
   evidence relevant to the item.
3. The parent orchestrator compares the report against batch expectations, such
   as item scope, branch name, PR base, final labels, and readiness state.
4. The parent orchestrator accepts the item as terminal only when the report
   contains ground-truth evidence and no unresolved discrepancy.

**Postconditions**: Batch-level status is based on verified current state rather
than agent self-belief.

**Information shown**:

- Item identifier and branch.
- Worktree path used by the runner.
- PR URL or number when present.
- Current PR readiness evidence.
- Any missing or not-applicable evidence with rationale.

**Actions available**:

- Aggregate the item into the batch summary.
- Redispatch the item if a fixable discrepancy remains.
- Escalate the item if the required evidence cannot be collected.

**Considerations**:

- Reports must make scope contamination visible, especially when PR changed
  files include paths outside the assigned issue's expected artifact set.
- The parent orchestrator should not have to infer whether a claim was verified;
  verified, not applicable, and unavailable states must be explicit.

### Use Case 4: Agent reports external runtime or environment verification

**Actor**: Stage agent or Work Item Runner.
**Preconditions**: The agent wants to claim that a runtime, database, browser,
deployment, or other external environment was verified.

**Steps**:

1. The agent performs the external verification needed for the claim.
2. The completion self-check records the live evidence source and observed
   result.
3. If the agent cannot perform the external check, it marks that claim as not
   verified and explains why.

**Postconditions**: Runtime or environment claims are traceable to observed
evidence, or they are clearly marked as unverified.

**Information shown**:

- The environment or surface checked.
- The current observed result.
- Any limitation that prevented verification.

**Actions available**:

- Human accepts the external verification evidence.
- Human performs the missing verification when access or credentials are not
  available to the agent.

**Considerations**:

- The feature does not require every item to perform external runtime checks; it
  requires that any external-runtime claim included in a completion report be
  backed by direct evidence.

## Business Rules

- **BR-1**: A Work Item Runner must not produce a final item completion report
  until it has performed the mandatory completion self-check for the surfaces
  relevant to the claimed terminal state.
- **BR-2**: Completion evidence must come from current ground-truth sources, not
  from memory, prior status text, expected command effects, or stale helper
  output.
- **BR-3**: Every final report claim about branch, HEAD, worktree, PR, labels,
  CI, review, tracker, or external runtime state must be either verified with
  raw or verbatim observed evidence, not applicable, or unavailable with a
  reason.
- **BR-4**: PR-related completion reports must verify the PR base branch,
  draft/readiness state, label list, current CI/check state, and changed-file
  scope from the live PR surface.
- **BR-5**: Repository-related completion reports must verify the branch,
  current HEAD, and workspace/worktree location used for the item.
- **BR-6**: Parallel batch completion reports must include enough worktree
  evidence to detect wrong-worktree execution, duplicate worktree confusion, or
  main workspace drift when those risks apply.
- **BR-7**: If observed ground truth disagrees with the intended final claim,
  the runner must report a discrepancy with expected and observed values and
  must not label the item successful.
- **BR-8**: If a required ground-truth surface is unavailable, the runner must
  report the surface as unavailable and explain whether the item is blocked,
  escalated, or still safe to hand off.
- **BR-9**: The completion self-check must not grant merge authority, skip human
  review, or weaken existing review, CI, readiness-label, tracker, or guardrails
  gates.
- **BR-10**: The exact command sequence, helper implementation, report
  serialization, and protocol-file edit plan are implementation-plan decisions.

## Operational Visibility

- **Completion report evidence**: Final item reports should include a dedicated
  ground-truth verification section with raw or verbatim observed evidence,
  observed values, and a pass, discrepancy, not-applicable, or unavailable result
  per checked surface.
- **Discrepancy visibility**: Any discrepancy should be prominent in the final
  report and should identify the next required human or orchestrator action.
- **Batch visibility**: In bounded multi-item runs, the parent summary should be
  able to quote or link each item's completion self-check result instead of
  requiring humans to reconstruct the state manually.
- **Review visibility**: Reviewers should be able to verify that implementation
  updates add the completion self-check requirement without treating this spec as
  a mandate for a particular script or command shape.

## Acceptance Criteria

- [ ] **AC1**: The workflow requires a completion self-check before any Work
      Item Runner report claims an item is ready, done, blocked, escalated, or
      waiting on a human.
- [ ] **AC2**: A completion report for an item with a PR includes raw or
      verbatim evidence for current branch, HEAD SHA, worktree/workspace
      location, PR number, PR base branch, draft/readiness state, labels,
      changed-file summary, and CI/check status.
- [ ] **AC3**: A completion report for an item without a PR still includes
      current branch, HEAD SHA, worktree/workspace location, tracker status when
      available, and an explanation for why PR fields are not applicable.
- [ ] **AC4**: PR readiness claims are verified from live PR/check surfaces and
      cannot rely solely on prior agent status messages or the expected outcome
      of previous commands.
- [ ] **AC5**: If a self-check finds an unexpected branch, unexpected PR base,
      missing readiness label, unexpected changed file, non-green CI, unresolved
      review state, dirty workspace, or unavailable required surface, the report
      flags a discrepancy and does not claim successful completion.
- [ ] **AC6**: Completion reports mark each checked surface as verified, not
      applicable, or unavailable, and include raw/verbatim evidence for verified
      surfaces plus a short rationale when unavailable or not applicable.
- [ ] **AC7**: Parallel batch item reports include worktree evidence sufficient
      for the parent orchestrator to confirm the assigned worktree and branch
      were used.
- [ ] **AC8**: External runtime, database, browser, deployment, or environment
      claims in a completion report include direct observed evidence, or are
      explicitly marked not verified.
- [ ] **AC9**: The workflow documentation or smoke-test coverage includes a
      scenario where a completion self-check detects a mismatch and reports a
      discrepancy instead of success.
- [ ] **AC10**: Existing review, CI, readiness-label, tracker, and guardrails
      gates remain in force; the new completion self-check is an additional
      reporting requirement, not a replacement gate.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Require a completion self-check before any item completion or "done" report | AC1, BR-1 |
| 2. Verify branch state, current location, and current HEAD from direct repository evidence | AC2, AC3, BR-5 |
| 3. Verify worktree state and wrong-worktree/duplicate-worktree risks | AC2, AC3, AC7, BR-6 |
| 4. Verify PR base, labels, readiness, and changed files from live PR state | AC2, AC4, AC5, BR-4 |
| 5. Verify CI status from the current PR/check provider | AC2, AC4, AC5 |
| 6. Require direct evidence for external-runtime or environment claims | AC8 |
| 7. Include raw or verbatim assertion evidence in a human-auditable form | AC2, AC3, AC6, BR-3 |
| 8. Flag disagreement to the parent orchestrator or human instead of reporting success | AC5, AC9, BR-7 |
| 9. Reduce human re-verification burden without changing merge authority or replacing gates | AC10, Use Case 3, BR-9 |

## Out of Scope (MVP)

- Defining the exact helper script names, command sequence, JSON schema, or
  shell implementation for the completion self-check; those belong in the
  implementation plan.
- Replacing existing review, CI, readiness-label, tracker, guardrails, or merge
  gates.
- Granting any new merge authority or changing the human-review requirement.
- Retroactively rewriting historical agent reports or closed PRs.
- Requiring external-runtime verification for every item regardless of scope;
  the requirement applies when the completion report makes an external-runtime
  or environment claim.
- Full automation for every possible tracker provider in the first iteration;
  unsupported provider evidence may be reported as unavailable with rationale.
