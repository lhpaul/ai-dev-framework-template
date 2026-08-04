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
7. **Checkpoint-resume gate**: When resuming after a human-checkpoint pause from a prior worktree-isolated run, run Protocol 91's `checkpoint-resume-gate.sh` before any mutation with explicit item, expected branch, expected worktree, main repo root, and checkpoint state. Continue only on `RESULT=continue`; stop on `RESULT=checkpoint_pending` or `RESULT=stop` and report the gate's recovery fields. Isolation verification does not satisfy or waive checkpoint state, and a main-clone resume must not change directories.
8. **Pre-mutation isolation self-check (BATCH_CONTEXT=true only)**: Before the first file edit, branch-changing command, commit, push, PR mutation, tracker mutation, or stage-agent handoff, verify the handoff's expected worktree path, expected branch, artifact repo root, mutation classification, and `isolation: "worktree"` are present; ensure `pwd -P` equals the expected worktree path or begins with the expected worktree path followed by `/` and compare only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch. If mutation may already have occurred outside the assigned worktree, escalate for human inspection instead of resetting, restoring, stashing, committing, or deleting suspect changes.
9. **Stage-agent handoff branch-skip requirement (BATCH_CONTEXT=true only)**: When `BATCH_CONTEXT=true`, every stage-agent handoff must include: (a) the literal resolved `<worktree-path>` value, (b) expected branch, artifact repo root, approved base branch, mutation classification, and `isolation: "worktree"` when the stage agent may mutate artifacts, (c) the explicit instruction "BATCH_CONTEXT=true — do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm `pwd -P` equals `<worktree-path>` or begins with `<worktree-path>/` before any git state-changing command.", and (d) the checkpoint instruction "For substantial or multi-part mutating item work, commit each completed logical sub-part as soon as it is coherent so agent death or compaction can resume from a recoverable checkpoint. Do not intentionally batch all completed sub-parts into one end-of-run commit. Single-step work with no meaningful completed intermediate checkpoint may use one final commit. Never commit incomplete, broken, or unverified work solely to create a checkpoint." Omitting required metadata or instructions causes the stage subagent to run Protocol 03's branching steps from the main repo root, leaking a branch-switch into the main working tree.
10. For substantial or multi-part mutating stage work, instruct the stage agent
    to commit immediately after each completed logical sub-part, avoid batching
    all completed sub-parts into one end-of-run commit, and never commit
    incomplete, failing, or incoherent edits only to satisfy this requirement.
11. **Main-tree return rule (BATCH_CONTEXT=false / no worktree isolation)**: When dispatched WITHOUT worktree isolation (`BATCH_CONTEXT` is `false` or absent), this skill runs in the main working tree. Before emitting the Work Item Runner Summary and returning, switch the main working tree back to the integration branch (`git switch develop`, or whichever branch `integration_branch` specifies in `.ai-dev-workflow.yaml`). Verify with `git rev-parse --abbrev-ref HEAD`. If uncommitted changes block the switch, commit or stash first. Omitting this return step causes Protocol 90 Step 5.2 to fire "wrong branch + clean" auto-correct on every subsequent item.
12. Before implementation mutation in `workflow_hub`, state the selected product repository, local path or remote identity, artifact owner, and mutation target. Stop before file edits, branch creation, commits, or implementation PR creation when product repository context is missing or ambiguous. Specs and plans remain hub-owned unless a later protocol says otherwise.
13. Before dispatching a stage path that may create a branch or open a PR, pass the expected branch, expected worktree when known, approved base, and artifact-owning repo root. Run `run-nested-artifact-guard.sh --mode <pre-create|pre-pr> --issue <number> --expected-branch <branch> --approved-base <branch> --repo-root "$ARTIFACT_REPO_ROOT"` before mutation and stop on `missing_base`, `blocked_duplicate`, `wrong_base`, or `scan_failed`.
14. After candidate discovery and a clean nested-artifact guard, run `validate-branch-reuse.sh` with the issue, exact expected branch, approved base, and artifact repo root. A matching item number is not sufficient: only `compatible` may resume through `workflow-next-action.sh`, while `no_existing_branch` follows the fresh path. Stop before mutation on `incompatible` or `verification_blocked`, report their distinct evidence and human action, and never delete, reset, rebase, check out, or force-push the branch automatically. Treat tracking divergence as diagnostic only. If a published workflow PR branch update would require a destructive push, stop before mutation and route the exact operation through `scripts/development-workflow/workflow-branch-push-guard.sh`; in `workflow_hub`, resolve the helper from `WORKFLOW_TOOL_ROOT` and pass the pushed checkout as `--repo-root "$ARTIFACT_REPO_ROOT"`.
15. For any plan-writing handoff, pass the exact current invocation item list
    (the single item for `/run-item`, or the current-batch item list for
    `/run-items`) and same-surface open PR evidence to the planner for the
    `Cross-Cutting Operational Assumption Check`. If the planner returns
    `Conflict` evidence, stop plan-stage advancement with `unclear_requirements`
    until the parent records `Resolved` or a human decision. When advancing a
    `Plan Ready` item into implementation, hand
    applicable plan assumption records to the implementer and require
    `Still valid` evidence before file edits.
