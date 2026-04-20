# Subagent Permission Denial Mitigation — Spec

**Depends on**: none

---

## Overview

During Batch 5 orchestration (2026-04-16), two consecutive `item-orchestrator` subagent dispatches for issue #160 were denied permission to call `Edit` and `Bash` mid-run, despite those tools being listed in the agent definition's `tools:` frontmatter. The main session had those tools available without interruption. Other subagents in the same batch succeeded, making the failure intermittent.

This spec defines the detection, mitigation, and protocol changes needed so that the Portfolio Orchestrator can identify and route around subagent permission failures without losing progress or requiring manual orchestrator intervention. The spec is scoped to the detection and recovery path — not to fixing the underlying harness behavior, which is outside this project's control.

---

## Use Cases

### Use Case 1: Portfolio Orchestrator detects permission failure after dispatch

**Actor**: Portfolio Orchestrator (automated agent run)
**Preconditions**:
- The Portfolio Orchestrator has dispatched an `item-orchestrator` subagent for a work item.
- The subagent reports back with an error or summary indicating that `Edit` or `Bash` tool calls were denied.

**Steps**:
1. The subagent attempts to call `Edit` or `Bash` and receives a "Permission to use [tool] has been denied" response from the harness.
2. The subagent exits its run and returns an error or summary to the Portfolio Orchestrator noting the denial.
3. The Portfolio Orchestrator reads the subagent result and identifies the permission-failure signal in the returned text.
4. The Portfolio Orchestrator logs the failure with the item identifier and the denied tool name.
5. The Portfolio Orchestrator does NOT redispatch the same subagent for the same item in the same batch run.
6. The Portfolio Orchestrator falls back to executing the item inline from the main session using the same worktree the subagent was given.

**Postconditions**:
- The item continues to advance from the main session using the correct worktree state.
- No work from the subagent's partial run is lost or double-applied.
- The failure is noted in the final Portfolio Orchestrator summary for retrospective analysis.

**Information shown**:
- A note in the batch summary: item `#N` fell back to inline execution after subagent permission denial on tools `[Edit, Bash]`.

**Actions available**:
- None required from the human — the orchestrator self-heals.

**Considerations**:
- The subagent may have partially completed some read-only steps before the denial. The inline fallback must re-evaluate state from scratch (using `workflow-next-action.sh`) rather than assuming any prior state from the subagent.
- The fallback must use the same worktree or branch that was set up for the item by the Portfolio Orchestrator dispatch.

---

### Use Case 2: Human operator reviews a batch run that used the inline fallback

**Actor**: Human operator reviewing a completed batch run summary
**Preconditions**: The Portfolio Orchestrator completed a batch and at least one item fell back to inline execution due to subagent permission denial.

**Steps**:
1. The human reads the batch summary at the end of the run.
2. The summary clearly identifies which items were handled inline vs. via subagent dispatch.
3. The human can identify what was denied and that the item still reached its terminal condition.

**Postconditions**:
- The human has enough information to decide whether to escalate the permission-denial issue to the harness maintainer.

**Information shown**:
- Per-item execution path in the batch summary (subagent vs. inline fallback).
- Denied tool names for each affected item.

**Actions available**:
- The human may file a follow-up issue to investigate harness-level root cause.
- No action is required if the item reached `ready-for-human-review` successfully.

**Considerations**:
- If the inline fallback itself fails (e.g., the main session also loses permission mid-run), that is a separate escalation path — stop and notify the human.

---

### Use Case 3: item-orchestrator protocol includes a pre-flight self-check before heavy operations

**Actor**: `item-orchestrator` subagent
**Preconditions**:
- The subagent has been dispatched and has received its handoff context.
- The subagent is about to begin creator-stage work (writing spec, writing plan, or implementing).

**Steps**:
1. Before calling any creator-stage agent or making any file edits, the subagent performs a lightweight self-check: it attempts a trivial `Edit` operation (appending a comment to a temp file) or checks tool availability via an introspection mechanism.
2. If the self-check succeeds, the subagent proceeds normally.
3. If the self-check fails with a permission denial, the subagent immediately exits with a structured error message identifying the denied tool, before any partial work is done.
4. The Portfolio Orchestrator receives the structured exit and falls back per Use Case 1.

