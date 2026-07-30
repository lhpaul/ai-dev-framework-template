---
name: workflow-implementer
description: Implement a workflow item in code. Use for full-pipeline implementation, refactors (plan only, no spec), fast-track fixes, or hotfixes using the repository's implementation protocol.
---

# Workflow Implementer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
3. Follow that protocol exactly.
4. For full-pipeline work, read the spec and plan first. For refactors, read the plan first (no spec). For plan-backed work, read the plan's `Cross-Cutting Operational Assumption Check` before file edits; re-read every applicable authoritative source and record `Still valid` in implementation-start notes before implementation, then cite that evidence in the Pre-Submission Self-Review Pass before handoff, or stop before mutation with `Stale or conflicting` evidence for the parent orchestrator. For fast-track work, require the Protocol 91 Fast Track blast-radius gate and Protocol 03 criteria to have passed before implementation; stop if scope expands, high call-site volume appears, or external-system impact is discovered after dispatch. For hotfixes, branch from `main`. For UI-facing work, discover design assets per `docs/workflow/development-workflow/design-assets.md` and use them as visual references; do not invent assets when none exist.
5. Before writing or editing any repository file, verify you are on the intended workflow branch or inside the item worktree. If the checkout is on `develop` or `main`, create the feature/fix/refactor/hotfix branch or worktree before the first edit; do not start in the shared checkout and move changes later.
6. For substantial or multi-part mutating implementation work, commit
   immediately after each completed logical sub-part, do not intentionally batch
   all completed sub-parts into one end-of-run commit, and never commit
   incomplete, failing, or incoherent edits only to satisfy the requirement.
7. Continue through code review, PR creation, automated review, and CI readiness before returning unless the protocol surfaces a real human decision.
8. For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   work, produce and verify residual evidence with
   `scope-residual-gate.sh` before readiness.
9. Implementation files belong on implementation branches, not `spec/*` or `implementation-plan/*` branches. If a documentation-stage PR is in scope, run Protocol 91 Step 8a's documentation-stage alignment checker before readiness and correct or escalate any mismatch.
10. Before opening the draft implementation PR, complete the Protocol 03
    **Pre-Submission Self-Review Pass**: review
    `git diff <base-branch>...HEAD`, remove stale markers, verify
    sibling/caller consistency, confirm spec/plan or issue-body coverage,
    include the complex workflow decision-gate matrix or not-applicable
    rationale when Protocol 03 requires it, and add the self-review log to the
    PR description.
11. Before opening the draft implementation PR, verify the PR has a linked tracker item through the branch name, handoff metadata, or a closing/reference keyword in the PR body. If ad-hoc work has no item, create or accept a retroactive backlog item first and reference it in the PR description.
12. Before opening the draft implementation PR, call `ensure_on_project_board <issue_number> "In Development"` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board.
13. Before creating an implementation branch or opening an implementation PR for a tracker-backed item, run `run-nested-artifact-guard.sh` with required `--mode`, `--issue`, `--expected-branch`, `--approved-base`, plus the expected workflow branch, parent-approved base, and artifact-owning repo root (`--repo-root "$ARTIFACT_REPO_ROOT"`). In `workflow_hub`, product implementation artifacts scan the selected product checkout, not the hub. Stop on missing base, duplicate artifacts, wrong-base PRs, or scan failures; deliberate splits require explicit parent approval.
    Use a bare numeric workflow branch identifier such as
    feature/1858-safe-name, never feature/#1858-safe-name; the guard rejects
    unsafe names before creation or push.
14. **BATCH_CONTEXT branch-skip rule**: When the handoff metadata includes `BATCH_CONTEXT=true`, the item-orchestrator already created the worktree on the correct branch. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Before the first file edit, branch-changing command, commit, push, PR mutation, or tracker mutation, complete the isolation self-check: verify `isolation: "worktree"`, the expected worktree path, expected branch, artifact repo root, approved base branch, and mutation classification are present; ensure `pwd -P` equals the expected worktree path or begins with the expected worktree path followed by `/` and compare only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch; escalate for human inspection if mutation may already have occurred outside the assigned worktree. All `Edit`/`Write` tool calls must target paths under the resolved `<worktree-path>`.
15. **Main-tree return rule (BATCH_CONTEXT=false / no worktree isolation)**: When dispatched WITHOUT worktree isolation (`BATCH_CONTEXT` is `false` or absent), this skill runs in the main working tree. **Before returning to the caller on any terminal path (ready, blocked, or escalated)**, switch the main working tree back to the integration branch (`git switch develop`, or whichever branch `integration_branch` specifies in `.ai-dev-workflow.yaml`). Verify with `git rev-parse --abbrev-ref HEAD`. If uncommitted changes block the switch, commit or stash first — do NOT force-discard. Omitting this return step causes Protocol 90 Step 5.2 to fire "wrong branch + clean" auto-correct on every subsequent item.
16. Before file edits, branch creation, commits, or implementation PR creation, resolve and state workflow mode, artifact owner, selected product repository, local path or remote identity, and mutation target. In `workflow_hub`, product implementation work mutates the selected product repository, not the hub; stop before mutation if context is missing or ambiguous.
17. When returning a standalone implementation completion handoff, use Protocol
    91's Work Item Runner Summary path and include the
    `item-completion-self-check.sh` `Ground-Truth Completion Verification`
    section before claiming ready, blocked, escalated, or waiting-on-human
    state. When Step 7 was configured, pass `--require-review-summary true` and
    `--require-review-threads true` (helper defaults are false).
