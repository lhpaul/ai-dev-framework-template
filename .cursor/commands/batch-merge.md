---
description: >
  Merge all ready PRs in a parallel batch into develop sequentially, auto-resolving trivial
  CHANGELOG and documentation conflicts, pausing for human input on non-trivial ones, and
  running post-merge-cleanup for each successfully merged PR.
  Usage: /batch-merge [#PR1 #PR2 ...] or /batch-merge --prs 101,102,103
---

Follow `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` exactly.

**Auto-discovery** (no arguments): discovers all PRs labeled `ready-for-human-review` targeting `develop`.

**Explicit PR list**: pass PR numbers as arguments, e.g. `/batch-merge #101 #102 #103` or `/batch-merge --prs 101,102,103`. The command proceeds to per-PR readiness checks regardless of label status.

Key rules:

- Do not start any merge until the human explicitly confirms the merge plan (Step 3 of the protocol).
- For each PR, run `./scripts/development-workflow/batch-merge.sh merge --pr <number>`.
- Auto-resolve CHANGELOG and non-overlapping documentation conflicts; pause and escalate non-trivial conflicts.
- After each successful merge: push `develop`, verify GitHub shows the PR as `MERGED`, delete the remote branch, run `./scripts/development-workflow/post-merge-cleanup.sh <branch>`.
- Never leave `develop` in a conflicted state.
- Always print the final summary table (Step 5) regardless of outcome.
