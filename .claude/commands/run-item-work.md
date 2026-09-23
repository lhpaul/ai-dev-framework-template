---
description: "Deprecated compatibility alias for /run-item. Identical behavior — use /run-item instead. Usage: /run-item-work <target>"
---

# Claude Code Command: Run Item Work (deprecated)

> **Deprecated**: `/run-item-work` is a compatibility alias for **`/run-item`**.
> New invocations should use `/run-item <target>`.

Follow the same protocol and prelude as `/run-item`:

- `.claude/commands/run-item.md`
- `docs/workflow/development-workflow/bounded-run-prelude.md`
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

The alias inherits `/run-item` preflight confirmation behavior, including
`policyRecommendation.confirmationSummary` and the invocation-scoped
`RUN_ITEM_POLICY_CONFIRMED` item/policy binding.

It also inherits `/run-item` checkpoint-resume gate behavior: a checkpointed
worktree-isolated run must invoke the fail-closed gate with complete context
before mutation. A main-clone resume stops instead of re-entering the worktree,
and isolation verification does not satisfy or waive checkpoint state.

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
