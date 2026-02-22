# Integration: Greptile (Automated PR Review)

This document describes how to use [Greptile](https://greptile.com) as the automated PR review tool in the workflow.

Greptile is **optional**. The workflow functions without it — agents go directly to human review after opening a PR.

---

## What Greptile Adds

- Automated code review on every PR, triggered on open/update
- Catches spec deviations, best practice violations, and security issues before human review
- Reduces human review cycles by closing the feedback loop faster
- The developer agent addresses Greptile's blocking issues before flagging the PR for human review

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

## The Greptile Review Loop

When Greptile is enabled, the developer agent follows this loop after opening a PR:

```
Open PR
   ↓
Wait for Greptile review (check PR comments)
   ↓
Any blocking issues?
   ├── Yes → Fix issues, push, re-trigger Greptile (@greptile review)
   │          Return to "Wait for Greptile review"
   └── No  → Apply agent:ready-for-review label
              Notify human that PR is ready for review
```

### How to re-trigger a Greptile review

After pushing fixes, post a comment on the PR:

```
@greptile review
```

Greptile will re-run its analysis and post updated comments.

### Issue severity

| Severity | How to handle |
|---|---|
| Blocking | Must fix before human review |
| Warning | Fix at discretion; document in PR if deferred |
| Suggestion | Optional improvement |

---

## Developer Agent Instructions (with Greptile)

After opening a PR, the developer agent:

1. Waits for Greptile to post its review (usually within 2-5 minutes)
2. Reads Greptile's comments on the PR
3. Fixes all **blocking** issues
4. Pushes fixes and comments `@greptile review` to re-trigger
5. Repeats until no blocking issues remain
6. Then applies `agent:ready-for-review` and notifies the human

---

## Without Greptile

If Greptile is not installed, the developer agent:

1. Runs the code reviewer agent (or asks the human to run it) before flagging for human review
2. Skips the `@greptile review` step
3. Goes directly to applying `agent:ready-for-review` after CI passes

The code reviewer agent (`04-review-implemented-development-protocol.md`) provides a similar review pass and can partially substitute for Greptile.

---

## Alternative Automated Review Tools

The workflow is not tied to Greptile. Any automated PR review tool can be used — the key requirement is:

1. It posts review comments on the PR (blocking vs. non-blocking distinction)
2. It can be re-triggered after fixes are pushed
3. The developer agent knows how to interpret its output

Update this document with the specifics of your chosen tool if you use an alternative.
