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

When mode is `no_target_scan`, follow Protocol 90 Steps 1–3 (scan + propose)
only. Do not dispatch items under `/run-work`:

In `workflow_hub`, preserve selected product repository context in implementation handoffs.
This lets mutation-oriented follow-up commands route the artifact owner, local
path or remote identity, and PR/reviewer/cleanup work without re-resolving or
guessing.

Render the scan output with Protocol 90 report categories kept separate:
`INFORMATIONAL - not actionable in this proposal`,
`ACTIONABLE RESUME - can advance now`,
`PROPOSED BATCH - your decision`, and
`HELD - not included in proposed batch`. The recommended approval or
`/run-items` command applies only to `PROPOSED BATCH - your decision` items;
informational records are excluded unless the operator explicitly names them in
a separate bounded command.

Portfolio scan protocol: `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