16. Before dispatching a Backlog item into Writing Spec, run or consume
    `scripts/development-workflow/spec-dispatch-context.sh`. For direct
    single-item runs, pass the selected item plus relevant in-scope Backlog peers
    from the current tracker scan in `--items`; a selected-only scope may collect
    decisions but cannot classify peer relationships. Pass non-blocking confirmed
    decisions and relationship outcomes to the spec writer; stop on
    `blocking=true` and report the helper's `humanAction`. Shared keywords alone
    are not dependency evidence.
17. **Guardrails enforcement**: At item-run start, use portfolio-resolved guardrails from handoff metadata when available; otherwise resolve from repo `guardrails` config. Report effective values before mutation. Enforce per-stage PR-open, delegated review, delegated merge, and completion gates per `docs/workflow/development-workflow/guardrails-enforcement.md` section 3. When no `guardrails` section is found, apply conservative defaults and state them. When the delegated merge gate returns `merge_allowed`, continue through merge, branch cleanup, `post-merge-cleanup.sh`, and live tracker verification before reporting the item terminal. When the gate returns `exceptional_bypass_authorized`, require separate named PR/SHA/fingerprint authorization and a pre-attempt `reviewer-access-bypass` audit marker before one exact human-authorized `gh pr merge <pr> --admin --match-head-commit <authorized-head-sha>` attempt; delegated merge policy is not enough. Treat merge authority explicitly: `merge_granted` means readiness is intermediate; `merge_denied` means the ready PR stops as `ready_human_merge` and no merge command is run. A merge-granted run that stops at readiness without a named blocker is `policy_inconsistent`.
18. For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
    items, run `scope-residual-gate.sh` before readiness and treat `block` or
    `escalate` as non-terminal.
19. For `spec/*` and `implementation-plan/*` PRs, run Protocol 91 Step 8a's
    documentation-stage alignment checker before readiness. Include the
    alignment result in the runner summary when readiness is blocked; correct
    or escalate mismatches instead of applying `ready-for-human-review`.
20. Before any terminal Work Item Runner Summary (`ready`, `done`, `blocked`,
    `escalated`, waiting on human, waiting on merge, or cleanup complete), run
    `scripts/development-workflow/item-completion-self-check.sh` for the claimed
    state and paste its `## Ground-Truth Completion Verification` section into
    the summary. When Step 7 was configured, pass `--require-review-summary true`
    and `--require-review-threads true` (helper defaults are false). A
    `discrepancy` or `unavailable_required` result is non-terminal; return to the
    matching Protocol 91 gate instead of reporting success.
