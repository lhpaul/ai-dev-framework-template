---
description: Prepare a release from develop. Creates the release branch, updates CHANGELOG, bumps version, and opens a PR targeting main. Usage: @prepare-release [version number, e.g. 1.2.0]
---

Follow the release process defined in:

`docs/ai/development-workflow/README.md` → "Release Process" section

Steps:
1. Confirm the version number with the user (MAJOR.MINOR.PATCH per semver)
2. Create branch: `git checkout -b release/v[X.Y.Z]` from `develop`
3. In `CHANGELOG.md`: rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` and add a new empty `[Unreleased]` section at the top
4. Bump version in any manifest files (e.g., `package.json`, `pyproject.toml`) — ask if unsure which files
5. Commit: `chore(release): v[X.Y.Z]`
6. Push and open PR targeting `main`

After the human merges the release PR:
7. Tag: `git tag v[X.Y.Z]` on `main`
8. Push tag: `git push origin v[X.Y.Z]`
9. Remind the human: merge `main` back into `develop` to prevent branch drift
