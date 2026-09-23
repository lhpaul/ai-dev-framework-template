---
description: "Propose portfolio batches (scan-only). No-target scan produces a batch recommendation; all target invocations emit redirect guidance. No mutation in any mode. Usage: /run-work [<target> ...]"
---

# Claude Code Command: Run Work

`/run-work` is **portfolio scan and batch proposal only** — a fully read-only
command that inspects the portfolio and recommends the next safe batch or
redirect command. It performs **no mutation** in any routing mode.

| Routing mode | Action |
| ------------ | ------ |
| `no_target_scan` | Protocol 90 scan + propose (no dispatch) |
| `redirect_items` | Stop; re-invoke `/run-items <targets>` (no mutation) |
| `redirect_item` | Stop; re-invoke `/run-item <target>` (no mutation) |
| `redirect_epic` | Stop; re-invoke `/run-epic --epic <n>` (no mutation) |
| `ambiguous` | Stop for human clarification |

Classifier (read-only):

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

When output includes `REDIRECT_COMMAND`, present it to the operator and do not
proceed with any mutation.

For single-item execution: `/run-item`. For multi-item execution: `/run-items`.
For bounded epic work: `/run-epic`.

When mode is `no_target_scan`, follow Protocol 90 Steps 1–3 (scan + propose)
only. Do not dispatch items under `/run-work`:

For multi-item implementation proposals, include Protocol 90's planless overlap
disposition from `workflow-batch-overlap.sh`. Concrete pairs and unconfirmed
suspected pairs are serialized by default, and the proposal must show pair IDs,
typed evidence, evidence hashes, and held-item reasons.

In `workflow_hub`, preserve selected product repository context in implementation handoffs.
This lets mutation-oriented follow-up commands route the artifact owner, local
path or remote identity, and PR/reviewer/cleanup work without re-resolving or
guessing.

Render the scan output with Protocol 90 report categories kept separate:
`INFORMATIONAL - not actionable in this proposal`,
`ACTIONABLE RESUME - can advance now`,
`PROPOSED BATCH - your decision`, and
`HELD - not included in proposed batch`. The recommended approval or
`/run-items` command applies only to `PROPOSED BATCH - your decision` items;
informational records are excluded unless the operator explicitly names them in
a separate bounded command.

Portfolio scan protocol: `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

Routing specification: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`

---

## Cursor dispatch profile

This command runs only in a Cursor environment; other runners are unchanged by this requirement -- Claude Code and Codex behavior is unaffected. Before any mutating action, declare which dispatch profile is in force per `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` (the canonical, normative source): `cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`, naming the Portfolio Orchestrator (portfolio layer) as the accountable orchestration role.

Evaluation order: initial handoff -- whether the current context can hand orchestration to the Portfolio Orchestrator at all -- is evaluated first; onward-handoff capability -- whether the Portfolio Orchestrator can hand stage work onward -- is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

Unconfirmed-handoff outcomes: once initial handoff is confirmed available, onward-handoff capability that cannot be confirmed is treated as unavailable, and the run declares `cursor-parent-orchestrated` as the conservative default until confirmed. Separately, initial handoff availability that itself cannot be confirmed is treated the same as no handoff of any kind: the run declares `cursor-inline-fallback` and stays read-only for the remainder of the run. A later confirmation never upgrades a run in place; the next run declares afresh.

Accountability postures: a declaration states exactly one of personally accountable (absorbed), handed off intact, or observing for the Portfolio Orchestrator role. Observing is valid only at a read-only checkpoint; a mutating action always declares absorbed or handed off. The required posture follows the run's current checkpoint, never its earlier mutation history; a mismatch in either direction is a missing declaration.

`/run-work` is read-only under every profile: it always declares the observing posture for the Portfolio Orchestrator role and runs the scan in the current context regardless of which profile is in force. Acting on the scan's results requires a new bounded run with its own declaration.

Named stop conditions (exact strings): `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and the reused `missing_required_secret_or_permission`.

- `dispatch_profile_declaration_missing` -- affected work item: the branch, pull request, or development-folder path this invocation targets. Human unblocking action: the stopped run is not resumed or corrected in place; start a fresh invocation supplying a valid profile, a named accountable role, a posture valid for the checkpoint, and, when rejected for a fact mismatch, the profile the known facts assign.
- `dispatch_handoff_unavailable` -- affected work item: the branch, pull request, or development-folder path the mutating action would have applied to. Human unblocking action: move to an environment where initial handoff is confirmed available and re-run, or explicitly accept the read-only result; for the parent-orchestrated stage-handoff-unavailable cause, first confirm the specific stage role the action needed is reachable in the target environment.
- `missing_required_secret_or_permission` (reused) -- when a reachable stage role reports a specific delegated action refused for a missing credential, GitHub permission, or access token: grant the identified credential or permission and re-run the same delegated action, or, for a structural restriction, reassign to the same stage role in a different context or explicitly accept the action does not proceed; the absorbing context never performs the action inline. This path never extends to a harness tool or local file-path permission denial.

No named stop for a harness or local-path denial: a reachable stage role's harness tool or local file-path permission denial on a delegated action is not a named stop condition; it is only observably similar to the `SUBAGENT_PERMISSION_DENIAL` contract (Work Item Runner to Portfolio Orchestrator only), and is Out of Scope, tracked as #1746.

Invalid-declaration boundaries: an invalid profile value, an invalid accountable role (none named, including empty), an invalid posture for the checkpoint, and a coarse-fact mismatch in either direction (more permissive or less permissive than the assigned outcome) are each a missing declaration. The coarse check governs the initial declaration and coarse-fact re-declarations only; it does not govern the mid-run recovery transitions (stage-handoff loss, native-handoff mid-run failure), which remain valid re-declarations.
