# Protocol: Batch Merge

**Agent role**: Developer (or Portfolio Orchestrator when invoked from Protocol 90)
**Purpose**: Merge all ready PRs in a parallel batch into the target integration branch (`develop` by default, or any epic integration branch) sequentially, auto-resolving trivial CHANGELOG and documentation conflicts (including duplicate section headers introduced by clean merges), pausing for human input on non-trivial ones, and running `post-merge-cleanup` for each successfully merged PR.

**Shell helper**: `scripts/development-workflow/batch-merge.sh`

**Governance**: The agent assists with merge execution. The merge plan is printed for visibility before execution, but no interactive approval is required — merges proceed immediately after the plan is displayed.

---

## Release Evidence Ownership

When a batch includes workflow-hub product release work, use the release
artifact ownership contract before handoff: product changelog entries, release
branches, tags, GitHub Releases, deployment evidence, and product cleanup
evidence are product-repository-owned; delivery manifests and tracker
reconciliation evidence are hub-owned.

Use `scripts/development-workflow/component-release-target.sh` and
`scripts/development-workflow/component-release-evidence.sh` from the hub
checkout to preserve the selected product repository, artifact owners,
`release_correlation_key`, and `contract_revision` through any release evidence
handoff. See the [Prepare Release Protocol](05-prepare-release-protocol.md)
before preparing or cleaning a component release branch.

---

## When to use this protocol

- A human invokes `/batch-merge` directly (Use Case 1 — human-invoked).
- The Portfolio Orchestrator detects that all PRs in a parallel batch have reached `ready-for-human-review` and routes to this protocol (Use Case 2 — orchestrator-invoked).

In both cases, the merge plan is displayed before any `git merge` runs, but execution proceeds immediately without waiting for user input.

---

## Step 1: Discovery — Build the Candidate List

### 1a. Invoke the discovery script

**Auto-discovery mode** (no explicit PR numbers provided):

```bash
./scripts/development-workflow/batch-merge.sh discover
# Or, to merge into an epic integration branch instead of develop:
./scripts/development-workflow/batch-merge.sh --base develop-<slug> discover
```

**Explicit PR list** (user supplied `#101 #102 #103` or `--prs 101,102,103`):

```bash
./scripts/development-workflow/batch-merge.sh discover --prs 101,102,103
# Or, with an integration branch override:
./scripts/development-workflow/batch-merge.sh --base develop-<slug> discover --prs 101,102,103
```

The `--base` flag is a global option placed **before** the subcommand name. It defaults to `develop` and must be passed consistently to `discover`, `merge`, and `delete-branch` when targeting an integration branch other than `develop`.

### 1b. Handle the discovery result

Parse the output. Each PR candidate is a block of `KEY=VALUE` lines terminated by `---`.

- If `DISCOVERY_RESULT=none` (auto-discovery mode only): exit immediately with the message:

  > No PRs labeled `ready-for-human-review` found targeting `<base>`. Nothing to merge.

  where `<base>` is the value passed to `--base` (defaults to `develop`). Stop — no side effects.

- If `DISCOVERY_RESULT=found`: collect all PR blocks into a candidate list.

  When the user supplied an explicit PR list the script proceeds to per-PR readiness checks regardless of label status (some may not have the `ready-for-human-review` label — those are handled in Step 2).

  If discovery warns that a PR is labeled `human-checkpoint-required`, treat it
  as skipped until the named checkpoint is satisfied or waived. Do not add it
  back to the candidate list just because `ready-for-human-review` is present.
  To inspect an explicitly supplied checkpointed PR in the candidate table after
  human confirmation, rerun discovery with `--include-checkpointed`; merge mode
  will still refuse the stale label, so the checkpoint lifecycle helper must
  record `satisfied` or `waived` evidence and sync labels before the merge step.

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

   > **Warning**: PR #N — _title_ — is missing the `ready-for-human-review` label.
   > Include it anyway or skip it?
   >
   > - Type **include** to proceed with a "not fully reviewed" notation.
   > - Type **skip** to exclude it from this run (outcome: `skipped_not_ready`).

   Record the human's decision. If the human does not respond or exits, treat as **skip**.
   Keep a comma-separated `APPROVED_UNREADY_PRS` list containing every unready PR
   the human explicitly included. If none were included, keep it empty.

