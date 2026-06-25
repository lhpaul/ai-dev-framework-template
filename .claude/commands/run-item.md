---
description: "Primary bounded command: advance exactly one non-epic workflow item with shared prelude before Protocol 91. Usage: /run-item <target> [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---

# Claude Code Command: Run Item

`/run-item` is the **canonical single-item bounded command**. It runs the shared
bounded prelude before any mutation, then advances exactly one non-epic item
through Protocol 91 until a real terminal condition.

`/run-item-work` is a deprecated compatibility alias with identical behavior.

## Bounded prelude and Protocol 91

Run the shared bounded prelude and single-item loop per
`docs/workflow/development-workflow/bounded-run-prelude.md` and Protocol 91
(`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`).
The prelude command flags mirror this command's scope flags (`--target`, `--issue`,
`--branch`, `--pr`, `--development`, policy overrides, `--json`).

- Resolve exactly one non-epic workflow item
- Use `scripts/development-workflow/` helpers for next-action classification
- In `workflow_hub`, state product repository and mutation target before implementation mutation
- Continue until waiting on human, blocked, or escalated
- Epic-like targets → use `/run-epic` instead
