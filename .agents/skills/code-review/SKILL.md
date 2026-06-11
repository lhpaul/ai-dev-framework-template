---
name: code-review
description: Command-style Codex alias for reviewing implementation changes. Use when the user asks for /code-review or wants the repository code review gate.
---

# Code Review

This is the Codex command-style alias for Claude Code `/code-review`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.codex/skills/workflow-code-reviewer/SKILL.md`.
3. Follow the `workflow-code-reviewer` skill exactly.
4. Resolve and report the implementation artifact owner before reviewing; in
   `workflow_hub`, product implementation PRs are reviewed in the selected
   product repository and hub-only workflow PRs remain hub-owned.
