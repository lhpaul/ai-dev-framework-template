# Smoke Test Runbook: Validate Existing Workflow Branches Before Reuse

**Feature**: Safe existing-branch reuse in `/run-item`
**Spec**: [1_1179-stale-branch-reuse_specs.md](../../specs/developments/20260723110011_1179-stale-branch-reuse/1_1179-stale-branch-reuse_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out.
- [ ] Git is available.
- [ ] The branch-reuse validator and its test harness exist.
- [ ] No disposable fixture repositories from an earlier failed run remain.
- [ ] The test runner can create a bare remote and linked Git worktree under a
      temporary directory.

---

## Test Data

| Item | Value |
| --- | --- |
| Issue | `1179` |
| Approved base | `develop` |
| Candidate branch | `implementation-plan/1179-stale-branch-reuse` |
| Compatible history | Candidate equals or descends from the current approved-base tip |
| Incompatible history | Candidate descends from an unrelated or older line that does not contain the current approved-base tip |
| Divergence history | Compatible local candidate differs from `origin/<candidate>` |
| Output formats | Stable shell `KEY=value` records and `--json` |

---

## Smoke Test Steps

### Step 1: Run the Automated Validator Harness

**Maps to**: Acceptance Criteria 1-11

1. Run
   `bash scripts/development-workflow/tests/test-validate-branch-reuse.sh`.
2. Confirm the output names passing cases for fresh, local, remote-only,
   worktree, incompatible, stale-tracking, missing-base, ambiguous-ref,
   failed-query, structured-output, and read-only scenarios.

**Expected result**: The harness exits successfully and every required
branch-discovery and failure mode is covered.

### Step 2: Verify the Fresh-Branch Path

**Maps to**: Acceptance Criteria 1, 2

1. Create or use the harness fixture with no exact candidate branch ref.
2. Include lookalike refs whose names contain `11790` or place the candidate
   text under a tag.
3. Run the validator with the exact issue, branch, approved base, and repository
   root.

**Expected result**: The validator reports `no_existing_branch`; lookalikes do
not count, and the caller can continue the normal fresh-branch path.

### Step 3: Verify Compatible Local Reuse

**Maps to**: Acceptance Criteria 1, 3, 4, 7

1. Create a local candidate branch from the approved-base tip.
2. Add one candidate commit.
3. Run the validator in shell-output and JSON modes.

**Expected result**: Both modes report `compatible`, name the issue, candidate,
approved base, resolved refs and object IDs, and authorize only the normal
resume path.

### Step 4: Verify Compatible Remote-Only Reuse

**Maps to**: Acceptance Criteria 1, 3, 4

1. Push the compatible candidate to the fixture remote.
2. Delete only the local candidate ref while retaining the remote-tracking ref.
3. Run the validator.

**Expected result**: The remote-only candidate is positively verified against
the approved base and reported as compatible without creating a local branch.

### Step 5: Verify Compatible Worktree Reuse

**Maps to**: Acceptance Criteria 1, 3, 4, 10

1. Check out the compatible candidate in a linked worktree.
2. Invoke the validator from the main fixture repository.
3. Record the registered worktree and branch before and after validation.

**Expected result**: The candidate is reported as compatible, its worktree
ownership is visible, and neither checkout nor worktree registration changes.

### Step 6: Block an Incompatible Branch

**Maps to**: Acceptance Criteria 2, 5, 7, 8

1. Create the exact candidate branch from unrelated history that does not
   contain the approved-base tip.
2. Snapshot HEAD, refs, worktrees, and status.
3. Run the validator.
4. Compare the repository snapshot after the command.

**Expected result**: The validator reports `incompatible`, names the item,
branch, approved base, failed ancestry reason, and human recovery action. It
does not delete, reset, rebase, switch, push, or otherwise mutate the fixture.

### Step 7: Block Unverifiable Evidence

**Maps to**: Acceptance Criteria 6, 7, 8

1. Run once with the approved-base ref absent.
2. Run once with deliberately ambiguous candidate or base evidence.
3. Use the harness injection point to make the ancestry query fail.

**Expected result**: Each run reports `verification_blocked`, not
`incompatible` or `compatible`, and gives a concrete action to restore evidence
and retry or request a human decision.

### Step 8: Keep Tracking Divergence Diagnostic

**Maps to**: Acceptance Criteria 3, 4, 9

1. Create a compatible local candidate.
2. Leave its remote-tracking ref behind, ahead, or diverged.
3. Run the validator.

**Expected result**: Compatibility still depends on approved-base ancestry.
Ahead/behind counts and tracking state are reported separately and do not
produce a false base mismatch.

### Step 9: Verify Guard Composition and Runner Routing

**Maps to**: Acceptance Criteria 5, 10, 12

1. Run:
   - `bash scripts/development-workflow/tests/test-run-nested-artifact-guard.sh`
   - `bash scripts/development-workflow/tests/test-worktree-resume-preflight.sh`
2. Inspect Protocol 91 and the item-runner files listed in the implementation
   plan.
3. Confirm candidate discovery and nested-artifact validation occur before the
   reuse validator.
4. Confirm only `compatible` reaches `workflow-next-action.sh`.
5. Confirm `incompatible` and `verification_blocked` stop before mutation and
   use the same recovery language on every supported surface.

**Expected result**: Existing guards still pass, the new gate complements them,
and the decision matrix is mirrored across Codex, Claude, and Cursor runners.

### Last Step: Validate and Shut Down

- Run markdown and shell guard lint required by the implementation plan.
- Verify every assertion below.
- Remove disposable fixture directories and linked worktrees created only for
  the smoke test.

---

## Assertions Checklist

- [ ] Existing branches are validated before reuse. AC1.
- [ ] Exact branch/item matching alone is not sufficient. AC2.
- [ ] Compatibility requires positive approved-base ancestry evidence. AC3.
- [ ] Compatible local, remote-only, and worktree candidates resume without
      duplicate branch creation. AC4.
- [ ] Incompatible candidates stop before Git, file, PR, label, or tracker
      mutation. AC5.
- [ ] Missing, ambiguous, and failed-query evidence reports
      `verification_blocked` separately. AC6.
- [ ] Blocked output names item, branch, base, reason, and human action. AC7.
- [ ] Validation never deletes, resets, rebases, force-pushes, or rewrites a
      candidate. AC8.
- [ ] Local-versus-remote divergence remains a separate diagnostic. AC9.
- [ ] Nested-artifact and worktree-isolation checks still run and pass. AC10.
- [ ] Automated coverage includes every discovery and failure path required by
      the spec. AC11.
- [ ] Protocol, skill, agent, and command surfaces mirror the same decision
      outcomes. AC12.

---

## Seed Data Reference

No database seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Disposable Git fixture | Base, compatible, incompatible, remote-only, worktree, and divergence histories | Generated by the validator shell harness |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Compatible fixture reports `verification_blocked` | The approved base or candidate ref was not created/fetched in the fixture | Inspect the reported resolved refs and rebuild the fixture |
| Remote-only case appears local | The local candidate ref was not deleted after push | Remove only the disposable local ref and rerun |
| Worktree fixture cannot be removed | The linked worktree still has a process or checkout lock | Exit the worktree, inspect `git worktree list`, and remove only the disposable fixture |
| Divergence case reports incompatible | The local candidate no longer contains the current approved-base tip | Rebuild the history so base ancestry and tracking divergence are independent |
| JSON assertion fails | Output escaping or `jq` availability differs | Inspect raw output and the helper's dependency error before retrying |

---

## Known Limitations

- This runbook validates one selected item branch per invocation; it does not
  audit or clean historical branches across the repository.
- Destructive branch recovery is intentionally excluded and always remains a
  separate human decision.
