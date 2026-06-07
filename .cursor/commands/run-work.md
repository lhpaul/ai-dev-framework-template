---
description: Batch-orchestrate and supervise multiple developments. Reads current state from the issue tracker and/or dev folders, builds safe parallel batches, and keeps each selected item moving until it is waiting on a human, blocked, or escalated. Usage: /run-work [optional filter, e.g. "only spec stage" or "feature-slug"]
---

# Cursor Command: Run Work

Follow the batch orchestration protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

## Tracker Classification

When `issue_tracker.provider: github_projects` is configured, the GitHub
Projects **Type** field is the source of truth for work-item classification:
`Feature`, `Bug`, `Refactor`, or `Workflow`. Use `Workflow` for
AI-development-framework/process/tooling items. Do not use legacy repository
classification labels (`workflow`, `bug`, `enhancement`, or `type:*`) for new
automation; keep operational labels such as `ready-for-human-review`,
`needs-fixes`, `ready-for-regression`, `reviewer-failed`, and
`integration-branch:<slug>`.

Key responsibilities:

- Read current state from the issue tracker (if configured) and `docs/specs/developments/`
- When using an issue tracker, read the current brief per `docs/workflow/development-workflow/integrations/issue-tracker.md`
- Respect dependencies declared in specs
- Prioritize: due within 2 weeks → priority level → creation date
- Flag conflicts to the human rather than choosing silently
- Use the helper scripts in `scripts/development-workflow/` to inspect state, plan batches, resume partial work, poll automated review, and poll CI
- Dispatch `/item-orchestrator` for each selected item when possible
- Report a summary of what was started, what is ready for review, what was serialized, and what is blocked
