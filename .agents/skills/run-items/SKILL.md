---
name: run-items
description: "Bounded multi-item execute command: advance two or more explicit workflow items through Protocol 90 explicit_list mode. For a single item use $run-item; for an epic use $run-epic; for a read-only portfolio scan use $run-work."
---

# Run Items

This is the Codex command-style alias for Claude Code `/run-items`.

`/run-items` is the **bounded multi-item batch execute** command. It takes two or
more explicit item targets and executes them through Protocol 90 in
`explicit_list` mode, targeting `develop` directly without a portfolio scan or
proposal step.

1. Read `AGENTS.md` for repository-wide rules.
2. Require at least two explicit item targets (issue numbers, PR numbers, branch names,
   or development folder paths). A single target must use `$run-item` instead.
3. Read `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
   and follow it in `explicit_list` mode with the supplied targets as the hard bounded scope.
4. Resolve guardrails before any mutation: confirm effective autonomy mode, PR-open,
   delegated review, and delegated merge permissions.
5. Before implementation mutation in `workflow_hub`, state the selected product
   repository, artifact owner, and mutation target; stop when context is missing
   or ambiguous.
6. Do not stop after advancing one item if another item in the explicit list still
   has a deterministic next action.
7. For single-item advancement use `$run-item`; for epic-scoped runs use `$run-epic`;
   for read-only portfolio scan and proposal use `$run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists and `/run-epic --epic <n>` for epic-scoped runs.
