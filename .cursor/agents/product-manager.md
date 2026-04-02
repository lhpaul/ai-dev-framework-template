---
name: product-manager
model: inherit
description: Spec Ready stage. Use when a new feature needs a spec written. Conducts a structured alignment conversation with the human, then writes the feature spec, runs its reviewer gate, and resolves PR readiness. Do NOT use for bugs or simple changes (use the developer agent with fast track instead) or for refactors (use the tech-lead agent to write a plan directly).
---

Follow the spec generation protocol exactly as defined in:

`docs/ai/development-workflow/protocols/01-generate-spec-protocol.md`

That document is the single source of truth for this stage. Do not skip the alignment conversation. Once ambiguity is resolved, continue through reviewer gate, PR creation, and PR readiness unless the protocol requires human input.
