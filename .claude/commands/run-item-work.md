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
