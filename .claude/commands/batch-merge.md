---
description: >
  Merge all ready PRs in a parallel batch into the target base branch sequentially, auto-resolving trivial
  CHANGELOG and documentation conflicts, pausing for human input only on non-trivial conflicts,
  and running post-merge-cleanup for each successfully merged PR. Prints the merge plan for
  visibility but proceeds immediately without requiring confirmation.
  Usage: /batch-merge [#PR1 #PR2 ...] or /batch-merge --prs 101,102,103
allowed-tools: Bash(./scripts/development-workflow/batch-merge.sh --merge-session "$MERGE_SESSION":*), Bash(./scripts/development-workflow/post-merge-cleanup.sh:*), Bash(git:*), Bash(gh:*), mcp__claude_ai_Linear__get_issue, mcp__claude_ai_Linear__save_issue, mcp__claude_ai_Linear__list_issue_statuses
# If using a different issue tracker, add its MCP tool names here (e.g. mcp__jira__update_issue).
---

## Merge-session admission and recovery

After ordinary review/CI/readiness and before any merge-operation audit, hold, bypass, merge or follow-up mutation, follow [Protocol 94 section 3.6](../../docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md#36-merge-session-admission-and-recovery). Freeze the entire selected ordered set in one authoritative owner-bound session; an unaffordable set admits no prefix. Supply the same `--merge-session` to mutating merge/cleanup helpers, and `--operation merge` to operation-owned audit calls. Direct authorized `gh pr merge` commands run through `workflow-merge-budget.py run-step` with their existing argv unchanged. Read-only risk classification remains separate; delegated merge requires the durable session plus all existing gates.

Deferred reports quota/reset, recorded PR states and pending follow-up without operation-owned remote writes; fresh selected PRs stay unmerged, while recovery deferral retains historical merged/uncertain facts. Waiting records a verified queue/auto-merge submission, stops subsequent selected merges and leaves merge-dependent follow-up pending. Interrupted retains completed/uncertain/pending work locally even if every API fails; stop further selected merges and use explicit verified recovery without duplicate submission or uncertain mutation replay. Completed requires all owned planned follow-up independently verified, including tracker and audit. Budget admission grants no risk, checkpoint, admin or deletion authority. Report the session recovery command together with the existing Ground-Truth Completion Verification before claiming a workflow terminal outcome.

Follow `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` exactly.

**Auto-discovery** (no arguments): discovers all PRs labeled `ready-for-human-review` targeting the configured base branch.

**Explicit PR list**: pass PR numbers as arguments, e.g. `/batch-merge #101 #102 #103` or `/batch-merge --prs 101,102,103`. The command proceeds to per-PR readiness checks regardless of label status.

Key rules:

- Print the merge plan (Step 3 of the protocol) for visibility, then proceed immediately without waiting for user confirmation.
- For each PR, run `./scripts/development-workflow/batch-merge.sh --merge-session "$MERGE_SESSION" merge --pr <number> --expected-head-sha <reviewed-headRefOid>`.
- Auto-resolve CHANGELOG conflicts and documentation file conflicts where changes are non-overlapping (different line ranges); pause and escalate all other conflicts.
- After each successful merge, follow Protocol 94 Step 4.2 for verification, guarded branch deletion, local branch preparation, cleanup, and post-recheck admission before selecting another PR.
- Never leave the target base branch in a conflicted state.
- Always print the final summary table (Step 5) regardless of outcome.
