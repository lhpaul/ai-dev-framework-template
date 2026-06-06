# Doc PR Quality Gate — Spec

---

## Overview

Spec and plan pull requests can spend hours cycling through automated document
review when the first submitted draft has avoidable gaps. This feature adds an
agent-facing quality gate before document PRs are submitted, so spec and plan
authors verify the most common review concerns while the context is still local.
The goal is to reduce repeated review cycles without weakening the existing
human-review and automated-review requirements.

## Brief Objective List

1. Reduce wall-clock latency caused by repeated Codex review cycles on spec and
   plan PRs.
2. Add a pre-PR self-review or quality gate for document authors before they
   open spec or plan PRs.
3. Ensure the gate checks the recurring high-value review categories called out
   in the brief, including API-surface gaps, concurrency correctness,
   naming/casing consistency, and single-snapshot semantics.
4. Preserve the existing review loop as the source of truth after a PR is
   opened.
5. Document operator expectations for long document-review cycles when they
   still occur.

## Use Cases

### Use Case 1: Spec or plan author submits a higher-quality document PR

**Actor**: Workflow agent writing a spec or implementation plan
**Preconditions**: A tracker item is approved to enter the spec or plan stage.

**Steps**:

1. The agent drafts the spec or implementation plan from the tracker brief and
   repository workflow guidance.
2. Before opening the draft PR, the agent performs the document quality gate.
3. The agent records the completed gate in the PR description.
4. The agent opens the draft PR and proceeds through the normal internal and
   automated reviewer flow.

**Postconditions**: The PR includes evidence that the author checked the most
common document-review failure modes before submission.

**Information shown**:

- A concise quality-gate log in the PR description.
- Any items the author intentionally deferred or marked not applicable.

**Actions available**:

- Reviewers can use the quality-gate log to focus on substantive remaining
  gaps instead of rediscovering basic omissions.
- The orchestrator can continue using the normal reviewer-loop result as the
  readiness signal.

**Considerations**:

- The quality gate must not be treated as a replacement for automated review.
- The quality gate should be short enough that agents reliably complete it.

### Use Case 2: Operator understands why a document PR is still cycling

**Actor**: Human workflow operator or portfolio orchestrator
**Preconditions**: A spec or plan PR continues to require multiple automated
review cycles after the quality gate was completed.

**Steps**:

1. The operator reviews the PR's quality-gate log and reviewer-loop summary.
2. The operator compares the remaining findings against the known document
   review categories.
3. The operator decides whether the loop is making useful progress, should
   continue, or should be escalated for human judgement.

**Postconditions**: Long-running document review cycles have visible context
for why they are continuing.

**Information shown**:

- The completed pre-submission quality gate.
- The automated reviewer-loop summary and any remaining findings.

**Actions available**:

- Continue the review loop when findings are substantive.
- Escalate when the loop has stopped making progress.

**Considerations**:

- The workflow should set realistic expectations for document PR review
  latency without normalizing poor first-pass quality.

## Business Rules

- A spec or plan PR must not be opened until its author has completed the
  applicable document quality gate.
- The quality gate must require a second-pass read of the document before PR
  creation.
- The quality gate must cover brief completeness, internal consistency,
  naming/casing consistency, behavioral guarantee clarity, and known
  high-signal reviewer categories.
- The quality gate must allow an item to be marked not applicable only when the
  reason is visible in the PR description or document.
- Completing the quality gate does not exempt the PR from internal review,
  automated review, CI, or human review.
- If a document PR still requires repeated cycles after the gate, the workflow
  must make the prior gate result and remaining review context visible enough
  for an operator to decide whether to continue or escalate.

## Operational Visibility

- **PR description**: Each spec or plan PR includes a completed quality-gate log
  with checked categories and any not-applicable rationale.
- **Reviewer-loop summary**: Existing automated reviewer-loop summaries remain
  the source of truth for post-submission review outcome.
- **Escalation summary**: If a document PR is escalated for review-loop
  latency, the summary references both the quality-gate log and the remaining
  reviewer findings.

## Acceptance Criteria

- [ ] AC1: A spec author following the workflow is instructed to complete a
      pre-submission document quality gate before opening a spec PR.
- [ ] AC2: A plan author following the workflow is instructed to complete a
      pre-submission document quality gate before opening an implementation
      plan PR.
- [ ] AC3: The gate includes checks for brief coverage, internal consistency,
      naming/casing consistency, behavioral guarantees, and the recurring
      high-value review categories from the brief.
- [ ] AC4: The PR description for a spec or plan PR includes a quality-gate log
      or equivalent visible evidence before the PR can proceed to readiness.
- [ ] AC5: The workflow states that the quality gate does not replace the
      internal review gate, automated reviewer loop, CI, or human review.
- [ ] AC6: The workflow documents how operators should interpret long
      spec/plan review cycles after the gate has already been completed.
- [ ] AC7: The implementation preserves normal reviewer-loop readiness rules
      for spec and plan PRs.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Reduce wall-clock latency caused by repeated Codex review cycles on spec and plan PRs. | AC1, AC2, AC3, AC4 |
| Add a pre-PR self-review or quality gate for document authors before they open spec or plan PRs. | AC1, AC2, AC4 |
| Ensure the gate checks recurring high-value review categories. | AC3 |
| Preserve the existing review loop as the source of truth after a PR is opened. | AC5, AC7 |
| Document operator expectations for long document-review cycles when they still occur. | AC6 |

## Out of Scope (MVP)

- Replacing Codex, PR-Agent, Haystack, Claude Code Action, or any other
  configured automated reviewer.
- Changing reviewer timeout budgets or polling intervals.
- Implementing an automatic reviewer-score prediction system.
- Requiring every document PR to reach a fixed maximum number of review cycles;
  the workflow should reduce avoidable cycles, not hide substantive findings.
