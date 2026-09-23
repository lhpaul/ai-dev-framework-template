# Integration: Ronda (Automated PR Review)

This document describes how to use Ronda as one automated PR reviewer tool
in the workflow.

Ronda is **optional**. The workflow functions without it. See
[`integrations/pr-review-platform.md`](pr-review-platform.md) for the
multi-platform loop and aggregation rules.

Ronda itself (setup, enablement, and product behavior) is maintained in its
own repository (`lhpaul/ronda`). This document covers only the ADF-side
adapter: how `pr-review-loop.sh` consumes Ronda's GitHub-facing output.

---

## What Ronda Adds

- Automated code review that reacts to the PR automatically — no trigger
  comment needed
- A GitHub pull-request review plus a single `Ronda review` check run per
  head SHA, so review completion is a normal GitHub signal (visible in the
  PR's Checks tab and Reviews list)

---

## Bot identity and check name

Ronda posts as `ronda[bot]` and its check run is named `Ronda review` by
default. Both are overridable via env vars (see
[Configuration](#configuration) below) if a deployment uses different values.

---

## Step 7 — Ronda-Specific Implementation

The **Work Item Runner's** Step 7 (Automated Reviewer Loop) requires
platform-specific commands. Below are the Ronda adapter details used by the
shared helper.

### Preferred helper

When possible, call the repository helper instead of re-implementing the
loop inline:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform ronda
```

It encapsulates the polling and the stable aggregate `RESULT=` output used
by the **Work Item Runner** (and by the **Portfolio Orchestrator** when it
supervises item-level runs).

### Step 7.1 — Trigger a re-review

**No trigger needed.** Ronda reacts to the PR automatically; there is no
trigger comment.

### Step 7.2 — Detect review completion

Ronda's check run is the authoritative terminal signal. Per Ronda's
architecture, the check run is created **exactly once, at the end of a
pass, already `completed`** — there is deliberately no `in_progress` write.

The helper script polls `repos/{owner}/{repo}/commits/{head_sha}/check-runs`
for a check run named `Ronda review`, re-resolving the PR's head SHA on
every poll:

| Check-run state for the current head SHA                       | Action                                                                |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| No check run found yet                                           | **Not finished yet** — never treated as clean or skipped; keep polling |
| Found, `status != completed`                                     | Not finished yet — keep polling (defensive; Ronda should not emit this)|
| Found, `status=completed`, `conclusion=success`                  | `RESULT=clean`                                                         |
| Found, `status=completed`, `conclusion=failure` or `action_required` | `RESULT=needs_fixes`                                                |
| Found, `status=completed`, any other conclusion                  | `RESULT=escalate` (`REASON=ronda_unexpected_conclusion`) — fail closed  |
| `max_wait` exhausted with no completed run observed               | `RESULT=escalate` (`REASON=timeout`)                                   |

Because the check-runs query is scoped to the current head SHA on every
poll, a new commit pushed mid-poll naturally supersedes any in-flight pass
— the loop keys on head SHA, not on a review or check-run count.

### Step 7.3 — Fetch inline comments

When the check run concludes `failure` or `action_required`, the helper
looks up Ronda's pull-request review for the current head SHA and counts
its inline review comments for `COMMENT_COUNT`/`BLOCKING_COUNT`:

<!-- workflow-shell-contract: bash-zsh -->
```bash
gh api --paginate repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  --jq '[.[] | select(.user.login == "ronda[bot]" and .commit_id == "'"$head_sha"'")] | last | .id'
gh api --paginate repos/{owner}/{repo}/pulls/{pr_number}/reviews/{review_id}/comments
```

If Ronda placed its findings in the review body rather than as inline
comments (so no comments are found), `BLOCKING_COUNT` is floored to 1 so a
`failure`/`action_required` conclusion is never reported with zero blocking
findings.

---

## Configuration

Declare `ronda` in `review.on_draft.github` or `review.on_ready.github` in
`.ai-dev-workflow.yaml`:

```yaml
review:
  on_ready:
    github:
      - ronda
```

Env var overrides:

| Variable            | Default          | Purpose                             |
| -------------------- | ---------------- | ------------------------------------ |
| `RONDA_BOT_LOGIN`    | `ronda[bot]`     | Bot login used to filter reviews     |
| `RONDA_CHECK_NAME`   | `Ronda review`   | Check-run name polled for completion |

---

## Known Limitations

- **No manual re-trigger.** Ronda reacts to pushes automatically; there is
  no documented trigger comment to force a fresh pass out of band.
- **Vendor-maintained details.** The check-run name, bot login, and pass
  semantics are controlled by Ronda and may change; consult `lhpaul/ronda`
  for the authoritative product behavior.
