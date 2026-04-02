---
description: >
  After a development PR is merged and the remote branch deleted, sync with origin,
  switch to develop, pull, delete the local branch, and update the related issue in the issue tracker.
  Usage: /post-merge-cleanup [branch-name]
---

Run the post-merge cleanup script from the repository root.

- **From repo root**, run:
  ```bash
  ./scripts/development-workflow/post-merge-cleanup.sh [branch-name]
  ```
- **No argument**: use the current branch (user should run while still on the merged branch).
- **With `branch-name`**: delete that local branch (e.g. `feature/my-feature`).

The script will: fetch origin, checkout `develop`, pull, then delete the local branch with `git branch -D` (force-delete; safe because the branch is already merged on the remote). If the user is not in the repo root, `cd` to the repo root first (e.g. use the workspace root or ask which directory is the repo).

Do not skip steps or change the order. If the script fails, show the error and stop.

**After the script succeeds — update the issue tracker (if configured):**
The merged branch name often contains an issue identifier (e.g. `feature/ENG-123-user-auth` → `ENG-123`, or `feature/42-user-auth` → `#42`). If so, update that issue in the project’s issue tracker to the merged/done state. For **Linear**, use the Linear MCP to set the issue status to **Merged** (see `docs/ai/development-workflow/integrations/linear.md`). For **GitHub Projects**, close the issue with `gh issue close <number>` and update the project item Status field to **Merged** via the `gh` CLI / GraphQL (see `docs/ai/development-workflow/integrations/github-projects.md`). For other trackers, set the equivalent "PR merged" status (e.g. Done, Closed, Merged); see `docs/ai/development-workflow/integrations/issue-tracker.md` and the tracker-specific doc under `docs/ai/development-workflow/integrations/`. If the branch has no issue ID or no tracker is in use, skip this step.
