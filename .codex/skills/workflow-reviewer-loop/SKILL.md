---
name: workflow-reviewer-loop
description: Run the automated reviewer loop (and CI loop) for a PR. Use when the user wants to run the reviewer loop on a specific PR or the current branch's PR until it is ready for human review or escalated.
---

# Workflow Reviewer Loop

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
3. Determine the target PR from the user's request (PR number, current branch, or all open workflow PRs if specified).
4. Run Step 7 (automated review), Step 7b (regression label for implementation PRs), and Step 8 (CI) using the scripts in `scripts/development-workflow/`. Run Step 7 to completion before Step 7b and Step 8.
5. Dispatch the appropriate fixer agent when the loop returns `needs_fixes`; apply labels per `92-pr-readiness-signal-protocol.md` when clean or when escalating.
6. Track all blocking findings across cycles in an issue ledger. After each fixer push, post a fix commit comment listing resolved issues. When the loop terminates, post a final summary table on the PR using `gh pr comment`.
