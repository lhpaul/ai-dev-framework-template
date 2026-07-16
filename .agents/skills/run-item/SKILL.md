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
   print `policyRecommendation.confirmationSummary`, including effective policy,
   field sources, pending checkpoint guidance, copy-paste equivalent, and the
   read-only guarantee. If all autonomy flags (`--delegate-review`,
   `--may-merge`, `--may-start-backlog`, `--max-risk`) were provided explicitly
   in the invocation, those explicit flags serve as human confirmation — proceed
   immediately after printing the summary and recording the invocation-scoped
   `RUN_ITEM_POLICY_CONFIRMED` item/policy binding. Otherwise (any flag was
   inferred from scope, scope is ambiguous, or pending checkpoints remain), stop
   and ask the human to confirm, customize, provide checkpoint input, or
   re-invoke with corrected flags.
4. Read `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   and follow it exactly. Do **not** delegate to `workflow-item-orchestrator` in the
   same run after Step 2 — that skill also runs the prelude and would duplicate
   scope/policy work.
5. Before implementation mutation in `workflow_hub`, state selected product
   repository, artifact owner, and mutation target; stop when context is missing
   or ambiguous.
6. Before branch creation or PR creation for a tracker-backed item, run
   `run-nested-artifact-guard.sh` with the expected branch, approved base, and
   artifact-owning repo root (`--repo-root "$ARTIFACT_REPO_ROOT"`).
   Stop on `missing_base`, `blocked_duplicate`, `wrong_base`, or `scan_failed`;
   explicit split work requires parent approval and `--allow-split true`.
7. **Guardrails enforcement**: Use portfolio-resolved guardrails from handoff when
   available; otherwise resolve from repo `guardrails` config. Report effective
   values before mutation. Enforce gates per
   `docs/workflow/development-workflow/guardrails-enforcement.md` section 3.
   When resuming after a human-checkpoint pause from a prior worktree-isolated
   run, perform Protocol 91's checkpoint-resume worktree preflight before any
   mutation. Worktree re-entry is a CWD safety check only; it does not satisfy
   or waive checkpoint state.
   For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   items, run Protocol 91's residual gate before `ready-for-human-review`; block
   or escalate instead of reporting terminal when residual evidence is missing or
   incomplete.
8. For `spec/*` and `implementation-plan/*` PRs, run Protocol 91 Step 8a's
   documentation-stage alignment checker before readiness; correct or escalate
   mismatches instead of applying `ready-for-human-review`.
9. Epic-like targets must use `$run-epic` / `/run-epic`, not this command.
10. When the delegated merge gate returns `merge_allowed`, continue through merge,
   remote/local branch cleanup, `post-merge-cleanup.sh`, and live tracker
   verification before reporting the item terminal. Do not stop at
   `ready-for-human-review` in a delegated merge run.
   Treat merge authority explicitly: `merge_granted` means readiness is
   intermediate; `merge_denied` means the ready PR stops as
   `ready_human_merge` and no merge command is run. A merge-granted run that
   stops at readiness without a named blocker is `policy_inconsistent`.
11. Before reporting any terminal state, run
    `scripts/development-workflow/item-completion-self-check.sh` for the claimed
    state and include its `## Ground-Truth Completion Verification` section in
    the Work Item Runner Summary. Treat `discrepancy` and
    `unavailable_required` as non-terminal and re-enter the relevant Protocol 91
    gate.

> **Deprecated alias**: `$run-item-work` / `/run-item-work` resolves to the same
> behavior for legacy invocations.
