---
description: Run a retrospective analysis on completed work to identify process improvement opportunities. Usage: /retrospective [PR number | branch name | batch date]
---

# Claude Code Command: Retrospective

Dispatch the `retrospective` agent to run the retrospective analysis.

Pass any scope hint provided by the user (PR number, branch name, or batch date) directly to the agent. When no hint is given, the agent defaults to recent PRs in the repository.

**Context bridging**: The retrospective agent runs as a subagent and cannot read the parent conversation. Batch notes saved to memory (e.g. `project_batchN_retro_notes.md`) are the primary context bridge — the orchestrator saves these proactively during supervision. If any key corrections or anomalies were NOT saved to memory, include a brief summary in the scope hint before dispatching.
