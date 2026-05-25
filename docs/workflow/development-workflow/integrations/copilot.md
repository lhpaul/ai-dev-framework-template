# Integration: GitHub Copilot Code Review (Automated PR Review)

This document describes how to use
[GitHub Copilot code review](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review)
as one automated PR reviewer tool in the workflow.

GitHub Copilot code review is **optional**. The workflow functions without it.
See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the
multi-platform loop and aggregation rules.

---

## What Copilot Code Review Adds

- Lightweight secondary automated review on every PR at no extra cost when a
  GitHub Copilot seat or the Copilot for Pull Requests feature is already active
  on the repository
- Catches logic errors, potential bugs, and style issues before human review,
  using Copilot's understanding of the repository codebase
- Complements other review platforms (PR-Agent, CodeRabbit) — can be layered as
  an additional signal or used as a standalone backstop when other platforms are
  unavailable

---

## Prerequisites

- **Active GitHub Copilot seat**: the repository must have GitHub Copilot
  available at the organization or individual account level, with Copilot code
  review enabled. See the
  [GitHub Copilot code review documentation](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review)
  for enablement details.
- **GitHub.com only**: GitHub Copilot code review is not supported on GitHub
  Enterprise Server (GHES) at this time.
- **No additional secrets or CI workflows required**: unlike Claude Code Action,
  Copilot code review uses GitHub's own infrastructure — no
  `ANTHROPIC_API_KEY`-style secret is needed and no Actions workflow file must
  be added to the repository.

---

## Setup

### 1. Verify Copilot Code Review is Enabled

Confirm that Copilot code review is available on the repository by navigating to
**Settings → Copilot** in the GitHub UI. The feature must be enabled before
`pr-review-loop.sh` can request Copilot as a reviewer.

### 2. Add `copilot` to `.ai-dev-workflow.yaml`

Declare `copilot` as a review platform so `pr-review-loop.sh` runs it
automatically:

```yaml
review:
  platforms:
    - copilot
```

To run Copilot only after earlier platforms have already cleared (the
`phase_after_clean` measurement position), use:

```yaml
review:
  platforms:
    - pr-agent
    - copilot
  phase_after_clean:
    - copilot
```

This configuration makes Copilot's net-new findings measurable independently of
whether `pr-agent` already found issues.

### 3. (Optional) Override the Default Bot Login

Copilot posts reviews as `copilot-pull-request-reviewer[bot]` on GitHub.com.
If your GitHub plan or a future GitHub change uses a different bot login, you can
override the default:

```bash
export COPILOT_BOT_LOGIN="your-copilot-bot-login[bot]"
```

Set this variable in your shell or in the CI environment where
`pr-review-loop.sh` runs.

---

## Step 7 — Copilot Integration

### Preferred helper

When possible, call the repository helper instead of re-implementing the loop
inline:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform copilot
```

It encapsulates the reviewer request, polling, result mapping, and stable
aggregate `RESULT=` output used by the Work Item Runner (and by the Portfolio
Orchestrator when it supervises item-level runs).

### Bot identity

Copilot posts reviews as `copilot-pull-request-reviewer[bot]`. Use this login
to filter its reviews from human activity. Override with `COPILOT_BOT_LOGIN` if
your environment uses a different login.

### Step 7.1 — Request Copilot as a reviewer

`pr-review-loop.sh` requests Copilot as a reviewer via the GitHub REST API:

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/requested_reviewers" \
  --method POST \
  --field 'reviewers[]=copilot'
```

This request is idempotent — GitHub silently deduplicates reviewer requests if
Copilot is already listed as a requested reviewer. If the request fails (non-zero
exit code), Copilot code review is likely not enabled on the repository; the
function immediately returns `RESULT=escalate REASON=unavailable`.

### Step 7.2 — Detect review completion

`pr-review-loop.sh` polls the pull-request reviews REST endpoint until Copilot
posts a review:

```bash
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --jq "[.[] | select(.user.login == \"copilot-pull-request-reviewer[bot]\")] | last | .state // empty"
```

| Review state         | `RESULT` output | Notes                                          |
| -------------------- | --------------- | ---------------------------------------------- |
| `APPROVED`           | `clean`         | No blocking findings                           |
| `COMMENTED`          | `clean`         | Non-blocking comment; treated as advisory only |
| `CHANGES_REQUESTED`  | `needs_fixes`   | Blocking findings; fix and re-run the loop     |
| No review (timeout)  | `escalate`      | `REASON=timeout` — apply unavailability policy |

### Step 7.3 — Polling parameters

The default poll interval and maximum wait follow the same values as other
platforms and are configurable via `pr-review-loop.sh` flags:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> \
  --platform copilot \
  --poll-interval 30 \
  --max-wait 300
```

---

## Known Limitations

- **GHES not supported**: GitHub Copilot code review is a GitHub.com feature only.
- **Review instructions not configurable**: unlike PR-Agent or CodeRabbit, Copilot
  code review does not support per-repository review instruction files via
  `.ai-dev-workflow.yaml`. Review behaviour is governed by GitHub Copilot
  settings at the organization or repository level.
- **Bot login may change**: the default bot login (`copilot-pull-request-reviewer[bot]`)
  is the currently observed login on GitHub.com. GitHub may change this in the future;
  use `COPILOT_BOT_LOGIN` to override if the login differs in your environment.
- **No companion script**: unlike `codex-github` and `claude-code-action`, Copilot
  does not require a separate reviewer companion script. The entire integration
  is contained within `run_copilot_review()` in `pr-review-loop.sh`.
