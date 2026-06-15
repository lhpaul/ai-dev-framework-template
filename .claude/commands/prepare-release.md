---
description: Prepare a release from develop. Creates the release branch, updates CHANGELOG, bumps version, opens PRs to main and develop, then drives reviewer loop + ready-for-regression + CI on the main PR before human merge. Usage: /prepare-release [version number, e.g. 1.2.0]
allowed-tools: Bash(git checkout:*), Bash(git fetch:*), Bash(git pull:*), Bash(git push:*), Bash(git log:*), Bash(git status:*), Bash(git branch:*), Bash(git diff:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh pr edit:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(date:*), Bash(./scripts/development-workflow/pr-review-loop.sh:*), Bash(./scripts/development-workflow/pr-ci-loop.sh:*), Bash(./scripts/development-workflow/prepare-release-post-merge-cleanup.sh:*)
---

Follow the release protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`

Key rules:

- Verify working directory is clean and currently on `develop` before starting
- Run `git fetch origin && git pull origin develop` before creating the release branch; if the pull fails, stop and report
- If no version provided, inspect `[Unreleased]` entries and suggest the next version
- Confirm the version with the human before creating the branch
- Open **two** PRs: one to `main`, one backport to `develop`
- **After both PRs exist**, run the automated reviewer loop, apply `ready-for-regression`, and run the CI loop on the **production PR targeting `main` only** — do not stop at “PR opened” (use `scripts/development-workflow/pr-review-loop.sh` and `pr-ci-loop.sh` per protocol)
- Merge `main` PR first; the tag is created automatically by CI
- After both PRs merge, run Step 9 post-merge cleanup with `--from-changelog` or an explicit `--issues` scope, then complete any emitted tracker handoff such as `TRACKER_ACTION=linear_mcp_or_api_required` before considering the release flow complete
