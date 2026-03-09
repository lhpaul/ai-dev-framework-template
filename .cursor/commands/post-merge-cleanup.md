---
description: >
  After a development PR is merged and the remote branch deleted, sync with origin,
  switch to develop, pull, and delete the local branch to keep the repo clean.
  Usage: /post-merge-cleanup [branch-name]
---

Run the post-merge cleanup script from the repository root.

- **From repo root**, run:
  ```bash
  ./scripts/development-workflow/post-merge-cleanup.sh [branch-name]
  ```
- **No argument**: use the current branch (user should run while still on the merged branch).
- **With `branch-name`**: delete that local branch (e.g. `feature/my-feature`).

The script will: fetch origin, checkout `develop`, pull, then delete the local branch with `git branch -d`. If the user is not in the repo root, `cd` to the repo root first (e.g. use the workspace root or ask which directory is the repo).

Do not skip steps or change the order. If the script fails, show the error and stop.
