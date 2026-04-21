---
name: workflow-plan-writer
description: Write an implementation plan for a feature (after spec approval) or a refactor (plan only, no spec). Use when a work item needs to advance into the implementation plan stage.
---

# Workflow Plan Writer

Recommended model tier: `premium`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md`.
3. Follow that protocol exactly.
4. Use the plan to make technical decisions that the spec intentionally avoids. For Refactor items, use the work item brief instead of a spec.
5. When the spec implies pattern-based completeness, run a live repo query, record a Verification Log, and only use frozen enumerations when explicitly authorized in the spec.
6. When the branch is created, continue through reviewer gate, PR creation, and PR readiness unless the protocol surfaces a real human decision.
