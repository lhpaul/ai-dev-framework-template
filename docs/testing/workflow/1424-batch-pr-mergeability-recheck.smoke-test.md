# Smoke Test Runbook: Batch PR Mergeability Recheck

**Feature**: Batch PR mergeability recheck
**Spec**: [Batch PR Mergeability Recheck - Spec](../../specs/developments/20260801142412_1424-batch-pr-mergeability-recheck/1_1424-batch-pr-mergeability-recheck_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in a disposable clone or mocked test fixture.
- [ ] `gh`, `git`, `jq`, and Bash are available.
- [ ] The implementation PR's branch is checked out.
- [ ] The batch merge test fixture can simulate multiple PR states.

---

## Test Data

| Item | Value |
| --- | --- |
| Frozen PR list | Two or more mocked PR numbers supplied through `--prs` |
| Invalidating sibling PR | First PR in the frozen list, marked merged before recheck |
| Remaining PR states | Clean, pending, unknown, dirty, blocked, behind, failing, timeout |
| Feature command | See command block below |

```bash
scripts/development-workflow/batch-merge.sh recheck-remaining \
  --prs 101,102,103 \
  --after-merged-pr 101 \
  --base develop
```

---

## Smoke Test Steps

### Step 1: Run the automated recheck regression

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8, AC9, AC10

1. Run the regression:

   ```bash
   bash scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh
   ```

2. Confirm the output includes passing cases for clean continuation, pending
   retry, unknown retry, dirty blocking, blocked blocking, behind blocking,
   failing blocking, timeout blocking, order preservation, and out-of-scope
   observation.

**Expected result**: The regression exits zero and every refreshed-state
scenario passes.

### Step 2: Verify stale clean evidence is invalidated

**Maps to**: AC1, AC2, AC3, AC5, AC10

1. Load the fixture where PRs `101` and `102` initially report `OPEN`, clean,
   and targeting `develop`.
2. Keep PR `101` open and clean for the initial merge command.
3. Set the fixture transition so a successful `merge --pr 101` changes PR `101`
   to merged and changes PR `102` to refreshed `mergeStateStatus: DIRTY`.
4. Run the caller path that will consume the recheck result:

   ```bash
   scripts/development-workflow/batch-merge.sh merge \
     --pr 101 \
     --base develop
   ```

5. Run the feature command:

   ```bash
   scripts/development-workflow/batch-merge.sh recheck-remaining \
     --prs 101,102 \
     --after-merged-pr 101 \
     --base develop
   ```

6. Assert PR `102` emits every required JSONL field with these values:

   ```json
   {
     "record_type": "remaining_pr",
     "pr": 102,
     "original_index": 1,
     "invalidating_sibling_pr": 101,
     "base_ref": "develop",
     "head_ref": "feature/mock-pr-102",
     "merge_state": "DIRTY",
     "checks_state": "success",
     "classification": "merge_blocked",
     "retryable": false,
     "attempts": 1,
     "deadline_seconds": 60,
     "outcome": "hold",
     "reason": "merge_state_non_clean"
   }
   ```

7. Assert the caller summary for PR `102` is `merge_blocked`, does not invoke
   `batch-merge.sh merge --pr 102`, and includes `invalidating_sibling_pr: 101`.

**Expected result**: PR B is not merged using the original clean result. Its
outcome is `merge_blocked` and the summary names PR A as the invalidating
sibling merge.

### Step 3: Verify retryable pending and unknown states

**Maps to**: AC4

1. Configure the fixture with `BATCH_MERGE_RECHECK_ATTEMPTS=3` and
   `BATCH_MERGE_RECHECK_SLEEP_SECONDS=0`.
2. Recheck PR `102` with required checks returning `pending`, then `pending`,
   then `success`.
3. Recheck PR `103` with `mergeStateStatus: UNKNOWN` for all three attempts.
4. Assert PR `102` emits `attempts: 3`, `classification: clean`, and
   `outcome: continue`.
5. Assert PR `103` emits `attempts: 3`, `classification: merge_blocked`,
   `retryable: false`, `deadline_seconds: 60`, and
   `reason: retry_attempts_exhausted`.
6. Repeat with `BATCH_MERGE_RECHECK_ATTEMPTS=99`,
   `BATCH_MERGE_RECHECK_SLEEP_SECONDS=1`, and
   `BATCH_MERGE_RECHECK_DEADLINE_SECONDS=1`; assert timeout emits
   `reason: retry_deadline_exhausted`.

**Expected result**: Retryable states are not treated as immediately clean or
terminal. Clean after retry can continue; exhausted or failing states become
`merge_blocked`.

### Step 4: Verify order preservation and later clean continuation

**Maps to**: AC6, AC7

1. Use frozen list `101,102,103`.
2. Simulate PR `101` merged, PR `102` dirty, and PR `103` refreshed clean.
3. Run the feature command:

   ```bash
   scripts/development-workflow/batch-merge.sh recheck-remaining \
     --prs 101,102,103 \
     --after-merged-pr 101 \
     --base develop
   ```

4. Assert the JSONL records for `102` and `103` have `original_index` values
   `1` and `2` respectively, in that order.
5. Continue the batch only if existing merge-order guardrails allow merging the
   independently refreshed-clean PR `103`.

**Expected result**: PR B remains in its original position with
`merge_blocked`; PR C is not moved ahead of PR B in the recorded order and is
merged only after independent refreshed-clean evidence.

### Step 5: Verify frozen scope

**Maps to**: AC8

1. Make the mocked GitHub state include open PR `104` targeting `develop`,
   absent from the supplied `--prs` list.
2. Run the feature command with frozen list `101,102,103`.
3. Assert exactly one PR `104` record appears, and only as:

   ```json
   {
     "record_type": "out_of_scope_observation",
     "pr": 104,
     "original_index": null,
     "invalidating_sibling_pr": 101,
     "base_ref": "develop",
     "head_ref": "feature/out-of-scope-104",
     "merge_state": "CLEAN",
     "checks_state": "success",
     "classification": "out_of_scope_observation",
     "retryable": false,
     "attempts": 1,
     "deadline_seconds": 60,
     "outcome": "observe",
     "reason": "not_in_frozen_scope"
   }
   ```

4. Inspect the mocked `gh` call log separately and assert PR `104` was not
   labeled, merged, retried for mutation, or appended to the frozen list.

**Expected result**: The out-of-scope PR is reported exactly once as
observation-only. It is not labeled, merged, rechecked for mutation, or added to
the batch.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary branches or fixtures created by the test harness.

---

## Assertions Checklist

- [ ] Every remaining in-scope PR is rechecked after a sibling merge.
- [ ] Prior clean evidence is treated as stale after the target base changes.
- [ ] Non-clean refreshed states do not merge under stale evidence.
- [ ] Pending and unknown states follow bounded retry semantics.
- [ ] The retry path asserts default or configured attempt and deadline bounds.
- [ ] Attempt exhaustion and wall-clock deadline exhaustion emit distinct
      `reason` values.
- [ ] Dirty, blocked, behind, failing, timeout, pending, unknown, and clean
      cases are all covered by the fixture.
- [ ] Every emitted JSONL record includes every canonical schema field.
- [ ] Blocked summaries name the invalidating sibling merge and refreshed state.
- [ ] Refreshed-clean PRs can continue under the original delegated policy.
- [ ] Original PR order is preserved when an entry becomes blocked.
- [ ] Out-of-scope PRs are observation-only and emitted exactly once.
- [ ] Out-of-scope PR summaries preserve `reason: not_in_frozen_scope`.
- [ ] The mocked call log proves no mutation targeted out-of-scope PRs.
- [ ] Final batch summary uses latest post-sibling-merge evidence.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Mock PR A | First sibling merged into the base | Created by `test-batch-merge-recheck-remaining.sh` |
| Mock PR B | Remaining PR changes from clean to dirty or retryable | Created by `test-batch-merge-recheck-remaining.sh` |
| Mock PR C | Later remaining PR stays refreshed-clean | Created by `test-batch-merge-recheck-remaining.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Recheck sees no remaining PRs | The frozen `--prs` list was not passed through after merge | Check Protocol 94 caller sequence and helper arguments |
| Dirty PR still merges | The next merge used stale discovery state | Verify the next merge selection consumes refreshed output |
| Out-of-scope PR is mutated | The helper used broad discovery instead of the frozen list | Restrict mutation logic to explicit `--prs` entries |

---

## Known Limitations

- The smoke runbook uses mocked or disposable PR state; do not intentionally
  dirty production PR branches to test the recheck behavior.
