---
name: workflow-spec-reviewer
description: Review and refine a workflow spec. Use when a spec draft or spec PR needs review against the repository's spec review protocol.
---

# Workflow Spec Reviewer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/ai/development-workflow/protocols/01-review-specs-protocol.md`.
3. Follow that protocol exactly.
4. Treat the protocol as the checklist; keep review findings concrete and scoped to the spec.
5. If invoked from an automated reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.
