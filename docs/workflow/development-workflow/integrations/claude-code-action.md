# Integration: Claude Code Action (Automated PR Review)

This document describes how to use [Claude Code Action](https://github.com/anthropics/claude-code-action)
as one automated PR reviewer tool in the workflow.

Claude Code Action is **optional**. The workflow functions without it. See
[`integrations/pr-review-platform.md`](pr-review-platform.md) for the
multi-platform loop and aggregation rules.

---

## What Claude Code Action Adds

- Automated inline code review on every PR, powered by Claude
- Catches logic errors, spec deviations, and best practice violations before
  human review
- No per-hour vendor review cap — unlike hosted review services, Claude Code
  Action runs entirely in your own GitHub Actions CI using your own Anthropic
  API key, so usage is limited only by your Anthropic account quota and GitHub
  Actions minutes

---

## Why There Is No Per-Hour Cap

Hosted PR review services (such as CodeRabbit's free tier) impose per-hour
review limits because the vendor bears the inference cost on your behalf. Claude
Code Action is different: the review workflow runs as a standard GitHub Actions
job inside your repository, calls the Anthropic API directly using the
`ANTHROPIC_API_KEY` secret you supply, and exits when finished. There is no
intermediary vendor account — you pay for the Anthropic API tokens used, and
GitHub Actions minutes (free for public repositories, included in the free
tier for private repositories) are the only other resource consumed.

---

## Setup

### 1. Add the `ANTHROPIC_API_KEY` Secret

In your repository settings, navigate to **Settings → Secrets and variables →
Actions** and create a new repository secret named exactly:

```text
ANTHROPIC_API_KEY
```

Obtain the value from [console.anthropic.com](https://console.anthropic.com).
Do not use an alternative secret name — `pr-review-loop.sh` and the companion
reviewer script expect this name by default.

### 2. Reference the Workflow File

The framework template ships a ready-to-use GitHub Actions workflow at:

```text
.github/workflows/claude-code-review.yml
```

This file is added by sibling item #706. Do not copy the workflow contents into
the guide — reference or activate the file as-is. If the workflow file is absent
in your repository, ensure issue #706 (or the equivalent sync from the template)
has been merged.

### 3. Understand the Trigger Mechanism

The shipped workflow is triggered via `workflow_dispatch` — not by posting a
comment on the PR. When `pr-review-loop.sh` runs the `claude-code-action`
platform, it calls the GitHub Actions dispatch API directly:

```bash
gh api "repos/$OWNER/$REPO/actions/workflows/claude-code-review.yml/dispatches" \
  --method POST \
  --raw-field "ref=$DEFAULT_BRANCH" \
  --raw-field "inputs[pr_number]=$PR_NUMBER" \
  --field "return_run_details=true"
```

The dispatch targets the repository's default branch (GitHub serves
`workflow_dispatch` only for workflows registered there) and asks for
`return_run_details=true`, so GitHub answers `200` with the
`workflow_run_id` of the run this dispatch created. The companion binds the
review to that run id (see Step 7.2). A host that answers `204` with no body
(for example, a GitHub Enterprise Server version without
`return_run_details`) cannot be bound and is reported as unavailable.

The companion script `claude-code-action-reviewer.sh` handles this step
automatically. You do not need to dispatch the workflow manually when using
`pr-review-loop.sh`.

### 4. Note the Bot Login for Thread Attribution

When Claude Code Action posts review threads on a PR, the comments appear under
the GitHub App bot login:

```text
claude[bot]
```

The `pr-review-loop.sh` helper and `claude-code-action-reviewer.sh` use this
login to attribute and count review threads. If you use a customised GitHub App
deployment with a different bot login, set:

```bash
export CLAUDE_CODE_ACTION_BOT_LOGIN="your-bot-login[bot]"
```

or pass `--bot-login <login>` to `claude-code-action-reviewer.sh`.

### 5. Add `claude-code-action` to `.ai-dev-workflow.yaml`

Declare `claude-code-action` as a review platform so `pr-review-loop.sh` runs
it automatically:

```yaml
review:
  on_draft:
    github:
      - claude-code-action
```

To run Claude Code Action only after draft GitHub reviewers have already cleared,
place it in the ready phase:

```yaml
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github:
      - claude-code-action
```

This configuration makes Claude Code Action's net-new findings measurable
independently of whether `pr-agent` already found issues.

---

## Step 7 — Claude Code Action Integration

### Preferred helper

When possible, call the repository helper instead of re-implementing the loop
inline:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform claude-code-action
```

It encapsulates the trigger, polling, review-thread classification, and stable
aggregate `RESULT=` output used by the Work Item Runner (and by the Portfolio
Orchestrator when it supervises item-level runs).

The integration is already available: `pr-review-loop.sh` and the companion
`scripts/development-workflow/claude-code-action-reviewer.sh` were added in the
same batch that ships this guide.

### Bot identity

Claude Code Action posts review threads as `claude[bot]`. Use this login to
filter its comments and reviews from human activity.

### Step 7.1 — Trigger a review

After each push, `pr-review-loop.sh` dispatches the workflow via the Actions
API (see Setup §3 for the dispatch command). The companion script
`claude-code-action-reviewer.sh` handles this automatically — you do not need
to dispatch the workflow manually when using the helper.

### Step 7.2 — Detect review completion

Claude Code Action completes its review by finishing the GitHub Actions run it
dispatches. The run is bound to this request only by the `workflow_run_id`
returned by the dispatch (#1789): the companion polls
`repos/$OWNER/$REPO/actions/runs/<workflow_run_id>` and nothing else. It never
searches the run list, and never selects a run by `created_at`, run name, or
`head_sha` — a `workflow_dispatch` run's `head_sha` is the dispatched ref's
tip, not the PR head — so an earlier dispatch's run for the same PR can never
answer for this one.

The companion prints machine-readable dispatch lines on stdout:

| Line | Meaning |
| --- | --- |
| `DISPATCH_RESULT=accepted` and `DISPATCH_WORKFLOW_RUN_ID=<id>` | The response carried `workflow_run_id`; that run is polled |
| `DISPATCH_RESULT=adopted` | A recorded run was adopted (`--adopt-run-id`, below); nothing was dispatched |
| `DISPATCH_RESULT=rejected` | The API rejected the dispatch; exit 3 |
| `DISPATCH_RESULT=workflow_not_found` | The API rejected the dispatch as not found (404); exit 3 |
| `DISPATCH_RESULT=no_workflow_run_id` | The dispatch was accepted but the response (for example an empty `204`) had no integer `workflow_run_id`; exit 3 with `VERDICT: UNAVAILABLE — dispatch response carried no workflow_run_id; the run cannot be bound to this request` |
| `REVIEW_REQUESTED_AT=<iso8601>` and `REVIEW_REQUEST_REF=<run id>` | Printed once the run is bound; the loop records them so its automatic re-wait can adopt the same run |

| Result                                           | Action                                                                |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| Bound run completed with `conclusion: success`   | Review complete — proceed to Step 7.3                                 |
| Bound run in progress and `elapsed < max_wait`   | Not finished yet — wait another `poll_interval` and poll again        |
| Bound run not completed at `elapsed >= max_wait` | **No verdict yet** — companion exit 4; the loop reports `waiting_on_reviewer` / `reviewer-no-verdict-yet` (detail `run_not_completed`), not an escalation |
| Bound run completed with any other conclusion    | **Reviewer failed** — companion exit 2; the loop reports `escalate` / `claude_code_action_run_failed` |
| Workflow file absent, dispatch rejected, or no `workflow_run_id` | Unavailable — companion exit 3; the loop reports `escalate` / `unavailable`, never clean and never No verdict yet |

**Current-revision binding (`--head-sha`).** The loop passes its head as
`--head-sha <40-hex sha>` (omitted when the loop head is unknown). A
`claude[bot]` review then counts only when its `commit_id` equals that head,
in addition to being submitted at or after the dispatch time, so a review of
another revision is never this head's verdict.

**Automatic re-wait (`--adopt-run-id` / `--adopt-requested-at`).** When the
loop re-waits once on the same revision (Protocol 91 Step 7,
`NO_VERDICT_REWAIT=available`), it passes the recorded run id and request
time instead of dispatching again (both flags are required together). The
companion reads `actions/runs/<id>` and adopts it only when the id matches,
the run's `path` ends with the workflow file, and its name's `PR #<n>` token
names this PR; it then polls only that run and keeps the original dispatch
time as the review boundary. A run that fails those checks or cannot be read
is not adopted: the companion prints a `WARN` and dispatches normally. Only
the run recorded for the current head and run id is ever adopted; a recorded
request time without a run id passes no adoption flags.

The wait budget is `max_wait` from the loop: 1200 s by default, configurable
under `review.wait_budgets.claude-code-action` up to the companion's own
3600 s maximum (see "Reviewer wait budgets and outcome classes" in
[`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md#reviewer-wait-budgets-and-outcome-classes-1789)).

### Step 7.3 — Fetch review threads

After the Actions run completes, the script checks for unresolved review threads
posted by `claude[bot]` on the PR:

```bash
gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            isResolved
            comments(first: 1) {
              nodes { author { login } body }
            }
          }
        }
      }
    }
  }' \
  -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" \
  | jq --arg bot "$BOT_LOGIN_PLAIN" \
      '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select(.comments.nodes[0].author.login == $bot)' | wc -l
