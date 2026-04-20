---
description: >
  After a development PR is merged and the remote branch deleted, sync with origin,
  switch to develop, pull, delete the local branch, and update the related issue in the issue tracker.
  Usage: /post-merge-cleanup [branch-name]
allowed-tools: Bash(./scripts/development-workflow/post-merge-cleanup.sh:*), Bash(git branch:*), Bash(gh issue:*), Bash(gh api:*), Bash(gh project:*), mcp__claude_ai_Linear__get_issue, mcp__claude_ai_Linear__save_issue, mcp__claude_ai_Linear__list_issue_statuses
# If using a different issue tracker, add its MCP tool names here (e.g. mcp__jira__update_issue).
---

Run the post-merge cleanup script from the repository root.

- **From repo root**, run:
  ```bash
  ./scripts/development-workflow/post-merge-cleanup.sh [branch-name]
  ```
- **No argument**: use the current branch (user should run while still on the merged branch).
- **With `branch-name`**: delete that local branch (e.g. `feature/my-feature`).

The script will: fetch origin, checkout `develop`, pull, delete the local branch with `git branch -D` (force-delete; safe because the branch is already merged on the remote), and for implementation branches (`fix/*`, `feature/*`, `hotfix/*`, `refactor/*`) automatically close the associated GitHub issue if a merged PR is found for the branch. If the user is not in the repo root, `cd` to the repo root first (e.g. use the workspace root or ask which directory is the repo).

Do not skip steps or change the order. If the script fails, show the error and stop.

**After the script succeeds — update the issue tracker (if configured):**
The merged branch name often contains an issue identifier (e.g. `feature/ENG-123-user-auth` → `ENG-123`, or `feature/42-user-auth` → `#42`). If so, update that issue in the project's issue tracker using the branch-type-based status table from Step 10 of `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`:

| Merged branch type | Set tracker status to |
|---|---|
| `spec/*` | Spec Ready |
| `implementation-plan/*` | Plan Ready |
| `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` | Merged |

If the item's tracker status is already in a further-advanced state (e.g., already `In Development` when a spec branch merges), do not roll it back — leave it as-is.

For **GitHub Issues/Projects**: the script already closes the GitHub issue for implementation branches (if a merged PR is found). You still need to update the GitHub Projects board status field via `gh` CLI / GraphQL (see `docs/ai/development-workflow/integrations/github-projects.md`). For **Linear**, use the Linear MCP to set the issue status (see `docs/ai/development-workflow/integrations/linear.md`). For other trackers, set the equivalent status; see `docs/ai/development-workflow/integrations/issue-tracker.md`. If the branch has no issue ID or no tracker is in use, skip this step.

**After cleanup and tracker update — suggest a retrospective if appropriate:**
If this post-merge cleanup is the final action for a work item that was advanced in the current session (i.e., you drove the item through implementation, review, and merge in this conversation), suggest running a retrospective:

> Would you like to run a retrospective on this session's work?

Only suggest this when the cleanup is for a standalone item run (not when called as part of a batch merge or orchestrator flow, which handle retrospectives at their own level). See `docs/ai/development-workflow/protocols/06-retrospective-protocol.md`.
