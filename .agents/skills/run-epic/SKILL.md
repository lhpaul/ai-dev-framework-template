---
name: run-epic
description: Command-style Codex alias for resolving a native GitHub epic or explicit item list into a bounded workflow execution scope, with read-only PR risk classification before delegated merge decisions. Use when the user asks for /run-epic, run-epic, or wants a bounded epic execution set.
---

# Run Epic

This is the Codex command-style alias for Claude Code `/run-epic`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
3. Run `./scripts/development-workflow/run-epic-scope-resolver.sh` with the
   requested `--epic` or `--items` arguments.
4. Treat resolver output as the bounded scope contract. The resolver itself is
   read-only: do not update tracker status, create branches, open PRs, merge
   PRs, close issues, or delete branches from the resolver phase.
5. When a later delegated run reaches a candidate PR merge decision, run
   `./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number>`
   with the invocation's `--max-risk` before merge. The classifier is also
   read-only and does not replace reviewer-loop, CI-loop, thread, merge-state,
   readiness-label, or repository merge-protocol checks.
