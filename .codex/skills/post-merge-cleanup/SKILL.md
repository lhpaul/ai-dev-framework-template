---
name: post-merge-cleanup
description: After a development PR is merged and the remote branch deleted, sync with origin, switch to develop, pull, delete the local branch, and update the related issue in the issue tracker. Use when you want to clean up the local repo post-merge.
---

# Post-merge cleanup

1. From the repository root, run:
   ```bash
   ./scripts/development-workflow/post-merge-cleanup.sh [branch-name]
   ```
2. **No argument**: the current branch is the one to delete (user runs while still on the merged branch).
3. **With `branch-name`**: delete that local branch (e.g. `feature/my-feature`).

The script fetches origin, checks out `develop`, pulls, and deletes the local branch with `git branch -D` (force-delete; safe because the branch is already merged on the remote). Do not change the order or skip steps.

4. **Update the issue tracker (if configured)**  
   The merged branch name often contains an issue identifier (e.g. `feature/ENG-123-user-auth` → `ENG-123`, `fix/PROJ-456-login` → `PROJ-456`). After the script succeeds:
   - If the branch name contains such an identifier, update the corresponding issue in the project’s issue tracker to the “merged” / “done” state (or equivalent).
   - **Linear**: Use the Linear MCP/skill to get the issue by ID and set its status to **Merged** (per `docs/ai/development-workflow/integrations/linear.md`).
   - **Other trackers**: Follow the same idea — set the issue to the status that means “PR merged to develop” (e.g. Done, Closed, Merged). See `docs/ai/development-workflow/integrations/issue-tracker.md` and the tracker-specific doc under `docs/ai/development-workflow/integrations/`.
   - If no issue identifier is present in the branch name or no tracker is in use, skip this step.
