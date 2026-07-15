---
name: workflow-code-reviewer
description: Review implemented changes against the repository's code review workflow. Use when a feature, refactor, fix, or hotfix PR needs review or reviewer feedback needs to be addressed.
---

# Workflow Code Reviewer

Recommended model tier: `balanced`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/03-review-implementation-protocol.md`.
3. Follow that protocol exactly.
4. Keep findings first, ordered by severity, with concrete file references.
5. When `BATCH_CONTEXT=true`, complete the isolation self-check before the first file edit, branch-changing command, commit, push, PR mutation, or tracker mutation: verify `isolation: "worktree"`, expected worktree path, expected branch, artifact repo root, approved base branch, and mutation classification are present; ensure `pwd -P` equals or is nested under the expected worktree path and compare only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch; escalate if mutation may already have occurred outside the assigned worktree.
6. If invoked from an automated reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.
7. When dispatched for a specific pass (Pass 1: Spec Compliance or Pass 2: Code Quality), restrict evaluation to the corresponding `REVIEW.md` sub-checklist. The pass name is provided in the dispatch prompt by the orchestrating skill.
8. Resolve and report the implementation artifact owner before reviewing. In `workflow_hub`, product implementation PRs are reviewed in the selected product repository while hub-only workflow PRs remain hub-owned.
