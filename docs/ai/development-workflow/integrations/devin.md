# Integration: Devin (Automated PR Review)

This document describes how to use [Devin](https://devin.ai) as one automated code review platform in the workflow.

Devin is **optional**. The workflow functions without it. See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the multi-platform loop and aggregation rules.

---

## What Devin Adds

- Automated code review on every push — no trigger comment needed
- AI-powered analysis that catches bugs, security issues, and logic errors
- Complements Greptile by providing a second independent review perspective

---

## Setup

### 1. Install the Devin GitHub App

Go to [devin.ai](https://devin.ai) and install the Devin GitHub App on your repository. Enable **auto-review** so Devin automatically reviews PRs when code is pushed.

### 2. Verify Auto-Review Is Active

After installation, push a commit to an open PR and confirm that Devin posts review comments. The bot posts as `devin-ai-integration[bot]`.

---

## Step 7 — Devin-Specific Implementation

The item orchestrator's Step 7 (Automated Reviewer Loop) requires platform-specific commands. Below are the Devin adapter details used by the shared helper.

### Preferred helper

When possible, call the repository helper instead of re-implementing the loop inline:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform devin
```

It encapsulates the polling, comment classification, and stable aggregate `RESULT=` output used by the orchestrator.

### Bot identity

Devin posts as `devin-ai-integration[bot]`. Use this login to filter its comments and reviews from human activity.

### Step 7.1 — Trigger a re-review

**No trigger needed.** Devin auto-reviews on every push. There is no trigger comment and therefore no `REVIEW_COMMENT_ID`. The aggregation layer already guards against empty values.

### Step 7.2 — Detect review completion

Devin signals completion in **two stages**:

1. A GitHub **check run** reaches `completed` status
2. Devin finishes posting all inline review comments and (optionally) a **summary review** with body containing `**Devin Review**`

**Important**: The check run may complete **before** Devin finishes posting review comments. Collecting results immediately after the check run completes can produce a false `clean` result while Devin is still posting blocking findings.

The helper script handles this with a two-part wait:

```bash
# 1. Poll until Devin's check run completes
check_completed=$(gh api repos/{owner}/{repo}/commits/{head_sha}/check-runs \
  --jq '[.check_runs[] | select(
    (.app.slug == "devin-ai-integration") or
    (.name | test("devin"; "i"))
  )] | map(select(.status == "completed")) | length')

# 2. After check completes, wait for Devin's summary review OR a grace period
devin_summary_count=$(gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --jq '[.[] | select(
    .user.login == "devin-ai-integration[bot]" and
    .submitted_at > "'$since_iso'" and
    (.body // "" | test("\\*\\*Devin Review\\*\\*|Devin Review has completed"; "i"))
  )] | length')
```

| Result | Action |
|---|---|
| `check_completed > 0` and `devin_summary_count > 0` | Review fully complete — proceed to Step 7.3 |
| `check_completed > 0` and `devin_summary_count == 0` and grace period (120s) elapsed | Assume complete — Devin may have only posted inline resolved/no-issue comments without a summary |
| `check_completed == 0` and `elapsed < max_wait` | Not finished yet — wait another `poll_interval` and poll again |
| `check_completed == 0` and `elapsed >= max_wait` | Timeout — escalate to human (also covers the case where Devin is not installed) |

### Step 7.3 — Fetch inline comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"devin-ai-integration[bot]\" and .created_at > \"$since_iso\" and .in_reply_to_id == null) | {path, line, body}]"
```

**All Devin findings are blocking.** Unlike Greptile, there is no `is_soft_suggestion()` heuristic — both severe (red) and non-severe (yellow) findings block the PR.

### Reply thread handling

Devin posts findings as inline comments on code lines, sometimes with a reply thread containing additional detail. The adapter filters out reply comments (`in_reply_to_id != null`) to avoid double-counting a finding and its reply as separate blocking items. Only top-level inline comments are counted.

### "No Issues Found" handling

When Devin finds no issues, it posts a summary comment containing "No Issues Found". These comments are excluded from the blocking count so the review correctly resolves as `clean`.