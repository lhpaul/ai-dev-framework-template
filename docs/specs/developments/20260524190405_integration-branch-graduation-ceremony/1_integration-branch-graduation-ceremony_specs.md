# Integration Branch Graduation Ceremony — Spec

---

## Overview

When all planned sub-items for an epic have been merged into their shared integration branch (`develop-<slug>`), the team performs a "graduation ceremony" to land the completed epic on the main integration branch (`develop`). This spec defines the rules, actors, steps, and acceptance criteria for that process — covering when graduation becomes eligible, how the merge PR is opened, how CHANGELOG content is handled, what happens to the epic issue and optional sub-items, and what cleanup is required after the merge.

The concrete reference for this spec is the first graduation performed on `develop-claude-review-platform` via PR #737.

---

## Use Cases

### Use Case 1: Orchestrator Determines Graduation Is Eligible

**Actor**: Portfolio Orchestrator (automated, operating on behalf of the engineering team)
**Preconditions**:
- An epic issue exists with the label `integration-branch:<slug>`.
- A remote branch `develop-<slug>` exists.
- All sub-items labeled `integration-branch:<slug>` that are marked as "planned" (i.e., not explicitly deferred or cancelled) have merged implementation PRs targeting `develop-<slug>`.

**Steps**:

1. During portfolio scan, the orchestrator identifies integration branches via `git branch -r | grep "^  origin/develop-"`.
2. For each `develop-<slug>` found, the orchestrator queries all issues labeled `integration-branch:<slug>`.
3. For each sub-item, it checks whether the implementation PR is merged to `develop-<slug>`.
4. If all planned sub-items are merged, the orchestrator marks the integration branch as graduation-eligible.
5. The orchestrator surfaces the eligible graduation to the human with a summary of what is included.

**Postconditions**: The human is informed that graduation is available and must explicitly approve before any graduation action is taken.

**Information shown**:

- Which integration branch is eligible.
- A list of all included sub-items with their issue numbers, titles, and merged PR numbers.
- A note identifying any sub-items that were explicitly deferred or marked optional, so the human can confirm whether to include them before graduating.

**Actions available**:

- Human approves graduation: continue to Use Case 2.
- Human defers graduation: orchestrator records the hold and stops.
- Human requests additional sub-items be merged first: orchestrator waits.

**Considerations**:

- Optional sub-items that were not yet started or are still open must be explicitly evaluated before graduation. The orchestrator does not silently skip them — it surfaces them for human confirmation.
- The orchestrator must not auto-graduate without human approval.

---

### Use Case 2: Opening the Graduation PR

**Actor**: Graduation Agent (invoked after human approval)
**Preconditions**:
- Human has approved the graduation.
- All planned sub-items are merged into `develop-<slug>`.
- `develop-<slug>` is up to date with `origin/develop-<slug>`.

**Steps**:

1. The agent fetches the latest remote state.
2. The agent verifies that `develop-<slug>` is not behind `develop` in a way that would cause conflicts — if it is, the agent surfaces the divergence to the human before proceeding.
3. The agent absorbs any CHANGELOG `[Unreleased]` content that accumulated on `develop-<slug>` into the graduation PR (see Business Rules for CHANGELOG handling).
4. The agent opens a PR from `develop-<slug>` to `develop` using a merge-commit strategy.
5. The PR title is: `Graduate \`<slug>\` integration branch to develop`.
6. The PR body includes: a summary of what the epic delivers, a bulleted list of all sub-items with their issue and PR numbers, and a statement that the merge strategy must be **merge commit** (not squash or rebase).
7. The agent runs the standard automated reviewer loop on the graduation PR.
8. Once the reviewer loop is clean, the agent applies `ready-for-human-review`.

**Postconditions**: A non-draft PR from `develop-<slug>` to `develop` is open and labeled `ready-for-human-review`.

**Information shown**:

- PR URL.
- List of included sub-items and their PRs.
- Result of the automated reviewer loop.

**Actions available**:

- Human reviews and merges the graduation PR using a merge commit.

**Considerations**:

