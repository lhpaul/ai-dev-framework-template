---
name: run-work
description: "Propose portfolio batches (scan-only). No-target scan produces a batch recommendation with no dispatch. Two or more targets redirect to $run-items. Single targets redirect to $run-item or $run-epic. No mutation in any mode."
---

# Run Work

This is the Codex command-style alias for Claude Code `/run-work`.

`/run-work` is **portfolio scan and batch proposal only** — a fully read-only
command. It performs no mutation in any routing mode.

| Routing mode | Action |
| ------------ | ------ |
| `no_target_scan` | Protocol 90 scan + propose (no dispatch); operator uses `$run-items` to execute |
| `redirect_items` | Stop; tell the user to run `$run-items` with the resolved targets |
| `redirect_item` | Stop; tell the user to run `$run-item` with the resolved target |
| `redirect_epic` | Stop; tell the user to run `$run-epic --epic <n>` |
| `ambiguous` | Stop; report `stopReason` |

1. Read `AGENTS.md` for repository-wide rules.
2. Run `./scripts/development-workflow/run-work-router.sh [<target>...] [--json]`.
3. Stop with **no mutation** when any routing mode other than `no_target_scan` is
   returned, or when stdout includes `REDIRECT_COMMAND=` (key=value output).
   With `--json`, also check `redirectCommand` in the routing record.
4. For `no_target_scan`, follow Protocol 90 Steps 1–3 (scan + propose) only.
   Do **not** dispatch items — present the proposal and emit the recommended
   `/run-items` command for the operator to execute.
5. For single-item advancement use `$run-item`; for epic bounded runs use `$run-epic`;
   for multi-item execution use `$run-items`.
6. In `workflow_hub`, preserve selected product repository context when building
   the portfolio proposal.

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
