---
description: "Portfolio parallel orchestration only: no-target scan or explicit multi-item batches (Protocol 90). Single targets redirect to /run-item; epics redirect to /run-epic. Usage: /run-work [<target> ...] — omit targets for portfolio scan; supply two or more for a hard bounded batch."
---

# Cursor Command: Run Work

`/run-work` is **portfolio parallel orchestration only**. It does not advance a
single item or epic directly.

| Invocation | Routing mode | Action |
| ---------- | ------------ | ------ |
| No target | `no_target_scan` | Protocol 90 — propose largest safe parallel batch |
| Two or more targets | `explicit_list` | Protocol 90 — bounded portfolio batch |
| One non-epic target | `redirect_item` | **Stop** — re-invoke `/run-item <target>` |
| Epic-like / `--epic` | `redirect_epic` | **Stop** — re-invoke `/run-epic --epic <n>` |

Run the classifier first (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

When `REDIRECT_COMMAND` is present, emit redirect guidance and perform **no**
mutation under `/run-work`.

For single-item work use `/run-item`. For bounded epic work use `/run-epic`.

Follow Protocol 90 when mode is `no_target_scan` or `explicit_list`:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
