---
description: Run a retrospective analysis on completed work to identify process improvement opportunities. Usage: /retrospective [PR number | branch name | batch date]
---

# Cursor Command: Retrospective

Invoke the `retrospective` agent to run the retrospective analysis.

Pass any scope hint provided by the user (PR number, branch name, or batch date) directly to the agent. When no hint is given, the agent defaults to recent PRs in the repository.
