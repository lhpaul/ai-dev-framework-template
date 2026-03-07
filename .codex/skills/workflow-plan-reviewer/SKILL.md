---
name: workflow-plan-reviewer
description: Review and refine an implementation plan. Use when a plan draft or plan PR needs review against the repository's plan review protocol.
---

# Workflow Plan Reviewer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/ai/development-workflow/protocols/02-review-implementation-plan-protocol.md`.
3. Follow that protocol exactly.
4. Validate the plan against the spec and existing codebase before suggesting changes.
5. If invoked from an automated reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.
