---
name: workflow-item-orchestrator
description: Advance a single workflow item until it reaches a real terminal condition. Use when the user wants Codex to resume or advance one specific development, branch, or PR without scanning the whole portfolio.
---

# Workflow Item Orchestrator

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and terminal-condition expectations.
2. Run the read-only bounded prelude before mutation unless handoff metadata includes
   `BATCH_CONTEXT=true` (portfolio batch dispatch — skip prelude per Protocol 91):
   `./scripts/development-workflow/run-bounded-prelude.sh --original-command "<invocation>" <scope flags> --json`
   See `docs/workflow/development-workflow/bounded-run-prelude.md`. When
   `policyRecommendation.requiresConfirmation` is true, stop for human acceptance
   or customization before continuing.
3. Read `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
4. Prefer the helper scripts in `scripts/development-workflow/` for next-action classification, resume behavior, CI polling, and automated review polling before using ad hoc shell commands.
5. Treat the protocol as canonical. Use the matching workflow skill for the next stage when your runner supports skill-to-skill handoff; otherwise continue in the current session by following the referenced stage protocol directly.
6. Stay scoped to one workflow item. If the request is portfolio-wide, route back to `workflow-orchestrator`.
7. **Stage-agent handoff branch-skip requirement (BATCH_CONTEXT=true only)**: When `BATCH_CONTEXT=true`, every stage-agent handoff must include: (a) the literal resolved `<worktree-path>` value, and (b) the explicit instruction "BATCH_CONTEXT=true — do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm CWD matches `<worktree-path>` before any git state-changing command." Omitting either instruction causes the stage subagent to run Protocol 03's branching steps from the main repo root, leaking a branch-switch into the main working tree.
8. **Main-tree return rule (BATCH_CONTEXT=false / no worktree isolation)**: When dispatched WITHOUT worktree isolation (`BATCH_CONTEXT` is `false` or absent), this skill runs in the main working tree. Before emitting the Work Item Runner Summary and returning, switch the main working tree back to the integration branch (`git switch develop`, or whichever branch `integration_branch` specifies in `.ai-dev-workflow.yaml`). Verify with `git rev-parse --abbrev-ref HEAD`. If uncommitted changes block the switch, commit or stash first. Omitting this return step causes Protocol 90 Step 5.2 to fire "wrong branch + clean" auto-correct on every subsequent item.
9. Before implementation mutation in `workflow_hub`, state the selected product repository, local path or remote identity, artifact owner, and mutation target. Stop before file edits, branch creation, commits, or implementation PR creation when product repository context is missing or ambiguous. Specs and plans remain hub-owned unless a later protocol says otherwise.
10. **Guardrails enforcement**: At item-run start, use portfolio-resolved guardrails from handoff metadata when available; otherwise resolve from repo `guardrails` config. Report effective values before mutation. Enforce per-stage PR-open, delegated review, delegated merge, and completion gates per `docs/workflow/development-workflow/guardrails-enforcement.md` section 3. When no `guardrails` section is found, apply conservative defaults and state them.
