---
name: workflow-orchestrator
description: Orchestrate the repository's staged AI development workflow. Use when the user wants Codex to discover what can advance, choose the next eligible action, and keep work moving until it reaches a real terminal condition.
---

# Workflow Orchestrator

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and terminal-condition expectations.
2. Read `docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md`.
3. Prefer the helper scripts in `scripts/development-workflow/` for state discovery, next-action classification, resume behavior, CI polling, and automated review polling before using ad hoc shell commands.
4. Treat the protocol as canonical. Use the matching workflow skill for the next stage when your runner supports skill-to-skill handoff; otherwise continue in the current session by following the referenced stage protocol directly.
5. Keep batching and prioritization decisions explicit, especially when work must be serialized because the runner cannot execute multiple skills concurrently.
6. Do not stop after a creator or reviewer stage if a deterministic next action still exists.
