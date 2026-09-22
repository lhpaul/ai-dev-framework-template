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
When `codex-github` is in the ready / `phase_after_clean` bucket, the loop
preflights this gate for remaining ready-phase expensive platforms **before**
`gh pr ready` with peer scope limited to earlier (draft) buckets, so an
automatic Codex start on mark-ready cannot outrun local/thread/baseline checks
and cannot deadlock waiting on same-bucket peers that need ready state. The
full gate (including same-bucket peers) still runs again immediately before
`run_platform_review`.
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

## Resolved Codex findings and blocker counting (#1757)

A resolved Codex review conversation must not, by itself, count as a
current blocker — even if its comment remains visible or re-anchored on the
diff. `codex-github-evidence-lib.sh` (`codex_review_thread_evidence_counts`)
is the single shared implementation of applicability-aware Codex
review-thread counting, sourced by both `codex-github-reviewer.sh` (the
companion's own pre-trigger existing-evidence check) and
`pr-review-loop.sh`'s `run_codex_github_review()` (the phase-1 gate and the
post-companion exit-1 recount). A thread only counts toward a blocker when
**all** of the following hold:

- it is not `isResolved` and does not carry a bot `✅ Addressed` marker
  (a resolved Codex finding is excluded regardless of visibility), and
- it is not outdated, and
- its owning review is not `DISMISSED`, and
- its owning review's commit matches the pull request's live `headRefOid`
  (when that commit cannot be read at all, the thread fails closed — it is
  still treated as a blocker rather than silently cleared).

The function exposes a `strict | provisional` mode (default fallback:
strict). `provisional` preserves issue #1508's "fixed and replied to, but
not yet resolved" relaxation for the companion's own re-trigger-eligibility
decision only; `strict` never applies that relaxation and is what both the
loop's phase-1 blocker gate and its post-companion recount use, so the
#1508 relaxation can never leak into a gate that decides `needs_fixes`.

**The pre-#1757 `unresolved_count=1` floor is removed.** Previously, when
the companion returned `NEEDS_REVISION` (exit 1), `pr-review-loop.sh` forced
its recounted blocker total to at least 1 even when a strict recount
confirmed zero applicable unresolved threads — a resolved Codex finding that
was merely still visible on the pull request was reported as a current
blocker. Now, a confirmed-zero recount on that path returns
`RESULT=waiting_on_reviewer` / `REASON=codex-github-review-pending` (a
cleared-findings retrigger) instead of a stale `needs_fixes`. If the recount
itself cannot be completed (a transient GraphQL failure), the loop still
fails closed and reports one blocker, matching the shipped floor's original
safety intent for that failure case only.

**Acknowledgement-only evidence is a wait, not an escalation.** A thumbs-up
reaction with no submitted review (`codex_return_reaction_without_review`)
now exits `4` (`WAITING_ON_REVIEWER`) instead of exit `2`. The companion's
full exit-code contract is documented in
`codex-github-reviewer.sh`'s own header comment.

**Exit `3` (hard-unavailable) reason propagation.** `pr-review-loop.sh` now
reads the companion's own `REASON=` for an exit-3 outcome instead of
hardcoding `codex-github-usage-limit`, so
`codex_return_account_not_connected`'s distinct
`REASON=codex-github-account-not-connected` is reported correctly instead of
being mislabelled as a usage-limit notice.

**`Reviewed commit` marker well-formedness (AC-3, AC-4).**
`codex_extract_reviewed_commit_field` (pure/local) classifies the marker
field as `absent` (no `Reviewed commit` label at all — acknowledgement
evidence), `empty` (label present, no extractable value — malformed), or
`token` (a candidate value to validate). `codex_marker_classify` then
validates that token against the live head:

- **Shape**: empty, non-hex, or multi-token content is `malformed`.
- **String relationship**: a token that is an offset-zero prefix of the
  live head is a `prefix` candidate; a token occurring elsewhere inside the
  live head (interior-substring) or that contains the whole live head plus
  extra characters (superstring) is `malformed` regardless of what commit
  it would otherwise resolve to; any other token is a `prior_revision`
  candidate.
- **Ambiguity**: `git rev-parse --disambiguate=<token>`, filtered to commit
  objects, decides locally provable ambiguity (`malformed`) or uniqueness.
  A full 40-hex token additionally checks `gh api repos/{owner}/{repo}/
  commits/{token}` for a definitive `422` (`malformed`, proven zero-match).

**Disclosed scope note on ambiguity proof.** The specification's ideal is
that every abbreviated token's uniqueness be proven before it is trusted.
This implementation proves ambiguity/non-existence whenever the local git
object database or a reachable, matching GitHub REST response can
positively establish it, but an abbreviated token that neither source can
prove OR disprove is trusted at its already-computed string classification
(`prefix` / `prior_revision`) rather than escalated to
`evidence_unavailable_codex_thread_state`. A live-network retry
(`git fetch` before the local retry) is available but **opt-in**
(`CODEX_GITHUB_MARKER_FETCH=1`), not unconditional: this repository's shell
test harnesses guarantee "no external tooling required beyond bash and git
... mock `gh` commands replace all network calls", and this repository's
own Codex regression fixtures pin roughly 130 `Reviewed commit` scenarios
against synthetic SHAs that are not real commits anywhere and that the
shared `gh` test double does not implement a `commits/{sha}` endpoint for;
an unconditional proof requirement would make every one of those fixtures'
terminal-comment evidence indeterminate. Interior-substring/superstring
rejection, empty/non-hex/multiple-token detection, and locally provable
ambiguity are still fully enforced.

