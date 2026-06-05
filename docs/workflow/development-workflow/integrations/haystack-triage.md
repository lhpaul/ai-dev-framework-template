# Integration: Haystack Triage CLI — Native PR Review Platform

This document describes how to configure `haystack triage` as a native automated review platform in `pr-review-loop.sh` (Step 7 of the development workflow).

For information about Haystack's local git hooks (truncation checker, LLM_RULES.md gate), see [`haystack.md`](haystack.md).

---

## Overview

`haystack-reviewer.sh` wraps the `haystack triage <PR> --json` CLI call and emits the standard key-value output contract consumed by `pr-review-loop.sh`. Teams that declare `haystack` in `review.platforms` gain a review platform that produces actionable, file-anchored findings with fix prompts — without requiring any additional GitHub App installation.

Key properties:

- **Poll-retry on pending**: When `haystack triage` returns `status=pending` (analysis still in progress), `haystack-reviewer.sh` waits `HAYSTACK_POLL_INTERVAL` seconds (default: 15) and retries automatically until the analysis completes or the overall `HAYSTACK_REVIEWER_TIMEOUT` budget is exhausted. This eliminates the timing-gap false-negative where the reviewer loop ran within the first 2–4 minutes of a PR push and silently skipped findings.
- **Policy-verdict visibility**: After triage completes, `haystack-reviewer.sh` also reads `haystack pr-status <PR> --json`. When Haystack reports `needsHumanReview: true` or `analysisVerdict: "needs-review"`, the reviewer loop keeps the result non-blocking if there are no blocking findings but displays `haystack (needs-review: policy)` in the PR summary instead of `haystack (clean)`.
- **No per-hour rate cap**: Unlike some hosted review services, Haystack triage is not subject to hourly review limits (as of the time of writing).
- **Graceful degradation**: If the `haystack` CLI is absent or unauthenticated, the reviewer exits with `UNAVAILABLE` and the review loop continues with the remaining configured platforms.
- **No GitHub App required**: This integration uses the CLI only. Haystack does not post inline GitHub review threads in this MVP — findings are reported locally via the key-value output.

---

## CLI Installation

Install the Haystack CLI using the official setup wizard:

```bash
haystack setup
```

