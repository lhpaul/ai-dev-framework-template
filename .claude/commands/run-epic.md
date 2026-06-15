---
description: Resolve a native GitHub epic or explicit item list into a bounded workflow execution scope, with optional delegated review and merge gates. Usage: /run-epic --epic <issue-number> | --items <issue-number>[,<issue-number>...] [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--json]
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
- When autonomy policy is missing or ambiguous, run the read-only policy
  recommender, present the recommended config in-place, and continue the same
  run when the human accepts or customizes it.
- Before any later delegated merge decision, run the PR risk classifier and
  respect its `--max-risk` gate.
- After delegated review, fix, merge, block, or escalation decisions, update
  stable PR disposition and epic ledger audit comments, including original,
  recommended, selected, and effective policy.
- Before merge, run the delegated gate with current scope, policy, reviewer,
  CI, risk, and audit evidence. Merge only when it reports `merge_allowed`.

Use the helper script:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh "$@"
```

Optional delegation policy flags:

```bash
--delegate-review
--may-merge
--may-start-backlog <true|false>
--max-risk <low|medium|high>
```

Use the read-only policy recommender before mutation when policy is missing or
ambiguous:

```bash
./scripts/development-workflow/run-epic-policy-recommender.sh --scope <resolver-json> --original-command "<requested command>"
```

Pass `--no-delegate-review` or `--no-may-merge` to the recommender when the
selected policy explicitly disables a recommended positive default.

Use the read-only risk helper before delegated merge decisions:

```bash
./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number> --max-risk <low|medium|high>
```

Use the final delegated gate before merge:

```bash
./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>]
```

Use the audit helper after delegated decisions:

```bash
./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <file> --pr <pr-number>
./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <file> --epic <issue-number>
```
