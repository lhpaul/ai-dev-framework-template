---
name: run-item
description: "Primary bounded command: advance exactly one non-epic workflow item. Use when the user asks for /run-item or wants to resume a specific development, branch, PR, or issue with the shared bounded prelude before Protocol 91. /run-item-work is a deprecated alias with identical behavior."
---

# Run Item

This is the Codex command-style alias for Claude Code `/run-item`.

`/run-item` is the **canonical single-item bounded command**. It runs the shared
bounded prelude (scope, guardrails, policy/checkpoints) before any mutation, then
advances exactly one non-epic item through Protocol 91.

1. Read `AGENTS.md` for repository-wide rules.
2. Run the read-only bounded prelude:
   `./scripts/development-workflow/run-bounded-prelude.sh --original-command "<invocation>" <scope flags> --json`
   See `docs/workflow/development-workflow/bounded-run-prelude.md`.
3. When `policyRecommendation.requiresConfirmation` is true in the prelude JSON,
   print the resolved policy summary. If all autonomy flags (`--delegate-review`,
   `--may-merge`, `--may-start-backlog`, `--max-risk`) were provided explicitly
   in the invocation, those explicit flags serve as human confirmation — proceed
   immediately after printing the summary. Otherwise (any flag was inferred from
   scope, scope is ambiguous, or pending checkpoints remain), stop and ask the
   human to confirm, customize, or re-invoke with corrected flags.
4. Read `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   and follow it exactly. Do **not** delegate to `workflow-item-orchestrator` in the
   same run after Step 2 — that skill also runs the prelude and would duplicate
   scope/policy work.
5. Before implementation mutation in `workflow_hub`, state selected product
   repository, artifact owner, and mutation target; stop when context is missing
   or ambiguous.
6. **Guardrails enforcement**: Use portfolio-resolved guardrails from handoff when
   available; otherwise resolve from repo `guardrails` config. Report effective
   values before mutation. Enforce gates per
   `docs/workflow/development-workflow/guardrails-enforcement.md` section 3.
7. Epic-like targets must use `$run-epic` / `/run-epic`, not this command.

> **Deprecated alias**: `$run-item-work` / `/run-item-work` resolves to the same
> behavior for legacy invocations.
