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

In a Cursor environment only, declare the dispatch profile in force before any
mutating action — `cursor-native-handoff`, `cursor-parent-orchestrated`, or
`cursor-inline-fallback` — naming the Work Item Runner (item layer) as the
accountable orchestration role, with a posture valid for the current checkpoint. Other runners are unaffected by
this requirement.

Evaluation order, unconfirmed-handoff outcomes, accountability postures, the
named stop conditions and their human unblocking actions, and the
invalid-declaration boundaries are defined once, normatively, in
`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.
Follow that document; this surface deliberately does not restate it.

