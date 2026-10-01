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
existing expired-wait non-blocking skips (D8) as skips, and accept a
platform's evidence only when it is bound to the current revision (D15).
Reconcile the
`reviewer-failed` label from per-platform failure evidence on every exit path
that evaluates reviewers, apply the spec's cross-platform precedence where a
run produces several outcomes, record per-platform budget and latency in run
output, the summary comment, and the ledger, and teach Protocol 91 Step 7 a
single automatic re-wait per revision that never re-posts an outstanding
review request.

**Estimated complexity**: L

**Rationale**: The change touches every supported platform handler (V1) in
`pr-review-loop.sh`, five companion scripts (`local-ai-reviewer.sh`,
`coderabbit-cli-reviewer.sh`, `claude-code-action-reviewer.sh`,
`codex-github-reviewer.sh`, `haystack-reviewer.sh`), the readiness
helper `apply-readiness-labels.sh`, the config reader in `workflow-lib.sh`, the ledger record, the summary renderer,
Protocol 91 and Protocol 93, and the per-platform integration guides, each
with tests in a large existing harness.

**Dependencies**: None. Spec PR #1869 is merged into `develop` (base
`13bf4c7f`).

---

## Decisions

Each decision below is the single normative statement of its fact. Every
other section refers to the decision by its label (D1–D15) instead of
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
- **Expiry signal (watchdog contract)**: the exit status of
  `run_with_timeout` is not evidence of expiry. Both of its paths forward a
  reviewer command's own exit status, so a command that exits 124 or 137 on
  its own before the budget is indistinguishable from a stopped one (V23).
  The wrapper therefore reports expiry out of band: it sets the global
  `RUN_WITH_TIMEOUT_EXPIRED` to `0` on entry and to `1` only in the branch
  where its own watchdog reached the budget **and** `kill -0` shows the
  reviewer process still running at that moment; only then does it signal the
  process group. A process that exited during the final poll second takes the
  normal `wait` path and keeps its own status and flag `0`. The GNU `timeout`
  branch is removed and the wrapper's own watchdog (the current `setsid` /
  `perl setpgrp` process-group path, already the macOS production path) runs
  on every host, because GNU `timeout` reports expiry only through the same
  124/137 statuses it also forwards from the command (V23). The `</dev/null`
  stdin (#1843) and the TERM-grace-KILL process-group sequence are kept. The
  same contract applies to the separate copy of `run_with_timeout` in
  `coderabbit-cli-reviewer.sh` (V23), whose `skipped`/`timeout` result becomes
  the D8 kept skip. That copy's fallback is weaker than the local reviewer's:
  it starts no process group and sends one `TERM` to the direct child only,
  then waits without a `KILL` (`coderabbit-cli-reviewer.sh:301-311`), while
  its GNU branch (plain `timeout`, no `--kill-after`) signals the whole
  process group. Removing only the GNU branch would therefore leak CLI
  descendants and let a CLI that ignores `TERM` block the wait on Linux. The
  CodeRabbit CLI copy is instead replaced by the local reviewer's watchdog —
  new process group via `setsid` / `perl setpgrp`, group `TERM`, 2 s grace,
  group `KILL` — plus the flag, so both companions share one shape. The
  unrelated `run_with_timeout` in `batch-merge.sh` (different signature, no
  reviewer) is not changed.
- **No verdict yet**: `RUN_WITH_TIMEOUT_EXPIRED=1` after the ordinary review
  command. The companion then prints `RESULT=waiting_on_reviewer`,
  `REASON=reviewer-no-verdict-yet`, `NO_VERDICT_YET=1` and exits **4**. The
  partial output of a stopped process is not inspected: a process that was
  still running when stopped had not reported an error by exiting, and this
  keeps the design free of any match on reviewer free text.
- **Reviewer failed**: every existing non-timeout `escalate` path in the
  companion is unchanged — a non-zero command exit before the budget, output
  the loop cannot read (`malformed_output`), credential, model-access,
  repository, head, and contract failures. A command that itself exits 124
  or 137 before the budget is one of these non-zero exits: it leaves the flag
  at `0` and reaches the existing probes and `malformed_output` handling
  (`local-ai-reviewer.sh:1392`, V23), never No verdict yet.
  `quota_exhausted` keeps its existing handling (BR 11 / AC-13).
- The strict spec/plan second pass inside the companion keeps its existing
  `strict_pass_failed` non-blocking `unavailable` state when it runs out of
  the shared budget; it never changes the ordinary verdict. It treats any
  non-zero wrapper status as `strict_pass_failed` (`local-ai-reviewer.sh:704`)
  and does not read the flag.

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
| `greptile` | `escalate`/`timeout`, no bot thumbs-up by budget end (`pr-review-loop.sh:2130-2139`) | No verdict yet, detail `no_acknowledgement` | missing trigger comment id (`:2113-2115`); new `head-sha-unavailable` (D15) |
| `devin` | `escalate`/`timeout`, check seen but not completed (`:5236-5244`); `skipped`/`no_check_run`, no check ever seen (`:5225-5235`) | No verdict yet, detail `check_not_completed`, unless a failure-type signal was recorded during the grace (failure-type completion signals, below); kept skip | stale-findings `needs_fixes` (`:5200-5221`); new `devin_run_failed` (failure-type completion signals, below) |
| `coderabbit` | `escalate`/`timeout`, activity seen (`:7846-7855`); `skipped`/`no_review`, no activity (`:7832-7844`) | No verdict yet, detail `review_not_submitted`; kept skip | `review_skipped_banner` (platform declined; `:7799-7814`), `rate_limit_max_retries`; new `coderabbit_status_failed` (failure-type completion signals, below) |
| `coderabbit-cli` | companion `skipped`/`timeout` on wrapper status 124 (`coderabbit-cli-reviewer.sh:339-342`) forwarded by the loop's skip arm (`:4627-4644`) | kept skip, emitted only when `RUN_WITH_TIMEOUT_EXPIRED=1` (D4 watchdog contract) | `unavailable`, `unauthorized`, `invalid_json`, `ambiguous_output`, `no_output`, `cli_failed` skips (a CLI that itself exits 124 before the budget now reaches these, V23); escalate reasons |
| `local-ai-reviewer` | companion `escalate`/`timeout` on wrapper status 124/137 (`local-ai-reviewer.sh:1321-1324`) forwarded by the loop's exit-2 arm (`:4864-4888`) | D4: companion exit 4 only when `RUN_WITH_TIMEOUT_EXPIRED=1`; new loop exit-4 arm → No verdict yet, detail `stopped_at_budget` | every other companion escalate reason, including a reviewer command that itself exits 124 or 137 before the budget (D4); `quota_exhausted` |
| `pr-agent` | `skipped`/`no_review` (`:5801-5812`) | kept skip | `pr_agent_trigger_failed`, `pr_agent_ambiguous_review`; new `pr_agent_run_failed` (failure-type completion signals, below) |
| `codex-github` | companion exit 4 (`codex-github-review-pending`, `codex-github-reaction-without-review`) | existing wait reasons kept, class `no_verdict_yet` (D5) | companion exit 2 and 3 reasons |
| `claude-code-action` | companion exit 2 when no run completed within the budget (`claude-code-action-reviewer.sh:397-401`), mapped to `escalate`/`timeout` (`:2623-2631`) | companion exits **4** for that case; new loop exit-4 arm → No verdict yet, detail `run_not_completed` | companion exit 2 for a completed run whose conclusion is not `success` → loop `escalate`/`claude_code_action_run_failed` (the companion's argument-validation exits, `claude-code-action-reviewer.sh:125-199`, also exit 2 and share that reason; still failure evidence); exit 3 → `unavailable`, including a dispatch response with no run id (D15) |
| `copilot` | `escalate`/`timeout` (`:2810-2817`) | No verdict yet, detail `review_not_submitted` | request failure `unavailable` (`:2700-2708`), `head-sha-unavailable` |
| `haystack` | loop `escalate` (exit-2 arm, `:4481-4494`) with companion reason `timeout` or `pending_timeout`, or `pending_check_run` when the check-run fallback ran after those budget-expiry paths (`haystack-reviewer.sh:791`, `:812`) | No verdict yet, detail = the companion reason; `pending_check_run` qualifies only with the companion's new `HAYSTACK_BUDGET_EXPIRED=1` key (failure-type completion signals, below) | companion `check_run_<conclusion>` (`timed_out`, `cancelled`, `stale`, `unknown` for an empty conclusion) on the same exit-2 arm stays `escalate`; `pending_check_run` without the key (the CLI-missing path, `haystack-reviewer.sh:483`) stays `escalate`; `draft-state-unavailable`; `unavailable`, `unauthorized`, `forbidden` skips |
| `bugbot` | `escalate`/`timeout`, check appeared but never completed (`:4331-4340`); `escalate`/`unavailable`, no check run ever appeared (`:4318-4328`) | No verdict yet, details `check_not_completed` and `check_not_started` | Bugbot's own `timed_out` conclusion (`:4237-4249`) renamed `escalate`/`bugbot-run-timed-out`; `fetch-failed`, `trigger-failed`, `head-sha-unavailable`, `unknown-conclusion-*`, `bugbot-unverified-verdict`, `bugbot-findings-not-retrievable`; `bugbot-disabled`, `bugbot-usage-limit` |
| `ronda` | `escalate`/`timeout` (`:3069-3076`) | No verdict yet, detail `check_not_completed` | `ronda_pass_failed`, `ronda_unexpected_conclusion`, `fetch-failed`, `head-sha-unavailable` |

The kept skips are exactly Devin `no_check_run`, CodeRabbit `no_review`,
CodeRabbit CLI `timeout`, and PR-Agent `no_review`. This set is the BR 4
exception; nothing else becomes a kept skip.

**Failure-type completion signals (BR 2, BR 3, BR 11, AC-2).** A platform's
own review run that reports it timed out or failed is failure evidence
(BR 2), on every platform (BR 3). The failure-type values are a check run
on `H` with `status` `completed` and `conclusion` in
`REVIEWER_LOOP_FAILED_CHECK_CONCLUSIONS` (`failure`, `timed_out`,
`cancelled`, `action_required`, `startup_failure`, `stale`), a commit status
on `H` with `state` `failure` or `error`, and a workflow run whose
`conclusion` is not `success`. A shared jq definition
`reviewer_failed_completion`, held in `REVIEWER_FAILED_COMPLETION_JQ` and
prepended the way `STATUS_CHECK_ROLLUP_DEDUPE_JQ` is, tests the first two on
the newest entry per check key after `dedupe_status_check_rollup`. Each
handler that reads such a signal applies one rule: a verdict bound to `H`
(D15) wins — bound blocking findings give `needs_fixes`, and a bound
completion review or summary gives its existing verdict; with neither, a
failure-type signal is `escalate` with the platform reason below, class
`reviewer_failed` (none of these reasons is in
`REVIEWER_LOOP_AVAILABILITY_REASONS`), so D9 requires the label and D10
ranks it 1. A conclusion a platform's own contract uses as its verdict keeps
that meaning. Rate-limit, usage-limit, and self-reported unavailability keep
their existing handling (AC-13).

**Binding enumeration** — how each handler treats a failure-type completion
signal today (line numbers at `13bf4c7f`, V33) and the change:

| Platform | Completion signal and failure-type handling today | Change |
| --- | --- | --- |
| `greptile` | Bot thumbs-up on the trigger comment plus reviews and comments; no check run, status, or workflow run is read (V33) | None |
| `devin` | Any `completed` Devin check run on `H` counts as completion (`pr-review-loop.sh:5099-5110`), and so does a Devin status in `success`, `failure`, or `error` (`:5124-5135`); both feed `check_completed` (`:5142-5145`); after the 120 s grace (`:5147-5155`) Phase 3 returns `clean` when it collects no findings (`:5357`), so a `timed_out` check or an `error` status with no findings is clean. When the budget ends inside the grace, the expiry branch (`:5236-5244`) returns `escalate`/`timeout` even though a check or status has completed | Phase 2 also records whether the newest Devin check run or status on `H` is failure-type, and whether the wait ended on that path rather than on a bound completion review. Phase 3 with no blocking findings, a check-or-status ending, and a failure-type signal returns `escalate`/`devin_run_failed`. Findings still give `needs_fixes`; a bound completion review keeps today's Phase 3. When the budget ends inside the grace and the recorded signal is failure-type, the expiry branch goes to Phase 3 as if the grace had ended, so the same rule applies; the D8 No verdict yet `check_not_completed` outcome is reached only when no failure-type Devin signal on `H` is recorded |
| `coderabbit` | Statuses read only for `success` with a description outside the #1437 rate/review-limit pattern (`coderabbit_success_status_count`, `:6474-6502`, called at `:7491`, `:7607`); a `failure` or `error` CodeRabbit status is never read, so the wait runs to No verdict yet or the `no_review` kept skip | New `coderabbit_failed_status_count` (same dedupe and description guard, `state` `failure` or `error`). A counted status on `H` ends the wait, like the D15 success status. Phase 3 then returns `needs_fixes` on bound findings, keeps today's verdict when a review with `commit_id == H` exists (the shared rule above), and otherwise returns `escalate`/`coderabbit_status_failed`. A failure status whose description matches the rate/review-limit pattern is not counted and keeps the existing rate-limit handling (AC-13) |
| `coderabbit-cli` | Local process exit, not a remote signal; non-zero exits keep their skip reasons (D8 row) | None beyond D4 |
| `local-ai-reviewer` | Local process exit (D4) | None beyond D4 |
| `pr-agent` | `PR-Agent review` check runs on `H` are read only for active states (`_pr_agent_active_review_check_count`, `:5469-5474`); a completed run with a failure-type conclusion is not read, so Phase 2 polls to the `no_review` kept skip (`:5801-5812`); D15 rule (b) at revision `b1880dcf` bound a first summary to any `completed` run | D15 rule (b) condition 2 requires `conclusion` `success`. **The newest `PR-Agent review` run on `H` governs.** New `_pr_agent_failed_review_check_conclusion` reads the `PR-Agent review` check runs on `H`, keeps the newest with `dedupe_status_check_rollup` (latest `started_at`, then highest `id`; V35), and prints its conclusion when it is `completed` and failure-type, else nothing. The handler calls it on each Phase 2 poll that binds no summary, before that poll's budget check. A failed run is superseded only by positive evidence: a newer `PR-Agent review` run on `H` (it becomes the newest, and the read then follows it), or a summary bound to `H` by D15 rule (a) or (b), which the shared rule above makes the verdict. Both runs are bound to `H` by the `commits/H` endpoint, so ordering them by `started_at` and `id` compares two runs on the same revision, never a run with another revision. No run is excluded for having completed before Phase 1 or before a request. The outcome depends on whether this invocation has an **outstanding request**: one it posted, a trigger recorded for `H` it reused (D15), or the recorded request it adopted (D11). In re-wait mode an adopted recorded request makes the request outstanding even when a run on `H` was also active at the pending check, so path (2) applies. (1) No outstanding request — `_pr_agent_trigger_already_pending` skipped posting because a run on `H` was active (`PR_AGENT_TRIGGER_SKIPPED active_review_in_progress`, `:5510`; V35): a failure-type result returns `escalate`/`pr_agent_run_failed` on that poll. (2) Outstanding request: that request is answered by an `issue_comment` run whose check run is on the default-branch tip, not `H` (V32), so the answer can supersede the failed run only as a summary bound to `H` (rule (a)) or as a newer run on `H`. While the request is outstanding the handler keeps polling and does not report Reviewer failed. At budget end, a failure-type newest run on `H` with no bound summary returns `escalate`/`pr_agent_run_failed` instead of the `no_review` kept skip. The latest run on `H` failed, so failure evidence for `H` exists and BR 1's No verdict yet (neither verdict nor failure evidence) does not apply. BR 2 holds because the evidence is the run's conclusion, not the budget end. The kept skip would drop the label that AC-2 and AC-8 require. A failed read leaves the last successful read in force; with no successful read there is no failure-type signal, and expiry gives the kept skip. A failed `/review` run itself cannot be bound to `H` (V32), so it alone never gives `pr_agent_run_failed` |
| `codex-github` | Reviews with the `Reviewed commit` marker and reactions; no check run, status, or workflow run is read (V33) | None |
| `claude-code-action` | Workflow-run `conclusion` other than `success` → companion exit 2 (`claude-code-action-reviewer.sh:405-408`) → loop `escalate` (`pr-review-loop.sh:2623-2631`) | Already failure; reason becomes `claude_code_action_run_failed` (D8 row) |
| `copilot` | Reviews with `commit_id == H`; review `state` is a verdict (`APPROVED`, `COMMENTED`, `CHANGES_REQUESTED`) with no failure-type value; no check run is read (V33) | None |
| `haystack` | Companion check-run fallback (`haystack-reviewer.sh:410-465`): `failure`, `action_required`, `startup_failure` → `needs_fixes` when a parsed summary category is blocking or no category parses and the summary does not state `**Findings:** 0`, else `clean` (the summary states `**Findings:** 0`, or every parsed category is non-blocking; `:423-452`, Haystack's findings verdict); `timed_out`, `cancelled`, `stale`, or any other conclusion → `skipped`/`check_run_<conclusion>` (`check_run_unknown` when empty), exit 2 → loop `escalate` | Already failure or a verdict; kept. The loop's exit-2 arm must not fold `check_run_<conclusion>` into No verdict yet (D8 row). `emit_check_run_fallback_or_skip` (`:468-477`) gains an `after_budget` argument, passed from the two budget-expiry paths (`:791`, `:812`); when the check run is still pending there, it prints `HAYSTACK_BUDGET_EXPIRED=1` before exiting 2 |
| `bugbot` | `failure`/`action_required` → `needs_fixes`, never clean (Bugbot reports bugs with them; `BLOCKING_COUNT` forced to at least 1, `:3994-3999`); `neutral`/`cancelled`/`skipped` → `needs_fixes` on retrievable current-head findings, `clean` only with an explicit no-issues `output.summary` and no findings, else `escalate` (`:4022-4235`, #1390); `timed_out` → `escalate` (`:4237-4249`); any other value (`stale`, `startup_failure`) → `escalate`/`unknown-conclusion-*` (`:4251-4263`) | Kept; `timed_out` renamed (D8 row). A `cancelled` run counts as clean only through its own summary's no-issues verdict for `H`, never through the conclusion alone |
| `ronda` | `success` → severity-line verdict; `failure` → `escalate`/`ronda_pass_failed`; any other conclusion → `escalate`/`ronda_unexpected_conclusion` (`:2960-3066`) | None |

Current-revision evidence (BR 6, AC-10) is not uniformly bound to the head
today (V28); D15 defines the binding every handler applies. Evidence that
fails it is ignored, so the platform keeps polling and ends in the No verdict
yet row above (or its kept skip) rather than in a verdict or a failure.

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
  `untracked`. It prints `available` only when this invocation's
  `_post_review_summary` call returned 0 (it returns 1 when the summary
  comment could not be persisted, `:13945`); when that call fails, the waiting
  entry the next invocation needs in order to see state `rewait` may not have
  been written, so the loop prints `untracked` instead. This keeps a ledger
  that can be read but not written from turning the single re-wait into an
  unbounded series (`reviewer_loop_persist_failure_should_escalate` escalates
  only `needs_fixes`/`needs_rerun`, `:12047-12063`, so a waiting result is not
  escalated on a persistence failure today; V27).
- Ledger entries carry `run_id`, `head_sha`, `result`, and `reason` today, and
  `waiting_on_reviewer` runs already persist an entry (`_post_review_summary`
  runs for every non-`skipped` result, `:14470-14486`), so the state needs no
  new ledger field. Adoption (below) reads the D12 additive keys
  `requested_at`, `requested_at_source`, and `request_ref` from that entry's
  platform record.
- The re-wait never counts toward the cycle caps: the per-run and lifetime
  counts are taken only from `needs_fixes`/`needs_rerun` entries
  (`reviewer_loop_history_entries_count`, `:11797-11830`), and Protocol 91
  increments `cycle` only when it dispatches a fixer.

Outstanding-request adoption in re-wait mode (no duplicate request while one
is outstanding). The **outstanding request** is the one this loop recorded,
not one inferred from timestamps: the platform's `platform_results[]` record
in the newest ledger entry that made the state `rewait` (same `run_id`,
`head_sha` equal to the current loop head, `waiting_on_reviewer`), when that
record has `requested_at_source` `request`. Its `request_ref` and
`requested_at` (D12) identify the request. The head commit's committer time
is never used: it does not establish when that revision became the PR head,
so a request or run created after it can still belong to the previous head.
The binding is sound because the recording invocation read the loop head
before posting the request, and its entry's `head_sha` equals the current
head; a request posted then was posted while the current head was already
the PR head. New `reviewer_loop_rewait_recorded_request <history_payload> <head_sha> <platform>`
prints two key lines, `RECORDED_REQUEST_REF=<ref>` and
`RECORDED_REQUESTED_AT=<time>` (either value may be empty), read with the
loop's `kv_value` helper, or prints nothing. Key lines rather than one
space-separated pair keep an empty `request_ref` from shifting the time into
the ref field under `read`. The loop calls it per platform in re-wait mode
and hands the values to the handler. When it prints nothing, the handler
behaves as in a fresh run and logs
`INFO: no recorded outstanding request for <platform> on <head>; requesting a review`.

| Platform | Re-wait behavior with a recorded request |
| --- | --- |
| `bugbot` | Do not post; the recorded request is the outstanding one whether or not its `request_ref` is empty or the comment still exists, because Bugbot's verdict is read from current-head check runs, not from the trigger comment. The #1390 re-trigger is skipped. Outside re-wait mode the handler posts as today; no timestamp-based adoption |
| `codex-github` | `--max-retriggers 0` (D5); no recorded request needed, the companion's own duplicate guard applies (V10) |
| `greptile` | When `request_ref` is non-empty and its reactions can be read, reuse that trigger comment regardless of the `max_wait` reuse window; a bot thumbs-up on it is that request's answer. When `request_ref` is empty or the reactions read fails (for example, the comment was deleted), there is no observable outstanding request: the handler prints `WARN: recorded greptile request <ref> on <head> is not readable; requesting a review` and posts as in a fresh run. Outside re-wait mode, trigger reuse follows D15 |
| `pr-agent` | Treat the recorded request as already pending (the handler's pending check before posting, `_pr_agent_trigger_already_pending` at `:5778`, returns pending) instead of the reuse-window search; an empty `request_ref` still adopts, because the pending check needs no comment id. Outside re-wait mode, trigger reuse follows D15 |
| `coderabbit` | No conditional `@coderabbitai review` re-trigger (a recorded request exists) |
| `claude-code-action` | Pass `--adopt-run-id <request_ref> --adopt-requested-at <requested_at>` to the companion (both required together). It skips Phase 1 dispatch, polls only `actions/runs/<request_ref>` after checking that the run's `path` ends with the workflow file and its name's `PR #<n>` token equals this PR, sets `DISPATCH_TIME` to the recorded `requested_at` so the review fetch keeps the original `.submitted_at >= DISPATCH_TIME` boundary (`claude-code-action-reviewer.sh:429-434`, V24), and never searches by `created_at`. A missing run or a run that fails those checks is not adopted: the companion prints a `WARN` and dispatches normally. An accepted fresh dispatch always yields a `request_ref`, because the run id comes from the dispatch response (D15 Claude dispatch rule); a recorded `requested_at` with an empty `request_ref` is therefore not an outstanding run, and the loop passes no adoption flags and the companion dispatches |
| `copilot` | No change: re-requesting a reviewer with a pending request is a no-op |
| `devin`, `ronda`, `haystack` | No change: they post no request |
| `local-ai-reviewer`, `coderabbit-cli` | No change: the local review runs again (BR 3) |

Runner side (Protocol 91 Step 7, D11 rows of the decision-gate matrix):

| Loop result | Runner action |
| --- | --- |
| `waiting_on_reviewer` + `NO_VERDICT_REWAIT=available` | Re-run Step 7 once, immediately, with the same `PR_REVIEW_LOOP_RUN_ID`; no fixer, no `cycle` increment, no readiness label |
| `waiting_on_reviewer` + `NO_VERDICT_REWAIT=used` | Stop as **Waiting on reviewer**: name `PENDING_REVIEWER`, `PENDING_REVIEW_HEAD_SHA`, the request time, and waited seconds; state that no failure was detected; human action is "re-run the reviewer loop later on the same revision, or investigate the platform if it still has not answered" |
| `waiting_on_reviewer` + `NO_VERDICT_REWAIT=untracked` | Stop as Waiting on reviewer as above, without the automatic re-wait, because the once-per-revision bound cannot be enforced without a stable run id or a persisted waiting entry |
| `waiting_on_reviewer` with `NO_VERDICT_REWAIT` absent or any other value | Treated as `untracked`: stop as Waiting on reviewer without the automatic re-wait. Fails closed, so a result the runner cannot place within the once-per-revision bound never re-runs Step 7 automatically |
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
| `PLATFORM_<n>_REQUEST_REF` | the handler's `REVIEW_REQUEST_REF` when it printed one; omitted otherwise |
| `PLATFORM_<n>_LATENCY_SECONDS` | end minus requested-at, for `verdict_received`, `reviewer_failed`, `existing_handling` |
| `PLATFORM_<n>_WAITED_SECONDS` | end minus requested-at, for `no_verdict_yet` |
| `PLATFORM_<n>_ELAPSED_SECONDS` | end minus requested-at, for `skipped` and `skipped_failure_evidence` |
| `PLATFORM_<n>_VERDICT_REUSED` | `1` for a #1692 replay; no budget, requested-at, or seconds key is printed for it |

Latency is measured to the poll that observed the verdict, so it overstates
the vendor's latency by at most one poll interval; the summary says so once.
Handlers that post or adopt a request print `REVIEW_REQUESTED_AT` (a reused
request is only one D15 binds to the current head, so an older head's
trigger is never recorded under the new head): Greptile
and Bugbot (trigger comment `created_at`), PR-Agent and CodeRabbit (their
trigger `created_at` when they posted or reused one), Copilot (time of the
reviewer request), `codex-github-reviewer.sh` (its `TRIGGER_TIME`, printed by
`emit_reviewed_head_if_known` and on the pending exit), and
`claude-code-action-reviewer.sh` (its `DISPATCH_TIME`, which in adoption is
the recorded `requested_at`, D11). Greptile, Bugbot, and PR-Agent also print
`REVIEW_REQUEST_REF` with the trigger comment `id` from the REST response
(Greptile already captures it; Bugbot and PR-Agent read it from the POST
response they discard or parse today, V25), and the Claude companion prints
it with the workflow run id from its dispatch response (D15 Claude dispatch
rule) or from the adopted run. D11
adoption reads these recorded values. A handler that adopts or reuses a
recorded request in re-wait mode (Bugbot, Greptile, PR-Agent, Claude Code
Action; D11 adoption table) prints that request's recorded `requested_at` as
`REVIEW_REQUESTED_AT` and its recorded `request_ref` as `REVIEW_REQUEST_REF`,
unchanged, so the adopting invocation's ledger record carries the same
request forward and a later invocation with the same run id on the same head
adopts it again instead of finding an empty `request_ref` (discharged in
each adopting handler's adoption branch; tests T2.12, T4.4, T4.7). Companion
keys reach the loop only through the handler: `run_codex_github_review` already captures the
companion output and re-prints selected keys with `kv_value_default`, and
adds `REVIEW_REQUESTED_AT` to them; `run_claude_code_action_review` today
discards the companion's stdout and stderr (`pr-review-loop.sh:2579-2582`,
`>/dev/null 2>&1`), so it now captures stdout (stderr stays discarded),
re-prints the companion's `REVIEW_REQUESTED_AT` and `REVIEW_REQUEST_REF`
on every exit arm, and appends the D11 adoption flags when the loop hands it
a recorded request. Without that capture no Claude request is ever recorded
and every re-wait re-dispatches, which `cancel-in-progress` turns into
cancelling the outstanding run (V24).

The summary comment gains a **Reviewer timing** section with one line per
platform (at most 200 characters), for example
`- bugbot: verdict received (clean) — budget 2400s (built-in default); requested 2026-09-23T12:35:16Z; latency 316s`
or `- pr-agent: verdict reused from an earlier run on this revision`. The same
fields are added to each `platform_results[]` ledger record as additive keys
(`outcome_class`, `wait_budget_seconds`, `wait_budget_source`,
`wait_budget_adjustment`, `requested_at`, `requested_at_source`,
`request_ref`, `elapsed_seconds`, `elapsed_kind` =
`latency`/`waited`/`elapsed`, `reused`),
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

### D15 — Current-revision binding of every platform's evidence (BR 6, AC-10)

A verdict, finding, or completion signal counts for the loop head `H` only
through one of these bindings:

| Evidence kind | Bound to `H` by | Never used as head evidence |
| --- | --- | --- |
| Check runs and commit statuses | being read from `commits/H/check-runs` or `commits/H/statuses` | — |
| Workflow runs the loop dispatches (Claude Code Action) | the run id returned by this invocation's dispatch (Claude dispatch rule below) or recorded for `H` (D11) | `created_at`, the run name, or the run's `head_sha`, which is the dispatched ref's tip (V31) |
| Pull request reviews (`pulls/<n>/reviews`) | `commit_id == H`, which GitHub fixes at submission (V29) | `submitted_at` alone |
| Pull request review comments (`pulls/<n>/comments`) | `original_commit_id == H` | `commit_id`, which GitHub moves to the newest head while the commented line is unchanged (V29); `created_at` alone |
| Issue comments and reactions (no commit field) | being the answer to a request recorded for `H` (below); PR-Agent's summary comment by the PR-Agent summary rules below the binding enumeration | `created_at` or `updated_at` compared with the head commit's committer time, which does not establish when `H` became the PR head (D11) |

A **request recorded for `H`** is a request this invocation posted after
reading `H` as the loop head, or one whose id a ledger platform record holds
under `head_sha` `H` with `requested_at_source` `request` (D12). New
`reviewer_loop_head_recorded_request_refs <history_payload> <head_sha> <platform>`
prints, one per line, every non-empty `request_ref` from such records in any
ledger entry for that head and platform, whatever its `run_id` or result, and
prints nothing when the ledger is unavailable. It serves fresh-mode reuse;
re-wait adoption keeps `reviewer_loop_rewait_recorded_request` (D11). The
loop calls it for Greptile and PR-Agent and hands the list and
`loop_head_sha` to the handler alongside the D11 values.

The binding governs verdict, finding, and completion evidence only. Platform
state notices that handlers read from issue comments by time — Bugbot's
disabled, usage-limit, and explicit-skip comments
(`bugbot_check_disabled_issue_comments`, `:3154`, read by
`bugbot_escalate_for_unavailable_issue_comments`, `:3186`) and CodeRabbit's
pause and rate-limit comments (`coderabbit_newest_rate_limit_comment`,
`:6935`) and its `review_skipped_banner` (`:7802`) — report the platform's
own availability, not a verdict on a revision, and keep their existing
reads: spec BR 2 keeps a self-reported unavailability on its existing
handling, and AC-13 keeps usage-limit and rate-limit outcomes unchanged.
Search, at `13bf4c7f`:
`grep -n '^bugbot_check_disabled_issue_comments\|^bugbot_escalate_for_unavailable_issue_comments\|^coderabbit_newest_rate_limit_comment\|REASON review_skipped_banner' scripts/development-workflow/pr-review-loop.sh`
(four hits, at the lines cited).

**Binding enumeration** — per platform, line numbers at `13bf4c7f` (V28):

| Platform | Evidence read today | Gap | Change |
| --- | --- | --- | --- |
| `greptile` | trigger reuse by age only, `now - created_at <= max_wait` (`pr-review-loop.sh:2000-2030`); bot thumbs-up on that trigger (`:2120-2144`); findings after the trigger by `created_at`/`submitted_at` (`:2146-2180`); pre-trigger findings after the head commit's committer time (`:2032-2066`) | A trigger posted while the previous head was the PR head is reused; its late thumbs-up and comments become the new head's verdict, D12 records it under the new head, and D11 adopts it again | Fresh mode reuses an age-window trigger only when its `id` is in the helper's list for `H`; otherwise it posts a new trigger (re-wait mode keeps its D11 row). Findings after the thumbs-up and pre-trigger findings add the comment and review bindings above to the existing time filters. The handler uses `loop_head_sha`, or reads `.head.sha` as it does today when the loop has none; with neither it returns `escalate`/`head-sha-unavailable` before posting |
| `devin` | completion review by `submitted_at` (`:5081-5091`); findings by time (`:4973-4995`, `:5254-5290`); check runs and statuses on `H` (`:5100`, `:5125`) | An older head's summary review submitted after the committer time ends the wait | Completion review and findings use the review and comment bindings; check runs and statuses keep their `commits/H` endpoint binding, and their failure-type conclusions and states are now read (D8 failure-type completion signals, `devin_run_failed`) |
| `coderabbit` | any review by `submitted_at` (`:7252-7263`); walkthrough issue comment by `created_at`/`updated_at` (`:7286-7307`); findings by time (`:7077-7096`, `:7865-7895`); success status on `H` in the rate-limit paths (`:7491`, `:7607`) | An older head's review or an edited walkthrough ends the wait | The wait ends on a review with `commit_id == H`, a CodeRabbit success status on `H` (`coderabbit_success_status_count`, `:6474`), or a failed one (`coderabbit_failed_status_count`, D8 failure-type completion signals); a walkthrough comment with neither still sets `coderabbit_any_activity` (so expiry gives the D8 No verdict yet, not the kept skip) but no longer ends the wait; findings use the review and comment bindings |
| `pr-agent` | Phase 1 summary comment containing `H` (`strict_sha`, `:5706`); Phase 2 `recent_or_sha`, a comment containing `H` **or** updated after the committer time (`:5794`, `:5825`; matcher `:5437-5459`); trigger reuse after the committer time within the reuse window (`_pr_agent_recent_trigger_comment_created_at`, `:5476-5502`) | An older head's summary edited after the committer time is accepted; an older head's `/review` trigger suppresses the new request | Phase 2 accepts a summary comment only by rule (a) or rule (b) below the table; `recent_or_sha` is removed. Trigger reuse counts only a trigger in the helper's list for `H`. A failure-type newest `PR-Agent review` run on `H` with no bound summary is `pr_agent_run_failed` under the D8 failure-type completion-signal row |
| `bugbot` | verdict from check runs on `H` (`:3632`, `:3730`); reviews with `commit_id == H` (`:3471`, `:3905`, `:4083`); review comments with `commit_id == H` (`:3458`, `:3801`, `:3892`, `:4070`) | Review-comment `commit_id` moves to the newest head | The four review-comment filters use `original_commit_id` |
| `codex-github` | `Reviewed commit` marker and reviews with `commit_id == H` (`codex-github-reviewer.sh:1867`, `:2209`, `:2537`, `:2656`, `:2813`); trigger body carries `H` (`:2021`); inline review-comment count by `commit_id` (`codex_inline_review_comment_count_since`, `:288-296`) | An older head's inline comment created after the trigger returns `NEEDS_REVISION` | `codex_inline_review_comment_count_since` uses `original_commit_id` |
| `claude-code-action` | fresh run selected as the newest `workflow_dispatch` run for this PR created at or after `DISPATCH_TIME` minus 10 s (`claude-code-action-reviewer.sh:336-353`, V24); adopted run by recorded id (D11); reviews by `submitted_at >= DISPATCH_TIME` (`:429-434`) | An earlier dispatch's run for this PR created inside that window (for example, another invocation's dispatch for the previous head seconds earlier) is selected while this dispatch's run is not yet visible, and its completed `success` with no blocking review returns clean (`:449-455`); a review from an earlier run that was not yet cancelled, submitted after the dispatch, counts | The run is bound by the Claude dispatch rule below the table, never by `created_at`; new `--head-sha <sha>` (the loop passes `loop_head_sha`); when given, counted reviews add `commit_id == head` |
| `copilot` | reviews with `commit_id == H` (`:2732-2734`, `:2758-2760`) | None | None |
| `ronda` | check runs on the current head (`:2920`) | None | None |
| `haystack` | companion check runs on the PR head (`haystack-reviewer.sh:236-241`) | None | None |
| `local-ai-reviewer`, `coderabbit-cli` | no remote verdict; the companion compares the reviewed head with the PR head (`local-ai-reviewer.sh:1449-1451`, `PARSE_STATUS=head_mismatch`; `coderabbit-cli-reviewer.sh:263-267`, checkout head versus PR head) | None | None |

**PR-Agent summary rules.** A PR-Agent summary comment counts for `H` only
by one of these rules; no rule accepts a comment because its time follows a
request time or the head commit's committer time. Rule (b)'s only positive
time test places the comment inside a run on `H`; its `/review` comparison
only excludes.

- **Rule (a)**: the body contains `H` (the `strict_sha` match Phase 1 already
  uses). V30 is the sampling record for the head marker PR-Agent writes when
  it updates its summary.
- **Rule (b)**, for a first summary that carries no marker, new
  `_pr_agent_first_summary_bound_to_head <comment_id> <created_at> <updated_at>`:
  the comment is accepted only when every condition holds.
  1. It was never edited (`updated_at == created_at`).
  2. **Binding run**: a `PR-Agent review` check run read from
     `commits/H/check-runs` is `completed` with `conclusion` `success`, and
     its `started_at <= created_at <= completed_at`. PR-Agent posts the
     summary from inside its Actions job, so a comment created inside the
     window of a run on `H` was posted while that run was reviewing `H`. A
     run that ended with any other conclusion did not finish its review, so
     a comment inside its window is not a verdict; its failure-type
     conclusion is handled by the D8 failure-type completion-signal row.
     All five V32 binding runs concluded
     `success` (V34), so the sampled first summaries still bind.
  3. No `PR-Agent review` check run on `H` is queued or in progress
     (`_pr_agent_active_review_check_count`, `:5469-5474`), so no later run on
     `H` is about to rewrite the comment.
  4. **No other revision's run could have posted it**. The handler finds the
     binding run's workflow through its `check_suite.id`
     (`actions/runs?check_suite_id=<id>` → `workflow_id`) and lists that
     workflow's `pull_request` runs on the PR's head branch
     (`actions/workflows/<workflow_id>/runs?event=pull_request&branch=<headRefName>`,
     fully paginated, so no time window bounds the search). No run there
     with `head_sha != H` may have been in progress at `created_at`
     (`run_started_at <= created_at`, and `status != completed` or
     `updated_at >= created_at`; `updated_at` is at or after completion, so
     the test can only widen the window). And no `/review` comment on the PR
     may predate `created_at`, because an `issue_comment` run records
     neither the PR (`pull_requests` is empty) nor the revision it read
     (`head_sha` is the default branch tip) (V32).

  Any of these API reads failing, or any condition failing, means the comment
  is not bound to `H`. Phase 2 keeps polling, and expiry ends in the D8
  `no_review` kept skip, never in a verdict, unless the newest
  `PR-Agent review` run on `H` is failure-type, which gives
  `pr_agent_run_failed` under the D8 failure-type completion-signal row. An
  unbound first summary is not
  a dead end: any later PR-Agent run on `H` (the second of two overlapping
  runs, or a later `/review` posted by a later invocation once no trigger
  recorded for `H` is inside the reuse window, or by a maintainer) updates
  the persistent summary with the `H` marker, which rule (a) accepts. V32
  records that all five never-edited first summaries in the V30 sample
  satisfy rule (b), so today's clean verdict stays reachable on
  first-summary PRs.

A body outside the sampled variants is tolerated: it matches rule (a) only
when it names `H` and rule (b) only through the run binding, so the platform
keeps polling and ends in its `no_review` kept skip (or, with a
failure-type newest run on `H`, in `pr_agent_run_failed` per the D8
failure-type completion-signal row), never in a verdict for another
revision.

**Claude dispatch rule.** The companion binds a fresh run to its own
dispatch by the run id GitHub returns for that dispatch, never by a
timestamp. Phase 1 adds the boolean body parameter `return_run_details`
(`--field return_run_details=true`, which `gh api` sends as JSON `true`) to
`POST actions/workflows/<file>/dispatches`, keeps the response body (today
printed and ignored as "HTTP 204 — no body expected"), and reads
`workflow_run_id`. The parameter is required: `gh api` sends
`X-GitHub-Api-Version: 2022-11-28`, and under that API version GitHub's REST
reference documents `200` with `workflow_run_id` only when
`return_run_details` is true and an empty `204` otherwise (V31). Phase 2 polls only
`actions/runs/<workflow_run_id>`; the `actions/runs?event=workflow_dispatch`
list search, `POLL_AFTER_TIME`, and the `created_at` / `PR #<n>` selection
(`:336-353`) are removed from the fresh path. When the response has no
integer `workflow_run_id` (for example, a GitHub Enterprise Server version
without `return_run_details` that still answers `204`), the companion prints
`VERDICT: UNAVAILABLE — dispatch response carried no workflow_run_id; the run cannot be bound to this request`
and exits 3, which the loop maps to `escalate`/`unavailable` (D8 Claude row),
never to clean or to No verdict yet. The run's own `head_sha` cannot bind it:
a `workflow_dispatch` run carries the dispatched ref's tip (`main`), not the
PR head (V31). This dispatch's run reviews the PR head at execution time
(V24), and the dispatch is posted after the loop read `H`. If the head moves
before the run reviews it, its reviews carry the newer `commit_id` and are
not counted, and the loop's existing head-move guard
(`pr-review-loop.sh:14345-14356`) turns the resulting clean aggregate into
`needs_fixes`/`head_moved_during_run`. The companion prints the bound id as
`REVIEW_REQUEST_REF` (D12), so re-wait adoption (D11) reuses the same id.

The `200`-with-`workflow_run_id` response is confirmed by GitHub's REST
reference only (V31). No dispatch carrying `return_run_details=true` was sent
while writing this plan, because every dispatch starts a real Claude review
run. Smoke runbook Step 8 is the live confirmation on this repository's host,
and it is a required step, not an optional one. If that step observes `204`
or a body without an integer `workflow_run_id`, the companion behaves as
this rule states (exit 3, `escalate`/`unavailable`, never clean). The smoke
tester records the observation as a blocking defect and escalates. The
time-window selection is not restored as a fallback.

Unresolved review threads are not a verdict for any revision and are out of
this binding: the D8-kept Devin and CodeRabbit `stale_findings` paths
(`:5208`, `:7700`) and the aggregate unresolved-thread audit
(`:14034-14096`) keep reading them regardless of revision. An older head's
Greptile, Devin, or CodeRabbit finding that the new pre-trigger and
collection filters drop therefore still blocks a clean aggregate while its
thread is unresolved, because those platforms' logins are in
`unresolved_bot_logins` (`:7983`, `:14006-14015`).

---

## Verification Log

All commands were run in the plan worktree at repository revision
`13bf4c7f` (`git rev-parse --short HEAD`), the merge of spec PR #1869, on
2026-10-01, except rows that name a later plan-branch revision; those
revisions change only this plan and its runbook, so every script line they
cite is identical at `13bf4c7f`.

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
| V9 | `local-ai-reviewer.sh` timeout path | `grep -n "timeout\|TIMEOUT" scripts/development-workflow/local-ai-reviewer.sh` | `run_with_timeout` returns 124 (GNU `timeout` or the fallback kill path); the caller treats 124/137 as timeout at `:1321-1324` and checks it before any output probe. V23 shows that status is not expiry evidence |
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
| V23 | `run_with_timeout` forwards a command's own 124/137 (reviewer-loop finding, revision `06d435e7`, whose script files equal `13bf4c7f`) | Extract the function with `sed -n '/^run_with_timeout() {/,/^}/p' scripts/development-workflow/local-ai-reviewer.sh`, source it, and call `run_with_timeout 3 <out> <err> sh -c '<cmd>'` for `exit 124`, `exit 137`, `sleep 6`; read both copies (`local-ai-reviewer.sh:174-223`, `coderabbit-cli-reviewer.sh:289-314`), their callers (`grep -n run_with_timeout` → `local-ai-reviewer.sh:696`, `:1314`; `coderabbit-cli-reviewer.sh:325`, `:328`), and the non-zero handling (`grep -n "malformed_output\|no_output\|cli_failed"`) | This host has no GNU `timeout` with `--kill-after`, so the fallback path ran: `exit 124` → 124 after 1 s, `exit 137` → 137 after 2 s, `sleep 6` → 124 after 4 s (budget 3). The fallback returns 124 itself only in its watchdog branch (`:203-220`) and otherwise forwards the child status through `wait` (`:222`); the GNU branch (`:180-186`) returns `timeout`'s status, which GNU documents as 124 on expiry and otherwise the command's own status (not reproducible on this host). The CodeRabbit CLI copy has the same status forwarding (its watchdog branch returns 124 at `:308-311`, otherwise `wait` at `:313`), but its fallback starts no process group and sends a single `TERM` to the direct child with no `KILL` (`:301-310`), and its GNU branch is plain `timeout` without `--kill-after` (`:295-298`). `batch-merge.sh:152` defines an unrelated `run_with_timeout` (no reviewer, different signature). Early non-zero exits with unreadable stdout reach `malformed_output` (`local-ai-reviewer.sh:1392`) and `no_output` / `cli_failed` (`coderabbit-cli-reviewer.sh:346-352`, `:523-525`). The strict pass (`:696-704`) treats any non-zero status as `strict_pass_failed` |
| V24 | Claude companion run selection and review boundary (reviewer-loop finding, revision `06d435e7`) | Read `claude-code-action-reviewer.sh:247-455` and `.github/workflows/claude-code-review.yml:11-58`; `grep -c "head_sha\|HEAD_SHA" scripts/development-workflow/claude-code-action-reviewer.sh` | The companion selects the newest `workflow_dispatch` run whose `path` ends with the workflow file, whose name carries `PR #<this PR>`, and whose `created_at >= POLL_AFTER_TIME` (`DISPATCH_TIME` minus 10 s; `:336-353`); the grep returns 0, so it has no head SHA input or check; a completed `success` run then reads bot reviews with `.submitted_at >= DISPATCH_TIME` (`:429-434`) and returns clean unless one requested changes (`:449-455`). The workflow takes only `pr_number` (`:16-21`), reviews the PR at execution time (`:58`), and cancels an in-progress run for the same PR when a new one is dispatched (`:26-28`). The loop handler invokes the companion with `>/dev/null 2>&1` (`grep -nF 'max-wait "$max_wait" >/dev/null 2>&1' scripts/development-workflow/pr-review-loop.sh` → `:2582`, the end of the `:2579` invocation in `run_claude_code_action_review`), so none of the companion's stdout reaches the loop today; `run_codex_github_review` captures its companion's output (`script_output=…2>&1`, `:2341`) and re-prints keys with `kv_value_default` |
| V25 | Request identifiers the request-posting handlers can record (revision `06d435e7`) | `grep -nF -e 'issues/$pr_number/comments" --method POST' -e '-X POST "repos/$repo/issues/$pr_number/comments"' scripts/development-workflow/pr-review-loop.sh` (hits `:2110`, `:3673`, `:4289`, `:5528`) and `grep -n "@coderabbitai review" scripts/development-workflow/pr-review-loop.sh`, then read the hits | Greptile captures the trigger comment `id` (`:2110`, `--jq '.id'`); Bugbot posts with output discarded (`:3673-3674`, `:4289-4290`); PR-Agent keeps the POST response and reads its `created_at` (`:5528-5533`); CodeRabbit posts with `gh pr comment` (`:7405`, `:7465`) and needs only the recorded `requested_at` under D11 |
| V26 | CodeRabbit CLI test PATH that runs the CLI without GNU `timeout` (revision `74d82039`, whose script files equal `13bf4c7f`) | `grep -n 'NO_CLI_BIN' scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh`, read the symlink loop at `:34-37`; then link the same ten commands into an empty directory, source the function extracted with V23's `sed` from `local-ai-reviewer.sh`, and call `run_with_timeout 2 <out> <err> sleep 5` with only that directory on `PATH` | The loop links `awk bash cat dirname grep jq mktemp rm sleep tr` (no `perl`, no `setsid`); the CLI runs under `$MOCK_BIN:$NO_CLI_BIN` at `:420` (`fallback_timeout_*`) and `:466` (`fallback_coderabbit_*`). The probe on this host (macOS, no `setsid`) returned status 127 after 1 s with `perl: command not found` on stderr |
| V27 | Summary-persistence status and which results escalate on a persistence failure (revision `7a8d15db`, whose script files equal `13bf4c7f`) | `grep -n -A16 '^reviewer_loop_persist_failure_should_escalate' scripts/development-workflow/pr-review-loop.sh`; `grep -n '^_post_review_summary' scripts/development-workflow/pr-review-loop.sh` and read to its closing brace; read the caller at `:14470-14486` | `reviewer_loop_persist_failure_should_escalate` (`:12047-12063`) returns false for every result other than `needs_fixes`/`needs_rerun`; `_post_review_summary` (`:13426`) returns 1 when the summary comment could not be persisted (`:13945`) and 0 otherwise (`:13947`); the caller records that status in `_post_summary_exit`, so a `waiting_on_reviewer` run whose ledger write failed keeps its result today |
| V28 | Head binding of each handler's evidence (reviewer-loop finding on revision `44973096`, whose script and workflow files equal `13bf4c7f`: `git diff --stat 13bf4c7f HEAD -- scripts .github` is empty) | `grep -n '^run_[a-z_]*_review()' scripts/development-workflow/pr-review-loop.sh` for the handler ranges; within them `grep -n 'max_wait)\|review_window_start=\|\.created_at > \$since\|\.submitted_at > \$since\|updated_at > \$since\|commits/\$[a-z_]*sha/\(check-runs\|statuses\)' scripts/development-workflow/pr-review-loop.sh`; `grep -n '\.commit_id == \$sha' scripts/development-workflow/pr-review-loop.sh`; `grep -n 'commit_id\|Reviewed commit' scripts/development-workflow/codex-github-reviewer.sh`; `grep -n 'submitted_at\|commit_id' scripts/development-workflow/claude-code-action-reviewer.sh`; `grep -n 'head_sha\|check-runs' scripts/development-workflow/haystack-reviewer.sh`; `grep -n 'recent_or_sha\|strict_sha' scripts/development-workflow/pr-review-loop.sh`; then read each hit | The D15 binding table, row by row. Greptile has no head check on its reused trigger (`:2000-2030`, age only) or its findings (`:2146-2180`, `created_at`/`submitted_at` only); Devin and CodeRabbit filter reviews and comments by time only; PR-Agent Phase 2 uses `recent_or_sha` (`:5794`, `:5825`); every `commit_id == $sha` filter on review comments is in Bugbot (`:3458`, `:3801`, `:3892`, `:4070`) and in `codex_inline_review_comment_count_since` (`codex-github-reviewer.sh:296`); the Claude companion's review count (`:433`) has no `commit_id` term. Head-bound today: Copilot reviews (`:2734`, `:2760`), Bugbot reviews (`:3471`, `:3905`, `:4083`) and check runs, Ronda (`:2920`), Haystack (`haystack-reviewer.sh:236-241`), Codex reviews and trigger. `bot_login_for_platform` (`:7978-7992`) maps Greptile, Devin, and CodeRabbit to non-empty logins used by the unresolved-thread audit |
| V29 | GitHub `commit_id` on review comments versus reviews | `gh api repos/lhpaul/ai-dev-framework-template/pulls/<n>/comments --paginate --jq '.[] \| [.id,.user.login,.created_at,.commit_id,.original_commit_id]'` for PRs #1800–#1872 that have review comments (25 PRs: 1872, 1869, 1868, 1857, 1856, 1854, 1850, 1848, 1845, 1844, 1842, 1833, 1832, 1831, 1827, 1826, 1825, 1821, 1818, 1816, 1815, 1807, 1803, 1802, 1800), run 2026-10-01T04:35Z; and `gh api repos/lhpaul/ai-dev-framework-template/pulls/1833/reviews --jq '.[] \| [.id,.submitted_at,.commit_id]'` | 532 review comments; 208 have `commit_id` different from `original_commit_id`. On PR #1833, review `5355251199` (submitted 2026-09-29T16:06:17Z) has `commit_id` `6f41c147`, while its comment `4135652731` now shows `commit_id` `5d36888b` (the PR's final head) and `original_commit_id` `6f41c147`; the PR's four reviews keep four distinct submission heads (`6f41c147`, `ec27ca03`, `ec27ca03`, `a1a408a2`). So a review's `commit_id` is the head it was submitted against, and a review comment's `commit_id` is not |
| V30 | PR-Agent summary-comment head marker (Rule 1 sampling record) | For each of the 30 most recent PRs (`gh pr list --state all --limit 30`, #1800–#1872, created 2026-09-24 to 2026-10-01), `gh api repos/lhpaul/ai-dev-framework-template/issues/<n>/comments --paginate --jq '.[] \| select(.user.login=="github-actions[bot]" and (.body\|test("PR Reviewer Guide"))) \| [.id,.created_at,.updated_at,(.body\|capture("Review updated until commit https://github.com/[^/]+/[^/]+/commit/(?<s>[0-9a-f]{40})")?.s)]'`, compared with `gh pr view <n> --json headRefOid`, run 2026-10-01T04:30Z | Producer PR-Agent (`.github/workflows/pr-agent.yml`, persistent review comment). 30 occurrences, one per PR, two variants. Variant 1, 25 edited comments (`updated_at` after `created_at`), each carrying the line `#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/<40-hex SHA>)` naming the PR's current head (comment id → head): 5923584487 → `44973096`, 5921127658 → `46704226`, 5921003723 → `baa6ec1e`, 5916528296 → `86494ba1`, 5915837212 → `385ae95f`, 5915738414 → `8f37d8ab`, 5914300509 → `14b935c4`, 5913226868 → `03cdc778`, 5911611179 → `c28b266c`, 5910487888 → `9444db4a`, 5900195916 → `d5e7b75d`, 5893619206 → `5d36888b`, 5893468974 → `3c7bf1fb`, 5893432669 → `92b93516`, 5892949543 → `65bb788b`, 5892808152 → `48885e66`, 5892724036 → `505b2945`, 5889722210 → `c77a467f`, 5862938661 → `22cedff3`, 5862042325 → `f1831794`, 5861742106 → `1bb31d8f`, 5837740046 → `1755b09c`, 5830205485 → `c239b070`, 5821872735 → `cb511bd3`, 5820335436 → `a9a99633`. Variant 2, 5 never-edited comments (`updated_at == created_at`) with no such line: 5918692074 (#1867), 5918702086 (#1866), 5917483876 (#1863), 5917347108 (#1861), 5892063119 (#1823). No third variant appeared. Adequacy: the sample spans both review modes the design must handle (a first review and an updated review) across 30 PRs; D15 rule (a) binds only to the marker naming the current head, rule (b) needs no body text, and any other body falls to the tolerant path stated in D15 |
| V31 | Claude dispatch run binding (reviewer-loop finding on revision `d94593bc`, whose script and workflow files equal `13bf4c7f`) | `curl -sL "https://docs.github.com/api/article/body?pathname=/en/rest/actions/workflows"` and the same URL with `&apiVersion=2022-11-28`, section "Create a workflow dispatch event", run 2026-10-01T05:15Z and 2026-10-01T05:30Z; `gh api --verbose repos/lhpaul/ai-dev-framework-template` (request header lines, gh 2.97.0); `gh api "repos/lhpaul/ai-dev-framework-template/actions/workflows/claude-code-review.yml/runs?per_page=5" --jq '.workflow_runs[] \| [.id,.event,.head_branch,.head_sha[0:8],.name,.created_at]'`; `grep -n 'dispatches\|HTTP 204\|POLL_AFTER_TIME\|X-GitHub-Api-Version' scripts/development-workflow/claude-code-action-reviewer.sh` | The unversioned (latest-version) reference lists only response `200` "Response including the workflow run ID and URLs" with required `workflow_run_id` (integer), `run_url`, and `html_url`. The `2022-11-28` reference adds body parameter `return_run_details` (boolean, "Whether the response should include the workflow run ID and URLs") and lists `200` "… when return\_run\_details parameter is true" and `204` "Empty response when return\_run\_details parameter is false". `gh api` sends `X-Github-Api-Version: 2022-11-28` (response `X-Github-Api-Version-Selected: 2022-11-28`), and the companion sets no version header, so the dispatch must send `return_run_details=true`. The five newest runs (of 126) are all `workflow_dispatch` on `head_branch` `main` with `head_sha` `0ed9da12` for PRs #872, #867 (three runs), and #865, so a run's `head_sha` is the dispatched ref's tip, not the PR head, and one PR can have several runs. The companion posts the dispatch with `gh api … --method POST` without keeping its stdout, logs "workflow dispatch accepted (HTTP 204 — no body expected)", and selects the run with `POLL_AFTER_TIME` (`:336-353`, V24). Not observed live: no dispatch with `return_run_details=true` was sent (each one starts a real review run); smoke Step 8 confirms the response on this host (D15 Claude dispatch rule) |
| V32 | PR-Agent first summaries and the D15 rule (b) run binding (same revision and scope as V31) | For each never-edited summary in V30 (#1867, #1866, #1863, #1861, #1823), with `H` = `gh pr view <n> --json headRefOid,headRefName`: `gh api "repos/lhpaul/ai-dev-framework-template/commits/<H>/check-runs?check_name=PR-Agent%20review"` (window containing the comment's `created_at`); `gh api --paginate "repos/lhpaul/ai-dev-framework-template/actions/workflows/pr-agent.yml/runs?event=pull_request&branch=<headRefName>"` (runs in progress at `created_at` and their `head_sha`); `gh api --paginate repos/lhpaul/ai-dev-framework-template/issues/<n>/comments` (count of `/review` bodies before `created_at`); plus `gh api "repos/lhpaul/ai-dev-framework-template/actions/workflows/pr-agent.yml/runs?event=issue_comment&per_page=5"` and the open PR's run `actions/runs/36817052144`; run 2026-10-01T05:20Z | All five pass every rule (b) condition. Binding check runs (`started_at`..`completed_at` ∋ `created_at`): #1867 `110072627980` and `110072606697` on `f8deabb6`; #1866 `110072606697` on `f8deabb6` (#1866 and #1867 share head `f8deabb6` and branch `release/v0.45.0`; both runs are on that head, so neither is another revision); #1863 `110041365380` on `6dfeee7c`; #1861 `110037812568` on `c019ce64`; #1823 `109448862127` on `36e2ae49`. Each comment was created 2–43 s before its binding run completed. Branch runs in progress at `created_at` all have `head_sha == H`; no other-revision branch run overlapped. Prior `/review` comments: 0 on each. A repository-wide run list would not be exclusive enough: run `36581030067` (head `36f7c2aa`, PR #1821's branch) overlapped #1823's comment, and its `pull_requests` is now `[]` because the PR is closed, so the D15 search is branch-scoped. `issue_comment` runs carry `head_branch` `main`, the default-branch `head_sha`, and `pull_requests` `[]`; the open PR #1872's `pull_request` run lists `[1872]`. `.github/workflows/pr-agent.yml` names the job `PR-Agent review` and posts from inside it |
| V33 | Failure-type completion signals per handler (reviewer-loop finding on revision `b1880dcf`, whose script and workflow files equal `13bf4c7f`) | `grep -nE 'check-runs\|/statuses\|actions/runs\|\.conclusion\|conclusion"' scripts/development-workflow/pr-review-loop.sh`, keeping hits inside the handler ranges `:1957-8166` (V28's `grep -n '^run_[a-z_]*_review()'`); `grep -cE 'check-runs\|/statuses\|actions/runs\|conclusion'` over `codex-github-reviewer.sh`, `codex-github-evidence-lib.sh`, `local-ai-reviewer.sh`, `coderabbit-cli-reviewer.sh`, `claude-code-action-reviewer.sh`, and `haystack-reviewer.sh`; then read every hit and the outcome arms each one feeds, run 2026-10-01T06:00Z | Loop hits, by handler: Ronda `:2833` (comment), `:2920`, `:2950`, `:2960`; Bugbot `:3243` (run count), `:3275-3302` (a completed `success` run makes disabled comments stale), `:3632` (trigger decision), `:3730`, `:3741`, `:3788` (verdict), `:4036`; Devin `:5100`, `:5125`; PR-Agent `:5470` (active states only); CodeRabbit `:6490` (`coderabbit_success_status_count`, `success` only). No hit in the Greptile, Codex, Claude, Copilot, Haystack, CodeRabbit CLI, or local-ai handler ranges. Companions: 0 in both Codex files, `local-ai-reviewer.sh`, and `coderabbit-cli-reviewer.sh`; 9 in `claude-code-action-reviewer.sh` (run `conclusion`; non-`success` exits 2 at `:405-408`); 14 in `haystack-reviewer.sh` (check-run fallback `:309-465`). The outcome of each failure-type value per platform is the D8 failure-type completion-signal table |
| V34 | Conclusion of the five V32 binding runs (D15 rule (b) condition 2) | `gh api repos/lhpaul/ai-dev-framework-template/check-runs/<id> --jq '[.id,.name,.status,.conclusion,.head_sha[0:8]] \| @tsv'` for `110072627980`, `110072606697`, `110041365380`, `110037812568`, `109448862127`, run 2026-10-01T06:02Z | All five are `PR-Agent review`, `completed`, `success`, on `f8deabb6`, `f8deabb6`, `6dfeee7c`, `c019ce64`, and `36e2ae49` |
| V35 | Newest-run ordering on one head and the PR-Agent no-post path (reviewer-loop finding on revision `b92b4ee9`, whose script files equal `13bf4c7f`) | `git diff --stat 13bf4c7f HEAD -- scripts` (empty); read `scripts/development-workflow/workflow-lib.sh:588-636`; `grep -n 'dedupe_status_check_rollup' scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/haystack-reviewer.sh`; read `pr-review-loop.sh:5469-5523`; run 2026-10-01T06:43Z | `dedupe_status_check_rollup` groups by check name or status context and keeps, per group, the entry with the latest timestamp (first non-empty of `started_at`, `completed_at`, `created_at`, `updated_at`), then the highest `id`; an active entry with no timestamp sorts as newest. The Ronda (`:2922`), Bugbot (`:3250`, `:3287`, `:3639`, `:3740`), Devin (`:5105`, `:5128-5130`), PR-Agent active-count (`:5471`), CodeRabbit (`:6494`), and Haystack companion (`haystack-reviewer.sh:257`) reads all use it, with no time filter that drops a completed entry. `_pr_agent_trigger_already_pending` returns pending without posting and prints `PR_AGENT_TRIGGER_SKIPPED active_review_in_progress` when a run on `H` is active (`:5504-5513`), and prints `recent_review_trigger` when it reuses a trigger (`:5515-5519`) |

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

`claude-code-action-reviewer.sh` exit 4, `--adopt-run-id` /
`--adopt-requested-at`, and `REVIEW_REQUEST_REF` (new): the only invoker is
the loop handler (V17). The new ledger key `request_ref` has one reader,
`reviewer_loop_rewait_recorded_request` (D11); the existing ledger readers in
the tables above select fields by name and ignore additive keys (T5.3).

New failure reasons `devin_run_failed`, `coderabbit_status_failed`, and
`pr_agent_run_failed` (D8 failure-type completion signals): they are
`escalate` results, so their consumers are the existing escalate consumers.
`reviewer_failed_label_required_for_result` requires the label (every
`escalate` reason except `rate_limited`, D9). `reviewer_loop_platform_outcome_class`
gives `reviewer_failed`, and D10 ranks them 1. `normalize_platform_verdict`
(`:8374-8381`) maps them to `unavailable` through its `*)` arm, and the ledger
normalizer maps `escalate` to `unavailable` (V20). No consumer matches these
names, because they are new. The Haystack companion key
`HAYSTACK_BUDGET_EXPIRED` has one reader, the loop's Haystack exit-2 arm.

`run_with_timeout` expiry semantics (D4 watchdog contract; V23): in
`local-ai-reviewer.sh`, the ordinary review call (`:1314`) reads
`RUN_WITH_TIMEOUT_EXPIRED` instead of the status for the exit-4 decision, and
the strict pass (`:696`) keeps treating any non-zero status as
`strict_pass_failed`; in `coderabbit-cli-reviewer.sh`, both calls
(`:325`, `:328`) feed one `cli_exit` whose `timeout` skip (`:339`) reads the
flag. An early command exit 124 or 137 therefore reaches the existing
non-zero handling in both companions. No other script defines or calls these
two copies (V23).

D15 changed units (V28; consumers found with
`grep -rn '<name>' scripts docs/workflow .github .claude .cursor .codex .agents`
at `44973096`, scripts equal to `13bf4c7f`):

| Unit | Consumer | Outcome after the change |
| --- | --- | --- |
| `_pr_agent_latest_comment_field` (via `_pr_agent_latest_comment` and `_pr_agent_latest_comment_url`) | Phase 1 body and URL (`:5706`, `:5715`, `strict_sha`) | Unchanged |
| same | Phase 2 poll (`:5794`) and its advisory URL (`:5825`), today `recent_or_sha` | New D15 rule (a)/(b) mode; an older head's edited summary, and a first summary that `_pr_agent_first_summary_bound_to_head` cannot bind to a run on the head, no longer end the poll, so Phase 2 keeps polling and expiry reaches the `no_review` kept skip (`:5801-5812`) |
| `_pr_agent_first_summary_bound_to_head` (new) | the Phase 2 matcher's rule (b) only | Only consumer; any failed API read returns "not bound" |
| `codex_inline_review_comment_count_since` | its four callers in `codex-github-reviewer.sh` (`:2278`, `:2492`, `:2622`, `:2778`) | Each counts only comments whose `original_commit_id` is the head; an older head's comment no longer returns `NEEDS_REVISION` there, and the caller falls through to its existing reaction and response checks |
| `claude-code-action-reviewer.sh` review count (`:429-434`) | the loop handler, its only invoker (V17) | The handler always passes `--head-sha`; a run without it (standalone use) keeps today's count |
| `claude-code-action-reviewer.sh` fresh run selection (`:336-353`) and dispatch response (`:277-297`) | the loop handler, its only invoker (V17); the selection tests in `test-claude-code-action-reviewer.sh` that copy the list filter | The run is the dispatch response's `workflow_run_id` (D15 Claude dispatch rule) for standalone and loop use alike; a response without it exits 3, which the loop's existing non-0/1/2/4 arm maps to `escalate`/`unavailable`; the copied-filter tests are replaced (Testing Strategy) |
| `reviewer_loop_head_recorded_request_refs` (new) | Greptile and PR-Agent fresh-mode reuse (D15) | Only consumer; an unavailable ledger yields an empty list, so the handler posts a new request |

**Rule 6 — scoped conditional obligations.**

| Obligation | Governed scope | Discharge point |
| --- | --- | --- |
| Documentation-branch shortening applies (D7) | platforms in D1, source `default`, branches `spec/*` and `implementation-plan/*` | `reviewer_wait_budget_resolve`; tests T1.4–T1.6 |
| Large-diff lengthening applies (D7) | non-documentation branches, no `--max-wait`, changed files above threshold, value below `LARGE_DIFF_MAX_WAIT` | `reviewer_wait_budget_resolve`; test T1.7 |
| Re-wait mode suppresses re-requests (D11) | invocations whose `reviewer_loop_no_verdict_rewait_state` is `rewait`; the request-posting handlers with a changed row in the D11 adoption table (Bugbot, Codex GitHub, Greptile, PR-Agent, CodeRabbit, Claude Code Action); only when `reviewer_loop_rewait_recorded_request` returns a recorded request for that platform (Codex excepted), and further only under that platform's own row conditions in the D11 adoption table (Greptile: a non-empty, readable `request_ref`; Claude: a `request_ref` whose run passes the checks) | each handler's request step; tests T2.12, T4.3–T4.7 |
| A trigger is reused only when recorded for the current head (D15) | fresh-mode (state `fresh` or `untracked`) Greptile and PR-Agent invocations that find a trigger inside their reuse window; re-wait mode is governed by the D11 row above | `run_greptile_review` reuse step and `_pr_agent_recent_trigger_comment_created_at`; tests T2.14, T2.15, T2.18 |
| PR-Agent rule (b) accepts an unedited summary (D15) | Phase 2 polls of `run_pr_agent_review` whose latest summary comment does not contain the head SHA, only when all four rule (b) conditions hold | `_pr_agent_first_summary_bound_to_head`; tests T2.18, T2.22 |
| Claude run is bound by the dispatch response (D15) | every fresh (non-adopting) `claude-code-action-reviewer.sh` dispatch; a response without `workflow_run_id` exits 3 | the companion's Phase 1/2; tests T2.19, T2.23; smoke Step 8 (live response on this host, V31) |
| Bugbot #1390 re-trigger fires (D3) | fresh (non-re-wait) Bugbot runs whose latest current-head check run is not completed at the re-trigger point | `run_bugbot_review`; tests T2.11–T2.12 |
| Runner re-waits (D11) | Step 7 results with `NO_VERDICT_REWAIT=available`, once per head per `PR_REVIEW_LOOP_RUN_ID` | Protocol 91 Step 7 table; tests T4.1–T4.2 and smoke Step 6 |
| A failure-type completion signal is Reviewer failed (D8) | the Devin, CodeRabbit, and PR-Agent handlers and the loop's Haystack exit-2 arm, for a signal on `H` with no verdict bound to `H`, under each row's conditions in the D8 failure-type completion-signal table (Devin: the wait ended on a check or status, including a budget end inside the grace; PR-Agent: the newest run on `H` is failure-type, immediately when this invocation has no outstanding request and at budget end otherwise) | each handler's Phase 3 or poll step and the Haystack exit-2 arm; tests T2.24–T2.27 |
| Label required (D9) | each invocation that reaches the post-loop path; per-platform failure evidence or a loop-level escalation in that invocation | `reviewer_loop_reconcile_reviewer_failed_label`; tests T3.1–T3.6 |

**Rule 1** fires once: D15's PR-Agent rule (a) relies on the summary
comment body containing the current head SHA. V30 is the sampling record
(producer, population, window, 30 located occurrences, two variants, no new
variant, adequacy rationale), and D15 states the tolerant behavior for a body
outside those variants. No other design matches vendor free text. D4
deliberately does not inspect a stopped reviewer's partial output; the Bugbot
and Claude Code Action changes key on GitHub API enumerated fields
(check-run and workflow-run `status`/`conclusion`), not on prose; the other
D15 bindings key on API fields (`commit_id`, `original_commit_id`,
check-run and workflow-run `status`, `started_at`, `completed_at`,
`run_started_at`, `updated_at`, and `head_sha`, comment `created_at` and
`updated_at`, and the dispatch response's `workflow_run_id`); adoption reads
the request id and time this loop recorded in its own ledger (D11).

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
  arm → `print_no_verdict_yet` with the companion reason as detail only for
  the D8 Haystack row's budget-expiry reasons, keeping `escalate` for
  `check_run_<conclusion>` and for `pending_check_run` without
  `HAYSTACK_BUDGET_EXPIRED=1`; the D8 failure-type completion signals
  (`REVIEWER_LOOP_FAILED_CHECK_CONCLUSIONS`, `REVIEWER_FAILED_COMPLETION_JQ`,
  Devin `devin_run_failed`, the new `coderabbit_failed_status_count` and
  `coderabbit_status_failed`, PR-Agent's outstanding-request flag,
  `_pr_agent_failed_review_check_conclusion`, and `pr_agent_run_failed`);
  `run_local_ai_reviewer_review` and `run_claude_code_action_review` gain an
  exit-4 arm; Claude's exit-2 arm reason becomes
  `claude_code_action_run_failed`; Bugbot's `timed_out` conclusion reason
  becomes `bugbot-run-timed-out`; Bugbot's budget bounds both attempts with
  the D3 re-trigger point; request-posting handlers print
  `REVIEW_REQUESTED_AT` and, where D12 says so, `REVIEW_REQUEST_REF`;
  `run_claude_code_action_review` captures the companion's stdout instead of
  discarding it and forwards those two keys (D12).
- [ ] Current-revision binding (D15): `reviewer_loop_head_recorded_request_refs`
  and its hand-off with `loop_head_sha` to the Greptile and PR-Agent
  handlers; each `pr-review-loop.sh` row of the D15 binding enumeration
  (Greptile, Devin, CodeRabbit, PR-Agent, Bugbot), including the PR-Agent
  rule (a)/(b) matcher and `_pr_agent_first_summary_bound_to_head`;
  `run_claude_code_action_review` passes `--head-sha "$loop_head_sha"`.
- [ ] `reviewer_failed_label_required_for_result` (D9) and new
  `reviewer_loop_reconcile_reviewer_failed_label`, called from the post-loop
  path.
- [ ] `reviewer_loop_precedence_select` (D10) used by the compare-mode
  aggregate restore; update the `--compare` help text.
- [ ] `reviewer_loop_no_verdict_rewait_state`, `reviewer_loop_rewait_mode`,
  `reviewer_loop_rewait_recorded_request` and the per-handler adoption of the
  recorded request (D11 adoption table), the `NO_VERDICT_REWAIT` /
  `PENDING_REVIEW_*` / `NO_FAILURE_DETECTED` keys, and `--max-retriggers 0`
  for Codex in re-wait mode (D5, D11).
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

- [ ] `scripts/development-workflow/local-ai-reviewer.sh`: D4 watchdog
  contract in `run_with_timeout` (`RUN_WITH_TIMEOUT_EXPIRED`, GNU branch
  removed, alive check at the deadline); the `:1321` branch tests the flag
  instead of the status and exits 4; usage text lists exit 4.
- [ ] `scripts/development-workflow/coderabbit-cli-reviewer.sh`: replace its
  own `run_with_timeout` (`:289-314`) with the local reviewer's process-group
  watchdog plus the D4 flag (GNU branch removed, new process group,
  TERM-grace-KILL to the group, alive check at the deadline); the `:339`
  `timeout` skip tests the flag instead of status 124.
- [ ] `scripts/development-workflow/claude-code-action-reviewer.sh`: exit 4
  when no run completed within the budget; `--adopt-run-id` and
  `--adopt-requested-at` flags with the D11 run checks and preserved
  review-fetch boundary; print `REVIEW_REQUESTED_AT` and
  `REVIEW_REQUEST_REF` (D12); `--head-sha` and its review `commit_id` term,
  and fresh run binding by the dispatch response's `workflow_run_id` (the
  dispatch sends `return_run_details=true`) with the run-list search and
  `POLL_AFTER_TIME` removed (D15 Claude dispatch rule);
  usage and exit-code header comment updated.
- [ ] `scripts/development-workflow/codex-github-reviewer.sh`: print
  `REVIEW_REQUESTED_AT=$TRIGGER_TIME` from `emit_reviewed_head_if_known` and
  on the pending exit when a trigger time is known;
  `codex_inline_review_comment_count_since` filters on `original_commit_id`
  (D15); no other verdict-logic change.
- [ ] `scripts/development-workflow/haystack-reviewer.sh`:
  `emit_check_run_fallback_or_skip` takes the `after_budget` argument from
  the `timeout` and `pending_timeout` paths and prints
  `HAYSTACK_BUDGET_EXPIRED=1` when the check run is still pending there
  (D8 failure-type completion signals); every conclusion arm is unchanged.
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
`--area 1789`); `test-local-ai-reviewer.sh` and
`test-coderabbit-cli-reviewer.sh` for D4;
`test-claude-code-action-reviewer.sh` for the companion exit 4 and adoption;
`test-haystack-reviewer.sh` for the `HAYSTACK_BUDGET_EXPIRED` key.
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
| T2.5 | Older-revision evidence only (Bugbot completed check on another SHA; Copilot review on another `commit_id`) → No verdict yet, never clean or failed; T2.14–T2.23 cover the D15 changes | AC-10 |
| T2.6 | Availability reasons in `REVIEWER_LOOP_AVAILABILITY_REASONS` keep result, reason, exit code, and label decision; Bugbot "disabled" self-report and Copilot request failure keep their existing failure handling | AC-13 |
| T2.7 | `local-ai-reviewer.sh` with a command that sleeps past `--timeout`: exit 4 and the D4 keys; commands exiting 1, 124, and 137 immediately with a 30 s budget, and unreadable output, keep `escalate` (never exit 4); `coderabbit-cli-reviewer.sh` with a CLI that exits 124 immediately reports `no_output`, not the `timeout` kept skip, and one that sleeps past the budget reports the kept skip (extend `test-coderabbit-cli-reviewer.sh`) | AC-1, AC-2 |
| T2.13 | `run_with_timeout` unit (both companions): early `exit 124` and `exit 137` → status forwarded and `RUN_WITH_TIMEOUT_EXPIRED=0`; command sleeping past the budget → `RUN_WITH_TIMEOUT_EXPIRED=1`; command finishing inside the final poll second → its own status and flag `0`; for the CodeRabbit CLI copy, a CLI that leaves a background descendant and one that ignores `TERM` are both gone and the wrapper returns within the budget plus the 2 s grace (the local reviewer's existing `fallback_timeout_kills_*` and `fallback_timeout_ignores_term_*` cases, mirrored) | AC-1, AC-2 |
| T2.14 | **Regression — a previous-head request answers after the new-head invocation begins** (Greptile, D15): a trigger `T0` posted for head `H0` sits inside the `max_wait` reuse window and no ledger record holds it for `H1`; the invocation on `H1` posts `T1` instead of reusing `T0`; the mock then adds the bot thumbs-up to `T0` and a Greptile review comment with `original_commit_id` `H0` (and `commit_id` moved to `H1`) created after `T1`. With no thumbs-up on `T1` by the budget → No verdict yet `no_acknowledgement`, never clean or `needs_fixes`, and the printed `REVIEW_REQUEST_REF` is `T1`'s id. Variant: `T1` is thumbs-upped too → `clean`, the `H0` comment not counted; with an `H1` comment as well → `needs_fixes` listing only the `H1` finding | AC-10 |
| T2.15 | Greptile fresh-mode reuse (D15): an age-window trigger whose id the helper lists for `H1` (recorded by another run) is reused with no post; the same trigger recorded only for `H0` is not reused; an unavailable ledger posts a new trigger; no `loop_head_sha` and an empty `.head.sha` → `escalate`/`head-sha-unavailable` with no post | AC-10, AC-11 |
| T2.16 | Review-comment drift (D15): Bugbot, Devin, and CodeRabbit collection paths and the Greptile, Devin, and CodeRabbit pre-trigger findings each ignore a bot comment with `commit_id` `H1` but `original_commit_id` `H0` created after the time filter, and count one with `original_commit_id` `H1`; `codex_inline_review_comment_count_since` returns 0 for the drifted comment, so the companion does not return `NEEDS_REVISION` | AC-10 |
| T2.17 | Completion signals (D15): a Devin summary review with `commit_id` `H0` submitted after the committer time does not end the wait (expiry → D8 Devin row); a CodeRabbit review with `commit_id` `H0` does not end the wait; a walkthrough comment edited after the committer time with no `H1` review and no success status keeps polling and expires as No verdict yet `review_not_submitted`; a CodeRabbit success status on `H1` ends the wait | AC-10 |
| T2.18 | PR-Agent (D15): a summary edited after the committer time whose body names `H0` is not accepted (expiry → `no_review` kept skip); one naming `H1` is accepted; an unedited summary created inside a completed `PR-Agent review` check run window on `H1`, with no active check run on `H1`, no overlapping branch run on another head, and no earlier `/review`, is accepted (the V32 shape); each single failed rule (b) condition — edited, outside the window, a window run on `H1` that concluded `failure` or `cancelled` instead of `success`, an active `H1` check run, an overlapping branch run on `H0`, an earlier `/review`, or a failing check-run or run-list read — leaves it unaccepted; a `/review` trigger inside the reuse window that the helper does not list for `H1` does not suppress the new request | AC-10 |
| T2.19 | `claude-code-action-reviewer.sh --head-sha H1`: a `CHANGES_REQUESTED` review with `commit_id` `H0` submitted after `DISPATCH_TIME` is not counted, so a completed `success` run returns clean; the same review with `commit_id` `H1` returns findings; without `--head-sha` today's count is kept; the loop handler passes `--head-sha` | AC-10 |
| T2.20 | Unresolved older-revision Greptile thread dropped by the D15 pre-trigger filter still makes the aggregate `needs_fixes`/`unresolved_review_threads` through the aggregate thread audit when Greptile is otherwise clean | AC-10 |
| T2.21 | `reviewer_loop_head_recorded_request_refs`: records under `H` from two runs (one waiting, one clean) → both refs; a `wait_start` record, an empty ref, another head, or another platform → not listed; unavailable ledger → nothing | AC-10 |
| T2.22 | **Regression — a delayed older-head PR-Agent first summary arrives after the current request** (D15 rule (b)): the PR has no summary; the `H1` invocation starts while the `H1` `pull_request` check run (the push's own review request) is in progress, so it posts no `/review` and polls; a `pull_request` run on `H0` that started before the push is still running; an unedited, marker-free summary is then created while both runs are in progress, and the `H1` run completes after it, so the comment lies inside a completed `H1` window. It is not accepted (another revision's run overlapped), and with no further comment by the budget the result is the `no_review` kept skip, never clean or `needs_fixes`. Variant: no overlapping `H0` run, but the invocation posted its `/review` request before the summary was created — not accepted, because a `/review` predates it; when the mock then edits the summary to carry the `H1` marker, rule (a) accepts it | AC-10 |
| T2.23 | **Regression — an older completed Claude run inside the dispatch window** (D15 Claude dispatch rule): the runs list holds a completed `success` run for this PR created 5 s before `DISPATCH_TIME` (inside the old 10 s window) and no blocking review; the mock dispatch response returns `workflow_run_id` of a different run that stays `in_progress`. The companion polls only the returned id, never reads the list (the mock `gh` log has no `actions/runs?event=` call), and exits 4 at the budget, never 0. The mock `gh` log shows the dispatch request carries `return_run_details=true`. Variants: the returned run completes `success` → exit 0; a dispatch response without `workflow_run_id` (empty `204` body) → exit 3 with the D15 message and no polling | AC-10 |
| T2.24 | **Regression — a timed-out Devin check with no findings** (D8 failure-type completion signals): the Devin check run on `H` completes `timed_out`, no Devin completion review and no finding bound to `H` appear, and the grace elapses → `escalate`/`devin_run_failed`, `reviewer_failed_required` set and the label required, never `clean`. Variants: a Devin status in `error` with no findings → the same; a `failure` check with an `H`-bound finding → `needs_fixes`; a bound "No Issues Found" review plus a `timed_out` check → today's clean verdict; a `success` check with no findings → `clean` as today; the budget ends inside the 120 s grace after a `timed_out` check with no findings → `escalate`/`devin_run_failed`, never No verdict yet | AC-2, AC-8 |
| T2.25 | CodeRabbit failure status (D8 failure-type completion signals): a CodeRabbit status on `H` in `failure` (and one in `error`) with no `H`-bound review or finding ends the wait and returns `escalate`/`coderabbit_status_failed` with the label required; with an `H`-bound finding → `needs_fixes`; a `failure` status whose description matches the #1437 rate/review-limit pattern is not counted, and the rate-limit path's outcome is unchanged | AC-2, AC-13 |
| T2.26 | PR-Agent failed run (D8 failure-type completion signals): Phase 1 finds a `PR-Agent review` run on `H` in progress (no `/review` posted), and it then completes `cancelled` (and, separately, `timed_out`) with no bound summary → `escalate`/`pr_agent_run_failed` on that poll and the label required. **Regression — a run on `H` that already completed `timed_out` before Phase 1** (the finding at `b92b4ee9`): the handler posts `/review`, no newer run on `H` and no bound summary appear, and the result at the budget is `escalate`/`pr_agent_run_failed`, never the kept skip; before the budget no poll returns. The same in re-wait mode with an adopted recorded request (no post) → `pr_agent_run_failed` at the budget; and in re-wait mode with an adopted recorded request while a run on `H` is active at the pending check and then completes `cancelled` → no poll returns before the budget, `pr_agent_run_failed` at the budget. Supersession variants for the pre-failed run: a newer `PR-Agent review` run on `H` (later `started_at` and higher `id`) appears `in_progress` and completes `success` with no bound summary → the `no_review` kept skip; the summary is then edited to carry the `H` marker → rule (a) verdict; a failure-type `/review` (`issue_comment`) run on the default-branch tip is never read as failure. A per-poll read that fails on every poll gives the kept skip; one failing poll after a failure-type read keeps `pr_agent_run_failed` at the budget | AC-2, AC-8 |
| T2.27 | Haystack exit-2 arm: companion exit 2 with `check_run_timed_out` or `check_run_cancelled` → `escalate` with that reason and the label required, never No verdict yet; `pending_check_run` with `HAYSTACK_BUDGET_EXPIRED=1` → No verdict yet; `pending_check_run` without the key → `escalate` as today. In `test-haystack-reviewer.sh`, the `timeout` and `pending_timeout` paths whose fallback check run is pending print the key, and the CLI-missing path does not | AC-1, AC-2 |
| T2.8 | `claude-code-action-reviewer.sh`: run never completes → exit 4; completed `failure` → exit 2; loop maps 4 and 2 per D8 | AC-1, AC-2 |
| T2.9 | Second local pass returning waiting → aggregate waiting, no `failed_for_head` record | AC-1 |
| T2.10 | Ledger normalization `no_verdict_yet` for a waiting record and for a kept skip recorded through `reviewer_loop_process_platform_output` (the `platform_result_records` entry, not only the normalizer called directly); `apply-readiness-labels.sh` refuses it as `reviewer-check-absent` (extend `test-apply-readiness-labels.sh`) | AC-1 |
| T2.11 | Bugbot fresh run: no completed run by the D3 re-trigger point → exactly one re-trigger, total wait bounded by the budget | AC-3, AC-6 |
| T2.12 | Bugbot re-wait mode with a recorded request: adopts the recorded trigger comment, posts no comment, and prints the recorded `REVIEW_REQUESTED_AT` and `REVIEW_REQUEST_REF` unchanged (D12 carry-forward), so a third invocation with the same run id and head adopts the same comment; a recorded request with an empty `request_ref` also posts no comment | AC-11 |
| T3.1 | Reconcile: PR carries `reviewer-failed`, run re-reviews and is clean → `--remove-label` issued | AC-7 |
| T3.2 | Reconcile: same, but every platform replayed from a clean ledger (#1692) → `--remove-label` issued | AC-7 |
| T3.3 | Reconcile: needs-fixes or waiting run with no failure evidence → label removed / not added | AC-8 |
| T3.4 | Reconcile: mixed compare run, one failed platform plus one clean, and a needs-fixes run with a `skipped`/`unavailable` peer → label added | AC-8 |
| T3.5 | Add/remove failure prints the WARN and does not change the exit code | AC-8 |
| T3.6 | Source-order check: the post-loop path calls the reconcile function once after the persistence step; pre-loop refusal exits do not | AC-7, AC-13 |
| T3.7 | Precedence function: failed + waiting → escalate; findings + waiting → needs_fixes; waiting + clean → waiting; kept skip + clean → clean; tie → earliest platform | AC-9 |
| T3.8 | Compare-mode aggregate uses the precedence function | AC-9 |
| T4.1 | Re-wait state: no prior entry → `fresh` and `NO_VERDICT_REWAIT=available`; prior waiting entry same run and head → `rewait` and `used`; other head or other run → `fresh`; unset run id or unavailable ledger → `untracked`; state `fresh` with a failing `_post_review_summary` (mock comment write fails) → `NO_VERDICT_REWAIT=untracked`, not `available` | AC-11 |
| T4.2 | A re-wait entry adds nothing to the cycle counts (`reviewer_loop_history_entries_count` unchanged) | AC-11 |
| T4.3 | Codex in re-wait mode receives `--max-retriggers 0` | AC-11 |
| T4.4 | Greptile and PR-Agent in re-wait mode reuse the recorded trigger comment and print its recorded `REVIEW_REQUESTED_AT` and `REVIEW_REQUEST_REF` (D12 carry-forward); PR-Agent with a recorded request whose `request_ref` is empty still posts nothing; Greptile with an empty `request_ref` or a recorded comment whose reactions read fails (mock 404) prints the D11 `WARN` and posts once; CodeRabbit posts no conditional re-trigger; with no recorded request each posts as in a fresh run and logs the D11 `INFO` line | AC-11 |
| T4.5 | Claude companion with `--adopt-run-id`/`--adopt-requested-at`: polls only that run and does not dispatch; a bot review submitted before the recorded `requested_at` is not counted (boundary preserved); a completed `success` run for this PR that is **not** the recorded run and was created after the head commit's committer time (an older-head run) is never read, so the result follows the recorded run (still running → exit 4, never clean); a recorded run whose `path` or `PR #<n>` does not match is not adopted and the companion dispatches | AC-10, AC-11 |
| T4.6 | `reviewer_loop_rewait_recorded_request`: matching run, head, waiting entry, and platform with source `request` → `RECORDED_REQUEST_REF` and `RECORDED_REQUESTED_AT` lines; a record with an empty ref → an empty `RECORDED_REQUEST_REF` line and the time intact in `RECORDED_REQUESTED_AT`; other head, other run, `wait_start` source, or no platform record → nothing; Bugbot outside re-wait mode posts its own trigger even when a `bugbot run` comment newer than the head commit time exists | AC-10, AC-11 |
| T4.7 | Loop-side Claude handler with a mock companion: a fresh run that exits 4 after printing `REVIEW_REQUESTED_AT` and `REVIEW_REQUEST_REF` yields `PLATFORM_<n>_REQUEST_REF` and a ledger `request_ref`; the following re-wait invocation (same run id and head) passes `--adopt-run-id`/`--adopt-requested-at` with those values, and its own ledger record carries the same `request_ref` and `requested_at`; with only a recorded `requested_at` it passes neither | AC-11, AC-12 |
| T5.1 | Timing keys for a verdict, a No verdict yet, a skip, a failure, and a replay; `REQUESTED_AT_SOURCE` `request` vs `wait_start`; `REQUEST_REF` printed and recorded only when the handler printed one | AC-12 |
| T5.2 | Summary "Reviewer timing" section lines and the `reviewer-no-verdict-yet` result line; reused marked reused | AC-12 |
| T5.3 | Ledger `platform_results[]` additive fields present; existing readers (`reviewer_loop_platform_clean_for_head`, #1692) still pass | AC-12 |
| T5.4 | Waiting aggregate prints `PENDING_REVIEWER`, `PENDING_REVIEW_HEAD_SHA`, `PENDING_REVIEW_REQUESTED_AT`, `PENDING_REVIEW_WAITED_SECONDS`, `NO_FAILURE_DETECTED=1` | AC-1, AC-11 |
| T6.1 | Documentation assertions: Protocol 93 contains the canonical section headings and the D2 table; Protocol 91's Step 7 table contains every D11 runner row; each guide in Documentation Updates names `reviewer-no-verdict-yet` or the kept skip | AC-14 |

Existing tests whose expectations change and must be updated in the same
commit as the behavior: Area 12 rows `reviewer_failed_escalate_timeout`
(input becomes a failure-only reason) and the `skipped timeout` expectation;
Area 0b Codex-defaults rows (`codex_github_defaults_should_apply` no longer
drives a global budget); Area 16 Bugbot timeout and unavailable rows; the
Copilot (Area 8), Haystack (Area 9), Devin, Ronda, Greptile, and CodeRabbit
timeout rows; compare-mode first-blocking rows (Area 3/compare). The
implementer runs `grep -n "REASON timeout\|=timeout\|no_check_run\|no_review\|first blocking" scripts/development-workflow/tests/test-pr-review-loop.sh`
and confirms each hit is either updated or still correct. For D15, mock
review comments that carry only `commit_id` gain a matching
`original_commit_id`, mock reviews and Devin/CodeRabbit completion reviews
gain `commit_id` equal to the mocked head, and PR-Agent Phase 2 mocks that
relied on `recent_or_sha` (a summary without the head SHA) are rewritten to
D15 rule (a) or (b), with rule (b) mocks supplying the check-run, check-suite,
and branch-run responses. In `test-claude-code-action-reviewer.sh`, the
run-selection tests that copy the companion's list filter (`POLL_AFTER_TIME`,
`PR #<n>` name scoping, newest `created_at`) test a filter the fresh path no
longer has; they are replaced by T2.23's dispatch-response cases (the
`PR #<n>` and `path` checks stay covered by T4.5's adoption checks), and
every mock dispatch returns a `workflow_run_id` body. The implementer runs
`grep -n "commit_id\|original_commit_id\|PR Reviewer Guide\|@greptile review" scripts/development-workflow/tests/test-pr-review-loop.sh scripts/development-workflow/tests/test-claude-code-action-reviewer.sh`
and confirms each mock still expresses the case it was written for. In
`test-local-ai-reviewer.sh`, the D4 change also moves `timeout_result` /
`timeout_reason` and the `fallback_timeout_*_result` / `_reason` rows from
`escalate`/`timeout` to the exit-4 No verdict yet keys (the grandchild-kill
and bounded-time assertions stay), and removes the two rows that pin the GNU
branch: `timeout_kill_after_137_*` (a fake `timeout` on `PATH`, no longer
consulted) and `s9d_gnu_timeout_has_kill_after` (asserts the removed
`timeout --kill-after=2s` line). In `test-coderabbit-cli-reviewer.sh`, the
restricted `NO_CLI_BIN` PATH gains `perl` (and `setsid` where the host has
it): the replaced CodeRabbit CLI wrapper, like the local reviewer's, starts
the CLI through `setsid` or `perl setpgrp`, and that PATH provides neither,
so without the addition the wrapper's launch exits 127 and the
`fallback_timeout_*` rows (expected `skipped`/`timeout`) and the
`fallback_coderabbit_*` rows (expected `clean`) both read `no_output`
instead (V26). Their expected values are otherwise unchanged.

**Regression suites to run before pushing**: `test-pr-review-loop.sh`,
`test-local-ai-reviewer.sh`, `test-local-ai-reviewer-pr-review-loop-dispatch.sh`,
`test-local-codex-review-command.sh` (its #1843 stdin probes run
`local-ai-reviewer.sh` through `run_with_timeout`),
`test-coderabbit-cli-reviewer.sh`, `test-coderabbit-cli-pr-review-loop-dispatch.sh`,
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
listener, callback, or timer runs concurrently with another. The one
watchdog-versus-process race, a local reviewer exiting in the same second its
budget ends, is settled inside `run_with_timeout` by the alive check at the
deadline (D4), and nothing else shares state with the child process. Two loop
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
| Positive failure evidence | D8 kept failure paths, including an early command exit 124/137 (D4) and the failure-type completion signals; D9 label | Protocol 93, Protocol 91 Step 7, guides | T2.3, T2.7, T2.13, T2.24–T2.27 |
| Budget ran out, first time for this revision | D8 No verdict yet (local reviewers: D4 watchdog flag); D11 `available` → runner re-wait | Protocol 91 Step 7, Protocol 93, guides | T2.1, T2.7, T2.13, T4.1 |
| Expired wait kept as non-blocking skip | D8 kept skips; D9 no label | Protocol 93, CodeRabbit, Devin, PR-Agent guides | T2.4 |
| No verdict yet again after re-wait | D11 `used` → runner stops as Waiting on reviewer | Protocol 91 Step 7, Protocol 93 | T4.1, smoke Step 6 |
| Only older-revision evidence | D15 bindings for every platform → No verdict yet (D8) or, for PR-Agent, its kept skip; fresh-mode reuse and re-wait adoption bound to a request recorded for the current head (D15, D11); PR-Agent summaries by D15 rules (a) and (b); fresh Claude runs by the D15 Claude dispatch rule | Protocol 93, Greptile, Devin, CodeRabbit, PR-Agent, Bugbot, Codex GitHub, and Claude Code Action guides | T2.5, T2.14–T2.23, T4.5, T4.6 |
| No sign of a started review, no unavailability report | D8 Bugbot `check_not_started`, Devin kept skip | Protocol 93, Bugbot guide | T2.1, T2.4 |
| Platform reports itself unavailable | D8 kept failure paths (Bugbot disabled, Copilot request failure, Haystack `unavailable`) | guides | T2.6 |
| Platform's own run timed out or failed | D8 failure-type completion signals for every platform: `devin_run_failed`, `coderabbit_status_failed`, `pr_agent_run_failed` (new), Haystack `check_run_<conclusion>` kept as failure, `bugbot-run-timed-out`, `claude_code_action_run_failed`, `ronda_pass_failed`, `ronda_unexpected_conclusion`; a bound verdict wins over the signal | Bugbot, Claude Code Action, Ronda, Devin, CodeRabbit, PR-Agent, Haystack guides | T2.3, T2.8, T2.24–T2.27 |
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
   (D8) and rank 1 (D10); a `waiting_on_reviewer` result with an absent or
   unknown `NO_VERDICT_REWAIT` has its own D11 runner row (treated as
   `untracked`); a fresh state whose waiting entry could not be persisted
   prints `untracked`, not `available` (D11). A completed check run, commit
   status, or workflow run with a failure-type conclusion maps to Reviewer
   failed on every platform whose completion signal it is, unless a verdict
   bound to the head or the platform's own verdict contract applies (D8
   failure-type completion signals, V33), including a Devin budget end inside
   the post-completion grace, a PR-Agent invocation that posted, reused, or
   adopted a request (decided at budget end), and one whose check-run read
   failed (the last successful read stands). PR-Agent rule (b) binds only to a
   `success` run (D15). Claude run selection has a
   binding for both paths: fresh dispatch by the D15 Claude dispatch rule,
   including the response-without-run-id state, and re-wait adoption by D11.
3. Precedence / order — pass: D7 states override → configured → default then
   adjustments; D10 states ranks and tie-break; loop-level escalations stay
   after platform aggregation.
4. Malformed / unknown input — pass: D6 and D13 define invalid budget
   handling; unreadable ledger → `untracked`; the recorded-request lookup
   prints key lines so an empty `request_ref` cannot shift fields, and each
   D11 adoption row states what happens with an empty or unreadable
   `request_ref` (Bugbot and PR-Agent still adopt, Greptile and Claude post
   or dispatch afresh).
5. Stale vs current evidence — pass: D15 binds every platform's verdict,
   finding, and completion evidence to the loop head by commit field, by
   `commits/<head>` endpoint, by a request recorded for that head, by a run
   on that head with no other revision's run overlapping (PR-Agent rule (b)),
   or by the run id of this invocation's own dispatch (Claude), and reuses a
   trigger in fresh mode only when it is recorded for that head; D11 keys
   re-wait state on `loop_head_sha` and `run_id`, and adopts only the request
   recorded for that head and run. No binding rests on comparing a comment,
   review, or run time with a request time or with the head commit's
   committer time; the time filters that remain (Greptile's, Devin's, and
   CodeRabbit's collection windows, Claude's `DISPATCH_TIME` review boundary)
   only narrow evidence a commit field already binds. Failure evidence is
   stale only when positive evidence on the same head supersedes it: the
   newest check run or status per key on `H` governs on every platform that
   reads one (`dedupe_status_check_rollup`, V35), and no handler excludes a
   failure-type run on `H` because it completed before the invocation or
   before a request (PR-Agent: D8 failure-type completion-signal row). Where
   the binding cannot be established, the outcome is No verdict yet, a kept
   skip, or a failure, never clean.
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
  contract, D12 timing keys, the D15 current-revision binding table (evidence
  kinds only; per-platform detail lives in the guides below), and the rule
  that a run's worst-case wait is the
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
  — Step 7 result table: the D11 runner rows replacing the single
  `waiting_on_reviewer` row; the settle-forward snippet's non-zero branch
  mentions re-wait for exit 4 with `NO_VERDICT_REWAIT=available`.
- [ ] `docs/workflow/development-workflow/integrations/bugbot.md` — D3 budget
  and re-trigger point, No verdict yet vs `bugbot-run-timed-out`, adoption;
  findings read by `original_commit_id` (D15).
- [ ] `docs/workflow/development-workflow/integrations/greptile.md` — timeout
  row → No verdict yet; re-wait trigger reuse; fresh-mode reuse only of a
  trigger recorded for the current head, findings bound to the current head,
  and `head-sha-unavailable` (D15).
- [ ] `docs/workflow/development-workflow/integrations/devin.md` — timeout row
  → No verdict yet; `no_check_run` kept skip; D1 documentation-branch budget;
  completion review and findings bound to the current head (D15); a failed,
  timed-out, or cancelled Devin check, or an `error`/`failure` status, with
  no findings is `devin_run_failed` (D8 failure-type completion signals).
- [ ] `docs/workflow/development-workflow/integrations/coderabbit.md` — App
  timeout row → No verdict yet, `no_review` kept skip; CLI `timeout` kept skip
  without `reviewer-failed`; the App wait ends only on a current-head review
  or success status, not on a walkthrough edit alone (D15); a `failure` or
  `error` CodeRabbit status that is not a rate/review-limit notice is
  `coderabbit_status_failed` (D8 failure-type completion signals).
- [ ] `docs/workflow/development-workflow/integrations/copilot.md` — timeout
  row → No verdict yet.
- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — wait
  reasons are in the No verdict yet class; re-wait with `--max-retriggers 0`;
  budget source wording for `CODEX_GITHUB_MAX_WAIT`; inline comments counted
  by `original_commit_id` (D15).
- [ ] `docs/workflow/development-workflow/integrations/claude-code-action.md`
  — exit-code table (new exit 4), `claude_code_action_run_failed`, the
  `--adopt-run-id` / `--adopt-requested-at` flags and the D11 rule that only
  the recorded run for the current head is adopted; `--head-sha` and the
  dispatch-response run binding (the dispatch requests `return_run_details`),
  including exit 3 when the host returns no run id (D15).
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` and
  `docs/workflow/development-workflow/integrations/haystack.md` — correct the
  stale "skipped / continue / apply `reviewer-failed`" text for `timeout` and
  `pending_timeout`: they are No verdict yet and stop as waiting, as is a
  check run still pending when the budget ends; a check run that concluded
  `timed_out`, `cancelled`, or `stale` stays a failure (D8 failure-type
  completion signals).
- [ ] `docs/workflow/development-workflow/integrations/local-ai-reviewer.md` —
  D4 budget, exit 4 (only when the watchdog stopped a still-running
  reviewer; a command's own early exit 124/137 is a failure), timeout table
  rows.
- [ ] `docs/workflow/development-workflow/integrations/pr-agent.md` —
  `no_review` kept skip reported as No verdict yet; which summary comment
  counts for the current head (D15 rules (a) and (b), including why a first
  summary can end in the kept skip) and when a `/review` trigger is reused
  (D15); when the newest `PR-Agent review` run on the head failed, timed
  out, or was cancelled and no summary is bound to the head, the result is
  `pr_agent_run_failed`, at budget end when the loop's own request is
  outstanding, while a failed `/review` run alone cannot be tied to the head
  (D8 failure-type completion-signal row).
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
| Adoption of an old trigger hides a request the vendor silently dropped | Low | Med | Re-wait adoption takes only the request recorded for the current head and run (D11), fresh-mode reuse only a trigger recorded for the current head inside the existing reuse window (D15), and re-wait mode ends in a named stop; Bugbot keeps its #1390 re-trigger in fresh runs |
| A CodeRabbit review that is clean but posts neither a formal review nor a success status on the head now waits instead of ending on the walkthrough edit (D15) | Low | Med | The rate-limit paths already rely on the success status (`:7491`, `:7607`); the outcome is No verdict yet with the D11 re-wait, never a false clean; the CodeRabbit guide documents it |
| A PR-Agent first summary that rule (b) cannot bind (a `/review` preceded it, another revision's branch run overlapped it, or an API read failed) ends that invocation in the `no_review` kept skip instead of clean | Low | Low | The skip is non-blocking and never a verdict for another revision; any later PR-Agent run on the head adds the head marker that rule (a) accepts (D15); V32 shows all five sampled first summaries bind |
| A GitHub host whose dispatch endpoint returns no `workflow_run_id` even with `return_run_details=true` (for example, an older GitHub Enterprise Server answering `204`) makes Claude Code Action report `unavailable` on every run | Low | Med | The failure names the cause in the companion's `VERDICT` line and never yields clean; the Claude Code Action guide documents the requirement (D15, V31); smoke Step 8 confirms the `200` response on this repository's host before merge, since V31 rests on the REST reference alone |
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
   re-trigger point, the D4 watchdog contract in both `run_with_timeout`
   copies, companion exit 4 for `local-ai-reviewer.sh` and
   `claude-code-action-reviewer.sh`, Rule 5 consumer updates, label-function
   change, the D8 failure-type completion signals (Devin, CodeRabbit,
   PR-Agent, the Haystack exit-2 arm and companion key); T2.1–T2.11, T2.13,
   and T2.24–T2.27; update the existing timeout rows listed in
   Testing Strategy. Run the full `test-pr-review-loop.sh`,
   `test-local-ai-reviewer.sh`, `test-local-codex-review-command.sh`,
   `test-coderabbit-cli-reviewer.sh`,
   `test-claude-code-action-reviewer.sh`, `test-haystack-reviewer.sh`, and
   `test-apply-readiness-labels.sh`.
3. **Phase 3 — Label reconciliation and precedence (D9, D10).** Reconcile
   function and call sites, precedence function and compare-mode use,
   `--compare` help text; T3.1–T3.8.
4. **Phase 4 — Re-wait and timing (D5, D11, D12).** Re-wait state, re-wait
   mode in handlers and companions, waiting output keys, timing capture,
   summary section, ledger fields; T2.12, T4.1–T4.7, T5.1–T5.4.
5. **Phase 5 — Current-revision binding (D15).** After Phase 4, because
   fresh-mode reuse reads the D12 `request_ref` ledger key:
   `reviewer_loop_head_recorded_request_refs`, every row of the D15 binding
   enumeration in `pr-review-loop.sh`, `codex-github-reviewer.sh`, and
   `claude-code-action-reviewer.sh` (including the PR-Agent rule (b) helper
   and the Claude dispatch-response binding), and the D15 mock and test
   updates named in Testing Strategy; T2.14–T2.23. Run the full
   `test-pr-review-loop.sh` and `test-claude-code-action-reviewer.sh`.
6. **Phase 6 — Documentation.** Every item in Documentation Updates, the
   `--help` text, and T6.1. Run
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
   and the `AGENTS.md` markdown lints over the changed documents.
7. **Phase 7 — Changelog fragment.** Add
   `changelog.d/1789.fixed.reviewer-no-verdict-yet.md` with exactly:

   ```markdown
   - **A reviewer that has not answered yet is no longer reported as failed** (#1789):
     the reviewer loop now waits a per-platform budget (Bugbot 2400 s, Codex
     GitHub 1800 s, others 1200 s; configurable under `review.wait_budgets`),
     reports a wait that runs out with no verdict and no failure evidence as
     `waiting_on_reviewer` / `reviewer-no-verdict-yet` instead of escalating,
     re-waits once per revision without re-posting an outstanding review
     request, accepts a verdict only when it is bound to the current
     revision, keeps `reviewer-failed` in step with the latest run (including
     runs that reuse a recorded verdict), and records each platform's budget,
     its source, and its latency in the run output, summary comment, and
     ledger. Bugbot's own timed-out run is now reported as
     `bugbot-run-timed-out`, a failed Claude Code Action run as
     `claude_code_action_run_failed`, a Devin, CodeRabbit, or PR-Agent
     review run that itself failed or timed out is reported as a failed
     reviewer instead of clean or skipped, and `--max-wait` rejects values
     that are not positive whole seconds.
   ```

   The budget values in this literal must match D2 at implementation time;
   if D2 changes, update the literal with it. Run
   `bash scripts/development-workflow/changelog-fragments.sh validate`.
8. **Phase 8 — Verification.** Run every suite listed under "Regression
   suites to run before pushing" and confirm all pass; walk the smoke runbook
   steps that do not need a live vendor (Steps 1–3) and record results in the
   PR. Steps 4–8 run in the smoke-test stage; Step 8 is the only live
   confirmation of the Claude dispatch response (D15, V31).

**Residual verification before readiness**: the implementation PR records,
for each row of the D8 tables (budget-expiry paths and failure-type
completion signals) and the D15 binding table, the test ID that exercises it
(a D15 row whose change is "None" records that no change was made), and the
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
  V1–V35.
- Behavioral guarantees: Checked — "once per revision" cites the ledger
  query keyed on `run_id` and `head_sha` and the persist-success gate on
  `available` (D11); "never shortens" cites the
  D7 comparison; "no duplicate request" cites the D11 adoption table and
  V10, and adoption binds to the recorded request id, time, and head (D11,
  V24, V25), not to the head commit time; "stopped at the budget" cites the
  D4 watchdog flag and V23, not the wrapper's exit status; "older-revision
  evidence is never an answer" cites the D15 per-platform binding table
  (V28), the review-comment `commit_id` drift (V29), PR-Agent rule (b)'s run
  binding (V32), the Claude dispatch-response run id (V31), and the
  regression tests T2.14, T2.22, and T2.23; "a platform's own failed run is
  Reviewer failed on every platform" cites the D8 failure-type
  completion-signal table (V33), rule (b)'s `success` requirement (V34), the
  newest-run-on-the-head ordering that keeps an earlier failure in force
  until a newer run on that head or a bound verdict supersedes it (V35), and
  the regression tests T2.24–T2.27.
- Complex workflow decision-gate matrix: Checked — plan mirror table above.
- Matrix coherence preflight: Checked — six checks pass (see the preflight
  list above).
- Parser/API/concurrency checklist: Checked — parser-risk addendum for the
  config reader; concurrency not applicable with rationale.
- CHANGELOG literal format: Checked — Phase 7 literal uses the
  `**Bold Title** (#1789):` form.

| Rule | Outcome | Rationale |
| --- | --- | --- |
| Rule 1 | Satisfied | D15's PR-Agent rule (a) depends on the summary body naming the head SHA; V30 records 30 located occurrences, two variants, and the adequacy rationale, and D15 states the tolerant path (see Factual claim evidence). Rule (b) reads no body text; its run binding is checked against the five marker-free variant occurrences in V32. |
| Rule 2 | Satisfied | Values and decisions are asserted once in D1–D15 and referenced elsewhere. |
| Rule 3 | Satisfied | Platform count (V1) and emit-site enumeration (V2) carry commands, revision, and population; the D8 binding table carries the enumeration. The D15 site counts (four Bugbot review-comment filters, four `codex_inline_review_comment_count_since` callers) carry V28's commands and their enumerated line numbers. The D8 failure-type completion-signal table covers all twelve platforms from V33's recorded search (loop hits by handler and companion counts). |
| Rule 4 | Satisfied | Existence and absence claims cite V3–V6, V8–V11, V14, V15, V17, V19, V20, V22–V29, V31–V35; which handlers read a failure-type completion signal, and which read none, is V33; the V32 binding runs' `success` conclusions are V34; the newest-run ordering on one head, the absence of a completed-run time filter in every handler that reads check runs or statuses, and PR-Agent's no-post path are V35; the "already head-bound" and "not head-bound" claims for every platform are V28, row by row in the D15 binding table; the dispatch response's `workflow_run_id` and the dispatched run's `head_sha` are V31 (the response shape from the REST reference, confirmed live by smoke Step 8); the PR-Agent run-window, branch-run, and `issue_comment` run fields are V32; the platform state-notice readers D15 leaves unchanged carry their own recorded search in D15. |
| Rule 5 | Satisfied | Consumer tables for the label function, the waiting result and the normalized ledger outcome, the global budget, both companion exit codes, `run_with_timeout` expiry semantics in both reviewer companions, the loop handler that consumes the Claude companion's new output keys, and the D15 changed units (`_pr_agent_latest_comment_field`, the new `_pr_agent_first_summary_bound_to_head`, `codex_inline_review_comment_count_since`, the Claude companion review count and its fresh run selection and dispatch response, the new head-recorded request helper), and the new failure reasons and Haystack companion key from the D8 failure-type completion signals (V12, V13, V17, V19, V20, V21, V23, V24, V28, V31, V33). |
| Rule 6 | Satisfied | Rule 6 table names scope and discharge for every conditional obligation. |
