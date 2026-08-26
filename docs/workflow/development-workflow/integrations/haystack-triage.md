# Integration: Haystack Triage CLI — Native PR Review Platform

This document describes how to configure `haystack triage` as a native automated review platform in `pr-review-loop.sh` (Step 7 of the development workflow).

For information about Haystack's local git hooks (truncation checker, LLM_RULES.md gate), see [`haystack.md`](haystack.md).

---

## Overview

`haystack-reviewer.sh` wraps the `haystack triage <PR> --json` CLI call and emits the standard key-value output contract consumed by `pr-review-loop.sh`. Teams that declare `haystack` in `review.on_ready.github` gain a review platform that produces actionable, file-anchored findings with fix prompts. When the Haystack GitHub App is installed, the same reviewer state may also appear as a `Haystack / Review` check run on the PR.

Key properties:

- **Poll-retry on pending**: When `haystack triage` returns `status=pending` (analysis still in progress), `haystack-reviewer.sh` waits `HAYSTACK_POLL_INTERVAL` seconds (default: 15) and retries automatically until the analysis completes or the overall `HAYSTACK_REVIEWER_TIMEOUT` budget is exhausted. This eliminates the timing-gap false-negative where the reviewer loop ran within the first 2–4 minutes of a PR push and silently skipped findings.
- **GitHub App check-run fallback**: When CLI triage is unavailable, times out, or stays pending past the timeout budget, `haystack-reviewer.sh` reads the latest `Haystack / Review` check run for the PR head. The check run is used as fallback/readback evidence; CLI triage remains the preferred source because it exposes richer finding details and fix prompts.
- **Terminal large-PR skip**: At each normal observation boundary, the adapter checks the current-head `Haystack / Review` run for a completed result that explicitly says the PR exceeds Haystack's analysis or file limit. That authoritative outcome becomes `RESULT=skipped`, `REASON=analysis_skipped_file_limit`, and `DISPLAY_RESULT=skipped (analysis file limit)` immediately. Generic `action_required`, generic `Analysis Skipped` text, numeric counts, unrelated limits, incomplete runs, comments, and prior-head evidence do not match.
- **Policy-verdict visibility**: After triage completes, `haystack-reviewer.sh` also reads `haystack pr-status <PR> --json`. When Haystack reports `needsHumanReview: true` or `analysisVerdict: "needs-review"`, the reviewer loop keeps the result non-blocking if there are no blocking findings but displays `haystack (needs-review: policy)` in the PR summary instead of `haystack (clean)`. The summary also records the Haystack bucket, `needsHumanReview`, and a disposition such as `blocking`, `policy-human-review`, `advisory-only`, or `good-to-merge`.
- **No per-hour rate cap**: Unlike some hosted review services, Haystack triage is not subject to hourly review limits (as of the time of writing).
- **Graceful degradation**: If neither CLI triage nor the GitHub App check run is reachable, the reviewer exits with `UNAVAILABLE` and the review loop continues with the remaining configured platforms.
- **GitHub App optional**: The CLI path is still sufficient. The GitHub App check run is optional fallback/readback state and must not be treated as ordinary CI when `haystack` is configured as a reviewer.

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

Add `haystack` to `review.on_ready.github` in `.ai-dev-workflow.yaml`:

```yaml
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github:
      - haystack
```

No other configuration changes are required in `.ai-dev-workflow.yaml`. If a repository uses the Haystack GitHub App check run under a non-default name, set `HAYSTACK_CHECK_NAME` for the reviewer and CI loop; the default is `Haystack / Review`.

Before relying on the GitHub App check run, verify that the organization permits
the Haystack App and that the current repository is included in the App
installation. Local CLI authentication is separate from GitHub App access: a
developer can be authenticated locally while GitHub still reports `Haystack /
Review` as failed or pending because the App cannot read the repository. A
healthy setup test is a small PR whose Haystack review completes with zero
blocking findings and whose `Haystack / Review` check is reachable from the PR
details URL.

If the repository creates implementation PRs as drafts, prefer
`review.on_ready.github` for Haystack. In this mode the reviewer loop lets
draft-compatible platforms clear first, marks the PR ready, and then runs
Haystack. Haystack triage may remain `pending` indefinitely while a PR is still
draft, so running it before `gh pr ready` can produce avoidable
`pending_timeout` escalations.

