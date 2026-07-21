---
name: add-backlog-item
description: Command-style Codex alias for creating a backlog item. Use when the user asks for /add-backlog-item or wants to create a tracked work item before spec or plan work.
---

# Add Backlog Item

This is the Codex command-style alias for Claude Code `/add-backlog-item`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`.
3. Prefer `./scripts/development-workflow/add-backlog-item.sh resolve` to determine the configured tracker destination before creating anything.
4. Follow the protocol exactly. Do not invent tracker-specific fields when the configured integration cannot be resolved.
5. When candidate files are supplied, follow Step 2b and
   `docs/workflow/development-workflow/design-assets.md`: recognize likely design
   assets, clarify ambiguous files once, attach or stage confirmed assets, and
   record a `## Design assets` body section. Do not invent assets when none are
   supplied.
