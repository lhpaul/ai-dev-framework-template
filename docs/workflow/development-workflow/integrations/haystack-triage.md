# Integration: Haystack Triage CLI — Native PR Review Platform

This document describes how to configure `haystack triage` as a native automated review platform in `pr-review-loop.sh` (Step 7 of the development workflow).

For information about Haystack's local git hooks (truncation checker, LLM_RULES.md gate), see [`haystack.md`](haystack.md).

---

## Overview

`haystack-reviewer.sh` wraps the `haystack triage <PR> --json` CLI call and emits the standard key-value output contract consumed by `pr-review-loop.sh`. Teams that declare `haystack` in `review.platforms` gain a review platform that produces actionable, file-anchored findings with fix prompts — without requiring any additional GitHub App installation.

Key properties:

- **Poll-retry on pending**: When `haystack triage` returns `status=pending` (analysis still in progress), `haystack-reviewer.sh` waits `HAYSTACK_POLL_INTERVAL` seconds (default: 15) and retries automatically until the analysis completes or the overall `HAYSTACK_REVIEWER_TIMEOUT` budget is exhausted. This eliminates the timing-gap false-negative where the reviewer loop ran within the first 2–4 minutes of a PR push and silently skipped findings.
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
| `Rules violation` | Advisory | Non-blocking; used for custom rule findings (e.g. CHANGELOG structure) that can produce false positives on hotfix backport PRs — see the ["Rules violation" section](#rules-violation--changelog-false-positive-on-hotfix-backport-prs) below |
| Any unrecognised value | Blocking | Conservative safe-fail per spec BR-2 |

The `COMMENT_COUNT` output equals `BLOCKING_COUNT + SUGGESTION_COUNT`.

### Overriding "Major" to blocking

By default, `Major` findings are treated as advisory (non-blocking). If your team wants `Major` findings to block PRs, set the environment variable before running `pr-review-loop.sh`:

```bash
HAYSTACK_MAJOR_IS_BLOCKING=1 ./scripts/development-workflow/pr-review-loop.sh <pr_number>
```

### "Rules violation" — CHANGELOG false positive on hotfix backport PRs

Haystack uses the `Rules violation` category for custom rule findings, including CHANGELOG structure checks. On hotfix backport PRs, this can produce a false positive:

**Root cause**: Hotfix branches are cut from `main`. The diff of a backport branch against `develop` shows an empty `[Unreleased]` section (from `main`'s version of the CHANGELOG). Haystack interprets the diff as "removing `[Unreleased]` content" and flags it as a structure violation. In reality, the 3-way merge on the `develop` side preserves its own `[Unreleased]` content; the CHANGELOG structure in the merged result is correct.

**Resolution**: `Rules violation` is classified as advisory (non-blocking) in `haystack-reviewer.sh`. If you see this finding on a backport PR, verify:

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

**When you see `REASON=pending_timeout`**: The review loop will treat the reviewer as unavailable for this run and continue with the remaining platforms. This is distinct from `REASON=unavailable` (CLI not installed or authentication failed) and `REASON=timeout` (a single call hung).

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

### "Rules violation" finding on a hotfix backport PR

```text
INFO: findings parsed — blocking: 0, advisory: 1, total: 1
RESULT=clean
```

**Cause**: Haystack flagged a `Rules violation` finding for CHANGELOG structure on the backport PR. This is a known false positive (see the "Rules violation" section above). The finding is advisory and does not block the reviewer loop.

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
