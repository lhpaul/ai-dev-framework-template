# Smoke Test Runbook: Delete Remote Implementation Branch After Multi-Stage Merge

**Feature**: Delete remote implementation branch after multi-stage merge
**Spec**: [1_1185-delete-remote-implementation-branch-after-merge_specs.md](../../specs/developments/20260714171110_1185-delete-remote-implementation-branch-after-merge/1_1185-delete-remote-implementation-branch-after-merge_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Work in a disposable repository or a temporary fork; do not use a
      production branch for deletion checks.
- [ ] `gh` is authenticated for the disposable repository.
- [ ] The implementation PR for this feature has been merged into `develop` in
      the test repository or equivalent mocked fixture.
- [ ] A temporary merged implementation branch exists remotely, such as
      `feature/1185-smoke-cleanup`.
- [ ] Temporary `spec/1185-smoke-cleanup` and
      `implementation-plan/1185-smoke-cleanup` branches are available for
      classification checks if the scan path is exercised live.

---

## Test Data

| Item | Value |
| --- | --- |
| Implementation branch | `feature/1185-smoke-cleanup` |
| Spec branch | `spec/1185-smoke-cleanup` |
| Plan branch | `implementation-plan/1185-smoke-cleanup` |
| Base branch | `develop` |
| Cleanup helper | `scripts/development-workflow/post-merge-cleanup.sh` |

---

## Smoke Test Steps

### Step 1: Verify merged implementation cleanup deletes the remote branch

**Maps to**: AC1, AC2, AC3, AC4, AC8

1. Confirm the implementation PR for `feature/1185-smoke-cleanup` is `MERGED`.
2. Confirm `origin/feature/1185-smoke-cleanup` exists before cleanup.
3. Run:

   ```bash
   ./scripts/development-workflow/post-merge-cleanup.sh --base develop feature/1185-smoke-cleanup
   ```

4. Confirm the output reports the remote branch as deleted or already absent.
5. Confirm `origin/feature/1185-smoke-cleanup` no longer exists.

**Expected result**: Cleanup only runs after merged-state verification and the
remote implementation branch is gone afterward.

### Step 2: Verify unmerged PRs are not deleted

**Maps to**: AC3, AC8

1. Create or mock an implementation branch whose PR is `OPEN` or
   closed-but-not-merged.
2. Run the cleanup path against that branch.
3. Inspect the output.

**Expected result**: The helper skips remote deletion, names the non-merged PR
state, and does not report terminal cleanup success for the implementation
branch.

### Step 3: Verify already absent remote branches are successful

**Maps to**: AC4

1. Use a merged implementation PR whose remote branch has already been deleted.
2. Run the cleanup helper for that branch.
3. Inspect the output.

**Expected result**: Cleanup reports the remote branch as already absent or
already complete and continues local/tracker cleanup.

### Step 4: Verify spec and plan branch classification

**Maps to**: AC5, AC6, AC7

1. Run the stale-branch scan or audit path against merged
   `spec/1185-smoke-cleanup` and
   `implementation-plan/1185-smoke-cleanup` branches.
2. Inspect the branch category output.
3. Run the same scan against a merged implementation branch whose remote ref
   still exists.

**Expected result**: Spec and plan branches are shown as expected-persistent.
Merged implementation branches with remote refs are shown as expected-deleted
cleanup findings with PR context.

### Last Step: Validate and clean up test branches

- Delete any temporary branches created for the smoke test.
- Confirm no temporary remote implementation branch remains.

---

## Assertions Checklist

- [ ] A full-pipeline implementation branch is deleted remotely after its PR is
      confirmed merged.
- [ ] Single-stage cleanup behavior remains compatible with the same result
      categories.
- [ ] Remote deletion is skipped for unmerged PR states.
- [ ] Already absent remote implementation branches are treated as successful.
- [ ] Spec and implementation-plan branches are classified as
      expected-persistent.
- [ ] Stale remote implementation branches are flagged with branch category and
      PR context.
- [ ] Cleanup failures remain visible and do not produce a misleading terminal
      success summary.
- [ ] Automated test or audit evidence covers the branch cleanup distinction.

---

## Seed Data Reference

No application seed data is required. Use temporary git branches and mocked or
disposable GitHub PR state.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Cleanup skips deletion for a branch expected to be merged | GitHub PR state is not `MERGED` or the branch name does not match the PR head | Re-check `gh pr view` for the PR state and head branch. |
| Cleanup reports already absent | The remote branch was auto-deleted or removed by a prior run | Treat as success and continue cleanup verification. |
| Scan reports spec/plan branches as stale implementation branches | Branch lifecycle classification was not applied | Re-run the updated scan/audit path and inspect branch category output. |

---

## Known Limitations

- The live smoke test should use a disposable repository or temporary fork
  because it intentionally creates and deletes remote branches.
