# Smoke Test Runbook: Batch Merge

**Feature**: Batch Merge
**Spec**: [`docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md`](../../specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository has a `develop` branch
- [ ] `gh` CLI is authenticated (`gh auth status` succeeds)
- [ ] You have push access to the repository
- [ ] At least 3 test PRs exist targeting `develop` (see Test Data below)

---

## Test Data

Create the following test PRs before running the smoke test. Each PR should be a small, real change (e.g., adding a comment to a file, creating a test file) so merges are meaningful.

| Item | Description |
|---|---|
| PR A (no CHANGELOG) | Targets `develop`, has `ready-for-human-review` label, does NOT modify `CHANGELOG.md`. Lowest PR number of the batch. |
| PR B (with CHANGELOG) | Targets `develop`, has `ready-for-human-review` label, adds an entry under `[Unreleased]` in `CHANGELOG.md`. |
| PR C (with CHANGELOG) | Targets `develop`, has `ready-for-human-review` label, adds a different entry under `[Unreleased]` in `CHANGELOG.md`. Higher PR number than PR B. |
| PR D (no label) | Targets `develop`, does NOT have `ready-for-human-review` label. Used for readiness gate testing. |
| PR E (conflict) | Targets `develop`, has `ready-for-human-review` label, modifies a non-doc code file that will conflict with an earlier PR (e.g., same line in a script). Used for non-trivial conflict testing. |

---

## Smoke Test Steps

### Step 1: Auto-discovery with no ready PRs

**Maps to**: AC 13 (auto-discovery, no ready PRs)

1. Temporarily remove `ready-for-human-review` from all test PRs (or use a repository with no labeled PRs).
2. Run `/batch-merge` with no arguments.

**Expected result**: The command exits immediately with an informational message ("No PRs labeled ready-for-human-review found targeting develop") and no side effects. No merge is attempted.

---

### Step 2: Auto-discovery with ready PRs

**Maps to**: AC 1, AC 2

1. Restore `ready-for-human-review` labels on PRs A, B, C, and E.
2. Run `/batch-merge` with no arguments.

**Expected result**:
- The command discovers PRs A, B, C, and E and displays a candidate summary table showing PR number, title, branch, labels, and readiness status.
- The command asks for confirmation before proceeding. No merge has occurred yet.
- Cancel/decline the confirmation to avoid merging (we will test merging in later steps).

---

### Step 3: Explicit PR list mode

**Maps to**: AC 1, AC 13

1. Run `/batch-merge` specifying PR numbers for PR A and PR B explicitly (e.g., `/batch-merge #101 #102`).

**Expected result**:
- The command shows only PRs A and B in the candidate list (not C, D, or E).
- The command asks for confirmation before proceeding.
- Cancel the confirmation.

---

### Step 4: Readiness gate — missing label warning

**Maps to**: AC 3, AC 14

1. Run `/batch-merge` specifying PR D (the one without `ready-for-human-review`) explicitly.

**Expected result**:
- The command warns that PR D is missing the `ready-for-human-review` label.
- The command asks whether to include or skip PR D.
- Choose "skip" and verify PR D is excluded and noted as `skipped_not_ready`.

2. Run the same command again and this time choose "include".

**Expected result**:
- PR D is included in the candidate list with a "not fully reviewed" notation.
- The command proceeds to the confirmation step.

---

### Step 5: Merge ordering

**Maps to**: AC 4

1. Run `/batch-merge` with PRs A (no CHANGELOG), B (with CHANGELOG), C (with CHANGELOG), ensuring A has the lowest PR number.
2. Confirm the merge plan.

**Expected result**:
- The merge order displayed is: PR A first (no CHANGELOG, lowest number), then PR B (CHANGELOG, lower number), then PR C (CHANGELOG, higher number).
- Verify this order in the confirmation prompt before any merge occurs.

---

### Step 6: Clean merge

**Maps to**: AC 5, AC 11, AC 12

1. Continue from Step 5 (or start a fresh batch with only PR A).
2. Confirm the merge plan.

**Expected result**:
- PR A merges cleanly into `develop`.
- The command reports `merged_clean` for PR A immediately after the merge.
- `post-merge-cleanup` runs for PR A's branch (branch is deleted locally, develop is updated).
- PR A's conversation thread on GitHub is intact (check the PR page).
- The merge commit is visible in `develop`'s history with the PR's individual commits preserved.

---

### Step 7: CHANGELOG conflict auto-resolution

**Maps to**: AC 6

1. Continue from Step 6 (PR B is next in the queue after PR A was merged).
2. PR B adds a CHANGELOG entry under `[Unreleased]`. After PR A was merged, PR B's branch diverges from `develop`.

**Expected result**:
- When PR B is merged, a CHANGELOG conflict is detected (if PR A also modified CHANGELOG or the base has diverged).
- If a CHANGELOG conflict occurs: the command auto-resolves it by combining all `[Unreleased]` entries from both sides, preserving all entries (none dropped), and reports `merged_auto` with a description of what was combined.
- If no conflict occurs (PR A did not touch CHANGELOG): the merge is clean and reports `merged_clean`.

3. PR C is next. Since PR B just merged with CHANGELOG changes, PR C's CHANGELOG changes will conflict.

**Expected result**:
- The CHANGELOG conflict is auto-resolved: entries from PR B (already in develop) appear first, followed by entries from PR C.
- The command reports `merged_auto` with details of the combined entries.
- No entries are dropped.

---

### Step 8: Non-trivial conflict — human resolves

**Maps to**: AC 8, AC 9

1. Set up PR E so it conflicts with a file already in `develop` (a non-doc, non-CHANGELOG file).
2. Run `/batch-merge` with PR E.
3. Confirm the merge plan.

**Expected result**:
- The command detects a non-trivial conflict.
- The command displays the conflicting file path(s) and a short excerpt of the conflict markers.
- The command pauses and asks the human to resolve the conflict in their editor.

4. Resolve the conflict in your editor (edit the file, remove conflict markers, stage the resolution).
5. Signal the command to resume.

**Expected result**:
- The command completes the merge and reports `merged_human`.
- `post-merge-cleanup` runs successfully.

---

### Step 9: Non-trivial conflict — human aborts

**Maps to**: AC 10

1. Create a new PR (PR F) that will conflict with `develop` on a non-doc file.
2. Run `/batch-merge` with PR F.
3. Confirm the merge plan.
4. When the conflict is detected and the command pauses, choose to abort the merge for this PR.

**Expected result**:
- The merge is canceled (`git merge --abort`).
- `develop` is returned to its pre-merge state (verify with `git status` — clean working tree).
- PR F is reported as `skipped_conflict`.
- The command continues with any remaining PRs (or reports the final summary if PR F was the last).

---

### Step 10: Abort entire batch mid-run

**Maps to**: AC 15

1. Create 3 PRs (G, H, I) targeting `develop` with `ready-for-human-review`.
2. Run `/batch-merge` with all three.
3. Confirm the merge plan.
4. After PR G merges successfully, abort the entire batch when prompted for PR H.

**Expected result**:
- PR G remains merged (already completed).
- PR H is marked `not_attempted`.
- PR I is marked `not_attempted`.
- The final summary shows: G = `merged_clean` (or appropriate status), H = `not_attempted`, I = `not_attempted`.

---

### Step 11: Final summary completeness

**Maps to**: AC 12

1. Review the final summary from any of the above test runs.

**Expected result**:
- Every candidate PR is listed with exactly one outcome code: `merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, `failed`, or `not_attempted`.
- Auto-resolved conflicts include a description of what was combined.
- The summary is printed regardless of whether all merges succeeded.

---

### Step 12: Multi-tool availability

**Maps to**: AC 13

1. Verify `/batch-merge` is available as a Claude Code slash command.
2. Verify `/batch-merge` is available as a Cursor command (check `.cursor/commands/batch-merge.md` exists and has correct frontmatter).
3. Verify `batch-merge` is available as a Codex skill (check `.codex/skills/batch-merge/SKILL.md` exists and has correct frontmatter).

**Expected result**: All three entry points exist, reference the same protocol (`94-batch-merge-protocol.md`), and contain consistent instructions.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: Auto-discovery finds all `ready-for-human-review` PRs and displays candidate list before merging
- [ ] AC 2: Human sees confirmation prompt; no merge occurs until confirmed
- [ ] AC 3: Missing `ready-for-human-review` label causes warning and requires explicit human decision
- [ ] AC 4: PRs merge in correct order (non-CHANGELOG first by PR number, then CHANGELOG by PR number)
- [ ] AC 5: Merge preserves individual PR history, PR threads intact, no force-push
- [ ] AC 6: CHANGELOG conflict auto-resolved with all entries preserved
- [ ] AC 7: Documentation file conflict with non-overlapping changes auto-resolved
- [ ] AC 8: Non-trivial conflict pauses with file paths and conflict marker excerpt
- [ ] AC 9: After human resolves conflict, merge resumes and remaining PRs continue
- [ ] AC 10: Human abort of conflict returns `develop` to pre-merge state; PR noted as skipped
- [ ] AC 11: `post-merge-cleanup` runs after each successful merge
- [ ] AC 12: Final summary lists every PR with correct outcome code
- [ ] AC 13: Command works as Claude Code command, Cursor command, and Codex skill; auto-discovery with no ready PRs exits cleanly
- [ ] AC 14: Orchestrator-invoked mode requires human confirmation for unready PRs
- [ ] AC 15: Abort stops future merges; already-merged PRs stay; remaining marked `not_attempted`

---

## Seed Data Reference

No database seed data. Test PRs must be created manually per the Test Data section.

| Entity | Scenario | How to load |
|---|---|---|
| Test PRs A-E | Various merge scenarios | Create manually with `gh pr create` targeting `develop` |
| Test PRs G-I | Abort scenario | Create manually with `gh pr create` targeting `develop` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `gh pr list` returns no PRs | `gh` not authenticated or wrong repo | Run `gh auth status` and verify you are in the correct repo |
| `git merge` fails with "not something we can merge" | Remote branch not fetched | Ensure `git fetch origin` runs before merge attempt |
| `post-merge-cleanup.sh` fails with "branch does not exist" | Branch already deleted remotely | Script should handle this gracefully; verify branch name is correct |
| CHANGELOG auto-resolution drops entries | Bug in conflict marker parsing | Check the agent's conflict resolution logic; ensure both sides of markers are read completely |
| `develop` left in conflicted state | `git merge --abort` not called on failure path | Verify all error paths include `git merge --abort`; manually run it to recover |

---

## Known Limitations

- This smoke test requires creating real PRs in a repository, which means it cannot be fully automated without a dedicated test repository.
- The CHANGELOG auto-resolution test (Step 7) depends on the specific structure of the `[Unreleased]` section; edge cases with unusual formatting may not be covered.
- The orchestrator-invoked mode (AC 14) is a stretch goal and may not be fully testable until the orchestrator integration is complete.
