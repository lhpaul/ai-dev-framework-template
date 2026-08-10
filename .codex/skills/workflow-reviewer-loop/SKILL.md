---
name: workflow-reviewer-loop
description: Run the automated reviewer loop (and CI loop) for a PR. Use when the user wants to run the reviewer loop on a specific PR or the current branch's PR until it is ready for human review or escalated.
---

# Workflow Reviewer Loop

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
3. Determine the target PR from the user's request (PR number, current branch, or all open workflow PRs if specified).
4. Run Step 7 (automated review), Step 7b (regression label for implementation PRs), and Step 8 (CI) using the scripts in `scripts/development-workflow/`. Run Step 7 to completion before Step 7b and Step 8. Run `pr-review-loop.sh` and `pr-ci-loop.sh` in the foreground — see `91-orchestrate-work-protocol.md` Step 7/Step 8 for the mandatory "run in the foreground, never background-and-yield" rule; it applies here exactly as written there.
5. Dispatch the appropriate fixer agent when the loop returns `needs_fixes`; apply labels per `92-pr-readiness-signal-protocol.md` when clean or when escalating. For `spec/*` and `implementation-plan/*` PRs, route through Protocol 91 Step 8a so `check-documentation-stage-alignment.sh` runs before `ready-for-human-review`.
6. When `BATCH_CONTEXT=true`, pass the full Protocol 90 isolation assignment to any fixer handoff: resolved absolute worktree path, expected branch, artifact repo root, approved base branch, mutation classification, and `isolation: "worktree"`.
7. Track all blocking findings across cycles in an issue ledger. After each fixer push, post a fix commit comment listing resolved issues. When the loop terminates, post a final summary table on the PR using `gh pr comment`.
8. Keep repository routing thin: in `workflow_hub`, pass selected product repository context through to shared reviewer and CI scripts for product implementation PRs; hub-owned spec, plan, and workflow PRs continue to target the hub.
