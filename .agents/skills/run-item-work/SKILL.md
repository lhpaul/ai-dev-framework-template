---
name: run-item-work
description: Command-style Codex alias for advancing one workflow item. Use when the user asks for /run-item-work or wants to resume a specific development, branch, or PR.
---

# Run Item Work

This is the Codex command-style alias for Claude Code `/run-item-work`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.codex/skills/workflow-item-orchestrator/SKILL.md`.
3. Follow the `workflow-item-orchestrator` skill exactly.
4. Before mutation in `workflow_hub`, state selected product repository,
   artifact owner, and mutation target; stop when product repository context is
   missing or ambiguous.
5. **Guardrails enforcement**: At item-run start, use portfolio-resolved
   guardrails from handoff metadata when available; otherwise resolve from repo
   `guardrails` config. Report effective values before mutation. Enforce
   per-stage PR-open, delegated review, delegated merge, and completion gates per
   `docs/workflow/development-workflow/guardrails-enforcement.md` section 3.
