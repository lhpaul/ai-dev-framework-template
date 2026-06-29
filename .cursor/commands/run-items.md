---
description: "Execute an explicit bounded batch: two or more items through Protocol 90 explicit_list mode, targeting develop directly. No scan or proposal step. Usage: /run-items <target> <target> [...] [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---

# Cursor Command: Run Items

`/run-items` is the **bounded multi-item batch execute** command. It takes two or
more explicit item targets and executes them through Protocol 90 in
`explicit_list` mode, targeting `develop` directly.

| Invocation | Action |
| ---------- | ------ |
| Two or more targets | `explicit_list` — Protocol 90 bounded portfolio batch |
| One target | Error — use `/run-item <target>` for a single item |

Follow Protocol 90 in `explicit_list` mode:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Key responsibilities:

- Require at least two explicit item targets (issue numbers, PR numbers, branch names,
  or development folder paths).
- Use the supplied targets as the hard bounded scope for Protocol 90 `explicit_list` mode.
- Resolve guardrails before any mutation; confirm effective autonomy mode, PR-open,
  delegated review, and delegated merge permissions.
- Infer the execution base branch from `--base` or the applicable default.
- In `workflow_hub`, include selected product repository context in implementation handoffs.
- Do not stop after advancing one item if another in the list still has a
  deterministic next action.

For single-item advancement use `/run-item`. For epic-scoped runs use `/run-epic`.
For read-only portfolio scan and proposal use `/run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists.

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
