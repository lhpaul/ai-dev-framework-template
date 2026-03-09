---
name: post-merge-cleanup
description: After a development PR is merged and the remote branch deleted, sync with origin, switch to develop, pull, and delete the local branch. Use when you want to clean up the local repo post-merge.
---

# Post-merge cleanup

1. From the repository root, run:
   ```bash
   ./scripts/development-workflow/post-merge-cleanup.sh [branch-name]
   ```
2. **No argument**: the current branch is the one to delete (user runs while still on the merged branch).
3. **With `branch-name`**: delete that local branch (e.g. `feature/my-feature`).

The script fetches origin, checks out `develop`, pulls, and deletes the local branch with `git branch -d`. Do not change the order or skip steps.
