# Protocol: Prepare Release

**Stage**: Release
**Triggered by**: Human (when develop is ready to ship)

---

## Pre-flight Checks

Before doing anything, verify:

1. Working directory is clean (`git status` returns no uncommitted changes). If not, stop and report.
2. Currently on `develop`. If not, stop and report.
3. Fetch and pull latest from remote so the release branch is created from up-to-date state:

   ```bash
   git fetch origin
   git pull origin develop
   ```

   If the pull fails (e.g., diverged history), stop and report to the human.

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

| PR                 | Target    | Purpose                                                      |
| ------------------ | --------- | ------------------------------------------------------------ |
| Production release | `main`    | Ships to production                                          |
| Backport           | `develop` | Keeps develop in sync — **mandatory**, prevents branch drift |

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

**No external reviewer tools for release PRs.** External automated reviewers (Haystack, CodeRabbit, PR-Agent, Claude Code Action, etc.) are not required for release PRs and must not be waited on. Every change in a release PR was already reviewed when its feature/fix PR merged into `develop`. Running `pr-review-loop.sh` on a release PR automatically exits with `RESULT=skipped` (release PR guard fires) — treat that as a clean non-blocking result and proceed directly to release artifact validation and CI.

Note: release PRs use a simplified readiness flow (the CI loop step applies `ready-for-human-review` directly after CI is green) and do not run Protocol 91's Step 8a/8b label checklist.

### 7.1 Resolve the production PR number

Identify the open PR from `release/v[X.Y.Z]` to `main`, for example:

```bash
gh pr list --head "release/v[X.Y.Z]" --base main --state open --json number --jq '.[0].number'
```

If multiple or zero matches, stop and resolve with the human.

### 7.2 Validate release artifacts

Before applying any labels or starting CI, confirm the release artifacts are correct:

1. **CHANGELOG version header**: verify `## [X.Y.Z] - YYYY-MM-DD` is present and the version matches the release target.
2. **Link definitions**: confirm the `[Unreleased]` and `[X.Y.Z]` reference-style link definitions at the bottom of `CHANGELOG.md` have been updated.
3. **Version bump**: if a manifest file (`package.json`, `pyproject.toml`, etc.) is versioned, verify the bump is present.

If any artifact is missing or incorrect, fix it on the release branch, push, and verify again before continuing.

**Downstream script-bug review**: Before labeling the production PR
`ready-for-human-review`, search for open workflow-framework GitHub issues that
were filed from downstream sync retrospectives. When `issue_tracker.provider` is
`github_projects`, use the project Type field instead of the legacy `workflow`
label:

```bash
bash -lc 'source scripts/development-workflow/workflow-lib.sh; list_open_workflow_type_issues'
```

When the provider is `github_issues`, use the repository's configured
classification convention. Older repositories may still use:

```bash
gh issue list --label workflow --state open --limit 200
```

If any known script bugs remain open and affect code in this release, address them
in the release branch or document the decision to defer with a comment on the issue.

### 7.3 Regression label (release / `main` PR only)

Apply the `ready-for-regression` label to the **production PR only** so
configured real regression checks, or an explicitly enabled placeholder, can run
(see [`integrations/e2e-regression.md`](../integrations/e2e-regression.md) and
`.github/workflows/e2e-regression.yml`).

```bash
gh pr edit <pr_number> --add-label "ready-for-regression"
```

This mirrors Step 7b in `91` for implementation PRs, but scoped here to the release PR targeting `main`.

### 7.4 CI loop

Run `pr-ci-loop.sh` and wait until required checks settle (including the e2e/regression check when configured):

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

| Result    | Action                                                                                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `green`   | Apply `ready-for-human-review` per [`92-pr-readiness-signal-protocol.md`](92-pr-readiness-signal-protocol.md); the production PR is ready for human merge review. |
| `red`     | Apply `needs-fixes`, fix, push, then return to the artifact validation step (§7.2) and repeat through the CI loop step (§7.4).                                                        |
| `timeout` | Escalate to a human; do not apply `ready-for-human-review`.                                                                                                       |

### 7.5 Backport PR (`develop` target)

Do **not** require `ready-for-regression` on the backport PR as part of this protocol. It may proceed on its own CI; merge order remains: **merge `main` first**, then backport.

---

## Step 8: Inform the Human

When the production PR is ready (or clearly escalated):

1. **Merge the `main` PR first** — the tag `v[X.Y.Z]` is created automatically by CI on merge (`.github/workflows/auto-tag-release.yml`)
2. Then merge the `develop` backport PR
3. Run Step 9 post-merge cleanup only after both PRs are merged

