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
8. For each in-scope item, pass the approved base and artifact-owning repo root
   to branch and PR creation paths and require
   `run-nested-artifact-guard.sh --repo-root "$ARTIFACT_REPO_ROOT"` before mutation. Stop on
   `missing_base`, `blocked_duplicate`, `wrong_base`, or `scan_failed` instead
   of widening scope or inferring a base.
9. Before dispatching an explicit-list batch where any runner may mutate,
   including sequential fallback, build the Protocol 90 isolation manifest and
   require a distinct absolute worktree path plus `isolation: "worktree"` for
   every mutating item. Stop before dispatch on missing isolation assignment or
   duplicate worktree path; non-isolated runners are exempt only when explicitly
   classified `read_only` and they will not edit files, switch branches, commit,
   push, mutate PRs, change labels, or update tracker state.
   Include the incremental commit requirement in every substantial or
   multi-part mutating runner handoff: commit immediately after each completed
   logical sub-part, do not intentionally batch all completed sub-parts into one
   final commit, and never commit incomplete or failing work only to satisfy the
   rule.
10. Do not stop after advancing one item if another item in the explicit list still
   has a deterministic next action.
11. Do not stop at transient in-flight CI/watch states. If a local watch exits
   early, duplicate checks are skipped/cancelled, or GitHub still shows pending
   or incomplete check evidence, re-query authoritative PR/check state and keep
   supervising until every in-scope PR is green, blocked, escalated, merged, or
   held by guardrails.
   For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   items, require residual gate evidence before accepting an item as
   `ready-for-human-review`.
12. For `spec/*` and `implementation-plan/*` PRs, require Protocol 91 Step 8a's
   documentation-stage alignment checker before accepting readiness. A
   mismatch keeps the item under supervision until corrected or escalated.
13. Before accepting any in-scope item as terminal, require the item runner's
   `## Ground-Truth Completion Verification` output from
   `item-completion-self-check.sh` or run the helper directly from current
   artifact state. Missing self-check evidence, `discrepancy`, or
   `unavailable_required` keeps the item under Protocol 90 Step 5 supervision.
14. After all in-scope PRs reach `ready-for-human-review`, inspect the effective
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
15. For single-item advancement use `$run-item`; for epic-scoped runs use `$run-epic`;
   for read-only portfolio scan and proposal use `$run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists and `/run-epic --epic <n>` for epic-scoped runs.
