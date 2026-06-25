---
name: run-work
description: "Portfolio parallel orchestration only: no-target scan or explicit multi-item batches via Protocol 90. Single targets redirect to $run-item; epics redirect to $run-epic. Use $run-item or $run-epic for bounded single-item or epic work."
---

# Run Work

This is the Codex command-style alias for Claude Code `/run-work`.

`/run-work` is **portfolio parallel orchestration only**. It does not mutate for
single-item or epic invocations — the router emits `redirect_item` or
`redirect_epic` with a `REDIRECT_COMMAND` instead.

| Routing mode | Action |
| ------------ | ------ |
| `no_target_scan` | Read `.codex/skills/workflow-orchestrator/SKILL.md` / Protocol 90 |
| `explicit_list` | Protocol 90 with hard bounded scope |
| `redirect_item` | Stop; tell the user to run `$run-item` with the resolved target |
| `redirect_epic` | Stop; tell the user to run `$run-epic --epic <n>` |
| `ambiguous` | Stop; report `stopReason` |

1. Read `AGENTS.md` for repository-wide rules.
2. Run `./scripts/development-workflow/run-work-router.sh [<target>...] [--json]`.
3. When `redirectCommand` is set, **do not mutate** — surface the redirect and stop.
4. For `no_target_scan` / `explicit_list`, follow Protocol 90 via `workflow-orchestrator`.
5. For single-item advancement use `$run-item`; for epic bounded runs use `$run-epic`.

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
