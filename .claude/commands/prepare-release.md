---
description: Prepare a release. Creates the release branch, updates CHANGELOG, bumps version, and opens PRs targeting both main and develop. Usage: /prepare-release [version number, e.g. 1.2.0]
allowed-tools: Bash(git checkout:*), Bash(git pull:*), Bash(git push:*), Bash(git log:*), Bash(git status:*), Bash(git branch:*), Bash(git diff:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(date:*)
---

Follow the release protocol exactly as defined in:

`docs/ai/development-workflow/protocols/06-prepare-release-protocol.md`

Key rules:
- Verify working directory is clean and currently on `develop` before starting
- If no version provided, inspect `[Unreleased]` entries and suggest the next version
- Confirm the version with the human before creating the branch
- Open **two** PRs: one to `main`, one backport to `develop`
- Merge `main` PR first; the tag is created automatically by CI
- Do not delete the release branch until both PRs are merged
