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
| Remaining PR states | Clean, pending, unknown, dirty, blocked, behind, failing |
| Feature command | `scripts/development-workflow/batch-merge.sh recheck-remaining` |

---

## Smoke Test Steps

### Step 1: Run the automated recheck regression

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC8, AC9, AC10

1. Run `bash scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh`.
2. Confirm the output includes passing cases for clean continuation, pending
   retry, unknown retry, dirty blocking, failing blocking, order preservation,
   and out-of-scope observation.

**Expected result**: The regression exits zero and every refreshed-state
scenario passes.

### Step 2: Verify stale clean evidence is invalidated

**Maps to**: AC1, AC2, AC3, AC5, AC10

1. Discover a frozen two-PR list where both PRs initially report clean.
2. Simulate merging PR A into the target base.
3. Recheck PR B after PR A's merge, returning `DIRTY`.
4. Inspect the batch summary entry for PR B.

**Expected result**: PR B is not merged using the original clean result. Its
outcome is `merge_blocked` and the summary names PR A as the invalidating
sibling merge.

### Step 3: Verify retryable pending and unknown states

**Maps to**: AC4

1. Recheck a remaining PR whose required checks are pending.
2. Confirm the runner keeps it under bounded supervision.
3. Repeat with a temporarily unknown mergeability state.
4. Let one scenario become clean and another reach timeout or terminal failure.

**Expected result**: Retryable states are not treated as immediately clean or
terminal. Clean after retry can continue; exhausted or failing states become
`merge_blocked`.

### Step 4: Verify order preservation and later clean continuation

**Maps to**: AC6, AC7

1. Use a frozen list with three PRs.
2. Simulate PR A merged, PR B dirty, and PR C refreshed clean.
3. Continue the batch only if existing merge-order guardrails allow it.
4. Inspect the final order and summary.

**Expected result**: PR B remains in its original position with
`merge_blocked`; PR C is not moved ahead of PR B in the recorded order and is
merged only after independent refreshed-clean evidence.

### Step 5: Verify frozen scope

**Maps to**: AC8

1. Make the mocked GitHub state include an additional open PR outside the
   supplied `--prs` list.
2. Run the remaining-PR recheck.
3. Inspect helper output and side effects.

**Expected result**: The out-of-scope PR is observation-only or absent from the
mutation set. It is not labeled, merged, rechecked for mutation, or added to the
batch.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary branches or fixtures created by the test harness.

---

## Assertions Checklist

- [ ] Every remaining in-scope PR is rechecked after a sibling merge.
- [ ] Prior clean evidence is treated as stale after the target base changes.
- [ ] Non-clean refreshed states do not merge under stale evidence.
- [ ] Pending and unknown states follow bounded retry semantics.
- [ ] Blocked summaries name the invalidating sibling merge and refreshed state.
- [ ] Refreshed-clean PRs can continue under the original delegated policy.
- [ ] Original PR order is preserved when an entry becomes blocked.
- [ ] Out-of-scope PRs are observation-only.
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
