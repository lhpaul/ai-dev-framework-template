---
name: batch-merge
description: Merge all ready PRs in a parallel batch into the target base branch sequentially, auto-resolving legacy trivial CHANGELOG and documentation conflicts, pausing for human input only on non-trivial conflicts, and running post-merge-cleanup for each successfully merged PR. Prints the merge plan for visibility but proceeds immediately without requiring confirmation. Use when a parallel batch of PRs is ready for merge.
---

# Batch Merge

## Merge-session admission and recovery

After ordinary review/CI/readiness and before any merge-operation audit, hold, bypass, merge or follow-up mutation, follow [Protocol 94 section 3.6](../../../docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md#36-merge-session-admission-and-recovery). Freeze the entire selected ordered set in one authoritative owner-bound session; an unaffordable set admits no prefix. Supply the same `--merge-session` to mutating merge/cleanup helpers, and `--operation merge` to operation-owned audit calls. Direct authorized `gh pr merge` commands run through `workflow-merge-budget.py run-step` with their existing argv unchanged. Read-only risk classification remains separate; delegated merge requires the durable session plus all existing gates.

Deferred reports quota/reset, recorded PR states and pending follow-up without operation-owned remote writes; fresh selected PRs stay unmerged, while recovery deferral retains historical merged/uncertain facts. Waiting records a verified queue/auto-merge submission, stops subsequent selected merges and leaves merge-dependent follow-up pending. Interrupted retains completed/uncertain/pending work locally even if every API fails; stop further selected merges and use explicit verified recovery without duplicate submission or uncertain mutation replay. Completed requires all owned planned follow-up independently verified, including tracker and audit. Budget admission grants no risk, checkpoint, admin or deletion authority. Report the session recovery command together with the existing Ground-Truth Completion Verification before claiming a workflow terminal outcome.

Follow `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` exactly.

1. **Auto-discovery mode** (no explicit PR numbers): run:

   ```bash
   ./scripts/development-workflow/batch-merge.sh discover
   ```

   If `DISCOVERY_RESULT=none`, exit immediately with an informational message — no merges occur.

2. **Explicit PR list** (PR numbers provided by the human): run:

   ```bash
   ./scripts/development-workflow/batch-merge.sh discover --prs <num1,num2,...>
   ```

3. Display the candidate summary table (PR number, title, branch, labels, readiness status).

4. **Readiness gate**: for each PR missing `ready-for-human-review`, warn the human and require an explicit include-or-skip decision. Never silently include or skip.

5. **Merge plan display**: present the final ordered merge plan, then proceed immediately without waiting for user confirmation.

6. **Sequential merge loop**: for each PR in order:
   - Run `./scripts/development-workflow/batch-merge.sh --merge-session "$MERGE_SESSION" merge --pr <number> --expected-head-sha <reviewed-headRefOid>` using the head SHA captured by the latest readiness/review gate.
   - On `MERGE_RESULT=clean`: proceed to post-merge steps.
   - On `MERGE_RESULT=conflict`: classify each conflicted file:
     - `CHANGELOG.md`: legacy fallback only; auto-resolve by combining all `[Unreleased]` entries (HEAD side first, incoming side second, no entries dropped). Report what was combined.
     - Documentation files (`docs/`, `.claude/`, `.cursor/`, `.codex/`): auto-resolve if non-overlapping; escalate if overlapping.
     - All other files (or overlapping doc changes): pause, show conflict markers, wait for human to resolve or abort.
   - On `MERGE_RESULT=failed`: retain the session Interrupted evidence, report the error and stop further selected merges until explicit verified recovery.
   - After each independently verified MERGED result: complete the authorized post-merge sequence from Protocol 94 Step 4.2 (the merge helper already pushed the target base branch and called `gh pr merge`; verify GitHub shows `MERGED`, perform only authorized remote cleanup, then run `./scripts/development-workflow/post-merge-cleanup.sh --merge-session "$MERGE_SESSION" --base <target-base> --pr <number> <branch>`).
   - Before selecting the next PR, run `./scripts/development-workflow/batch-merge.sh --merge-session "$MERGE_SESSION" recheck-remaining --prs <comma-separated-approved-pr-list> --after-merged-pr <number> --base <target-base> --approved-unready-prs <comma-separated-human-included-unready-prs>` for the frozen in-scope PR list. Apply Protocol 94 Step 4.2 as the source of truth for post-recheck admission semantics.

7. **Final summary**: always print a table listing every candidate PR with its outcome code (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, `merge_blocked`, `out_of_scope`, `failed`, `not_attempted`).

Key rules:

- Never leave the target base branch in a conflicted state — always run `git merge --abort` if a conflict cannot be resolved.
- Do not force-push or rebase PR branches.
- Do not use `gh pr close` — the merge must be recognized by GitHub as `MERGED`.
- Already-merged PRs stay merged even if the human aborts mid-batch.
- `git push origin develop` failures are **batch-fatal**: stop processing further PRs immediately, run `git merge --abort` if a conflict exists, surface a clear error, and require human intervention before resuming.
- `post-merge-cleanup` failures record Interrupted with pending reconciliation and stop remaining selected merges until explicit verified recovery.
