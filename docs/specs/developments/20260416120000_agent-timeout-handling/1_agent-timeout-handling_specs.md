# Agent Timeout Handling — Spec

**Depends on**: <!-- no dependencies -->

---

## Overview

Long-running item-orchestrator agents can time out mid-run (observed as "API Error: Stream idle timeout" after ~20 minutes), leaving the workflow in an ambiguous partial state. This spec defines the behavior the framework should guarantee when an agent run is interrupted: what progress is preserved, how a resumed agent can detect incomplete state, and what guidance operators need to safely resume. The goal is to eliminate the class of incidents where a timed-out agent leaves a PR appearing ready when the review loop was never completed.

---

## Use Cases

### Use Case 1: Agent times out during the review loop

**Actor**: Item-orchestrator agent (automated)
**Preconditions**: An item-orchestrator agent has opened a draft PR, run the internal review gate, and is mid-way through the external automated reviewer loop or CI loop when the API stream idles out.

**Steps**:
1. The agent run is interrupted (stream idle timeout, context-window exhaustion, or API error).
2. The PR may have labels partially applied (e.g., `ready-for-regression` present but `ready-for-human-review` absent).
3. The automated reviewer loop summary comment is absent from the PR.
4. A human operator or the portfolio orchestrator detects the incomplete state.
5. The operator (or a resumed agent) inspects the PR and determines the correct resume point.
6. The resumed agent picks up from the incomplete step without re-running already-completed work.

**Postconditions**: The PR reaches a consistent, verifiable ready state, with no step skipped and no step double-executed.

**Information shown**:
- The PR comment history clearly indicates which steps ran and which did not.
- Labels accurately reflect the current review state.
- The automated reviewer loop summary comment is present and complete.

**Actions available**:
- Operator can trigger a resumed agent with a known resume point.
- Orchestrator can detect incomplete state via heuristic checks (presence/absence of expected comments and labels).

**Considerations**:
- The timed-out agent may have applied some labels before stopping. The resumed agent must not assume all labels reflect a completed step.
- The review loop summary comment is a reliable completion signal for Step 7 — its absence means Step 7 did not finish.
- If the PR already has `ready-for-human-review` but lacks the review summary comment, the label must be removed and the review loop re-run.

---

### Use Case 2: Orchestrator detects a stale-looking PR during batch dispatch

**Actor**: Portfolio orchestrator (automated)
**Preconditions**: A PR exists with some readiness labels but without the expected automated reviewer loop summary comment. The PR is non-draft and not labeled `needs-fixes`.

**Steps**:
1. The portfolio orchestrator scans open PRs.
2. It finds a PR that has labels consistent with "ready" (e.g., non-draft, `ready-for-regression`) but no reviewer loop summary comment.
3. The orchestrator classifies the PR as "incomplete — review loop not run" rather than "ready".
4. It dispatches an item-orchestrator agent to resume from Step 7.

**Postconditions**: The PR is advanced through the review loop and reaches a verified ready state.

**Information shown**:
- The orchestrator's dispatch log notes the reason for re-dispatch (incomplete review loop detected).

**Actions available**:
- Orchestrator dispatches a resumed item-orchestrator agent.

**Considerations**:
- The orchestrator must not re-dispatch a PR that is genuinely `ready-for-human-review` and has a complete review summary comment — this would waste cycles and confuse reviewers.
- The detection heuristic (labels present, summary comment absent) should be documented so operators can run it manually.

---

### Use Case 3: Operator manually resumes an interrupted item

**Actor**: Human operator
**Preconditions**: An agent run timed out. The operator knows the PR number and wants to resume from the incomplete step.

**Steps**:
1. The operator inspects the PR state: labels, comments, CI checks.
2. The operator consults the documented resume guide to identify the correct resume point.
3. The operator invokes the item-orchestrator (or automated-reviewer-loop agent) with the PR number and a resume hint.
4. The resumed agent completes the remaining steps.

**Postconditions**: PR is fully ready for human review.

**Information shown**:
- The resume guide documents the signals to look for and the command to run for each scenario.

**Actions available**:
- Invoke the item-orchestrator or automated-reviewer-loop agent with the PR number.

**Considerations**:
- The operator must not manually apply `ready-for-human-review` without completing the review loop — doing so reintroduces the original problem.

---

## Business Rules

