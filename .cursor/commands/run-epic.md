---
description: "Compatibility/advanced alias: resolve a native GitHub epic into a bounded workflow execution scope, with optional delegated review and merge gates. For the recommended starting point, use /run-work <epic-target> instead. For explicit item lists, use /run-items. Usage: /run-epic --epic <issue-number> [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--json]"
---

# Cursor Command: Run Epic

> **Compatibility/advanced alias**: `/run-epic` bypasses the `/run-work`
> routing layer and invokes the bounded epic scope resolver directly with
> explicit delegation flags. If you are not sure which command to use, start
> with `/run-work <epic-number>` — it will route to this protocol automatically
> when the target is epic-like. Use `/run-epic` when you need direct control
> over delegation flags (`--delegate-review`, `--may-merge`, `--max-risk`).

Follow the resolver protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`

Key responsibilities:

- Require `--epic <issue-number>`. For explicit item lists, use `/run-items`.
- Resolve native GitHub sub-issues for the epic.
- Infer the execution base branch from `--base`, shared
  `integration-branch:<slug>`, or the applicable default.
- In `workflow_hub` mode, treat that base as the product implementation base;
  do not block because it is absent from the hub repository.
- Group items as `eligible`, `blocked`, `already_merged`, `in_review`,
  `ambiguous`, or `out_of_scope`.
- Keep the command read-only: no tracker updates, branches, PRs, merges, issue
  closure, or cleanup.
- When autonomy policy is missing or ambiguous, run the read-only policy
  recommender, present the recommended config and checkpoint policy in-place,
  and continue the same run when the human accepts or customizes it.
- Before any later delegated merge decision, run the PR risk classifier and
  respect its `--max-risk` gate.
- After delegated review, fix, merge, block, or escalation decisions, update
  stable PR disposition and epic ledger audit comments, including original,
  recommended, selected, and effective policy plus checkpoint state.
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
