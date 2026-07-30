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

CodeRabbit supports three independent usage modes in this framework:

### CLI-only (Path A)

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

Use this mode by keeping `reviews.auto_review.enabled: false` in
`.coderabbit.yaml` and leaving `coderabbit` out of `review.on_draft.github` and
`review.on_ready.github`.

### CLI Step 7 reviewer (Path B)

Use the CodeRabbit CLI as a configured Step 7 platform without installing the
GitHub App. Add `coderabbit-cli` to `review.on_draft.github` or
`review.on_ready.github`:

```yaml
review:
  on_draft:
    github:
      - coderabbit-cli
  coderabbit_cli:
    rate_limit_policy: warn
```

The platform runs `cr --agent --base <pr-base>` when `cr` is installed. If `cr`
is absent and `coderabbit` is available, it runs
`coderabbit review --agent --base <pr-base>`. The PR base is read with
`gh pr view <number> --json baseRefName,headRefName`; if that lookup is
unavailable, the companion script falls back to `develop`.

The CLI path is intentionally not enabled by default. It requires local CLI
installation and authentication in the runner environment.

#### CLI Result Mapping

`scripts/development-workflow/coderabbit-cli-reviewer.sh` emits the same
companion-script contract as other CLI reviewers:

- `RESULT=clean` when agent JSON includes a recognized findings array and no
  blocking findings.
- `RESULT=needs_fixes` when one or more findings have blocking severity.
- `RESULT=skipped` with `REASON=unavailable`, `unauthorized`, `invalid_json`,
  `ambiguous_output`, `no_output`, `timeout`, or `rate_limited` when a fresh
  reliable review did not complete.
- `RESULT=escalate` with `REASON=rate_limited` when the rate-limit policy is
  strict.

The default rate-limit policy is `warn`, which records
`RESULT=skipped`, `REASON=rate_limited`, and `DISPLAY_RESULT=rate_limited`.
Set `CODERABBIT_CLI_RATE_LIMIT_POLICY=strict` or configure
`review.coderabbit_cli.rate_limit_policy: strict` to stop readiness on rate
limit instead.

`coderabbit-cli` does not post GitHub review threads in this MVP, so
`bot_login_for_platform coderabbit-cli` returns empty. The script-owned
Automated Reviewer Loop Summary is the durable evidence. A skipped CLI result
must be reported as unavailable or rate-limited evidence, not as "CodeRabbit CLI
found no issues."

### GitHub App PR reviewer (Path C)

To enable CodeRabbit as a Step 7 automated PR reviewer platform:

1. Set `reviews.auto_review.enabled: true` in `.coderabbit.yaml`
2. Add `coderabbit` to `review.on_draft.github` or `review.on_ready.github` in `.ai-dev-workflow.yaml`
3. Install the CodeRabbit GitHub App on the repository

The `coderabbit` App platform remains separate from `coderabbit-cli`. It uses
the `coderabbitai[bot]` review/comment evidence path described below.

This template repository uses this mode for ready-phase PR review: CodeRabbit
auto-review is enabled for non-draft PRs targeting `develop`, and
`.ai-dev-workflow.yaml` lists `coderabbit` under `review.on_ready.github`.

---

## Step 7a — Internal Reviewer (Draft PRs)

CodeRabbit can act as a Step 7a internal reviewer, running on a draft PR before it is converted to non-draft. This uses the same GitHub App auto-review mechanism as Step 7, but is triggered on a draft PR during the internal review gate.

### Configuration

Add `coderabbit` to `review.on_draft.runner` in `.ai-dev-workflow.yaml`:

```yaml
review:
  on_draft:
    runner:
      - claude
      - coderabbit
```

All reviewers in the list must APPROVE before `gh pr ready` is called. Reviewers run sequentially in the listed order.

### Draft-PR Requirement

`reviews.auto_review.enabled: true` must be set in `.coderabbit.yaml` for CodeRabbit to auto-review draft PRs. If the CodeRabbit App configuration filters out draft PRs, the runner classifies `coderabbit` as unreachable in Step 7a (BR-5).

Ensure your `.coderabbit.yaml` is configured to allow draft PR reviews:

```yaml
reviews:
  auto_review:
    enabled: true
```

### Invocation

CodeRabbit auto-reviews on every push when `auto_review.enabled` is `true`. No trigger comment is needed. The runner waits for a `coderabbitai[bot]` review posted after the HEAD commit timestamp. This is identical to the Step 7 mechanism but applied to a draft PR.

### Severity Classification

