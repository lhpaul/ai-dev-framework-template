---
name: run-item-work
description: "Deprecated compatibility alias for /run-item. Identical behavior — prefer $run-item or /run-item for new invocations."
---

# Run Item Work (deprecated)

> **Deprecated**: `$run-item-work` / `/run-item-work` is a compatibility alias for
> **`$run-item` / `/run-item`**. Use `$run-item` for new invocations.

1. Read `AGENTS.md` for repository-wide rules.
2. Follow `.agents/skills/run-item/SKILL.md` exactly (same bounded prelude + Protocol 91).
   This includes the fail-closed checkpoint-resume gate inherited from
   `$run-item`; the deprecated alias must not resume a checkpointed worktree run
   from the main clone or change directories to repair context. It also inherits
   the nested-artifact guard requirement before branch or PR creation.

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

