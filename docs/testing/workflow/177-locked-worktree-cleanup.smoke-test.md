# Smoke Test Runbook: fix(post-merge-cleanup): handle locked Claude worktrees

**Feature**: Locked-worktree cleanup fallback in `post-merge-cleanup.sh`
**Spec**: [`docs/specs/developments/20260417194717_177-locked-worktree-cleanup/1_177-locked-worktree-cleanup_specs.md`](../../specs/developments/20260417194717_177-locked-worktree-cleanup/1_177-locked-worktree-cleanup_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You have a working git installation (2.17+ for double-force support)
- [ ] `scripts/development-workflow/post-merge-cleanup.sh` has been updated with the lock-aware removal block
- [ ] You can create temporary directories under `/tmp` (or equivalent on your OS)
- [ ] No external services are required; all steps use local git operations only

---

## Test Data

| Item | Value |
|---|---|
| Temp repo root | `/tmp/smoke-177/main-repo` |
| Worktree path | `/tmp/smoke-177/wt-test` |
| Test branch | `feature/177-smoke-test` |

---

## Setup: Create a Temporary Test Repository

Run the following once before any scenario:

```bash
rm -rf /tmp/smoke-177
mkdir -p /tmp/smoke-177/main-repo
cd /tmp/smoke-177/main-repo
git init
git config user.email "smoke@test.local"
git config user.name "Smoke Test"
echo "init" > README.md
git add README.md
git commit -m "init"
git checkout -b develop
echo "develop" >> README.md
git add README.md
git commit -m "develop commit"
git checkout -b feature/177-smoke-test
echo "feature" >> README.md
git add README.md
git commit -m "feature commit"
git checkout develop
```

The main repo now has `feature/177-smoke-test` as a local branch checked out on `develop`.

---

## Smoke Test Steps

### Scenario 1: Locked worktree — unlock-then-remove path (AC 1, AC 2, AC 6)

**Maps to**: Use Case 1 and Acceptance Criteria 1, 2, 6

**Setup**:
```bash
cd /tmp/smoke-177/main-repo
git worktree add /tmp/smoke-177/wt-test feature/177-smoke-test
git worktree lock /tmp/smoke-177/wt-test --reason "claude agent agent-test (pid 99999)"
```

**Execute**:
```bash
cd /tmp/smoke-177/main-repo
./path/to/scripts/development-workflow/post-merge-cleanup.sh feature/177-smoke-test
```

> Replace `./path/to/scripts` with the actual path to the repository's `scripts` directory.

**Expected results**:
- Script prints: `WARNING: Worktree '/tmp/smoke-177/wt-test' is locked (reason: claude agent agent-test (pid 99999)). Force-overriding — if this worktree belongs to an active agent, data may be lost.`
- Script does NOT exit non-zero
- Worktree `/tmp/smoke-177/wt-test` is removed (directory no longer exists)
- Branch `feature/177-smoke-test` is deleted from local repo
- Script ends with `Done. You are on develop and 'feature/177-smoke-test' has been removed locally.`

**Verification**:
```bash
git worktree list  # should show only the main worktree
git branch         # feature/177-smoke-test should not appear
ls /tmp/smoke-177/wt-test 2>&1  # should error: No such file or directory
```

**Teardown** (for next scenario):
```bash
cd /tmp/smoke-177/main-repo
git checkout -b feature/177-smoke-test
git checkout develop
```

---

### Scenario 2: Unlock unavailable — double-force fallback path (AC 1, AC 2, AC 6)

**Maps to**: Use Case 2 and Acceptance Criteria 1, 2, 6

> This scenario tests the fallback by temporarily making `git worktree unlock` fail (e.g., via a wrapper function). The simplest approach is to test with a git version that does not support `unlock`, or to stub it in the script temporarily. For manual smoke testing, verify by reading the code path and confirming the fallback `--force --force` call is present and reachable.

**Manual verification steps**:
1. Inspect the updated `scripts/development-workflow/post-merge-cleanup.sh` and confirm the `else` branch after the `unlock` check contains `git worktree remove "$WORKTREE_PATH" --force --force`.
2. Confirm the `echo "WARNING: 'git worktree unlock' unavailable or failed; using double-force fallback."` message is present in that branch.
3. Optionally: temporarily wrap `git worktree unlock` in the script with a function that always returns 1, then re-run Scenario 1's setup and execute steps, confirming the fallback warning appears.

**Expected results**:
- The fallback warning is printed.
- Worktree is successfully removed.
- Script continues to branch deletion and cleanup.

---

### Scenario 3: Non-locked worktree — standard path unchanged (AC 3)

**Maps to**: Use Case 3 and Acceptance Criterion 3

**Setup**:
```bash
cd /tmp/smoke-177/main-repo
# Ensure feature/177-smoke-test branch exists (re-create if deleted in Scenario 1)
git branch feature/177-smoke-test 2>/dev/null || true
git worktree add /tmp/smoke-177/wt-test feature/177-smoke-test
# Do NOT lock the worktree
```

**Execute**:
```bash
cd /tmp/smoke-177/main-repo
./path/to/scripts/development-workflow/post-merge-cleanup.sh feature/177-smoke-test
```

**Expected results**:
- No `WARNING:` lines appear in the output
- Worktree `/tmp/smoke-177/wt-test` is removed
- Branch `feature/177-smoke-test` is deleted
- Script ends cleanly

**Verification**:
```bash
git worktree list  # main worktree only
git branch         # feature/177-smoke-test absent
```

---

### Scenario 4: No worktree for branch — unchanged behavior (AC 4)

**Maps to**: Use Case 4 and Acceptance Criterion 4

**Setup**:
```bash
cd /tmp/smoke-177/main-repo
# Ensure no worktree uses the branch (already cleaned from Scenario 3)
git branch feature/177-smoke-test 2>/dev/null || true
git worktree list  # confirm no worktree points to feature/177-smoke-test
```

**Execute**:
```bash
cd /tmp/smoke-177/main-repo
./path/to/scripts/development-workflow/post-merge-cleanup.sh feature/177-smoke-test
```

**Expected results**:
- No worktree-related output (the worktree block is skipped)
- Branch `feature/177-smoke-test` is deleted directly
- Script ends cleanly

---

### Scenario 5: Both remediation paths fail — non-zero exit (AC 5)

**Maps to**: Acceptance Criterion 5

> This scenario requires injecting a failure into both the `unlock + remove` path and the `--force --force` path. For manual smoke testing, verify by code inspection: confirm the `exit 1` and `echo ... >&2` calls are present in the final failure branch.

**Manual verification steps**:
1. Inspect the updated script and confirm that after both paths fail, there is an `exit 1` (or equivalent non-zero exit).
2. Confirm the error message is printed to stderr (`>&2`), not stdout.
3. Confirm the script does NOT continue to the branch-deletion step after a failed worktree removal.

---

### Final Step: Validate & Clean Up

```bash
rm -rf /tmp/smoke-177
```

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: Locked worktree removal attempt fails with lock error → script logs force-override warning and successfully removes the worktree via the unlock-then-remove or fallback path.
- [ ] AC 2: Force-override warning includes the worktree path and the detected lock reason.
- [ ] AC 3: Non-locked worktree → standard single removal succeeds and no warning is emitted.
- [ ] AC 4: No worktree for merged branch → behavior unchanged (worktree block skipped).
- [ ] AC 5: Both remediation attempts fail → script exits non-zero with clear error; does not silently continue.
- [ ] AC 6: End-to-end: `post-merge-cleanup.sh <branch>` on a locked-worktree branch completes successfully without manual intervention.

---

## Seed Data Reference

| Entity | Scenario | How to load |
|---|---|---|
| Temporary git repo | All scenarios | Run the Setup block above (`mkdir`, `git init`, `git commit`, etc.) |
| Locked worktree | Scenarios 1, 2 | `git worktree lock <path> --reason "<reason>"` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `fatal: cannot remove a locked working tree` still exits script | Lock-detection grep pattern does not match git's error message on this git version | Check `git worktree remove --force /tmp/smoke-177/wt-test 2>&1` output and adjust the grep pattern in the script |
| `git worktree unlock` command not found | git version < 2.17 | Upgrade git, or verify the double-force fallback path is triggered correctly |
| `rm -rf /tmp/smoke-177` leaves files | OS or permission issue | Run with `sudo` or adjust the temp directory |

---

## Known Limitations

- Scenario 2 (unlock unavailable) is best verified by code inspection or by stub injection rather than a real git version downgrade.
- Scenario 5 (both paths fail) requires manual code inspection or test harness injection; a real filesystem failure is difficult to produce reliably in a smoke test.
