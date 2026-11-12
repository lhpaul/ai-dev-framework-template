---
name: review-backlog
description: "Backlog maintenance command: periodic three-gate review of the whole backlog (structural ledger, order, closeout). Use when the user asks for /review-backlog. Detects tracker capabilities, waits for confirmation at each gate, and complements /run-work without dispatching work."
---

# Review Backlog

Follow `docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md`
exactly. This skill is a pointer; the protocol defines the gates, the
capability detection, and the write authority, and nothing here overrides it.

Pass any scope hint (project, milestone, `--all-projects`, `--aged-days`,
`--recent-days`) to the protocol's scope resolution. Confirmation in the
conversation is the only write authority. The review never dispatches work;
use `/run-work` afterwards to select the batch.
