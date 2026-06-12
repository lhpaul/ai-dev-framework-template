---
description: Resolve a native GitHub epic or explicit item list into a read-only workflow execution scope. Usage: /run-epic --epic <issue-number> | --items <issue-number>[,<issue-number>...] [--base <branch>] [--json]
---

# Cursor Command: Run Epic

Follow the resolver protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`

Key responsibilities:

- Require exactly one of `--epic` or `--items`.
- Resolve native GitHub sub-issues for `--epic`; keep `--items` exact.
- Infer the base branch from `--base`, shared `integration-branch:<slug>`, or
  `develop`.
- Group items as `eligible`, `blocked`, `already_merged`, `in_review`,
  `ambiguous`, or `out_of_scope`.
- Keep the command read-only: no tracker updates, branches, PRs, merges, issue
  closure, or cleanup.

Use the helper script:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh "$@"
```
