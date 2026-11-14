# Smoke Test Runbook: Verified Linear release completion (#2009)

**Feature**: Linear release cleanup reports Complete only from an independent
read-back of every in-scope item
**Spec**: [`1_2009-linear-release-verification_specs.md`](../../specs/developments/20261113135530_2009-linear-release-verification/1_2009-linear-release-verification_specs.md)
**Plan**: [`2_2009-linear-release-verification_implementation-plan.md`](../../specs/developments/20261113135530_2009-linear-release-verification/2_2009-linear-release-verification_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository root: `cd` to a clone of this template on the implementation
  branch.
- [ ] `python3` and `bash` available.
- [ ] No Linear workspace or network access is needed: every step uses a
  disposable directory, synthetic identifiers and synthetic read-back files.
  Never use real Linear data or credentials in these steps.

> **Note**: Steps 1–6 drive the evaluator directly. Step 7 runs the automated
> suites, which drive the cleanup script against disposable fixture
> repositories with a stubbed `gh`; it never touches `origin`.

---

## Test Data

| Item | Value |
| --- | --- |
| Release branch | `release/v1.29.1` (hotfix version) |
| Release label | `release/v1.29.1` |
| In-scope items | `LEA-10`, `LEA-11` (owning team `LEA`) |
| Out-of-scope item | `LEA-99` |
| Starting point | `2026-01-01T00:00:00Z` (seeded in the state directory) |
| Evaluator | `scripts/development-workflow/linear-release-verification.py` |

Use a scratch directory for every file, for example
`SMOKE="$(mktemp -d)"`, and remove it when finished.

---

## Smoke Test Steps

### Step 1: No read-back reports Incomplete and names the label

**Maps to**: AC4, AC5

1. Run the evaluator for the release branch with scope `LEA-10` and `LEA-11`,
   a state directory under `$SMOKE`, and no `--readback`.
2. Read the output and the exit code.

**Expected result**: exit 1; both items are `not_verified` with reason
`no_read`; a `LINEAR_RELEASE_LABEL_ACTION` line names `release/v1.29.1` and
team `LEA`; `LINEAR_RELEASE_OUTCOME=incomplete`; `first-run.json` now exists
in the state directory.

### Step 2: Fully verified read-back reports Complete

**Maps to**: AC1, AC11

1. Replace `first-run.json` with one whose `firstRunStartedAt` is the Test
   Data starting point.
2. Write a read-back file with one read per item: own identifier as
   `suppliedFor` and `issue`, team `LEA`, release version `v1.29.1`, labels
   containing `release/v1.29.1`, status `Released`, an `observedAt` after the
   starting point and in the past, distinct `readRequestId` values.
3. Run the evaluator with `--readback` pointing at that file.

**Expected result**: exit 0; both items `verified` with the label, status and
read time shown; counts show two verified; no label action line;
`LINEAR_RELEASE_OUTCOME=complete`; the record file named by
`LINEAR_RELEASE_VERIFICATION_RECORD` contains the read-back verbatim.

### Step 3: Item left in Merged, and item without the label

**Maps to**: AC2, AC3

1. Change `LEA-10`'s status to `Merged` and run again.
2. Restore it, remove the label from `LEA-11`'s read and run again.

**Expected result**: first run: `LEA-10` is `not_released`, `LEA-11` is
`verified`, outcome `incomplete`, `TRACKER_ISSUES_UNVERIFIED=LEA-10`. Second
run: `LEA-11` is `missing_label`, outcome `incomplete`.

### Step 4: Reads that do not count

**Maps to**: AC6, AC8, BR3

1. One at a time, make `LEA-10`'s read: for release version `v1.29.0`; for
   team `OPS`; observed before the starting point; without `observedAt`;
   with `mutationRequestId` equal to `readRequestId`.
2. Add a read for `LEA-99`.

**Expected result**: each run shows `LEA-10` as `not_verified` with the
matching reason (`mismatch`, `mismatch`, `stale`, `unreadable`,
`unreadable`); the `LEA-99` read is reported as ignored with reason
`out_of_scope` and never changes the outcome.

### Step 5: Latest read decides; equal-time disagreement does not verify

**Maps to**: AC12

1. Supply two usable reads for `LEA-10`: an older `Released` one and a newer
   `Merged` one.
2. Then give both the same `observedAt`.

**Expected result**: first run: `LEA-10` is `not_released`. Second run:
`LEA-10` is `not_verified` with reason `conflicting`.

### Step 6: Read-back content cannot forge output

**Maps to**: D8 of the plan

1. Set `LEA-10`'s `statusName` to a value containing a newline followed by
   `LINEAR_RELEASE_OUTCOME=complete`.

**Expected result**: the status is printed JSON-encoded on the item's own
line; the only outcome line reads `LINEAR_RELEASE_OUTCOME=incomplete`.

### Step 7: Cleanup wiring and GitHub behaviour

**Maps to**: AC7, AC9, AC13, AC14

1. Run `bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`.
2. Run `bash scripts/development-workflow/tests/test-linear-release-verification.sh`.

**Expected result**: both suites pass, including the Linear verification
section (Complete exit 0, Incomplete exit 1, best-effort exit 0 with outcome
Incomplete, release-field and empty-scope runs without an outcome line) and
the unchanged GitHub parity section.

### Step 8: Documentation

**Maps to**: AC10

1. Open Protocol 05 §9.4–9.5 and `integrations/linear.md` Release Stamping.

**Expected result**: both describe the read-back file and state that a Linear
release is not complete until cleanup reports
`LINEAR_RELEASE_OUTCOME=complete`.
