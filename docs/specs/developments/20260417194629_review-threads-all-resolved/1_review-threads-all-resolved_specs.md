# Require All Review Threads Resolved Before Ready-For-Human-Review — Spec

---

## Overview

The automated PR review loop (`pr-review-loop.sh`) currently blocks `ready-for-human-review` only on findings classified as blocking (Critical/Major for CodeRabbit; any non-"No Issues Found" comment for Devin). Non-blocking threads — CodeRabbit Nitpick/Trivial/Minor and any inline review thread authored by an automated reviewer — slip through as "suggestions" and do not prevent the readiness label from being applied.

This feature extends the readiness gate so that **every** unresolved review thread on a PR authored by an automated reviewer must be either replied-to-and-resolved (via the GitHub `resolveReviewThread` mutation) or addressed by a code fix on the current HEAD before `ready-for-human-review` is applied. The gate applies regardless of thread severity (Critical, Major, Minor, Nitpick, Trivial).

This directly fixes a recurring pattern across batches 4, 5, 7, and 8 where humans had to audit and manually resolve non-blocking threads post-ready.

---

## Use Cases

### Use Case 1: Automated reviewer posts a non-blocking inline thread

**Actor**: Orchestration agent (item-orchestrator or portfolio-orchestrator) running the PR review loop

**Preconditions**:
- A PR is open and non-draft
- An automated reviewer (CodeRabbit, Devin) has posted one or more inline review comments, including at least one thread whose severity is Nitpick, Trivial, or Minor

**Steps**:
1. Agent runs the PR review loop (Step 7 in Protocol 91)
2. The review loop script enumerates all review threads on the PR and checks each one for its resolved state
3. The script identifies unresolved threads authored by automated reviewers (regardless of severity)
4. The script reports `needs_fixes` for any unresolved thread authored by an automated reviewer
5. A fixer agent is dispatched; it either replies with a decision rationale and resolves the thread via the GitHub resolve API, or pushes a code fix to the current HEAD
6. After the fix, the loop re-runs and confirms all previously unresolved threads are now resolved
7. The loop reports `clean` only when no unresolved automated-reviewer threads remain
8. The agent applies `ready-for-human-review`

**Postconditions**: All review threads on the PR authored by automated reviewers are resolved (`isResolved: true`)

**Information shown**:
- The loop script emits `UNRESOLVED_THREAD_COUNT=N` alongside the existing `BLOCKING_COUNT` output
- When a thread is resolved via reply-only (no code fix), the fixer emits a note in the Automated Reviewer Loop Summary indicating the thread was acknowledged

**Actions available**:
- Fixer agent can resolve via (a) reply + `resolveReviewThread` mutation, or (b) code fix on current HEAD followed by normal loop re-run

**Considerations**:
- Only threads authored by known automated reviewer bot accounts (configurable list; defaults to `coderabbitai[bot]`, `devin-ai-integration[bot]`, `greptile-apps[bot]`) are subject to the gate
- Human-authored threads on the PR are not subject to this gate (those are covered by the `needs-fixes` label flow in Protocol 91 Step 9)
- A thread that is already `isResolved: true` on entry counts as resolved regardless of when it was resolved

---

### Use Case 2: PR review loop re-run after a code-fix push

**Actor**: Orchestration agent running the PR review loop in a subsequent cycle after a fixer push

**Preconditions**:
- A PR had unresolved automated-reviewer threads in a prior cycle
- Fixer agent pushed a code fix to the current HEAD

**Steps**:
1. Agent re-runs the PR review loop on the updated HEAD
2. The loop script re-enumerates all review threads
3. CodeRabbit appends "✅ Addressed in commit ..." to previously open threads after the push — these are counted as resolved
4. For threads where CodeRabbit has not auto-resolved (e.g., the fix did not change the exact file/line), the agent verifies whether the code fix addressed the underlying concern
5. If all threads are `isResolved: true` (or have a `✅ Addressed` marker), the loop proceeds normally
6. If threads remain unresolved, the loop returns `needs_fixes` again with the remaining thread IDs

**Postconditions**: Loop emits `clean` only when all automated-reviewer threads are resolved

**Information shown**:
- Loop summary comment lists which threads were resolved in this cycle and which remain

**Actions available**:
- Agent may call `resolveReviewThread` mutation directly for threads whose concern was addressed but which CodeRabbit has not auto-resolved

**Considerations**:
- The `✅ Addressed` text from CodeRabbit on the parent comment is treated as equivalent to `isResolved: true` for the purposes of this gate (consistent with existing behavior in `is_coderabbit_blocking`)
- When CodeRabbit skips spec branches entirely (documented behavior), Devin result is authoritative and the unresolved-thread check falls back to Devin-authored threads only

---

### Use Case 3: Step 8c independent verification rejects a PR with unresolved threads

