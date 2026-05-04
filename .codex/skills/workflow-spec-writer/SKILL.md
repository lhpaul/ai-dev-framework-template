---
name: workflow-spec-writer
description: Write a feature spec for the AI development workflow. Use when a new feature needs to move from backlog into the spec stage.
---

# Workflow Spec Writer

Recommended model tier: `premium`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`.
3. Follow that protocol exactly.
4. Keep the spec product-focused; implementation details belong in the plan stage.
5. For tracker-backed briefs, include the mandatory Brief Objective List, Coverage Matrix, and PR-visible Deferral Notes before moving to PR readiness.
6. When the branch is created, continue through reviewer gate, PR creation, and PR readiness unless the protocol surfaces a real human decision.