3. Do not silently skip or silently include an unready PR. The human must explicitly decide.

4. If `PR_HAS_HUMAN_CHECKPOINT=true`, display a warning:

   > **Warning**: PR #N — _title_ — still requires a human checkpoint.
   > The required action must be completed and recorded before this batch can
   > merge it.
   >
   > - Type **satisfied** only after the checkpoint lifecycle evidence records
   >   `satisfied` or `waived` and the `human-checkpoint-required` label has
   >   been synced away.
   > - Type **skip** to exclude it from this run (outcome:
   >   `skipped_human_checkpoint`).

   Do not proceed on a verbal "include" alone. The merge helper refuses a stale
   `human-checkpoint-required` label, so the concrete action is to satisfy or
   waive the checkpoint, rerun label sync, rerun discovery, and continue only
   after `PR_HAS_HUMAN_CHECKPOINT=false`.

After Step 2, update the candidate list: remove any PRs the human chose to skip and mark them `skipped_not_ready` in the tracking state.

---

## Step 3: Merge Plan Display

Display the final merge plan (only PRs approved so far) and proceed immediately:

```text
Merge plan (will be executed in this order)
──────────────────────────────────────────
  1. PR #101  feature/101-widget     (no CHANGELOG conflict expected)
  2. PR #102  feature/102-docs       (no CHANGELOG conflict expected)
  3. PR #103  fix/103-docs-update    (may cause CHANGELOG conflict — will auto-resolve)

Skipped (not ready): #104
```

After printing the plan, proceed directly to Step 3.5 without waiting for user input.

---

## Step 3.5: Pre-Merge Clean-State Check

Before starting the sequential merge loop, verify that the main working tree (the checkout that will receive the merges) is clean and on the expected integration branch:

```bash
# Verify branch — use the same --base value passed to batch-merge.sh
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
EXPECTED_BRANCH="${TARGET_BASE:-develop}"   # develop, or the --base override
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

If either check fails, **stop immediately** and report to the human. Do not attempt any merges with a dirty or mis-branched working tree — leaked modifications may be incorporated into merge commits and corrupt the base branch.

**Defense-in-depth note**: Protocol 90 Step 5.2 runs an equivalent check immediately after each Work Item Runner returns — before any orchestrator action, including batch-merge handoff. This Step 3.5 check is a second line of defense for cases where Step 5.2 was not run (e.g., manual invocation of batch-merge, or a non-parallel-batch context). Both checks are required; neither substitutes for the other.

---

## Step 4: Sequential Merge Loop

Process PRs one at a time in the approved order.

### 4.1 Per-PR merge attempt

> **Critical sequencing rule**: Call `batch-merge.sh merge --pr N --expected-head-sha <reviewed-headRefOid>` for **exactly one PR at a
> time**, inspect `MERGE_RESULT`, and fully resolve the outcome (merge success, conflict
> resolution, or abort) **before** advancing to the next PR. Never wrap multiple merge
> calls in a single non-interactive shell loop (e.g., `for pr in …; do … merge --pr $pr; done`)
> — if one PR leaves the working tree in a conflicted state, subsequent calls will fail with
> "Could not check out '<base>' — working tree is not clean" and all remaining PRs will be
> lost. The sequential discipline is mandatory even when all PRs are expected to be conflict-free.

For each PR in the approved order:

**a. Announce the merge attempt:**

> Merging PR #N: _title_ (branch: _branch_)...

**b. Capture the reviewed PR head SHA from the readiness evidence:**

Use the `headRefOid` captured during the latest readiness/review gate for this
PR. `batch-merge.sh discover` emits this as `PR_HEAD_SHA` in each candidate
record for handoff into the merge command. If that SHA is missing or stale, stop
and rerun the review/CI readiness gate before merging.

**c. Run the merge script with the reviewed SHA:**

<!-- workflow-shell-contract: bash-zsh -->
```bash
# Standard (merging into develop):
./scripts/development-workflow/batch-merge.sh merge --pr <number> --expected-head-sha <reviewed-headRefOid>

