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
5. When the handoff includes output from
   `scripts/development-workflow/spec-dispatch-context.sh`, read it before the
   alignment conversation. Preserve confirmed decisions and non-blocking
   relationship outcomes as product constraints. Do not turn helper mechanics,
   token matching, JSON fields, or implementation algorithms into spec
   requirements. If context is `blocking=true` or `Unclear`, stop for the named
   human relationship decision.
6. When `BATCH_CONTEXT=true`, complete the isolation self-check before the first file edit, branch-changing command, commit, push, PR mutation, or tracker mutation: verify `isolation: "worktree"`, expected worktree path, expected branch, artifact repo root, approved base branch, and mutation classification are present; ensure `pwd -P` equals the expected worktree path or begins with the expected worktree path followed by `/` and compare only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch; escalate if mutation may already have occurred outside the assigned worktree.
7. For substantial or multi-part mutating spec work, commit immediately after
   each completed logical sub-part, do not intentionally batch all completed
   sub-parts into one end-of-run commit, and never commit incomplete, failing,
   or incoherent edits only to satisfy the requirement.
8. Use follow-up commits for published spec PR branches. If a destructive
   branch update would be required, stop before mutation and route the exact
   push through `scripts/development-workflow/workflow-branch-push-guard.sh`.
   In `workflow_hub`, resolve the helper from `WORKFLOW_TOOL_ROOT` and pass the
   pushed checkout as `--repo-root "$ARTIFACT_REPO_ROOT"`.
9. Before opening the draft spec PR, complete Protocol 01's Document Quality
   Gate and include the gate log in the PR description. For tracker-backed
   briefs, include the mandatory Brief Objective List, Coverage Matrix, and
   PR-visible Deferral Notes as part of that gate. For complex workflow
   decision-gate specs, include Protocol 01's consistency matrix or
   not-applicable rationale.
9. Before opening the draft spec PR, call `ensure_on_project_board <issue_number> "Writing Spec"` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board.
10. Before creating the spec branch or opening the spec PR for a tracker-backed item, run `run-nested-artifact-guard.sh` with required `--mode`, `--issue`, `--expected-branch`, `--approved-base`, plus the expected `spec/*` branch and approved artifact base. Stop on missing base, duplicate artifacts, wrong-base PRs, or scan failures.
11. When creating the development folder, discover design assets per
    `docs/workflow/development-workflow/design-assets.md`. If confirmed tracker
    design assets exist, copy or download them into `<dev-folder>/assets/` and
    update the issue-body location note. Do not invent assets when none exist.
12. When the branch is created, continue through reviewer gate, PR creation, and PR readiness unless the protocol surfaces a real human decision.
13. Resolve repository mode, artifact owner, and artifact base branch before
   writing: `single_repo` uses the current repository; `workflow_hub` keeps specs
   and spec PRs hub-owned on the hub artifact base branch, even when the
   product implementation base is different; `product_repo` should report the
   configured hub owner or stop if ownership is ambiguous.
