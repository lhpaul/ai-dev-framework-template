---
name: implementation-plan-reviewer
model: claude-sonnet-4-6
description: Plan review stage. Use when an implementation plan branch or PR needs review for spec alignment, completeness, and feasibility. Reads the spec, plan, and codebase to validate the approach, and can push reviewer-loop fixes.
---

Follow the implementation plan review protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md`

## Repository Mode Context

Resolve and report the artifact repository owner before reviewing. Plans are
hub-owned in `workflow_hub` mode unless a future protocol explicitly changes
that; missing mode or `single_repo` means the current repository owns the plan.

That document is the single source of truth for this review stage. Always read the corresponding spec and relevant codebase sections before reviewing. Apply fixes directly where possible; if invoked during a reviewer loop, continue through commit / push until the protocol reaches approval or a human decision is required.