---

## Bot Login Identifier

Haystack triage does not post inline GitHub review threads in this integration. The Haystack CLI reads triage results locally and does not push findings to the GitHub PR review thread API. The Haystack GitHub App can publish a check run, but that check run is not a review thread.

Because no GitHub review threads are posted, the `check_unresolved_threads` gate is not invoked for Haystack. `bot_login_for_platform("haystack")` returns an empty string `""`, which signals to `pr-review-loop.sh` that no thread audit is needed.

If a future integration adds Haystack inline thread posting, this can be updated to the actual bot login (e.g., `haystack-ai[bot]`). A check run alone does not require changing the bot login.

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
| `Code contract violation` | Advisory | Non-blocking; used for API/protocol usage findings. Haystack's own policy verdict (`haystack pr-status`) classifies PRs with only this finding as "good-to-merge" / "clean", so the reviewer loop treats it as advisory-only |
| Any unrecognised value | Blocking | Conservative safe-fail per spec BR-2 |

The `COMMENT_COUNT` output equals `BLOCKING_COUNT + SUGGESTION_COUNT`.

## Review Policy Verdicts

Haystack exposes two related but separate result channels:

| CLI command | Data surfaced | Reviewer-loop treatment |
| ----------- | ------------- | ----------------------- |
| `haystack triage <PR> --json` | Code-review findings in `.findings[]` and rating | Blocking categories stop the loop; advisory categories increment `SUGGESTION_COUNT` |
| `haystack pr-status <PR> --json` | Pipeline/review-policy verdicts such as `analysisVerdict`, `needsHumanReview`, `bucket`, `hasReviewer`, and `haystackRating` | Non-blocking visibility signal when no blocking triage findings exist |
| `Haystack / Review` check run | GitHub App status, details URL, output summary, and annotations when installed | Fallback/readback source when CLI triage cannot return completed findings; ignored by `pr-ci-loop.sh` as generic CI when Haystack is configured as a reviewer |

When `pr-status` reports `needsHumanReview: true` or
`analysisVerdict: "needs-review"`, `haystack-reviewer.sh` emits:

```text
POLICY_STATUS_AVAILABLE=1
POLICY_REVIEW_REQUIRED=1
POLICY_DISPOSITION=policy-human-review
POLICY_VERDICT=needs-review
POLICY_NEEDS_HUMAN=true
DISPLAY_RESULT=needs-review: policy
```

`pr-review-loop.sh` uses `DISPLAY_RESULT` in its summary comment, so a clean
triage result with a policy verdict appears as:

```text
haystack (needs-review: policy)
```

The same summary comment includes an explicit policy acknowledgement handoff:

```text
Policy acknowledgements:
- haystack: bucket=needs-assignment; needsHumanReview=true; disposition=policy-human-review; verdict=needs-review; analysisStatus=ready; rating=5; hasReviewer=false;
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

### "Rules violation" — CHANGELOG structure findings

Haystack uses the `Rules violation` category for custom rule findings,
including CHANGELOG structure checks (rule
`keep-single-unreleased-changelog-section`). Normal feature/fix/refactor PRs
should write `changelog.d/` fragments rather than editing `CHANGELOG.md`
directly, so this rule is primarily relevant to release and hotfix PRs that
intentionally mutate `CHANGELOG.md`.

> **IMPORTANT — for agents**: When you see a `Rules violation` finding that
> references CHANGELOG structure, first verify the current PR type. For normal
> implementation PRs, the correct fix is to use a valid `changelog.d/` fragment
> and avoid direct `CHANGELOG.md` edits. For release or hotfix PRs, verify the
> structure with the authoritative lint checks before changing the changelog.

**Why false positives can happen**: Haystack's LLM-based CHANGELOG structure
checker analyzes a diff, not the fully rendered file. On release and hotfix
PRs, that can misread valid movement around `## [Unreleased]` and versioned
sections.

**Resolution**: `Rules violation` is classified as advisory (non-blocking) in `haystack-reviewer.sh`. The loop exits `RESULT=clean` with `SUGGESTION_COUNT=1`. No code change is required. Verify:

