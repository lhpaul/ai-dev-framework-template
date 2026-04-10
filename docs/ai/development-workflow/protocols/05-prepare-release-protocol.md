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

1. **Polish or trim the `[Unreleased]` content** (do this before renaming the section). Accumulated entries often read like a raw merge log: too long, repetitive, or full of implementation detail. Tighten them so the release is easy to scan:
   - Prefer **short, scannable bullets**: one clear outcome or change per line where possible.
   - **Merge or drop** near-duplicates; keep a single bullet for a feature or fix instead of one per PR or sub-task unless each line adds distinct user value.
   - **User- or operator-facing language**: what changed for readers of the changelog, not file names or refactors unless those matter externally.
   - **Drop or shorten** internal-only notes (e.g., test-only, doc nits) unless they are meaningful to consumers of the release.
   - If a subsection (Added, Changed, Fixed, etc.) is crowded, **summarize** into fewer high-signal bullets rather than listing every incremental commit.
   - Stay faithful to what shipped: polish for clarity, do not invent or remove substantive release notes without human agreement.

2. Rename `## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD` (use today's date)

3. Add a new empty `## [Unreleased]` section at the top (above the versioned entry)

4. **Reference-style link definitions** (Keep a Changelog): at the bottom of the file, update or add link definitions so version headers remain clickable comparison links on GitHub. **Do not remove** existing definitions; update them to include the new version.
   - `[Unreleased]`: `https://github.com/<owner>/<repo>/compare/vX.Y.Z...HEAD`
   - `[X.Y.Z]`: `https://github.com/<owner>/<repo>/compare/v<previous>...vX.Y.Z`
   - Retain (or add) definitions for all other version headers. Use the same tag format as your CI (e.g. `v1.2.0` if auto-tag-release uses that).

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

Example:

```bash
# 1) Production release PR (release/* -> main)
gh pr create --base main --title "chore(release): v[X.Y.Z]" --body-file /tmp/release-notes.md

# 2) Backport PR (release/* -> develop)
gh pr create --base develop --title "chore(release): v[X.Y.Z]" --body-file /tmp/release-notes.md
```

Opening PRs is **not** a terminal condition. Continue with Step 7 for the production PR before telling the human the release is ready to merge.

---

## Step 7: Drive Production PR Readiness (`main` Target Only)

Apply only to the **release PR that targets `main`**. Do **not** apply the regression-label requirement to the backport PR to `develop` (that PR may still run other CI; this step scopes expensive label-gated e2e/regression to production).

Canonical loop semantics match [`91-orchestrate-work-protocol.md`](91-orchestrate-work-protocol.md) (Steps 7, 7b, 8) and [`93-automated-reviewer-loop-protocol.md`](93-automated-reviewer-loop-protocol.md) for standalone reviewer runs. Prefer the repository helpers:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch release/v[X.Y.Z]
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

### 7.1 Resolve the production PR number

Identify the open PR from `release/v[X.Y.Z]` to `main`, for example:

```bash
gh pr list --head "release/v[X.Y.Z]" --base main --state open --json number --jq '.[0].number'
```

If multiple or zero matches, stop and resolve with the human.

### 7.2 Pre-flight (optional but recommended)

Per `93-automated-reviewer-loop-protocol.md`, check for existing unresolved blocking review comments before re-running automation.

### 7.3 Automated reviewer loop (Step 7)

Run `pr-review-loop.sh` to completion **before** starting the CI loop. Do not run reviewer and CI in parallel.

Interpret `RESULT` from the script output:

| Result | Action |
|---|---|
| `clean` | Continue to Step 7.4 (regression label). |
| `skipped` | No review platforms configured in `.ai-dev-workflow.yaml`; continue to Step 7.4 and document that external review was skipped. |
| `needs_fixes` | Address blocking findings (commit and push to the release branch), then re-run Step 7.3 from the top. Follow fixer guidance in `91` (e.g. `code-reviewer` for code changes). Do not hand off while blocking findings remain. |
| `escalate` | Stop and escalate to a human; do not mark the release as merge-ready. |

### 7.4 Regression label (release / `main` PR only)

After Step 7.3 ends with `clean` or `skipped`, apply the `ready-for-regression` label to the **production PR only** so label-gated e2e/regression runs (see [`integrations/e2e-regression.md`](../integrations/e2e-regression.md) and `.github/workflows/e2e-regression.yml`).

```bash
gh pr edit <pr_number> --add-label "ready-for-regression"
```

This mirrors Step 7b in `91` for implementation PRs, but scoped here to the release PR targeting `main`.

### 7.5 CI loop (Step 8)

Run `pr-ci-loop.sh` and wait until required checks settle (including the e2e/regression check when configured).

| Result | Action |
|---|---|
| `green` | Apply `ready-for-human-review` per [`92-pr-readiness-signal-protocol.md`](92-pr-readiness-signal-protocol.md); the production PR is ready for human merge review. |
| `red` | Apply `needs-fixes`, fix, push, then return to Step 7.3 (reviewer) and repeat through Step 7.5. |
| `timeout` | Escalate to a human; do not apply `ready-for-human-review`. |

### 7.6 Backport PR (`develop` target)

Do **not** require `ready-for-regression` on the backport PR as part of this protocol. It may proceed on its own CI; merge order remains: **merge `main` first**, then backport.

---

## Step 8: Inform the Human

When the production PR is ready (or clearly escalated):

1. **Merge the `main` PR first** — the tag `v[X.Y.Z]` is created automatically by CI on merge (`.github/workflows/auto-tag-release.yml`)
2. Then merge the `develop` backport PR
3. Do not delete the release branch until both PRs are merged

If Step 7 escalated or CI timed out, report status and blockers before merge.

---

## Notes

- If `develop` is branch-protected (requires PR to merge), the backport PR is the correct mechanism — do not attempt to push directly.
- If no CI workflow exists for auto-tagging, instruct the human to run after the `main` merge: `git tag v[X.Y.Z] && git push origin v[X.Y.Z]`
- Reference-style links follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Removing them makes version headers plain text instead of comparison links on GitHub.
