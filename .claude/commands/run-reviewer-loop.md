---
description: Run the automated reviewer loop (and CI loop) for a PR until clean or escalate. Usage: /run-reviewer-loop [PR number or "current"]
---

# Claude Code Command: Run Reviewer Loop

Follow the standalone automated reviewer loop protocol:

`docs/ai/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`

- **Scope**: Run Step 7 (automated review) and Step 8 (CI) for the specified PR, dispatching fixer agents when the platform reports blocking issues, until the PR is ready for human review or escalated.
- **Target**: Use the PR number from the command if given; otherwise resolve the PR for the current branch (e.g. `gh pr view --json number --jq '.number'`).
- **Pre-flight — check for existing unresolved findings before running the scripts**: Run `gh pr view <number> --json reviews` and read all review comments (e.g. `gh api repos/{owner}/{repo}/pulls/<number>/comments`). If any configured review platform (see `.ai-dev-workflow.yaml`) has already posted a review with blocking findings that have not been addressed in a subsequent commit, dispatch a fixer agent to resolve them and push first — then proceed with the scripts. This handles the case where a platform posted its review after a previous run timed out.
- Use the helper scripts `scripts/development-workflow/pr-review-loop.sh` and `scripts/development-workflow/pr-ci-loop.sh`. Do **not** pass `--platform` unless you intend to override the repo config: the script reads `.ai-dev-workflow.yaml` and uses `review.platforms` when no `--platform` is given. Run Step 7 to completion before Step 8 (do not run in background).
- Apply labels per `docs/ai/development-workflow/protocols/92-pr-readiness-signal-protocol.md` when the loops are clean or when CI/feedback requires `needs-fixes`.
