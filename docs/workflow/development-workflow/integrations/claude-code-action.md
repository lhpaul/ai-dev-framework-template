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

```
ANTHROPIC_API_KEY
```

Obtain the value from [console.anthropic.com](https://console.anthropic.com).
Do not use an alternative secret name — `pr-review-loop.sh` and the companion
reviewer script expect this name by default.

### 2. Reference the Workflow File

The framework template ships a ready-to-use GitHub Actions workflow at:

```
.github/workflows/claude-code-review.yml
```

This file is added by sibling item #706. Do not copy the workflow contents into
the guide — reference or activate the file as-is. If the workflow file is absent
in your repository, ensure issue #706 (or the equivalent sync from the template)
has been merged.

### 3. Configure the Trigger Phrase

The shipped workflow dispatches Claude Code Action when a specific comment is
posted on a PR. The default trigger phrase is:

```
@claude review
```

The `pr-review-loop.sh` helper posts this phrase automatically when
`claude-code-action` is listed in `review.platforms`. If you customise the
trigger phrase in the workflow file, set the `CLAUDE_CODE_ACTION_TRIGGER_PHRASE`
environment variable or pass `--trigger-phrase` to
`claude-code-action-reviewer.sh` so the helper uses the same phrase.

### 4. Note the Bot Login for Thread Attribution

When Claude Code Action posts review threads on a PR, the comments appear under
the GitHub App bot login:

```
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
  platforms:
    - claude-code-action
```

To run Claude Code Action only after earlier platforms have already cleared (the
`phase_after_clean` measurement position), use:

```yaml
review:
  platforms:
    - pr-agent
    - claude-code-action
  phase_after_clean:
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

After each push, `pr-review-loop.sh` posts the trigger comment and captures its
ID:

```bash
trigger_body="@claude review"
trigger_response=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
  --method POST --raw-field body="$trigger_body")
trigger_comment_id=$(printf '%s\n' "$trigger_response" | jq -r '.id')
```

The companion script `claude-code-action-reviewer.sh` handles this step
automatically. You do not need to post the trigger manually when using the
helper.

### Step 7.2 — Detect review completion

Claude Code Action completes its review by finishing the GitHub Actions run it
dispatches. The companion script polls the Actions API for the run triggered
after the review comment was posted:

```bash
run_status=$(gh api "repos/$OWNER/$REPO/actions/runs" \
  --jq ".workflow_runs | map(select(.event == \"workflow_dispatch\")) | .[0].status")
```

| Result                                           | Action                                                                |
| ------------------------------------------------ | --------------------------------------------------------------------- |
| Actions run completed with `conclusion: success` | Review complete — proceed to Step 7.3                                 |
| Actions run in progress and `elapsed < max_wait` | Not finished yet — wait another `poll_interval` and poll again        |
| `elapsed >= max_wait`                            | Timeout — escalate to human                                           |
| Workflow file absent or dispatch rejected        | Unavailable — apply `internal_reviewers_unavailable_policy` behaviour |

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
  | jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select(.comments.nodes[0].author.login == "claude")' | wc -l
```

> **Note**: The GraphQL `author.login` field returns `claude` (without `[bot]`)
> while the REST API returns `claude[bot]`. The script strips the `[bot]` suffix
> automatically.

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
  internal_reviewers:
    - claude
    - claude-code-action
```

> **Note**: `claude-code-action` as an internal reviewer requires the
> `ANTHROPIC_API_KEY` secret and the workflow file to be present. The runner
> classifies it as `unreachable` if the workflow file is absent or the dispatch
> is rejected. The configured `internal_reviewers_unavailable_policy` then
> determines whether to hard-fail or warn and proceed with the remaining
> reachable reviewers.

### Exit code semantics

`claude-code-action-reviewer.sh` emits the following exit codes, which the
Step 7a gate maps to outcomes:

| Exit code | Meaning        | Gate outcome                                              |
| --------- | -------------- | --------------------------------------------------------- |
| `0`       | APPROVED       | Reviewer approved — continue to the next reviewer         |
| `1`       | NEEDS_REVISION | Blocking threads found — fix and re-run the review cycle  |
| `2`       | TIMED_OUT      | Workflow did not complete within `max_wait`               |
| `3`       | UNAVAILABLE    | Workflow file absent or dispatch rejected                 |

---

## Troubleshooting

| Symptom                                                        | Cause                                                          | Resolution                                                                                                                      |
| -------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `RESULT=escalate REASON=unavailable`                           | Workflow file absent or `ANTHROPIC_API_KEY` not set            | Confirm `.github/workflows/claude-code-review.yml` exists and the secret is added in repository settings                       |
| `RESULT=escalate REASON=timeout`                               | Actions run did not complete within `max_wait` (default 600 s) | Check the Actions tab for the run status; increase `--max-wait` if the review consistently takes longer than 10 minutes         |
| Review threads not detected after Actions run succeeds         | Bot login mismatch                                             | Confirm the bot posting threads is `claude[bot]`; if using a custom App, set `CLAUDE_CODE_ACTION_BOT_LOGIN` to the correct login |
| `pr-review-loop.sh` reports `skipped` for `claude-code-action` | Platform not listed in `review.platforms`                      | Add `claude-code-action` to `review.platforms` in `.ai-dev-workflow.yaml`                                                       |
| Trigger comment posted but no Actions run appears              | Workflow trigger phrase mismatch or workflow event not matching | Confirm the workflow listens to `issue_comment` events with the correct trigger phrase (`@claude review`)                       |

---

## See Also

- [`pr-review-platform.md`](pr-review-platform.md) — Step 7 multi-platform review loop
- [`coderabbit.md`](coderabbit.md) — CodeRabbit integration (common default reviewer)
- Protocol 93 — [`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md)
- Protocol 03 — [`../protocols/03-implement-development-protocol.md`](../protocols/03-implement-development-protocol.md)
- `scripts/development-workflow/claude-code-action-reviewer.sh` — companion script