**Postconditions**:
- No partial work is done if the subagent cannot proceed.
- The Portfolio Orchestrator is informed early (within the first seconds of the subagent run) rather than after the subagent has wasted time on read-only steps.

**Information shown**:
- A structured failure message: "Pre-flight check failed: Edit tool denied. Falling back to orchestrator inline execution."

**Actions available**:
- None for the human — the orchestrator handles recovery automatically.

**Considerations**:
- The self-check should be as lightweight as possible (does not write to tracked files).
- If the self-check itself is not possible without Edit/Bash, the subagent should rely on the early-failure path from Use Case 1 instead.
- This use case is a "nice to have" optimization; Use Case 1 covers the recovery even without it.

---

## Business Rules

- The Portfolio Orchestrator MUST NOT redispatch the same subagent for the same item in the same batch run after a permission-denial failure.
- The inline fallback MUST re-evaluate item state from the current branch/worktree rather than assuming any progress from the failed subagent.
- A permission denial on `Edit` or `Bash` is always treated as an infrastructure failure, not a content failure. It does NOT add a `needs-fixes` label to any PR.
- The batch run summary MUST distinguish items completed via subagent dispatch from items completed via inline fallback.
- If the inline fallback also fails, the item is marked blocked and the human is notified. The batch does not retry further.
- The pre-flight self-check (Use Case 3) is optional but, when present, MUST run before any creator-stage tool call or file edit. It MUST NOT touch tracked files (commits, spec content, or production files).

---

## Operational Visibility

- **Logs**: The Portfolio Orchestrator logs each permission-denial failure with the item identifier and the denied tool name when detected (Use Case 1, step 4).
- **Notifications**: If both the subagent and the inline fallback fail, the human is notified and the item is marked blocked. No notification is required for a successful inline fallback.
- **Audit trail**: The final batch run summary records the per-item execution path (subagent vs. inline fallback) and denied tool names for any affected items.

---

## Acceptance Criteria

- [ ] AC1: When a subagent reports "Permission to use Edit has been denied" or "Permission to use Bash has been denied", the Portfolio Orchestrator recognizes this as a permission-failure signal and does not redispatch the subagent for the same item in the same batch.
- [ ] AC2: After a subagent permission failure, the Portfolio Orchestrator executes the item inline from the main session using the same worktree path, starting from a fresh `workflow-next-action.sh` evaluation.
- [ ] AC3: The final batch run summary lists any items that fell back to inline execution and includes the denied tool name(s).
- [ ] AC4: The item still reaches `ready-for-human-review` (or another valid terminal condition) via the inline fallback — the failure does not leave the item permanently stuck.
- [ ] AC5: The `item-orchestrator` protocol document (protocol 91) includes guidance instructing the subagent to exit immediately with a structured error message when a tool-permission denial is encountered before any partial work is committed.
- [ ] AC6: If both the subagent and the inline fallback fail due to permission denial, the item is marked blocked in the batch summary and the human is notified rather than the orchestrator looping indefinitely.

---

## Out of Scope (MVP)

- Identifying or fixing the root cause of why some subagent spawns receive a more restrictive permission mode than others. That is a Claude Code harness behavior outside this project's control.
- Adding new CI checks or automated tests that verify subagent tool permissions at spawn time.
- Modifying the `settings.json` tool allowlist to add new permitted Bash commands beyond what is currently configured. If specific script calls need allowlisting, that is a separate backlog item.
- Telemetry, dashboards, or long-term tracking of permission-denial frequency across batches.
- Handling permission denials on tools other than `Edit` and `Bash` (e.g., `WebFetch`, `Glob`) — those have not been observed and have different risk profiles.

---

## Open Questions

1. **Q: Is there a reliable way for a subagent to introspect its own tool list at runtime (before attempting a call)?** If yes, the pre-flight self-check in Use Case 3 can be implemented without side effects. If no, the self-check must attempt a benign write to a temp file. This is an implementation-plan question.
2. **Q: Should the permission-denial signal detection use exact string matching on the harness error message, or a fuzzy match?** Exact matching is safer but fragile if the harness changes its error wording. The implementation plan should decide the matching strategy.
