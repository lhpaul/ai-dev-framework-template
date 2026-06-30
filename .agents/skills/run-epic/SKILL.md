---
name: run-epic
description: "Compatibility/advanced alias: resolve a native GitHub epic into a bounded workflow execution scope, with optional delegated review and merge gates. For the recommended starting point, use /run-work <epic-target> instead. Use /run-epic when you need direct control over delegation flags (--delegate-review, --may-merge, --max-risk). For explicit item lists, use /run-items."
---

# Run Epic

This is the Codex command-style alias for Claude Code `/run-epic`.

> **Compatibility/advanced alias**: `/run-epic` bypasses the `/run-work`
> routing layer and invokes the bounded epic scope resolver directly with
> explicit delegation flags. If you are not sure which command to use, start
> with `/run-work <epic-number>` — it will route to this protocol automatically
> when the target is epic-like.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
3. Run `./scripts/development-workflow/run-epic-scope-resolver.sh` with the
   `--epic <issue-number>` argument plus any invocation policy flags:
   `--delegate-review`, `--may-merge`, `--may-start-backlog <true|false>`,
   `--max-risk <low|medium|high>`, and `--base <branch>`.
   For explicit item lists, use `/run-items` instead of `--items`.
   In `workflow_hub` mode, treat the resolver's base as the product
   implementation base. Do not block because that branch is absent from the hub
   repository; validate it only after the owning product repository is selected.
4. Treat resolver output as the bounded scope contract. The resolver itself is
   read-only: do not update tracker status, create branches, open PRs, merge
   PRs, close issues, or delete branches from the resolver phase.
5. When autonomy policy values are missing or ambiguous, run
   `./scripts/development-workflow/run-epic-policy-recommender.sh --scope <resolver-json> --original-command "<requested command>"`
   with any supplied policy flags, including `--no-delegate-review` or
   `--no-may-merge` for explicit negative selections. Present the recommended
   policy, checkpoint policy, risk rationale, base branch, scoped items, and
   copy-paste equivalent command before mutation. Continue in the same run when
   the human accepts the recommendation or supplies custom values. Exact fully
   specified invocations may skip the prompt but still record original,
   recommended, selected, and effective policy in later audit evidence.
6. When a later delegated run reaches a candidate PR merge decision, run
   `./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number>`
   with the invocation's `--max-risk` before merge. The classifier is also
   read-only and does not replace reviewer-loop, CI-loop, thread, merge-state,
   readiness-label, or repository merge-protocol checks.
7. After delegated review, fix, merge, block, or escalation decisions, use
   `./scripts/development-workflow/run-epic-audit-trail.sh` to create or update
   stable PR disposition and epic ledger comments, including checkpoint state:
   - `render-pr-disposition --input <file>`
   - `apply-pr-disposition --input <file> --pr <pr-number>`
   - `render-epic-ledger --input <file>`
   - `apply-epic-ledger --input <file> --epic <issue-number>`
8. Before any delegated merge, run
   `./scripts/development-workflow/run-epic-delegated-gate.sh` with current
   scope, reviewer, CI, risk, and audit evidence; pass `--policy <file>` when
   the resolver policy is captured separately. Merge only when the gate reports
   `merge_allowed`.
9. **Guardrails layer context**: The `--delegate-review`, `--may-merge`,
   `--may-start-backlog`, and `--max-risk` flags are the **invocation-override**
   layer (highest priority) of the three-layer guardrails precedence. The
   repository `guardrails` config in `.ai-dev-workflow.yaml` is the base layer.
   An invocation override may narrow or widen authority only within what the mode
   permits. This protocol shares **one policy path** with Protocols 90 and 91 —
   the same run-epic helpers and enforcement gates defined in
   `docs/workflow/development-workflow/guardrails-enforcement.md`.
