---
name: workflow-item-orchestrator
description: Advance a single workflow item until it reaches a real terminal condition. Use when the user wants Codex to resume or advance one specific development, branch, or PR without scanning the whole portfolio.
---

# Workflow Item Orchestrator

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and terminal-condition expectations.
2. Unless handoff metadata includes `BATCH_CONTEXT=true`, run the read-only
   bounded prelude before mutation:
   `./scripts/development-workflow/run-bounded-prelude.sh --original-command "<invocation>" <scope flags> --json`
   See `docs/workflow/development-workflow/bounded-run-prelude.md`. Print
   `policyRecommendation.confirmationSummary`, including effective policy, field
   sources, pending checkpoint guidance, copy-paste equivalent, and the read-only
   guarantee. If all autonomy flags (`--delegate-review`, `--may-merge`,
   `--may-start-backlog`, `--max-risk`) were provided explicitly in the
   invocation, those explicit flags serve as human confirmation — proceed
   immediately after printing the summary and recording the invocation-scoped
   `RUN_ITEM_POLICY_CONFIRMED` item/policy binding. Otherwise (any flag was
   inferred, scope is ambiguous, or pending checkpoints remain), stop for human
   acceptance, checkpoint input, or customization before continuing. When
   `BATCH_CONTEXT=true`, skip this per-item prelude, summary printing, and
   `RUN_ITEM_POLICY_CONFIRMED` binding; portfolio batch approval in Protocol 90
   covers the confirmation gate.
3. Read `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
4. Prefer the helper scripts in `scripts/development-workflow/` for next-action classification, resume behavior, CI polling, and automated review polling before using ad hoc shell commands.
5. Treat the protocol as canonical. Use the matching workflow skill for the next stage when your runner supports skill-to-skill handoff; otherwise continue in the current session by following the referenced stage protocol directly.
6. Stay scoped to one workflow item. If the request is portfolio-wide, route back to `workflow-orchestrator`.
7. **Checkpoint-resume worktree preflight**: When resuming after a human-checkpoint pause from a prior worktree-isolated run, run Protocol 91's `worktree-resume-preflight.sh` before any mutation. Continue only from the expected worktree, or stop with the helper's recovery fields. Worktree re-entry does not satisfy or waive checkpoint state.
8. **Pre-mutation isolation self-check (BATCH_CONTEXT=true only)**: Before the first file edit, branch-changing command, commit, push, PR mutation, tracker mutation, or stage-agent handoff, verify the handoff's expected worktree path, expected branch, artifact repo root, mutation classification, and `isolation: "worktree"` against `pwd -P` and `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch. If mutation may already have occurred outside the assigned worktree, escalate for human inspection instead of resetting, restoring, stashing, committing, or deleting suspect changes.
9. **Stage-agent handoff branch-skip requirement (BATCH_CONTEXT=true only)**: When `BATCH_CONTEXT=true`, every stage-agent handoff must include: (a) the literal resolved `<worktree-path>` value, and (b) the explicit instruction "BATCH_CONTEXT=true — do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm CWD matches `<worktree-path>` before any git state-changing command." Omitting either instruction causes the stage subagent to run Protocol 03's branching steps from the main repo root, leaking a branch-switch into the main working tree.
10. **Main-tree return rule (BATCH_CONTEXT=false / no worktree isolation)**: When dispatched WITHOUT worktree isolation (`BATCH_CONTEXT` is `false` or absent), this skill runs in the main working tree. Before emitting the Work Item Runner Summary and returning, switch the main working tree back to the integration branch (`git switch develop`, or whichever branch `integration_branch` specifies in `.ai-dev-workflow.yaml`). Verify with `git rev-parse --abbrev-ref HEAD`. If uncommitted changes block the switch, commit or stash first. Omitting this return step causes Protocol 90 Step 5.2 to fire "wrong branch + clean" auto-correct on every subsequent item.
11. Before implementation mutation in `workflow_hub`, state the selected product repository, local path or remote identity, artifact owner, and mutation target. Stop before file edits, branch creation, commits, or implementation PR creation when product repository context is missing or ambiguous. Specs and plans remain hub-owned unless a later protocol says otherwise.
12. Before dispatching a stage path that may create a branch or open a PR, pass the expected branch, expected worktree when known, approved base, and artifact-owning repo root. Run `run-nested-artifact-guard.sh --repo-root "$ARTIFACT_REPO_ROOT"` before mutation and stop on `missing_base`, `blocked_duplicate`, `wrong_base`, or `scan_failed`.
13. **Guardrails enforcement**: At item-run start, use portfolio-resolved guardrails from handoff metadata when available; otherwise resolve from repo `guardrails` config. Report effective values before mutation. Enforce per-stage PR-open, delegated review, delegated merge, and completion gates per `docs/workflow/development-workflow/guardrails-enforcement.md` section 3. When no `guardrails` section is found, apply conservative defaults and state them. When the delegated merge gate returns `merge_allowed`, continue through merge, branch cleanup, `post-merge-cleanup.sh`, and live tracker verification before reporting the item terminal.
14. For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
    items, run `scope-residual-gate.sh` before readiness and treat `block` or
    `escalate` as non-terminal.
15. Before any terminal Work Item Runner Summary (`ready`, `done`, `blocked`,
    `escalated`, waiting on human, waiting on merge, or cleanup complete), run
    `scripts/development-workflow/item-completion-self-check.sh` for the claimed
    state and paste its `## Ground-Truth Completion Verification` section into
    the summary. A `discrepancy` or `unavailable_required` result is
    non-terminal; return to the matching Protocol 91 gate instead of reporting
    success.
