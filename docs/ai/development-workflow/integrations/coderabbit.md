# Integration: CodeRabbit (Automated PR Review)

This document describes how to use [CodeRabbit](https://www.coderabbit.ai) as one automated PR reviewer tool in the workflow.

CodeRabbit is **optional**. The workflow functions without it. See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the multi-platform loop and aggregation rules.

---

## What CodeRabbit Adds

- AST-based code analysis that catches race conditions, memory leaks, security vulnerabilities, and logic errors
- Severity-classified findings (Critical, Major, Minor) with inline suggestions
- Complements other reviewers by providing static analysis from a different angle

---

## Usage Modes

CodeRabbit supports two independent usage modes in this framework:

### CLI-only (Path A — default)

Use the CodeRabbit CLI locally before pushing. No GitHub App needed.

```bash
# Install
brew install coderabbit
# or: curl -fsSL https://cli.coderabbit.ai/install.sh | sh

# Authenticate
coderabbit auth login

# In Claude Code
/plugin install coderabbit
/coderabbit:review
```

The `.coderabbit.yaml` at the repo root ships with `auto_review.enabled: false` so the GitHub App (if installed) does not auto-review PRs.

### External PR reviewer (Path B)

To enable CodeRabbit as a Step 7 automated PR reviewer platform:

1. Set `reviews.auto_review.enabled: true` in `.coderabbit.yaml`
2. Add `coderabbit` to `review.platforms` in `.ai-dev-workflow.yaml`
3. Install the CodeRabbit GitHub App on the repository

---

## Setup (Path B only)

### 1. Install the CodeRabbit GitHub App

Go to [coderabbit.ai](https://www.coderabbit.ai) and install the GitHub App on your repository. Enable auto-review so CodeRabbit automatically reviews PRs when code is pushed.

### 2. Enable auto-review in `.coderabbit.yaml`

```yaml
reviews:
  auto_review:
    enabled: true
```

### 3. Add to `.ai-dev-workflow.yaml`

```yaml
review:
  platforms:
    - coderabbit
```

### 4. Verify Auto-Review Is Active

Push a commit to an open PR and confirm that CodeRabbit posts review comments. The bot posts as `coderabbitai[bot]`.

---

## Step 7 — CodeRabbit-Specific Implementation

The **Work Item Runner's** Step 7 (Automated Reviewer Loop) requires platform-specific commands. Below are the CodeRabbit adapter details used by the shared helper.

### Preferred helper

When possible, call the repository helper instead of re-implementing the loop inline:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform coderabbit
```

It encapsulates the polling, comment classification, and stable aggregate `RESULT=` output used by the **Work Item Runner** (and by the **Portfolio Orchestrator** when it supervises item-level runs).

### Bot identity

CodeRabbit posts as `coderabbitai[bot]`. Use this login to filter its comments and reviews from human activity.

### Step 7.1 — Trigger a re-review

**No trigger needed.** CodeRabbit auto-reviews on every push when `auto_review.enabled` is `true` in `.coderabbit.yaml`. There is no trigger comment and therefore no `REVIEW_COMMENT_ID`.

### Step 7.2 — Detect review completion

CodeRabbit signals completion in one of these ways:

1. **Review submission** — a `COMMENTED` review posted by `coderabbitai[bot]` after the HEAD commit timestamp
2. **Summary comment update** — the PR issue comment containing `<!-- This is an auto-generated comment: summarize by coderabbit.ai -->` no longer contains "Currently processing"

The helper script checks for a CodeRabbit review on each poll iteration. If a review is found submitted after the HEAD commit, the review is considered complete.

| Result | Action |
| --- | --- |
| CodeRabbit review found after HEAD commit | Review complete — proceed to Step 7.3 |
| No review yet and `elapsed < max_wait` | Not finished yet — wait another `poll_interval` and poll again |
| `elapsed >= max_wait` and no CodeRabbit activity detected | Stale findings recovery, then skip as `no_review` if none found |
| `elapsed >= max_wait` and CodeRabbit activity was detected | Timeout — escalate to human |

### Step 7.3 — Fetch inline comments and reviews

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"coderabbitai[bot]\" and .created_at > \"$since_iso\" and .in_reply_to_id == null) | {path, line, body}]"
```

Additionally, `CHANGES_REQUESTED` reviews posted by `coderabbitai[bot]` after the HEAD commit are also fetched from the reviews endpoint and counted as blocking, regardless of the emoji severity marker in their body. This matches the behavior of the other platform adapters.

### Blocking vs. suggestion classification

Unlike Devin (where all findings are blocking), CodeRabbit inline comments include severity markers that determine blocking status:

| Severity marker | Classification |
| --- | --- |
| `🔴 Critical` | Blocking |
| `🟠 Major` | Blocking |
| `🟡 Minor` | Suggestion (non-blocking) |
| `🟢 Low` or no marker | Suggestion (non-blocking) |

The adapter parses the comment body for these emoji+label patterns. Comments without a recognized severity marker default to suggestion.

### Reply thread handling

CodeRabbit posts findings as inline comments on code lines. The adapter filters out reply comments (`in_reply_to_id != null`) to avoid double-counting a finding and its reply as separate items. Only top-level inline comments are counted.

### Resolved comment handling

When CodeRabbit detects fixes in subsequent commits, it may update or resolve prior findings. The adapter excludes comments that are replies or resolved confirmations from the blocking count.