**Actor**: Orchestration agent performing the post-label verification in Protocol 91 Step 8c

**Preconditions**:
- Step 7 completed with `clean` but the unresolved-thread check was not performed (e.g., from a prior run before this feature shipped)
- One or more review threads on the PR are still `isResolved: false`

**Steps**:
1. Agent runs Step 8c independent verification
2. Step 8c enumerates all review threads on the PR and checks each one's resolved state
3. Any unresolved automated-reviewer thread causes Step 8c to fail
4. Agent removes `ready-for-human-review` and applies `needs-fixes`
5. Agent dispatches a fixer to resolve remaining threads
6. After fix, agent re-runs from Step 7a

**Postconditions**: Step 8c passes only when `isResolved: true` for all automated-reviewer threads

**Information shown**:
- Step 8c log lists the unresolved thread IDs and their authors

**Actions available**:
- Fixer resolves threads via reply + mutation or code fix

**Considerations**:
- This use case is the safety net for cases where the loop script's thread check was bypassed or is running against an older version of the script

---

## Business Rules

- Every unresolved review thread on a PR authored by a configured automated reviewer bot must be resolved (via text reply + `resolveReviewThread` mutation, or via a code fix on current HEAD) before `ready-for-human-review` is applied.
- The gate applies to all thread severities: Critical, Major, Minor, Nitpick, Trivial, and any severity the reviewer may introduce in the future.
- Only threads with `isResolved: false` are subject to the gate; threads with `isResolved: true` or containing a `✅ Addressed` marker in the parent comment body are already considered resolved.
- The list of automated reviewer bot logins subject to the gate is driven by the configured platforms in `.ai-dev-workflow.yaml` (`review.platforms`). Default bot accounts per platform: `coderabbitai[bot]` (coderabbit), `devin-ai-integration[bot]` (devin), `greptile-apps[bot]` (greptile).
- Human-authored review threads are not subject to this automated gate; they are handled by the `needs-fixes` / human feedback loop in Protocol 91 Step 9.
- When a thread is resolved via reply-only (no code change), the Automated Reviewer Loop Summary must record this explicitly so the human reviewer can see the rationale.
- A thread is considered resolved if `isResolved: true` on the GitHub review thread object, **or** if the parent comment body contains the text `✅ Addressed` (CodeRabbit's auto-resolved marker after a fix commit). Both conditions are equivalent for the purposes of this gate.
- The thread enumeration must be complete: no automated-reviewer thread may be missed. The implementation must handle PRs with more than a single page of review threads without silently skipping threads beyond the first page.
- The unresolved-thread check is a **hard gate**: it must run (a) as the final check inside `pr-review-loop.sh` before exiting `clean`, and (b) as one of the verification checks in Protocol 91 Step 8c.

---

## Acceptance Criteria

- [ ] **AC1**: When `pr-review-loop.sh` completes a review cycle with zero blocking findings but one or more automated-reviewer threads are `isResolved: false`, the script exits with `needs_fixes` and emits `UNRESOLVED_THREAD_COUNT=N` in its output.
- [ ] **AC2**: When all automated-reviewer review threads have `isResolved: true` (or `✅ Addressed` on the parent comment), `pr-review-loop.sh` exits `clean`.
- [ ] **AC3**: Protocol 91 Step 8c verification enumerates all review threads on the PR and rejects the PR (removes `ready-for-human-review`, applies `needs-fixes`) if any automated-reviewer thread is unresolved.
- [ ] **AC4**: After a fixer agent resolves threads via `resolveReviewThread` mutation and the loop re-runs, the PR reaches `ready-for-human-review` with all threads resolved.
- [ ] **AC5**: The Automated Reviewer Loop Summary comment includes a section listing threads resolved via reply-only (no code fix) with a short rationale, so the human reviewer can audit the decision.
- [ ] **AC6**: The unresolved-thread check is scoped only to bot accounts belonging to configured review platforms; human-authored threads do not trigger this gate.
- [ ] **AC7**: The portfolio orchestrator's pre-readiness verification includes an explicit check that all automated-reviewer review threads are resolved before declaring a PR ready for human review.

---

## Out of Scope (MVP)

- Automatically generating reply text for non-blocking threads (the fixer agent writes the reply; this spec does not prescribe the reply wording).
- Retroactively re-resolving threads on already-merged PRs.
- Changing the severity classification logic inside `is_coderabbit_blocking` (this spec adds a separate unresolved-thread gate on top of the existing blocking-finding gate, not a replacement).
- Any changes to `post-merge-cleanup.sh`, developer agent docs, or Protocol 91 Step 7a internal review — those are separate issues.
- Support for review platforms not currently listed in `review.platforms` in `.ai-dev-workflow.yaml`.
- UI or notification changes outside the existing PR comment and label flows.