```

> **Note**: GitHub's GraphQL API returns bot logins **without** the `[bot]`
> suffix (e.g., `claude`), unlike the REST API which includes it (e.g.,
> `claude[bot]`). The companion script strips `[bot]` from the configured
> `CLAUDE_CODE_ACTION_BOT_LOGIN` value before building GraphQL filters.
> When setting `CLAUDE_CODE_ACTION_BOT_LOGIN`, use the full REST format
> including `[bot]` (e.g., `custom-app[bot]`); the script normalises it
> for GraphQL queries automatically.

### Blocking vs. suggestion classification

Claude Code Action posts all findings as review threads. The integration treats
every unresolved thread from `claude[bot]` as blocking. There is no severity
marker system for this platform — address all open threads before the loop
advances.

---

## Model Selection

Claude Code Action uses `claude-sonnet-4-6` as the default review model. Sonnet
provides a strong balance of analysis depth and cost for most PRs.

| Model               | Recommended for                                        | Approximate cost context |
| ------------------- | ------------------------------------------------------ | ------------------------ |
| `claude-haiku-4-5`  | Small docs or config PRs                               | Lowest (fastest)         |
| `claude-sonnet-4-6` | Default — most feature/fix PRs                         | Moderate                 |
| `claude-opus-4-5`   | Large diffs (500+ lines) or when depth matters most    | Highest                  |

To change the model, set the `model` input in `.github/workflows/claude-code-review.yml`:

```yaml
with:
  model: claude-opus-4-5
