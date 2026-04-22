---
description: Run a retrospective analysis on completed work to identify process improvement opportunities. Usage: /retrospective [PR number | branch name | batch date]
---

# Claude Code Command: Retrospective

Follow the retrospective protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`

- **Scope**: Analyze the PRs from the current session or the scope hint provided (PR number, branch name, or batch date). When no hint is given, default to recent PRs in the repository.
- **Data sources**: GitHub PR metadata (via `gh`) and, when conversation context is available, the current session's conversation history.
- **Output**: A categorized list of improvement opportunities — each with a category, severity signal, and recommended action. Present findings first, then act only on the human's explicit choices.
- **Actions**: "Address now" applies a simple fix, commits, and pushes (no new PR). "Add to backlog" creates a GitHub issue directly. "Skip" moves on.
- **Constraint**: Never apply fixes or create issues without the human's explicit choice.
