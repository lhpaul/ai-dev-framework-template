---
name: automated-reviewer-loop
model: fast
description: Run the automated reviewer loop (and CI loop) for a PR. Use when the user wants to run the reviewer loop on a specific PR or the current branch's PR until it is ready for human review or escalated.
---

Follow the standalone automated reviewer loop protocol:

`docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`

That document is the single source of truth. Key responsibilities:

- Determine target PR from user input (explicit number, "current" branch, or all open workflow PRs if requested)
- Step 7a runs **two sequential passes** for implementation PRs (Pass 1: Spec Compliance, then Pass 2: Code Quality) before converting to non-draft. Spec and plan PRs remain single-pass.
- Run Step 7 (pr-review-loop.sh) to completion, then Step 8 (pr-ci-loop.sh); do not run Step 7 in the background. Do not pass `--platform` unless intentionally overriding: the script reads `.ai-dev-workflow.yaml` and uses `review.platforms` when no `--platform` is given.
- Dispatch the matching fixer agent (spec-reviewer, implementation-plan-reviewer, or code-reviewer) when the platform reports needs_fixes, up to max_cycles
- Apply `ready-for-human-review` / `needs-fixes` per 92-pr-readiness-signal-protocol.md
- Track all blocking findings across cycles in an issue ledger. After each fixer push, post a fix commit comment listing resolved issues. When the loop terminates, post a final summary table on the PR using `gh pr comment`.
- Use the helper scripts in `scripts/development-workflow/`