Findings are classified using the same severity matrix as [Step 7](#blocking-vs-suggestion-classification). For Step 7a, only `Critical` and `Major` findings are blocking — the runner applies fixes and re-runs the internal review cycle. `Minor`, `Low`, and unmarked findings are non-blocking suggestions that the runner may optionally address but that do not prevent Step 7a from approving.

### Fix-Cycle Limit

CodeRabbit as an internal reviewer is subject to the same `max_internal_review_cycles` limit as other internal reviewers (default: 5). When the cycle count reaches the limit with unresolved blocking findings, Step 7a escalates to human rather than continuing to loop.

### Availability Check

Before dispatching, the runner performs a runtime availability check to classify `coderabbit` as `reachable` or `unreachable`:

1. **App installation signal**: Check whether `coderabbitai[bot]` has any prior activity on the repository via `gh api repos/{owner}/{repo}/installation` or by inspecting recent PR comments for `coderabbitai[bot]` posts.
2. **Draft-PR configuration check**: Verify that `.coderabbit.yaml` sets `reviews.auto_review.enabled: true` and does not otherwise restrict reviews to non-draft PRs.

If either check fails, `coderabbit` is classified as `unreachable`. The configured `internal_reviewers_unavailable_policy` then determines whether to proceed with the remaining reachable reviewers (`warn`, the default) or hard-fail the Step 7a gate (`fail-if-any-unavailable`).

### Troubleshooting

| Symptom                                                                 | Cause                                                                    | Resolution                                                                                                                                                                               |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `coderabbit` classified as `unreachable` — warning comment posted       | CodeRabbit GitHub App is not installed on the repository                 | Install the CodeRabbit GitHub App at [coderabbit.ai](https://www.coderabbit.ai) and verify it has access to the repository                                                               |
| `coderabbit` classified as `unreachable` — `auto_review.enabled: false` | `.coderabbit.yaml` has auto-review disabled                              | Set `reviews.auto_review.enabled: true` in `.coderabbit.yaml`                                                                                                                            |
| `coderabbit` classified as `unreachable` — draft PRs not enabled        | CodeRabbit App configuration or `.coderabbit.yaml` filters out draft PRs | Confirm the CodeRabbit App settings permit draft PR reviews and that `.coderabbit.yaml` does not restrict to non-draft only                                                              |
| All Step 7a reviewers unreachable — hard-fail                           | No reachable runner reviewers available                                  | Run Step 7a from a context where at least one reviewer is reachable, or temporarily override `review.on_draft.runner` via `.ai-dev-workflow.local.yaml` to remove unreachable reviewers |
| CodeRabbit does not post a review after push                            | App installed but auto-review trigger not firing                         | Push a new commit to the draft PR, confirm the App is active, and check the CodeRabbit dashboard for any rate limiting or quota issues                                                   |

---

## Setup (Path C only)

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
  on_draft:
    github:
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

CodeRabbit signals completion by posting a review (typically `COMMENTED` or `CHANGES_REQUESTED`) on the PR after analyzing the pushed commit.

The helper script checks for a CodeRabbit review on each poll iteration. If a review from `coderabbitai[bot]` is found submitted after the HEAD commit timestamp, the review is considered complete and the script proceeds to Phase 3.

As a secondary signal, the script also checks for CodeRabbit issue comments (e.g., the PR summary comment) as an **activity indicator** — this is used only to distinguish "CodeRabbit is active but hasn't finished" from "CodeRabbit didn't review this HEAD at all" when the timeout is reached.

| Result                                                     | Action                                                          |
| ---------------------------------------------------------- | --------------------------------------------------------------- |
| CodeRabbit review found after HEAD commit                  | Review complete — proceed to Step 7.3                           |
| No review yet and `elapsed < max_wait`                     | Not finished yet — wait another `poll_interval` and poll again  |
| `elapsed >= max_wait` and no CodeRabbit activity detected  | Stale findings recovery, then skip as `no_review` if none found |
| `elapsed >= max_wait` and CodeRabbit activity was detected | Timeout — escalate to human                                     |

### Step 7.3 — Fetch inline comments and reviews

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq "[.[] | select(.user.login == \"coderabbitai[bot]\" and .created_at > \"$since_iso\" and .in_reply_to_id == null) | {path, line, body}]"
```

Additionally, `CHANGES_REQUESTED` reviews posted by `coderabbitai[bot]` after the HEAD commit are also fetched from the reviews endpoint and counted as blocking, regardless of the emoji severity marker in their body. This matches the behavior of the other platform adapters.

### Blocking vs. suggestion classification

Unlike Devin (where all findings are blocking), CodeRabbit inline comments include severity markers that determine blocking status:

| Severity marker       | Classification            |
| --------------------- | ------------------------- |
| `🔴 Critical`         | Blocking                  |
| `🟠 Major`            | Blocking                  |
| `🟡 Minor`            | Suggestion (non-blocking) |
| `🟢 Low` or no marker | Suggestion (non-blocking) |

The adapter parses the comment body for these emoji+label patterns. Comments without a recognized severity marker default to suggestion.

### Reply thread handling

CodeRabbit posts findings as inline comments on code lines. The adapter filters out reply comments (`in_reply_to_id != null`) to avoid double-counting a finding and its reply as separate items. Only top-level inline comments are counted.

### Resolved comment handling

When CodeRabbit detects fixes in subsequent commits, it may post a reply starting with `✅` on the original finding.

**Stale-findings recovery** (where the entire PR history is scanned without a timestamp bound) is the only path that performs explicit `✅`-reply filtering: it collects the IDs of all bot replies starting with `✅` and excludes their parent comments from the stale blocking count — the same `jq -s` pattern as the Devin adapter.

**Phase 1 and Phase 3 do not perform explicit resolved-comment filtering.** They rely on the `since_iso` timestamp bound instead: only comments posted after the HEAD commit are fetched. Because CodeRabbit posts findings and `✅` resolution replies in separate review cycles (triggered by different pushes), a resolved finding's original comment will have a `created_at` before `since_iso` and will not appear in Phase 1 or Phase 3 queries. Reply comments (`in_reply_to_id != null`) are always excluded from direct counting regardless of phase.
