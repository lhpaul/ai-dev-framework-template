# Protocol: Batch Merge

**Agent role**: Developer (or Portfolio Orchestrator when invoked from Protocol 90)
**Purpose**: Merge all ready PRs in a parallel batch into `develop` sequentially, auto-resolving trivial CHANGELOG and documentation conflicts, pausing for human input on non-trivial ones, and running `post-merge-cleanup` for each successfully merged PR.

**Shell helper**: `scripts/development-workflow/batch-merge.sh`

**Governance**: The agent assists with merge execution but does **not** merge autonomously. Every merge in this protocol requires explicit human confirmation of the merge plan (Step 3) before any `git merge` runs. This satisfies the repository's human-gate policy.

---

## When to use this protocol

- A human invokes `/batch-merge` directly (Use Case 1 — human-invoked).
- The Portfolio Orchestrator detects that all PRs in a parallel batch have reached `ready-for-human-review` and routes to this protocol (Use Case 2 — orchestrator-invoked).

In both cases, **no merge occurs until the human explicitly confirms the merge plan** (Step 3).

---

## Step 1: Discovery — Build the Candidate List

### 1a. Invoke the discovery script

**Auto-discovery mode** (no explicit PR numbers provided):

```bash
./scripts/development-workflow/batch-merge.sh discover
```

**Explicit PR list** (user supplied `#101 #102 #103` or `--prs 101,102,103`):

```bash
./scripts/development-workflow/batch-merge.sh discover --prs 101,102,103
```

### 1b. Handle the discovery result

Parse the output. Each PR candidate is a block of `KEY=VALUE` lines terminated by `---`.

- If `DISCOVERY_RESULT=none` (auto-discovery mode only): exit immediately with the message:

  > No PRs labeled `ready-for-human-review` found targeting `develop`. Nothing to merge.

  Stop — no side effects.

- If `DISCOVERY_RESULT=found`: collect all PR blocks into a candidate list.

  When the user supplied an explicit PR list the script proceeds to per-PR readiness checks regardless of label status (some may not have the `ready-for-human-review` label — those are handled in Step 2).

### 1c. Display the candidate summary table

Print a summary table so the human can see what was discovered before any gate or merge:

```text
Candidate PRs for batch merge
──────────────────────────────────────────────────────────────────────────────
 Order │  PR #  │ Title                             │ Branch              │ Labels
──────────────────────────────────────────────────────────────────────────────
   1   │  #101  │ feat: add widget                  │ feature/101-widget  │ ready-for-human-review
   2   │  #103  │ fix: correct typo                 │ fix/103-typo        │ ready-for-human-review
   3   │  #102  │ feat: update docs                 │ feature/102-docs    │ ready-for-human-review, CHANGELOG
──────────────────────────────────────────────────────────────────────────────
Merge order: non-CHANGELOG PRs first (ascending PR #), then CHANGELOG PRs (ascending PR #).
```

Fields: Order, PR number, title, branch name, labels, readiness status.

---

## Step 2: Readiness Gate

For each candidate PR:

1. If `PR_READY_LABEL=true` — it passes the gate automatically. No action needed.

2. If `PR_READY_LABEL=false` — display a warning:

   > **Warning**: PR #N — *title* — is missing the `ready-for-human-review` label.
   > Include it anyway or skip it?
   > - Type **include** to proceed with a "not fully reviewed" notation.
   > - Type **skip** to exclude it from this run (outcome: `skipped_not_ready`).

   Record the human's decision. If the human does not respond or exits, treat as **skip**.

3. Do not silently skip or silently include an unready PR. The human must explicitly decide.

After Step 2, update the candidate list: remove any PRs the human chose to skip and mark them `skipped_not_ready` in the tracking state.

---

## Step 3: Human Confirmation — Merge Plan

Display the final merge plan (only PRs approved so far):

```text
Merge plan (will be executed in this order)
──────────────────────────────────────────
  1. PR #101  feature/101-widget     (no CHANGELOG conflict expected)
  2. PR #102  feature/102-docs       (no CHANGELOG conflict expected)
  3. PR #103  fix/103-docs-update    (may cause CHANGELOG conflict — will auto-resolve)

Skipped (not ready): #104

Proceed with the merge? [yes / no / abort]
```

