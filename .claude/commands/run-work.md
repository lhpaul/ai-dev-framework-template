---
description: "Propose portfolio batches (scan-only). No-target scan produces a batch recommendation; all target invocations emit redirect guidance. No mutation in any mode. Usage: /run-work [<target> ...]"
---

# Claude Code Command: Run Work

`/run-work` is **portfolio scan and batch proposal only** — a fully read-only
command that inspects the portfolio and recommends the next safe batch or
redirect command. It performs **no mutation** in any routing mode.

| Routing mode | Action |
| ------------ | ------ |
| `no_target_scan` | Protocol 90 scan + propose (no dispatch) |
| `redirect_items` | Stop; re-invoke `/run-items <targets>` (no mutation) |
| `redirect_item` | Stop; re-invoke `/run-item <target>` (no mutation) |
| `redirect_epic` | Stop; re-invoke `/run-epic --epic <n>` (no mutation) |
| `ambiguous` | Stop for human clarification |

Classifier (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

When output includes `REDIRECT_COMMAND`, present it to the operator and do not
proceed with any mutation.

For single-item execution: `/run-item`. For multi-item execution: `/run-items`.
For bounded epic work: `/run-epic`.

Portfolio scan protocol: `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
