# Attempt Tracking for Reviewer Loop Prompts — Spec

**Issue**: #448

---

## Overview

When the automated reviewer loop retries a fixer agent dispatch after a failed attempt, the fixer starts with no knowledge of what was already tried. This causes repeated identical fixes, lost context from prior attempts, and wasted token spend re-analyzing the same issues. This feature injects attempt-aware context into the fixer agent's prompt on each retry so the agent can reason about prior work, avoid re-applying failing approaches, and converge faster.

---

## Brief Coverage

| Brief Objective | Spec Trace |
|---|---|
| Track attempt number and pass it to fixer agent on each retry | AC-1, AC-2, Use Case 1 |
| Include summary of what prior attempts tried and why they failed | AC-3, AC-4, Use Case 2 |
| First attempt has no prior context overhead | AC-5, Business Rules |
| No change to the external reviewer step (pr-review-loop.sh) | Out of Scope |

---

## Use Cases

### Use Case 1: Fixer agent receives attempt context on retry

**Actor**: Automated reviewer loop (orchestrator)
**Preconditions**: The reviewer loop has dispatched a fixer agent at least once for a PR, the previous attempt did not fully resolve all blocking findings, and the loop is preparing to dispatch the fixer again.

**Steps**:
1. The orchestrator increments the attempt counter (cycle N → N+1)
2. The orchestrator collects a brief summary of what the previous attempt addressed and what findings remain open
3. The orchestrator prepends the attempt context to the fixer agent's prompt: "Attempt N/M: prior attempt(s) tried [summary of what was done]. The following findings remain open: [list]. Try a different approach for each remaining finding."
4. The fixer agent reads the attempt context before deciding how to address remaining findings
5. The fixer agent applies fixes informed by the prior-attempt summary and pushes a single commit

**Postconditions**: The fixer agent's output reflects awareness of prior attempts; it does not simply repeat the same change that was already tried and found insufficient.

**Information shown** (to the fixer agent in its prompt):
- Current attempt number and the configured maximum
- A short description of what each prior attempt addressed (e.g., "Attempt 1 rewrote the function signature in `foo.sh`")
- The specific findings still open after the last push

**Actions available**:
- The fixer agent can choose a different strategy for each remaining finding based on the context provided

**Considerations**:
- The attempt summary must be concise — it is prepended to the fixer's prompt and counts against its token budget
- If no prior attempt summary is available (e.g., the first retry has no recorded context), the orchestrator falls back to a minimal note: "Attempt 2/N: prior attempt did not fully resolve all findings. Try a different approach."
- The maximum attempt count shown to the fixer agent is the same `max_cycles` value that governs loop escalation

---

### Use Case 2: First-attempt fixer dispatch has no prior-attempt overhead

**Actor**: Automated reviewer loop (orchestrator)
**Preconditions**: A fixer agent is being dispatched for the first time for a given PR (cycle = 1).

**Steps**:
1. The orchestrator dispatches the fixer agent with the standard blocking-findings list and no attempt-context prefix
2. The fixer agent receives only the blocking findings and the standard fixer batching rule

**Postconditions**: The first-attempt prompt is unchanged from the current behavior; no attempt-counter overhead is added.

**Considerations**:
- The absence of attempt context on the first dispatch is intentional — the agent should not be primed with "retry" framing when it has not yet tried anything

---

### Use Case 3: Attempt context accumulates across multiple retries

**Actor**: Automated reviewer loop (orchestrator)
**Preconditions**: The fixer has been dispatched two or more times and findings remain after each attempt.

**Steps**:
1. After each fixer push, the orchestrator records a short summary entry for that attempt (what was changed and which findings were addressed or left open)
2. On the next dispatch, the orchestrator includes summaries for all prior attempts, not only the most recent one
3. The fixer agent can see the full history of what was tried to avoid repeating the same approaches

**Postconditions**: The fixer agent's prompt for attempt N contains summaries for attempts 1 through N-1.

**Considerations**:
- Each per-attempt summary entry should be kept to one or two sentences to control prompt length
- When a finding was previously addressed but reappeared (regression), the summary should note the reappearance explicitly so the fixer understands the fix did not hold

---

## Business Rules

- Attempt context is only added when the current dispatch is a retry (attempt number ≥ 2); the first dispatch always uses the standard prompt
- Each per-attempt summary is a short plain-language description of what was changed and what findings remained after that push
- The attempt counter shown in the prompt always matches the `cycle` counter maintained by the orchestrator's Step 7 loop
- The maximum attempt count displayed in the prompt is the `max_cycles` parameter configured for the loop (default: 10)
- The attempt summary is informational context for the fixer; it does not change the list of blocking findings passed to the fixer
- Attempt summaries must be retained in the orchestrator's in-session state for the duration of a PR's review loop; they do not need to be persisted across separate orchestration sessions
- The prompt injection applies to fixer agents dispatched from Step 7 (external automated reviewers) only; Step 7a (internal review gate) fixer cycles are unaffected

---

## Acceptance Criteria

- [ ] When the reviewer loop dispatches a fixer for attempt 1 (first fixer dispatch), the fixer's prompt does not include any attempt-context prefix
- [ ] When the reviewer loop dispatches a fixer for attempt N ≥ 2, the fixer's prompt begins with "Attempt N/M:" followed by a summary of what prior attempts addressed and what findings remain open
- [ ] The attempt counter N shown in the prompt matches the orchestrator's current `cycle` value
- [ ] The maximum M shown in the prompt matches the `max_cycles` parameter
- [ ] The attempt summary for each prior dispatch is a short plain-language description (one to two sentences) of what was changed and what remained open after that push
- [ ] When a finding reappeared after a prior fix, the attempt summary notes the reappearance explicitly
- [ ] The attempt-context prefix does not replace the standard blocking-findings list in the fixer prompt; it is prepended as additional context
- [ ] Protocol 91 Step 7 (or Step 7a where applicable) documents the attempt-context injection rule and the required prompt format
- [ ] Protocol 93 documents the same rule for the standalone reviewer loop path

---

## Out of Scope (MVP)

- Persisting attempt summaries across separate orchestration sessions (summaries live in the orchestrator's in-session state only)
- Modifying `pr-review-loop.sh` or any external reviewer tool — the change is limited to the fixer agent dispatch step in the orchestrator protocol
- Changing the attempt-tracking logic for Step 7a (internal review gate) fixer cycles — only Step 7 (external reviewer) dispatches are in scope
- Automated summarization of what the fixer agent changed — the orchestrator derives the per-attempt summary from the fixer's response and the PR feedback ledger update (both already tracked)
- UI or dashboard for attempt history — context is passed as prompt text only
- Attempt tracking for the CI loop fixer dispatch (Step 8 `red` result) — only the Step 7 review loop is in scope