```

Model names and pricing change over time. Verify current model availability and
pricing at [console.anthropic.com](https://console.anthropic.com) before
selecting a model for production use.

---

## Step 7a — Internal Reviewer (Draft PRs)

Claude Code Action can act as a Step 7a internal reviewer on draft PRs before
they are converted to non-draft. The companion script
`claude-code-action-reviewer.sh` is used directly for this mode.

Configure in `.ai-dev-workflow.yaml`:

```yaml
review:
  on_draft:
    runner:
      - claude
    github:
      - claude-code-action
```

> **Note**: Register `claude-code-action` under `review.on_draft.github` or
> `review.on_ready.github`, not `review.on_draft.runner` — Protocol 91 Step 7a
> only accepts `claude`, `cursor`, `codex`, and `coderabbit` as runner
> reviewers. See Setup §5 for platform configuration.

### Exit code semantics

`claude-code-action-reviewer.sh` emits the following exit codes, which the
Step 7a gate maps to outcomes:

| Exit code | Meaning        | Gate outcome                                              |
| --------- | -------------- | --------------------------------------------------------- |
| `0`       | APPROVED       | Reviewer approved — continue to the next reviewer         |
| `1`       | NEEDS_REVISION | Blocking threads found — fix and re-run the review cycle  |
| `2`       | FAILED         | The bound run completed with a conclusion other than `success`, or the arguments were invalid; `pr-review-loop.sh` reports `escalate` / `claude_code_action_run_failed` |
| `3`       | UNAVAILABLE    | Workflow file absent, dispatch rejected, dispatch response without `workflow_run_id`, or no review could be verified; `pr-review-loop.sh` reports `escalate` / `unavailable` |
| `4`       | NO_VERDICT_YET | The bound run did not complete within `max_wait`; `pr-review-loop.sh` reports `waiting_on_reviewer` / `reviewer-no-verdict-yet` (no `reviewer-failed` label) |

---

## Troubleshooting

| Symptom                                                        | Cause                                                          | Resolution                                                                                                                      |
| -------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `RESULT=escalate REASON=unavailable`                           | Workflow file absent or `ANTHROPIC_API_KEY` not set            | Confirm `.github/workflows/claude-code-review.yml` exists and the secret is added in repository settings                       |
| `RESULT=waiting_on_reviewer REASON=reviewer-no-verdict-yet`    | The bound run did not complete within its wait budget (1200 s by default in the loop) | Not a failure. Let the runner's automatic re-wait adopt the same run; if the review consistently takes longer, raise `review.wait_budgets.claude-code-action` (at most 3600) |
| `RESULT=escalate REASON=claude_code_action_run_failed`         | The bound run completed with a conclusion other than `success` | Open the run named in the `found run — id=` log line and fix the workflow failure                                             |
| `DISPATCH_RESULT=no_workflow_run_id`                           | The host answered the dispatch without a `workflow_run_id` (for example `204`) | The run cannot be bound; use a GitHub host that supports `return_run_details`. Time-window run selection is intentionally not used as a fallback |
| Review threads not detected after Actions run succeeds         | Bot login mismatch                                             | Confirm the bot posting threads is `claude[bot]`; if using a custom App, set `CLAUDE_CODE_ACTION_BOT_LOGIN` to the correct login |
| `pr-review-loop.sh` reports `skipped` for `claude-code-action` | Platform not listed in `review.on_draft.github` or `review.on_ready.github` | Add `claude-code-action` to the appropriate GitHub reviewer bucket in `.ai-dev-workflow.yaml`                                    |
| Workflow dispatched but no Actions run appears                 | Dispatch accepted but workflow file not found or wrong ref     | Confirm `.github/workflows/claude-code-review.yml` exists on the default branch and the dispatch `ref` matches the repository default branch |

---

## See Also

- [`pr-review-platform.md`](pr-review-platform.md) — Step 7 multi-platform review loop
- [`coderabbit.md`](coderabbit.md) — CodeRabbit integration (opt-in reviewer)
- Protocol 93 — [`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md)
- Protocol 03 — [`../protocols/03-implement-development-protocol.md`](../protocols/03-implement-development-protocol.md)
- `scripts/development-workflow/claude-code-action-reviewer.sh` — companion script
