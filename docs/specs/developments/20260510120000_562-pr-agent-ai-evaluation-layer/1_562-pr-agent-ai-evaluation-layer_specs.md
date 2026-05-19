# AI Evaluation Layer for PR-Agent "Possible Issue" Findings — Spec

**Depends on**: None

---

## Overview

When PR-Agent posts a "Possible Issue" advisory finding on a pull request, the automated reviewer loop currently classifies it as non-blocking and proceeds to `clean` without any further evaluation. This has caused genuine bugs to pass undetected — most notably in Batch 33 (PR #517), where both PR-Agent and CodeRabbit independently flagged a real bug, but only CodeRabbit's unresolved-thread gate blocked the loop. The bug was fixed only after a human asked about it.

This spec defines an AI evaluation sub-step that is inserted into the reviewer loop whenever PR-Agent returns `clean` with one or more "Possible Issue" advisory labels. A code-reviewer agent evaluates each finding against the actual code and either pushes a fix (if a real bug is found) or posts an explicit acknowledgment comment (if the finding is acceptable). This reduces the false-negative rate without introducing a new source of spurious blocking loops.

---

## Use Cases

### Use Case 1: PR-Agent Returns Clean with a "Possible Issue" Label

**Actor**: Automated reviewer loop (running on a pull request)
**Preconditions**:

- A PR is open and the automated reviewer loop is running
- PR-Agent has posted a summary comment for the current HEAD commit
- The PR-Agent summary classifies as `clean` (no hard-blocker labels)
- The summary includes at least one "Possible Issue" label in the "Recommended focus areas for review" section

**Steps**:

1. The reviewer loop detects the `clean` result from PR-Agent and inspects advisory labels
2. The loop finds one or more "Possible Issue" labels
3. The loop dispatches a code-reviewer agent with:
   - The PR-Agent comment body (the finding text)
   - The PR diff or relevant changed files
   - A clear prompt asking the agent to determine if the finding describes a real bug or is noise
4. The code-reviewer agent evaluates the finding:
   - **Scenario A — real bug found**: The agent pushes a fix commit to the PR branch; the reviewer loop continues as normal (re-runs from the top on the new HEAD)
   - **Scenario B — finding is acceptable**: The agent posts an acknowledgment comment on the PR (equivalent to resolving a review thread) explaining why the finding is not actionable; the loop proceeds to `clean`
5. In both scenarios the reviewer loop waits for the agent's verdict before emitting a final result

**Postconditions**:

- If a real bug was found: the PR branch has a new fix commit, and the loop re-runs on the updated HEAD
- If the finding is acceptable: an acknowledgment comment is visible on the PR, and the loop result is `clean`

**Information shown**:

- (No interactive UI — this is an automated workflow step)
- The reviewer loop summary includes a note indicating that the "Possible Issue" finding was evaluated and the outcome (fix pushed or acknowledged)

**Actions available**:

- (Automated — no manual action required during the loop)

**Considerations**:

- If the code-reviewer agent cannot be dispatched (runtime unavailable, timeout), the loop should fall back to the current advisory-only behavior (log a warning and proceed `clean`) rather than blocking indefinitely
- The acknowledgment comment must be substantive — it must explain the reasoning, not just say "acknowledged"
- If the agent posts an acknowledgment and the loop later re-runs (e.g., due to a new push), the finding will not be re-evaluated (evaluation is scoped to the current HEAD — see Business Rules)

---

### Use Case 2: PR-Agent Returns Clean with Other Advisory Labels (No Change)

**Actor**: Automated reviewer loop
**Preconditions**:

- A PR is open and the automated reviewer loop is running
- PR-Agent summary classifies as `clean`
- Advisory labels are present but none is "Possible Issue" (e.g., "Edge Case", "Logic Gap", "Documentation Inconsistency", "Performance Concern", etc.)

**Steps**:

1. The reviewer loop detects the `clean` result from PR-Agent
2. The advisory labels are recorded in the loop's output (existing behavior)
3. No code-reviewer agent is dispatched
4. The loop proceeds to `clean` as before

**Postconditions**: Loop result is `clean`; advisory labels are surfaced in the summary without triggering evaluation

**Information shown**:

- (No additional information — existing loop summary behavior)

**Actions available**:

- (No actions — no evaluation step triggered)

**Considerations**:

- This use case defines the explicit boundary of the feature: only "Possible Issue" triggers AI evaluation; all other advisory labels remain non-blocking and unevaluated

---

### Use Case 3: PR-Agent Returns Clean with No Advisory Labels

**Actor**: Automated reviewer loop
**Preconditions**:

- PR-Agent summary classifies as `clean` with no advisory labels (or the "No major issues detected" message)

**Steps**:

1. The reviewer loop detects the `clean` result
2. No evaluation step is triggered
3. Loop proceeds to `clean` immediately

**Postconditions**: Loop result is `clean` — no change from current behavior

**Information shown**:

- (No additional information — standard clean result)

**Actions available**:

- (No actions — loop proceeds normally)

**Considerations**:

- (None — this is the baseline happy path)

---

## Business Rules

- Only the "Possible Issue" label triggers the AI evaluation sub-step. All other advisory labels ("Edge Case", "Logic Gap", "Documentation Inconsistency", "Performance Concern", and others) remain non-blocking and unevaluated.
- The AI evaluation sub-step must wait for the code-reviewer agent's verdict before the reviewer loop emits a final result for the PR-Agent platform.
- If the code-reviewer agent finds a real bug, it pushes a fix; the loop re-runs from the top on the new HEAD. This re-run is subject to the existing loop retry limits (no special bypass).
- If the code-reviewer agent finds the finding acceptable, it must post an acknowledgment comment on the PR before the loop proceeds to `clean`.
- The evaluation is scoped to the current HEAD commit. A "Possible Issue" finding from a PR-Agent comment that was posted for an earlier commit does not trigger evaluation on a subsequent loop pass (the loop already evaluates only the latest PR-Agent comment for the current HEAD).
- If the code-reviewer agent dispatch fails (runtime unavailable or timed out), the loop falls back to treating the finding as advisory-only (`clean`) and logs a warning. The fallback must be explicit — it must not silently drop the advisory label from the loop summary.
- Hard-blocker labels ("Critical", "Must Fix", "Breaking Change", "Security Concern", "API Change", "Backward Compatibility") are already blocking by existing reviewer loop behavior and are unaffected by this feature.
- Spec and chore PRs are included — if a "Possible Issue" advisory label appears on a spec or chore PR, the agent is dispatched; if the finding is noise in that context, the agent acknowledges it and the loop proceeds. No PR type is exempt from evaluation (the agent's acknowledgment is the gate, not the PR type).

---

## Operational Visibility

- **Logs**: The reviewer loop emits a log line when dispatching the code-reviewer agent for a "Possible Issue" evaluation, and another when the verdict is received (fix pushed or acknowledged)
- **Notifications**: No additional notifications are introduced. When the finding is acceptable, the agent posts an acknowledgment comment on the PR. When a real bug is found, the agent pushes a fix commit to the PR branch (visible in the PR timeline/commits); this is a commit artifact, not a PR comment
- **Audit trail**: The acknowledgment comment or fix commit is visible on the PR timeline and constitutes the audit record for each evaluated finding

---

## Acceptance Criteria

- [ ] When PR-Agent posts a `Possible Issue` finding on any PR and the overall PR-Agent classification is `clean`, the reviewer loop dispatches a code-reviewer agent to evaluate the finding before declaring the loop result `clean`
- [ ] If the code-reviewer agent determines the finding is a real bug, it pushes a fix commit and the loop re-runs from the top on the new HEAD (subject to existing retry limits)
- [ ] If the code-reviewer agent determines the finding is acceptable, it posts a substantive acknowledgment comment on the PR, and the loop result is `clean`
- [ ] Advisory labels other than "Possible Issue" ("Edge Case", "Logic Gap", "Documentation Inconsistency", "Performance Concern", etc.) do not trigger the AI evaluation sub-step and remain non-blocking
- [ ] A `Possible Issue` finding on a spec or chore PR is correctly evaluated: the agent acknowledges it as noise or pushes a fix; in either case the loop does not enter a spurious fix loop
- [ ] If the code-reviewer agent dispatch fails (runtime unavailable or timeout), the loop logs a warning and proceeds with the `clean` result (advisory-only fallback), and the advisory label is still present in the loop summary output

---

## Out of Scope (MVP)

- Evaluation of advisory labels other than "Possible Issue" — the spec intentionally limits the initial scope to the label that has historically generated false negatives
- Metrics tracking or comparison mode for per-platform verdict analysis (this is the scope of companion issue #563)
- Changes to how hard-blocker PR-Agent labels ("Critical", "Must Fix", etc.) are handled — those already block the loop
- UI or dashboard for surfacing acknowledgment history
- Automatic categorization or tagging of "acknowledged" vs "fixed" outcomes beyond what is visible in PR comments and loop logs
- Retry logic specifically for the AI evaluation sub-step beyond the existing reviewer loop retry limits
