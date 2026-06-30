---
description: "Read-only portfolio scan. No-target scan proposes batches; two or more targets redirect to /run-items; single targets redirect to /run-item; epics redirect to /run-epic. No mutation in any mode. Usage: /run-work [<target> ...]"
---

# Cursor Command: Run Work

`/run-work` is **portfolio scan and batch proposal only** — a fully read-only
command. It does not advance items directly in any invocation mode.

| Invocation | Routing mode | Action |
| ---------- | ------------ | ------ |
| No target | `no_target_scan` | Protocol 90 scan + propose a batch (no dispatch) |
| Two or more targets | `redirect_items` | **Stop** — re-invoke `/run-items <targets>` |
| One non-epic target | `redirect_item` | **Stop** — re-invoke `/run-item <target>` |
| Epic-like / `--epic` | `redirect_epic` | **Stop** — re-invoke `/run-epic --epic <n>` |
| Ambiguous target | `ambiguous` | **Stop** — report `stopReason`; do not mutate |

Run the router first (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

For single-item work use `/run-item`. For bounded multi-item batch execution use
`/run-items`. For epic-scoped runs use `/run-epic`.

When mode is `no_target_scan`, follow Protocol 90 Steps 1–3 (scan + propose)
only. Do not dispatch items under `/run-work`:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
