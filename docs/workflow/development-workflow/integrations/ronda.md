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

Ronda's check run is named `Ronda review` by default. The review verdict is
read from that check run alone, so the adapter's verdict path does not depend
on who authored the review: reviews posted through Ronda's reusable GitHub
Actions workflow are authored by `github-actions[bot]`, while a GitHub App
deployment posts as `ronda[bot]`. Both names are overridable via env vars (see
[Configuration](#configuration) below).

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
| Found, `status=completed`, `conclusion=success`, summary `Blocking: 0` | `RESULT=clean` (`SUGGESTION_COUNT` = Important + Nit)            |
| Found, `status=completed`, `conclusion=success`, summary `Blocking: N` (N ≥ 1) | `RESULT=needs_fixes` (`REASON=ronda_blocking_findings`, `BLOCKING_COUNT=N`) |
| Found, `status=completed`, `conclusion=success`, severity line missing, duplicated, or unparseable | `RESULT=escalate` (`REASON=ronda_severity_unparseable`) — fail closed |
| Found, `status=completed`, `conclusion=failure`                  | `RESULT=escalate` (`REASON=ronda_pass_failed`, `RONDA_CHECK_TITLE` names the cause) |
| Found, `status=completed`, any other conclusion (including `action_required`) | `RESULT=escalate` (`REASON=ronda_unexpected_conclusion`) — fail closed |
| `max_wait` exhausted with no completed run observed               | **No verdict yet** — `RESULT=waiting_on_reviewer` (`REASON=reviewer-no-verdict-yet`, `WAIT_EXPIRED_DETAIL=check_not_completed`), exit 4; not an escalation and no `reviewer-failed` label |
| The check-run read fails (including an HTTP 401 or 403 refusal)   | `RESULT=escalate` (`REASON=fetch-failed`), `reviewer-failed` applied; never No verdict yet |

`max_wait` is Ronda's own wait budget: 1200 s by default, configurable as
`review.wait_budgets.ronda` (see "Reviewer wait budgets and outcome classes"
in
[`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md#reviewer-wait-budgets-and-outcome-classes-1789)).
A `failure` conclusion stays Reviewer failed (`ronda_pass_failed`): it is the
pass's own report that it could not complete.

Because the check-runs query is scoped to the current head SHA on every
poll, a new commit pushed mid-poll naturally supersedes any in-flight pass
— the loop keys on head SHA, not on a review or check-run count.

Ronda's consumption contract (`lhpaul/ronda`,
`docs/adoption/ronda-review-adoption.md` §4) defines the conclusion as
whether the **pass** completed, not whether it found problems:

- `success` — the pass worked, **with or without findings**. A successful
  pass can carry Blocking findings, so `success` alone is never clean.
- `failure` — the pass could not complete (timed out, model unavailable,
  credential missing or invalid, changes too large, unusable model output,
  or an unexpected error). That is an infrastructure failure, not a code
  finding, so the loop escalates instead of sending the fixer after
  findings that do not exist.

### Step 7.3 — Read the finding verdict

On a successful pass the check-run summary carries exactly one severity
line (produced by `buildCheckRunOutput` in Ronda's `src/core/summary.ts`):

```text
Blocking: 0, Important: 1, Nit: 0
```

The helper reads the counts from that line of the same check run it polled
— no review or review-comment lookup is involved in the verdict.
`BLOCKING_COUNT` is the Blocking count, `SUGGESTION_COUNT` is Important +
Nit, and `COMMENT_COUNT` is the total. Exactly one line may start with a
`Blocking:` label (case-insensitive, even indented or emphasized), and that
line must be well-formed; trailing whitespace is tolerated. A missing,
duplicated, or malformed line escalates rather than being guessed clean, so
a valid `Blocking: 0` line cannot mask a second malformed one. If Ronda changes that line's format, the loop fails
closed (`ronda_severity_unparseable`) until the adapter is updated.

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
| `RONDA_BOT_LOGIN`    | `ronda[bot]`     | Bot login used by the unresolved-thread and readiness checks (not by the verdict); set `github-actions[bot]` for the Actions ingress |
| `RONDA_CHECK_NAME`   | `Ronda review`   | Check-run name polled for completion and verdict |

---

## Known Limitations

- **No manual re-trigger.** Ronda reacts to pushes automatically; there is
  no documented trigger comment to force a fresh pass out of band.
- **Vendor-maintained details.** The check-run name, bot login, summary
  severity-line format, and pass semantics are controlled by Ronda and may
  change; consult `lhpaul/ronda` for the authoritative product behavior.
