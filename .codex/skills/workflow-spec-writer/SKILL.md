---
name: workflow-spec-writer
description: Write a feature spec for the AI development workflow. Use when a new feature needs to move from backlog into the spec stage.
---

# Workflow Spec Writer

Recommended model tier: `premium`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`.
3. Follow that protocol exactly.
4. Keep the spec product-focused; implementation details belong in the plan stage.
5. When `BATCH_CONTEXT=true`, complete the isolation self-check before the first file edit, branch-changing command, commit, push, PR mutation, or tracker mutation: verify `isolation: "worktree"`, expected worktree path, expected branch, artifact repo root, approved base branch, and mutation classification are present; compare only the expected worktree path to `pwd -P` and only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch; escalate if mutation may already have occurred outside the assigned worktree.
6. Before opening the draft spec PR, complete Protocol 01's Document Quality Gate and include the gate log in the PR description. For tracker-backed briefs, include the mandatory Brief Objective List, Coverage Matrix, and PR-visible Deferral Notes as part of that gate.
7. Before opening the draft spec PR, call `ensure_on_project_board <issue_number> "Writing Spec"` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board.
8. Before creating the spec branch or opening the spec PR for a tracker-backed item, run `run-nested-artifact-guard.sh` with the expected `spec/*` branch and approved artifact base. Stop on missing base, duplicate artifacts, wrong-base PRs, or scan failures.
9. When the branch is created, continue through reviewer gate, PR creation, and PR readiness unless the protocol surfaces a real human decision.
10. Resolve repository mode, artifact owner, and artifact base branch before
   writing: `single_repo` uses the current repository; `workflow_hub` keeps specs
   and spec PRs hub-owned on the hub artifact base branch, even when the
   product implementation base is different; `product_repo` should report the
   configured hub owner or stop if ownership is ambiguous.
