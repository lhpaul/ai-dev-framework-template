---
description: "Propose portfolio batches (scan-only). No-target scan produces a batch recommendation; two or more targets emit /run-items redirect; single target redirects to /run-item; epics redirect to /run-epic. No mutation in any mode. Usage: /run-work [<target> ...]"
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

Run the classifier first (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

When `REDIRECT_COMMAND` is present, emit redirect guidance and perform **no**
mutation under `/run-work`.

For single-item execution use `/run-item`. For multi-item execution use `/run-items`.
For bounded epic work use `/run-epic`.

When mode is `no_target_scan`, follow Protocol 90 Steps 1–3 (scan + propose)
only. Do not dispatch items under `/run-work`:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