**No merge occurs until the human types `yes`.** If the human types `no` or `abort`, exit immediately with no side effects.

---

## Step 3.5: Pre-Merge Clean-State Check

Before starting the sequential merge loop, verify that the main working tree (the checkout that will receive the merges) is clean and on the expected integration branch:

```bash
# Verify branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
EXPECTED_BRANCH="develop"   # or the configured integration branch
if [ "$CURRENT_BRANCH" != "$EXPECTED_BRANCH" ]; then
  echo "ERROR: main working tree is on '$CURRENT_BRANCH', expected '$EXPECTED_BRANCH'. Aborting batch merge."
  exit 1
fi

# Verify no uncommitted modifications
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
  echo "ERROR: main working tree has uncommitted modifications. Aborting batch merge."
  echo "$DIRTY"
  echo "Resolve or discard these changes before running batch merge."
  exit 1
fi
```

If either check fails, **stop immediately** and report to the human. Do not attempt any merges with a dirty or mis-branched working tree — leaked modifications may be incorporated into merge commits and corrupt `develop`.

**Defense-in-depth note**: Protocol 90 Step 5.2 runs an equivalent check immediately after each Work Item Runner returns — before any orchestrator action, including batch-merge handoff. This Step 3.5 check is a second line of defense for cases where Step 5.2 was not run (e.g., manual invocation of batch-merge, or a non-parallel-batch context). Both checks are required; neither substitutes for the other.

---

## Step 4: Sequential Merge Loop

Process PRs one at a time in the approved order.

### 4.1 Per-PR merge attempt

> **Critical sequencing rule**: Call `batch-merge.sh merge --pr N` for **exactly one PR at a
> time**, inspect `MERGE_RESULT`, and fully resolve the outcome (merge success, conflict
> resolution, or abort) **before** advancing to the next PR. Never wrap multiple merge
> calls in a single non-interactive shell loop (e.g., `for pr in …; do … merge --pr $pr; done`)
> — if one PR leaves the working tree in a conflicted state, subsequent calls will fail with
> "Could not check out 'develop' — working tree is not clean" and all remaining PRs will be
> lost. The sequential discipline is mandatory even when all PRs are expected to be conflict-free.

For each PR in the approved order:

**a. Announce the merge attempt:**

> Merging PR #N: *title* (branch: *branch*)...

**b. Run the merge script:**

```bash
./scripts/development-workflow/batch-merge.sh merge --pr <number>
```

Parse the output:

- `MERGE_RESULT=clean` → merge succeeded with no conflicts. Proceed to **4.2 Post-merge steps**.
- `MERGE_RESULT=conflict` → conflicts detected. Proceed to **4.3 Conflict classification**.
- `MERGE_RESULT=failed` → unexpected failure. Report:

  > Failed to merge PR #N: *ERROR_MESSAGE*. Skipping.

  Record outcome as `failed`. Continue with the next PR.

**Abort-at-any-time gate**: Before starting each PR, check whether the human has signaled an abort (e.g., by typing "abort" at any prompt). If yes, mark all remaining PRs as `not_attempted` and jump to Step 5.

### 4.2 Post-merge steps (after a successful merge)

After a clean or resolved merge, in order:

1. **Push `develop` to origin and mark the PR as merged on GitHub:**

   As of the fix for issue #412, `batch-merge.sh merge` now performs the push and the
   `gh pr merge` call internally before returning `MERGE_RESULT=clean`. You do **not**
   need to run a separate `git push origin develop` step — the script already did it.

   If you are running a resolved-conflict merge (Step 4.3) and need to commit the
   resolution before continuing, run `git push origin develop` after staging and
   committing the resolved files. The script does not handle the post-conflict push.

2. **Verify GitHub recognizes the PR as merged** (not just closed):

   ```bash
   gh pr view <number> --json state --jq '.state'
   ```

   Expected output: `MERGED`.

   - If the state is not `MERGED` after up to 30 seconds (poll every 5 s): report `failed` for this PR, do not delete the remote branch or run cleanup, and continue with the next PR.

   > **Failure mode — CLOSED instead of MERGED (historical context)**: Before issue
   > #412 was fixed, `batch-merge.sh` did a local `git merge` + `git push` but never
   > called `gh pr merge`, so GitHub left PRs in `OPEN` state after the push. The fix
   > adds `gh pr merge --merge` inside `cmd_merge()` immediately after the push, so
   > GitHub records the PR as MERGED atomically with the merge commit. The
   > `delete-branch` subcommand still enforces the MERGED-state guard before deleting
   > the remote branch, providing a second line of defense.

