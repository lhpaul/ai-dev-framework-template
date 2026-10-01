# A reviewer that has not answered yet is not a failed reviewer — Implementation Plan

**Spec**: [`1_1789-reviewer-no-verdict-yet_specs.md`](1_1789-reviewer-no-verdict-yet_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1789-reviewer-no-verdict-yet.smoke-test.md`](../../../testing/workflow/1789-reviewer-no-verdict-yet.smoke-test.md)
**Issue**: #1789 (observed on PR #1787)

---

## Summary

**Approach**: Replace the single global reviewer wait in
`scripts/development-workflow/pr-review-loop.sh` with a per-platform wait
budget resolved in the spec's order (one-run override, configured value,
built-in default). Make every platform handler report a wait that ran out with
no verdict and no failure evidence as **No verdict yet** — the existing
`waiting_on_reviewer` result with the new platform-neutral reason
`reviewer-no-verdict-yet` — instead of `escalate`/`timeout`, while keeping the
existing expired-wait non-blocking skips (D8) as skips. Reconcile the
`reviewer-failed` label from per-platform failure evidence on every exit path
that evaluates reviewers, apply the spec's cross-platform precedence where a
run produces several outcomes, record per-platform budget and latency in run
output, the summary comment, and the ledger, and teach Protocol 91 Step 7 a
single automatic re-wait per revision that never re-posts an outstanding
review request.

**Estimated complexity**: L

**Rationale**: The change touches every supported platform handler (V1) in
`pr-review-loop.sh`, three companion scripts (`local-ai-reviewer.sh`,
`claude-code-action-reviewer.sh`, `codex-github-reviewer.sh`), the readiness
helper `apply-readiness-labels.sh`, the config reader in `workflow-lib.sh`, the ledger record, the summary renderer,
Protocol 91 and Protocol 93, and the per-platform integration guides, each
with tests in a large existing harness.

**Dependencies**: None. Spec PR #1869 is merged into `develop` (base
`13bf4c7f`).

---

## Decisions

Each decision below is the single normative statement of its fact. Every
other section refers to the decision by its label (D1–D14) instead of
restating the value.

### D1 — Platforms that do not review documentation branches (spec plan note 1; BR 8, AC-4)

The set is exactly `{devin}`. Evidence (Verification Log V3–V5): the only
code or documentation in the repository that names a platform as not
reviewing `spec/*` or `implementation-plan/*` branches is the Devin statement
in the `--help` text and the branch-type-aware timeout comment of
`pr-review-loop.sh`; the PR-Agent workflow has no branch filter; Claude Code
Action is dispatched on demand; Bugbot reviewed `implementation-plan/*`
branch PR #1787 five times; `local-ai-reviewer` selects dedicated `spec` and
`plan` checklists for those branches. The documentation-branch shortening
(`PR_REVIEW_LOOP_DOC_MAX_WAIT`, default 180 s) therefore applies only to
Devin's built-in default on those branches. A future platform is added to the
set only by editing the single membership function named in Layer 1.

### D2 — Built-in default wait budgets (BR 9, AC-6)

| Platform | Built-in default (seconds) | Source of the value |
| --- | --- | --- |
| `bugbot` | 2400 | D3 |
| `codex-github` | 1800 | Unchanged prior default (`codex_github_default_max_wait`) |
| `greptile`, `devin`, `coderabbit`, `coderabbit-cli`, `local-ai-reviewer`, `pr-agent`, `claude-code-action`, `copilot`, `haystack`, `ronda` | 1200 | Unchanged prior implementation-branch default (BR 9 floor) |
| `devin` on `spec/*` or `implementation-plan/*` | `PR_REVIEW_LOOP_DOC_MAX_WAIT` (default 180) | D1 — the only shortened built-in default |

No value in this table is below the BR 9 floor for its platform on
implementation branches.

### D3 — Bugbot default and its polling margin (spec plan note 2; BR 9, AC-3, AC-6)

Bugbot's built-in default is **2400 s**. The handler keeps its #1390 one-shot
re-trigger, but the budget now bounds the whole handler wait (both attempts).
The re-trigger point is `budget - min(600, floor(budget / 2))`, which is
**1800 s** for the default.

Rationale:

- BR 9 requires that a Bugbot verdict arriving up to 1500 s after the request
  is observed. The handler checks the check run at elapsed counter values
  `0, p, 2p, …` while the counter is below the attempt window, and the counter
  never runs ahead of wall-clock time (it adds the poll interval and ignores
  API time). A verdict at wall time `T` is therefore guaranteed to be observed
  inside the first attempt when the first attempt's window is at least
  `T + p`. With the implementation-branch poll interval `p = 120` (D14) the
  requirement is `1500 + 120 = 1620 ≤ 1800`; the remaining 180 s is 1.5 poll
  intervals of slack for API latency. On documentation branches `p = 30`
  (D14), so the margin is larger.
- The retry window after the re-trigger is 600 s, about twice the slowest
  trigger-to-completion latency in the recorded PR #1787 sample (V7 is the
  single statement of the sampled values).
- Placing the re-trigger after 1500 s means AC-3's "answers clean 25 minutes
  or less after the request" case is always observed before any re-trigger,
  so the re-trigger can never replace the run that is about to answer.
- 2400 s equals the existing `LARGE_DIFF_MAX_WAIT` default, so the large-diff
  extension (D7) never changes Bugbot's default.

The #1390 re-trigger is skipped in re-wait mode (D11).

### D4 — `local-ai-reviewer` budget and No verdict yet detection (spec plan note 3; BR 3, AC-1)

- Budget: built-in default per D2 (1200 s) on every branch, including
  documentation branches, where it previously received the 180 s documentation
  budget through `--timeout "$max_wait"`. The loop keeps passing the resolved
  budget as `--timeout`; `LOCAL_AI_REVIEWER_TIMEOUT` keeps applying only to
  standalone companion runs, as today.
- **No verdict yet**: `run_with_timeout` returned 124 or 137, which is the
  companion's existing signal that it stopped the reviewer process at the end
  of the budget while it was still running (`local-ai-reviewer.sh`
  `run_with_timeout` and the 124/137 branch, V9). The companion then prints
  `RESULT=waiting_on_reviewer`, `REASON=reviewer-no-verdict-yet`,
  `NO_VERDICT_YET=1` and exits **4**. The partial output of a stopped process
  is not inspected: a process that was still running when stopped had not
  reported an error by exiting, and this keeps the design free of any match on
  reviewer free text.
- **Reviewer failed**: every existing non-timeout `escalate` path in the
  companion is unchanged — a non-zero command exit before the budget, output
  the loop cannot read (`malformed_output`), credential, model-access,
  repository, head, and contract failures. `quota_exhausted` keeps its
  existing handling (BR 11 / AC-13).
- The strict spec/plan second pass inside the companion keeps its existing
  `strict_pass_failed` non-blocking `unavailable` state when it runs out of
  the shared budget; it never changes the ordinary verdict.

### D5 — Codex GitHub wait reasons and the automatic re-wait (spec plan note 4; BR 7, AC-11)

**Yes**: `codex-github-review-pending` and
`codex-github-reaction-without-review` get the automatic one-time re-wait.
Rationale: the spec's Statuses section places both reasons in the No verdict
yet class, and BR 7 applies to that class; excluding them would keep the
exact unattended-stop symptom this item removes for the one platform with the
longest budget. The re-wait cannot post a duplicate request: the companion
already skips a new trigger while a current-head trigger is pending
(`codex-github-reviewer.sh` "trigger comment already posted for commit …
skipping duplicate post", V10), and in re-wait mode (D11) the loop passes
`--max-retriggers 0`, which also disables the async-arrival trigger (the
companion only posts it when `MAX_RETRIGGERS > 0`). The cleared-findings path
(`codex-github-review-pending` after every current-head finding was resolved)
still posts a fresh trigger, because the earlier request was answered and is
no longer outstanding.

### D6 — Where configured per-platform budgets live (BR 8, BR 10, AC-5)

- Key: `review.wait_budgets.<platform>` in `.ai-dev-workflow.yaml`, a block
  mapping whose keys are the supported platform names and whose values are
  whole seconds:

  ```yaml
  review:
    wait_budgets:
      bugbot: 2700
      local-ai-reviewer: 1500
  ```

- Read from the same PR-base config snapshot (`config_file`) the loop already
  uses for `review.max_cycles`, through a new reader
  `workflow_config_review_wait_budget <platform> [config_file]` in
  `workflow-lib.sh`.
- `CODEX_GITHUB_MAX_WAIT`, when set, remains Codex GitHub's configured value
  and takes precedence over `review.wait_budgets.codex-github` (the same
  env-over-file order `reviewer_loop_resolve_max_cycles` uses). No other new
  environment variable is added.
- Validation: a configured value must match `^[1-9][0-9]{0,5}$`. Anything
  else (empty, `0`, negative, decimal, exponent, non-numeric, seven or more
  digits) prints
  `WARN: review.wait_budgets.<platform> value '<v>' is not a positive whole number of seconds; using the built-in default`
  to stderr and the platform falls back to its built-in default with source
  `default`. An invalid `CODEX_GITHUB_MAX_WAIT` keeps its existing warning and
  then falls through to the YAML value or default.
- A `wait_budgets` key that is not a supported platform name (V1) prints one `WARN: review.wait_budgets.<key> is not a supported platform; ignored`
  line per run.
- A non-block value on the `wait_budgets:` line itself (for example a flow
  mapping) prints `WARN: review.wait_budgets must be a block mapping; ignored`
  and every platform uses its built-in default.

### D7 — Budget resolution order and adjustments (BR 8)

`reviewer_wait_budget_resolve <platform>` prints
`<seconds> <source> <adjustment>`:

1. `--max-wait` given → `<override> override none` for every platform; no
   adjustment ever applies to an override.
2. Else configured value (D6) valid → `<value> configured …`.
3. Else built-in default (D2) → `<value> default …`.

Adjustments after step 2 or 3:

- `documentation_branch`: only when the branch is `spec/*` or
  `implementation-plan/*`, the platform is in the D1 set, and the source is
  `default`; the value becomes the D2 documentation-branch value.
- `large_diff`: only when the branch is not `spec/*` or
  `implementation-plan/*`, the PR's changed-files count exceeds
  `LARGE_DIFF_THRESHOLD`, and `LARGE_DIFF_MAX_WAIT` is greater than the value
  from step 2 or 3; the value becomes `LARGE_DIFF_MAX_WAIT`. It never
  shortens. The changed-files fetch and its `CHANGED_FILES_COUNT` /
  `LARGE_DIFF_EXTENDED` output keep today's conditions (`--max-wait` not
  given, non-documentation branch).

### D8 — Outcome classes and the per-platform budget-expiry paths (BR 1–4, AC-1, AC-2, AC-8, AC-13)

New shared helper `print_no_verdict_yet <platform> <detail> <head_sha> <requested_at>`
prints the standard **No verdict yet** block:

```text
RESULT=waiting_on_reviewer
REASON=reviewer-no-verdict-yet
NO_VERDICT_YET=1
WAIT_EXPIRED_DETAIL=<detail>
PENDING_REVIEWER=<platform>
PENDING_REVIEW_HEAD_SHA=<head_sha>
REVIEW_REQUESTED_AT=<requested_at, omitted when unknown>
COMMENT_COUNT=0
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
```

Kept expired-wait skips (BR 4 exception) keep `RESULT=skipped` and their
existing `REASON`, and add `NO_VERDICT_YET=1` and
`DISPLAY_RESULT=no verdict yet (non-blocking skip: <reason>)`.

`reviewer_loop_platform_outcome_class <result> <reason> <no_verdict_flag>`
classifies each platform outcome for reporting:

| Result / reason | Class |
| --- | --- |
| `clean`, `needs_fixes`, `needs_rerun` | `verdict_received` |
| `waiting_on_reviewer` (any reason) | `no_verdict_yet` |
| `skipped` with `NO_VERDICT_YET=1` | `no_verdict_yet` (kept skip) |
| `skipped` with reason `unavailable`, `thread-check-failed`, `forbidden`, `unauthorized` | `skipped_failure_evidence` |
| other `skipped` | `skipped` |
| `escalate` with a reason in `REVIEWER_LOOP_AVAILABILITY_REASONS` | `existing_handling` |
| any other `escalate`, or an unrecognized result | `reviewer_failed` |

`REVIEWER_LOOP_AVAILABILITY_REASONS` is `rate_limited`,
`rate_limit_max_retries`, `codex-github-usage-limit`,
`codex-github-account-not-connected`, `bugbot-usage-limit`, `quota_exhausted`
(V11). It is a reporting label only: those outcomes keep their result,
reason, exit code, and label behavior byte-for-byte (AC-13).

**Binding enumeration** — the budget-expiry paths each handler changes, and
the failure-evidence paths it keeps (line numbers at `13bf4c7f`, V2):

| Platform | Budget-expiry path today | New outcome | Failure-evidence and availability paths kept unchanged |
| --- | --- | --- | --- |
| `greptile` | `escalate`/`timeout`, no bot thumbs-up by budget end (`pr-review-loop.sh:2130-2139`) | No verdict yet, detail `no_acknowledgement` | missing trigger comment id (`:2113-2115`) |
| `devin` | `escalate`/`timeout`, check seen but not completed (`:5236-5244`); `skipped`/`no_check_run`, no check ever seen (`:5225-5235`) | No verdict yet, detail `check_not_completed`; kept skip | stale-findings `needs_fixes` (`:5200-5221`) |
| `coderabbit` | `escalate`/`timeout`, activity seen (`:7846-7855`); `skipped`/`no_review`, no activity (`:7832-7844`) | No verdict yet, detail `review_not_submitted`; kept skip | `review_skipped_banner` (platform declined; `:7799-7814`), `rate_limit_max_retries` |
| `coderabbit-cli` | companion `skipped`/`timeout` (`coderabbit-cli-reviewer.sh:339-342`) forwarded by the loop's skip arm (`:4627-4644`) | kept skip | `unavailable`, `unauthorized`, `invalid_json`, `ambiguous_output`, `no_output`, `cli_failed` skips; escalate reasons |
| `local-ai-reviewer` | companion `escalate`/`timeout` on exit 124/137 (`local-ai-reviewer.sh:1321-1324`) forwarded by the loop's exit-2 arm (`:4864-4888`) | D4: companion exit 4; new loop exit-4 arm → No verdict yet, detail `stopped_at_budget` | every other companion escalate reason; `quota_exhausted` |
| `pr-agent` | `skipped`/`no_review` (`:5801-5812`) | kept skip | `pr_agent_trigger_failed`, `pr_agent_ambiguous_review` |
| `codex-github` | companion exit 4 (`codex-github-review-pending`, `codex-github-reaction-without-review`) | existing wait reasons kept, class `no_verdict_yet` (D5) | companion exit 2 and 3 reasons |
| `claude-code-action` | companion exit 2 when no run completed within the budget (`claude-code-action-reviewer.sh:397-401`), mapped to `escalate`/`timeout` (`:2623-2631`) | companion exits **4** for that case; new loop exit-4 arm → No verdict yet, detail `run_not_completed` | companion exit 2 for a completed run whose conclusion is not `success` → loop `escalate`/`claude_code_action_run_failed` (the companion's argument-validation exits, `claude-code-action-reviewer.sh:125-199`, also exit 2 and share that reason; still failure evidence); exit 3 → `unavailable` |
| `copilot` | `escalate`/`timeout` (`:2810-2817`) | No verdict yet, detail `review_not_submitted` | request failure `unavailable` (`:2700-2708`), `head-sha-unavailable` |
| `haystack` | loop `escalate` with companion reason `timeout` or `pending_timeout` (`:4481-4494`) | No verdict yet, detail = the companion reason | `draft-state-unavailable`; `unavailable`, `unauthorized`, `forbidden` skips |
| `bugbot` | `escalate`/`timeout`, check appeared but never completed (`:4331-4340`); `escalate`/`unavailable`, no check run ever appeared (`:4318-4328`) | No verdict yet, details `check_not_completed` and `check_not_started` | Bugbot's own `timed_out` conclusion (`:4237-4249`) renamed `escalate`/`bugbot-run-timed-out`; `fetch-failed`, `trigger-failed`, `head-sha-unavailable`, `unknown-conclusion-*`, `bugbot-unverified-verdict`, `bugbot-findings-not-retrievable`; `bugbot-disabled`, `bugbot-usage-limit` |
| `ronda` | `escalate`/`timeout` (`:3069-3076`) | No verdict yet, detail `check_not_completed` | `ronda_pass_failed`, `ronda_unexpected_conclusion`, `fetch-failed`, `head-sha-unavailable` |

The kept skips are exactly Devin `no_check_run`, CodeRabbit `no_review`,
CodeRabbit CLI `timeout`, and PR-Agent `no_review`. This set is the BR 4
exception; nothing else becomes a kept skip.

Current-revision evidence (BR 6, AC-10) is unchanged and relied on: every
handler that can see an older-revision verdict already filters by the current
head (Bugbot and Copilot by `commit_id`, Ronda and Bugbot by check runs on the
current head SHA, Codex by the `Reviewed commit` marker); such evidence keeps
the platform polling and therefore ends in the No verdict yet row above.

### D9 — `reviewer-failed` label reconciliation (BR 11, AC-7, AC-8, AC-13)

- `reviewer_failed_label_required_for_result` drops `timeout` and
  `pending_timeout` from its `skipped` list; the remaining `skipped` reasons
  (`unavailable`, `thread-check-failed`, `forbidden`, `unauthorized`) and the
  `escalate` rule (every reason except `rate_limited`) are unchanged.
  `waiting_on_reviewer` never requires the label (unchanged).
- New `reviewer_loop_reconcile_reviewer_failed_label <pr> <aggregate_result> <aggregate_reason>`
  (defined before the harness return point) computes
  `required = reviewer_failed_required OR label_required(aggregate)` and calls
  the existing `sync_reviewer_failed_label`. `reviewer_failed_required` is
  reset to 0 per invocation (`pr-review-loop.sh:13156`) and set per platform in
  `reviewer_loop_process_platform_output`, so the decision reflects only this
  run's platforms.
- Exit paths that call it: the main post-loop path (replacing
  `:14512-14515`), which every platform-evaluating run reaches — including a
  run whose platforms were all replayed from the ledger (#1692 staging),
  because the replay goes through `reviewer_loop_process_platform_output`
  (`:9554-9555`) and then falls through the same post-loop code. The
  not-configured exit (`:13962`) keeps `sync_reviewer_failed_label "$pr_number" 0`
  and the release-guard exit (`:12936`) keeps its removal, both as today.
  Ownership refusals, lock contention, `truncated_run`, and
  `execution_budget_misconfigured` exits never reach either call and leave the
  label unchanged, as today (V8).
- A failed add or remove is reported by `sync_reviewer_failed_label`'s existing
  `WARN` lines and never changes the result.

### D10 — Precedence across platforms (BR 5, AC-9)

New `reviewer_loop_precedence_select` ranks each recorded platform outcome
from `platform_peer_evidence` (`platform|result|reason`): rank 1 `escalate` or
any unrecognized result; rank 2 `needs_fixes` or `needs_rerun`; rank 3
`waiting_on_reviewer`; rank 4 `clean` or `skipped` (kept skips are `skipped`
and therefore rank 4). The overall result is the best rank; ties go to the
earliest platform in evaluation order, and that platform's recorded output
(from `platform_blocking_outputs`) becomes `aggregate_output`.

- `--compare` runs use it in place of "first blocking platform governs"
  (`:13967-13997`), because a compare run is the run that actually produces
  several outcomes. The `--compare` help text changes accordingly.
- Normal runs already stop evaluating after the first non-clean,
  non-skipped outcome (`reviewer_loop_process_platform_output`'s break), so
  they produce at most one outcome of rank 1–3 and the order is satisfied
  without code changes; BR 5 forbids changing when evaluation stops.
- Loop-level escalations (cycle caps, `ledger_persist_failed`, thread-audit
  failures, ownership, `ready_for_review_failed`, expensive-gate cap,
  `local_pass_unavailable`) are applied after platform aggregation exactly as
  today and therefore keep precedence over every platform row. This includes
  `reviewer_loop_cap_exceeded` turning a `waiting_on_reviewer` aggregate into
  `max_cycles_exceeded` at the per-run or lifetime cap (#1757 behavior,
  unchanged).

### D11 — Automatic re-wait and outstanding-request adoption (BR 7, AC-11)

Loop side:

- New `reviewer_loop_no_verdict_rewait_state <history_payload> <head_sha>`
  prints `fresh`, `rewait`, or `untracked`:
  - `untracked` when `PR_REVIEW_LOOP_RUN_ID` is unset (the run id is an
    `auto-…` per-invocation id), the loop head is unknown, or the ledger is
    unavailable;
  - `rewait` when the ledger holds at least one entry with this `run_id`,
    `head_sha` equal to the loop head, `result` `waiting_on_reviewer`, and a
    reason in `REVIEWER_LOOP_NO_VERDICT_REASONS`
    (`reviewer-no-verdict-yet`, `codex-github-review-pending`,
    `codex-github-reaction-without-review`);
  - `fresh` otherwise.
- It runs once per invocation after `loop_head_sha` is read. `rewait` sets the
  global `reviewer_loop_rewait_mode=1`, consulted by the handlers below.
- On a `waiting_on_reviewer` result whose reason is in
  `REVIEWER_LOOP_NO_VERDICT_REASONS`, the loop prints
  `NO_VERDICT_REWAIT=available` (state `fresh`), `used` (state `rewait`), or
  `untracked`.
- Ledger entries carry `run_id`, `head_sha`, `result`, and `reason` today, and
  `waiting_on_reviewer` runs already persist an entry (`_post_review_summary`
  runs for every non-`skipped` result, `:14470-14486`), so the state needs no
  new ledger field.
- The re-wait never counts toward the cycle caps: the per-run and lifetime
  counts are taken only from `needs_fixes`/`needs_rerun` entries
  (`reviewer_loop_history_entries_count`, `:11797-11830`), and Protocol 91
  increments `cycle` only when it dispatches a fixer.

Outstanding-request adoption in re-wait mode (no duplicate request while one
is outstanding). An outstanding request is one posted after the current head
commit's committer time with no verdict yet:

| Platform | Re-wait behavior |
| --- | --- |
| `bugbot` | Phase 2 adopts the newest `BUGBOT_TRIGGER_COMMENT` issue comment created after the head commit time instead of posting (this adoption also applies outside re-wait mode); the #1390 re-trigger is skipped |
| `codex-github` | `--max-retriggers 0` (D5) |
| `greptile` | Reuse the newest trigger comment created after the head commit time that has no bot thumbs-up, regardless of the `max_wait` reuse window |
| `pr-agent` | The trigger reuse window becomes "since the head commit time" |
| `coderabbit` | No conditional `@coderabbitai review` re-trigger when one was posted after the head commit time |
| `claude-code-action` | Companion `--adopt-existing-run`: when a run named for this PR was created after the head commit time (any status), poll it instead of dispatching |
| `copilot` | No change: re-requesting a reviewer with a pending request is a no-op |
| `devin`, `ronda`, `haystack` | No change: they post no request |
| `local-ai-reviewer`, `coderabbit-cli` | No change: the local review runs again (BR 3) |

Runner side (Protocol 91 Step 7, D11 rows of the decision-gate matrix):

| Loop result | Runner action |
| --- | --- |
| `waiting_on_reviewer` + `NO_VERDICT_REWAIT=available` | Re-run Step 7 once, immediately, with the same `PR_REVIEW_LOOP_RUN_ID`; no fixer, no `cycle` increment, no readiness label |
| `waiting_on_reviewer` + `NO_VERDICT_REWAIT=used` | Stop as **Waiting on reviewer**: name `PENDING_REVIEWER`, `PENDING_REVIEW_HEAD_SHA`, the request time, and waited seconds; state that no failure was detected; human action is "re-run the reviewer loop later on the same revision, or investigate the platform if it still has not answered" |
| `waiting_on_reviewer` + `NO_VERDICT_REWAIT=untracked` | Stop as Waiting on reviewer as above, without the automatic re-wait, because the once-per-revision bound cannot be enforced without a stable run id |
| Re-wait run returns any other result | Act on it with its existing Step 7 row |

### D12 — Budget source and latency record (BR 12, AC-12)

Per dispatched platform `n` (the second local pass uses its existing index
`${#platforms[@]} + 1`), the loop records the wait start immediately before
`run_platform_review` and the end immediately after, and prints:

| Key | Value |
| --- | --- |
| `PLATFORM_<n>_OUTCOME_CLASS` | D8 class |
| `PLATFORM_<n>_WAIT_BUDGET_SECONDS` | D7 seconds |
| `PLATFORM_<n>_WAIT_BUDGET_SOURCE` | `override`, `configured`, `default` |
| `PLATFORM_<n>_WAIT_BUDGET_ADJUSTMENT` | `none`, `documentation_branch`, `large_diff` |
| `PLATFORM_<n>_REQUESTED_AT` | the handler's `REVIEW_REQUESTED_AT` when it posted or adopted a request, else the wait start (ISO-8601 UTC) |
| `PLATFORM_<n>_REQUESTED_AT_SOURCE` | `request` or `wait_start` |
| `PLATFORM_<n>_LATENCY_SECONDS` | end minus requested-at, for `verdict_received`, `reviewer_failed`, `existing_handling` |
| `PLATFORM_<n>_WAITED_SECONDS` | end minus requested-at, for `no_verdict_yet` |
| `PLATFORM_<n>_ELAPSED_SECONDS` | end minus requested-at, for `skipped` and `skipped_failure_evidence` |
| `PLATFORM_<n>_VERDICT_REUSED` | `1` for a #1692 replay; no budget, requested-at, or seconds key is printed for it |

Latency is measured to the poll that observed the verdict, so it overstates
the vendor's latency by at most one poll interval; the summary says so once.
Handlers that post or adopt a request print `REVIEW_REQUESTED_AT`: Greptile
and Bugbot (trigger comment `created_at`), PR-Agent and CodeRabbit (their
trigger `created_at` when they posted or reused one), Copilot (time of the
reviewer request), `codex-github-reviewer.sh` (its `TRIGGER_TIME`, printed by
`emit_reviewed_head_if_known` and on the pending exit), and
`claude-code-action-reviewer.sh` (its `DISPATCH_TIME` or the adopted run's
`created_at`).

The summary comment gains a **Reviewer timing** section with one line per
platform (at most 200 characters), for example
`- bugbot: verdict received (clean) — budget 2400s (built-in default); requested 2026-09-23T12:35:16Z; latency 316s`
or `- pr-agent: verdict reused from an earlier run on this revision`. The same
fields are added to each `platform_results[]` ledger record as additive keys
(`outcome_class`, `wait_budget_seconds`, `wait_budget_source`,
`wait_budget_adjustment`, `requested_at`, `requested_at_source`,
`elapsed_seconds`, `elapsed_kind` = `latency`/`waited`/`elapsed`, `reused`),
schema string unchanged. The ledger copy matters because the summary comment
is rewritten in place every run; only the ledger keeps the per-run latency
history that tuning (Use Case 5) reads.

On a `waiting_on_reviewer` aggregate with a reason in
`REVIEWER_LOOP_NO_VERDICT_REASONS`, the loop also prints
`PENDING_REVIEW_REQUESTED_AT`, `PENDING_REVIEW_WAITED_SECONDS`, and
`NO_FAILURE_DETECTED=1`, and the summary result line for
`reviewer-no-verdict-yet` reads
`waiting_on_reviewer (reviewer-no-verdict-yet) — <platform> has not returned a verdict for <head> after <seconds>s (budget <budget>s, <source>); no reviewer failure was detected`.
The two Codex reasons keep their existing result line.

### D13 — `--max-wait` validation (BR 10, AC-5)

The spec says an invalid one-run override is refused "as today", but the
script has no such check today (V6): `--max-wait 0` currently posts triggers
and then times out immediately. The plan adds the check: right after argument
parsing and before any `gh` call, a `--max-wait` value that does not match
`^[1-9][0-9]{0,5}$` prints
`--max-wait must be a positive whole number of seconds (got '<value>').` plus
the usage text to stderr and exits 64, the exit code the script already uses
for invalid arguments.

### D14 — Poll interval per platform

`reviewer_poll_interval_resolve <platform> <budget>`: `--poll-interval` when
given; else `codex_github_default_poll_interval` for `codex-github`
(`CODEX_GITHUB_POLL_INTERVAL`, default 60); else 30 on `spec/*` and
`implementation-plan/*` branches; else 120. The result is clamped below the
budget (`max(1, floor(budget / 2))` when it is not smaller). Before this change
the Codex poll default applied to every platform whenever Codex was
configured; afterwards it applies to Codex only.

---

## Verification Log

All commands were run in the plan worktree at repository revision
`13bf4c7f` (`git rev-parse --short HEAD`), the merge of spec PR #1869, on
2026-10-01.

| ID | Check | Command / query | Result |
| --- | --- | --- | --- |
| V1 | Supported platform count | `sed -n '/^run_platform_review()/,/^}/p' scripts/development-workflow/pr-review-loop.sh \| grep -cE '^    [a-z-]+\)$'` | 12 (`greptile`, `devin`, `coderabbit`, `coderabbit-cli`, `local-ai-reviewer`, `pr-agent`, `codex-github`, `claude-code-action`, `copilot`, `haystack`, `bugbot`, `ronda`) |
| V2 | Budget-expiry and unavailable emit sites in the loop | `grep -nE 'print_kv REASON (timeout\|no_check_run\|no_review\|unavailable)$' scripts/development-workflow/pr-review-loop.sh` | lines 2133, 2625, 2634, 2703, 2812, 3071, 4240, 4320, 4332, 5226, 5238, 5803, 7833, 7847; each is classified in the D8 table (2634 and 2703 are kept failure paths) |
| V3 | Code that names a non-reviewing platform for documentation branches | `grep -n 'spec/\*\|implementation-plan/\*' scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/*-reviewer.sh scripts/development-workflow/local-*.sh` | Devin statement at `pr-review-loop.sh:750-751` and comment `:13037-13039`; every other hit names no non-reviewing platform: the `--help` poll-interval sentence (`:754-755`), the CodeRabbit no-trigger-timeout comment citing the 180 s doc-branch budget (`:6516`), the large-diff comment (`:13072-13073`), the doc-branch budget blocks (`:13045`, `:13089`), compare-metrics branch typing (`:8497-8498`), and `local-ai-reviewer.sh:872` (comment) and `:875-876` (selects `spec`/`plan` checklists, i.e. it does review them) |
| V4 | Branch filters in reviewer workflows | Read `.github/workflows/pr-agent.yml` (`on: pull_request` with no `branches` filter; same-repository condition only) and `.github/workflows/claude-code-review.yml` (`workflow_dispatch` only) | No documentation-branch exclusion |
| V5 | Integration guides naming documentation-branch non-review | `grep -n "spec/\|implementation-plan/\|doc-branch\|DOC_MAX_WAIT\|documentation branch" docs/workflow/development-workflow/integrations/*.md` | Only `local-ai-reviewer.md` (checklist selection for those branches) among reviewer guides; no guide states a platform skips them |
| V6 | Existing `--max-wait` validation | `grep -n 'max_wait" =~\|--max-wait value\|max-wait must' scripts/development-workflow/pr-review-loop.sh` | Only `:6559` (`coderabbit_no_trigger_timeout_default` input check) and `:13081` (`LARGE_DIFF_MAX_WAIT`); the `--max-wait` parser at `:12606-12611` stores the value unchecked |
| V7 | Bugbot trigger-to-completion latency sample (PR #1787) | `gh api repos/lhpaul/ai-dev-framework-template/commits/<sha>/check-runs --jq '.check_runs[] \| select(.name=="Cursor Bugbot") \| [.status,.conclusion,.started_at,.completed_at]'` for heads `909ab08a`, `e9ba0f4b`, `62dc8eb5`, `6e62224e`, `fa2fa9c9`, paired with the `bugbot run` comment times from `gh api repos/lhpaul/ai-dev-framework-template/issues/1787/comments` | triggers 12:35:16, 12:43:30, 12:50:07, 12:56:10, 13:07:28 → completions 12:40:32, 12:46:44, 12:53:06, 13:00:44, 13:10:37 (2026-09-23 UTC): 5 min 16 s, 3 min 14 s, 2 min 59 s, 4 min 34 s, 3 min 9 s |
| V8 | Exit paths and label calls | `grep -nE '^\s*exit [0-9]+\|^\s*exit "' scripts/development-workflow/pr-review-loop.sh` (main section) and `grep -n sync_reviewer_failed_label scripts/development-workflow/pr-review-loop.sh` | Pre-loop exits at `:12520-12829` and the repository-root / head-branch resolution failure exit at `:13032` never call the label sync; label sync at `:12936` (release guard), `:13962` (not configured), `:14515` (post-loop); all platform-evaluating runs reach `:14515` |
| V9 | `local-ai-reviewer.sh` timeout path | `grep -n "timeout\|TIMEOUT" scripts/development-workflow/local-ai-reviewer.sh` | `run_with_timeout` returns 124 (GNU `timeout` or the fallback kill path); the caller treats 124/137 as timeout at `:1321-1324` and checks it before any output probe |
| V10 | Codex duplicate-trigger guard | `grep -n "skipping duplicate post\|MAX_RETRIGGERS=0" scripts/development-workflow/codex-github-reviewer.sh` | `:2077` skips a duplicate trigger for a pending current-head trigger; `:2482` skips the async-arrival trigger when `MAX_RETRIGGERS=0` |
| V11 | Availability reasons emitted today | `grep -n "bugbot-usage-limit\|codex-github-usage-limit\|codex-github-account-not-connected\|rate_limit_max_retries\|quota_exhausted\|REASON=rate_limited\|REASON rate_limited" scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/codex-github-reviewer.sh scripts/development-workflow/local-ai-reviewer.sh scripts/development-workflow/coderabbit-cli-reviewer.sh` | Each reason in `REVIEWER_LOOP_AVAILABILITY_REASONS` (D8) is emitted by at least one of those files |
| V12 | Consumers of `reviewer_failed_label_required_for_result` (Rule 5) | `grep -rn "reviewer_failed_label_required_for_result" scripts docs .claude .cursor .codex .agents` | Code consumers `pr-review-loop.sh:1342`, `:9120`, `:9840`, `:14512`; tests in `test-pr-review-loop.sh`; prose in `codex-github.md:51`, Protocol 93 `:293`, and a #1649 smoke runbook; remaining hits are merged historical spec/plan documents under `docs/specs/developments/` (not consumers) |
| V13 | Consumers of `waiting_on_reviewer` and of ledger `platform_results` (Rule 5) | `grep -rln "waiting_on_reviewer" scripts docs/workflow .github .claude .cursor .codex .agents` and `grep -rln "platform_results" scripts` | `pr-review-loop.sh`, `codex-github-reviewer.sh`, `codex-github-evidence-lib.sh`, Protocol 91, Protocol 93, `codex-github.md`; ledger readers `apply-readiness-labels.sh`, `item-completion-self-check.sh`, `reviewer-effectiveness-report.sh` |
| V14 | Mirror agent, skill, and command surfaces that restate loop results | `grep -n -i "timeout\|waiting_on\|exit code 4\|reviewer-failed\|max-wait" .claude/agents/automated-reviewer-loop.md .claude/agents/item-orchestrator.md .claude/commands/run-reviewer-loop.md .cursor/agents/automated-reviewer-loop.md .cursor/agents/item-orchestrator.md .cursor/commands/run-reviewer-loop.md .codex/skills/workflow-item-orchestrator/SKILL.md .codex/skills/workflow-reviewer-loop/SKILL.md .agents/skills/*/SKILL.md .cursor/rules/workflow.mdc` | No surface restates timeout, waiting, label, or wait-budget semantics; they delegate result interpretation to Protocol 91/93 (the command returns no matches; a separate `grep -n "timed out" .claude/commands/run-reviewer-loop.md` finds one line mentioning "a previous run timed out" as pre-flight context only) |
| V15 | Config tools with an allowed-key list for `review` | `grep -c "ALLOWED\|allowed_keys\|KNOWN_" scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/validate-workflow-config.sh` | 0 and 0 — a new `review.wait_budgets` key is not rejected |
| V16 | Second local pass gate | Read `reviewer_loop_second_local_pass_gate_result` (`:9654-9664`) and `reviewer_loop_local_pass_required` (`:9346-9373`) | A `waiting_on_reviewer` second pass currently maps to `escalate`/`local_pass_unavailable`; a non-clean prior local outcome maps to `prior_findings` |
| V17 | Claude companion consumers | `grep -rln "claude-code-action-reviewer.sh" scripts docs/workflow .github .claude .cursor .codex .agents` | Only `pr-review-loop.sh` invokes it; other hits are comments (`claude-code-action-reviewer.sh` itself, `apply-readiness-labels.sh`, `.github/workflows/claude-code-review.yml`), its test, its guide, and a historical anecdote in Protocol 03 (`:591`) |
| V18 | Open same-surface PRs | `gh pr list --state open --json number --jq length` at 2026-10-01T02:21:56Z | 0 |
| V19 | Consumers of `local-ai-reviewer.sh` exit codes (Rule 5) | `grep -rln "local-ai-reviewer.sh" scripts docs/workflow .github .claude .cursor .codex .agents \| grep -v '/tests/'` and `grep -n "local-ai-reviewer.sh" scripts/development-workflow/workflow-lib.sh scripts/development-workflow/apply-readiness-labels.sh scripts/development-workflow/local-http-reviewer.sh scripts/development-workflow/local-codex-reviewer.sh` | Invokers: `pr-review-loop.sh` (`run_local_ai_reviewer_review`, exit arms `:4840-4911`), `local-http-reviewer.sh:60` and `local-codex-reviewer.sh:42` (`exec`); `workflow-lib.sh:4388` and `apply-readiness-labels.sh:843` are comments; the two integration guides are prose |
| V20 | Readiness-gate outcome arms for ledger `platform_results[].result` | `grep -n '_adapter_refusal_reason="reviewer-' scripts/development-workflow/apply-readiness-labels.sh` (the `case "$outcome"` arms are the hits at `:759` and `:760`) and read `reviewer_loop_normalize_platform_outcome` (`pr-review-loop.sh:8982-8999`) | `:759` maps `not_yet_run\|unknown` to `reviewer-check-absent`; `:760` maps every other non-`clean` value to `reviewer-evidence-unreadable`; the normalizer maps `waiting_on_reviewer` to `unknown` and `escalate` to `unavailable` |
| V21 | In-loop readers of the normalized ledger outcome (Rule 5) | `grep -n '\.result //' scripts/development-workflow/pr-review-loop.sh`, then `grep -n 'reviewer_loop_local_latest_verdict\|reviewer_loop_platform_clean_for_head' scripts/development-workflow/pr-review-loop.sh` for the callers | Platform-record readers: `:9210` in `reviewer_loop_local_latest_verdict` (callers `reviewer_loop_retain_local_evidence_for_current_run` `:9169`, `reviewer_loop_local_pass_required` `:9357`, `reviewer_loop_missed_finding_records` `:10363`), `:9414` in `reviewer_loop_platform_clean_for_head` (caller `:9476`, #1692 stage skip), and `:10374` (missed-finding walk); the other hits (`:1708`, `:8710`, `:11867-11877`, `:14112`) read entry-level or gate fields, not `platform_results[].result`. Cross-script readers are V13's. Writers: `grep -rn 'reviewer_loop_normalize_platform_outcome\|reviewer_loop_platform_result_record_json' scripts \| grep -v '/tests/'` finds the normalizer's only caller in `reviewer_loop_platform_result_record_json` (`:9008`) and that function's three callers `:9182`, `:9894`, `:10266`, all in `pr-review-loop.sh` |
| V22 | Documentation surfaces that restate reviewer-loop timeout, wait, or label semantics | `grep -rln -i 'times out\|REASON=timeout\|~20 min\|(20 min)\|1200 s\|reviewer-failed' docs/workflow docs/project REVIEW.md AGENTS.md .claude .cursor .codex .agents` | Every hit is in Documentation Updates except: `retro-metrics.md` (historical batch records), `provider-contingency-runner-failover.md` and Protocol 90 (agent stream timeouts, not reviewer waits), and `github-projects.md`, `AGENTS.md`, `.claude/agents/orchestrator.md`, `.cursor/agents/orchestrator.md` (list `reviewer-failed` as an operational label only) |

### Factual claim evidence

**Rule 5 — consumer outcomes after the change.**

`reviewer_failed_label_required_for_result` (V12):

| Consumer | Path | Outcome after the change |
| --- | --- | --- |
| `expensive_gate_peer_evidence_acceptable` (`:1342`) | expensive-gate peer check, reached only for `skipped` peers whose reason is in `EXPENSIVE_GATE_ACCEPTED_SKIP_REASONS` (`not_configured`, `explicit-skip`, `release_pr`, `unsupported-platform`) | Unchanged: a kept no-verdict skip has a reason outside that list (`no_check_run`, `no_review`, `timeout`) and is still not acceptable, so the gate still defers |
| `reviewer_loop_recompute_current_round_aggregates` (`:9120`) | recompute after a local-reviewer record replacement | A CodeRabbit CLI `skipped`/`timeout` peer no longer sets `reviewer_failed_required` |
| `reviewer_loop_process_platform_output` (`:9840`) | every dispatched or replayed platform | Same as above; `waiting_on_reviewer` platforms never set it |
| post-loop aggregate (`:14512`, moved into `reviewer_loop_reconcile_reviewer_failed_label`) | final label decision | Loop-level escalations still require the label; a `waiting_on_reviewer` aggregate does not |

`RESULT=waiting_on_reviewer` from the new No verdict yet paths (V13):

| Consumer | Path | Outcome |
| --- | --- | --- |
| `reviewer_loop_process_platform_output` waiting arm (`:9948-9962`) | platform loop | Aggregate becomes `waiting_on_reviewer`, the loop stops evaluating further platforms (normal mode), exit 4 |
| `reviewer_loop_cap_exceeded` (`:11986-11996`) | post-loop cap check | At the per-run or lifetime cap the aggregate still becomes `escalate`/`max_cycles_exceeded` or `max_total_cycles_exceeded` (loop-level escalation precedence, D10) |
| `normalize_platform_verdict` (`:8358-8385`) | compare-mode verdict tokens | `waiting`; the renamed `bugbot-run-timed-out` is added to the `timed out` token list |
| `reviewer_loop_second_local_pass_gate_result` (`:9654-9664`) | second local pass before the ready gate | New arm: `waiting_on_reviewer` → `waiting_on_reviewer`/`reviewer-no-verdict-yet` (instead of `escalate`/`local_pass_unavailable`), and `local_second_pass_failed_head_record` is not set for it, so the next run on the same head is not refused as `failed_for_head` |
| `reviewer_loop_normalize_platform_outcome` (`:8982-8999`) | ledger `platform_results[].result` | New normalized value `no_verdict_yet` for `waiting_on_reviewer` and for kept skips; it gains an optional third argument, the platform's `NO_VERDICT_YET` flag, so a kept skip is recognized from the flag rather than from its reason. Its only caller is `reviewer_loop_platform_result_record_json` (`:9008`), which gains a matching optional fourth argument (before the D12 timing arguments) and forwards it; of that function's three callers (V21), only `reviewer_loop_process_platform_output` (`:9894`) passes it, read from the platform output's `NO_VERDICT_YET` key — the retained-local-evidence call (`:9182`, `clean`/`skipped` local records) and the late-review-threads call (`:10266`, `needs_fixes`) never carry a kept skip and pass none. Its in-loop readers are the next four rows and the local-evidence row (V21) |
| `reviewer_loop_local_pass_required` (`:9346-9373`) | #1656 second-pass decision | `no_verdict_yet` maps to `no_evidence` (a fresh local pass runs), not `prior_findings` |
| `reviewer_loop_retain_local_evidence_for_current_run` (`:9158-9183`, V21) | platform-filtered ready-phase run reusing local evidence | Unchanged: it retains only `clean` or `skipped`; `no_verdict_yet` falls to its `*)` arm and is not retained, as the `unavailable` value of a local `escalate`/`timeout` record was not retained before |
| `reviewer_loop_platform_clean_for_head` (`:9399-9446`, V21) | #1692 stage-skip replay decision | `no_verdict_yet` returns `not_clean` (previously `unknown` → `no_evidence` for a waiting record); the caller (`:9476-9477`) replays only on `clean_current`, so both values dispatch the platform and nothing changes |
| `reviewer_loop_missed_finding_records` walk (`:10372-10383`, V21) | missed-finding telemetry over the current round's records | Unchanged: it considers only `needs_fixes` records |
| `reviewer_loop_local_evidence_state` and its label (`:10017-10067`) | missed-finding telemetry | New state `no_verdict_yet`, label "No verdict yet", classification `not_a_miss` |
| `apply-readiness-labels.sh` `coderabbit_cli_local_ai_ledger_verdict` (`:757-761`, V20) | readiness label gate | Requires the Layer 3 edit: without it, the new `no_verdict_yet` value falls into the `*)` arm and refuses as `reviewer-evidence-unreadable`; with `no_verdict_yet` added to the `not_yet_run\|unknown` arm it refuses as `reviewer-check-absent`. Before this change a `waiting_on_reviewer` record normalized to `unknown` (also `reviewer-check-absent`), a local-reviewer `escalate`/`timeout` record normalized to `unavailable` (`reviewer-evidence-unreadable`), and a CodeRabbit CLI `skipped`/`timeout` record normalized to `skipped` (`reviewer-evidence-unreadable`). Never a pass |
| `item-completion-self-check.sh` (`:781-787`) | completion self-check | Unchanged: accepts only `clean` |
| `reviewer-effectiveness-report.sh` (`:129-177`) | effectiveness report | Unchanged: counts only `needs_fixes` and Codex presence |
| `_post_review_summary` result line (`:13477-13479`) | summary comment | New `reviewer-no-verdict-yet` wording (D12); Codex wording unchanged |
| Protocol 91 Check 0.5 and `.github/workflows/pr-policy.yml` (`:250-253`) | readiness summary checks | Unchanged: the result line is not `clean`/`skipped`, so readiness is refused |
| Protocol 91 Step 7 result table | runner | New D11 rows |

Global `max_wait` → per-platform budget: the main-level consumers are the
documentation-branch block (`:13043-13052`), the Codex block
(`:13054-13061`), the large-diff block (`:13087-13112`), the platform loop
dispatch (`:13406`), and the second local pass dispatch (`:9758`); all are
rewritten to call `reviewer_wait_budget_resolve` and
`reviewer_poll_interval_resolve` per platform. Handler functions receive the
budget as their existing fourth argument and need no signature change.

`local-ai-reviewer.sh` exit 4 (new): consumers (V19) are the loop handler
(new arm; today its `*)` arm would map an unknown exit 4 to `skipped`
with the companion's `REASON`, defaulting to `disabled_by_config`) and the exec wrappers `local-codex-reviewer.sh`
and `local-http-reviewer.sh`, which pass the exit code through unchanged to
their standalone callers; the companion's usage text and
`local-ai-reviewer.md` document exit 4.

`claude-code-action-reviewer.sh` exit 4 (new): the only invoker is the loop
handler (V17).

**Rule 6 — scoped conditional obligations.**

| Obligation | Governed scope | Discharge point |
| --- | --- | --- |
| Documentation-branch shortening applies (D7) | platforms in D1, source `default`, branches `spec/*` and `implementation-plan/*` | `reviewer_wait_budget_resolve`; tests T1.4–T1.6 |
| Large-diff lengthening applies (D7) | non-documentation branches, no `--max-wait`, changed files above threshold, value below `LARGE_DIFF_MAX_WAIT` | `reviewer_wait_budget_resolve`; test T1.7 |
| Re-wait mode suppresses re-requests (D11) | invocations whose `reviewer_loop_no_verdict_rewait_state` is `rewait`; the six request-posting handlers in the D11 table | each handler's request step; tests T4.3–T4.6 |
| Bugbot #1390 re-trigger fires (D3) | fresh (non-re-wait) Bugbot runs whose latest current-head check run is not completed at the re-trigger point | `run_bugbot_review`; tests T2.11–T2.12 |
| Runner re-waits (D11) | Step 7 results with `NO_VERDICT_REWAIT=available`, once per head per `PR_REVIEW_LOOP_RUN_ID` | Protocol 91 Step 7 table; tests T4.1–T4.2 and smoke Step 6 |
| Label required (D9) | each invocation that reaches the post-loop path; per-platform failure evidence or a loop-level escalation in that invocation | `reviewer_loop_reconcile_reviewer_failed_label`; tests T3.1–T3.6 |

**Rule 1** does not fire: no new design matches vendor free text. D4
deliberately does not inspect a stopped reviewer's partial output; the Bugbot
and Claude Code Action changes key on GitHub API enumerated fields
(check-run and workflow-run `status`/`conclusion`), not on prose; adoption
matches comments whose bodies this loop itself posts.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved artifact and implementation base | `develop` at `13bf4c7f` (spec PR #1869 merged) | Parent handoff; `git log -1 --format=%H origin/develop` | 2026-10-01T02:21:56Z, `13bf4c7f` | Current invocation item list `[1789]`; open PRs touching `pr-review-loop.sh`, Protocol 91/93, or integration guides: none (V18 — no open PRs at all) | `Verified` |
| Artifact owner / repository mode | `single_repo`; this repository owns the plan | `.ai-dev-workflow.yaml` (no `mode` key) and parent handoff | 2026-10-01T02:21:56Z, `13bf4c7f` | Same as above | `Verified` |
| Configured reviewers the defaults must serve | `review.on_draft.github: [pr-agent]`, `review.on_ready.github: [local-ai-reviewer]`; Bugbot and Codex GitHub not configured here but supported | `.ai-dev-workflow.yaml` | 2026-10-01T02:21:56Z, `13bf4c7f` | Same as above | `Verified` |
| Reviewer-loop default wait values before this change | 1200 s global; 1800 s when Codex GitHub configured; 180 s on documentation branches; 2400 s large-diff | `pr-review-loop.sh:12532`, `:8778-8785`, `:8759-8766`, `:13076` | 2026-10-01T02:21:56Z, `13bf4c7f` | Same as above | `Verified` |

---

## Layer-by-Layer Changes

### Layer 1 — Configuration reader (`scripts/development-workflow/workflow-lib.sh`)

- [ ] Add `workflow_config_review_wait_budget <platform> [config_file]`: an
  awk reader that finds the top-level `review:` section, then its
  `wait_budgets:` child (any indentation deeper than `review:`'s children),
  then an exact `<platform>:` key one level deeper, and prints the trimmed raw
  value (quotes and trailing `# comment` removed), or nothing. It stops the
  `wait_budgets` scope at the first line indented at or above `wait_budgets:`.
  It prints the literal `__flow__` when the `wait_budgets:` line itself
  carries a non-comment value.
- [ ] Add `workflow_config_review_wait_budget_keys [config_file]` printing
  every key under `wait_budgets:` (one per line) for the unsupported-key
  warning (D6).

### Layer 2 — Reviewer loop (`scripts/development-workflow/pr-review-loop.sh`)

Functions are added before the harness return point (`:12516`) so the test
harness can call them.

- [ ] Budget and poll resolution (D1, D2, D6, D7, D14):
  `reviewer_platform_reviews_documentation_branches <platform>` (false only
  for `devin`), `reviewer_wait_budget_builtin_default <platform>`,
  `reviewer_wait_budget_configured <platform>` (D6 validation and warnings,
  `CODEX_GITHUB_MAX_WAIT` first for Codex), `reviewer_wait_budget_resolve`,
  `reviewer_poll_interval_resolve`. Keep `doc_branch_default_max_wait`,
  `codex_github_default_max_wait`, and `codex_github_default_poll_interval`
  as the value sources they already are.
- [ ] Main flow: add D13 validation after argument parsing; replace the global
  `max_wait`/`poll_interval` blocks (`:13037-13112`) with
  `max_wait_override` (set only by `--max-wait`) plus the large-diff fetch
  kept under today's conditions; print `PLATFORM_WAIT_BUDGETS=<platform>:<seconds>:<source>[:<adjustment>],…`
  once before the loop; dispatch each platform and the second local pass with
  its own resolved budget and poll interval.
- [ ] Outcome helpers (D8): `print_no_verdict_yet`,
  `reviewer_loop_platform_outcome_class`, `REVIEWER_LOOP_AVAILABILITY_REASONS`,
  `REVIEWER_LOOP_NO_VERDICT_REASONS`.
- [ ] Handler changes exactly as the D8 binding table and the D11 adoption
  table say, including: Greptile, Devin, CodeRabbit, Copilot, Ronda, Bugbot
  budget-expiry paths → `print_no_verdict_yet`; Devin, CodeRabbit, PR-Agent,
  and the loop's CodeRabbit CLI skip arm add `NO_VERDICT_YET=1` and the
  kept-skip `DISPLAY_RESULT` on their expired-wait skips; Haystack's exit-2
  arm → `print_no_verdict_yet` with the companion reason as detail;
  `run_local_ai_reviewer_review` and `run_claude_code_action_review` gain an
  exit-4 arm; Claude's exit-2 arm reason becomes
  `claude_code_action_run_failed`; Bugbot's `timed_out` conclusion reason
  becomes `bugbot-run-timed-out`; Bugbot's budget bounds both attempts with
  the D3 re-trigger point; request-posting handlers print
  `REVIEW_REQUESTED_AT` (D12).
- [ ] `reviewer_failed_label_required_for_result` (D9) and new
  `reviewer_loop_reconcile_reviewer_failed_label`, called from the post-loop
  path.
- [ ] `reviewer_loop_precedence_select` (D10) used by the compare-mode
  aggregate restore; update the `--compare` help text.
- [ ] `reviewer_loop_no_verdict_rewait_state`, `reviewer_loop_rewait_mode`, the
  `NO_VERDICT_REWAIT` / `PENDING_REVIEW_*` / `NO_FAILURE_DETECTED` keys, and
  `--max-retriggers 0` for Codex in re-wait mode (D5, D11).
- [ ] Timing (D12): wait-start/end capture around both dispatch sites,
  `reviewer_loop_record_platform_timing`, a `platform_timing_records` array
  (cleared with the other per-run arrays and filtered by
  `reviewer_loop_replace_current_round_platform_record` so a second local pass
  replaces the first pass's timing), `reviewer_loop_timing_summary_section`,
  extra optional arguments to `reviewer_loop_platform_result_record_json`, and
  the replay marker on the #1692 path.
- [ ] Consumers from the Rule 5 tables: second-pass gate arm and failed-head
  record exclusion, `reviewer_loop_normalize_platform_outcome` and the
  `NO_VERDICT_YET` pass-through from `reviewer_loop_process_platform_output`
  via `reviewer_loop_platform_result_record_json` (normalizer Rule 5 row),
  `reviewer_loop_local_pass_required`, local evidence state and label,
  `normalize_platform_verdict` token list, `_post_review_summary` result line.
- [ ] `--help` text: replace the "Branch-type-aware default timeout" block
  with a "Per-platform wait budgets" block that points to Protocol 93 for the
  values, and document the new output keys and `REASON=reviewer-no-verdict-yet`
  in the outputs list.

### Layer 3 — Companion scripts and the readiness helper

- [ ] `scripts/development-workflow/local-ai-reviewer.sh`: D4 exit 4 on
  124/137; usage text lists exit 4.
- [ ] `scripts/development-workflow/claude-code-action-reviewer.sh`: exit 4
  when no run completed within the budget; `--adopt-existing-run` flag (D11);
  print `REVIEW_REQUESTED_AT`; exit-code header comment updated.
- [ ] `scripts/development-workflow/codex-github-reviewer.sh`: print
  `REVIEW_REQUESTED_AT=$TRIGGER_TIME` from `emit_reviewed_head_if_known` and
  on the pending exit when a trigger time is known; no verdict-logic change.
- [ ] `scripts/development-workflow/apply-readiness-labels.sh`
  (`coderabbit_cli_local_ai_ledger_verdict`): add `no_verdict_yet` to the
  `not_yet_run|unknown` arm so it refuses as `reviewer-check-absent` (Rule 5
  consumer table, V20); covered by T2.10.

### Layer 4 — Infrastructure / configuration

- [ ] `.ai-dev-workflow.yaml`: add a commented `review.wait_budgets` example
  next to the `max_cycles` comments, outside the template-owned block, with a
  pointer to Protocol 93 for the built-in defaults.

### Layer 5 — Protocols and documentation

Listed under Documentation Updates.

### Database, Backend/API, Frontend/UI

Not applicable — this repository's change is workflow tooling and
documentation only.

---

## Testing Strategy

**Test types**: Bash unit and composed-function tests in the existing
self-contained harnesses (mock `gh`, `HARNESS_MODE=1` sourcing, `run_test` /
`run_contains`), plus full-script subprocess runs for argument validation;
manual smoke runbook for live platforms.

**Harness**: `scripts/development-workflow/tests/test-pr-review-loop.sh`, new
area `=== Area 1789: reviewer no verdict yet ===` (runnable alone with
`--area 1789`); `test-local-ai-reviewer.sh` for D4;
`test-claude-code-action-reviewer.sh` for the companion exit 4 and adoption.
All wait-path tests use budgets of 1–2 s and poll 1 s so the area adds
seconds, not minutes, to the suite (the #1562 measurement shows Area 13
already dominates the run time).

**Coverage intent** (indicative; an implementer may substitute a
coverage-equivalent set): the projected cases cover each decision's branches
once — every D8 row, every D7 source and adjustment, each D11 state, each
D9 exit path, each D10 rank — rather than every platform × branch × source
combination, because the handlers share `print_no_verdict_yet` and the
resolver is a single function.

| ID | Scenario | AC |
| --- | --- | --- |
| T1.1 | Resolver: no override, no config → D2 value and source `default` for each of the twelve platforms | AC-6 |
| T1.2 | Resolver: valid `review.wait_budgets.bugbot` → `configured`; `--max-wait` override wins over it for every platform | AC-5 |
| T1.3 | Resolver: invalid configured values (`abc`, `0`, `-5`, `1.5`, empty, seven digits) → default plus the D6 warning; unsupported key and flow mapping warnings | AC-5 |
| T1.4 | Resolver on `implementation-plan/x`: Devin gets the documentation value with adjustment `documentation_branch`; Bugbot and `local-ai-reviewer` keep their D2 values | AC-4 |
| T1.5 | Resolver on `spec/x` with a configured Devin value: configured value, no shortening | AC-4, AC-5 |
| T1.6 | Resolver: `PR_REVIEW_LOOP_DOC_MAX_WAIT` override and invalid value keep today's behavior for Devin only | AC-4 |
| T1.7 | Resolver: large diff lengthens a 1200 default to 2400, leaves Bugbot's 2400 and an override untouched, never shortens | AC-5 |
| T1.8 | Full-script runs with `--max-wait 0`, `abc`, `-5`, `1.5` exit 64 with the D13 message and the mock `gh` log is empty | AC-5 |
| T1.9 | Poll resolver: explicit, Codex default, documentation 30, default 120, clamp below budget | AC-4 |
| T1.10 | Config reader edge cases (parser-risk addendum) | AC-5 |
| T2.1 | Each of the nine handlers with a No verdict yet path in D8 returns `waiting_on_reviewer`/`reviewer-no-verdict-yet` with its detail when its mock never answers; `reviewer_loop_process_platform_output` sets the aggregate to waiting, does not set `reviewer_failed_required`, and breaks | AC-1 |
| T2.2 | Bugbot on `implementation-plan/x`, no override, mock check run completes `success` at elapsed counter 1500 with budget per D2 and poll 30 (time-scaled through a mocked `_interruptible_sleep` that only advances the counter) → `clean`, no re-trigger posted | AC-3 |
| T2.3 | Each D8 failure-evidence path (one per platform) still returns `escalate` and requires the label; Bugbot `timed_out` conclusion returns `bugbot-run-timed-out` | AC-2 |
| T2.4 | Kept skips (Devin `no_check_run`, CodeRabbit `no_review`, CodeRabbit CLI `timeout`, PR-Agent `no_review`): `skipped`, `NO_VERDICT_YET=1`, class `no_verdict_yet`, aggregate stays clean, label not required | AC-8 |
| T2.5 | Older-revision evidence only (Bugbot completed check on another SHA; Copilot review on another `commit_id`) → No verdict yet, never clean or failed | AC-10 |
| T2.6 | Availability reasons in `REVIEWER_LOOP_AVAILABILITY_REASONS` keep result, reason, exit code, and label decision; Bugbot "disabled" self-report and Copilot request failure keep their existing failure handling | AC-13 |
| T2.7 | `local-ai-reviewer.sh` with a command that sleeps past `--timeout`: exit 4 and the D4 keys; command exiting 1 before the budget, and unreadable output, keep `escalate` | AC-1, AC-2 |
| T2.8 | `claude-code-action-reviewer.sh`: run never completes → exit 4; completed `failure` → exit 2; loop maps 4 and 2 per D8 | AC-1, AC-2 |
| T2.9 | Second local pass returning waiting → aggregate waiting, no `failed_for_head` record | AC-1 |
| T2.10 | Ledger normalization `no_verdict_yet` for a waiting record and for a kept skip recorded through `reviewer_loop_process_platform_output` (the `platform_result_records` entry, not only the normalizer called directly); `apply-readiness-labels.sh` refuses it as `reviewer-check-absent` (extend `test-apply-readiness-labels.sh`) | AC-1 |
| T2.11 | Bugbot fresh run: no completed run by the D3 re-trigger point → exactly one re-trigger, total wait bounded by the budget | AC-3, AC-6 |
| T2.12 | Bugbot re-wait mode: adopts the existing trigger, posts no comment | AC-11 |
| T3.1 | Reconcile: PR carries `reviewer-failed`, run re-reviews and is clean → `--remove-label` issued | AC-7 |
| T3.2 | Reconcile: same, but every platform replayed from a clean ledger (#1692) → `--remove-label` issued | AC-7 |
| T3.3 | Reconcile: needs-fixes or waiting run with no failure evidence → label removed / not added | AC-8 |
| T3.4 | Reconcile: mixed compare run, one failed platform plus one clean, and a needs-fixes run with a `skipped`/`unavailable` peer → label added | AC-8 |
| T3.5 | Add/remove failure prints the WARN and does not change the exit code | AC-8 |
| T3.6 | Source-order check: the post-loop path calls the reconcile function once after the persistence step; pre-loop refusal exits do not | AC-7, AC-13 |
| T3.7 | Precedence function: failed + waiting → escalate; findings + waiting → needs_fixes; waiting + clean → waiting; kept skip + clean → clean; tie → earliest platform | AC-9 |
| T3.8 | Compare-mode aggregate uses the precedence function | AC-9 |
| T4.1 | Re-wait state: no prior entry → `fresh` and `NO_VERDICT_REWAIT=available`; prior waiting entry same run and head → `rewait` and `used`; other head or other run → `fresh`; unset run id or unavailable ledger → `untracked` | AC-11 |
| T4.2 | A re-wait entry adds nothing to the cycle counts (`reviewer_loop_history_entries_count` unchanged) | AC-11 |
| T4.3 | Codex in re-wait mode receives `--max-retriggers 0` | AC-11 |
| T4.4 | Greptile and PR-Agent in re-wait mode reuse an older trigger; CodeRabbit posts no conditional re-trigger | AC-11 |
| T4.5 | Claude companion `--adopt-existing-run` polls the existing run and does not dispatch | AC-11 |
| T4.6 | Bugbot outside re-wait mode adopts a trigger posted after the head commit instead of posting | AC-11 |
| T5.1 | Timing keys for a verdict, a No verdict yet, a skip, a failure, and a replay; `REQUESTED_AT_SOURCE` `request` vs `wait_start` | AC-12 |
| T5.2 | Summary "Reviewer timing" section lines and the `reviewer-no-verdict-yet` result line; reused marked reused | AC-12 |
| T5.3 | Ledger `platform_results[]` additive fields present; existing readers (`reviewer_loop_platform_clean_for_head`, #1692) still pass | AC-12 |
| T5.4 | Waiting aggregate prints `PENDING_REVIEWER`, `PENDING_REVIEW_HEAD_SHA`, `PENDING_REVIEW_REQUESTED_AT`, `PENDING_REVIEW_WAITED_SECONDS`, `NO_FAILURE_DETECTED=1` | AC-1, AC-11 |
| T6.1 | Documentation assertions: Protocol 93 contains the canonical section headings and the D2 table; Protocol 91's Step 7 table contains the three D11 rows; each guide in Documentation Updates names `reviewer-no-verdict-yet` or the kept skip | AC-14 |

Existing tests whose expectations change and must be updated in the same
commit as the behavior: Area 12 rows `reviewer_failed_escalate_timeout`
(input becomes a failure-only reason) and the `skipped timeout` expectation;
Area 0b Codex-defaults rows (`codex_github_defaults_should_apply` no longer
drives a global budget); Area 16 Bugbot timeout and unavailable rows; the
Copilot (Area 8), Haystack (Area 9), Devin, Ronda, Greptile, and CodeRabbit
timeout rows; compare-mode first-blocking rows (Area 3/compare). The
implementer runs `grep -n "REASON timeout\|=timeout\|no_check_run\|no_review\|first blocking" scripts/development-workflow/tests/test-pr-review-loop.sh`
and confirms each hit is either updated or still correct.

**Regression suites to run before pushing**: `test-pr-review-loop.sh`,
`test-local-ai-reviewer.sh`, `test-local-ai-reviewer-pr-review-loop-dispatch.sh`,
`test-coderabbit-cli-pr-review-loop-dispatch.sh`,
`test-ronda-pr-review-loop-dispatch.sh`, `test-claude-code-action-reviewer.sh`,
`test-haystack-reviewer.sh`, `test-expensive-reviewer-gate.sh`,
`test-apply-readiness-labels.sh`, `test-item-completion-self-check.sh`,
`test-reviewer-effectiveness-report.sh`, `test-reviewer-loop-guard-workflow.sh`,
and `scripts/development-workflow/select-test-suites.sh` for anything else it
selects for the changed files; plus `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
and the markdown lints from `AGENTS.md`.

**Smoke test runbook**: `docs/testing/workflow/1789-reviewer-no-verdict-yet.smoke-test.md`

### Parser-risk addendum (configuration reader only)

The plan is parser-risk only through Layer 1's YAML reader (structured-text
parsing over config). No other part scans text.

**Edge-case enumeration** (each maps to one T1.10 sub-case):

| Case | Input under `review:` | Expected reader output for `bugbot` |
| --- | --- | --- |
| E1 plain | `  wait_budgets:` / `    bugbot: 1800` | `1800` |
| E2 quoted | `    bugbot: "1800"` and `    bugbot: '1800'` | `1800` |
| E3 trailing comment | `    bugbot: 1800  # slow vendor` | `1800` |
| E4 hyphenated key | `    local-ai-reviewer: 1500` (query `local-ai-reviewer`) | `1500` |
| E5 prefix lookalike (negative) | `    local-ai-reviewer: 1500` (query `local-ai`) | empty |
| E6 wrong parent (negative) | `bugbot: 1800` under `review.on_ready:` or a top-level `wait_budgets:` | empty |
| E7 scope end (negative) | `  wait_budgets:` then `  max_cycles: 10` then `    bugbot: 1800` | empty |
| E8 commented key (negative) | `    # bugbot: 1800` | empty |
| E9 missing file, section, or key | — | empty |
| E10 duplicate key | `    bugbot: 1800` then `    bugbot: 900` | `1800` (first wins) |
| E11 flow mapping | `  wait_budgets: {bugbot: 1800}` | `__flow__` |
| E12 deeper indentation | four-space children under `wait_budgets:` | value found |
| E13 invalid values | `abc`, `0`, `-5`, `1.5`, `1e3`, empty, `1234567` | raw value returned; the resolver rejects (T1.3) |

**Unit test file**: `scripts/development-workflow/tests/test-pr-review-loop.sh`
Area 1789, one `run_test` per row above.

**Suppression semantics**: not applicable — the reader has no suppression
directives.

### Concurrent-event-source addendum

Not applicable. The loop polls each platform sequentially in one process; no
listener, callback, or timer runs concurrently with another. Two loop
invocations for the same PR cannot overlap because of the existing per-PR
lock (`REASON=lock_contention`, exit 75), which is also what serializes the
ledger read that decides re-wait state (D11) against the ledger write of the
previous invocation.

---

## Complex Workflow Decision-Gate Matrix (plan mirror)

The normative matrix is the spec's
[Complex Workflow Decision-Gate Matrix](1_1789-reviewer-no-verdict-yet_specs.md#complex-workflow-decision-gate-matrix).
This table maps each spec row to the mechanism and test that implement it, and
names the mirror surfaces this plan edits. Example column values are the
spec's examples unless stated.

| Spec gate input | Mechanism (decision) | Mirror surfaces edited | Tests |
| --- | --- | --- | --- |
| Clean verdict within budget | Handler `clean`; D12 latency; D9 removes label | Protocol 93, Protocol 91 Step 7, summary | T2.2, T3.1, T5.1 |
| Findings within budget | Existing needs-fixes path; D9 no label | Protocol 93, Protocol 91 Step 7 | T3.3 |
| Positive failure evidence | D8 kept failure paths; D9 label | Protocol 93, Protocol 91 Step 7, guides | T2.3 |
| Budget ran out, first time for this revision | D8 No verdict yet; D11 `available` → runner re-wait | Protocol 91 Step 7, Protocol 93, guides | T2.1, T4.1 |
| Expired wait kept as non-blocking skip | D8 kept skips; D9 no label | Protocol 93, CodeRabbit, Devin, PR-Agent guides | T2.4 |
| No verdict yet again after re-wait | D11 `used` → runner stops as Waiting on reviewer | Protocol 91 Step 7, Protocol 93 | T4.1, smoke Step 6 |
| Only older-revision evidence | Existing head filters → No verdict yet (D8) | Protocol 93 | T2.5 |
| No sign of a started review, no unavailability report | D8 Bugbot `check_not_started`, Devin kept skip | Protocol 93, Bugbot guide | T2.1, T2.4 |
| Platform reports itself unavailable | D8 kept failure paths (Bugbot disabled, Copilot request failure, Haystack `unavailable`) | guides | T2.6 |
| Platform's own run timed out or failed | D8 `bugbot-run-timed-out`, `claude_code_action_run_failed`, `ronda_pass_failed` | Bugbot, Claude Code Action, Ronda guides | T2.3, T2.8 |
| Revision changes during the wait | Existing head-moved handling, unchanged | Protocol 91 Step 7 (unchanged row) | existing #1574 tests |
| Usage, spend, account, rate-limit outcomes | Unchanged paths; D8 `existing_handling` reporting label | guides (unchanged text) | T2.6 |
| Loop-level escalation | Unchanged; D10 precedence | Protocol 93, Protocol 91 Step 7 | existing cap tests, T3.6 |
| Several platforms contribute outcomes | D10 | Protocol 93 | T3.7, T3.8 |
| Configured budget missing | D7 default | Protocol 93, `.ai-dev-workflow.yaml` comment | T1.1 |
| Configured budget invalid | D6 warning + default | Protocol 93 | T1.3 |
| Invalid one-run override | D13 refusal, exit 64 | `--help` text | T1.8 |
| Later clean run on same revision with label present | D9 on both re-review and replay paths | Protocol 93, Protocol 91 Step 8a reference | T3.1, T3.2 |

Mirror surfaces not edited, with rationale: the agent, skill, and command
files in V14 delegate result interpretation to Protocols 91 and 93 and
restate none of the changed semantics; `REVIEW.md` and Protocols 02/03 carry
no reviewer-loop result or wait-budget text affected by this change.

### Matrix coherence preflight (plan-owned stateful contracts: D7, D8, D10, D11)

1. Overlapping rows — pass: D8 classes are evaluated in table order and the
   `skipped` rows are disjoint by `NO_VERDICT_YET` and reason; D7 adjustments
   are mutually exclusive by branch type.
2. Missing states — pass: unknown results classify as `reviewer_failed`
   (D8) and rank 1 (D10); unknown `NO_VERDICT_REWAIT` inputs fall to
   `untracked` (D11).
3. Precedence / order — pass: D7 states override → configured → default then
   adjustments; D10 states ranks and tie-break; loop-level escalations stay
   after platform aggregation.
4. Malformed / unknown input — pass: D6 and D13 define invalid budget
   handling; unreadable ledger → `untracked`.
5. Stale vs current evidence — pass: D8 relies on current-head filters; D11
   keys re-wait state on `loop_head_sha` and `run_id`.
6. Terminal vs waiting vs escalation — pass: every D11 runner row ends in
   continue, re-wait once, or a named Waiting on reviewer stop; failure paths
   escalate.

---

## Seed Data

None — the tests use harness mocks. The smoke runbook uses a disposable
`implementation-plan/*` test PR with Bugbot enabled (see the runbook's Test
Data).

---

## Documentation Updates

These are executed in the implementation PR.

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  — new canonical section "Reviewer wait budgets and outcome classes
  (#1789)": the three outcome classes and kept skips, the D2 defaults, D6
  configuration, D7 order, D10 precedence, D9 label rule, D11 re-wait
  contract, D12 timing keys, and the rule that a run's worst-case wait is the
  sum of its platforms' budgets plus one re-wait; update "Stuck-loop detection" ("per-platform
  timeouts … (20 min)" → per-platform budgets), "Codex phase outcomes"
  (both wait reasons are in the No verdict yet class and get the re-wait),
  and "CodeRabbit silence patterns" (`:877-966`), whose "the loop times out
  and exits `escalate`" ending and "When to escalate vs. wait" rule become No
  verdict yet and the D11 waiting stop, and whose effective-timeout table
  examples cite the old 1200 s global and 180 s documentation-branch
  defaults.
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md`
  — "Aggregation Rules" and "Review Model": a reviewer whose wait runs out
  with no verdict gives `waiting_on_reviewer`, not `escalate`, with the D10
  precedence; the `.ai-dev-workflow.yaml` example comment for
  `local-ai-reviewer` no longer lists "timeout" among the escalating causes
  (D4).
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — "Expected
  Run Durations": the `automated-reviewer-loop` row's "~20 min" threshold
  points to the per-platform budgets in Protocol 93 and the one automatic
  re-wait instead of the old single 20-minute wait.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  — Step 7 result table: the three D11 rows replacing the single
  `waiting_on_reviewer` row; the settle-forward snippet's non-zero branch
  mentions re-wait for exit 4 with `NO_VERDICT_REWAIT=available`.
- [ ] `docs/workflow/development-workflow/integrations/bugbot.md` — D3 budget
  and re-trigger point, No verdict yet vs `bugbot-run-timed-out`, adoption.
- [ ] `docs/workflow/development-workflow/integrations/greptile.md` — timeout
  row → No verdict yet; re-wait trigger reuse.
- [ ] `docs/workflow/development-workflow/integrations/devin.md` — timeout row
  → No verdict yet; `no_check_run` kept skip; D1 documentation-branch budget.
- [ ] `docs/workflow/development-workflow/integrations/coderabbit.md` — App
  timeout row → No verdict yet, `no_review` kept skip; CLI `timeout` kept skip
  without `reviewer-failed`.
- [ ] `docs/workflow/development-workflow/integrations/copilot.md` — timeout
  row → No verdict yet.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — wait
  reasons are in the No verdict yet class; re-wait with `--max-retriggers 0`;
  budget source wording for `CODEX_GITHUB_MAX_WAIT`.
- [ ] `docs/workflow/development-workflow/integrations/claude-code-action.md`
  — exit-code table (new exit 4), `claude_code_action_run_failed`, adoption.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` and
  `docs/workflow/development-workflow/integrations/haystack.md` — correct the
  stale "skipped / continue / apply `reviewer-failed`" text for `timeout` and
  `pending_timeout`: they are No verdict yet and stop as waiting.
- [ ] `docs/workflow/development-workflow/integrations/local-ai-reviewer.md` —
  D4 budget, exit 4, timeout table rows.
- [ ] `docs/workflow/development-workflow/integrations/pr-agent.md` —
  `no_review` kept skip reported as No verdict yet.
- [ ] `docs/workflow/development-workflow/integrations/ronda.md` — timeout row
  → No verdict yet.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` — the
  reviewer-loop failure symptom list adds `waiting_on_reviewer` (no verdict
  yet: re-run later) next to `escalate` and `reviewer-failed`.
- [ ] `.ai-dev-workflow.yaml` — Layer 4 comment.
- `docs/project/*`, `AGENTS.md`, `REVIEW.md`, and the other V22 hits: no
  change — none describes reviewer-loop results, wait budgets, or the label
  rule beyond listing `reviewer-failed` as an operational label (V22).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A stuck platform now costs up to its budget plus one re-wait before a human sees it, instead of a fast false failure | Med | Med | The stop names the platform and the human action; budgets are tunable per platform (D6) from recorded latency (D12) |
| Total run time with several slow platforms exceeds what a caller allows | Low | Med | Budgets are sequential and bounded; the D2 sum for this repository's configured reviewers (PR-Agent + `local-ai-reviewer`) is 2400 s, inside the existing execution budget default (`PR_REVIEW_LOOP_EXECUTION_BUDGET_DEFAULT`, `pr-review-loop.sh:117`); Protocol 93 documents the sum rule |
| Renamed reasons (`bugbot-run-timed-out`, `claude_code_action_run_failed`) break an external consumer that matched `timeout` | Low | Low | V13 shows no in-repo consumer matching those reasons other than `normalize_platform_verdict` (updated); changelog names the renames |
| Adoption of an old trigger hides a request the vendor silently dropped | Low | Med | Bugbot keeps its #1390 re-trigger in fresh runs; other platforms adopt only in re-wait mode, which ends in a named stop |
| Large test-harness edits collide with the #1562 snapshot runner | Low | Low | New tests live in one new area appended before the footer; run with `--area 1789` while iterating |

---

## Code Samples

```bash
# Illustrative — adapt during implementation.
reviewer_wait_budget_resolve() {
  local platform="$1" value source adjustment="none"
  if [ -n "${max_wait_override:-}" ]; then
    printf '%s override none\n' "$max_wait_override"; return 0
  fi
  if value="$(reviewer_wait_budget_configured "$platform")" && [ -n "$value" ]; then
    source="configured"
  else
    value="$(reviewer_wait_budget_builtin_default "$platform")"; source="default"
    if branch_is_documentation_branch "$branch_name" \
        && ! reviewer_platform_reviews_documentation_branches "$platform"; then
      value="$(doc_branch_default_max_wait)"; adjustment="documentation_branch"
    fi
  fi
  # large_diff adjustment per D7 (non-documentation branches only)
  printf '%s %s %s\n' "$value" "$source" "$adjustment"
}
```

---

## Implementation Order

Each phase is one or more coherent commits; tests land in the same commit as
the behavior they cover.

1. **Phase 1 — Budgets (D1, D2, D6, D7, D13, D14).** Layer 1 reader;
   resolver, poll resolver, `--max-wait` validation, main-flow rewiring,
   `PLATFORM_WAIT_BUDGETS`; T1.1–T1.10; update Area 0b. Run
   `bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 0b --area 1789`
   and confirm all pass.
2. **Phase 2 — Outcome classes (D3, D4, D8, D9 label function).** Helpers,
   handler edits per the D8 binding table, Bugbot budget bounding and
   re-trigger point, companion exit 4 for `local-ai-reviewer.sh` and
   `claude-code-action-reviewer.sh`, Rule 5 consumer updates, label-function
   change; T2.1–T2.11; update the existing timeout rows listed in Testing
   Strategy. Run the full `test-pr-review-loop.sh`, `test-local-ai-reviewer.sh`,
   `test-claude-code-action-reviewer.sh`, `test-haystack-reviewer.sh`, and
   `test-apply-readiness-labels.sh`.
3. **Phase 3 — Label reconciliation and precedence (D9, D10).** Reconcile
   function and call sites, precedence function and compare-mode use,
   `--compare` help text; T3.1–T3.8.
4. **Phase 4 — Re-wait and timing (D5, D11, D12).** Re-wait state, re-wait
   mode in handlers and companions, waiting output keys, timing capture,
   summary section, ledger fields; T2.12, T4.1–T4.6, T5.1–T5.4.
5. **Phase 5 — Documentation.** Every item in Documentation Updates, the
   `--help` text, and T6.1. Run
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
   and the `AGENTS.md` markdown lints over the changed documents.
6. **Phase 6 — Changelog fragment.** Add
   `changelog.d/1789.fixed.reviewer-no-verdict-yet.md` with exactly:

   ```markdown
   - **A reviewer that has not answered yet is no longer reported as failed** (#1789):
     the reviewer loop now waits a per-platform budget (Bugbot 2400 s, Codex
     GitHub 1800 s, others 1200 s; configurable under `review.wait_budgets`),
     reports a wait that runs out with no verdict and no failure evidence as
     `waiting_on_reviewer` / `reviewer-no-verdict-yet` instead of escalating,
     re-waits once per revision without re-posting an outstanding review
     request, keeps `reviewer-failed` in step with the latest run (including
     runs that reuse a recorded verdict), and records each platform's budget,
     its source, and its latency in the run output, summary comment, and
     ledger. Bugbot's own timed-out run is now reported as
     `bugbot-run-timed-out`, a failed Claude Code Action run as
     `claude_code_action_run_failed`, and `--max-wait` rejects values that are
     not positive whole seconds.
   ```

   The budget values in this literal must match D2 at implementation time;
   if D2 changes, update the literal with it. Run
   `bash scripts/development-workflow/changelog-fragments.sh validate`.
7. **Phase 7 — Verification.** Run every suite listed under "Regression
   suites to run before pushing" and confirm all pass; walk the smoke runbook
   steps that do not need a live vendor (Steps 1–3) and record results in the
   PR.

**Residual verification before readiness**: the implementation PR records,
for each row of the D8 binding table, the test ID that exercises it, and the
output of the `grep` in Testing Strategy showing each pre-existing timeout
expectation either updated or still correct. That per-row record is the
evidence that the sweep over all twelve platforms is complete.

---

## Document Quality Gate

Plan revision: recorded in the PR description (a commit cannot name its own
SHA).

- Spec/brief coverage: Checked — AC-1…AC-14 map to D-decisions, the Testing
  Strategy table, and smoke steps; all four spec plan notes are D1, D3, D4,
  D5.
- Implementation-order consistency: Checked — phases reference the same
  decisions, functions, files, and test IDs as the Layer sections.
- Verification support: Checked — existence, count, and consumer claims cite
  V1–V22.
- Behavioral guarantees: Checked — "once per revision" cites the ledger
  query keyed on `run_id` and `head_sha` (D11); "never shortens" cites the
  D7 comparison; "no duplicate request" cites the D11 adoption table and
  V10.
- Complex workflow decision-gate matrix: Checked — plan mirror table above.
- Matrix coherence preflight: Checked — six checks pass (see the preflight
  list above).
- Parser/API/concurrency checklist: Checked — parser-risk addendum for the
  config reader; concurrency not applicable with rationale.
- CHANGELOG literal format: Checked — Phase 6 literal uses the
  `**Bold Title** (#1789):` form.

| Rule | Outcome | Rationale |
| --- | --- | --- |
| Rule 1 | Not applicable | No new design depends on externally produced free text (see Factual claim evidence). |
| Rule 2 | Satisfied | Values and decisions are asserted once in D1–D14 and referenced elsewhere. |
| Rule 3 | Satisfied | Platform count (V1) and emit-site enumeration (V2) carry commands, revision, and population; the D8 binding table carries the enumeration. |
| Rule 4 | Satisfied | Existence and absence claims cite V3–V6, V8–V11, V14, V15, V17, V19, V20, V22. |
| Rule 5 | Satisfied | Consumer tables for the label function, the waiting result and the normalized ledger outcome, the global budget, and both companion exit codes (V12, V13, V17, V19, V20, V21). |
| Rule 6 | Satisfied | Rule 6 table names scope and discharge for every conditional obligation. |
