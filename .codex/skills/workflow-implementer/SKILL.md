---
name: workflow-implementer
description: Implement a workflow item in code. Use for full-pipeline implementation, refactors (plan only, no spec), fast-track fixes, or hotfixes using the repository's implementation protocol.
---

# Workflow Implementer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
3. Follow that protocol exactly.
4. For full-pipeline work, read the spec and plan first. For refactors, read the plan first (no spec). For fast-track work, stop if scope expands. For hotfixes, branch from `main`.
5. Before writing or editing any repository file, verify you are on the intended workflow branch or inside the item worktree. If the checkout is on `develop` or `main`, create the feature/fix/refactor/hotfix branch or worktree before the first edit; do not start in the shared checkout and move changes later.
6. Continue through code review, PR creation, automated review, and CI readiness before returning unless the protocol surfaces a real human decision.
7. For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   work, produce and verify residual evidence with
   `scope-residual-gate.sh` before readiness.
8. Before opening the draft implementation PR, complete the Protocol 03 **Pre-Submission Self-Review Pass**: review `git diff <base-branch>...HEAD`, remove stale markers, verify sibling/caller consistency, confirm spec/plan or issue-body coverage, and add the self-review log to the PR description.
9. Before opening the draft implementation PR, verify the PR has a linked tracker item through the branch name, handoff metadata, or a closing/reference keyword in the PR body. If ad-hoc work has no item, create or accept a retroactive backlog item first and reference it in the PR description.
10. Before opening the draft implementation PR, call `ensure_on_project_board <issue_number> "In Development"` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board.
11. Before creating an implementation branch or opening an implementation PR for a tracker-backed item, run `run-nested-artifact-guard.sh` with the expected workflow branch, parent-approved base, and artifact-owning repo root (`--repo-root "$ARTIFACT_REPO_ROOT"`). In `workflow_hub`, product implementation artifacts scan the selected product checkout, not the hub. Stop on missing base, duplicate artifacts, wrong-base PRs, or scan failures; deliberate splits require explicit parent approval.
12. **BATCH_CONTEXT branch-skip rule**: When the handoff metadata includes `BATCH_CONTEXT=true`, the item-orchestrator already created the worktree on the correct branch. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Verify CWD matches the `<worktree-path>` provided in the handoff before any git state-changing command. All `Edit`/`Write` tool calls must target paths under the resolved `<worktree-path>`.
13. **Main-tree return rule (BATCH_CONTEXT=false / no worktree isolation)**: When dispatched WITHOUT worktree isolation (`BATCH_CONTEXT` is `false` or absent), this skill runs in the main working tree. **Before returning to the caller on any terminal path (ready, blocked, or escalated)**, switch the main working tree back to the integration branch (`git switch develop`, or whichever branch `integration_branch` specifies in `.ai-dev-workflow.yaml`). Verify with `git rev-parse --abbrev-ref HEAD`. If uncommitted changes block the switch, commit or stash first — do NOT force-discard. Omitting this return step causes Protocol 90 Step 5.2 to fire "wrong branch + clean" auto-correct on every subsequent item.
14. Before file edits, branch creation, commits, or implementation PR creation, resolve and state workflow mode, artifact owner, selected product repository, local path or remote identity, and mutation target. In `workflow_hub`, product implementation work mutates the selected product repository, not the hub; stop before mutation if context is missing or ambiguous.
