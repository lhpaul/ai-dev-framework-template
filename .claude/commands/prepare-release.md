---
description: Prepare a release. Creates the release branch, updates CHANGELOG, bumps version, and opens PRs targeting both main and develop. Usage: /prepare-release [version number, e.g. 1.2.0]
allowed-tools: Bash(git checkout:*), Bash(git pull:*), Bash(git push:*), Bash(git log:*), Bash(git status:*), Bash(git branch:*), Bash(git diff:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(date:*)
---

Follow the release process defined in:

`docs/ai/development-workflow/README.md` → "Release Process" section

Steps:
1. Confirm the version number with the user (MAJOR.MINOR.PATCH per semver). If no version is provided, inspect the unreleased CHANGELOG entries and suggest the appropriate next version.
2. Verify the working directory is clean (`git status`) and on `develop`. If not, abort and explain.
3. Pull the latest `develop`: `git pull origin develop`
4. Create branch: `git checkout -b release/v[X.Y.Z]`
5. In `CHANGELOG.md`: rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` (use today's date) and add a new empty `[Unreleased]` section at the top
6. Bump version in any manifest files (e.g., `package.json`, `pyproject.toml`) — ask the user which files apply if unsure
7. Commit: `chore(release): v[X.Y.Z]`
8. Push the branch: `git push -u origin release/v[X.Y.Z]`
9. Open **two** PRs using `gh pr create`:
   - PR targeting `main`: the production release
   - PR targeting `develop`: mandatory backport to prevent branch drift
   Use title `chore(release): v[X.Y.Z]` for both. Include the CHANGELOG entries for this version in the PR body.

After both PRs are open, inform the human:
10. Merge the `main` PR first — the tag `v[X.Y.Z]` is created automatically by CI (`.github/workflows/auto-tag-release.yml`)
11. Then merge the `develop` backport PR
12. Do **not** delete the release branch until both PRs are merged
