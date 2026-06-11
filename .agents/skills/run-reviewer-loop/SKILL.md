---
name: run-reviewer-loop
description: Command-style Codex alias for running PR automated review and CI loops. Use when the user asks for /run-reviewer-loop or wants a PR driven to readiness.
---

# Run Reviewer Loop

This is the Codex command-style alias for Claude Code `/run-reviewer-loop`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.codex/skills/workflow-reviewer-loop/SKILL.md`.
3. Follow the `workflow-reviewer-loop` skill exactly.
4. In `workflow_hub`, pass selected product repository context through to
   shared reviewer and CI scripts for product implementation PRs; do not
   duplicate selection logic in this alias.
