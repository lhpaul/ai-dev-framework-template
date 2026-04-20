---
name: workflow-retrospective
description: Run a retrospective analysis on completed work to identify process improvement opportunities. Use when the user wants to review a completed batch or item run, or invoke on-demand with a PR number, branch, or date as scope hint.
---

# Workflow Retrospective

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/ai/development-workflow/protocols/06-retrospective-protocol.md`.
3. Resolve scope from the user's request (PR number, branch name, batch date) or default to recent PRs in the repository.
4. Gather GitHub PR metadata (review cycles, finding types, labels, merge conflicts) and git history (commit patterns, fix-commit ratio) using `gh`. When conversation context is available, also analyze manual interventions, human corrections, and agent deviations from the current session.
5. Synthesize findings into a categorized list using the fixed taxonomy and severity signals defined in the protocol.
6. Present findings to the human. For each opportunity, accept the human's choice of "Address now", "Add to backlog", or "Skip" — then execute the chosen action.
7. "Address now": apply simple fix on a `fix/[slug]` branch, open a PR to `develop`, and proceed through normal review/CI gates — do not push directly to shared branches. "Add to backlog": create GitHub issue directly via `gh issue create`. "Skip": move on.
8. After all opportunities are acted on, post a confirmation summary table.
