---
name: batch-merge
description: Merge all ready PRs in a parallel batch into develop sequentially, auto-resolving trivial CHANGELOG and documentation conflicts, pausing for human input on non-trivial ones, and running post-merge-cleanup for each successfully merged PR. Use when a parallel batch of PRs is ready for merge.
---

# Batch Merge

Follow `docs/ai/development-workflow/protocols/94-batch-merge-protocol.md` exactly.

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

5. **Human confirmation**: present the final ordered merge plan and require explicit approval before any merge.

6. **Sequential merge loop**: for each approved PR in order:
   - Run `./scripts/development-workflow/batch-merge.sh merge --pr <number>`
   - On `MERGE_RESULT=clean`: proceed to post-merge steps.
   - On `MERGE_RESULT=conflict`: classify each conflicted file:
     - `CHANGELOG.md`: auto-resolve by combining all `[Unreleased]` entries (HEAD side first, incoming side second, no entries dropped). Report what was combined.
     - Documentation files (`docs/`, `.claude/`, `.cursor/`, `.codex/`): auto-resolve if non-overlapping; escalate if overlapping.
     - All other files (or overlapping doc changes): pause, show conflict markers, wait for human to resolve or abort.
   - On `MERGE_RESULT=failed`: report the error, mark `failed`, continue.
   - After each successful merge: complete the post-merge sequence from Protocol 94 Step 4.2 (`git push origin develop`, verify GitHub shows `MERGED`, delete the remote branch if it still exists, create a temporary local branch if needed, then run `./scripts/development-workflow/post-merge-cleanup.sh <branch>`).

7. **Final summary**: always print a table listing every candidate PR with its outcome code (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, `failed`, `not_attempted`).

Key rules:

- Never leave `develop` in a conflicted state — always run `git merge --abort` if a conflict cannot be resolved.
- Never force-push or rebase PR branches.
- Never use `gh pr close` — the merge must be recognized by GitHub as `MERGED`.
- Already-merged PRs stay merged even if the human aborts mid-batch.
- `post-merge-cleanup` failures are reported but do not stop remaining merges.
