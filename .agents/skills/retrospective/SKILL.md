---
name: retrospective
description: Command-style Codex alias for running a retrospective. Use when the user asks for /retrospective or wants a completed batch or item analyzed.
---

# Retrospective

This is the Codex command-style alias for Claude Code `/retrospective`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.codex/skills/workflow-retrospective/SKILL.md`.
3. Follow the `workflow-retrospective` skill exactly.
4. For automated-reviewer retry-loop metrics, prefer the
   `reviewer_loop_history.v1` payload from the latest script-owned
   reviewer-loop summary comment before using legacy timestamp heuristics.
