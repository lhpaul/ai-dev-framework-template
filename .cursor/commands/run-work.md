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

For multi-item implementation proposals, include Protocol 90's planless overlap
disposition from `workflow-batch-overlap.sh`. Concrete pairs and unconfirmed
suspected pairs are serialized by default, and the proposal must show pair IDs,
typed evidence, evidence hashes, and held-item reasons.

In `workflow_hub`, preserve selected product repository context in
implementation handoffs so mutation-oriented follow-up commands can route the
artifact owner, local path or remote identity, and PR/reviewer/cleanup work
without re-resolving or guessing.

Render the scan output with Protocol 90 report categories kept separate:
`INFORMATIONAL - not actionable in this proposal`,
`ACTIONABLE RESUME - can advance now`,
`PROPOSED BATCH - your decision`, and
`HELD - not included in proposed batch`. The recommended approval or
`/run-items` command applies only to `PROPOSED BATCH - your decision` items;
informational records are excluded unless the operator explicitly names them in
a separate bounded command.

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