3. **Delete the remote branch** using the guarded helper (which re-checks MERGED
   state immediately before deletion to prevent the CLOSED-not-MERGED failure mode):

   ```bash
   ./scripts/development-workflow/batch-merge.sh delete-branch --pr <number>
   ```

   Parse the output:

   - `DELETE_RESULT=deleted` → branch was deleted successfully.
   - `DELETE_RESULT=not_found` → branch was already gone (auto-delete or prior run). No action needed.
   - `DELETE_RESULT=skipped` → branch was NOT deleted. The `ERROR_MESSAGE` field contains
     the reason, which falls into one of two sub-cases:
     - *PR not in MERGED state*: Do **not** delete the branch manually. Investigate why
       GitHub has not yet recognised the merge (e.g., push failed silently, network error)
       before retrying.
     - *Push failure* (network/auth/permissions): Retry after resolving the underlying
       issue. The branch still exists on the remote.

4. **Run `post-merge-cleanup` for the merged branch.**

   > **Note on worktree cleanup**: Do **not** attempt to remove worktrees manually before
   > calling `post-merge-cleanup.sh`. The script already handles worktree detection and
   > removal internally — it checks for any worktree using the merged branch and removes it
   > (with locked-worktree handling) before deleting the local branch. Any manual worktree
   > removal step here is redundant and risks breaking the cleanup sequence.

   `post-merge-cleanup.sh` requires a local branch to exist. Because `batch-merge.sh` merges via `origin/<branch>` without creating a local tracking branch, create a temporary local branch first:

   ```bash
   BRANCH="$(gh pr view <number> --json headRefName --jq '.headRefName')"
   # Try origin/<branch> first; fall back to HEAD~1 if the remote branch was
   # already deleted (e.g., repo has auto-delete enabled). HEAD~1 points to the
   # pre-merge develop commit, not the PR's tip, but post-merge-cleanup.sh only
   # needs the branch *name* to delete it — the commit it points to is irrelevant.
   git branch "$BRANCH" "origin/$BRANCH" 2>/dev/null || git branch "$BRANCH" HEAD~1 2>/dev/null || true
   ./scripts/development-workflow/post-merge-cleanup.sh "$BRANCH"
   ```

   If cleanup fails: report the failure but **do not halt remaining merges**. The human can re-run cleanup manually.

5. Report the per-PR outcome immediately (see outcome codes in Step 5).

### 4.3 Conflict classification

When `MERGE_RESULT=conflict`, read `CONFLICTED_FILES` from the script output.

Classify each conflicted file:

#### CHANGELOG.md — trivial (auto-resolve)

Applies when `CHANGELOG.md` is in the conflict list.

Auto-resolution procedure:

1. Read the current (conflicted) content of `CHANGELOG.md`.
2. Locate all `<<<<<<`, `=======`, and `>>>>>>>` conflict marker blocks within the `[Unreleased]` section.
3. Extract **all unique entries** from both the `HEAD` side (entries already in `develop`) and the incoming side (entries from the PR being merged).
4. Write the resolved content:
   - Entries from the `HEAD` side first, followed by entries from the incoming side.
   - No entries dropped.
   - Remove all conflict markers.
5. Stage the resolved file:

   ```bash
   git add CHANGELOG.md
   ```

6. Report:

   > Auto-resolved CHANGELOG.md: combined entries from `develop` and PR #N.
   > HEAD entries (kept first): [brief summary]
   > Incoming entries (appended): [brief summary]

#### Documentation / protocol files — potentially trivial

Applies when a conflicted file's path starts with `docs/`, `.claude/`, `.cursor/`, or `.codex/`.

Check whether the changes are in **non-overlapping line ranges**:

- Read the conflict markers for this file.
- If the `HEAD` side and the incoming side touch **different lines** (no shared line numbers in conflict markers): auto-resolve by accepting both changes. Stage the file with `git add <file>`.
- If the conflict markers show **overlapping changes** (same lines modified on both sides): treat as **non-trivial** (see below).