- **BR-1**: The presence of `ready-for-human-review` on a PR does NOT guarantee the automated reviewer loop ran to completion. The only reliable signal is a PR comment whose body contains `"Automated Reviewer Loop Summary"` or `"No blocking PR feedback"`. This comment is the canonical "Step 7 complete" signal; no other label or PR state substitutes for it.
- **BR-2**: The Step 8c independent verification gate (post-label verification in protocol 91) MUST check for the reviewer loop summary comment before reporting a PR as ready. This check already exists in the protocol; it must be enforced consistently.
- **BR-3**: A resumed agent that finds a PR without the reviewer loop summary comment MUST re-run Step 7 (external automated reviewers) from the beginning of that step, regardless of which labels are already applied.
- **BR-4**: A resumed agent that finds a PR with no CI checks completed must re-run Step 8 (CI loop).
- **BR-5**: If the Step 8c gate fails (missing review summary comment, missing label, CI not green), the agent must apply `needs-fixes` and remove `ready-for-human-review` before re-entering the fix loop from Step 7a.
- **BR-6**: The agent model configuration document should document the expected maximum duration for each agent role so operators know when a run has likely timed out versus is still running.
- **BR-7**: Long-running review loops should not be broken into separate parallel async sub-calls unless the orchestration protocol explicitly supports async handoff — doing so risks leaving the PR in an inconsistent intermediate state.

---

## UX Rules

This feature primarily affects the orchestration protocol documents and the agent model config — there is no end-user UI. The "UX" is for human operators and AI agents reading protocol documents.

- The resume guide (to be added to the protocols or agent-model-config) must be scannable in under 30 seconds: a checklist of signals (label present/absent, comment present/absent, CI state) maps to a "resume from Step N" action.
- Protocol documents that describe terminal conditions must list the reviewer loop summary comment as a hard prerequisite for "ready for human review", not just an optional check.
- Any new guidance must not require changes to external tools or CI configuration — it must be achievable through protocol text and documentation updates only.

---

## Operational Visibility

- **Logs / Comments**: The automated reviewer loop summary comment on the PR is the primary operational signal that Step 7 completed. Agents must post this comment at the end of Step 7 in all outcomes (clean, escalated, max cycles).
- **Labels**: Labels (`ready-for-regression`, `ready-for-human-review`, `needs-fixes`) serve as coarse state indicators, but they are not sufficient alone — the reviewer loop comment must also be present.
- **Audit trail**: The PR comment history is the audit trail for which steps ran. The Step 8c verification gate documents why a PR was or was not declared ready.

---

## Acceptance Criteria

- [ ] The Step 8c independent verification checklist in [`91-orchestrate-work-protocol.md`](../../../workflow/development-workflow/protocols/91-orchestrate-work-protocol.md) includes an explicit check: at least one PR comment whose body contains `"Automated Reviewer Loop Summary"` or `"No blocking PR feedback"` must be present before `ready-for-human-review` is applied. (This check already exists in the protocol; this criterion confirms it is clearly stated and not removable by an agent.)
- [ ] [`docs/workflow/development-workflow/agent-model-config.md`](../../../workflow/development-workflow/agent-model-config.md) documents an expected maximum run duration for the `item-orchestrator` and `automated-reviewer-loop` agents (e.g., "typical run: 5–15 min; consider timeout at ~25 min").
- [ ] A "Resume a timed-out agent run" section is added to [`docs/workflow/development-workflow/agent-model-config.md`](../../../workflow/development-workflow/agent-model-config.md) (or a dedicated doc linked from it). The section describes: (a) how to detect an incomplete run (checklist of signals), (b) the command to resume, and (c) the warning not to manually apply `ready-for-human-review` without completing the review loop.
- [ ] The portfolio orchestrator protocol ([`90-batch-orchestrate-work-protocol.md`](../../../workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md)) documents the heuristic for detecting a stale/incomplete PR (labels present, summary comment absent) and the action to take (re-dispatch item-orchestrator to resume from Step 7).
- [ ] All changes are documentation-only: no code, no scripts, no CI configuration changes are required.

---

## Out of Scope (MVP)

- Automatic checkpointing: persisting agent progress to a file so a resumed agent can continue from the exact interrupted instruction (complex to implement reliably; deferred).
- Reducing the probability of timeouts by restructuring the review loop into smaller steps or async sub-calls (architectural change to the protocol; a separate investigation item).
- Automatic agent restart triggered by a watchdog or CI job (requires external tooling not in scope for this item).
- Changes to the underlying API timeout configuration (outside the framework's control).
- Detecting timeouts that happen before a PR is opened (no PR means no comment trail to inspect; out of scope for this iteration).

---

## Open Questions

1. Should the "Resume a timed-out agent run" section live in `agent-model-config.md` or in a new dedicated runbook? The implementation plan should decide based on discoverability for operators.