1. Normal implementation PRs have a valid `changelog.d/` fragment and do not edit `CHANGELOG.md` directly.
2. Release and hotfix PRs preserve one `## [Unreleased]` section, put any hotfix versioned section directly below it, and keep subsection headers non-duplicated.
3. The `check-changelog-duplicate-headers.sh` CI check and `markdownlint-cli2` lint pass — these are the authoritative validators for CHANGELOG structure and are not subject to Haystack's diff-interpretation issue.

If both conditions hold, the finding is a confirmed false positive and can be dismissed.

### Mirror guidance — actionable drift vs. stale advisories

Haystack also uses `Rules violation` for mirror guidance around the agent-doc surface map. Treat those findings as follows:

- **Actionable mirror drift**: a real mismatch exists between matching `.claude/agents/*` and `.cursor/agents/*` workflow docs, or between another documented mirror pair that actually exists in the repository.
- **Non-actionable advisory**: the finding is based only on tool-specific front matter, a missing `.cursor/skills` tree, or another surface that the repository does not actually contain.

The reviewer loop keeps these findings non-blocking. Use the repository surface map and the mirrored file content to decide whether a `Rules violation` needs a fix or just a note in the summary comment.

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

`haystack-reviewer.sh` degrades gracefully in four distinct scenarios:

**Analysis skipped because the PR exceeds Haystack's file limit**
(`REASON=analysis_skipped_file_limit`, exit 3):

```text
RESULT=skipped
REASON=analysis_skipped_file_limit
DISPLAY_RESULT=skipped (analysis file limit)
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
COMMENT_COUNT=0
```

This is a healthy, terminal platform skip rather than a reviewer-health
failure. It does not add `reviewer-failed`, and the adapter checks for it before
each triage observation and again after transient triage output before sleep.
The result therefore stops the extended polling window promptly and remains
stable on a same-head rerun. The workflow-owned Automated Reviewer Loop Summary
and its `reviewer_loop_history.v1` payload preserve the distinct display token.
The skip is permissive for Haystack only: other reviewer findings, CI failures,
unresolved review threads, regression checks, and readiness requirements remain
authoritative.

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

In all four cases, `pr-review-loop.sh` continues with the remaining platforms.
Only the file-limit outcome is a healthy skip; the other three are reviewer
health failures.

When any of the three Haystack reviewer-health failures occur,
`pr-review-loop.sh` applies the `reviewer-failed` label to the PR so the failure
is visible from the PR list or project board. The label is self-healing: a later
loop run that reaches healthy reviewer output (`clean`, `needs_fixes`,
`needs_rerun`, `skipped/not_configured`, or
`skipped/analysis_skipped_file_limit`) removes `reviewer-failed`.

---

## Exit Code Contract

| Exit code | Meaning | RESULT emitted | REASON emitted |
| --------- | ------- | -------------- | -------------- |
| `0` | APPROVED — no blocking findings | `clean` | — |
| `1` | NEEDS_REVISION — one or more blocking findings | `needs_fixes` | — |
| `2` | TIMED_OUT — per-call OS timeout exhausted the overall budget | `skipped` (→ `escalate` via `pr-review-loop.sh`) | `timeout` |
| `2` | PENDING_TIMEOUT — analysis stayed `pending` until the overall budget expired | `skipped` (→ `escalate` via `pr-review-loop.sh`) | `pending_timeout` |
| `3` | UNAVAILABLE — CLI not installed, authentication failed, `status=none` | `skipped` | `unavailable` |
| `3` | ANALYSIS_SKIPPED_FILE_LIMIT — completed current-head check explicitly declines an oversized PR | `skipped` | `analysis_skipped_file_limit` |

The `REASON` field distinguishes reviewer-health failures from the terminal
file-limit outcome. Callers can retry later for `pending_timeout`, investigate
connectivity for `timeout`, check authentication for `unavailable`, or continue
the remaining gates immediately for `analysis_skipped_file_limit`.

---

## Troubleshooting

### Haystack reports `Analysis Skipped` for an oversized PR

