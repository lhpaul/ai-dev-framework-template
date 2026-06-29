---
description: "Read-only portfolio scan: discovers what can advance, proposes the largest safe batch options. No execution — for bounded multi-item execution use /run-items; for single items use /run-item; for epics use /run-epic. Usage: /run-work — no targets (scan mode only)."
---

# Cursor Command: Run Work

`/run-work` is the **read-only portfolio scan** entrypoint. It scans the
portfolio and proposes what can advance, without executing or mutating anything.

| Routing mode | Action |
| ------------ | ------ |
| `no_target_scan` | Scan portfolio — propose largest safe batch (read-only) |
| `ambiguous` | Stop; report `stopReason` |

Run the router first (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [--json]
```

For single-item work use `/run-item`. For bounded multi-item batch execution use
`/run-items`. For epic-scoped runs use `/run-epic`.

Follow Protocol 90 proposal mode when mode is `no_target_scan`:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
