---
name: run-epic
description: Command-style Codex alias for resolving a native GitHub epic or explicit item list into a read-only workflow execution scope. Use when the user asks for /run-epic, run-epic, or wants a bounded epic execution set.
---

# Run Epic

This is the Codex command-style alias for Claude Code `/run-epic`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
3. Run `./scripts/development-workflow/run-epic-scope-resolver.sh` with the
   requested `--epic` or `--items` arguments.
4. Treat the output as read-only scope resolution. Do not update tracker status,
   create branches, open PRs, merge PRs, close issues, or delete branches from
   this skill.
