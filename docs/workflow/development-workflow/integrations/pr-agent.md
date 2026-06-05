# Integration: PR-Agent (Automated PR Review)

This document describes how to use [PR-Agent](https://github.com/qodo-ai/pr-agent) (open source, by Qodo) as an automated PR reviewer. Unlike cloud-based tools, PR-Agent runs as a **GitHub Actions workflow** and calls a third-party LLM API you supply — there is no per-seat fee.

PR-Agent is **optional**. The workflow functions without it. See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the multi-platform loop and aggregation rules.

---

## What PR-Agent Adds

- Automated code review on every push — no trigger comment needed (triggered by the `pull_request` GHA event)
- AI-powered analysis powered by any LLM you choose (DeepSeek, Kimi, OpenAI, Claude, Gemini, etc.)
- No per-seat pricing — cost is purely LLM token usage (~$5–30/month at typical batch volumes)
- Interactive: developers can post `/review`, `/improve`, `/describe` in PR comments to trigger on demand

---

## Setup

### 1. Add the GitHub Actions Workflow

The workflow file is already committed at `.github/workflows/pr-agent.yml`. It triggers automatically on PR open/reopen/ready-for-review events and on PR comment commands.

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

Open or push to any PR and confirm that `github-actions[bot]` posts an issue comment with a **PR Reviewer Guide** section. The comment body will contain one of two stable markers:

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

**No trigger needed for automated runs.** PR-Agent fires automatically on every push via the `pull_request` GHA event. There is no trigger comment and no `REVIEW_COMMENT_ID`.

For **manual re-triggers**, post a comment on the PR:

```
/review
```

This is handled by the `issue_comment` trigger in the workflow.

### Step 7.2 — Detect review completion

PR-Agent signals completion by posting a plain issue comment (not a formal GitHub PR review). The helper polls the issue comments API for a comment from `github-actions[bot]` with:

- Body containing `PR Reviewer Guide` (PR-Agent's stable output marker)
- `updated_at` timestamp after the HEAD commit's push time (so stale comments from a prior HEAD are ignored)

| Result                                                                   | Action                                                                          |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Comment with `No major issues detected`                                  | Review complete — clean                                                         |
| Comment with `Recommended focus areas for review` + hard-blocker label   | Review complete — blocking                                                      |
| Comment with `Recommended focus areas for review` + advisory labels only | Review complete — clean (advisory only)                                         |
| Comment with neither marker                                              | Ambiguous — escalate for human review                                           |
| No matching comment and `elapsed < max_wait`                             | GHA still running — wait `poll_interval` and poll again                         |
| `elapsed >= max_wait` and no comment posted                              | Treat as `skipped` (GHA may not have run, e.g., fork PR with no secrets access) |

Unlike Devin, there are no check runs to monitor — the comment itself is the completion signal.

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

When a PR is opened from a fork, GitHub Actions **does not expose repository secrets** to the workflow. This means `DEEPSEEK_API_KEY` (or the alternative key) is unavailable and the workflow will fail silently — no review is posted. The helper will time out and report `RESULT=skipped` with `REASON=no_review`. This is expected behavior and is not a configuration error.

If fork PRs need automated review, consider using a GitHub App token instead of `GITHUB_TOKEN`.

---

## Enabling Interactive Commands

With the `issue_comment` trigger active, any PR contributor can post PR-Agent commands:

| Command           | Effect                                 |
| ----------------- | -------------------------------------- |
| `/review`         | Re-run the full code review            |
| `/describe`       | Update the PR description              |
| `/improve`        | Post inline code suggestions           |
| `/ask <question>` | Ask PR-Agent a question about the code |

These commands fire only when `github.event.sender.type != 'Bot'` (the guard in the workflow), so automated agents posting comments will not accidentally trigger PR-Agent in a loop.
