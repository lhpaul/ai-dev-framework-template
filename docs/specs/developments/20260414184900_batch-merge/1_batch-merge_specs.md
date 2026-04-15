# Batch Merge — Spec

**Depends on**: None

---

## Guiding principle (important)

This stage is intentionally **product-focused**:

- Write **user-facing behavior**, permissions, UX rules, and acceptance criteria.
- Avoid prescribing **implementation details** (database tables/columns, specific endpoints, file paths, class names, or migration design). Those belong in the **Implementation Plan** stage.
- If a technical constraint matters to the product (e.g., "an agent may belong to multiple broker companies"), express it as a **product requirement** without naming tables.

## Overview

When the orchestrator produces a batch of parallel PRs targeting `develop`, merging them sequentially causes cascading conflicts — primarily in `CHANGELOG.md`, shared protocol files, and configuration — because each successive PR diverges from `develop` after the first one is merged. The `batch-merge` command gives humans (and the orchestrator) a single entry point to merge all ready PRs in a batch without manually resolving the same conflict types over and over. It orders the merges, auto-resolves known trivial conflicts (CHANGELOG entries, documentation-only overlaps), pauses for human input on non-trivial conflicts, and runs `post-merge-cleanup` for each successfully merged PR.

---

## Use Cases

### Use Case 1: Human-invoked batch merge

**Actor**: Developer / team member (human, invoking `/batch-merge` from Claude Code, a Cursor command, or a Codex skill)

**Trigger**: The human decides that one or more PRs targeting `develop` are ready to merge and starts the batch-merge command.

**Preconditions**:
- At least one PR in the repository is labeled `ready-for-human-review`
- The human is on or has access to the repository's `develop` branch

**Steps**:
1. The human invokes `/batch-merge` (or the equivalent Cursor command or Codex skill), optionally specifying a batch identifier, a list of PR numbers, or allowing the command to auto-discover all `ready-for-human-review` PRs.
2. The command discovers all candidate PRs and displays a summary table (PR number, title, branch, current labels) so the human can confirm the set before proceeding.
3. The command checks each PR for the `ready-for-human-review` label.
   - Any PR missing that label is flagged with a warning; the command asks the human to confirm whether to include it anyway or skip it.
   - If the human confirms skip, the PR is excluded from this run.
   - If the human confirms include, the PR proceeds with an explicit "not fully reviewed" notation.
4. The command determines the merge order (see Business Rules — Merge Ordering).
5. For each PR in order:
   a. The command attempts to merge the PR into `develop`.
   b. If the merge is clean, it succeeds immediately.
   c. If the merge has conflicts that are all classified as trivial (CHANGELOG entries or documentation/protocol files), the command auto-resolves them and completes the merge.
   d. If the merge has any non-trivial conflict, the command pauses and asks the human to resolve it, then resumes after the human confirms resolution.
   e. After each successful merge, the command runs `post-merge-cleanup` for that branch.
6. When all PRs have been processed, the command reports the outcome for each PR (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, or `failed`).

**Postconditions**:
- All PRs the human approved for merging are merged into `develop` (or explicitly noted as skipped or pending human resolution).
- `post-merge-cleanup` has been run for every successfully merged PR.
- The issue tracker status is updated for each merged branch (per the branch-type-to-status table).

**Information shown**:
- Pre-merge summary table: PR number, title, branch, labels, readiness status
- Per-PR merge result: clean merge / auto-resolved trivial conflicts / paused (non-trivial conflict) / skipped / failed
- List of auto-resolved trivial conflicts with a brief description of what was combined
- Post-run summary: how many PRs merged, how many skipped, how many need human action

**Actions available**:
- Confirm or adjust the candidate PR list before merging
- Approve or skip a PR flagged as missing `ready-for-human-review`
- Resolve non-trivial conflicts manually and signal the command to resume
- Abort the entire batch merge at any time

