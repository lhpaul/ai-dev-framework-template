---
name: workflow-orchestrator
description: Orchestrate the repository's staged AI development workflow. Use when the user wants Codex to discover what can advance, choose the next eligible stage, and coordinate the work.
---

# Workflow Orchestrator

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and approval gates.
2. Read `docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md`.
3. Prefer `./scripts/discover-workflow-state.sh` for state discovery and `./scripts/check-workflow-branch.sh <branch>` for branch checks before using ad hoc shell commands.
4. Treat the protocol as canonical. Use the matching workflow skill for the next stage when your runner supports skill-to-skill handoff; otherwise continue in the current session by following the referenced stage protocol directly.
5. Keep batching and prioritization decisions explicit, especially when work must be serialized because the runner cannot execute multiple skills concurrently.
