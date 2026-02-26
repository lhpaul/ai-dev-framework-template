---
description: Prepare a release from develop. Creates the release branch, updates CHANGELOG, bumps version, and opens PRs targeting both main and develop. Usage: /prepare-release [version number, e.g. 1.2.0]
---

Follow the release process defined in:

`docs/ai/development-workflow/README.md` → "Release Process" section

Steps:
1. Confirm the version number with the user (MAJOR.MINOR.PATCH per semver)
2. Create branch: `git checkout -b release/v[X.Y.Z]` from `develop`
3. In `CHANGELOG.md`: rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` and add a new empty `[Unreleased]` section at the top
4. Bump version in any manifest files (e.g., `package.json`, `pyproject.toml`) — ask if unsure which files
5. Commit: `chore(release): v[X.Y.Z]`
6. Push the branch and open **two** PRs:
   - PR targeting `main`: the production release
   - PR targeting `develop`: mandatory backport to prevent branch drift
   Use title `chore(release): v[X.Y.Z]` and include the CHANGELOG entries for this version in the PR body.

After both PRs are open, remind the human:
7. Merge the `main` PR first — the tag `v[X.Y.Z]` will be created automatically by CI (`.github/workflows/auto-tag-release.yml`)
8. Then merge the `develop` backport PR
9. Do **not** delete the release branch until both PRs are merged
