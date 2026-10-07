# Integration: PR-Agent (Automated PR Review)

This document describes how to use [PR-Agent](https://github.com/qodo-ai/pr-agent) (open source, by Qodo) as an automated PR reviewer. Unlike cloud-based tools, PR-Agent runs as a **GitHub Actions workflow** and calls a third-party LLM API you supply — there is no per-seat fee.

PR-Agent is **optional**. The workflow functions without it. See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the multi-platform loop and aggregation rules.

---

## What PR-Agent Adds

- Explicit automated code review when the reviewer loop or a maintainer requests
  `/review`
- AI-powered analysis powered by any LLM you choose (DeepSeek, Kimi, OpenAI, Claude, Gemini, etc.)
- No per-seat pricing — cost is purely LLM token usage (~$5–30/month at typical batch volumes)
- Interactive: developers can post `/review` in PR comments to trigger a review
  on demand

---

## Setup

### 1. Add the GitHub Actions Workflow

The workflow file is already committed at `.github/workflows/pr-agent.yml`.
It triggers automatically on low-volume PR lifecycle events
(`opened`, `reopened`, `ready_for_review`) and on the explicit `/review`
PR comment command. It does **not** run on every PR synchronize event by
default, and arbitrary human comments do not trigger it.

### 2. Choose a Model and Add the API Key

**DeepSeek (default — cheapest option):**

1. Create an account at [platform.deepseek.com](https://platform.deepseek.com)
2. Generate an API key
3. In your GitHub repository go to **Settings → Secrets → Actions** and add:
   - `DEEPSEEK_API_KEY` = your DeepSeek API key

**Kimi K2.6 (Moonshot AI — alternative):**

1. Create an account at [platform.moonshot.ai](https://platform.moonshot.ai)
2. Generate an API key
3. Add `MOONSHOT_API_KEY` to GitHub Actions secrets
4. In `.pr_agent.toml`, uncomment the Kimi model block and comment out the DeepSeek block
5. In `.github/workflows/pr-agent.yml`, swap `DEEPSEEK_API_KEY` for `MOONSHOT_API_KEY`

### 3. Verify the Integration

Open a PR or post `/review` on an existing PR and confirm that
`github-actions[bot]` posts an issue comment with a **PR Reviewer Guide**
section. The comment body will contain one of two stable markers:

- `No major issues detected` — clean (`RESULT=clean`)
- `Recommended focus areas for review` + hard-blocker label — blocking (`RESULT=needs_fixes`)
- `Recommended focus areas for review` + advisory labels only — clean (`RESULT=clean`)

---

## Pricing Reference (May 2026)

| Model                           | Input ($/1M tokens) | Output ($/1M tokens) | Notes                                         |
| ------------------------------- | ------------------- | -------------------- | --------------------------------------------- |
| DeepSeek Chat (alias: v4-flash) | $0.14               | $0.28                | Most affordable                               |
| DeepSeek V4 Pro                 | $0.44               | $0.87                | Better quality; discount expires May 31, 2026 |
| Kimi K2.6                       | $0.74               | $3.49                | Strong alternative; 262K context window       |

For a moderate batch workflow (100 PRs/month, ~20K tokens each), expect **$3–15/month** with DeepSeek.

To review the GitHub Actions runner-time side of PR-Agent usage, run the
lightweight workflow audit in [`actions-cost-audit.md`](actions-cost-audit.md).
That audit reports recent workflow run counts and wall time; it does not replace
provider token-cost estimates or GitHub billing dashboards.

---

## Model Configuration

Model settings live in two places:

- [`.pr_agent.toml`](../../../../.pr_agent.toml) — `model`, `fallback_models`, `model_weak`
- [`.github/workflows/pr-agent.yml`](../../../../.github/workflows/pr-agent.yml) — the same three keys are also pinned as `config.model`, `config.fallback_models`, `config.model_weak` GHA env vars

A local `.pr_agent.toml` has higher precedence than GitHub Actions env vars — TOML values override env-based settings, not the other way around. Both are set here as defense-in-depth: the TOML file is the authoritative source, and the GHA env vars ensure the same values are active during the action startup phase before TOML is fully merged.

To switch models: update **all three keys** (`model`, `fallback_models`, `model_weak`) in **both** the TOML file and the workflow env vars, then swap the API key secret in the workflow. The `model_weak` key controls ancillary tasks (PR description generation, classification, file summaries) and must use the same provider as `model` so only one API key needs to be configured.

---

## Step 7 — PR-Agent-Specific Implementation

The **Work Item Runner's** Step 7 (Automated Reviewer Loop) requires platform-specific commands. Below are the PR-Agent adapter details used by the shared helper.

### Preferred helper

When possible, call the repository helper instead of re-implementing the loop inline:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform pr-agent
```

It encapsulates the polling, review-state classification, and stable aggregate `RESULT=` output used by the **Work Item Runner** (and by the **Portfolio Orchestrator** when it supervises item-level runs).

### Bot identity

PR-Agent posts as `github-actions[bot]` (the default identity when using `GITHUB_TOKEN`). Reviews are identified by both the bot login and the presence of `PR Reviewer Guide` in the review body (a stable PR-Agent marker), which distinguishes them from any other GHA workflows that might post reviews.

### Step 7.1 — Trigger a re-review

`pr-review-loop.sh` explicitly requests PR-Agent by posting the same command a
maintainer would post manually:

```text
/review
```

The workflow only treats an exact `/review` PR comment as an issue-comment
trigger. General PR discussion comments do not run PR-Agent. The exact command
check is also the loop-prevention control: PR-Agent's own output does not match
`/review`, while trusted reviewer-loop automation can still request a configured
review even when it authenticates as a bot or GitHub App.

### Step 7.2 — Detect review completion

PR-Agent signals completion by posting a plain issue comment (not a formal GitHub PR review) from `github-actions[bot]` whose body contains `PR Reviewer Guide` (PR-Agent's stable output marker). PR-Agent keeps **one persistent summary comment** and edits it in place, so the comment's `created_at` or `updated_at` cannot show which revision it describes. Since #1789 the helper accepts a summary comment for the current head `H` only by one of two rules, never by its time:

- **Rule (a) — head marker.** With PR-Agent's hidden `<!-- pr-agent-review-state:v1 … -->` block removed, the visible body contains the marker line `Review updated until commit https://<host>/<owner>/<repo>/commit/<H>)` naming the full 40-character `H`. A match of `H` anywhere else, including inside the review-state block, does not count. A block opener with no `-->` terminator makes the comment unbound (fail closed). PR-Agent writes this marker whenever it updates its summary.
- **Rule (b) — first summary bound to its run.** An unedited first summary with no marker (`updated_at == created_at`) is accepted only when every condition holds: a `PR-Agent review` check run on `commits/H/check-runs` completed with conclusion `success` and its `started_at <= created_at <= completed_at`; no `PR-Agent review` check run on `H` is queued or in progress; no `pull_request` run of that workflow on the PR's head branch for another revision was in progress at `created_at`; and no `/review` comment on the PR was posted at or before the summary (an `issue_comment` run records neither the PR nor the revision it read). Any failed API read or failed condition leaves the summary unbound.

An unbound summary keeps the helper polling. A first summary that rule (b)
cannot bind (for example, because a `/review` preceded it or another
revision's run overlapped it) ends that invocation in the `no_review` kept
skip, never in a verdict for another revision; any later PR-Agent run on `H`
rewrites the summary with the `H` marker, which rule (a) accepts.

| Result                                                                   | Action                                                                          |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Bound comment with `No major issues detected`                            | Review complete — clean                                                         |
| Bound comment with `Recommended focus areas for review` + hard-blocker label | Review complete — blocking                                                   |
| Bound comment with `Recommended focus areas for review` + advisory labels only | Review complete — clean (advisory only)                                   |
| Bound comment with neither marker                                        | Ambiguous — escalate for human review                                           |
| No bound comment and `elapsed < max_wait`                                | GHA still running — wait `poll_interval` and poll again                         |
| The newest `PR-Agent review` check run on `H` completed `failure`, `timed_out`, `cancelled`, `action_required`, `startup_failure`, or `stale`, and no summary is bound to `H` | **Reviewer failed** — `RESULT=escalate`, `REASON=pr_agent_run_failed`, `reviewer-failed` applied (see below for when) |
| `elapsed >= max_wait` and no bound comment                               | Kept skip — `RESULT=skipped`, `REASON=no_review`, `NO_VERDICT_YET=1`, `DISPLAY_RESULT=no verdict yet (non-blocking skip: no_review)`; reported as No verdict yet, no `reviewer-failed` label (GHA may not have run, e.g., fork PR with no secrets access or PR-Agent unavailable) |

**When a failed PR-Agent run is a failure.** The newest `PR-Agent review` check
run on `H` (latest `started_at`, then highest id) governs; a newer run on `H`
or a summary bound to `H` supersedes an earlier failed one. When the helper did
not post or adopt a `/review` request because a run on `H` was already active,
a failure-type result returns `pr_agent_run_failed` on that poll. When the
helper's own request is outstanding (it posted `/review`, reused a trigger
recorded for `H`, or adopted the recorded request in a re-wait), it keeps
polling until the budget ends, because only a summary bound to `H` or a newer
run on `H` can answer that request; at the budget end a failure-type newest run
on `H` with no bound summary gives `pr_agent_run_failed` instead of the kept
skip. A failed `/review` (`issue_comment`) run on its own is never read as
failure, because its check run sits on the default-branch tip, not on `H`. A
failed read keeps the last successful read; with no successful read there is
no failure signal.

**Trigger reuse.** In a fresh run the helper reuses a recent `/review` comment
inside the reuse window only when the loop's ledger records that comment's id
as a request for the current head; an older revision's `/review` never
suppresses the new request. When the runner re-waits once on the same revision
(Protocol 91 Step 7, `NO_VERDICT_REWAIT=available`), the request the first run
recorded is treated as still pending and nothing is posted, even when its
comment id is empty.

PR-Agent waits for its own budget: 1200 s by default, configurable as
`review.wait_budgets.pr-agent` (see "Reviewer wait budgets and outcome
classes" in
[`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md#reviewer-wait-budgets-and-outcome-classes-1789)).

The summary comment is the completion signal; the `PR-Agent review` check runs
on `H` are read only to bind a first summary (rule (b)) and to detect a failed
run.

### Step 7.3 — Classify findings

PR-Agent's blocking classification is based on stable body-content markers in its `PR Reviewer Guide` comment:

- `No major issues detected` → clean (`RESULT=clean`)
- `Recommended focus areas for review` → **may or may not be blocking** (see label check below)
- Neither marker present → ambiguous (`RESULT=escalate`, requires human review)

**Label-based severity check**: PR-Agent emits `Recommended focus areas for review` even for purely advisory findings like `Possible Issue`. The classifier inspects the bold `<strong>` labels inside the section's `<details>` elements:

| Label                          | Blocking?                                                           |
| ------------------------------ | ------------------------------------------------------------------- |
| `Critical`                     | Yes — `RESULT=needs_fixes`                                          |
| `Must Fix`                     | Yes — `RESULT=needs_fixes`                                          |
| `Breaking Change`              | Yes — `RESULT=needs_fixes`                                          |
| `Security Concern`             | Yes — `RESULT=needs_fixes` (security findings require human review) |
| `API Change`                   | Yes — `RESULT=needs_fixes` (compatibility concern)                  |
| `Backward Compatibility`       | Yes — `RESULT=needs_fixes` (compatibility concern)                  |
| `Possible Issue`               | No — `RESULT=clean`                                                 |
| `Edge Case`                    | No — `RESULT=clean` (robustness suggestion)                         |
| `Logic Gap`                    | No — `RESULT=clean` (advisory suggestion)                           |
| `Documentation Inconsistency`  | No — `RESULT=clean` (doc suggestion)                                |
| Any other (unrecognized) label | Yes — `RESULT=needs_fixes` (conservative)                           |
| No `<strong>` labels parsed    | Yes — `RESULT=needs_fixes` (unreadable format)                      |

When `Recommended focus areas for review` is present but contains **only** explicitly-known advisory labels (`Possible Issue`, `Edge Case`, `Logic Gap`, `Documentation Inconsistency`), the classifier returns `clean`. Hard-blocker labels, security labels (`Security Concern`), and compatibility labels (`API Change`, `Backward Compatibility`) always block.

**Classifier-safe fallback**: If an agent cannot read the full PR-Agent comment body
because the runner's classifier or tool policy blocks the structured review text, do
not stop the reviewer loop. Re-run PR-Agent through `pr-review-loop.sh --platform
pr-agent` and consume only the helper's key-value output (`RESULT`, counts, advisory
labels, and possible-issue evaluation). Protocol 93 documents this label-only path;
the full review body should not be required for the agent to decide whether to proceed,
dispatch a fixer, or escalate.

### Fork PR handling

When a PR is opened from a fork, GitHub Actions **does not expose repository secrets** to the workflow. This means `DEEPSEEK_API_KEY` (or the alternative key) is unavailable and the workflow will fail silently — no review is posted. When its wait budget ends, the helper reports the kept No verdict yet skip, `RESULT=skipped` with `REASON=no_review`. This is expected behavior and is not a configuration error.

If fork PRs need automated review, consider using a GitHub App token instead of `GITHUB_TOKEN`.

---

## Enabling Interactive Commands

With the constrained `issue_comment` trigger active, the template default only
runs PR-Agent for the explicit review command:

| Command           | Effect                                 |
| ----------------- | -------------------------------------- |
| `/review`         | Re-run the full code review            |

Downstream repositories may opt into additional PR-Agent commands such as
`/describe`, `/improve`, or `/ask <question>`, but doing so increases
issue-comment fan-out and should be an explicit local decision.

## Migration Notes for Downstream Repositories

Earlier versions of this template ran PR-Agent on every same-repository PR
synchronize event and on every human PR comment. That was convenient, but it
could consume private-repository runner minutes even when PR-Agent output was
not needed.

After this change:

- pushing a new commit to a PR does not run PR-Agent by default;
- arbitrary human comments do not run PR-Agent;
- `/run-reviewer-loop`, `/run-item`, and `/run-epic` still request PR-Agent when
  the effective review config includes `pr-agent`;
- maintainers can still run PR-Agent manually by posting `/review`;
- downstream projects that want broader automatic PR-Agent behavior must opt in
  by editing `.github/workflows/pr-agent.yml` locally.
