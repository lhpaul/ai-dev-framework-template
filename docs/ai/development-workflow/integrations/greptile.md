# Integration: Greptile (Automated PR Review)

This document describes how to use [Greptile](https://greptile.com) as the automated code review platform in the workflow.

Greptile is **optional**. The workflow functions without it — agents go directly to human review after opening a PR. See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the platform-agnostic loop and requirements.

---

## What Greptile Adds

- Automated code review on every PR, triggered on open/update
- Catches spec deviations, best practice violations, and security issues before human review
- Reduces human review cycles by closing the feedback loop faster

---

## Setup

### 1. Install the Greptile GitHub App

Go to [greptile.com](https://greptile.com) and install the GitHub App on your repository. Greptile will automatically review PRs when opened or updated.

### 2. Configure the Review Scope (Optional)

You can guide Greptile's reviews by creating a `.greptile.yml` file at the root of the repository:

```yaml
# .greptile.yml
review:
  # Files or patterns to always include in reviews
  include:
    - "src/**"
    - "packages/**"
  # Files or patterns to exclude
  exclude:
    - "**/*.generated.ts"
    - "docs/**"
  # Reference files that provide context for reviews
  context:
    - "docs/ai/development-workflow/README.md"
    - "docs/best-practices/*.md"
```

---

## Step 8 — Greptile-Specific Implementation

The orchestrator's Step 8 (Automated Reviewer Loop) requires platform-specific commands. Below are the Greptile implementations for each step.

### Bot identity

Greptile posts as `greptile-apps[bot]`. Use this login to filter its comments and reviews from human activity.

### Step 8.1 — Trigger a re-review

After each push, record the timestamp and capture the comment ID (needed for Step 8.2):

```bash
last_push_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

review_comment_url=$(gh pr comment <pr_number> --body "@greptile review")
# Extract numeric comment ID from the URL (e.g. https://github.com/.../pull/18#issuecomment-12345678)
review_comment_id=$(echo "$review_comment_url" | grep -oE '[0-9]+$')
```

### Step 8.2 — Detect review completion

Greptile signals that it has **finished** reviewing by adding a 👍 reaction to the `@greptile review` comment. This is the reliable completion signal regardless of whether it found issues.

```bash
# Poll until Greptile reacts with 👍 on the trigger comment
thumbs_up=$(gh api repos/{owner}/{repo}/issues/comments/{review_comment_id}/reactions \
  --jq "[.[] | select(.content == \"+1\")] | length")
```

| Result | Action |
|---|---|
| `thumbs_up > 0` | Review complete — proceed to Step 8.3 to check for inline comments |
| `thumbs_up == 0` and `elapsed < max_wait` | Not finished yet — wait another `poll_interval` and poll again |
| `thumbs_up == 0` and `elapsed >= max_wait` | Timeout — escalate to human (Step 8.5) |

### Step 8.3 — Fetch inline comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"greptile-apps[bot]\" and .created_at > \"$last_push_at\") | {path, line, body}]"
```

Apply the blocking vs. suggestion classification rules defined in Step 8.3 of `90-orchestrate-work-protocol.md`.
