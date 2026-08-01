# Smoke Test Runbook: Agent Behavior No-Force-Push Guard

**Feature**: Agent behavior no-force-push guard
**Spec**: [Agent Behavior No-Force-Push Guard - Spec](../../specs/developments/20260801142411_1423-agent-behavior-no-force-push/1_1423-agent-behavior-no-force-push_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in a disposable clone or temporary Git fixture, not a repository
      with human work in progress.
- [ ] `gh`, `git`, `jq`, and Bash are available.
- [ ] The implementation PR's branch is checked out.
- [ ] The test helper can create temporary local and remote branches.

---

## Test Data

| Item | Value |
| --- | --- |
| Test PR branch | Temporary branch created by the test fixture |
| Remote tip | Captured before each guarded push attempt |
| Authorization fixture | Temporary JSON or key/value file with matching and mismatched records |
| Feature command | `scripts/development-workflow/workflow-branch-push-guard.sh` |

---

## Smoke Test Steps

### Step 1: Run the automated guard regression

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC6, AC7, AC9, AC10

1. Run `bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`.
2. Confirm the output reports passing cases for unauthorized destructive push
   blocking, safe follow-up push, local-only amend allowance, exact authorized
   exception, stale remote tip, mismatched scope, expiry, and replay.

**Expected result**: The regression exits zero and every listed guard scenario
passes.

### Step 2: Verify unauthorized destructive update stops before mutation

**Maps to**: AC1, AC2

1. In the disposable fixture, create and push a PR-like branch.
2. Attempt a guarded `force-with-lease` update without an authorization record.
3. Read the guard output.
4. Re-read the remote branch tip.

**Expected result**: The guard reports a blocked result naming the branch, the
prohibited action, and that general workflow confirmation is insufficient. The
remote tip is unchanged.

### Step 3: Verify safe follow-up commit path

**Maps to**: AC3

1. Add a normal follow-up commit to the pushed test branch.
2. Run the guarded normal push path.
3. Re-read the remote branch tip.

**Expected result**: The guard allows the push and the remote branch advances
without rewriting history.

### Step 4: Verify local-only amend remains allowed

**Maps to**: AC4

1. Create a local branch that has not been pushed.
2. Amend the local commit.
3. Run the guarded first-publish path.
4. Confirm the guard used a fresh remote-ref existence check rather than local
   upstream metadata to classify the branch as unpublished.

**Expected result**: The first publish is allowed because no published PR branch
history is rewritten and the remote branch ref did not exist immediately before
the publish.

### Step 5: Verify exact authorized exception

**Maps to**: AC5, AC6, AC7, AC8

1. Create an authorization record naming the authenticated operator, repository
   or PR, full branch ref, destructive action, expected remote tip, and
   single-use or expiry.
2. Run the guarded destructive update with the matching record.
3. Attempt to reuse the same record.
4. Repeat with records that use the wrong repository, same-named branch in a
   different repository, wrong action, stale tip, and expired authorization.

**Expected result**: The exact matching update succeeds once through a
conditional remote-tip check. Every mismatched, stale, expired, or replayed
record is blocked. Existing risk-classifier hard blockers are not cleared by
the push authorization.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Remove temporary local and remote branches created by the disposable fixture.

---

## Assertions Checklist

- [ ] Unauthorized destructive PR branch updates stop before remote mutation.
- [ ] Stop output names the branch, action, and missing exact authorization.
- [ ] Safe follow-up commits can update an already-pushed PR branch.
- [ ] Local-only amend before first publication remains allowed only when a
      fresh remote-ref existence check proves the branch is unpublished.
- [ ] Exact destructive authorization is scoped and single-use or expiring.
- [ ] Stale-tip and mismatched-scope authorizations block.
- [ ] `force_push_required` and `destructive_action_required` remain separate
      hard blocker classifications.
- [ ] Spec, plan, implementation, review-fix, and batch-supervision guidance all
      point to the shared guard.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Temporary Git fixture | Published branch, unpublished branch, remote-tip changes | Created by `test-workflow-branch-push-guard.sh` |
| Authorization records | Matching, mismatched, stale, expired, replayed | Created by `test-workflow-branch-push-guard.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Remote tip changed unexpectedly | The fixture reused an existing branch | Rerun in a fresh temp repository or delete the fixture branch |
| Authorization appears valid but blocks | Operator, full ref, action, or expected tip differs | Print the guard's parsed fields and compare to the fixture |
| Risk classifier no longer blocks | Implementation coupled push authorization to PR risk clearance | Restore independent risk-classifier blocker handling |

---

## Known Limitations

- The smoke runbook uses disposable Git fixtures; do not run destructive branch
  update tests against shared human branches.
