# Residual Verification Before Closing Epic Sub-items - Spec

---

## Overview

Epic sub-items that describe sweep or batch work need an explicit completion check before the workflow marks them ready for human review. This feature adds a product-level scope-residual gate to the item and epic workflow so agents must show that the stated sweep scope is complete, or that any remaining scope is intentionally tracked before handoff. The goal is to prevent partial sweep completion, dead helper work, and closure of under-delivered sub-items that only a later human audit would catch.

## Brief Objective List

- **BO-1**: Identify sweep or batch sub-items whose issue brief states a broad scope, such as cleaning many occurrences, refactoring across a codebase, or extracting multiple helpers.
- **BO-2**: Before applying `ready-for-human-review` or otherwise closing a sweep or batch sub-item, require residual verification that matches the issue's stated scope.
- **BO-3**: For occurrence-based work, show whether any in-scope occurrences, files, or clusters remain.
- **BO-4**: For helper-extraction work, flag helper outputs that appear to have no callers before the sub-item can be considered complete.
- **BO-5**: When residuals remain, block closure unless the residuals are explicitly outside scope or tracked in a linked follow-up issue.
- **BO-6**: Emit a human-readable residual summary that reports remaining work and the required disposition.
- **BO-7**: Reduce reliance on suspicion-triggered human grep audits before higher-risk work continues.

## Use Cases

### Use Case 1: Agent verifies a sweep sub-item before handoff

**Actor**: Work Item Runner or Epic Runner
**Preconditions**: A workflow item is in progress, belongs to an epic or batch context, and its title or brief describes sweep-style work with a broad target scope.

**Steps**:

1. The runner reaches the point where it would normally mark the item ready for human review.
2. The runner recognizes that the item describes sweep or batch completion scope.
3. The runner performs residual verification against the stated scope.
4. The runner records the verification evidence in the PR or terminal summary.
5. If no residuals remain, the runner continues the normal readiness flow.

**Postconditions**: The item cannot be handed off as complete without visible evidence that the broad scope was checked.

**Information shown**:

- Scope that was checked.
- Residual verification result.
- Remaining residual count or "none found" outcome.
- Where the evidence is recorded.

**Actions available**:

- Continue to readiness when residuals are clear.
- Stop and report residuals when work remains.

**Considerations**:

- The runner must not treat ordinary CI or automated review success as proof that the sweep scope was fully covered.
- The gate applies to workflow completion behavior; it does not change human review or merge authority.

### Use Case 2: Residuals remain after a partial sweep

**Actor**: Work Item Runner or Epic Runner
**Preconditions**: A sweep or batch sub-item still has in-scope residuals when the runner reaches completion.

**Steps**:

1. The runner detects remaining in-scope residuals.
2. The runner checks whether each residual group is explicitly out of scope or tracked in a linked follow-up issue.
3. If any residual group lacks a disposition, the runner blocks readiness.
4. The runner emits a summary explaining the remaining residuals and the required human or agent action.

**Postconditions**: The sub-item remains in a fixable state until residuals are addressed or deliberately tracked.

**Information shown**:

- Number or grouping of remaining residuals.
- Which residuals are missing a disposition.
- Required action: finish the residual work, link a follow-up issue, or document why the residuals are outside scope.

**Actions available**:

- Continue implementation work to eliminate residuals.
- Create or link a follow-up issue for deferred residuals.
- Escalate to the human when the original scope is ambiguous.

**Considerations**:

- A residual cannot be silently deferred in prose without a linked follow-up or explicit out-of-scope rationale.
- The runner should preserve the existing workflow stage and avoid moving the item to human-ready status until the residual disposition is complete.

### Use Case 3: Helper extraction creates unused helper outputs

**Actor**: Work Item Runner or Epic Runner
**Preconditions**: A workflow item asks for helper extraction, shared-helper creation, or similar reuse-oriented work.

**Steps**:

1. The runner reaches the completion gate for the helper-extraction item.
2. The runner verifies whether created helper outputs appear to be used by the intended consuming scope.
3. If helper outputs appear unused, the runner flags them as residual completion risk.
4. The runner blocks readiness until the unused helper risk is resolved, tracked, or explicitly accepted as outside the item scope.

**Postconditions**: The workflow does not mark helper extraction complete when the produced helpers appear to be dead work.

**Information shown**:

- Helper outputs that appear unused.
- Expected disposition for each unused helper risk.
- Whether the item can continue to readiness.

**Actions available**:

- Connect the helper outputs to their intended callers.
- Remove or revise unused helper outputs.
- Track remaining migration work in a linked follow-up issue.

**Considerations**:

- This gate is a completion-scope check, not a guarantee of perfect semantic dead-code detection.
- When the intended caller scope is ambiguous, the runner should escalate before readiness instead of inventing a disposition.

