# Smoke Test Runbook: Reviewer Loop Retry History Preservation

**Feature**: Reviewer Loop Retry History Preservation
**Spec**: [1_1243-preserve-reviewer-loop-retry-history_specs.md](../../specs/developments/20260716104000_1243-preserve-reviewer-loop-retry-history/1_1243-preserve-reviewer-loop-retry-history_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI is authenticated and can read/write PR comments in the repository.
- [ ] Reviewer-loop platforms can be mocked or run safely on a disposable PR.
- [ ] The implementation branch includes the reviewer-loop history changes and retrospective guidance updates.
- [ ] A disposable PR exists for smoke testing, or the test harness can simulate PR comments.

---

## Test Data

| Item | Value |
| --- | --- |
| Test PR | Disposable PR number used for reviewer-loop smoke testing |
| First iteration | Reviewer-loop result with at least one blocking finding or mocked `needs_fixes` result |
| Final iteration | Reviewer-loop result with clean terminal state |
| Missing-history PR/comment | Legacy summary comment without `reviewer_loop_history.v1` |
| Malformed-history PR/comment | Summary comment with invalid `reviewer_loop_history.v1` JSON |

---

## Smoke Test Steps

### Step 1: Multi-Iteration History Preservation

**Maps to**: AC1, AC2, AC3, AC7

1. Run or simulate the reviewer loop on the test PR so the first completed iteration exits with `needs_fixes`.
2. Inspect the PR's `### Automated Reviewer Loop Summary` comment through the GitHub comments API.
3. Verify the comment has one `reviewer_loop_history.v1` JSON payload with one entry.
4. Apply or simulate the required fix.
5. Run or simulate the reviewer loop again so it exits `clean`.
6. Inspect the same summary comment again.

**Expected result**: The same summary comment is updated in place, the human-readable top section shows the final clean result, and the history payload contains both the earlier `needs_fixes` entry and the final `clean` entry with result, blocker count, and timestamp/order evidence.

### Step 2: Retrospective Exact Retry Metrics

**Maps to**: AC3

1. Run the retrospective protocol against the test PR from Step 1, or manually follow the protocol's PR data gathering steps.
2. Confirm the retrospective reads the `reviewer_loop_history.v1` payload before using legacy timestamp heuristics.
3. Confirm it calculates retry count as `entries.length - 1`.
4. Confirm it reports per-iteration result, blocker count, and timestamp/order evidence.

**Expected result**: The retrospective reports exact retry metrics from the preserved history.

### Step 3: Single Clean Run Reports Zero Retries

**Maps to**: AC4

1. Run or simulate the reviewer loop on a PR where the first completed iteration exits `clean`.
2. Inspect the summary comment history payload.
3. Run the retrospective protocol against that PR.

**Expected result**: The history payload contains one clean entry and the retrospective reports zero automated-reviewer retry loops.

### Step 4: Missing Or Malformed History Reports Unavailable

**Maps to**: AC5

1. Use a legacy summary comment without a history payload, or create a mocked comment fixture with no `reviewer_loop_history.v1` block.
2. Run the retrospective protocol against that PR/comment data.
3. Repeat with a malformed history JSON fixture.

**Expected result**: The retrospective reports a specific unavailable reason, such as missing history or malformed history, and does not treat the retry count as zero.

### Step 5: Existing Gates Remain Unchanged

**Maps to**: AC6

1. Run the normal reviewer loop validation on the test PR.
2. Confirm blocking findings still prevent readiness.
3. Confirm a clean reviewer-loop result still allows the existing readiness flow to proceed.
4. Confirm CI, tracker status, readiness labels, and merge-authority behavior are unchanged by the presence of history.

**Expected result**: Reviewer-loop history changes do not alter existing blocking-review, CI, readiness-label, tracker-status, or merge-authority gates.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Remove or close any disposable smoke-test PR if one was created solely for this test.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: Multiple reviewer-loop iterations are recorded before the PR is marked clean.
- [ ] AC2: Updating the final clean summary does not discard prior iteration history.
- [ ] AC3: Retrospective output reports exact retry count, per-iteration result, blocker count, and timestamp/order evidence from preserved history.
- [ ] AC4: A first-pass clean PR records one clean iteration and reports zero retries.
- [ ] AC5: Missing or unreadable history reports a specific unavailable reason instead of zero retries.
- [ ] AC6: Existing blocking-review, CI, readiness-label, tracker-status, and merge-authority gates behave as before.
- [ ] AC7: The final human summary remains focused on the current terminal state while exposing compact access to preserved history.

---

## Known Limitations

- A fully live multi-iteration smoke test depends on reviewer platform availability. If platforms are unavailable, use the existing shell harness and mocked PR comment fixtures for deterministic validation.
- This MVP does not backfill exact retry history for PRs completed before the feature ships.
