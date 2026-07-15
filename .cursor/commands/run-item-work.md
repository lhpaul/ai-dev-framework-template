---
description: "Deprecated compatibility alias for /run-item. Identical behavior — use /run-item instead. Usage: /run-item-work <target>"
---

# Cursor Command: Run Item Work (deprecated)

> **Deprecated**: `/run-item-work` is a compatibility alias for **`/run-item`**.
> New invocations should use `/run-item <target>`.

Behavior is identical to `/run-item`:

- `.cursor/commands/run-item.md`
- `docs/workflow/development-workflow/bounded-run-prelude.md`
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

This alias bypasses `/run-work` routing and advances exactly one known item
directly. For portfolio scans or epic batches, use `/run-work` or `/run-epic`.

The alias inherits `/run-item` preflight confirmation behavior, including
`policyRecommendation.confirmationSummary` and the invocation-scoped
`RUN_ITEM_POLICY_CONFIRMED` item/policy binding.

It also inherits `/run-item` checkpoint-resume worktree preflight behavior: a
checkpointed worktree-isolated run must re-enter the expected item worktree
before mutation, and re-entry does not satisfy or waive checkpoint state.
