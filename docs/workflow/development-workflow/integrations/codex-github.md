# Integration: Codex GitHub Reviewer

`codex-github` is the default ready-phase GitHub reviewer for this template.
It is triggered by `scripts/development-workflow/codex-github-reviewer.sh`,
which posts the configured Codex trigger phrase to the pull request and waits
for Codex review evidence on the current head commit.

Before posting a trigger, the script first checks for existing Codex evidence on
the current PR head. This catches reviews that GitHub/Codex already started
automatically when the PR was opened, marked ready, or updated, and avoids
spending another full poll cycle on a duplicate trigger. The scan waits up to
`CODEX_GITHUB_PRE_TRIGGER_WAIT` seconds, default `60`; set it to `0` to skip
the pre-trigger check. Existing evidence is accepted only when it is tied to the
current head: a submitted review whose `commit_id` matches the current
`headRefOid`, a SHA-pinned root comment whose `Reviewed commit` marker matches
that head, or unresolved non-outdated Codex review threads. Stale review
evidence for an older head and resolved threads are ignored and the normal
trigger path still runs.

The reviewer requires terminal evidence that can be tied to the current PR head:
a submitted GitHub review whose `commit_id` matches the current `headRefOid`, or
current-head inline review comments. Codex-authored root PR comments are terminal
only when they include a `Reviewed commit` marker matching the current head;
otherwise they are used for acknowledgement, usage-limit, and setup-failure
detection only. A thumbs-up reaction on the trigger comment is only an
acknowledgement and does not make the PR clean by itself.

When the SHA-pinned root comment and a submitted review are both terminal
evidence, the strictly newer one wins; on an exact timestamp tie, any
response that is not a clean approval — blocking or unrecognized format,
either of which the verdict classifier would not exit `APPROVED` for —
always wins over an approved one, regardless of which side supplied it, and
a later non-terminal (ancillary) root comment never discards an earlier
SHA-pinned blocking one. A failed fetch of Codex root PR comments — including
during the async grace-period poll — is treated as unavailable, not as
absence of evidence, so it cannot be silently overridden by a clean
submitted review.

## Expensive reviewer gate

`codex-github` is an expensive reviewer. Before `pr-review-loop.sh` dispatches
it, the expensive-reviewer gate requires four current-head conditions,
evaluated in order and stopping at the first unmet one:

1. `local-ai-reviewer` is configured and has current-head clean evidence
   (exact `1` on both derived keys; missing/stale/unexpected values defer)
2. Every preceding peer under the reordered platform list (same-bucket
   non-expensive peers plus earlier buckets) has acceptable evidence —
   `clean`, or `skipped` with an allow-listed reason
   (`not_configured`, `explicit-skip`, `release_pr`, `unsupported-platform`)
   confirmed by `reviewer_failed_label_required_for_result` returning false
3. Zero unresolved, non-outdated review threads on the same head
4. Non-reviewer baseline checks are non-empty and all green on the same head
   (empty set → `baseline_checks_unobserved`; reviewer-owned checks excluded)

Expensive reviewers are reordered last **within their own phase bucket** so
those peers can run first; the reorder never moves a draft-configured
expensive reviewer behind a ready-phase platform.

A defer sets the loop aggregate to `needs_fixes` /
`REASON=expensive_gate_deferred` (readiness withheld; Step 7 re-runs) and
breaks the platform iteration so later ready-phase platforms do not run.
Deferrals are bounded by `PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS` (default
`3`, head-scoped occurrence count). At the cap the loop escalates.
`EXPENSIVE_GATE_ESCALATION` is emitted **only** when
`EXPENSIVE_GATE_RESULT=deferral_cap` and is one of:

- `expensive_gate_deferral_cap` — budget exhausted
- `expensive_gate_deferral_budget_unreadable` — ledger unreadable
  (`EXPENSIVE_GATE_DEFERRALS=-1`); an absent ledger is `0` and defers normally

Override with `PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1` for a one-off run
(justify in the PR). The gate still emits `EXPENSIVE_GATE_RESULT=forced` with
the reason it would have deferred.

