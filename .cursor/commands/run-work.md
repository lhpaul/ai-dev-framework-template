---
description: Orchestrate and advance multiple developments in parallel. Reads current state from the issue tracker and/or dev folders, determines what can advance, and executes safe parallel work. Usage: @run-work [optional filter, e.g. "only spec stage" or "feature-slug"]
---

Follow the orchestration protocol exactly as defined in:

`docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md`

Key responsibilities:
- Read current state from the issue tracker (if configured) and `docs/specs/developments/`
- Respect dependencies declared in specs
- Prioritize: due within 2 weeks → priority level → creation date
- Flag conflicts to the human rather than choosing silently
- Report a summary of what was started, what is ready for review, and what is blocked
