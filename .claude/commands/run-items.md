---
description: "Bounded multi-item execute command: advance two or more explicit workflow items through Protocol 90 explicit_list mode, targeting develop directly. No scan or proposal step. Usage: /run-items <target> <target> [...] [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---

# Claude Code Command: Run Items

`/run-items` is the **bounded multi-item batch execute** command. It takes two or
more explicit item targets, validates the list with the read-only router, runs
the shared bounded prelude, and then executes through Protocol 90 in
`explicit_list` mode. PRs target `develop` directly without creating an
integration branch.

| Invocation | Router mode | Action |
| ---------- | ----------- | ------ |
| No target | `no_target_scan` | **Stop** — use `/run-work` for scan-only discovery |
| One non-epic target | `redirect_item` | **Stop** — use `/run-item <target>` |
| One epic target / `--epic` | `redirect_epic` | **Stop** — use `/run-epic --epic <n>` |
| Two or more non-epic targets | `redirect_items` | Continue to bounded prelude, then Protocol 90 `explicit_list` |
| Ambiguous target | `ambiguous` | **Stop** — report `stopReason`; do not mutate |

## Bounded prelude and Protocol 90

1. Run read-only router validation:

   ```bash
   ./scripts/development-workflow/run-work-router.sh <target> [<target>...] [--json]
   ```

   Continue only when the router returns `MODE=redirect_items` (or JSON
   `mode: "redirect_items"`). Use the resolved scope as the hard bounded list.
2. Run the shared bounded prelude before mutation:

   ```bash
   ./scripts/development-workflow/run-bounded-prelude.sh \
     --original-command "/run-items <target> <target>" \
     --items "<comma-separated-list>" \
     [policy flags] \
     --json
   ```

   `--items` takes a single comma-separated string such as `"978,979"`. When the
   prelude reports `policyRecommendation.requiresConfirmation: true`, present
   the policy/checkpoint recommendation and continue only after human acceptance,
   customization, or waiver.
3. Follow Protocol 90 in `explicit_list` mode:

`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Key responsibilities:

- Require at least two explicit item targets (issue numbers, PR numbers, branch names,
  or development folder paths).
- Use the supplied targets as the hard bounded scope for Protocol 90 `explicit_list` mode.
- Target `develop` directly; `/run-items` does not create or target
  `develop-<slug>` integration branches.
- In `workflow_hub`, state the selected product repository, artifact owner, and mutation
  target before implementation mutation; stop when context is missing or ambiguous.
- Do not stop after advancing one item if another in the list still has a
  deterministic next action.
- Do not stop at transient in-flight CI/watch states. If a local watch exits
  early, duplicate checks are skipped/cancelled, or GitHub still shows pending
  or incomplete check evidence, re-query authoritative PR/check state and keep
  supervising until every in-scope PR is green, blocked, escalated, merged, or
  held by guardrails.
- After all in-scope PRs reach `ready-for-human-review`, inspect the effective
  guardrails. When the relevant stages allow `may_merge_pr: true`, run
  Guardrails Enforcement Gate 5 for each in-scope PR, including
  `run-epic-risk-classifier.sh` and `run-epic-delegated-gate.sh`; continue only
  when every in-scope PR returns `merge_allowed`. Then route into Protocol 94
  batch merge using only the explicit in-scope PR list: run
  `batch-merge.sh discover --prs <comma-separated-in-scope-prs>` and continue
  through merge, cleanup, and tracker reconciliation. Never use Protocol 94
  auto-discovery from `/run-items`. If any stage does not allow merge, finish at the
  `ready-for-human-review` handoff, report the exact
  `stages.<stage>.may_merge_pr: false` guardrail for each affected PR, and tell
  the human to invoke `/batch-merge` or adjust guardrails to permit delegated
  merging.

For single-item advancement use `/run-item`. For epic-scoped runs use `/run-epic`.
For read-only portfolio scan and proposal use `/run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists and `/run-epic --epic <n>` for epic-scoped runs.
