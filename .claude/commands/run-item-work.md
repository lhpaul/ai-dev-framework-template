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
