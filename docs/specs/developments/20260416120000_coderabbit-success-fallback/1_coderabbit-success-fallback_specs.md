# CodeRabbit SUCCESS Commit-Status Fallback — Spec

**Depends on**: <!-- none -->

---

## Overview

When multiple PRs are opened in rapid succession (3+ within seconds), CodeRabbit may exhaust its per-hour rate-limit budget before posting a fresh inline review comment on later PRs. The `pr-review-loop.sh` script currently waits up to its full retry budget and then escalates with `timeout`, even when CodeRabbit has already posted a `SUCCESS` commit-status context on the current HEAD — indicating the review is complete and clean. This causes orchestrator agents to appear "stuck" and forces manual intervention on every parallel batch of this size.

This fix adds a fallback path: if the CodeRabbit review-loop retry budget is exhausted but a CodeRabbit `SUCCESS` commit-status context exists on the current HEAD SHA, the script treats the PR as `clean` for the CodeRabbit platform (logging the fallback reason) rather than escalating.

---

## Use Cases

### Use Case 1: CodeRabbit Rate-Limit Window Exceeds Retry Budget — HEAD Has SUCCESS Status

**Actor**: Automated orchestrator agent running `pr-review-loop.sh` against a PR that is one of several opened in a parallel batch.

**Preconditions**:

- CodeRabbit is configured as a review platform in `.ai-dev-workflow.yaml`.
- The current HEAD SHA has a CodeRabbit commit-status context with `state: SUCCESS`.
- The CodeRabbit retry budget (poll cycles) has been exhausted without a new CodeRabbit review comment appearing.
- There are no existing blocking CodeRabbit findings (Critical or Major inline comments) on the current HEAD.

**Steps**:

1. The script exhausts the retry budget waiting for CodeRabbit to post a review.
2. Before running stale-findings recovery or returning `escalate`, the script queries the commit-status contexts for the current HEAD SHA.
3. The script finds a CodeRabbit status context with `state: SUCCESS`.
4. No existing blocking inline comments are present for the current HEAD.
5. The script returns `clean` (with `REASON=coderabbit_status_success_fallback`) instead of `escalate`.

**Postconditions**:

- `pr-review-loop.sh` exits with `RESULT=clean`.
- The orchestrator agent proceeds to the CI loop without human intervention.
- The fallback reason is recorded in the script output and surfaced in the automated reviewer loop summary comment.

**Information shown**:

- `RESULT=clean`
- `REASON=coderabbit_status_success_fallback`
- The reviewer loop summary comment on the PR notes that CodeRabbit's inline review was not re-posted but a `SUCCESS` commit-status was present, and the PR was treated as clean.

**Actions available**:

- The orchestrator proceeds to Step 8 (CI loop) normally.
- A human reviewer may optionally post `@coderabbitai review` on the PR after the rate-limit window resets for a full inline review.

**Considerations**:

- The fallback only applies when the commit-status `state` is exactly `SUCCESS`. A `pending`, `failure`, or `error` state does not trigger the fallback.
- The fallback only applies after the retry budget is exhausted, not on the first timeout.
- If existing blocking inline comments are present for the current HEAD, the fallback does not apply — the script must return `needs_fixes` as usual.

---

### Use Case 2: CodeRabbit Rate-Limit Window Exceeds Retry Budget — No SUCCESS Status

**Actor**: Automated orchestrator agent running `pr-review-loop.sh`.

**Preconditions**:

- CodeRabbit is configured as a review platform.
- The current HEAD SHA does NOT have a CodeRabbit commit-status context with `state: SUCCESS`.
- The CodeRabbit retry budget has been exhausted.

**Steps**:

1. The script exhausts the retry budget waiting for CodeRabbit to post a review.
2. The script queries the commit-status contexts for the current HEAD SHA.
3. No CodeRabbit `SUCCESS` status context is found.
4. The script falls through to its existing stale-findings recovery path and then returns `needs_fixes (stale_findings)`, `skipped (no_review)`, or `escalate (timeout)` per existing logic.

**Postconditions**:

- Behavior is unchanged from the current implementation for this case.

**Considerations**:

- No change to escalation behavior when CodeRabbit has not signaled SUCCESS.

---

## Business Rules

- The SUCCESS commit-status fallback applies **only** to CodeRabbit and has no effect on Greptile or Devin platform handlers.
- The fallback is checked after normal review polling is exhausted but **before** stale-findings recovery runs: if a `SUCCESS` commit-status is found at this point, the script returns `clean` immediately without scanning for stale findings.
- A CodeRabbit `SUCCESS` commit-status context is treated as authoritative evidence that CodeRabbit reviewed the HEAD and found no issues blocking the PR.
- Existing blocking inline comments (Critical or Major) on the current HEAD still block the PR even when a `SUCCESS` status context is present. The status context is a supplement to, not a replacement for, the inline comment check.
- The fallback reason (`coderabbit_status_success_fallback`) must be included in the script's key-value output so orchestrators and summary comments can surface it.

---

## Operational Visibility

- **Script output**: `RESULT=clean` and `REASON=coderabbit_status_success_fallback` are printed to stdout as key-value pairs alongside all other existing output fields.
- **Reviewer loop summary comment**: The automated reviewer loop summary posted on the PR must include the fallback reason so a human reviewer can see why the inline review was not awaited.

---

## Acceptance Criteria

- [ ] When `pr-review-loop.sh` exhausts the CodeRabbit retry budget and the current HEAD SHA has a CodeRabbit commit-status context with `state: SUCCESS`, the script exits with `RESULT=clean` and `REASON=coderabbit_status_success_fallback`.
- [ ] When `pr-review-loop.sh` exhausts the CodeRabbit retry budget and the current HEAD SHA does NOT have a CodeRabbit `SUCCESS` commit-status context, the script behavior is unchanged (falls through to stale-findings recovery and existing escalation logic).
- [ ] When existing blocking CodeRabbit inline comments (Critical or Major) are present on the current HEAD, the fallback does not apply regardless of commit-status state; the script returns `needs_fixes`.
- [ ] The `REASON=coderabbit_status_success_fallback` key-value is included in the script output when the fallback is triggered.
- [ ] The Greptile and Devin platform handlers are unaffected by this change.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 3.7 is updated to document the new fallback behavior so orchestrators know the manual workaround is no longer needed.

---

## Out of Scope (MVP)

- Changes to the Greptile or Devin platform handlers.
- Triggering `@coderabbitai review` automatically after a rate-limit window resets.
- Any changes to how blocking inline comments (Critical/Major) are detected or classified.
- Changes to `CODERABBIT_RATE_LIMIT_MAX_RETRIES` / `CODERABBIT_RATE_LIMIT_WAIT` retry logic (that controls the earlier rate-limit comment detection path, which is separate from this timeout fallback).
- Issue #167 (`fix/167-*`) changes to thread-resolution enforcement in `pr-review-loop.sh` — those changes must be able to land cleanly on top of this PR.
