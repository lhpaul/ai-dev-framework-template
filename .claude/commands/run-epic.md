---
description: Resolve a native GitHub epic or explicit item list into a bounded workflow execution scope, with PR risk classification before delegated merge decisions. Usage: /run-epic --epic <issue-number> | --items <issue-number>[,<issue-number>...] [--base <branch>] [--json]
---

# Claude Code Command: Run Epic

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
- Before any later delegated merge decision, run the PR risk classifier and
  respect its `--max-risk` gate.

Use the helper script:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh "$@"
```

Use the read-only risk helper before delegated merge decisions:

```bash
./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number> --max-risk <low|medium|high>
```
