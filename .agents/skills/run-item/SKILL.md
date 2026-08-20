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
   For substantial or multi-part mutating item work, commit immediately after
   each completed logical sub-part, do not intentionally batch all completed
   sub-parts into one end-of-run commit, and never commit incomplete, failing,
   or incoherent edits only to satisfy the requirement.
5. Before implementation mutation in `workflow_hub`, state selected product
   repository, artifact owner, and mutation target. Follow the canonical
   [implementation routing classifier](../../../docs/workflow/development-workflow/repository-modes.md#implementation-routing-classifier)
   contract for routing outcome, fingerprint, and stop evidence.
6. Before branch creation or PR creation for a tracker-backed item, run
   `run-nested-artifact-guard.sh --mode <pre-create|pre-pr> --issue <number>
   --expected-branch <branch> --approved-base <branch>
   --repo-root "$ARTIFACT_REPO_ROOT"` (optional `--expected-worktree` /
   `--allow-split`). Stop on `missing_base`, `blocked_duplicate`, `wrong_base`,
   or `scan_failed`; explicit split work requires parent approval and
   `--allow-split true`.
   Use a bare numeric workflow branch identifier such as
   feature/1858-safe-name, never feature/#1858-safe-name; the guard rejects
   unsafe names before creation or push.
7. After candidate discovery and a clean nested-artifact guard, run
   `validate-branch-reuse.sh` with the issue, exact expected branch, approved
   base, and artifact repo root. Only `compatible` may resume with
   `workflow-next-action.sh`; `no_existing_branch` follows the fresh path.
   Stop before mutation on `incompatible` or `verification_blocked`, report the
   evidence and human action, and never delete, reset, rebase, check out, or
   force-push the branch automatically. Tracking divergence is diagnostic only.
   If a published workflow PR branch update would require a destructive push,
   stop before mutation and route the exact operation through
   `scripts/development-workflow/workflow-branch-push-guard.sh`.
8. Before dispatching a Backlog item into Writing Spec, run or consume
   `scripts/development-workflow/spec-dispatch-context.sh`. For direct
   single-item runs, pass the selected item plus relevant in-scope Backlog peers
   from the current tracker scan in `--items`; a selected-only scope may collect
   decisions but cannot classify peer relationships. Pass non-blocking confirmed
   decisions and relationship outcomes to the spec writer; stop on
   `blocking=true` and report the helper's `humanAction`. Shared keywords alone
   are not dependency evidence.
9. **Guardrails enforcement**: Use portfolio-resolved guardrails from handoff when
   available; otherwise resolve from repo `guardrails` config. Report effective
   values before mutation. Enforce gates per
   `docs/workflow/development-workflow/guardrails-enforcement.md` section 3.
   When resuming after a human-checkpoint pause from a prior worktree-isolated
   run, invoke Protocol 91's `checkpoint-resume-gate.sh` with item, expected
   branch, expected worktree, main repo root, and checkpoint state before any
   mutation. Continue only on `RESULT=continue`; `RESULT=checkpoint_pending`
   and `RESULT=stop` are human-decision or unclear-requirements stops.
   Isolation verification never satisfies or waives checkpoint state, and a
   main-clone resume must stop instead of changing directories.
   For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   items, run Protocol 91's residual gate before `ready-for-human-review`; block
   or escalate instead of reporting terminal when residual evidence is missing or
   incomplete.
10. For `spec/*` and `implementation-plan/*` PRs, run Protocol 91 Step 8a's
   documentation-stage alignment checker before readiness; correct or escalate
   mismatches instead of applying `ready-for-human-review`.
11. Epic-like targets must use `$run-epic` / `/run-epic`, not this command.
12. When the delegated merge gate returns `merge_allowed`, continue through merge,
   remote/local branch cleanup, `post-merge-cleanup.sh`, and live tracker
   verification before reporting the item terminal. Do not stop at
   `ready-for-human-review` in a delegated merge run.
   When the gate returns `exceptional_bypass_authorized`, do not treat it as
   normal merge authority; follow the canonical exceptional-bypass policy in
   `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5, then
   verify and update the same audit marker.
   Treat merge authority explicitly: `merge_granted` means readiness is
   intermediate; `merge_denied` means the ready PR stops as
   `ready_human_merge` and no merge command is run. A merge-granted run that
   stops at readiness without a named blocker is `policy_inconsistent`.
13. Before reporting any terminal state, run
    `scripts/development-workflow/item-completion-self-check.sh` for the claimed
    state and include its `## Ground-Truth Completion Verification` section in
    the Work Item Runner Summary. When Step 7 was configured, pass
    `--require-review-summary true` and `--require-review-threads true` (helper
    defaults are false). Treat `discrepancy` and `unavailable_required` as
    non-terminal and re-enter the relevant Protocol 91 gate.

> **Deprecated alias**: `$run-item-work` / `/run-item-work` resolves to the same
> behavior for legacy invocations.