## Business Rules

- **BR-1**: The scope-residual gate must run before a sweep or batch sub-item is marked ready for human review or otherwise reported as complete.
- **BR-2**: A sweep or batch sub-item is in scope for this gate when the issue title or brief states broad completion language, such as "all", "across", a numeric target count, a codebase-wide cleanup, a batch extraction, or multiple named targets.
- **BR-3**: Passing CI, automated review, or an internal review gate is not sufficient evidence that sweep scope is complete.
- **BR-4**: The residual verification evidence must be visible to a human reviewer in the PR, workflow comment, or terminal summary.
- **BR-5**: If residuals remain, each residual group must have one of these dispositions before readiness: completed now, explicitly outside scope, or tracked in a linked follow-up issue.
- **BR-6**: If any in-scope residual has no disposition, the runner must block readiness and report the item as needing fixes or human decision.
- **BR-7**: Helper-extraction items must surface apparently unused helper outputs as residual risk before readiness.
- **BR-8**: The runner must avoid closing or marking a sub-item ready based only on a statement that "the rest is deferred" unless the deferred work is linked or clearly outside the approved scope.
- **BR-9**: When the residual scope cannot be determined from the issue brief, the runner must escalate the ambiguity rather than guessing that the item is complete.

## Operational Visibility

- **Completion evidence**: The workflow records the checked scope, residual result, and disposition in a stable location visible during PR review or item handoff.
- **Blocked readiness**: When the gate blocks readiness, the summary names the residual groups and the exact unblock path.
- **Follow-up traceability**: Linked follow-up issues must be visible alongside the residual summary so humans can confirm that remaining work was not silently dropped.
- **Batch and epic auditability**: Epic-level summaries should make it clear which sub-items passed residual verification and which were blocked or deferred with linked follow-up work.

## Acceptance Criteria

- **AC-1**: Given a workflow item whose brief says to clean a stated class of occurrences across multiple files, when the runner reaches readiness, then the runner records residual verification evidence before applying `ready-for-human-review`.
- **AC-2**: Given a sweep item with no remaining in-scope residuals, when the residual gate runs, then the item can continue through the normal readiness flow and the summary states that no residuals were found.
- **AC-3**: Given a sweep item with remaining in-scope residuals and no linked follow-up issue or out-of-scope rationale, when the residual gate runs, then the runner does not apply `ready-for-human-review` and reports the remaining residuals as blocking.
- **AC-4**: Given a sweep item with remaining residuals that are linked to a follow-up issue, when the residual gate runs, then the item can continue only if the summary lists the linked follow-up and distinguishes the deferred residuals from completed scope.
- **AC-5**: Given a helper-extraction item that creates helper outputs with no apparent callers, when the residual gate runs, then the runner flags the unused helper outputs before readiness and requires completion, follow-up tracking, or explicit out-of-scope rationale.
- **AC-6**: Given an item whose stated scope includes a target count, when the residual summary is produced, then it reports the checked target and remaining count or grouping in human-readable form.
- **AC-7**: Given an item whose sweep scope is ambiguous, when the runner reaches the residual gate, then the runner escalates for a human decision instead of marking the item complete.
- **AC-8**: Given an epic or batch summary containing sweep or batch sub-items, when the summary is produced, then each applicable sub-item shows whether residual verification passed, blocked readiness, or continued with a linked follow-up disposition.

## Coverage Matrix

| Brief objective | Covered by | Notes |
| --- | --- | --- |
| BO-1 | BR-2, AC-1, AC-8 | Defines which broad-scope sub-items must enter the gate. |
| BO-2 | BR-1, BR-3, AC-1 | Requires verification before readiness or completion. |
| BO-3 | BR-4, AC-2, AC-3, AC-6 | Requires visible occurrence/file residual evidence. |
| BO-4 | BR-7, AC-5 | Covers unused helper outputs before closure. |
| BO-5 | BR-5, BR-6, BR-8, AC-3, AC-4 | Blocks silent deferral and requires linked or explicit disposition. |
| BO-6 | BR-4, Operational Visibility, AC-6, AC-8 | Requires the residual summary to be human-readable and auditable. |
| BO-7 | BR-3, Operational Visibility, AC-8 | Makes residual verification part of the workflow rather than relying on ad hoc human audits. |

## Out of Scope (MVP)

- Building a perfect semantic code-understanding engine for every language or framework.
- Defining the exact implementation mechanism for search, static analysis, or caller detection; the implementation plan will choose the appropriate tooling and integration points.
- Changing human review, merge authority, or guardrail policy beyond blocking readiness when residual evidence is missing or incomplete.
- Automatically creating follow-up issues without the workflow already having authority to create backlog items.