The adapter accepts this outcome only from a completed `Haystack / Review`
check fetched for the current PR head, and only when its title or summary
explicitly says the PR exceeds the Haystack analysis or file limit. When the
predicate matches, the reviewer loop records
`analysis_skipped_file_limit`, posts or updates its script-owned summary and
durable history, and continues with every other configured gate.

Do not reproduce this behavior with a manual summary comment. If the distinct
reason is absent, inspect the current-head check run and follow the normal
pending, unavailable, finding, or timeout path. Free-form issue comments and
prior-head check runs are deliberately not authoritative.

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

### Haystack check is access-restricted (`HTTP 403` / `REASON=forbidden`)

**Cause**: The Haystack GitHub App or organization policy cannot access the
repository even though CLI triage or another reviewer source may show zero
blocking findings. This is reviewer infrastructure evidence, not a successful
fresh review.

**Remediation**: Restore repository or organization App access first, then
rerun the reviewer loop and delegated merge gate. If access cannot be restored
in the required window and this check is the only remaining protection blocker,
the delegated gate may present a human-only exceptional path. That path requires
current green CI, zero blocking reviewer findings, current access-denial
evidence, remediation evidence, and the canonical exceptional-bypass policy in
[`guardrails-enforcement.md`](../guardrails-enforcement.md) Gate 5. It is never
implied by delegated merge policy or batch approval.

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

> **Protocol guard (when Haystack is listed in `review.on_ready.github` and the loop returns `skipped/pending_timeout`)**: Before applying `ready-for-human-review`, agents must verify that `REASON=pending_timeout` is not masking real findings. Check whether the Haystack GitHub App has posted a "Haystack Code Reviewer: PR Analysis Ready!" comment on the PR:
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

### "Rules violation" finding for CHANGELOG structure

```text
INFO: findings parsed — blocking: 0, advisory: 1, total: 1
RESULT=clean
```

**Cause**: Haystack fired the `keep-single-unreleased-changelog-section` rule
on a PR with changelog-related changes. The finding is advisory and does not
block the reviewer loop.

**Remediation**: For normal implementation PRs, verify that the PR uses a valid
`changelog.d/` fragment and does not edit `CHANGELOG.md` directly. For release
or hotfix PRs, verify that `markdownlint-cli2` and
`check-changelog-duplicate-headers.sh` both pass. No code change is required
for a confirmed false positive.

### "Rules violation" finding on a hotfix backport PR

```text
INFO: findings parsed — blocking: 0, advisory: 1, total: 1
RESULT=clean
```

**Cause**: Haystack flagged a `Rules violation` finding for CHANGELOG structure on the backport PR. This is a known false positive (see the "Hotfix backport PRs" subsection above). The finding is advisory and does not block the reviewer loop.

**Remediation**: Verify that the merged CHANGELOG on `develop` will have correct Keep-a-Changelog structure. No code change is required; the finding can be dismissed.

### "Code contract violation" finding (stale or for fixed code)

```text
INFO: findings parsed — blocking: 0, advisory: 1, total: 1
RESULT=clean
```

**Cause**: Haystack reported a `Code contract violation` finding, typically for API/protocol usage concerns such as unescaped free-form values in structured output lines. The category is advisory (`SUGGESTION_COUNT`), not blocking. Haystack's own policy verdict (`haystack pr-status`) classifies PRs with only this category as "good-to-merge" / "clean", so the reviewer loop exits `RESULT=clean`. This finding can also appear as a stale cached result after the underlying issue has been fixed.

**Remediation**: Verify the finding is described accurately. If the cited issue is already fixed (e.g., multi-word values are already single-quoted), the finding is a stale Haystack cache result and can be dismissed. Push a new commit (e.g., a test addition) to force Haystack to re-analyze the latest code if needed.

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
| `.ai-dev-workflow.yaml` | Declare `haystack` under `review.on_ready.github` |
| `docs/workflow/development-workflow/integrations/haystack.md` | Haystack local git hooks integration (truncation checker, LLM_RULES.md) |

---

## See Also

- [`pr-review-platform.md`](pr-review-platform.md) — Step 7 multi-platform review loop (platform-agnostic)
- [`haystack.md`](haystack.md) — Haystack git hooks integration
- [`coderabbit.md`](coderabbit.md) — CodeRabbit integration (opt-in reviewer)
- Protocol 93 — [`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md)
