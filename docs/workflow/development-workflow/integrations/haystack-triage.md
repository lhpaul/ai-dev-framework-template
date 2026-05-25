# Integration: Haystack Triage CLI — Native PR Review Platform

This document describes how to configure `haystack triage` as a native automated review platform in `pr-review-loop.sh` (Step 7 of the development workflow).

For information about Haystack's local git hooks (truncation checker, LLM_RULES.md gate), see [`haystack.md`](haystack.md).

---

## Overview

`haystack-reviewer.sh` wraps the `haystack triage <PR> --json` CLI call and emits the standard key-value output contract consumed by `pr-review-loop.sh`. Teams that declare `haystack` in `review.platforms` gain a review platform that produces actionable, file-anchored findings with fix prompts — without requiring any additional GitHub App installation.

Key properties:

- **Synchronous**: `haystack triage` runs and returns; no polling loop required.
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

The `haystack triage --json` output schema uses a `.findings[].category` field as the severity discriminator (confirmed against the Haystack CLI as of 2026-05-25).

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
| Any unrecognised value | Blocking | Conservative safe-fail per spec BR-2 |

The `COMMENT_COUNT` output equals `BLOCKING_COUNT + SUGGESTION_COUNT`.

### Overriding "Major" to blocking

By default, `Major` findings are treated as advisory (non-blocking). If your team wants `Major` findings to block PRs, set the environment variable before running `pr-review-loop.sh`:

```bash
HAYSTACK_MAJOR_IS_BLOCKING=1 ./scripts/development-workflow/pr-review-loop.sh <pr_number>
```

---

## Timeout Configuration

The default timeout for `haystack triage` is 120 seconds. Override it with the `HAYSTACK_REVIEWER_TIMEOUT` environment variable:

```bash
HAYSTACK_REVIEWER_TIMEOUT=60 ./scripts/development-workflow/pr-review-loop.sh <pr_number>
```

If `haystack triage` does not return within the timeout, `haystack-reviewer.sh` exits with code `2` (TIMED_OUT) and `pr-review-loop.sh` reports `RESULT=escalate / REASON=timeout`.

---

## Graceful Degradation

When the `haystack` CLI is absent from `$PATH` or returns a non-zero exit code (authentication failure, network error, etc.), `haystack-reviewer.sh` exits `3` (UNAVAILABLE) and emits:

```
RESULT=skipped
REASON=unavailable
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
COMMENT_COUNT=0
```

`pr-review-loop.sh` then applies the configured `internal_reviewers_unavailable_policy` (default: `warn`) — it logs a warning and continues with the remaining platforms. Other platforms are not blocked.

---

## Exit Code Contract

| Exit code | Meaning | RESULT emitted |
| --------- | ------- | -------------- |
| `0` | APPROVED — no blocking findings | `clean` |
| `1` | NEEDS_REVISION — one or more blocking findings | `needs_fixes` |
| `2` | TIMED_OUT — `haystack triage` did not return within timeout | `escalate` (via `pr-review-loop.sh`) |
| `3` | UNAVAILABLE — CLI not installed or authentication failed | `skipped` |

---

## Troubleshooting

### `haystack` CLI not found

```
INFO: haystack CLI not found in PATH — skipping (UNAVAILABLE)
RESULT=skipped
REASON=unavailable
```

**Remediation**: Run `haystack setup` to install and authenticate the CLI. Verify with `which haystack`.

### Triage returns `status=none`

```
INFO: haystack triage returned status=none (no analysis available for this PR yet) — treating as UNAVAILABLE
```

**Cause**: Haystack has not yet analysed this PR (e.g., the PR was just opened and analysis is still pending, or the PR was not submitted via `haystack submit`). The `--no-wait` flag used by `haystack-reviewer.sh` exits immediately if analysis is pending.

**Remediation**: Run `haystack triage <PR>` without `--no-wait` to wait for analysis to complete, then re-run the review loop. Alternatively, use `haystack submit` when opening PRs to ensure analysis starts immediately.

### Triage times out

```
INFO: haystack triage timed out after 120s
RESULT=escalate
REASON=timeout
```

**Remediation**: Increase `HAYSTACK_REVIEWER_TIMEOUT` or check network connectivity to the Haystack service.

### Unrecognised finding category

```
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
