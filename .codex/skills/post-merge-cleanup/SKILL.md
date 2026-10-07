---
name: post-merge-cleanup
description: After a development PR is merged, sync with origin, switch to the merged PR's base branch, pull, verify or delete the remote implementation branch, delete the local branch, and update the related issue in the issue tracker. Use when you want to clean up the local repo post-merge.
---

# Post-merge cleanup

## Merge-session admission and recovery

After ordinary review/CI/readiness and before any merge-operation audit, hold, bypass, merge or follow-up mutation, follow [Protocol 94 section 3.6](../../../docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md#36-merge-session-admission-and-recovery). Freeze the entire selected ordered set in one authoritative owner-bound session; an unaffordable set admits no prefix. Supply the same `--merge-session` to mutating merge/cleanup helpers, and `--operation merge` to operation-owned audit calls. Direct authorized `gh pr merge` commands run through `workflow-merge-budget.py run-step` with their existing argv unchanged. Read-only risk classification remains separate; delegated merge requires the durable session plus all existing gates.

Deferred reports quota/reset, recorded PR states and pending follow-up without operation-owned remote writes; fresh selected PRs stay unmerged, while recovery deferral retains historical merged/uncertain facts. Waiting records a verified queue/auto-merge submission, stops subsequent selected merges and leaves merge-dependent follow-up pending. Interrupted retains completed/uncertain/pending work locally even if every API fails; stop further selected merges and use explicit verified recovery without duplicate submission or uncertain mutation replay. Completed requires all owned planned follow-up independently verified, including tracker and audit. Budget admission grants no risk, checkpoint, admin or deletion authority. Report the session recovery command together with the existing Ground-Truth Completion Verification before claiming a workflow terminal outcome.

1. From the repository root, run:
   <!-- workflow-shell-contract: bash-zsh -->
   ```bash
   ./scripts/development-workflow/post-merge-cleanup.sh [--merge-session session-path] [--base base-branch] [--pr merged-pr-number] [branch-name]
   ```
2. **No argument**: the current branch is the one to delete (user runs while still on the merged branch).
3. **With `branch-name`**: delete that local branch (e.g. `feature/my-feature`).
4. **With `--base base-branch`**: explicitly choose the cleanup base branch. When omitted for hub-owned cleanup, the script queries the merged PR base and fails closed if that lookup is unavailable.
5. **With `--pr merged-pr-number`**: bind implementation remote branch cleanup to the exact merged PR before deleting any remote branch. Required on implementation branches; the helper fail-fasts with exit 64 when this flag is missing.
6. In `workflow_hub`, preserve the selected product repository context for product-owned implementation cleanup and pass it through to shared cleanup helpers; hub-owned spec, plan, and workflow PR cleanup remains in the hub. Missing mode or `single_repo` keeps current cleanup behavior.
7. **Update the issue tracker (if configured)**
   The merged branch name often contains an issue identifier (e.g. `feature/ENG-123-user-auth` → `ENG-123`, `fix/PROJ-456-login` → `PROJ-456`, `feature/42-user-auth` → `#42`). After the script succeeds, update the corresponding issue using the branch-type-based status table from Step 10 of `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`:

   | Merged branch type                                | Set tracker status to |
   | ------------------------------------------------- | --------------------- |
   | `spec/*`                                          | Spec Ready            |
   | `implementation-plan/*`                           | Plan Ready            |
   | `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` | Merged                |

   If the item’s tracker status is already in a further-advanced state (e.g., already `In Development` when a spec branch merges), do not roll it back — leave it as-is.
   - **Linear**: Use the Linear MCP/skill to get the issue by ID and set its status (per `docs/workflow/development-workflow/integrations/linear.md`).
   - **GitHub Issues/Projects**: The script already closes the GitHub issue for implementation branches (if a merged PR is found). You still need to update the GitHub Projects board status field via `gh` CLI / GraphQL (per `docs/workflow/development-workflow/integrations/github-projects.md`).
   - **Other trackers**: Follow the same idea — set the issue to the appropriate status per the table above. See `docs/workflow/development-workflow/integrations/issue-tracker.md` and the tracker-specific doc under `docs/workflow/development-workflow/integrations/`.
   - If no issue identifier is present in the branch name or no tracker is in use, skip this step.
8. For implementation branches (`feature/*`, `fix/*`, `refactor/*`,
   `hotfix/*`), verify the script reports `REMOTE_DELETE_RESULT=deleted` or
   `REMOTE_DELETE_RESULT=not_found` before claiming cleanup complete. A
   `skipped` or `failed` remote deletion result is non-terminal. Spec and
   implementation-plan branches are expected-persistent remotely.
9. Before reporting cleanup or tracker reconciliation complete for a workflow
   item, run `scripts/development-workflow/item-completion-self-check.sh` with
   `--stage cleanup` and the expected tracker status when claimed. Include its
   `## Ground-Truth Completion Verification` section in the cleanup report; a
   `discrepancy` or `unavailable_required` result means cleanup is not complete.

**After cleanup and tracker update — suggest a retrospective if appropriate:**
If this post-merge cleanup is the final action for a work item that was advanced in the current session (i.e., you drove the item through implementation, review, and merge in this conversation), suggest running a retrospective:

> Would you like to run a retrospective on this session’s work?

Only suggest this when the cleanup is for a standalone item run (not when called as part of a batch merge or orchestrator flow, which handle retrospectives at their own level). See `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`.

The script (step 1) fetches origin, checks out the merged PR's base branch, pulls, verifies or deletes the remote implementation branch after confirming the PR is merged, deletes the local branch with `git branch -D` (force-delete; safe because the branch is already merged on the remote), and for implementation branches (`fix/*`, `feature/*`, `hotfix/*`, `refactor/*`) automatically closes the associated GitHub issue if a merged PR is found. Do not change the order or skip steps.

For an existing merge session, subsequent CLI or MCP tracker work stays in that same journal. Record intent before a provider mutation and independently read back its owning issue/status before discharge; Linear uses the existing normalized MCP bridge. A script success, best-effort zero exit or deferred action is pending evidence, never completion. Standalone cleanup obtains a follow-up-only admission before its first mutation; an invalid supplied session cannot fall back to a new smaller session.
