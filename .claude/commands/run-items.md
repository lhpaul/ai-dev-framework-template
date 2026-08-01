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
- Before dispatching an explicit-list batch where any runner may mutate,
  including sequential fallback, build the Protocol 90 isolation manifest and
  require a distinct absolute worktree path plus `isolation: "worktree"` for
  every mutating item. Stop before dispatch on missing isolation assignment or
  duplicate worktree path. Non-isolated runners are allowed only when explicitly
  classified `read_only` and will not edit files, switch branches, commit, push,
  mutate PRs, change labels, or update tracker state.
- For checkpoint-resume redispatch, pass checkpoint state with the complete
  isolation assignment to a fresh runner and require `checkpoint-resume-gate.sh`
  before mutation. Do not resume a paused runner while sibling runners remain
  active, and do not treat isolation verification as satisfying or waiving the
  checkpoint.
- For plan-writing handoffs in the explicit list, pass the exact current-batch
  item list and any known same-surface open PR evidence to Protocol 02's
  `Cross-Cutting Operational Assumption Check`. Keep returned `Conflict`
  evidence visible until the parent records `Resolved` or stops for
  `unclear_requirements` and request `Human decision required`; do not widen
  the bounded list or replace this with an all-open-PR scan.
- Before parallel implementation dispatch, run Protocol 90's planless overlap
  gate from the current tracker snapshot and plan-derived file sets. Concrete
  pairs and suspected pairs without a matching current `allow_parallel` decision
  are serialized by default; pass serial groups into
  `workflow-batch-lanes.sh --overlap-input` or apply the identical hold result.
  Keep pair IDs, typed evidence, evidence hashes, accepted/stale decisions, and
  held-item reasons visible in confirmation and final summaries.
- In `workflow_hub`, state the selected product repository, artifact owner, and mutation
  target before implementation mutation; stop when context is missing or ambiguous.
- Do not stop after advancing one item if another in the list still has a
  deterministic next action.
- Do not stop at transient in-flight CI/watch states. If a local watch exits
  early, duplicate checks are skipped/cancelled, or GitHub still shows pending
  or incomplete check evidence, re-query authoritative PR/check state and keep
  supervising until every in-scope PR is green, blocked, escalated, merged, or
  held by guardrails.
- Before accepting any in-scope item as terminal, require the item runner's
  `## Ground-Truth Completion Verification` output from
  `item-completion-self-check.sh` (or run the helper directly). When Step 7
  was configured, pass `--require-review-summary true` and
  `--require-review-threads true` (helper defaults are false). Missing
  evidence, `discrepancy`, or `unavailable_required` keeps the item under
  Protocol 90 Step 5 supervision.
- After all in-scope PRs reach `ready-for-human-review`, inspect the effective
  guardrails. When the relevant stages allow `may_merge_pr: true`, run
  Guardrails Enforcement Gate 5 for each in-scope PR, including
  `run-epic-risk-classifier.sh` and `run-epic-delegated-gate.sh`; continue only
  when every normally merged in-scope PR returns `merge_allowed`. If any PR returns
  `exceptional_bypass_authorized`, split it out of the normal batch-merge list
  and require separate named PR/SHA/fingerprint authorization plus pre-attempt
  `reviewer-access-bypass` audit before one exact human-authorized
  `gh pr merge <pr> --admin` attempt. Then route normal candidates into
  Protocol 94 batch merge using only the explicit in-scope PR list: run
  `batch-merge.sh discover --prs <comma-separated-in-scope-prs>` and continue
  through merge, cleanup, post-sibling-merge `recheck-remaining` calls, and
  tracker reconciliation while keeping that explicit PR list frozen. Never use
  Protocol 94 auto-discovery from `/run-items`. If any stage does not allow merge, finish at the
  `ready-for-human-review` handoff, report the exact
  `stages.<stage>.may_merge_pr: false` guardrail for each affected PR, and tell
  the human to invoke `/batch-merge` or adjust guardrails to permit delegated
  merging.
- Report terminal outcomes per in-scope PR: `merged`, `ready_human_merge`,
  `merge_blocked`, `policy_inconsistent`, or `out_of_scope`. A
  `merge_granted` PR that stops at readiness without a named blocker is
  `policy_inconsistent`; a `merge_denied` PR stops at `ready_human_merge`.

For single-item advancement use `/run-item`. For epic-scoped runs use `/run-epic`.
For read-only portfolio scan and proposal use `/run-work`.

> **Deprecation notice**: `/run-epic --items` is deprecated. Use `/run-items` for
> explicit item lists and `/run-epic --epic <n>` for epic-scoped runs.
