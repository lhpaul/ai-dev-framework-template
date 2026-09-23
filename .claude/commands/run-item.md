---
description: "Primary bounded command: advance exactly one non-epic workflow item with shared prelude before Protocol 91. Usage: /run-item <target> [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---

# Claude Code Command: Run Item

`/run-item` is the **canonical single-item bounded command**. It runs the shared
bounded prelude before any mutation, then advances exactly one non-epic item
through Protocol 91 until a real terminal condition.

`/run-item-work` is a deprecated compatibility alias with identical behavior.

## Bounded prelude and Protocol 91

Run the shared bounded prelude and single-item loop per
`docs/workflow/development-workflow/bounded-run-prelude.md` and Protocol 91
(`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`).
The prelude command flags mirror this command's scope flags (`--target`, `--issue`,
`--branch`, `--pr`, `--development`, policy overrides, `--json`).

- Print `policyRecommendation.confirmationSummary` before mutation, including
  effective policy, field sources, pending checkpoint guidance, copy-paste
  equivalent, and the read-only guarantee.
- After explicit autonomy flags or human acceptance, record the
  invocation-scoped `RUN_ITEM_POLICY_CONFIRMED` item/policy binding and do not
  re-prompt for the same selected policy.
- Pending checkpoints, guardrail stops, review/CI failures, risk violations, and
  missing permissions still stop the run.
- When resuming after a human-checkpoint pause from a prior worktree-isolated
  run, invoke Protocol 91's fail-closed checkpoint-resume gate before any
  mutation with item, expected branch, expected worktree, main repo root, and
  checkpoint state. Continue only on `RESULT=continue`; pending checkpoints and
  unclear isolation stop. The gate never satisfies or waives checkpoint state,
  and main-clone resumes must not change directories.
- Resolve exactly one non-epic workflow item
- Use `scripts/development-workflow/` helpers for next-action classification
- After candidate discovery and the nested-artifact guard, require a
  `compatible` result from `validate-branch-reuse.sh` before reusing an existing
  branch. Stop distinctly on incompatible or unverifiable evidence; never
  delete or rewrite the branch automatically, and keep tracking divergence
  diagnostic only.
- In `workflow_hub`, state product repository and mutation target before implementation mutation
- Continue until waiting on human, blocked, or escalated
- If delegated merge authority is active and the merge gate returns
  `merge_allowed`, continue through merge, branch cleanup,
  `post-merge-cleanup.sh`, and live tracker verification before reporting
  terminal
- If the merge gate returns `exceptional_bypass_authorized`, follow the
  canonical exceptional-bypass policy in
  `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5;
  delegated merge authority is not enough
- Treat merge authority explicitly: `merge_granted` means readiness is
  intermediate and the runner continues through merge; `merge_denied` means the
  ready PR stops as `ready_human_merge` and no merge command is run. Stopping
  at readiness without a named blocker in a merge-granted run is
  `policy_inconsistent`
- Epic-like targets → use `/run-epic` instead

---

## Cursor dispatch profile

This command runs only in a Cursor environment; other runners are unchanged by this requirement -- Claude Code and Codex behavior is unaffected. Before any mutating action, declare which dispatch profile is in force per `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` (the canonical, normative source): `cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`, naming the Work Item Runner (item layer) as the accountable orchestration role.

Evaluation order: initial handoff -- whether the current context can hand orchestration to the Work Item Runner at all -- is evaluated first; onward-handoff capability -- whether the Work Item Runner can hand stage work onward -- is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

Unconfirmed-handoff outcomes: once initial handoff is confirmed available, onward-handoff capability that cannot be confirmed is treated as unavailable, and the run declares `cursor-parent-orchestrated` as the conservative default until confirmed. Separately, initial handoff availability that itself cannot be confirmed is treated the same as no handoff of any kind: the run declares `cursor-inline-fallback` and stays read-only for the remainder of the run. A later confirmation never upgrades a run in place; the next run declares afresh.

Accountability postures: a declaration states exactly one of personally accountable (absorbed), handed off intact, or observing for the Work Item Runner role. Observing is valid only at a read-only checkpoint; a mutating action always declares absorbed or handed off. The required posture follows the run's current checkpoint, never its earlier mutation history; a mismatch in either direction is a missing declaration.

Under `cursor-parent-orchestrated`: the current context absorbs the item layer itself (Protocol 91's full contract), dispatches no Work Item Runner, and delegates every stage of product work (spec, plan, implement, review) to its stage role with full handoff metadata -- never inline.

Named stop conditions (exact strings): `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and the reused `missing_required_secret_or_permission`.

- `dispatch_profile_declaration_missing` -- affected work item: the branch, pull request, or development-folder path this invocation targets. Human unblocking action: the stopped run is not resumed or corrected in place; start a fresh invocation supplying a valid profile, a named accountable role, a posture valid for the checkpoint, and, when rejected for a fact mismatch, the profile the known facts assign.
- `dispatch_handoff_unavailable` -- affected work item: the branch, pull request, or development-folder path the mutating action would have applied to. Human unblocking action: move to an environment where initial handoff is confirmed available and re-run, or explicitly accept the read-only result; for the parent-orchestrated stage-handoff-unavailable cause, first confirm the specific stage role the action needed is reachable in the target environment.
- `missing_required_secret_or_permission` (reused) -- when a reachable stage role reports a specific delegated action refused for a missing credential, GitHub permission, or access token: grant the identified credential or permission and re-run the same delegated action, or, for a structural restriction, reassign to the same stage role in a different context or explicitly accept the action does not proceed; the absorbing context never performs the action inline. This path never extends to a harness tool or local file-path permission denial.

No named stop for a harness or local-path denial: a reachable stage role's harness tool or local file-path permission denial on a delegated action is not a named stop condition; it is only observably similar to the `SUBAGENT_PERMISSION_DENIAL` contract (Work Item Runner to Portfolio Orchestrator only), and is Out of Scope, tracked as #1746.

Invalid-declaration boundaries: an invalid profile value, an invalid accountable role (none named, including empty), an invalid posture for the checkpoint, and a coarse-fact mismatch in either direction (more permissive or less permissive than the assigned outcome) are each a missing declaration. The coarse check governs the initial declaration and coarse-fact re-declarations only; it does not govern the mid-run recovery transitions (stage-handoff loss, native-handoff mid-run failure), which remain valid re-declarations.