**Considerations**:
- If `/batch-merge` is invoked in auto-discovery mode (no explicit PR numbers provided) and no `ready-for-human-review` PRs exist in the repository, the command exits immediately with an informational message and no side effects. When the user provides an explicit PR list, the command always proceeds to the per-PR readiness check (Step 3) regardless of label status.
- If only a single PR is in the candidate set, the command proceeds as normal (not a no-op).
- A PR that fails to merge (e.g., unresolvable conflict after human gives up) is noted in the final summary and skipped; remaining PRs continue.

---

### Use Case 2: Orchestrator-invoked batch merge

**Actor**: Portfolio Orchestrator (`/run-work` or `item-orchestrator`) preparing a batch merge after all PRs in a batch reach `ready-for-human-review`

**Trigger**: The orchestrator detects that every PR in a batch has reached `ready-for-human-review` and initiates the batch-merge validation flow.

**Preconditions**:
- All PRs in the current batch are expected to be labeled `ready-for-human-review`

**Steps**:
1. The orchestrator detects all batch PRs have `ready-for-human-review` and prepares the batch-merge flow (discovers candidates, determines merge order, validates readiness).
2. If any PR in the batch is missing `ready-for-human-review`, the orchestrator warns the human and requires an explicit decision for each unready PR (exclude or include). The orchestrator must not proceed silently with any unready PR.
3. The orchestrator presents the validated merge plan to the human and requests explicit approval to execute the merges. The human must confirm before any merge occurs.
4. Once the human approves, the orchestrator runs the same merge procedure as the human-invoked case (Use Case 1).
5. For trivial conflicts (CHANGELOG entries, documentation files), the orchestrator auto-resolves without additional human confirmation.
6. For non-trivial conflicts, the orchestrator pauses and escalates to the human.

**Postconditions**:
- Same as Use Case 1.

