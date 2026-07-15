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
9. Do not stop at transient in-flight CI/watch states. If a local watch exits
   early, duplicate checks are skipped/cancelled, or GitHub still shows pending
   or incomplete check evidence, re-query authoritative PR/check state and keep
   supervising until every in-scope PR is green, blocked, escalated, merged, or
   held by guardrails.
   For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   items, require residual gate evidence before accepting an item as
   `ready-for-human-review`.
10. After all in-scope PRs reach `ready-for-human-review`, inspect the effective
   guardrails. When the relevant stages allow `may_merge_pr: true`, run
   Guardrails Enforcement Gate 5 for each in-scope PR, including
   `run-epic-risk-classifier.sh` and `run-epic-delegated-gate.sh`; continue only
   when every in-scope PR returns `merge_allowed`. The bounded-prelude
   confirmation (or explicit autonomy flags) recorded for this `/run-items`
   invocation is the required merge gate for Protocol 90 `explicit_list` batches.
   Then route into Protocol 94 batch merge using only the explicit in-scope PR list:
   run
   `batch-merge.sh discover --prs <comma-separated-in-scope-prs>` and continue
   through merge, cleanup, and tracker reconciliation. Never use Protocol 94
   auto-discovery from `/run-items`. If any stage does not allow merge, finish at the
   `ready-for-human-review` handoff, report the exact
   `stages.<stage>.may_merge_pr: false` guardrail for each affected PR, and tell
   the human to invoke `$batch-merge` or adjust guardrails to permit delegated
   merging.
11. For single-item advancement use `$run-item`; for epic-scoped runs use `$run-epic`;
   for read-only portfolio scan and proposal use `$run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists and `/run-epic --epic <n>` for epic-scoped runs.