Report auto-resolved files:

> Auto-resolved *file*: non-overlapping changes from `develop` and PR #N combined.

#### Non-trivial conflicts

Any conflict that is not in the above categories, or a documentation file with overlapping changes.

1. Display:

   > **Non-trivial conflict detected in PR #N**
   >
   > Conflicting files:
   > - `path/to/file.sh`
   >
   > Conflict excerpt:
   >
   > ```text
   > <<<<<<< HEAD
   > [first 10 lines of HEAD side]
   > =======
   > [first 10 lines of incoming side]
   > >>>>>>> origin/<branch>
   > ```
   >
   > Please resolve the conflict in your editor, stage the resolved files, and then reply with:
   > - **`resolved`** to complete the merge and continue.
   > - **`abort`** to cancel this PR's merge (develop will be returned to its pre-merge state).

2. **Wait for human response.**

3. If the human replies **`resolved`**:

   - Verify resolution: `git diff --check` must succeed (no conflict markers).
   - Complete the merge:

     ```bash
     git commit --no-edit
     ```

   - Record outcome as `merged_human`.
   - Proceed to **4.2 Post-merge steps**.

4. If the human replies **`abort`**:

   - Abort the merge to return `develop` to its pre-merge state:

     ```bash
     git merge --abort
     ```

   - Report:

     > Merge aborted. `develop` has been returned to its pre-merge state.
     > PR #N outcome: `skipped_conflict`.

   - Continue with the next PR.

#### Complete the merge after auto-resolution

When all conflicts have been classified and auto-resolved:

```bash
git commit --no-edit
```

Record outcome as `merged_auto`.

Proceed to **4.2 Post-merge steps**.

---

## Step 5: Final Summary

After all PRs have been processed (or the batch has been aborted), always print a structured summary:

```text
Batch Merge Summary
──────────────────────────────────────────────────────────────────────────────
 PR #  │ Title                       │ Outcome
──────────────────────────────────────────────────────────────────────────────
 #101  │ feat: add widget             │ merged_clean
 #102  │ feat: update CHANGELOG docs  │ merged_auto  (CHANGELOG combined)
 #103  │ fix: conflict fix            │ merged_human
 #104  │ feat: missing label          │ skipped_not_ready
 #105  │ fix: bad conflict            │ skipped_conflict
──────────────────────────────────────────────────────────────────────────────
Merged: 3  |  Skipped: 2  |  Failed: 0  |  Not attempted: 0
```

**Outcome codes**:

| Code | Meaning |
|---|---|
| `merged_clean` | Merged without any conflicts |
| `merged_auto` | Merged with auto-resolved trivial conflicts (CHANGELOG or non-overlapping doc files) |
| `merged_human` | Merged after human resolved non-trivial conflict(s) |
| `skipped_not_ready` | Skipped because PR lacked `ready-for-human-review` and human chose to exclude it |
| `skipped_conflict` | Skipped because human aborted conflict resolution; `develop` returned to pre-merge state |
| `failed` | Merge failed for an unexpected reason |
| `not_attempted` | PR was not processed when human aborted the entire batch |

Include details of any auto-resolved conflicts in the summary (which files, what entries were combined).

---

## Orchestrator-Invoked Mode (Use Case 2)

When called from the Portfolio Orchestrator (Protocol 90), the same flow applies:

- The orchestrator passes the PR list discovered from the batch.
- This protocol still requires explicit human confirmation at Step 3 before any merge occurs.
- The orchestrator must NOT skip or auto-approve the readiness gate (Step 2) for any unready PR.
- Non-trivial conflicts still require human resolution at Step 4.3.

The orchestrator should include the batch-merge summary in its overall `Step 6: Notify Humans` output.

---

## Safety Rules

- **`develop` must never be left in a conflicted state.** Every code path that encounters a conflict has either a resolution path or a `git merge --abort` fallback.
- **Do not use `gh pr close`.** The merge must be recognized by GitHub as a real merge, not a closed-unmerged PR.
- **Do not force-push** or rebase PR branches.
- **Already-merged PRs stay merged** even if the human aborts the batch mid-run.
- If `post-merge-cleanup` fails, report the failure and continue — do not halt remaining merges.