- The merge strategy must always be a **merge commit**. Squash or rebase would collapse the history of all sub-item work into a single synthetic commit, losing the individual contribution history. The graduation PR body must state this constraint explicitly.
- Graduation PRs do not require a `ready-for-regression` label, because there is no new implementation in the graduation PR itself — all implementation was already tested via each sub-item's implementation PR.

---

### Use Case 3: Post-Graduation Cleanup

**Actor**: Graduation Agent or human operator
**Preconditions**:
- The graduation PR has been merged to `develop` using a merge commit.

**Steps**:

1. Sync `develop` locally: `git checkout develop && git pull origin develop`.
2. Delete the integration branch on the remote: `git push origin --delete develop-<slug>`.
3. Delete the local integration branch: `git branch -d develop-<slug>`.
4. Close the epic issue on the tracker if all sub-items (including any optional ones) are complete, or leave it open with a note if optional sub-items remain.
5. Confirm cleanup is complete to the human.

**Postconditions**:
- `develop-<slug>` no longer exists on remote or locally.
- The epic issue status reflects whether it is fully done or still open for optional sub-items.
- All sub-items labeled `integration-branch:<slug>` that are merged are marked `Done` in the tracker.

**Information shown**:

- Confirmation that the branch was deleted.
- Current status of the epic issue.
- Any remaining open sub-items and their current status.

**Actions available**:

- Human can close the epic manually if all remaining optional sub-items are explicitly deferred to future work.

**Considerations**:

- Worktrees that were created for sub-item development and whose branches are already merged should be removed as part of cleanup. The orchestrator checks for stale worktrees in its Step 3.3 pre-dispatch check; after a graduation, the operator should also run `git worktree list` and remove any worktrees associated with the graduated `develop-<slug>` or its sub-items.

---

### Use Case 4: Handling Optional Sub-Items After Graduation

**Actor**: Human operator and Portfolio Orchestrator
**Preconditions**:
- The integration branch `develop-<slug>` has been graduated and deleted.
- One or more sub-items labeled `integration-branch:<slug>` remain open in the tracker (these were explicitly deferred as optional or lower-priority at graduation time).

**Steps**:

1. The human decides whether to pursue each remaining optional sub-item.
2. If an optional sub-item will be pursued, the human removes the `integration-branch:<slug>` label from it and treats it as a standalone item targeting `develop` directly, or creates a new integration branch for a follow-up epic.
3. The epic issue may be closed even while optional sub-items remain open — the epic is considered complete when the core planned deliverable landed on `develop`.
4. Optional sub-items that will never be pursued should be explicitly closed or cancelled in the tracker with a note.

**Postconditions**:
- Each remaining optional sub-item has a clear disposition: standalone work item, cancelled, or part of a new epic.
- The epic issue is closed if the core deliverable is done.

**Information shown**:

- List of any open sub-items at graduation time.
- Their current tracker status.

**Actions available**:

- Close the epic.
- Reassign optional sub-items to standalone workflow.
- Cancel optional sub-items.

**Considerations**:

- The decision about optional sub-items at graduation time is a human judgment call. The orchestrator surfaces the list but does not make the disposition decision autonomously.
- Issue #709 is the concrete example: it remained open after the `develop-claude-review-platform` integration branch graduated, because it was not part of the core deliverable scoped to that epic.

---

## Business Rules