# Integration-branch override (merging into develop-<slug> or other base):
./scripts/development-workflow/batch-merge.sh --base develop-<slug> merge --pr <number> --expected-head-sha <reviewed-headRefOid>
# Equivalent using the env var form:
# TARGET_BASE=develop-<slug> ./scripts/development-workflow/batch-merge.sh merge --pr <number> --expected-head-sha <reviewed-headRefOid>
```

Parse the output:

- `MERGE_RESULT=clean` → merge succeeded with no conflicts. Check `CHANGELOG_DEDUPED` (see below), then proceed to **4.2 Post-merge steps**.
- `MERGE_RESULT=conflict` → conflicts detected. Proceed to **4.3 Conflict classification**.
- `MERGE_RESULT=failed` → unexpected failure. Report:

  > Failed to merge PR #N: _ERROR_MESSAGE_. Skipping.

  Record outcome as `failed`. Continue with the next PR.

**`CHANGELOG_DEDUPED` field (clean merges only)**: When `MERGE_RESULT=clean`, the script also emits `CHANGELOG_DEDUPED=true|false` to indicate whether the post-merge CHANGELOG deduplication guard ran and made changes.

- `CHANGELOG_DEDUPED=false` → no duplicate section headers were found (normal case).
- `CHANGELOG_DEDUPED=true` → the merge introduced duplicate `### Category` headers within `[Unreleased]` (e.g., two `### Fixed` sections). The script auto-consolidated them and amended the merge commit before pushing. Include a note in the Step 5 summary under the merged PR's outcome (use outcome code `merged_clean` with a parenthetical `(CHANGELOG deduped)` suffix).

This guard prevents the scenario where a clean git merge silently produces a structurally invalid CHANGELOG (no conflict markers, but two `### Fixed` blocks in the same `## [Unreleased]` section). If a `WARNING` about residual duplicates appears in the script's stderr output, the automatic consolidation did not fully resolve all duplicates — a manual fix to `CHANGELOG.md` on `develop` is required before the next batch merge.

**Abort-at-any-time gate**: Before starting each PR, check whether the human has signaled an abort (e.g., by typing "abort" at any prompt). If yes, mark all remaining PRs as `not_attempted` and jump to Step 5.

### 4.2 Post-merge steps (after a successful merge)

After a clean or resolved merge, in order:

1. **Push the base branch to origin and mark the PR as merged on GitHub:**

   As of the fix for issue #412, `batch-merge.sh merge` now performs the push and the
   `gh pr merge` call internally before returning `MERGE_RESULT=clean`. You do **not**
   need to run a separate `git push origin <base>` step — the script already did it.

   If you are running a resolved-conflict merge (Step 4.3) and need to commit the
   resolution before continuing, run `git push origin <base>` after staging and
   committing the resolved files. The script does not handle the post-conflict push.

