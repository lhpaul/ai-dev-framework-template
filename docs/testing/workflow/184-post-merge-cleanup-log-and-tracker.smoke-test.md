# Smoke Test Runbook: fix(post-merge-cleanup) — Contradictory Log Output and Missing Tracker Status Update

**Feature**: Unified issue-number detection and automatic tracker status update in `post-merge-cleanup.sh`
**Spec**: [1_post-merge-cleanup-log-and-tracker_specs.md](../../specs/developments/20260417203259_post-merge-cleanup-log-and-tracker/1_post-merge-cleanup-log-and-tracker_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in the repository root: `cd /path/to/ai-dev-framework-template`
- [ ] `gh` CLI is authenticated: `gh auth status`
- [ ] `shellcheck` is available (optional but recommended): `shellcheck --version`
- [ ] The implementation branch has been built and `scripts/development-workflow/post-merge-cleanup.sh` reflects the changes from this PR
- [ ] For Step 5 (tracker update), you have access to a GitHub Projects v2 project with Status options: `Spec Ready`, `Plan Ready`, `Merged`

> **Important**: Steps 1–4 can be run without a real GitHub Projects setup by checking only the log output and return code. Step 5 requires a live project. Use `GITHUB_PROJECT_NUMBER` and `GITHUB_PROJECT_OWNER` environment variables to point at a test project if needed.

---

## Test Data

| Item | Value |
|---|---|
| Repo root | `/path/to/ai-dev-framework-template` |
| Test branch (spec) | `spec/184-smoke-test-dummy` (create locally, do not push) |
| Test branch (plan) | `implementation-plan/184-smoke-test-dummy` (create locally, do not push) |
| Test branch (feature) | `feature/184-smoke-test-dummy` (create locally, do not push) |
| Test branch (no issue) | `feature/my-legacy-feature` (create locally, do not push) |
| GitHub issue | `#184` (must exist in the repo) |
| Project number | `$GITHUB_PROJECT_NUMBER` (set in environment) |
| Project owner | `$GITHUB_PROJECT_OWNER` (set in environment) |

---

## Smoke Test Steps

### Step 0: Prepare test branches

Create four dummy local branches to use as inputs. These do not need to be pushed to origin or have any commits beyond the current `develop` HEAD.

```bash
git checkout develop
git branch spec/184-smoke-test-dummy
git branch implementation-plan/184-smoke-test-dummy
git branch feature/184-smoke-test-dummy
git branch feature/my-legacy-feature
```

**Expected result**: All four branches created locally. You are still on `develop`.

---

### Step 1: Spec branch — single log line, no "No issue number detected"

**Maps to**: Acceptance Criteria 1 and 4

```bash
# Capture output; the script will try to delete the branch and switch to develop.
# We need to be on develop already and not on the test branch.
# The script exits 0 even if tracker update warns.
output=$(./scripts/development-workflow/post-merge-cleanup.sh spec/184-smoke-test-dummy 2>&1)
echo "$output"
```

**Expected result**:

1. Output contains exactly **one** line that mentions issue `#184` (e.g., contains "184" and "stays open" or "Spec Ready").
2. Output does **not** contain the phrase `No issue number detected`.
3. Output **does not** contain two separate messages about the issue — only one.
4. Script exits 0.
5. Local branch `spec/184-smoke-test-dummy` is deleted.
6. If GitHub Projects is configured: output contains a line about "Updating tracker status" or "Spec Ready"; project board for issue #184 shows `Spec Ready`.
7. If GitHub Projects is not configured (env vars absent): output contains a `Warning:` line mentioning missing project config; script still exits 0.

---

### Step 2: Implementation-plan branch — single log line, tracker update for Plan Ready

**Maps to**: Acceptance Criteria 2 and 5

```bash
# Re-create the branch (it was NOT deleted in Step 1 since we passed spec/ above)
git branch implementation-plan/184-smoke-test-dummy 2>/dev/null || true
output=$(./scripts/development-workflow/post-merge-cleanup.sh implementation-plan/184-smoke-test-dummy 2>&1)
echo "$output"
```

**Expected result**:

1. Output contains exactly **one** line mentioning issue `#184`.
2. Output does **not** contain `No issue number detected`.
3. Script exits 0.
4. Local branch `implementation-plan/184-smoke-test-dummy` is deleted.
5. If GitHub Projects is configured: output mentions `Plan Ready`; project board for issue #184 shows `Plan Ready`.
6. If GitHub Projects is not configured: `Warning:` line present; script exits 0.

---

### Step 3: Feature branch — issue close preserved, tracker update for Merged

**Maps to**: Acceptance Criterion 3

```bash
git branch feature/184-smoke-test-dummy 2>/dev/null || true
output=$(./scripts/development-workflow/post-merge-cleanup.sh feature/184-smoke-test-dummy 2>&1)
echo "$output"
```

**Expected result**:

1. Output does **not** contain `No issue number detected`.
2. Script attempts to close issue #184 (may log "Issue #184 is already CLOSED" or attempt `gh issue close` — both are acceptable).
3. Script exits 0.
4. Local branch `feature/184-smoke-test-dummy` is deleted.
5. If GitHub Projects is configured: output mentions `Merged`; project board for issue #184 shows `Merged`.
6. If GitHub Projects is not configured: `Warning:` line present; script exits 0.

---

### Step 4: Branch with no issue number — single skip message, no tracker update

**Maps to**: Acceptance Criteria 6

```bash
git branch feature/my-legacy-feature 2>/dev/null || true
output=$(./scripts/development-workflow/post-merge-cleanup.sh feature/my-legacy-feature 2>&1)
echo "$output"
```

**Expected result**:

1. Output contains exactly **one** line matching `No issue number detected in branch name`.
2. Output does **not** contain any mention of a tracker update.
3. Script exits 0.
4. Local branch `feature/my-legacy-feature` is deleted.

---

### Step 5: GitHub Projects misconfigured — warning, clean exit

**Maps to**: Acceptance Criterion 7

```bash
# Temporarily unset project env vars to simulate missing config
git branch feature/184-smoke-test-dummy 2>/dev/null || true
output=$(GITHUB_PROJECT_NUMBER="" GITHUB_PROJECT_OWNER="" \
  ./scripts/development-workflow/post-merge-cleanup.sh feature/184-smoke-test-dummy 2>&1)
exit_code=$?
echo "$output"
echo "Exit code: $exit_code"
```

**Expected result**:

1. Script outputs a `Warning:` line mentioning missing `GITHUB_PROJECT_NUMBER` or `GITHUB_PROJECT_OWNER`.
2. Script exits 0 (git cleanup completed successfully).
3. If the branch was not already deleted, it is deleted now. (If deleted in Step 3, re-create it first with `git branch feature/184-smoke-test-dummy`.)

---

### Last Step: Verify main working tree is clean

```bash
git status --porcelain
git branch --show-current
```

**Expected result**: Output is empty (no uncommitted changes). Current branch is `develop`.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] **AC 1**: `post-merge-cleanup.sh spec/<N>-...` → exactly one log line about issue; no "No issue number detected" message (Step 1)
- [ ] **AC 2**: `post-merge-cleanup.sh implementation-plan/<N>-...` → exactly one log line about issue; no "No issue number detected" message (Step 2)
- [ ] **AC 3**: `post-merge-cleanup.sh feature/<N>-...` → GitHub Projects v2 Status set to `Merged`; existing issue-close behavior preserved (Step 3)
- [ ] **AC 4**: `post-merge-cleanup.sh spec/<N>-...` → GitHub Projects v2 Status set to `Spec Ready` (Step 1, with live project)
- [ ] **AC 5**: `post-merge-cleanup.sh implementation-plan/<N>-...` → GitHub Projects v2 Status set to `Plan Ready` (Step 2, with live project)
- [ ] **AC 6**: Branch with no numeric issue number → single "No issue number detected" line; no tracker update (Step 4)
- [ ] **AC 7**: GitHub Projects misconfigured → `Warning:` line; script exits 0; git cleanup completes (Step 5)