**Finding–thread correlation (AC-7, AC-9).**
`codex_review_finding_correlation` decides, per terminal verdict, whether
its findings are actionable, cleared, or correlation-missing:

- A **root pull-request comment** (no owning review) always contributes a
  blocking finding as `correlation_missing` — a comment owns no
  review-thread identifier by construction.
- A **submitted review**'s findings are its own inline comments
  (`pull_request_review_id` matching the review, `commit_id` matching the
  live head) plus any blocking assertion in the review's own body. A body
  finding is always correlation-missing (no thread identity); it takes
  precedence even when the review also has correlated inline findings.
  With no body finding, every inline finding must have an identifiable
  matching GraphQL review-thread conversation: any unidentifiable inline
  finding is correlation-missing; if all are identifiable and resolved
  (and the review is not itself `CHANGES_REQUESTED`), the verdict's
  findings are `cleared`.

`codex_finalize_verdict` in `codex-github-reviewer.sh` runs this
correlation check **unconditionally for every submitted review** (not only
one that already looks blocking) — finding extraction is per review, never
gated on the review's own body text alone, so a review with a genuine
inline finding under an unremarkable summary body is still evaluated. It
runs ahead of the companion's blocking-verdict emission at every
verdict-decision site: a correlation-missing verdict escalates
(`codex_finding_thread_correlation_missing`, exit `2`); an unresolved
correlated finding is the existing `NEEDS_REVISION` (exit `1`)
actionable-blocker path; a fully cleared verdict — with
`codex_review_thread_evidence_counts(strict)` confirming no other
applicable unresolved live-head conversation — waits for a fresh review
(`codex-github-review-pending`, exit `4`) instead of dispatching a fixer or
escalating, **except** a `CHANGES_REQUESTED` review, which is never treated
as cleared this way and stays actionable regardless of its own findings'
resolution state; a review with no finding requiring correlation at all is
only actionable through its own `CHANGES_REQUESTED` state, otherwise it is
not actionable and the caller's own usage-limit/approved/unrecognized chain
decides it. A root-comment-sourced verdict's blocking finding is always
correlation-missing, independent of this per-review check (no review object
to correlate against at all).

**Live-head evidence window (AC-13, AC-14).** A root comment's `Reviewed
commit` marker only counts as live-head evidence within that head's
evidence window: `codex_scan_comment_evidence` filters candidate marker
comments to `created_at` at or after the boundary (the latest review
trigger for a triggered head, tie-broken by comment ID; the pull request's
own `created_at` for a trigger-less head), matching the freshness boundary
the four post-trigger poll sites already enforce server-side in their own
`gh api` query. **Disclosed scope note**: this item does not implement the
force-push/`head_ref_deleted`/`head_ref_restored` occupancy guard that
raises the boundary further for a SHA-reuse (revert-and-return) scenario —
an accepted, narrow residual on top of the freshness-boundary
implementation above.

**Unrecognized verdicts now escalate (AC-7).** A current terminal verdict
that matches neither an approved clean template nor the documented
blocking markers — previously `NEEDS_REVISION` (exit `1`, "unrecognized
response format — safe-fail") — now escalates
`codex_current_verdict_unrecognized` (exit `2`).

**The four new fail-closed escalation reason codes** —
`codex_current_verdict_malformed_revision_marker`,
`codex_finding_thread_correlation_missing`,
`codex_current_verdict_unrecognized`, and
`evidence_unavailable_codex_thread_state` — are terminal for the current
run and are never converted into `needs_fixes`, `waiting_on_reviewer`, or
clean readiness. `evidence_unavailable_codex_thread_state` also covers a
bounded thread/correlation evidence query that fails or is truncated after
retry.

**Cycle-limit interaction (AC-5).** `reviewer_loop_cap_exceeded` now treats
a `waiting_on_reviewer` aggregate result the same as `needs_fixes` /
`needs_rerun`: an exhausted per-run or lifetime allowance escalates
(`max_cycles_exceeded` / `max_total_cycles_exceeded`) rather than emitting
`waiting_on_reviewer` when the evaluation would otherwise require another
review cycle — including a cleared-findings retrigger. A `clean` result is
never overridden by an exhausted allowance.

## Step 7a runner reviewer

`codex-github` is an opt-in Step 7a runner reviewer value; it is not in the
shipped default list. Add it to `review.on_draft.runner` only when the Codex
GitHub App is configured for the repository. Availability is decided at runtime
by the bounded repository-activity proxy described in Protocol 91. That proxy
does not prove installation: historical activity can be stale and a new or
review-only installation can have no issue-comment activity. See the existing
verification checklist below before opting in.

<!-- step7a-codex-github-availability:start -->
`codex-github` needs no local Codex runtime, so no driving runner is inherently barred. Its bounded repository-activity proxy reports `prerequisite-missing` for no bot activity on a complete short page and `check-inconclusive` for a full unmatched page. Post-dispatch errors remain review failures, never unavailable reclassification.
<!-- step7a-codex-github-availability:end -->

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