2. **Verify GitHub recognizes the PR as merged** (not just closed):

   ```bash
   gh pr view <number> --json state --jq '.state'
   ```

   Expected output: `MERGED`.
   - If the state is not `MERGED` after up to 30 seconds (poll every 5 s): report `failed` for this PR, do not delete the remote branch or run cleanup, and continue with the next PR.
   - If the script emitted a `WARNING: gh pr merge failed` line to stderr, that is a signal that this MERGED-state check is especially important — the local merge and push to the base branch succeeded, but the GitHub merge-mark may have failed. `MERGE_RESULT=clean` on the same run refers to the local merge only and does **not** mean this PR is done: the poll above is what decides. If it does not converge to `MERGED` within 30 s, this PR is `failed` even though `MERGE_RESULT=clean` was printed.

   > **Failure mode — CLOSED instead of MERGED (historical context)**: Before issue
   > #412 was fixed, `batch-merge.sh` did a local `git merge` but neither pushed nor
   > called `gh pr merge`, so GitHub left PRs in `OPEN` state. The fix adds `git push`
   > and `gh pr merge --merge` inside `cmd_merge()` immediately after a successful
   > local merge. When `gh pr merge` fails for a non-idempotent reason, a warning is
   > emitted to stderr and this MERGED-state poll acts as the safety net. The
   > `delete-branch` subcommand also enforces the MERGED-state guard before deletion.

   > **Exceptional reviewer access bypass**: If a PR was excluded from the
   > normal batch route because `run-epic-delegated-gate.sh` returned
   > `exceptional_bypass_authorized`, do not merge it through `batch-merge.sh`.
   > The runner must use the exact named `gh pr merge <pr> --admin --match-head-commit <authorized-head-sha>` command only
   > after verifying the PR/SHA/fingerprint authorization and pre-attempt
   > `reviewer-access-bypass` audit marker. After the one attempt, verify
   > GitHub's live PR state, update the same audit marker, fetch the refreshed
   > base, and rediscover the remaining batch PRs. This exception never applies
   > to unaffected PRs.

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
     - _PR not in MERGED state_: Do **not** delete the branch manually. Investigate why
       GitHub has not yet recognised the merge (e.g., push failed silently, network error)
       before retrying.
     - _Push failure_ (network/auth/permissions): Retry after resolving the underlying
       issue. The branch still exists on the remote.

4. **Run `post-merge-cleanup` for the merged branch.**

   > **Note on worktree cleanup**: Do **not** attempt to remove worktrees manually before
   > calling `post-merge-cleanup.sh`. The script already handles worktree detection and
   > removal internally — it checks for any worktree using the merged branch and removes it
   > (with locked-worktree handling) before deleting the local branch. Any manual worktree
   > removal step here is redundant and risks breaking the cleanup sequence.

   `post-merge-cleanup.sh` verifies or performs guarded remote cleanup for
   implementation branches. If `batch-merge.sh delete-branch` already removed
   the remote branch, `post-merge-cleanup.sh` reports
   `REMOTE_DELETE_RESULT=not_found` / `REMOTE_DELETE_STATUS=already_absent` and
   continues. If the remote implementation branch still exists, the helper
   deletes it only after confirming the PR is `MERGED`; if deletion fails, the
   cleanup is non-terminal.

   The helper requires a local branch to exist. Because `batch-merge.sh` merges
   via `origin/<branch>` without creating a local tracking branch, create a
   temporary local branch first:

   <!-- workflow-shell-contract: bash-zsh -->
   ```bash
   PR_NUMBER="<number>"
   BRANCH="$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName')" || {
     printf 'ERROR: could not resolve head branch for PR #%s\n' "$PR_NUMBER" >&2
     exit 1
   }
   [ -n "$BRANCH" ] || {
     printf 'ERROR: PR #%s has no head branch\n' "$PR_NUMBER" >&2
     exit 1
   }
   BASE_BRANCH="${TARGET_BASE:-develop}"
   # Try origin/<branch> first; fall back to HEAD~1 if the remote branch was
   # already deleted (e.g., repo has auto-delete enabled). HEAD~1 points to the
   # pre-merge develop commit, not the PR's tip, but post-merge-cleanup.sh only
   # needs the branch *name* to delete it — the commit it points to is irrelevant.
   git branch "$BRANCH" "origin/$BRANCH" 2>/dev/null || git branch "$BRANCH" HEAD~1 2>/dev/null || true
   ./scripts/development-workflow/post-merge-cleanup.sh --base "$BASE_BRANCH" --pr "$PR_NUMBER" "$BRANCH"
   ```

   If cleanup fails: report the failure but **do not halt remaining merges**. The human can re-run cleanup manually.

