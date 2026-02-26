# Integration: Automated Code Review Platform (Generic)

This document defines **platform-agnostic** expectations for how agents use an automated code review tool in this workflow.

> Platform-specific setup (how to trigger, poll, and fetch comments) lives in the platform's own integration doc. See [`integrations/greptile.md`](greptile.md) for Greptile.

---

## What the Platform Must Provide

For the orchestrator's automated reviewer loop (Step 8 of `90-orchestrate-work-protocol.md`) to work, the platform must:

1. **Post a review automatically** when a PR is opened or updated
2. **Allow re-triggering** after fixes are pushed (e.g., via a comment or webhook)
3. **Post inline comments** for each finding
4. **Post a review summary** when the analysis is complete — this is the reliable signal that the review cycle is done (even when no issues are found)

---

## What Each Integration Doc Must Define

Each platform-specific integration doc (e.g., `greptile.md`) must specify:

| Requirement | Description |
|---|---|
| **Bot / app identity** | Username or login used to filter the platform's comments from human comments |
| **How to trigger a re-review** | Command or comment to post after pushing fixes |
| **How to detect review completion** | API call or query to check whether a new review summary has been posted after `last_push_at` |
| **How to fetch inline comments** | API call or query to retrieve new inline comments after `last_push_at` |

---

## Without an Automated Reviewer

If no automated review platform is configured, skip Step 8 in the orchestrator protocol. In the Step 6 summary, report: `Automated review: ⏭️ skipped (not configured)`.

The code reviewer agent (`04-review-implemented-development-protocol.md`) can partially substitute — run it before flagging the PR for human review.
