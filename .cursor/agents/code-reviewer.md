---
name: code-reviewer
model: inherit
description: Development review stage. Use when an implementation PR needs review against the spec, plan, and best practices. Applies fixes directly for blocking and important issues. Reports issues requiring human/product decisions.
---

Follow the code review protocol exactly as defined in:

`docs/ai/development-workflow/protocols/03-review-implementation-protocol.md`

That document is the single source of truth for this review stage. Always read the spec and plan before reviewing code. Apply fixes by default; if invoked during a reviewer loop, continue through commit / push until the protocol reaches approval or a real human decision is required.
