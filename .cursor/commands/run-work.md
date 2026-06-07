---
description: Batch-orchestrate and supervise multiple developments. Reads current state from the issue tracker and/or dev folders, builds safe parallel batches, and keeps each selected item moving until it is waiting on a human, blocked, or escalated. Usage: /run-work [optional filter, e.g. "only spec stage" or "feature-slug"]
---

# Cursor Command: Run Work

Follow the batch orchestration protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Key responsibilities:

- Read current state from the issue tracker (if configured) and `docs/specs/developments/`
- When using an issue tracker, read the current brief per `docs/workflow/development-workflow/integrations/issue-tracker.md`
- When GitHub Projects is configured, use the Project **Type** field (`Feature`, `Bug`, `Refactor`, `Workflow`) for work-item classification; do not rely on legacy repository labels such as `workflow`, `bug`, `enhancement`, or `type:*`
- Respect dependencies declared in specs
- Prioritize: due within 2 weeks → priority level → creation date
- Flag conflicts to the human rather than choosing silently
- Use the helper scripts in `scripts/development-workflow/` to inspect state, plan batches, resume partial work, poll automated review, and poll CI
- Dispatch `/item-orchestrator` for each selected item when possible
- Report a summary of what was started, what is ready for review, what was serialized, and what is blocked
