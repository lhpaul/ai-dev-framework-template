# Protocol: Prepare Release

**Stage**: Release
**Triggered by**: Human (when develop is ready to ship)

---

## Pre-flight Checks

Before doing anything, verify:

1. Working directory is clean (`git status` returns no uncommitted changes). If not, stop and report.
2. Currently on `develop`. If not, stop and report.
3. Pull latest: `git pull origin develop`

---

## Step 1: Confirm Version

If the version was not provided, inspect the `[Unreleased]` section of `CHANGELOG.md` and suggest the appropriate next version using [Semantic Versioning](https://semver.org/):

- **PATCH** (`x.y.Z`): bug fixes only
- **MINOR** (`x.Y.0`): new features, backwards-compatible
- **MAJOR** (`X.0.0`): breaking changes

Wait for human confirmation before proceeding.

---

## Step 2: Create the Release Branch

```bash
git checkout -b release/v[X.Y.Z]
```

---

## Step 3: Update CHANGELOG

In `CHANGELOG.md`:

1. Rename `## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD` (use today's date)
2. Add a new empty `## [Unreleased]` section at the top (above the versioned entry)

---

## Step 4: Bump Version in Manifests

Update the version field in any manifest files that track it (e.g., `package.json`, `pyproject.toml`, `Cargo.toml`). Ask the human which files apply if it's not obvious.

---

## Step 5: Commit

```
chore(release): v[X.Y.Z]
```

---

## Step 6: Push and Open Two PRs

```bash
git push -u origin release/v[X.Y.Z]
```

Open **two** PRs from the release branch using `gh pr create`:

| PR | Target | Purpose |
|---|---|---|
| Production release | `main` | Ships to production |
| Backport | `develop` | Keeps develop in sync — **mandatory**, prevents branch drift |

Use title `chore(release): v[X.Y.Z]` for both. Include the CHANGELOG entries for this version in the PR body.

---

## Step 7: Inform the Human

After both PRs are open:

1. **Merge the `main` PR first** — the tag `v[X.Y.Z]` is created automatically by CI on merge (`.github/workflows/auto-tag-release.yml`)
2. **Then merge the `develop` backport PR**
3. **Do not delete the release branch** until both PRs are merged

---

## Notes

- If `develop` is branch-protected (requires PR to merge), the backport PR is the correct mechanism — do not attempt to push directly.
- If no CI workflow exists for auto-tagging, instruct the human to run after the `main` merge: `git tag v[X.Y.Z] && git push origin v[X.Y.Z]`
