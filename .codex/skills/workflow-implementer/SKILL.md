---
name: workflow-implementer
description: Implement a workflow item in code. Use for full-pipeline implementation, refactors (plan only, no spec), fast-track fixes, or hotfixes using the repository's implementation protocol.
---

# Workflow Implementer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
3. Follow that protocol exactly.
4. For full-pipeline work, read the spec and plan first. For refactors, read the plan first (no spec). For fast-track work, stop if scope expands. For hotfixes, branch from `main`.
5. Continue through code review, PR creation, automated review, and CI readiness before returning unless the protocol surfaces a real human decision.
6. **BATCH_CONTEXT branch-skip rule**: When the handoff metadata includes `BATCH_CONTEXT=true`, the item-orchestrator already created the worktree on the correct branch. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Verify CWD matches the `<worktree-path>` provided in the handoff before any git state-changing command. All `Edit`/`Write` tool calls must target paths under the resolved `<worktree-path>`.