This installs the CLI, authenticates with your GitHub account, and configures the Haystack service. Refer to [https://haystackeditor.com/](https://haystackeditor.com/) for the current installation instructions.

After setup, verify that the CLI is reachable:

```bash
haystack --version
haystack whoami
```

---

## Configuration

Add `haystack` to `review.platforms` (or `review.phase_after_clean`) in `.ai-dev-workflow.yaml`:

```yaml
review:
  # Run haystack alongside or after other review platforms.
  platforms:
    - pr-agent
    - haystack

  # Or run haystack only after earlier platforms are clean:
  # phase_after_clean:
  #   - haystack
```

No other configuration changes are required in `.ai-dev-workflow.yaml`.

If the repository creates implementation PRs as drafts, prefer
`review.phase_after_clean` for Haystack. In this mode the reviewer loop lets
draft-compatible platforms clear first, marks the PR ready, and then runs
Haystack. Haystack triage may remain `pending` indefinitely while a PR is still
draft, so running it before `gh pr ready` can produce avoidable
`pending_timeout` escalations.

---

## Bot Login Identifier

Haystack triage does not post inline GitHub review threads in this MVP. The Haystack CLI reads triage results locally and does not push findings to the GitHub PR review thread API.

Because no GitHub review threads are posted, the `check_unresolved_threads` gate is not invoked for Haystack. `bot_login_for_platform("haystack")` returns an empty string `""`, which signals to `pr-review-loop.sh` that no thread audit is needed.

If a future integration adds a Haystack GitHub App with inline thread posting, this can be updated to the actual bot login (e.g., `haystack-ai[bot]`).

---

## Severity Mapping

The `haystack triage --json` output schema uses a `.findings[].category` field as the severity discriminator (confirmed against the Haystack CLI as of 2026-05-25). `haystack-reviewer.sh` parses this field from every element of the `.findings[]` array to classify each finding as blocking or advisory; for example, a finding object `{"category": "Logic error", "message": "..."}` maps to a blocking result and increments `BLOCKING_COUNT`.

| Haystack category | Classification | Notes |
| ----------------- | -------------- | ----- |
| `Logic error` | Blocking | Maps to exit code 1 (NEEDS_REVISION) |
| `Critical` | Blocking | Maps to exit code 1 (NEEDS_REVISION) |
| `Major` | Advisory (default) | Advisory by default; set `HAYSTACK_MAJOR_IS_BLOCKING=1` to treat as blocking |
| `Minor` | Advisory | Non-blocking; reported in SUGGESTION_COUNT |
| `Advisory` | Advisory | Non-blocking; reported in SUGGESTION_COUNT |
| `Nitpick` | Advisory | Non-blocking; reported in SUGGESTION_COUNT |
| `Trivial` | Advisory | Non-blocking; reported in SUGGESTION_COUNT |
| `Weak test coverage` | Advisory | Non-blocking; reported in SUGGESTION_COUNT |
| `Rules violation` | Advisory | Non-blocking; used for custom rule findings (e.g. CHANGELOG structure) that can produce false positives on correctly-formatted PRs and hotfix backport PRs — see the ["Rules violation" section](#rules-violation--changelog-false-positive-on-correctly-formatted-prs) below |
| Any unrecognised value | Blocking | Conservative safe-fail per spec BR-2 |

The `COMMENT_COUNT` output equals `BLOCKING_COUNT + SUGGESTION_COUNT`.

## Review Policy Verdicts

Haystack exposes two related but separate result channels:

| CLI command | Data surfaced | Reviewer-loop treatment |
| ----------- | ------------- | ----------------------- |
| `haystack triage <PR> --json` | Code-review findings in `.findings[]` and rating | Blocking categories stop the loop; advisory categories increment `SUGGESTION_COUNT` |
| `haystack pr-status <PR> --json` | Pipeline/review-policy verdicts such as `analysisVerdict`, `needsHumanReview`, `bucket`, `hasReviewer`, and `haystackRating` | Non-blocking visibility signal when no blocking triage findings exist |

When `pr-status` reports `needsHumanReview: true` or
`analysisVerdict: "needs-review"`, `haystack-reviewer.sh` emits:

```text
POLICY_STATUS_AVAILABLE=1
POLICY_REVIEW_REQUIRED=1
POLICY_VERDICT=needs-review
DISPLAY_RESULT=needs-review: policy
```

`pr-review-loop.sh` uses `DISPLAY_RESULT` in its summary comment, so a clean
triage result with a policy verdict appears as:

```text
haystack (needs-review: policy)
```

This is intentionally advisory: the workflow already routes ready PRs to human
review, so the policy verdict should be visible without blocking deterministic
progress when `.findings[]` has no blocking issue. If Haystack also reports a
blocking triage category, the normal `needs_fixes` path still wins.

### Overriding "Major" to blocking

By default, `Major` findings are treated as advisory (non-blocking). If your team wants `Major` findings to block PRs, set the environment variable before running `pr-review-loop.sh`:

```bash
HAYSTACK_MAJOR_IS_BLOCKING=1 ./scripts/development-workflow/pr-review-loop.sh <pr_number>
```

### "Rules violation" — CHANGELOG false positive on correctly-formatted PRs

Haystack uses the `Rules violation` category for custom rule findings, including CHANGELOG structure checks (rule `keep-changelog-unreleased-structure-canonical`). This rule fires as a false positive on PRs whose CHANGELOG entry is **correctly** formatted. This is a known recurring pattern (observed in Batches 34, 35, 55, and PR #801).

> **IMPORTANT — for agents**: When you see a `Rules violation` finding that references CHANGELOG structure (`keep-changelog-unreleased-structure-canonical` or similar), **do not attempt to fix it**. The current CHANGELOG format is correct. Attempting to restructure the CHANGELOG in response to this finding will introduce a real regression. Treat it as non-actionable and dismiss it.

**Why the finding fires**: Haystack's LLM-based CHANGELOG structure checker (`keep-changelog-unreleased-structure-canonical` rule in `.haystack/pr-rules.yml`) misidentifies correctly placed entries. The rule is intended to catch a single `[Unreleased]` section with ordered subsections, but Haystack's analysis of a diff (not the full file) can misread the context and report the entry as appended outside the section rather than nested within it. The actual CHANGELOG structure follows Keep a Changelog format correctly.

**Resolution**: `Rules violation` is classified as advisory (non-blocking) in `haystack-reviewer.sh`. The loop exits `RESULT=clean` with `SUGGESTION_COUNT=1`. No code change is required. Verify:

1. The CHANGELOG entry is under `## [Unreleased]` followed by `### Fixed` (or another appropriate subsection).
2. The `check-changelog-duplicate-headers.sh` CI check and `markdownlint-cli2` lint pass — these are the authoritative validators for CHANGELOG structure and are not subject to Haystack's diff-interpretation issue.

If both conditions hold, the finding is a confirmed false positive and can be dismissed.

#### Hotfix backport PRs

An additional false positive occurs specifically on hotfix backport PRs. Hotfix branches are cut from `main`. The diff of a backport branch against `develop` shows an empty `[Unreleased]` section (from `main`'s version of the CHANGELOG). Haystack interprets the diff as "removing `[Unreleased]` content" and flags it as a structure violation. In reality, the 3-way merge on the `develop` side preserves its own `[Unreleased]` content; the CHANGELOG structure in the merged result is correct.

For backport PRs, verify:

1. The `develop` branch also has an empty `[Unreleased]` section (or the same content that was on `main`).
2. The merged CHANGELOG on `develop` will have the correct Keep-a-Changelog structure: `[Unreleased]` at the top, followed by the new versioned section from the hotfix, followed by prior versioned sections.

If both conditions hold, the finding is a false positive and can be dismissed. Genuine CHANGELOG structure problems are caught by the `check-changelog-duplicate-headers.sh` CI check and `markdownlint-cli2` lint, which are not subject to the same diff-interpretation issue.

---

## Timeout and Poll Interval Configuration

`haystack-reviewer.sh` polls `haystack triage` until the analysis completes or the overall budget expires. Two environment variables control this behaviour:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `HAYSTACK_REVIEWER_TIMEOUT` | `120` | Total seconds the script may spend across all poll-retry calls. When this budget is exhausted while the analysis is still `pending`, the script exits with `REASON=pending_timeout`. |
| `HAYSTACK_POLL_INTERVAL` | `15` | Seconds to wait between successive `haystack triage --no-wait` calls when the response carries `status=pending`. |

Override both via environment variable:

```bash
HAYSTACK_REVIEWER_TIMEOUT=180 HAYSTACK_POLL_INTERVAL=20 \
  ./scripts/development-workflow/pr-review-loop.sh <pr_number>
```

If a single `haystack triage` call hangs (e.g., network issue), the script enforces a per-call timeout of `floor(remaining_budget / 2)` seconds (minimum 1 second) and retries as long as the overall budget allows. When the budget is finally exhausted due to a hung call, the script exits with `REASON=timeout` (exit code 2).

---

## Graceful Degradation

`haystack-reviewer.sh` degrades gracefully in three distinct scenarios:

**CLI not installed or authentication failed** (`REASON=unavailable`, exit 3):

```text
RESULT=skipped
REASON=unavailable
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
COMMENT_COUNT=0
```

**Analysis timed out waiting for pending result** (`REASON=pending_timeout`, exit 2):

```text
RESULT=skipped
REASON=pending_timeout
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
COMMENT_COUNT=0
```

**Single `haystack triage` call hung past the overall budget** (`REASON=timeout`, exit 2):

```text
RESULT=skipped
REASON=timeout
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
COMMENT_COUNT=0
```

In all three cases, `pr-review-loop.sh` treats the reviewer as unavailable and continues with the remaining platforms. Other platforms are not blocked.

When any of these Haystack reviewer-health failures occur, `pr-review-loop.sh` applies the `reviewer-failed` label to the PR so the failure is visible from the PR list or project board. The label is self-healing: a later loop run that reaches healthy reviewer output (`clean`, `needs_fixes`, `needs_rerun`, or only `skipped/not_configured`) removes `reviewer-failed`.

---

## Exit Code Contract

| Exit code | Meaning | RESULT emitted | REASON emitted |
| --------- | ------- | -------------- | -------------- |
| `0` | APPROVED — no blocking findings | `clean` | — |
| `1` | NEEDS_REVISION — one or more blocking findings | `needs_fixes` | — |
| `2` | TIMED_OUT — per-call OS timeout exhausted the overall budget | `skipped` (→ `escalate` via `pr-review-loop.sh`) | `timeout` |
| `2` | PENDING_TIMEOUT — analysis stayed `pending` until the overall budget expired | `skipped` (→ `escalate` via `pr-review-loop.sh`) | `pending_timeout` |
| `3` | UNAVAILABLE — CLI not installed, authentication failed, `status=none` | `skipped` | `unavailable` |

The `REASON` field distinguishes the three `skipped` sub-cases so callers can decide whether to retry later (`pending_timeout` — analysis was in progress), investigate connectivity (`timeout` — a call hung), or check authentication (`unavailable` — CLI absent or no analysis submitted).

---

## Troubleshooting

### `haystack` CLI not found

```text
INFO: haystack CLI not found in PATH — skipping (UNAVAILABLE)
RESULT=skipped
REASON=unavailable
```

**Remediation**: Run `haystack setup` to install and authenticate the CLI. Verify with `which haystack`.

### Triage returns `status=none`

```text
INFO: haystack triage returned status=none (no analysis available for this PR yet) — treating as UNAVAILABLE
```

**Cause**: Haystack has no record of this PR. This happens when the PR was not submitted via `haystack submit` and the Haystack GitHub App has not yet picked it up automatically.

**Remediation**: Run `haystack submit` on the branch to trigger analysis, then re-run the review loop.

### Triage returns `status=pending` (analysis in progress — automatic retry)

```text
INFO: status=pending — waiting 15s before retry (15s elapsed of 120s budget)
```

**Cause**: `haystack triage --no-wait` exits immediately when the Haystack cloud analysis is not yet complete. Haystack analysis typically takes 2–4 minutes after a PR is pushed.

**Behaviour since issue #795**: `haystack-reviewer.sh` now **automatically polls and retries** when it receives `status=pending`. It waits `HAYSTACK_POLL_INTERVAL` seconds (default: 15) between calls and continues retrying until the analysis completes or the `HAYSTACK_REVIEWER_TIMEOUT` budget (default: 120 seconds) is exhausted.

If the overall budget is exhausted while the analysis is still pending, the script emits:

```text
INFO: haystack triage status=pending — budget exhausted after 120s (pending_timeout)
RESULT=skipped
REASON=pending_timeout
```

**When you see `REASON=pending_timeout`**: The review loop will treat the reviewer as unavailable for this run, apply `reviewer-failed`, and continue with the remaining platforms. This is distinct from `REASON=unavailable` (CLI not installed or authentication failed) and `REASON=timeout` (a single call hung). A later clean Haystack run removes `reviewer-failed`.

**Recovery options**:

1. **Increase the timeout**: Set `HAYSTACK_REVIEWER_TIMEOUT=300` to give Haystack more time to complete analysis.
2. **Re-run the review loop manually** after a few minutes: `./scripts/development-workflow/pr-review-loop.sh <pr_number>`.
3. **Run haystack triage directly** if you need an immediate result:

   ```bash
   haystack triage <pr_number>
   ```

> **Protocol guard (when Haystack is listed in `review.platforms` and the loop returns `skipped/pending_timeout`)**: Before applying `ready-for-human-review`, agents must verify that `REASON=pending_timeout` is not masking real findings. Check whether the Haystack GitHub App has posted a "Haystack Code Reviewer: PR Analysis Ready!" comment on the PR:
>
> ```bash
> gh pr view <pr_number> --json comments \
>   --jq '[.comments[].body | select(test("Haystack Code Reviewer: PR Analysis Ready"))] | length'
> ```
>
> If the output is `≥ 1`, the analysis completed after the reviewer loop timed out. Run `haystack triage <pr_number>` manually and evaluate findings before labeling the PR `ready-for-human-review`.

### Triage times out

```text
INFO: haystack triage timed out after 120s
RESULT=escalate
REASON=timeout
```

**Remediation**: Increase `HAYSTACK_REVIEWER_TIMEOUT` or check network connectivity to the Haystack service.

### "Rules violation" finding for CHANGELOG structure (regular PR)

```text
INFO: findings parsed — blocking: 0, advisory: 1, total: 1
RESULT=clean
```

**Cause**: Haystack fired the `keep-changelog-unreleased-structure-canonical` rule on a PR whose CHANGELOG entry is correctly formatted under `[Unreleased]` → `### Fixed`. This is a known false positive (see the ["Rules violation" section](#rules-violation--changelog-false-positive-on-correctly-formatted-prs) above). The finding is advisory and does not block the reviewer loop.

**Remediation**: Verify that the CHANGELOG entry follows the correct Keep a Changelog format (`## [Unreleased]` → `### Fixed`) and that `markdownlint-cli2` and `check-changelog-duplicate-headers.sh` both pass. No code change is required; the finding can be dismissed. **Do not restructure the CHANGELOG to satisfy this finding.**

### "Rules violation" finding on a hotfix backport PR

```text
INFO: findings parsed — blocking: 0, advisory: 1, total: 1
RESULT=clean
```

**Cause**: Haystack flagged a `Rules violation` finding for CHANGELOG structure on the backport PR. This is a known false positive (see the "Hotfix backport PRs" subsection above). The finding is advisory and does not block the reviewer loop.

**Remediation**: Verify that the merged CHANGELOG on `develop` will have correct Keep-a-Changelog structure. No code change is required; the finding can be dismissed.

### Unrecognised finding category

```text
INFO: unrecognised finding category 'SomeNewCategory' — treating as blocking (safe-fail)
```

**Cause**: Haystack introduced a new severity category not yet mapped in `haystack-reviewer.sh`.

**Remediation**: Update the severity mapping table in `haystack-reviewer.sh` and this document. Open a follow-up issue if the new category should be treated as advisory.

---

## Related Files

| Path | Role |
| ---- | ---- |
| `scripts/development-workflow/haystack-reviewer.sh` | Companion script — wraps `haystack triage --json` and emits key-value contract |
| `scripts/development-workflow/pr-review-loop.sh` | Main review loop — dispatches `run_haystack_review()` for the `haystack` platform |
| `.ai-dev-workflow.yaml` | Declare `haystack` under `review.platforms` or `review.phase_after_clean` |
| `docs/workflow/development-workflow/integrations/haystack.md` | Haystack local git hooks integration (truncation checker, LLM_RULES.md) |

---

## See Also

- [`pr-review-platform.md`](pr-review-platform.md) — Step 7 multi-platform review loop (platform-agnostic)
- [`haystack.md`](haystack.md) — Haystack git hooks integration
- [`coderabbit.md`](coderabbit.md) — CodeRabbit integration (common default reviewer)
- Protocol 93 — [`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md)
