# Smoke Test Runbook: Haystack Large-PR Analysis Skip

**Feature**: Haystack Large-PR Analysis Skip
**Spec**: [1_1311-haystack-large-pr-skip_specs.md](../../specs/developments/20260723112815_1311-haystack-large-pr-skip/1_1311-haystack-large-pr-skip_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] The implementation branch contains the file-limit skip behavior and
  focused shell tests.
- [ ] `bash`, `jq`, and the repository test harness dependencies are available.
- [ ] Tests use mocked `gh` and Haystack responses; no production pull request
  is mutated.

---

## Test Data

| Fixture | Value |
| --- | --- |
| Current head | `e135dff4fdfb69b0f2432b5f233e3be348647ef1` |
| Authoritative check | Completed `Haystack / Review`, conclusion `action_required`, title `PR exceeds the Haystack analysis limit` |
| Authoritative summary | Explicitly states that 168 changed files exceed the 100-file analysis limit |
| Stale head | A different SHA with otherwise identical check text |
| Other reviewer clean | Mock platform result `clean` |
| Other reviewer blocker | Mock platform result `needs_fixes` with one blocking finding |

The values mirror an observed oversized template-sync PR but are local fixtures,
not a dependency on that live PR.

---

## Smoke Test Steps

### Step 1: Classify the Current-Head File-Limit Outcome

**Maps to**: AC-1, AC-7

1. Run `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`.
2. Inspect the focused current-head check-run cases.
3. Confirm the authoritative fixture emits:
   `RESULT=skipped`, `REASON=analysis_skipped_file_limit`,
   `DISPLAY_RESULT=skipped (analysis file limit)`, zero finding counts, and
   exit code `3`.
4. Confirm generic `action_required`, generic `Analysis Skipped`, unrelated
   limit text, and prior-head evidence do not emit that reason.

**Expected result**: Only explicit file-limit evidence bound to the current PR
head produces the terminal file-limit skip.

### Step 2: Verify Prompt Poll Termination and Stable Reruns

**Maps to**: AC-2, AC-6

1. Use the harness case where Haystack triage is transient and the authoritative
   check becomes visible during the same observation.
2. Confirm the adapter probes before the next sleep and exits without consuming
   the remaining extended wait.
3. Run the same current-head fixture twice.
4. Compare both result contracts and recorded call/sleep counts.

**Expected result**: Each invocation terminates within the next standard
observation cycle, returns the same skip classification, and does not begin a
new extended wait.

### Step 3: Verify Permissive Aggregate Behavior

**Maps to**: AC-3

1. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh`.
2. Exercise Haystack's file-limit skip with every other configured reviewer
   clean or permissibly skipped.
3. Inspect the aggregate result and reviewer-failed label decision.

**Expected result**: The aggregate reviewer-loop result is clean, the distinct
Haystack skip remains visible, and `reviewer-failed` is not required solely for
the recognized file-limit outcome.

### Step 4: Preserve Another Reviewer's Blocker

**Maps to**: AC-4

1. Exercise the aggregate harness with the same Haystack skip and another
   reviewer returning `needs_fixes`.
2. Repeat with another reviewer returning an escalation.
3. Inspect the aggregate result and readiness decision.

**Expected result**: The other platform remains authoritative, the aggregate
stays blocked or escalated, and no readiness path is bypassed.

### Step 5: Preserve Summary and Durable History

**Maps to**: AC-5, AC-6

1. Run a mocked clean aggregate iteration containing the Haystack file-limit
   skip.
2. Inspect the script-owned `### Automated Reviewer Loop Summary`.
3. Confirm its human-readable platform list identifies the Haystack analysis
   file-limit skip.
4. Parse the `reviewer_loop_history.v1` payload and confirm the same platform
   token appears in the appended iteration.
5. Run a second same-head iteration and inspect the updated comment.

**Expected result**: The same summary comment is updated, prior history is
retained, and a stable new iteration records the same terminal Haystack skip.

### Step 6: Verify Haystack and Sync-Template Guidance

**Maps to**: AC-8

1. Run `bash scripts/development-workflow/tests/test-sync-template-apply-modes.sh`.
2. Inspect the Haystack integration guide and Protocol 93.
3. Inspect the sync-template Step 6.2 guidance in the three full command/skill
   bodies and the terminal guidance in both workflow-sync-template wrappers.

**Expected result**: Every surface explains that oversized sync PRs may skip
Haystack by design, while other reviewers, CI, unresolved-thread, regression,
and readiness gates remain mandatory.

### Last Step: Validate and Shut Down

1. Run the plan's focused test, static-analysis, and markdown-lint commands.
2. Confirm no test fixture created a live comment, check run, label, or PR
   mutation.

---

## Assertions Checklist

- [ ] AC-1: The current-attempt file-limit outcome becomes a distinct terminal
  Haystack skip within the next observation cycle.
- [ ] AC-2: No remaining extended wait is consumed solely for Haystack.
- [ ] AC-3: The skip permits a clean aggregate only when all other reviewers
  are clean or permissibly skipped.
- [ ] AC-4: Another reviewer blocker or escalation remains authoritative.
- [ ] AC-5: The workflow-owned summary records the reason and
  `reviewer_loop_history.v1`.
- [ ] AC-6: Same-head reruns are stable and prompt.
- [ ] AC-7: Ambiguous, unrelated, and stale evidence is rejected.
- [ ] AC-8: Haystack and sync-template guidance preserve every remaining gate.

---

## Known Limitations

- The MVP does not raise Haystack's external file limit or force analysis of an
  oversized pull request.
- A bot comment without the current-head check run is not treated as
  authoritative because free-form comments do not reliably prove the current
  attempt.
- Live platform corroboration is optional; deterministic mocked fixtures are
  the required regression evidence.
