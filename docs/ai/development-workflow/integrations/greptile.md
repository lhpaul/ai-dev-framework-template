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

After each push, record the timestamp and post this comment on the PR:

```bash
last_push_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

gh pr comment <pr_number> --body "@greptile please re-review"
```

### Step 8.2 — Detect review completion

Greptile always posts a review summary when it finishes — even when it finds no issues — so this is the reliable signal that the review cycle is complete. Poll using:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --jq "[.[] | select(.user.login == \"greptile-apps[bot]\" and .submitted_at > \"$last_push_at\")] | length"
```

A result of `> 0` means Greptile has completed a new review after `last_push_at`. A result of `0` means it has not responded yet.

### Step 8.3 — Fetch inline comments

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"greptile-apps[bot]\" and .created_at > \"$last_push_at\") | {path, line, body}]"
```

Apply the blocking vs. suggestion classification rules defined in Step 8.3 of `90-orchestrate-work-protocol.md`.