**Information shown**:
- Same as Use Case 1 (reported in the orchestrator's summary).

**Actions available**:
- Human can intervene at any point to resolve non-trivial conflicts.

**Considerations**:
- The orchestrator-invoked path is a stretch goal; the human-invoked path (Use Case 1) is the primary deliverable.
- The orchestrator prepares and validates the batch but does not merge autonomously — the human must explicitly approve the merge execution. This aligns with the repository governance rule that humans perform merges.
- The orchestrator must not silently skip the readiness check — if any PR is not `ready-for-human-review`, the command must warn and require human confirmation.

---

## Business Rules

### Merge Requirements

The merge approach must satisfy these product requirements:

- Individual PR commit history must remain visible in `develop`'s log (useful for audit, blame, and bisect)
- PR conversation threads must not be disrupted by the merge process
- The merge approach must not require force-pushing or rewriting PR branches
- The merge approach must be the natural extension of the existing per-PR merge workflow
- Each PR's contribution must be individually identifiable in `develop`'s history

The specific merge strategy (merge commit, squash, rebase) and implementation approach will be decided in the Implementation Plan. See the **Technical Notes for Implementation Plan** appendix for a preliminary evaluation of three candidate approaches.

### Merge Ordering

The command orders PRs for merging according to this priority (highest first):

1. PRs without CHANGELOG changes — merge these first since they cannot cause CHANGELOG conflicts. Among these, lowest PR number (oldest) merges first.
2. PRs with CHANGELOG changes — merge after all non-CHANGELOG PRs. Among these, lowest PR number (oldest) merges first.
3. Ties (same PR number is impossible; this covers any future grouping) are broken by PR creation timestamp, earlier first.

This ordering minimizes the total number of conflict resolutions needed.

### Trivial Conflict Auto-Resolution

The following conflict types are classified as **trivial** and auto-resolved without human confirmation:

1. **CHANGELOG.md `[Unreleased]` section**: When two PRs each added entries under `[Unreleased]`, the command merges the entry lists by including all unique entries from both sides, ordered chronologically by PR merge sequence (entries from the PR merged first appear first, followed by entries from the PR merged second). No entries are dropped. The human is notified of what was combined in the post-merge summary.

2. **Protocol / documentation files** (e.g., files under `docs/`, `.cursor/`, `.codex/`): When two PRs each modified documentation-only files with non-overlapping line ranges, the command applies both changes. If the changes overlap, the conflict is treated as **non-trivial** and escalated to the human.

Any conflict outside these two categories is treated as **non-trivial**.

### Non-Trivial Conflict Handling

When a non-trivial conflict is encountered during a merge:

1. The command pauses the merge for that PR.
2. The command clearly states which files are in conflict and what the conflicting sections are.
3. The human is asked to resolve the conflict in their editor and then signal the command to resume (e.g., by running `git merge --continue` manually, then confirming in the command interface).
4. Once the human signals resolution, the command completes the merge and proceeds to `post-merge-cleanup` and remaining PRs.
5. If the human cannot resolve the conflict and chooses to abort, the PR is skipped (the merge is abandoned with `git merge --abort`), and the command continues with remaining PRs. The skipped PR is noted in the final summary.

### Readiness Gate

- A PR without the `ready-for-human-review` label triggers a warning before any merges begin.
- The human must explicitly approve including such a PR or confirm it should be skipped.
- The command must not silently skip or silently merge an unready PR.
- In orchestrator-invoked mode, the command must NOT proceed with any unready PR without human confirmation.

### Post-Merge Cleanup Integration

- After each successful merge, `post-merge-cleanup` is run for the merged branch (see existing `post-merge-cleanup` protocol for exact steps and side effects).
- If cleanup fails, the failure is reported but does not halt the remaining merges.

### Abortability

- The human can abort the entire batch merge at any time.
- Any already-merged PRs remain merged; the abort only stops future merges.
- On abort, the command reports which PRs were merged and which remain unprocessed.

### Scope

- The command operates on PRs targeting `develop` only.
- PRs targeting `main` (e.g., release PRs) are out of scope for this command.

---

## UX Rules

- The command must display a confirmation prompt listing all candidate PRs before performing any merge. The human must acknowledge before merges begin.
- Each per-PR merge result must be reported immediately (not just in the final summary) so the human can track progress.
- Auto-resolved trivial conflicts must be explicitly described (which files, what was combined) — silent auto-resolution is not acceptable.
- The final summary must clearly distinguish: merged clean (`merged_clean`), merged with auto-resolved conflicts (`merged_auto`), merged after human-resolved conflict (`merged_human`), skipped because not ready (`skipped_not_ready`), skipped because conflict was aborted (`skipped_conflict`), and failed (`failed`).
- When pausing for a non-trivial conflict, the command must display the conflicting file path(s) and a short excerpt of the conflict markers.
- The command must not leave `develop` in a conflicted state under any circumstances. If a merge cannot be cleanly completed (human aborts resolution), the merge is aborted (`git merge --abort`) before proceeding.

---

## Statuses / Enum Values

This feature does not introduce new tracker statuses. Per-PR outcomes within the command's own output are:

| Code value | Display label | Description |
|---|---|---|
| `merged_clean` | Merged (clean) | PR merged without any conflicts |
| `merged_auto` | Merged (auto-resolved) | PR merged with auto-resolved trivial conflicts |
| `merged_human` | Merged (human-resolved) | PR merged after human resolved non-trivial conflict(s) |
| `skipped_not_ready` | Skipped (not ready) | PR skipped because it lacked `ready-for-human-review` and human chose to exclude it |
| `skipped_conflict` | Skipped (conflict aborted) | PR skipped because human could not resolve conflict and chose to abort the merge |
| `failed` | Failed | PR merge failed for an unexpected reason |

---

## Operational Visibility

- **Logs / Output**: The command produces inline progress output for each PR: merge attempt started, merge result (clean / auto-resolved / conflict detected), conflict details on pause, resume confirmation, `post-merge-cleanup` result.
- **Final Summary**: A structured end-of-run summary is always printed, regardless of whether all merges succeeded.
- **Audit trail**: Each merge on `develop` should reference the PR number and branch name so the audit trail is visible in `git log`.
- **Issue tracker updates**: `post-merge-cleanup` updates the issue tracker status for each merged PR (same as the existing `post-merge-cleanup` command behavior).

---

## Acceptance Criteria

- [ ] Running `/batch-merge` (or equivalent) with no arguments discovers all PRs labeled `ready-for-human-review` and displays a candidate list before any merge is attempted.
- [ ] The human is shown a confirmation prompt with the candidate PR list; no merge occurs until the human confirms.
- [ ] A PR missing the `ready-for-human-review` label causes a warning and requires explicit human confirmation to include or exclude; it is never silently processed.
- [ ] PRs are merged in the order defined by the Merge Ordering rule (non-CHANGELOG PRs first by lowest PR number; then CHANGELOG PRs by lowest PR number).
- [ ] The merge approach satisfies the Merge Requirements: individual PR history visible, PR threads intact, no force-push, each PR individually identifiable in `develop`'s history.
- [ ] A CHANGELOG conflict between two PRs is auto-resolved by combining all `[Unreleased]` entries from both sides; no entries are dropped; the auto-resolution is described in the output.
- [ ] A documentation/protocol file conflict with non-overlapping changes is auto-resolved; the output describes which files were combined.
- [ ] A non-trivial conflict (code files, or overlapping doc changes) causes the command to pause, display the conflicting file(s) and conflict markers, and wait for the human to resolve.
- [ ] After the human signals conflict resolution, the command resumes the merge and continues with remaining PRs.
- [ ] If the human aborts a conflict resolution, the merge is abandoned (`git merge --abort`) and the PR is noted as skipped; remaining PRs continue.
- [ ] After each successful merge, `post-merge-cleanup` runs for the merged branch and its result is reported.
- [ ] The final summary lists every candidate PR with its outcome (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, or `failed`).
- [ ] In auto-discovery mode, if no `ready-for-human-review` PRs exist, the command exits cleanly with an informational message and no side effects. When explicit PR numbers are provided, the command proceeds to per-PR readiness checks regardless of label status.
- [ ] The command works as a Claude Code slash command (`/batch-merge`), a Cursor command, and a Codex skill.
- [ ] In orchestrator-invoked mode, any PR missing `ready-for-human-review` causes a warning and requires an explicit human decision (exclude or include). The command must not proceed silently with any unready PR.

---

## Out of Scope (MVP)

- Merging release PRs (PRs targeting `main`). This command is scoped to PRs targeting `develop`.
- Alternative merge strategies beyond what the implementation plan selects.
- Merging PRs across different repositories or monorepo packages.
- Automatically reopening or rebasing PRs that failed to merge; the command only reports failures.
- Support for pull request queues or GitHub's merge queue feature.
- Automatic scheduling or time-based trigger of batch merge (the command is always explicitly invoked, either by a human or the orchestrator).
- Configurable merge ordering beyond the rule defined above.
- UI or web dashboard for batch merge status.

---

## Open Questions

<!-- All alignment questions were answered by the human. No open questions remain. -->

---

## Appendix: Technical Notes for Implementation Plan

> This section is informational context for the implementation plan, not product requirements.

Three approaches were evaluated for solving the cascading-conflict problem:

**Option A — Rebase each PR on top of the latest `develop` before merging**
- Rewrites the PR branch's commit history to sit on top of `develop` after previous merges.
- Pro: each subsequent merge is always a fast-forward; no conflict possible.
- Con: rewrites commits, changes SHAs, breaks PR conversation threads, and requires force-push. Disruptive in collaborative workflows.

**Option B — Sequential merge commit with automated conflict resolution**
- Merges PRs in order using merge commits. After the first merge updates `develop`, each subsequent PR's branch diverges. The command detects and auto-resolves trivial conflicts; pauses on non-trivial ones.
- Pro: preserves full commit history; PR conversation threads intact. Merge commits are explicit and auditable.
- Con: non-trivial conflicts still require human intervention (unavoidable in any approach).

**Option C — Temporary integration branch**
- Create a temporary branch from `develop`, merge all PRs into it sequentially, then merge the integration branch into `develop` as a single commit.
- Pro: `develop`'s history gets a clean single-merge-commit.
- Con: hides individual PR contributions; does not pair naturally with per-PR `post-merge-cleanup`; more complex.

**Preliminary recommendation: Option B** — it best satisfies the Merge Requirements (individual PR history visible, PR threads intact, no force-push). The implementation plan should confirm or revise this choice.
