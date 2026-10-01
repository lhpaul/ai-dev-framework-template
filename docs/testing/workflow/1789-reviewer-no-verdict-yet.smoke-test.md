# Smoke Test Runbook: A Reviewer That Has Not Answered Yet Is Not a Failed Reviewer

**Feature**: Per-platform wait budgets, the No verdict yet outcome, label reconciliation, and latency recording for the automated reviewer loop
**Spec**: [`docs/specs/developments/20260930224945_1789-reviewer-no-verdict-yet/1_1789-reviewer-no-verdict-yet_specs.md`](../../specs/developments/20260930224945_1789-reviewer-no-verdict-yet/1_1789-reviewer-no-verdict-yet_specs.md)
**Plan**: [`docs/specs/developments/20260930224945_1789-reviewer-no-verdict-yet/2_1789-reviewer-no-verdict-yet_implementation-plan.md`](../../specs/developments/20260930224945_1789-reviewer-no-verdict-yet/2_1789-reviewer-no-verdict-yet_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Scope of this smoke test

Steps 1–3 need no live reviewer vendor and run against the harness or a
throwaway PR with a mocked reviewer. Steps 4–7 use a live disposable PR and
the platforms named in each step. Decision labels (D1–D14) refer to the plan.
No UI is involved and no design assets exist for this item, so there is no
design-fidelity step.

---

## Prerequisites

- [ ] `gh` is authenticated (`gh auth status`) with write access to the test
      repository
- [ ] `jq` is installed
- [ ] The implementation branch is checked out (or merged into `develop`)
- [ ] For Steps 4–6: a repository where Bugbot (Cursor GitHub App) is installed
- [ ] For Step 7: `local-ai-reviewer` configured in `review.on_ready.github`
      (this repository's default)

---

## Test Data

| Item | Value |
| --- | --- |
| Test PR (documentation branch) | A disposable PR from an `implementation-plan/smoke-1789-*` branch with one changed Markdown file |
| Test PR (implementation branch) | A disposable PR from a `fix/smoke-1789-*` branch |
| Run id | `export PR_REVIEW_LOOP_RUN_ID="smoke-1789-$(date +%s)"` before each scenario |
| Loop command | `./scripts/development-workflow/pr-review-loop.sh <pr> --branch <branch>` |

---

## Smoke Test Steps

### Step 1: Harness area passes

**Maps to**: AC-1 through AC-13 (unit coverage)

1. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1789`.
2. Run `bash scripts/development-workflow/tests/test-local-ai-reviewer.sh` and
   `bash scripts/development-workflow/tests/test-claude-code-action-reviewer.sh`.

**Expected result**: every test passes; the area finishes in seconds.

### Step 2: Invalid one-run override is refused before any request

**Maps to**: AC-5

1. Run the loop command with `--max-wait 0` against the test PR.
2. Repeat with `--max-wait abc`.
3. Open the PR timeline.

**Expected result**: both runs exit 64 and print
`--max-wait must be a positive whole number of seconds`. No trigger
comment, label change, or summary comment appears on the PR.

### Step 3: Budgets, sources, and configuration warnings

**Maps to**: AC-4, AC-5, AC-6

1. On the documentation-branch PR, run the loop with
   `--platform devin,bugbot,local-ai-reviewer` and read `PLATFORM_WAIT_BUDGETS=`.
2. Add `review.wait_budgets.bugbot: abc` to a scratch copy of
   `.ai-dev-workflow.yaml` used by the run (or the PR base config) and run
   again.
3. Set `review.wait_budgets.bugbot: 2700` and run again; then run once more
   with `--max-wait 600`.

**Expected result**:

- Step 1 shows Devin at the documentation-branch value with adjustment
  `documentation_branch`, Bugbot and `local-ai-reviewer` at their D2
  defaults with source `default` and no adjustment.
- Step 2 prints the D6 warning for `bugbot` and Bugbot falls back to its D2
  default with source `default`.
- Step 3 shows Bugbot `2700` with source `configured`; the `--max-wait 600`
  run shows `600` with source `override` for every platform.

### Step 4: Bugbot answering within its budget is a clean verdict (PR #1787 reproduction)

**Maps to**: AC-3, AC-12

1. On the documentation-branch PR, with no `--max-wait`, run the loop with
   `--platform bugbot`.
2. Read the run output and the "Automated Reviewer Loop Summary" comment.

**Expected result**: `RESULT=clean`; `PLATFORM_1_OUTCOME_CLASS=verdict_received`;
`PLATFORM_1_WAIT_BUDGET_SOURCE=default`; `PLATFORM_1_REQUESTED_AT` equals the
`bugbot run` comment time; `PLATFORM_1_LATENCY_SECONDS` is present; the
summary's "Reviewer timing" section shows the same values. No
`reviewer-failed` label.

### Step 5: No verdict yet, then the label follows the latest run

**Maps to**: AC-1, AC-7, AC-8, AC-12

1. Manually add the `reviewer-failed` label to the implementation-branch PR.
2. Run the loop with `--platform bugbot --max-wait 60` immediately after a
   push, so Bugbot cannot finish in time.
3. Wait until Bugbot's check run completes, then run the loop again with the
   same run id and no `--max-wait`.
4. Re-add the `reviewer-failed` label, then run the loop a fourth time on the
   same head without pushing and **without `--platform`**, in a test
   repository whose PR-base `.ai-dev-workflow.yaml` lists `bugbot` as the
   only configured reviewer for the PR's phase. An explicit `--platform`
   disables the #1692 verdict reuse (`explicit_platform_selection`), so this
   run must take the platforms from configuration.

**Expected result** (each bullet names the numbered step that produced the
run):

- Step 2: `RESULT=waiting_on_reviewer`, `REASON=reviewer-no-verdict-yet`,
  `PENDING_REVIEWER=bugbot`, `PENDING_REVIEW_WAITED_SECONDS` present,
  `NO_FAILURE_DETECTED=1`, `NO_VERDICT_REWAIT=available`,
  `PLATFORM_1_REQUEST_REF` equal to the id of the `bugbot run` comment it
  posted, exit 4. The `reviewer-failed` label is removed (no platform carried
  failure evidence). The summary says no reviewer failure was detected.
- Step 3: `RESULT=clean`; no new `bugbot run` comment was posted (the
  request recorded in Step 2 was adopted, D11).
- Step 4: `STAGE_SKIPPED_PLATFORMS=bugbot`,
  `PLATFORM_1_VERDICT_REUSED=1`, no latency key; the summary marks Bugbot
  as reused, and the re-added `reviewer-failed` label is removed on this
  reuse path too.

### Step 6: Automatic re-wait once, then a waiting stop

**Maps to**: AC-11

1. Run `/run-item` (or Protocol 91 Step 7 by hand) on a PR whose configured
   ready-phase reviewer is made to exceed its budget (for example
   `review.wait_budgets.bugbot: 60` on a PR Bugbot takes longer to review).
2. Watch the runner's Step 7 handling.

**Expected result**: the first `waiting_on_reviewer` result with
`NO_VERDICT_REWAIT=available` triggers exactly one immediate re-run with the
same run id and no fixer dispatch; that re-run posts no new review request.
If it is still waiting, it reports `NO_VERDICT_REWAIT=used` and the runner
stops as **Waiting on reviewer**, naming the platform, the revision, the
request time, and the waited seconds, without `escalate`, without
`reviewer-failed`, and without `ready-for-human-review`. `CYCLE_COUNT` does not
increase across the two runs.

### Step 7: Local reviewer stopped at budget end

**Maps to**: AC-1, AC-2

1. Run the loop on the implementation-branch PR with
   `--platform local-ai-reviewer --max-wait 5` and a slow
   `LOCAL_AI_REVIEWER_COMMAND` (for example `sleep 30`).
2. Run again with a command that exits 1 immediately.
3. Run again with a command that exits 124 immediately (`exit 124`), the
   status a stopped reviewer used to be recognized by.

**Expected result**: run 1 returns `waiting_on_reviewer` /
`reviewer-no-verdict-yet` and no `reviewer-failed` label; runs 2 and 3 each
return `escalate` within a few seconds and apply `reviewer-failed` (an early
exit with status 124 is a failure, not a stopped reviewer, D4).

### Last Step: Validate and clean up

- Verify every assertion below.
- Close the disposable PRs and delete their branches.

---

## Assertions Checklist

- [ ] AC-1: an expired wait with no verdict and no failure evidence reports Waiting on reviewer, names the platform, applies no label, does not escalate, dispatches no fixer (Steps 1, 5, 7)
- [ ] AC-2: positive failure evidence still escalates and applies `reviewer-failed` (Steps 1, 7)
- [ ] AC-3: a Bugbot clean answer within its budget on an `implementation-plan/*` branch is clean, not a timeout (Step 4)
- [ ] AC-4: only Devin gets the shortened documentation-branch wait (Step 3)
- [ ] AC-5: override → configured → default, invalid configured value warns and falls back, invalid override is refused before any request (Steps 2, 3)
- [ ] AC-6: defaults meet the floors, Bugbot at least 25 minutes (Steps 1, 3)
- [ ] AC-7: a later clean run removes the label on both the re-review and the reuse paths (Step 5)
- [ ] AC-8: no label after needs-fixes or waiting runs without failure evidence, or after an expired-wait kept skip; label present when any platform carries failure evidence (Steps 1, 5)
- [ ] AC-9: precedence across several platform outcomes (Step 1)
- [ ] AC-10: older-revision verdicts are not accepted (Step 1)
- [ ] AC-11: one automatic re-wait per revision with no duplicate request, then a waiting stop that does not count toward cycle caps (Step 6)
- [ ] AC-12: run output and summary record outcome, budget and source, request time, and latency or waited time; reused verdicts marked reused (Steps 4, 5)
- [ ] AC-13: usage, spend, account, and rate-limit outcomes unchanged (Step 1)
- [ ] AC-14: Protocol 91, Protocol 93, and the per-platform guides describe the outcome classes, precedence, re-wait, and label rule (review the implementation PR diff)

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Disposable PRs | Steps 2–7 | Create `implementation-plan/smoke-1789-*` and `fix/smoke-1789-*` branches with a one-line change and open draft PRs |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `NO_VERDICT_REWAIT=untracked` | `PR_REVIEW_LOOP_RUN_ID` not exported | Export a stable run id before each scenario |
| A second `bugbot run` comment appears in Step 5, step 3 | Adoption not applied: no recorded request for this head and run | Check that Step 5, step 2 printed `PLATFORM_1_REQUEST_REF`, that step 3 used the same `PR_REVIEW_LOOP_RUN_ID`, and that the head did not change between them (D11 adopts only the recorded request) |
| Step 5, step 4 shows no `STAGE_SKIPPED_PLATFORMS` | `--platform` was passed, or `PR_REVIEW_LOOP_DISABLE_STAGE_SKIP=1` is set | Re-run with platforms taken from configuration and the variable unset |
| Step 4 times out | Bugbot slower than its budget on this repository | Record the waited seconds and compare with the D3 rationale; raise `review.wait_budgets.bugbot` if the data supports it |

---

## Known Limitations

- Steps 4–6 depend on live vendor latency; a vendor outage turns Step 4 into
  a Waiting on reviewer result, which is itself the correct behavior.
- Latency is measured to the observing poll, so it can exceed the vendor's
  real latency by up to one poll interval.
