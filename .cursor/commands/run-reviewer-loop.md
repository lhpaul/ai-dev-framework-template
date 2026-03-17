---
description: Run the automated reviewer loop (and CI loop) for a PR until clean or escalate. Usage: /run-reviewer-loop [PR number or "current"]
---

# Cursor Command: Run Reviewer Loop

Follow the standalone automated reviewer loop protocol:

`docs/ai/development-workflow/protocols/92-automated-reviewer-loop-protocol.md`

- **Scope**: Run Step 7 (automated review) and Step 8 (CI) for the specified PR, dispatching fixer agents when the platform reports blocking issues, until the PR is ready for human review or escalated.
- **Target**: Use the PR number from the command if given; otherwise resolve the PR for the current branch (e.g. `gh pr view --json number --jq '.number'`).
- Use the helper scripts `scripts/development-workflow/pr-review-loop.sh` and `scripts/development-workflow/pr-ci-loop.sh`. Do **not** pass `--platform` unless you intend to override the repo config: the script reads `.ai-dev-workflow.yaml` and uses its `review_platforms` list when no `--platform` is given. Run Step 7 to completion before Step 8 (do not run in background).
- Apply labels per `docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md` when the loops are clean or when CI/feedback requires `agent:needs-fixes`.
