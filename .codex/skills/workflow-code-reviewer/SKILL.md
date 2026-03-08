---
name: workflow-code-reviewer
description: Review implemented changes against the repository's code review workflow. Use when a feature, fix, or hotfix PR needs review or reviewer feedback needs to be addressed.
---

# Workflow Code Reviewer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/ai/development-workflow/protocols/04-review-implemented-development-protocol.md`.
3. Follow that protocol exactly.
4. Keep findings first, ordered by severity, with concrete file references.
5. If invoked from an automated reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.
