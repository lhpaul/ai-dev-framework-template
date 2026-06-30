---
name: run-items
description: "Bounded multi-item execute command: advance two or more explicit workflow items through Protocol 90 explicit_list mode. For a single item use $run-item; for an epic use $run-epic; for a read-only portfolio scan use $run-work."
---

# Run Items

This is the Codex command-style alias for Claude Code `/run-items`.

`/run-items` is the **bounded multi-item batch execute** command. It takes two or
more explicit item targets, validates the list with the read-only router, runs
the shared bounded prelude, and then executes through Protocol 90 in
`explicit_list` mode. PRs target `develop` directly without a portfolio scan or
proposal step.

1. Read `AGENTS.md` for repository-wide rules.
2. Run read-only router validation:
   `./scripts/development-workflow/run-work-router.sh <target> [<target>...] [--json]`.
   Continue only when the router returns `MODE=redirect_items` (or JSON
   `mode: "redirect_items"`). Stop with redirect guidance for `no_target_scan`,
   `redirect_item`, `redirect_epic`, or `ambiguous`.
3. Run the read-only bounded prelude:
   `./scripts/development-workflow/run-bounded-prelude.sh --original-command "<invocation>" --items "<comma-separated-list>" [policy flags] --json`.
   Use a single comma-separated `--items` value such as `"978,979"`.
4. When `policyRecommendation.requiresConfirmation` is true in the prelude JSON,
   present policy/checkpoint recommendations and continue only after human
   acceptance, customization, or waiver.
5. Read `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
   and follow it in `explicit_list` mode with the supplied targets as the hard
   bounded scope.
6. Target `develop` directly; `/run-items` does not create or target
   `develop-<slug>` integration branches.
7. Before implementation mutation in `workflow_hub`, state the selected product
   repository, artifact owner, and mutation target; stop when context is missing
   or ambiguous.
8. Do not stop after advancing one item if another item in the explicit list still
   has a deterministic next action.
9. Stop with in-scope PRs at `ready-for-human-review`; landing is a separate
   `$batch-merge` step.
10. For single-item advancement use `$run-item`; for epic-scoped runs use `$run-epic`;
   for read-only portfolio scan and proposal use `$run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists and `/run-epic --epic <n>` for epic-scoped runs.
