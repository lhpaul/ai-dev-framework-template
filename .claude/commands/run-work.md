---
description: "Portfolio parallel orchestration only (Protocol 90). No-target scan or explicit multi-item batches. Single targets redirect to /run-item; epics redirect to /run-epic. Usage: /run-work [<target> ...]"
---

# Claude Code Command: Run Work

`/run-work` is **portfolio parallel orchestration only** — not a universal
"run anything" entrypoint.

| Routing mode | Handoff |
| ------------ | ------- |
| `no_target_scan` | Protocol 90 (portfolio scan) |
| `explicit_list` | Protocol 90 (hard bounded batch) |
| `redirect_item` | Stop; re-invoke `/run-item <target>` (no mutation) |
| `redirect_epic` | Stop; re-invoke `/run-epic --epic <n>` (no mutation) |
| `ambiguous` | Stop for human clarification |

Classifier (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

When output includes `REDIRECT_COMMAND`, present it to the operator and do not
enter Protocol 90.

Bounded single-item work: `/run-item`. Bounded epic work: `/run-epic`.

Portfolio protocol: `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
