---
description: >
  Backlog maintenance. Periodic three-gate review of the whole backlog
  (structural ledger, order, closeout); complements /run-work.
  Usage: /review-backlog [optional scope hint]
---

# Claude Code Command: Review Backlog

Follow the backlog review protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md`

Pass any scope hint (project, milestone, `--all-projects`, `--aged-days`,
`--recent-days`) to the protocol's scope resolution. The protocol defines the
gates, the capability detection, and the write authority; this command
restates none of it. Confirmation in the conversation is the only write
authority, and the review never dispatches work — use `/run-work` afterwards
to select the batch.
