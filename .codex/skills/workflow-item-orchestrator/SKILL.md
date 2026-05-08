---
name: workflow-item-orchestrator
description: Advance a single workflow item until it reaches a real terminal condition. Use when the user wants Codex to resume or advance one specific development, branch, or PR without scanning the whole portfolio.
---

# Workflow Item Orchestrator

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and terminal-condition expectations.
2. Read `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
3. Prefer the helper scripts in `scripts/development-workflow/` for next-action classification, resume behavior, CI polling, and automated review polling before using ad hoc shell commands.
4. Treat the protocol as canonical. Use the matching workflow skill for the next stage when your runner supports skill-to-skill handoff; otherwise continue in the current session by following the referenced stage protocol directly.
5. Stay scoped to one workflow item. If the request is portfolio-wide, route back to `workflow-orchestrator`.
6. **Stage-agent handoff branch-skip requirement (BATCH_CONTEXT=true only)**: When `BATCH_CONTEXT=true`, every stage-agent handoff must include: (a) the literal resolved `<worktree-path>` value, and (b) the explicit instruction "BATCH_CONTEXT=true — do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm CWD matches `<worktree-path>` before any git state-changing command." Omitting either instruction causes the stage subagent to run Protocol 03's branching steps from the main repo root, leaking a branch-switch into the main working tree.
