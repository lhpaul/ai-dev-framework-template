# Agents Add to Project Board — Spec

---

## Overview

Workflow agents (spec-writer, plan-writer, and developer) do not currently ensure that the issues they work on are registered on the GitHub Project board. This means issues created outside the orchestrator — for example, manually filed issues or issues added mid-session — can advance through multiple workflow stages without ever becoming visible to the portfolio orchestrator. This feature adds a board-membership check-and-add step to the completion sequence of each stage agent and to the pre-dispatch validation in the portfolio orchestrator, so that every item is guaranteed to be on the board before its status is updated or it is elected for dispatch.

---

## Use Cases

### Use Case 1: Spec-writer ensures board membership before marking spec complete

**Actor**: Spec-writer agent (automated)
**Preconditions**: The spec-writer has finished writing the spec and is about to push the branch and open the draft PR.

**Steps**:

1. The spec-writer checks whether the issue it is working on is already registered on the project board.
2. If the issue is not on the board, the spec-writer adds it and sets the initial status to "Writing Spec".
3. If the issue is already on the board, the spec-writer proceeds without modifying the existing board entry.
4. The spec-writer continues with pushing the branch and opening the draft PR.

**Postconditions**: The issue appears on the project board with at least "Writing Spec" status. The spec PR is open and visible to the portfolio orchestrator.

**Information shown**:

- A log line indicating whether the issue was added to the board or already present.

**Actions available**:

- None required from the human — the step is fully automated and non-blocking.

**Considerations**:

- If the board-add operation fails due to a permissions or API error, the agent logs a warning and continues — the board check must never block forward progress on the spec itself.
- The check must be idempotent: running it multiple times does not create duplicate board entries.

---

### Use Case 2: Plan-writer ensures board membership before marking plan complete

**Actor**: Plan-writer agent (automated)
**Preconditions**: The plan-writer has finished writing the implementation plan and is about to push the branch and open the draft PR.

**Steps**:

1. The plan-writer checks whether the issue is already registered on the project board.
2. If the issue is not on the board, the plan-writer adds it and sets the initial status to "Writing Plan".
3. If the issue is already on the board, the plan-writer proceeds without modifying the existing board entry.
4. The plan-writer continues with pushing the branch and opening the draft PR.

**Postconditions**: The issue appears on the project board with at least "Writing Plan" status. The plan PR is visible to the portfolio orchestrator.

**Information shown**:

- A log line indicating whether the issue was added to the board or already present.

**Actions available**:

- None required from the human.

**Considerations**:

- Same idempotency and fail-open rules as Use Case 1.

---

### Use Case 3: Developer agent ensures board membership before marking implementation complete

**Actor**: Developer agent (automated)
**Preconditions**: The developer agent has finished implementing the feature and is about to push the branch and open the draft PR.

**Steps**:

1. The developer checks whether the issue is already registered on the project board.
2. If the issue is not on the board, the developer adds it and sets the initial status to "In Development".
3. If the issue is already on the board, the developer proceeds without modifying the existing board entry.
4. The developer continues with pushing the branch and opening the draft PR.

**Postconditions**: The issue appears on the project board with at least "In Development" status. The implementation PR is visible to the portfolio orchestrator.

**Information shown**:

- A log line indicating whether the issue was added to the board or already present.

**Actions available**:

- None required from the human.

**Considerations**:

- Same idempotency and fail-open rules as Use Cases 1 and 2.

---

### Use Case 4: Portfolio orchestrator guarantees board membership before dispatching any item

**Actor**: Portfolio orchestrator agent (automated)
**Preconditions**: The portfolio orchestrator has elected one or more items for dispatch during Step 2.5 (pre-dispatch validation).

**Steps**:

1. For each elected item, the portfolio orchestrator checks whether the item is registered on the project board.
2. If the item is not on the board, the orchestrator adds it and sets the initial status appropriate to the stage it is about to dispatch (e.g., "Writing Spec" for a spec dispatch).
3. If the item is already on the board, the orchestrator proceeds with the normal status update.
4. The orchestrator continues with dispatch as normal.

**Postconditions**: Every item dispatched by the portfolio orchestrator is registered on the project board before its status is updated.

**Information shown**:

- A log line per item indicating whether it was added to the board or already present.

**Actions available**:

- None required from the human.

**Considerations**:

- If the board-add fails (e.g., API rate limit or insufficient permissions), the orchestrator logs a warning and continues the dispatch — the board check is a best-effort registration step, not a hard gate.
- This use case is the safety net: it catches any items that slipped past the per-agent checks in Use Cases 1–3.

---

## Business Rules

- The board membership check must run before any tracker status update is attempted in the agent completion sequence. A status update on an item that is not on the board silently fails or creates inconsistency.
- Adding an item to the board is always idempotent: if the item is already present, no action is taken and no error is raised.
- The board-add step is fail-open: an API or permissions failure must not block the agent from completing its primary task (writing the spec, plan, or implementation and opening the PR).
- The initial status set when adding a new board item must match the stage that is completing: "Writing Spec" for spec agents, "Writing Plan" for plan agents, "In Development" for developer agents.
- When the portfolio orchestrator adds an item to the board, it must then proceed to set the status to the pre-dispatch value (e.g., "Writing Spec") as part of the normal status update, not leave it at a default "Backlog" value.
- If the board-add operation reports that the item was already present, the existing status must not be overwritten — only the intended next-stage status update should proceed.

---

## Acceptance Criteria

- [ ] When a spec-writer agent completes its work on an issue that was not previously on the project board, the issue appears on the board with status "Writing Spec" by the time the draft spec PR is opened.
- [ ] When a plan-writer agent completes its work on an issue that was not previously on the project board, the issue appears on the board with status "Writing Plan" by the time the draft plan PR is opened.
- [ ] When a developer agent completes its work on an issue that was not previously on the project board, the issue appears on the board with status "In Development" by the time the draft implementation PR is opened.
- [ ] When any of the above agents runs on an issue that is already on the project board, the existing board entry is not modified by the board-add step (the subsequent status update still proceeds normally).
- [ ] When the portfolio orchestrator elects an item for dispatch that is not yet on the project board, the item is added to the board and its status is set to the appropriate pre-dispatch value before the dispatch proceeds.
- [ ] If the board-add operation fails (API error, rate limit, or permissions), the agent logs a warning and continues without blocking progress on the primary task.
- [ ] Running the board-membership check-and-add step multiple times for the same issue does not create duplicate board entries.
- [ ] The board-membership check-and-add step is documented in the completion sequence of each affected protocol (`01-generate-spec-protocol.md`, `02-generate-implementation-plan-protocol.md`, `03-implement-development-protocol.md`) and in the pre-dispatch validation section of `90-batch-orchestrate-work-protocol.md`.

---

## Out of Scope (MVP)

- Automatically removing items from the board when issues are closed or cancelled (board cleanup is a separate concern).
- Enforcing board membership as a hard gate that prevents the agent from opening a PR if the board-add fails.
- Migrating existing issues that are already in progress but missing from the board (this is a one-time manual cleanup, not a workflow feature).
- Setting non-status custom fields (e.g., priority, assignee, sprint) when adding items to the board.
- Supporting project board providers other than GitHub Projects (e.g., Linear, Jira) — this spec targets GitHub Projects only.
- Notifying the human when an item is added to the board by an agent (silent best-effort registration is sufficient).
