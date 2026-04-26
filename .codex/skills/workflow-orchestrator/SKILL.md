---
name: workflow-orchestrator
description: Batch-orchestrate the repository's staged AI development workflow. Use when the user wants Codex to discover what can advance across multiple items, build safe parallel batches, and supervise each item until it reaches a real terminal condition.
---

# Workflow Orchestrator

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and terminal-condition expectations.
2. Read `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
3. Prefer the helper scripts in `scripts/development-workflow/` for state discovery, batch planning, next-action classification, resume behavior, CI polling, and automated review polling before using ad hoc shell commands.
4. Treat the protocol as canonical. Use `workflow-item-orchestrator` for each selected item when your runner supports skill-to-skill handoff; otherwise continue in the current session by following `91-orchestrate-work-protocol.md` item by item.
5. Keep batching and prioritization decisions explicit, especially when work must be serialized because the runner cannot execute multiple item orchestrators concurrently.
6. Do not stop after dispatching a batch if any selected item still has a deterministic next action.
