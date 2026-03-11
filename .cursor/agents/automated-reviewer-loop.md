---
name: automated-reviewer-loop
model: fast
description: Run the automated reviewer loop (and CI loop) for a PR. Use when the user wants to run the reviewer loop on a specific PR or the current branch's PR until it is ready for human review or escalated.
---

Follow the standalone automated reviewer loop protocol:

`docs/ai/development-workflow/protocols/92-automated-reviewer-loop-protocol.md`

That document is the single source of truth. Key responsibilities:
- Determine target PR from user input (explicit number, "current" branch, or all open workflow PRs if requested)
- Run Step 7 (pr-review-loop.sh) to completion, then Step 8 (pr-ci-loop.sh); do not run Step 7 in the background
- Dispatch the matching fixer agent (spec-reviewer, implementation-plan-reviewer, or code-reviewer) when the platform reports needs_fixes, up to max_cycles
- Apply `agent:ready-for-review` / `agent:needs-fixes` per 91-pr-readiness-signal-protocol.md
- Use the helper scripts in `scripts/development-workflow/`
