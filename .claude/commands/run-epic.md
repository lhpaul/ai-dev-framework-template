---
description: "Compatibility/advanced alias: resolve a native GitHub epic or explicit item list into a bounded workflow execution scope, with optional delegated review and merge gates. For the recommended starting point, use /run-work <epic-target> instead. Usage: /run-epic --epic <issue-number> | --items <issue-number>[,<issue-number>...] [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--json]"
---

# Claude Code Command: Run Epic

> **Compatibility/advanced alias**: `/run-epic` bypasses the `/run-work`
> routing layer and invokes the bounded epic scope resolver directly with
> explicit delegation flags. If you are not sure which command to use, start
> with `/run-work <epic-number>` — it will route to this protocol automatically
> when the target is epic-like. Use `/run-epic` when you need direct control
> over delegation flags (`--delegate-review`, `--may-merge`, `--max-risk`).

Follow the resolver protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`

Key responsibilities:

- Require exactly one of `--epic` or `--items`.
- Resolve native GitHub sub-issues for `--epic`; keep `--items` exact.
- Infer the execution base branch from `--base`, shared
  `integration-branch:<slug>`, or the applicable default.
- In `workflow_hub` mode, treat that base as the product implementation base;
  do not block because it is absent from the hub repository.
- Group items as `eligible`, `blocked`, `already_merged`, `in_review`,
  `ambiguous`, or `out_of_scope`.
- Keep the resolver phase read-only: no tracker updates, branches, PRs, merges,
  issue closure, or cleanup during scope resolution.
- When autonomy policy is missing or ambiguous, run the read-only policy
  recommender, present the recommended config and checkpoint policy in-place,
  and continue the same run when the human accepts or customizes it.
- Before any child item creates a branch or opens a PR, run
  `run-nested-artifact-guard.sh --mode <pre-create|pre-pr> --issue <number>
  --expected-branch <branch> --approved-base <branch>
  --repo-root "$ARTIFACT_REPO_ROOT"`. Stop on missing base, duplicate
  artifacts, wrong-base PRs, or scan failures unless an explicit split is
  approved and recorded.
- On checkpoint resume from a prior worktree-isolated item run, perform the
  Protocol 95/91 fail-closed checkpoint-resume gate before mutation with
  complete item, branch, worktree, main-root, and checkpoint-state context.
  Pending checkpoints and unclear isolation stop; the gate never satisfies or
  waives checkpoint state, and main-clone resumes must not change directories.
- Before any later delegated merge decision, run the PR risk classifier and
  respect its `--max-risk` gate.
- After delegated review, fix, merge, block, or escalation decisions, update
  stable PR disposition and epic ledger audit comments, including original,
  recommended, selected, and effective policy plus checkpoint state.
- Before merge, run the delegated gate with current scope, policy, reviewer,
  CI, risk, and audit evidence. Merge only when it reports `merge_allowed`.
- After `merge_allowed`, continue through Protocol 95 Step 11: merge, merge
  verification, branch deletion/pruning, `post-merge-cleanup.sh`, live tracker
  verification, audit update, and rediscovery.
- Treat merge authority explicitly: `merge_granted` makes readiness
  intermediate for in-scope child PRs; `merge_denied` stops at
  `ready_human_merge`; unexplained stalled-at-ready child PRs are
  `policy_inconsistent`; discovered unrelated PRs remain `out_of_scope`.

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