See Protocol 93 § Expensive reviewer gate for the full normative contract.

## Verdict Classification

`APPROVED` requires the response — the **entire, untruncated** body,
whitespace-normalized — to be an **exact** match against one of a small set
of literal templates captured verbatim from real Codex clean responses, each
template including the complete vendor `<details>` "About Codex in GitHub"
footer text. Today exactly one template is evidenced, covering the
`Codex Review: Didn't find any major issues. <flavor>` / `**Reviewed commit:**`
shape plus the complete footer. There is no vocabulary list, no grammar, no
truncation step, and no case-insensitive or punctuation-tolerant matching —
whitespace normalization (collapsing whitespace runs to a single space,
trimming the ends) is the only permitted flexibility.

**The template has exactly two bounded placeholders, never a general
wildcard**: the commit SHA (`[0-9a-f]{7,40}`, git's own documented
abbreviated-to-full SHA-1 hex-length range), and the `<flavor>` slot
immediately after "Didn't find any major issues. " — a single bounded
placeholder, ``[^*`[:cntrl:]]{1,40}`` (up to 40 characters, excluding
asterisk, backtick, and control characters), not a fixed word and not an
enumerated list.

**Why a placeholder, not an enumeration.** PR #1494's own Codex review
returned `:rocket:` instead of the originally-shipped `Swish!` literal,
proving the vendor rotates this slot. The first fix enumerated every
evidenced token as a literal alternation — but a repository-history sweep
for that fix found 14 distinct tokens (single words, full sentences, GitHub
emoji shortcodes, inconsistent trailing punctuation) from under 50 samples,
a discovery rate indicating LLM-generated variety rather than a fixed,
enumerable vocabulary. Enumeration would not have converged — the same
non-convergence failure this classifier's entire design history exists to
avoid, on a new axis. The bounded placeholder replaced the alternation
before merge.

**Bound derivation**: the 40-character cap is the longest evidenced token
(31 characters, "More of your lovely PRs please.") rounded up with modest
headroom. The excluded characters protect adjacent template structure only:
asterisk protects the `**Reviewed commit:**` marker that follows, backtick
protects the SHA field's delimiters, and control characters (including
newline) are excluded as defense in depth even though whitespace
normalization already prevents them from reaching this point.

**The deliberate, disclosed trade of this design**: a genuinely clean
response using different wording anywhere in the body — including a
cosmetic vendor footer rewording, or a flavor phrase exceeding 40 characters
or containing an excluded character — safe-fails to `NEEDS_REVISION` today
rather than being approved. This failure direction is always safe (more
`NEEDS_REVISION`, never a false `APPROVED`). **The flavor placeholder is the
one exception to "never a false `APPROVED`" stated plainly, not hidden**: a
false `APPROVED` through this slot requires Codex to emit self-contradictory
output — a clean verdict immediately followed by an actual directive inside
the 40-character slot, while still reproducing the complete, exact footer
afterward. No evidence of this has ever been observed; recovery if it ever
is, is narrowing the placeholder's bound, never widening it without new live
evidence. See issue #1491's implementation plan (Decision 2 and its two
addenda) for the full design history and rationale.

## Prerequisites

Before a repository keeps `codex-github` in `review.on_ready.github`, verify:

1. The Codex GitHub integration is installed and enabled for the target
   repository or organization.
2. The account or team running the workflow has access to Codex GitHub PR
   reviews.
3. The default trigger phrase works for the repository:

   ```text
   @codex review
   ```

4. The bot login returned by GraphQL matches the default expected by the
   reviewer, or `CODEX_GITHUB_BOT_LOGIN` is set accordingly:

   <!-- workflow-shell-contract: bash-zsh -->

   ```bash
   CODEX_GITHUB_BOT_LOGIN=chatgpt-codex-connector[bot]
   ```

Do not store account tokens or secrets in `.ai-dev-workflow.yaml`. Use local
environment variables, CI secrets, or a local untracked config when an override
is needed.

## Workflow Configuration

The template default is:

```yaml
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github:
      - codex-github
```

If Codex GitHub is not available in a downstream repository, remove
`codex-github` from that repository's shared `.ai-dev-workflow.yaml` or override
the ready-phase reviewer list locally in `.ai-dev-workflow.local.yaml` until the
integration is installed.

## Verification

Use a disposable or already-open PR and run:

<!-- workflow-shell-contract: bash-zsh -->

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> \
  --platform pr-agent,codex-github \
  --ready-phase codex-github \
  --post-final-summary \
  --max-wait 1800 \
  --poll-interval 60
```

Expected successful evidence:

- `PLATFORM_1_RESULT=clean` for PR-Agent, or `skipped` only when intentionally
  unavailable.
- `PLATFORM_2_NAME=codex-github`.
- `PLATFORM_2_RESULT=clean`.
- `RESULT=clean`.

If the result is `needs_fixes`, address the reported review threads and rerun
the reviewer loop. If the result is `escalate` or `skipped` with an availability
reason, treat that as integration setup evidence rather than a clean review.

Codex may also respond to `@codex review` with a setup message such as
`To use Codex here, create an environment for this repo`. That is an unavailable
review path, not a clean result. Create the Codex cloud environment or remove
`codex-github` from the configured reviewer list until the integration can
produce current-head review evidence. Within a single invocation's poll
window, a recorded environment-setup error cannot be silently overridden by
a later thumbs-up reaction or by review/comment evidence that is not
strictly newer than the recorded error — but a genuinely fresh, strictly
newer current-head review (e.g. after an operator creates the environment
mid-poll) is allowed to supersede it, following the same newest-wins rule
applied to every other evidence type. A blocking terminal or review finding
is the one exception to newest-wins: it always wins outright over an
environment-setup error regardless of timing, so an actionable finding can
never be hidden behind an "unavailable" verdict. This applies within a
single poll as
well as across polls: an environment-setup error is not silently discarded
by a same-fetch or later plain acknowledgement, since a bare acknowledgement
carries no information and is never treated as competing evidence. A
usage-limit notice follows the same PRIORITY rules as an environment-setup
error for ranking purposes (e.g. against a same-timestamp unrecognized-format
response), but not the same RETENTION rule: unlike an environment-setup
error, a usage-limit notice terminates the invocation immediately as soon as
it is detected (`VERDICT: UNAVAILABLE`), rather than being retained through
the rest of the poll window for a later, strictly newer review to
potentially supersede. Codex hitting its own usage limit is treated as a
harder stop than a misconfigured environment, since a fresh useful review
arriving moments later in the same short poll window is unlikely once quota
is exhausted.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| The loop waits until timeout after posting `@codex review` | Codex GitHub is not installed, not enabled for the repository, or the account cannot run reviews | Install/enable the integration, confirm account access, then rerun the loop |
| Codex leaves only a thumbs-up reaction on the trigger comment | Codex acknowledged the trigger but did not publish SHA-pinned review evidence | Treat the run as unavailable; do not mark the PR clean from the reaction alone |
| Codex says to create an environment for this repo | Manual trigger path is missing a Codex cloud environment | Create the environment or remove `codex-github` from the reviewer list until it is available |
| Codex review threads remain open after a fix commit | GitHub did not auto-resolve a fixed thread | Verify the current head addresses the finding, then resolve the thread or rerun review if unsure |
| Codex submitted a review for an older commit | Review arrived for a stale head SHA | Push or retrigger only if needed, then wait for a submitted review whose `commit_id` matches the current head |
| Thread authors do not match the default bot login | Repository uses a different Codex bot identity | Set `CODEX_GITHUB_BOT_LOGIN` to the observed bot login |
| Old threads are still visible but marked outdated | GitHub marked the original diff location stale after the fix | Outdated threads are non-blocking in workflow readiness audits |

## Related Files

- [Workflow Configuration](../README.md#workflow-configuration)
- [Automated PR Review Platforms](pr-review-platform.md)
- `scripts/development-workflow/codex-github-reviewer.sh`
- `.ai-dev-workflow.yaml`
