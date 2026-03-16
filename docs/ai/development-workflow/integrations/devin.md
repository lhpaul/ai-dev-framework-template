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

Devin signals completion via a GitHub **check run**. Poll the check-runs API for the head SHA until a Devin check run reaches `completed` status:

```bash
# Poll until Devin's check run completes
check_completed=$(gh api repos/{owner}/{repo}/commits/{head_sha}/check-runs \
  --jq '[.check_runs[] | select(
    (.app.slug == "devin-ai-integration") or
    (.name | test("devin"; "i"))
  )] | map(select(.status == "completed")) | length')
```

| Result | Action |
|---|---|
| `check_completed > 0` | Review complete — proceed to Step 7.3 to check for inline comments |
| `check_completed == 0` and `elapsed < max_wait` | Not finished yet — wait another `poll_interval` and poll again |
| `check_completed == 0` and `elapsed >= max_wait` | Timeout — escalate to human (also covers the case where Devin is not installed) |

### Step 7.3 — Fetch inline comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"devin-ai-integration[bot]\" and .created_at > \"$review_window_start\") | {path, line, body}]"
```

**All Devin findings are blocking.** Unlike Greptile, there is no `is_soft_suggestion()` heuristic — both severe (red) and non-severe (yellow) findings block the PR.

### "No Issues Found" handling

When Devin finds no issues, it posts a summary comment containing "No Issues Found". These comments are excluded from the blocking count so the review correctly resolves as `clean`.
