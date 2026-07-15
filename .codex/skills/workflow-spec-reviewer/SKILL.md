---
name: workflow-spec-reviewer
description: Review and refine a workflow spec. Use when a spec draft or spec PR needs review against the repository's spec review protocol.
---

# Workflow Spec Reviewer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/01-review-spec-protocol.md`.
3. Follow that protocol exactly.
4. Treat the protocol as the checklist; keep review findings concrete and scoped to the spec.
5. When `BATCH_CONTEXT=true`, complete the isolation self-check before the first file edit, branch-changing command, commit, push, PR mutation, or tracker mutation: verify `isolation: "worktree"`, expected worktree path, expected branch, artifact repo root, approved base branch, and mutation classification are present; ensure `pwd -P` equals or is nested under the expected worktree path and compare only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch; escalate if mutation may already have occurred outside the assigned worktree.
6. If invoked from an automated reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.
7. Resolve and report the artifact repository owner before reviewing. Specs are hub-owned in `workflow_hub` mode unless a future protocol explicitly changes that.
