# Smoke Test Runbook: Prevent Unsanctioned Nested Agent PRs

**Feature**: Prevent unsanctioned nested agent PRs
**Spec**: [1_1200-prevent-unsanctioned-nested-agent-prs_specs.md](../../specs/developments/20260714164835_1200-prevent-unsanctioned-nested-agent-prs/1_1200-prevent-unsanctioned-nested-agent-prs_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in a disposable local checkout or isolated worktree.
- [ ] `gh` is authenticated for read-only PR listing in this repository.
- [ ] No real workflow PR will be opened during this smoke test.
- [ ] Temporary fixture branches, worktrees, and mocked PR data can be created
      and removed locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Issue number | `1200` |
| Expected branch | `feature/1200-canonical-path` |
| Approved base branch | `develop` |
| Wrong base branch | `main` |
| Duplicate branch | `feature/1200-duplicate-path` |
| Lookalike branch | `feature/12000-unrelated-path` |
| Backport branch | `backport/hotfix/1200-backport-path` |
| Guard helper | `scripts/development-workflow/run-nested-artifact-guard.sh` |

---

## Smoke Test Steps

### Step 1: Verify Canonical Artifact Is Allowed

**Maps to**: AC1, AC2, AC7, AC9

1. Create or mock one issue-scoped canonical worktree or branch named
   `feature/1200-canonical-path`.
2. Run the guard in `pre-create` mode with issue `1200`, expected branch
   `feature/1200-canonical-path`, and approved base `develop`.
3. Confirm the output reports `RESULT=clean`.
4. Confirm the output identifies the canonical branch or worktree and does not
   report it as a duplicate.

**Expected result**: The canonical item runner path can continue and no duplicate
work is created.

### Step 2: Detect Duplicate Local Artifact Before Creation

**Maps to**: AC1, AC2, AC8, AC10

1. Add a mocked or local duplicate branch named `feature/1200-duplicate-path`.
2. Run the guard in `pre-create` mode for expected branch
   `feature/1200-canonical-path`.
3. Confirm the output reports `RESULT=blocked_duplicate`.
4. Confirm the output includes issue `1200`, expected branch, discovered branch
   or worktree, and required next action.
5. Confirm no new worktree, branch, commit, push, or PR is created by the
   attempted nested action.

**Expected result**: The nested action stops before creating a duplicate path and
the parent runner has enough detail to resume or ask for direction.

### Step 3: Reject Missing Base Context

**Maps to**: AC3, AC4, AC6

1. Run the guard in `pre-pr` mode with an empty approved base value.
2. Confirm the output reports `RESULT=missing_base`.
3. Confirm the required next action tells the parent runner to re-dispatch with
   explicit base context.
4. Confirm no PR creation command is executed.

**Expected result**: The workflow refuses branch or PR creation instead of
falling back to the GitHub repository default branch.

### Step 4: Reject Wrong PR Base

**Maps to**: AC4, AC5, AC6, AC8

1. Mock an issue-scoped open PR for branch `feature/1200-duplicate-path` whose
   base is `main`.
2. Run the guard in `pre-pr` or `audit` mode with approved base `develop`.
3. Confirm the output reports `RESULT=wrong_base`.
4. Confirm the output includes the PR number, observed base `main`, approved base
   `develop`, and required next action.

**Expected result**: The workflow surfaces the wrong-base PR before treating the
item as ready.

### Step 5: Preserve Explicit Batch Scope

**Maps to**: AC7, AC8, AC9, AC10

1. Run the parent audit with issue scope limited to `1200`, approved base
   `develop`, and the artifact-owning `--repo-root`.
2. Include mocked artifacts for issue `1200` and a separate out-of-scope issue.
3. Confirm the audit reports only in-scope unexpected forks for issue `1200` as
   actionable for this run.
4. Confirm out-of-scope artifacts are reported as skipped warnings and are not
   mutated or advanced.

**Expected result**: The batch runner preserves the approved item scope and does
not opportunistically touch unrelated work.

### Step 6: Allow Deliberate Split Only With Approval

**Maps to**: AC11

1. Run the guard with duplicate issue-scoped artifacts and no split approval.
2. Confirm the duplicate blocks continuation.
3. Re-run with explicit split approval and approved base `develop`.
4. Confirm the output allows continuation and includes an audit line that names
   the approved split path and base branch.
5. Re-run with split approval but a mocked wrong-base PR and confirm
   `RESULT=wrong_base` still blocks continuation.

**Expected result**: Deliberate split work is possible only when it is explicit,
parent-visible, base-bound, and not masking a wrong-base PR.

### Last Step: Validate Parent Summary Content

**Maps to**: AC8, AC10, AC12

1. Run the workflow path or test fixture that simulates the parent orchestrator
   receiving guard output.
2. Confirm the parent-visible summary includes duplicate-fork stops or warnings,
   skipped out-of-scope artifacts, base-branch failures, and the canonical branch
   or PR that remains active.
3. Remove temporary branches, worktrees, and mocked data.

**Expected result**: Operators can understand the active canonical path and any
blocked nested attempts without reconstructing events from GitHub notifications.

### Automated Regression Harness

Run the committed harnesses:

```bash
bash scripts/development-workflow/tests/test-run-nested-artifact-guard.sh
bash scripts/development-workflow/tests/test-workflow-hub-pr-auth.sh
```

Expected coverage includes canonical artifacts, duplicate local/remote/worktree
artifacts, `ENG-1200` tracker prefixes, lowercase/path lookalikes,
`backport/hotfix/*` branches, wrong-base PRs, audit-only unexpected forks,
missing approved base in audit mode, repository-qualified PR scans,
explicit split approval, `gh pr list` scan failure, mixed in-scope/out-of-scope
PR data, malformed PR JSON, split approval that cannot override wrong-base PRs,
and `open-product-pr.sh --approved-base` dry-run/live mismatch stops.

---

## Assertions Checklist

- [ ] AC1: Existing issue-scoped worktrees, local branches, remote branches, and
      open PRs are checked before new artifact creation.
- [ ] AC2: Existing artifacts block or report duplicate nested work before
      mutation.
- [ ] AC3: Handoffs include intended base branch before branch or PR creation.
- [ ] AC4: Missing, ambiguous, or conflicting base context refuses branch or PR
      creation.
- [ ] AC5: Wrong PR base is rejected before submission or readiness.
- [ ] AC6: GitHub default branch is not used as an implicit workflow fallback.
- [ ] AC7: Parent orchestrators enumerate in-scope worktrees and open PRs at
      documented checkpoints.
- [ ] AC8: Duplicate-fork warnings include issue, expected artifact, discovered
      artifact, observed base where available, and required next action.
- [ ] AC9: Explicit batch scope is preserved and out-of-scope artifacts are not
      mutated.
- [ ] AC10: Final runner summaries report duplicate-fork warnings, skipped
      out-of-scope artifacts, base-context failures, and the canonical path.
- [ ] AC11: Deliberate split work requires explicit approval and explicit base.
- [ ] AC12: Regression or smoke coverage verifies duplicate, missing-base,
      wrong-base, and parent-warning paths.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Guard reports `missing_base` unexpectedly | The parent handoff did not pass approved base context | Re-dispatch with the resolved workflow base branch |
| Lookalike branch is treated as in scope | Issue matching is not anchored tightly enough | Fix branch/issue pattern matching and rerun boundary tests |
| Parent summary lacks warning details | The orchestrator consumed guard output without re-emitting it | Update parent summary handling before marking ready |
| Test leaves temporary branches or worktrees | Cleanup trap did not run or failed | Remove fixture artifacts manually, then fix the test cleanup path |

---

## Known Limitations

- The smoke test uses local or mocked artifacts and must not create real
  duplicate GitHub PRs.
- Historical duplicate PRs created before this feature are out of scope.