> **Use regular merge commits — not squash or rebase.** Squash-merging release PRs breaks the gitflow history chain: `main` won't share commit ancestors with `develop`, causing future comparisons to show accumulated historical divergence instead of just new changes. Regular merge commits preserve the relationship so `git log main..develop` accurately reflects pending work.

If Step 7 escalated or CI timed out, report status and blockers before merge.

---

## Step 9: Post-Merge Cleanup (Branch + Tracker)

Run this step only after both release PRs from `release/v[X.Y.Z]` are merged.

### 9.1 Verify merged state before deletion

Confirm the release branch has:

- One merged PR to `main`
- One merged PR to `develop`
- No remaining open PRs to either base

If either merged PR is missing, or one PR is still open, stop. Do **not** delete the release branch and do **not** run release stamping or tracker release transitions.

Before running cleanup, derive the explicit shipped issue set from the finalized
`## [X.Y.Z]` section in `CHANGELOG.md`. Use only issue references that actually
shipped in that release section. Prefer the helper's `--from-changelog` parser,
or pass the same explicit scope with `--issue` / `--issues`. Do not infer release
scope from the whole project board.

### 9.2 Preferred command (single entry point)

Use the helper script:

```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v[X.Y.Z] --from-changelog
```

The script performs all required checks and actions in order:

1. Verifies both merged PRs exist (`main` and `develop`) and no open PR remains.
2. Deletes remote branch `release/v[X.Y.Z]` (or logs that it is already absent).
3. Deletes local branch `release/v[X.Y.Z]` when safe.
4. Records the production release version on each explicit in-scope tracker item.
5. Transitions explicit in-scope tracker items from merged-to-integration to released-to-production.

Use `--issues <issue1,issue2,...>` or repeated `--issue <issue>` only when the
CHANGELOG section cannot be used and a human has confirmed the shipped issue
scope.

### 9.3 Manual equivalent (when script cannot be used)

```bash
# verify merged PRs first (examples)
gh pr list --head "release/v[X.Y.Z]" --base main --state merged --json number
gh pr list --head "release/v[X.Y.Z]" --base develop --state merged --json number

# delete remote branch (only after both merges)
git push origin --delete "release/v[X.Y.Z]"

# delete local branch (switch away first if currently checked out)
git switch develop
git branch -D "release/v[X.Y.Z]"
```

If local deletion fails because the branch is checked out in another worktree, switch away in that worktree and retry.

### 9.4 Release stamp + tracker transition for in-scope items

Use the provider-routed release-stamp operation documented in [`issue-tracker.md`](../integrations/issue-tracker.md) and the same GitHub Projects v2 status update path documented in [`github-projects.md`](../integrations/github-projects.md). The helper script accepts explicit issue numbers (`--issue`/`--issues`) to keep scope safe.

- Default status names: `Merged` and `Released`
- Optional env overrides:
  - `GITHUB_PROJECT_STATUS_MERGED`
  - `GITHUB_PROJECT_STATUS_RELEASED`
- GitHub providers stamp releases with a Milestone named `vX.Y.Z`, assign it to each shipped issue, and close the milestone after cleanup succeeds.
- Unsupported providers log a release-stamp skip/warning and continue; release stamping is best effort and must not block status transitions.
- Linear providers require MCP/API completion after shell cleanup. If the helper
  emits `TRACKER_ACTION=linear_mcp_or_api_required`, transition every listed
  `TRACKER_ISSUES` item from `Merged` to `Released` with Linear MCP/API before
  treating the release as complete. The helper exits non-zero unless
  `--best-effort` is passed.

Only transition work items explicitly confirmed as part of the shipped release. Do not bulk-move all project items in `Merged` unless a human explicitly asks for that scope.

### 9.5 Completion gate

The release is not complete until branch cleanup succeeds and tracker transitions
either succeed or a human explicitly accepts `--best-effort` handling. A cleanup
run that emits `TRACKER_INCOMPLETE=1` is a handoff signal, not a success state:
complete the named tracker action and rerun/verify before reporting the release
closed.

If release stamping needs manual repair, use the provider-native release marker
for each shipped issue (for example, GitHub Milestone `vX.Y.Z`, Jira Fix
Version/s, or a Linear `release/vX.Y.Z` label/custom field) and then rerun or
manually complete the `Merged` -> `Released` status transition.

---

## Notes

- If `develop` is branch-protected (requires PR to merge), the backport PR is the correct mechanism — do not attempt to push directly.
- If no CI workflow exists for auto-tagging, instruct the human to run after the `main` merge: `git tag v[X.Y.Z] && git push origin v[X.Y.Z]`
- Reference-style links follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Removing them makes version headers plain text instead of comparison links on GitHub.