5. **Recheck remaining in-scope PRs before selecting the next merge.**

   When the approved batch has any unmerged in-scope PRs after this merge,
   prior mergeability evidence for those PRs is stale. Run:

   <!-- workflow-shell-contract: bash -->
   ```bash
   bash ./scripts/development-workflow/batch-merge.sh recheck-remaining \
     --prs <comma-separated-approved-pr-list> \
     --after-merged-pr <number> \
     --base "$BASE_BRANCH" \
     --approved-unready-prs "$APPROVED_UNREADY_PRS" \
     --reviewed-head-shas "$REVIEWED_HEAD_SHAS" \
     --annotate
   ```

   `APPROVED_UNREADY_PRS` must be the same explicit include list recorded in
   Step 2, not recomputed from current labels. The helper validates that every
   approved-unready PR is still part of the frozen approved PR list.

   `REVIEWED_HEAD_SHAS` is `<pr>:<PR_HEAD_SHA>` for every PR in the frozen
   list, joined by commas, taken from the `discover` output captured in Step 1
   (issue #1558). It binds each remaining PR to the head its reviewer-loop,
   CI, risk-classification and delegated-gate verdicts were produced at. A
   sibling merge that forces a conflict resolution gives a PR a new head, and
   every one of those verdicts is then about a commit that no longer exists;
   a `CLEAN` merge state at the new head is not admission. `--annotate` writes
   the resulting hold onto the PR itself (a `<!-- batch-merge-hold:v1 -->`
   comment, updated in place), so the information is never computed and then
   dropped.

   Treat the recheck output as an admission gate before attempting another
   merge or reporting readiness:
   - The helper must exit `0`.
   - The output must include one fresh `remaining_pr` record for every
     remaining unmerged PR in the frozen approved list.
   - Only PRs with `classification=clean` and `outcome=continue` may remain in
     the merge candidate set.
   - Any missing record means the PR was not rechecked. Record/report
     `merge_blocked` for that PR with reason `missing_recheck_record`, stop
     before the next merge attempt, and report the coverage gap.

   Parse each JSONL record before attempting another merge:
   - `classification=clean` and `outcome=continue` means the PR may remain in
     the candidate set, subject to the existing order and guardrails.
   - The helper supervises pending or unknown state internally and emits only
     terminal records; retryable state is not an externally consumable
     admission result.
   - `classification=merge_blocked` means record the PR outcome as
     `merge_blocked`, including `invalidating_sibling_pr`, `merge_state`,
     `checks_state`, `reason`, `head_sha`, `reviewed_head_sha`,
     `verdicts_voided`, `required_action`, and `annotation`, then skip that
     PR without reordering. `reason=head_sha_changed` means the head moved
     after its verdicts were produced: `verdicts_voided` lists
     `reviewer_loop`, `ci`, `risk_classification` and `delegated_gate`, and
     `required_action=reverify_at_current_head`. `reason=merge_state_non_clean`
     with `required_action=resolve_conflict_then_reverify` means the head has
     not moved yet but will once the conflict is resolved, so the same
     re-verification follows. `annotation` reports whether the hold comment
     was `created`, `updated`, or `failed:<why>` — a failed annotation does
     not change the classification, but report it.
   - `classification=out_of_scope_observation` is read-only information. Do
     not label, merge, retry for mutation, or add that PR to the frozen list.
   - `classification=helper_failed` or a non-zero helper exit is batch-fatal
     for the current sequence; stop before any further merge attempt and report
     the helper reason.

   The helper preserves the frozen `--prs` order and emits terminal records for
   every sibling PR it rechecks, including PRs that are already merged. Continue
   only with remaining in-scope PRs that independently recheck clean after the
   latest sibling merge.

5a. **Route every hold to its runner — the record is not the notification.**

   For each `merge_blocked` record whose `reason` is not `already_merged`,
   tell the Work Item Runner that owns the PR (issue #1558 AC-1). When the
   runner is alive, send it the record verbatim plus this instruction; when it
   has exited, the annotated PR comment is the handoff and the next dispatch
   for that item carries the same text:

   > Sibling PR #<invalidating_sibling_pr> merged into `<base>`. Your PR
   > #<pr> is now `<merge_state>` at head `<head_sha>` (reviewed head:
   > `<reviewed_head_sha>`). Verdicts void at this head: `<verdicts_voided>`.
   > Required before any merge decision: `<required_action>`. Treat this as
   > non-terminal: resolve the conflict if any, then re-run Step 7 (reviewer
   > loop), Step 8 (CI), and — where delegated merge is in scope — Gate 5
   > (risk classifier and delegated gate) at the current head. A merge
   > attempted with the old `--expected-head-sha` is refused by
   > `batch-merge.sh merge` and by the delegated gate (`stale_verdict_head`).

   A runner that declared its item terminal before this notice must be
   redispatched (Protocol 90 Step 5 item 4): an unmergeable PR is not
   `ready-for-human-review` in any sense that matters to the batch.

6. Report the per-PR outcome immediately (see outcome codes in Step 5).

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

> Auto-resolved _file_: non-overlapping changes from `develop` and PR #N combined.

#### Non-trivial conflicts

Any conflict that is not in the above categories, or a documentation file with overlapping changes.

1. Display:

   > **Non-trivial conflict detected in PR #N**
   >
   > Conflicting files:
   >
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
   >
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
 #106  │ feat: invalidated sibling    │ merge_blocked
 #107  │ feat: outside frozen scope    │ out_of_scope
──────────────────────────────────────────────────────────────────────────────
Merged: 3  |  Skipped: 2  |  Blocked: 1  |  Observed: 1  |  Failed: 0  |  Not attempted: 0
```

**Outcome codes**:

| Code                | Meaning                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `merged_clean`      | Merged without any conflicts                                                             |
| `merged_auto`       | Merged with auto-resolved trivial conflicts (CHANGELOG or non-overlapping doc files)     |
| `merged_human`      | Merged after human resolved non-trivial conflict(s)                                      |
| `skipped_not_ready` | Skipped because PR lacked `ready-for-human-review` and human chose to exclude it         |
| `skipped_conflict`  | Skipped because human aborted conflict resolution; `develop` returned to pre-merge state |
| `merge_blocked`     | Held because a post-sibling-merge recheck found non-clean or exhausted retry state       |
| `out_of_scope`      | Observed during recheck but outside the frozen approved PR list; no mutation performed   |
| `failed`            | Merge failed for an unexpected reason                                                    |
| `not_attempted`     | PR was not processed when human aborted the entire batch                                 |

Include details of any auto-resolved conflicts in the summary (which files, what entries were combined). For `merge_blocked`, include the invalidating sibling PR, refreshed merge state, refreshed checks state, and helper reason.

---

## Orchestrator-Invoked Mode (Use Case 2)

When called from the Portfolio Orchestrator (Protocol 90), the same flow applies:

- The orchestrator passes the PR list discovered from the batch.
- The merge plan is printed for visibility at Step 3, then execution proceeds immediately.
- The orchestrator must NOT skip or auto-approve the readiness gate (Step 2) for any unready PR. It must pass the Step 2 `APPROVED_UNREADY_PRS` value to every `recheck-remaining --approved-unready-prs` call.
- Non-trivial conflicts still require human resolution at Step 4.3.

The orchestrator should include the batch-merge summary in its overall `Step 6: Notify Humans` output.

---

## Safety Rules

- **The base branch must never be left in a conflicted state.** Every code path that encounters a conflict has either a resolution path or a `git merge --abort` fallback.
- **Do not use `gh pr close`.** The merge must be recognized by GitHub as a real merge, not a closed-unmerged PR.
- **Do not force-push** or rebase PR branches.
- If conflict recovery or remaining-PR supervision would require rewriting a
  workflow PR branch, stop before mutation and route the exact operation through
  `scripts/development-workflow/workflow-branch-push-guard.sh`; batch merge
  approval does not authorize a force-push.
- **Already-merged PRs stay merged** even if the human aborts the batch mid-run.
- If `post-merge-cleanup` fails, report the failure and continue — do not halt remaining merges.
