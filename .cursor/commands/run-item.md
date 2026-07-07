---
description: "Primary bounded command: advance exactly one non-epic workflow item with shared prelude (scope, guardrails, policy/checkpoints) before Protocol 91. Usage: /run-item <target> [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---

# Cursor Command: Run Item

`/run-item` is the **canonical single-item bounded command**. It runs the shared
bounded prelude before any mutation, then advances exactly one non-epic item
through Protocol 91 until a real terminal condition.

For portfolio-wide or ambiguous targets, use `/run-work` (portfolio scan) or
`/run-epic` (bounded epic). `/run-item-work` is a deprecated compatibility alias
with identical behavior.

## Bounded prelude and Protocol 91

Run the shared bounded prelude and single-item loop per
`docs/workflow/development-workflow/bounded-run-prelude.md` and Protocol 91
(`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`).
The prelude command flags mirror this command's scope flags (`--target`, `--issue`,
`--branch`, `--pr`, `--development`, policy overrides, `--json`).

`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

Key responsibilities:

- Print `policyRecommendation.confirmationSummary` before mutation, including
  effective policy, field sources, pending checkpoint guidance, copy-paste
  equivalent, and the read-only guarantee.
- After explicit autonomy flags or human acceptance, record the
  invocation-scoped `RUN_ITEM_POLICY_CONFIRMED` item/policy binding and do not
  re-prompt for the same selected policy.
- Pending checkpoints, guardrail stops, review/CI failures, risk violations, and
  missing permissions still stop the run.
- Resolve the request to exactly one non-epic workflow item
- Use helper scripts in `scripts/development-workflow/` for next-action classification
- In `workflow_hub`, state selected product repository, artifact owner, and mutation target before implementation mutation
- Continue through creator, reviewer, PR, automated review, and CI until terminal
- If delegated merge authority is active and the merge gate returns
  `merge_allowed`, continue through merge, branch cleanup,
  `post-merge-cleanup.sh`, and live tracker verification before reporting
  terminal
- If the target is epic-like, stop and use `/run-epic` instead
