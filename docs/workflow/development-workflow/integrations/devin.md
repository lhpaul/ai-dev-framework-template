# Integration: Devin (Automated PR Review)

This document describes how to use [Devin](https://devin.ai) as one automated PR reviewer tool in the workflow.

Devin is **optional**. The workflow functions without it. See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the multi-platform loop and aggregation rules.

---

## What Devin Adds

- Automated code review on every push — no trigger comment needed
- AI-powered analysis that catches bugs, security vulnerabilities, and logic errors
- Complements Greptile by providing a second independent review perspective

---

## Setup

### 1. Install the Devin GitHub App

Go to [devin.ai](https://devin.ai) and install the Devin GitHub App on your repository. Enable **auto-review** so Devin automatically reviews PRs when code is pushed.

### 2. Verify Auto-Review Is Active

After installation, push a commit to an open PR and confirm that Devin posts review comments. The bot posts as `devin-ai-integration[bot]`.

---

## Step 7 — Devin-Specific Implementation

The **Work Item Runner's** Step 7 (Automated Reviewer Loop) requires platform-specific commands. Below are the Devin adapter details used by the shared helper.

### Preferred helper

When possible, call the repository helper instead of re-implementing the loop inline:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform devin
```

It encapsulates the polling, comment classification, and stable aggregate `RESULT=` output used by the **Work Item Runner** (and by the **Portfolio Orchestrator** when it supervises item-level runs).

### Bot identity

Devin posts as `devin-ai-integration[bot]`. Use this login to filter its comments and reviews from human activity.

### Step 7.1 — Trigger a re-review

**No trigger needed.** Devin auto-reviews on every push. There is no trigger comment and therefore no `REVIEW_COMMENT_ID`. The aggregation layer already guards against empty values.

### Step 7.2 — Detect review completion

Devin signals completion in one of these ways:

1. **Summary review** — body contains `**Devin Review**` or "Devin Review has completed"
2. **No-findings review** — body contains "No Issues Found" (Devin posts this when it finds no blocking PR feedback; it may not create a check run in that case)
3. **Check run + grace period** — a Devin check run reaches `completed` and 120s have passed without a summary (handles inline-only or no summary)

**Important**: The check run may complete **before** Devin finishes posting review comments, and in some cases Devin may post review output later than expected or without a visible check run at the start of polling. The helper script therefore checks for completion **reviews first** on every poll (including "No Issues Found") and does **not** immediately skip just because no check run is visible yet.

The helper script:

- On each poll, looks for any Devin review since the commit with body matching `**Devin Review**`, "Devin Review has completed", or "No Issues Found". If found, treats review as complete and proceeds to Step 7.3.
- If no such review is seen, checks for Devin check runs and, once a completed check run is seen, applies a 120s grace period before treating the run as complete.
- If no Devin review and no Devin check run appear during the full `max_wait` window, checks for stale findings (see below) before returning `skipped`.

| Result                                                                                       | Action                                                             |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Any Devin review with "**Devin Review**", "Devin Review has completed", or "No Issues Found" | Review complete — proceed to Step 7.3                              |
| `check_completed > 0` and grace period (120s) elapsed                                        | Assume complete — proceed to Step 7.3                              |
| No completion review yet and `elapsed < max_wait`                                            | Not finished yet — wait another `poll_interval` and poll again     |
| `elapsed >= max_wait` and no Devin check run was ever seen                                   | Stale findings recovery, then the kept skip `no_check_run` if none found (`NO_VERDICT_YET=1`, `DISPLAY_RESULT=no verdict yet (non-blocking skip: no_check_run)`; no `reviewer-failed` label) |
| `elapsed >= max_wait` and a Devin check run was seen but has not completed                   | **No verdict yet** — `RESULT=waiting_on_reviewer`, `REASON=reviewer-no-verdict-yet`, `WAIT_EXPIRED_DETAIL=check_not_completed`, exit 4; not an escalation |
| A Devin check run on the head completed `failure`, `timed_out`, `cancelled`, `action_required`, `startup_failure`, or `stale`, or a Devin status is `failure` or `error`, and no finding or completion review is bound to the head | **Reviewer failed** — `RESULT=escalate`, `REASON=devin_run_failed`, `reviewer-failed` applied (also when the budget ends inside the 120 s grace) |

`max_wait` is Devin's own wait budget (#1789): 1200 s by default on
implementation branches. Devin is the only platform that does not review
`spec/*` and `implementation-plan/*` branches, so only Devin's built-in default
is shortened there, to `PR_REVIEW_LOOP_DOC_MAX_WAIT` (default 180 s); a
configured `review.wait_budgets.devin` value or a one-run `--max-wait` is never
shortened. See "Reviewer wait budgets and outcome classes" in
[`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md#reviewer-wait-budgets-and-outcome-classes-1789).

A failure-type Devin check or status does not override a verdict bound to the
head: bound findings still give `needs_fixes`, and a bound completion review
(for example "No Issues Found") keeps its verdict.

**Current-revision binding.** The completion review counts only when its
`commit_id` is the current head, so an older revision's summary submitted after
the push does not end the wait. Findings count only from review comments whose
`original_commit_id` is the current head (GitHub moves `commit_id` forward
while the commented line is unchanged). Check runs and statuses are read from
the current head's commit, so they are already bound.

### Step 7.3 — Fetch inline comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"devin-ai-integration[bot]\" and .created_at > \"$since_iso\" and .original_commit_id == \"$head_sha\" and .in_reply_to_id == null) | {path, line, body}]"
```

**Stale findings recovery:** When Devin does not review the current HEAD (no check run within `max_wait`), the helper scans the full PR history for unresolved Devin inline comments before reporting `skipped`. If unresolved findings exist from a prior review cycle (e.g. before a merge of the base branch), the helper reports `needs_fixes` with reason `stale_findings` so the agent dispatches a fixer. Devin's `✅ **Resolved**` confirmations and "No Issues Found" comments are excluded from this scan.

**All Devin findings are blocking.** Unlike Greptile, there is no `is_soft_suggestion()` heuristic — both severe (red) and non-severe (yellow) findings block the PR.

### Reply thread handling

Devin posts findings as inline comments on code lines, sometimes with a reply thread containing additional detail. The adapter filters out reply comments (`in_reply_to_id != null`) to avoid double-counting a finding and its reply as separate blocking items. Only top-level inline comments are counted.

### "No Issues Found" handling

When Devin finds no blocking PR feedback, it may post a summary comment containing "No Issues Found". These comments are excluded from the blocking count so the review correctly resolves as `clean`.

### Resolved comment handling

Devin posts `✅ **Resolved**:` comments when it detects a commit that fixes a previously reported issue. These confirmations are excluded from the blocking count so they are not misclassified as new findings.