- **BR-1: Human approval required before graduation**: The graduation merge PR must not be opened autonomously. The human must explicitly approve after reviewing the list of included sub-items.
- **BR-2: Merge commit is mandatory**: The graduation PR must be merged with a merge commit. Squash or rebase is not permitted, as it collapses the sub-item contribution history.
- **BR-3: All planned sub-items must be merged before graduation**: Graduation is blocked if any planned (non-optional, non-cancelled) sub-item has no merged implementation PR on `develop-<slug>`.
- **BR-4: Optional sub-items do not block graduation**: Sub-items explicitly deferred or marked optional may remain open when graduation happens. They must be surfaced to the human for disposition, not silently skipped.
- **BR-5: CHANGELOG handling — absorb before graduation**: Before opening the graduation PR, all `[Unreleased]` CHANGELOG entries accumulated on `develop-<slug>` must be present in the graduation PR diff. The sub-item PRs each added CHANGELOG entries to `develop-<slug>` — the graduation PR must carry those entries intact so they land on `develop` together with the code. Do not pre-absorb them separately from the graduation PR (as was attempted and reverted during PR #737 — the absorb commit must be part of the graduation branch itself, not a separate prior merge).
- **BR-6: `ready-for-regression` label not required for graduation PRs**: Graduation PRs from `develop-<slug>` to `develop` do not carry new implementation — all code was already in sub-item PRs. Therefore, the `ready-for-regression` label is not required for graduation PRs.
- **BR-7: Post-graduation branch deletion is mandatory**: After the graduation PR is merged, the `develop-<slug>` remote branch must be deleted. Stale integration branches cause confusion in the portfolio scan.
- **BR-8: Epic issue lifecycle**: The epic issue should be closed when the core planned deliverable has landed on `develop` (i.e., after graduation). Remaining optional sub-items do not prevent closing the epic — each optional sub-item should be re-evaluated and either reassigned or cancelled independently.
- **BR-9: Sub-item tracker status at graduation**: All sub-items with merged PRs targeting `develop-<slug>` must be marked `Done` in the tracker by graduation time (they were marked Done when each sub-item PR merged). No additional tracker update is required for sub-items at graduation — only the epic issue status changes.

---

## Acceptance Criteria

- [ ] AC-1: Given a `develop-<slug>` branch where all planned sub-items have merged implementation PRs, the Portfolio Orchestrator surfaces the branch as graduation-eligible during its portfolio scan.
- [ ] AC-2: The orchestrator does not auto-graduate; it requires explicit human approval before opening the graduation PR.
- [ ] AC-3: The graduation PR is opened from `develop-<slug>` to `develop` with the title format `Graduate \`<slug>\` integration branch to develop`.
- [ ] AC-4: The graduation PR body lists every included sub-item with its issue number, title, and implementation PR number.
- [ ] AC-5: The graduation PR body states that the merge strategy must be a merge commit (not squash or rebase).
- [ ] AC-6: All CHANGELOG `[Unreleased]` entries accumulated on `develop-<slug>` are present in the graduation PR diff — they are not separately pre-absorbed before the PR is opened.
- [ ] AC-7: The `ready-for-regression` label is not required on graduation PRs; the Step 5.1 verification check does not flag its absence as a protocol deviation for `develop-<slug>` PRs.
- [ ] AC-8: After the graduation PR is merged, the `develop-<slug>` remote branch is deleted.
- [ ] AC-9: After graduation, the epic issue is closed in the tracker (unless the human explicitly defers closure for ongoing optional sub-items).
- [ ] AC-10: Any open optional sub-items that were not included in the graduation are surfaced to the human for disposition (reassign as standalone, cancel, or defer to a new epic). The orchestrator does not silently drop them.
- [ ] AC-11: The Protocol 05b (`graduate-development-protocol.md`) is updated (or a reference to it is added in Protocol 90) so that the graduation ceremony is discoverable from the main orchestration protocol.
- [ ] AC-12: The Portfolio Orchestrator Step 1 portfolio scan explicitly enumerates open `develop-<slug>` branches and, for each, determines whether graduation is eligible, so the graduation step is surfaced in normal batch runs.

---

## Out of Scope (MVP)

- Automated graduation without human approval: the graduation step always requires explicit human confirmation; fully autonomous graduation is not part of this spec.
- Keeping `develop-<slug>` continuously rebased onto `develop` during sub-item development: this is the human's responsibility; the spec does not define an automated rebase policy.
- Partially-completed epics where only some planned sub-items are done and the human wants to "partial-graduate": not in scope. Graduation requires all planned sub-items to be merged.
- Multi-level integration branch nesting (e.g., `develop-epic-sub-epic`): out of scope.
- Retroactive graduation records or documentation for `develop-claude-review-platform` beyond what is captured in the git log and PR #737: out of scope.