---

## Seed Data Reference

Not applicable. No seed data is required. Test branches are created locally during the test and deleted by the script under test.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Local branch 'spec/184-smoke-test-dummy' does not exist` | Branch was not created in Step 0 | Run `git branch spec/184-smoke-test-dummy` from `develop` |
| `You are on 'develop'. Pass the merged branch name…` | Passed wrong argument or no arg | Pass the branch name explicitly as the first argument |
| `Warning: GITHUB_PROJECT_OWNER or GITHUB_PROJECT_NUMBER not set` | Env vars not exported | Export `GITHUB_PROJECT_NUMBER` and `GITHUB_PROJECT_OWNER` before running |
| `Warning: could not resolve project ID` | Wrong project number or owner | Verify with `gh project list --owner <OWNER>` |
| `Warning: issue #184 not found in project` | Issue not added to the project | Add issue #184 to the project via GitHub UI or `gh project item-add` |
| Two log lines appear for spec/plan branch | Bug not fully fixed | Review the unified extraction block; ensure `STAGE_ISSUE` variable path is removed |

---

## Known Limitations

- Steps 1–4 validate log output structure but cannot assert tracker field values without a live GitHub Projects setup. Use Step 5 env-var override to test the failure path without real credentials.
- The script runs real `git checkout develop` and `git branch -D` operations; ensure test branches are truly throwaway before running.
