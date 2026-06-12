---
name: run-work
description: Command-style Codex alias for portfolio orchestration. Use when the user asks for /run-work, run-work, or wants to batch-orchestrate workflow items.
---

# Run Work

This is the Codex command-style alias for Claude Code `/run-work`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.codex/skills/workflow-orchestrator/SKILL.md`.
3. Follow the `workflow-orchestrator` skill exactly.
4. For `workflow_hub` implementation work, preserve selected product repository
   context in item handoffs; missing mode or `single_repo` does not require
   `--repo`.
