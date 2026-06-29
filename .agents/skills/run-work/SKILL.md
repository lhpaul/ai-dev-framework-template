---
name: run-work
description: "Read-only portfolio scan: discovers what can advance, proposes the largest safe batch options, and redirects single/epic targets. No execution — for bounded multi-item execution use $run-items; for single items use $run-item; for epics use $run-epic."
---

# Run Work

This is the Codex command-style alias for Claude Code `/run-work`.

`/run-work` is the **read-only portfolio scan** entrypoint. It scans the
portfolio and proposes what can advance, without executing or mutating anything.
For execution, use `$run-items` (multi-item bounded batch), `$run-item` (single
item), or `$run-epic` (epic-scoped run).

| Routing mode | Action |
| ------------ | ------ |
| `no_target_scan` | Scan portfolio; propose largest safe parallel plan (read-only, no mutation) |
| `redirect_item` | Stop; tell the user to run `$run-item` with the resolved target |
| `redirect_epic` | Stop; tell the user to run `$run-epic --epic <n>` |
| `ambiguous` | Stop; report `stopReason` |

1. Read `AGENTS.md` for repository-wide rules.
2. Run `./scripts/development-workflow/run-work-router.sh [--json]` (no targets — scan mode).
3. Stop with **no mutation** when mode is `redirect_item` or `redirect_epic`, or when
   stdout includes `REDIRECT_COMMAND=` (key=value output). With `--json`, also check
   `redirectCommand` in the routing record.
4. For `no_target_scan`, follow Protocol 90 proposal mode via `workflow-orchestrator`
   to scan and propose. Do not dispatch execution in this mode.
5. For bounded multi-item execution use `$run-items`; for single items use `$run-item`;
   for epic-scoped runs use `$run-epic`.

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
