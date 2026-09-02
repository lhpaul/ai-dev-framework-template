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
5. When `BATCH_CONTEXT=true`, complete the isolation self-check before the first file edit, branch-changing command, commit, push, PR mutation, or tracker mutation: verify `isolation: "worktree"`, expected worktree path, expected branch, artifact repo root, approved base branch, and mutation classification are present; ensure `pwd -P` equals the expected worktree path or begins with the expected worktree path followed by `/` and compare only the expected branch to `git rev-parse --abbrev-ref HEAD`. Stop before mutation on missing metadata, wrong CWD, main-repo CWD, or wrong branch; escalate if mutation may already have occurred outside the assigned worktree.
6. If invoked from an automated reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required. Use follow-up commits on published PR branches; if a destructive branch update would be required, stop before mutation and route the exact push through `scripts/development-workflow/workflow-branch-push-guard.sh`; in `workflow_hub`, resolve the helper from `WORKFLOW_TOOL_ROOT` and pass the pushed checkout as `--repo-root "$ARTIFACT_REPO_ROOT"`.
7. When dispatched for a specific pass (Pass 1: Spec Compliance or Pass 2: Code Quality), restrict evaluation to the corresponding `REVIEW.md` sub-checklist. The pass name is provided in the dispatch prompt by the orchestrating skill.
8. When the change under review touches workflow-policy surfaces — `REVIEW.md`, the root agent instruction files, `.ai-dev-workflow.yaml`, `docs/workflow/**`, `docs/best-practices/**`, `scripts/development-workflow/**`, or the per-tool instruction trees `.claude/**`, `.cursor/**`, `.codex/**` and `.agents/**` — also evaluate the `## Workflow Policy Review Checklist`, in addition to the dispatched pass.
9. Resolve and report the implementation artifact owner before reviewing. In `workflow_hub`, product implementation PRs are reviewed in the selected product repository while hub-only workflow PRs remain hub-owned.
