# Protocol: Prepare Release

**Stage**: Release
**Triggered by**: Human (when the configured release source is ready to ship)

---

## Repository Ownership

In `workflow_hub` or `product_repo` mode, validate the selected product release
contract before creating or mutating product-owned release artifacts such as
changelog entries, release branches, tags, GitHub Releases, deployment
evidence, or product cleanup evidence.

From the hub checkout in `workflow_hub` mode, pass exactly one selected product
repository name and resolve the canonical component release target:

<!-- workflow-shell-contract: bash-zsh -->
```bash
TARGET_REPO_KEY="<product-repo>"
TARGET_BINDING_SAFE_KEY="$(printf '%s' "$TARGET_REPO_KEY" | tr -c 'A-Za-z0-9._-' '_')"
TARGET_BINDING_FILE="$(mktemp "${TMPDIR:-/tmp}/component-release-target.${TARGET_BINDING_SAFE_KEY}.XXXXXX")"
TARGET_BINDING_TMP="${TARGET_BINDING_FILE}.$$"
scripts/development-workflow/component-release-target.sh \
  --repo "$TARGET_REPO_KEY" \
  --json > "$TARGET_BINDING_TMP"
mv "$TARGET_BINDING_TMP" "$TARGET_BINDING_FILE"
```

Continue only when the helper reports
`routing_outcome=component_release_routed` and `mutation_allowed=true`. Stop
before mutation for any stop outcome defined in
[Repository modes](../repository-modes.md#release-artifact-ownership). These
stop outcomes are successful classifications; do not convert them into release
branches, tags, changelog edits, deployment evidence, cleanup evidence, or
tracker changes.

Also record the normalized release fields from the resolver output:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/validate-workflow-config.sh --repo <product-repo>
```

From a product checkout in `product_repo` mode, omit `--repo`; validation reads
`product_repo.release` from the current repository config or applies the
product-repository defaults:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/validate-workflow-config.sh
```

For product-owned releases, switch to the resolved product checkout before any
mutation. Use these resolved values for the rest of the protocol:

- `TARGET_LOCAL_PATH`: product checkout to mutate.
- `TARGET_RELEASE_BASE`: source/backport base branch.
- `TARGET_RELEASE_BRANCH_PATTERN`: release branch pattern.
- `TARGET_REPO_NAME`: product repository placeholder value.
- `TARGET_RELEASE_CONTRACT_REVISION`: stable digest of the normalized portable
  release contract.

Resolve the release branch by replacing `{version}` with the confirmed version
and `{product_repo}` with `TARGET_REPO_NAME`. If validation did not emit these
fields, or the resolved checkout is missing, stop before mutation.

Bind the product checkout and release base before pre-flight:

<!-- workflow-shell-contract: bash-zsh -->
```bash
cd "${TARGET_LOCAL_PATH:?}"
RELEASE_BASE="${TARGET_RELEASE_BASE:?}"
RELEASE_BRANCH_PATTERN="${TARGET_RELEASE_BRANCH_PATTERN:?}"
PRODUCT_REPO_NAME="${TARGET_REPO_NAME:?}"
```

Single-repository releases keep the existing current-repository ownership model
and may use `RELEASE_BASE=develop` and
`RELEASE_BRANCH_PATTERN=release/v{version}` with an empty `PRODUCT_REPO_NAME`.

For workflow-hub multi-repository adoption, collect release self-review
assurance from
[Multi-repository release adoption](../multi-repo-release-adoption.md) before
release mutation. A previously adopted release may reuse persisted validation
only when the selected product contract, fixture inputs, and historical
baselines have not changed since that validation. Otherwise rerun assurance.
The evidence must show `adoption_status=validated` and unchanged hub-owned and
product-owned historical baselines, or stop with the reported owner action. It
is not required for unchanged `single_repo` releases.

---

## Pre-flight Checks

Before doing anything, verify the artifact-owning checkout:

1. Working directory is clean (`git status` returns no uncommitted changes). If not, stop and report.
2. Fetch and pull the resolved release base so the release branch is created from up-to-date state:

   <!-- workflow-shell-contract: bash-zsh -->
   ```bash
   git fetch origin
   git switch "$RELEASE_BASE"
   git pull --ff-only origin "$RELEASE_BASE"
   ```

   If the pull fails (e.g., diverged history), stop and report to the human.

---

## Step 1: Confirm Version

If the version was not provided, inspect the `[Unreleased]` section of `CHANGELOG.md` and suggest the appropriate next version using [Semantic Versioning](https://semver.org/):

- **PATCH** (`x.y.Z`): bug fixes only
- **MINOR** (`x.Y.0`): new features, backwards-compatible
- **MAJOR** (`X.0.0`): breaking changes

Wait for human confirmation before proceeding.

After confirmation, bind the release branch from the normalized pattern:

<!-- workflow-shell-contract: bash-zsh -->
```bash
VERSION="X.Y.Z"
PRODUCT_REPO_NAME="${PRODUCT_REPO_NAME:-}"
RELEASE_BRANCH="${RELEASE_BRANCH_PATTERN//\{version\}/$VERSION}"
RELEASE_BRANCH="${RELEASE_BRANCH//\{product_repo\}/$PRODUCT_REPO_NAME}"
```

If `RELEASE_BRANCH` is empty or differs from the validated pattern semantics,
stop before branch creation.

For workflow-hub component releases, re-resolve `TARGET_BINDING_FILE` now that
`RELEASE_BRANCH` is known, passing it as `--release-branch`. The release
correlation key is otherwise derived only from static contract fields
(product repository, release base, branch pattern, contract revision), so
without a per-attempt identifier every release of the same product and
unchanged contract — for example `v1.2.3` and a later `v1.2.4` — would collide
on the same `release_correlation_key`, conflating separate releases in
cleanup locking, conflict detection, and audit records:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/component-release-target.sh   --repo "$TARGET_REPO_KEY"   --release-branch "$RELEASE_BRANCH"   --json > "$TARGET_BINDING_TMP"
mv "$TARGET_BINDING_TMP" "$TARGET_BINDING_FILE"
```

Persist a component release evidence record before opening release PRs. The
evidence must be derived from the target binding produced by
`component-release-target.sh` and must preserve `selected_product_repo_key`,
`canonical_repository_identity`, `artifact_owners`, `release_correlation_key`,
and `contract_revision`:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_BINDING_FILE" \
  --binding-file "$TARGET_BINDING_FILE" \
  --release-branch "$RELEASE_BRANCH" \
  --release-outcome pending \
  --ci-outcome pending \
  --deployment-outcome pending \
  --cleanup-outcome not_started \
  --hub-tracker-ref "<tracker-item-or-epic>" \
  --output /path/to/component-release-evidence.json
```

When the component release belongs to an open hub-owned delivery bundle, attach
that evidence to the bundle after the product release evidence file exists. The
delivery bundle remains hub-owned; this handoff must not change the product
release artifact owner or create a shared suite branch:

<!-- workflow-shell-contract: bash-zsh -->
```bash
DELIVERY_BUNDLE_MANIFEST="${DELIVERY_BUNDLE_MANIFEST:?}"
DELIVERY_BUNDLE_KEY="${DELIVERY_BUNDLE_KEY:?}"
DELIVERY_BUNDLE_REVISION="$(jq -r '.revision' "$DELIVERY_BUNDLE_MANIFEST")"

scripts/development-workflow/delivery-bundle-manifest.sh update-component \
  --manifest "$DELIVERY_BUNDLE_MANIFEST" \
  --bundle-key "$DELIVERY_BUNDLE_KEY" \
  --expected-revision "${DELIVERY_BUNDLE_REVISION:?}" \
  --component-key "${TARGET_REPO_KEY:?}" \
  --evidence-file /path/to/component-release-evidence.json \
  --component-tag "${COMPONENT_TAG:?}" \
  --component-version "${VERSION:?}" \
  --source-pr "${SOURCE_PR_NUMBER:?}" \
  --release-pr "${RELEASE_PR_NUMBER:?}" \
  --hub-tracker-reconciliation-outcome complete \
  --child-item "<tracker-item-or-child>" \
  --child-release-state merged \
  --json
```

If any delivery bundle field is unknown, leave the component release evidence in
place and let the hub operator attach it later. Do not infer a bundle key from a
temporary file path or product branch name.

After component release evidence, product cleanup evidence, and hub tracker
reconciliation are complete, reconcile the hub-owned component milestone and
release status from the hub checkout. Component-child reconciliation may create
or reuse `<product-repo>@<component-tag>` and assign it only to the matching
component child. Parent-epic reconciliation may update the delivery manifest
`release_status` only after the delivery bundle is finalized; it must not stamp
a milestone on the parent epic or delivery bundle issue:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/component-milestone-reconciliation.sh apply-component \
  --issue "${COMPONENT_CHILD_ISSUE:?}" \
  --target-kind component_child \
  --product-repo "${TARGET_REPO_KEY:?}" \
  --component-tag "${COMPONENT_TAG:?}" \
  --evidence-file /path/to/component-release-evidence.json \
  --hub-tracker-reconciliation-outcome complete \
  --child-release-state merged \
  --json

scripts/development-workflow/component-milestone-reconciliation.sh inspect-parent \
  --parent-issue "${PARENT_EPIC_ISSUE:?}" \
  --delivery-manifest "${DELIVERY_BUNDLE_MANIFEST:?}" \
  --require-finalized \
  --json
```

If the helper reports `component_release_pending`,
`component_release_not_ready`, `component_target_mismatch`,
`component_tag_missing`, `parent_blocked`, `parent_partially_released`, or
`parent_not_released`, stop before tracker milestone or release-status mutation
and report the emitted `required_next_action`.

---

## Step 2: Create the Release Branch

<!-- workflow-shell-contract: bash-zsh -->
```bash
git checkout -b "$RELEASE_BRANCH"
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

## Step 6: Push and Open Release PR(s)

<!-- workflow-shell-contract: bash-zsh -->
```bash
git push -u origin "$RELEASE_BRANCH"
```

**If `RELEASE_BASE` is `main`** (the resolved release base for a trunk-based
product repository — for example a product with `default_branch: main` and no
explicit `release.base` override), the production and backport targets are
identical. Opening a second PR with the same head and base as the first is
impossible (`gh pr create` fails: a PR from `RELEASE_BRANCH` to `main` already
exists) and there is no separate branch to keep in sync. Use the **one-PR
flow**: open only the production PR below, skip the backport PR entirely, and
treat every later step that references the backport PR (§7.5, Step 8 backport
merge, Step 9 two-merged-PR checks) as satisfied by that single PR. Continue to
Step 7.

Otherwise, open **two** PRs from the release branch using `gh pr create`:

| PR                 | Target    | Purpose                                                      |
| ------------------ | --------- | ------------------------------------------------------------ |
| Production release | `main`    | Ships to production                                          |
| Backport           | `RELEASE_BASE` | Keeps the source branch in sync — **mandatory**, prevents branch drift |

Use title `chore(release): v[X.Y.Z]` for both. Include the CHANGELOG entries for this version in the PR body.

Example:

<!-- workflow-shell-contract: bash-zsh -->
```bash
# 1) Production release PR (configured release branch -> main)
gh pr create --base main --title "chore(release): v[X.Y.Z]" --body-file /tmp/release-notes.md

# 2) Backport PR (configured release branch -> release base) — skip when RELEASE_BASE=main
gh pr create --base "$RELEASE_BASE" --title "chore(release): v[X.Y.Z]" --body-file /tmp/release-notes.md
```

Opening PRs is **not** a terminal condition. Continue with Step 7 for the production PR before telling the human the release is ready to merge.

---

## Step 7: Drive Production PR Readiness (`main` Target Only)

Apply only to the **release PR that targets `main`**. Do **not** apply the regression-label requirement to the backport PR to `RELEASE_BASE` (that PR may still run other CI; this step scopes expensive label-gated e2e/regression to production).

**No external reviewer tools for release PRs.** External automated reviewers (Haystack, CodeRabbit, PR-Agent, Claude Code Action, etc.) are not required for release PRs and must not be waited on. Every change in a release PR was already reviewed when its feature/fix PR merged into the resolved release base. Running `pr-review-loop.sh` on a release PR automatically exits with `RESULT=skipped` (release PR guard fires) — treat that as a clean non-blocking result and proceed directly to release artifact validation and CI.

Note: release PRs use a simplified readiness flow (the CI loop step applies `ready-for-human-review` directly after CI is green) and do not run Protocol 91's Step 8a/8b label checklist.

### 7.1 Resolve the production PR number

Identify the open PR from the resolved release branch to `main`, for example:

<!-- workflow-shell-contract: bash-zsh -->
```bash
gh pr list --head "$RELEASE_BRANCH" --base main --state open --json number --jq '.[0].number'
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

<!-- workflow-shell-contract: bash-zsh -->
```bash
bash -lc 'source scripts/development-workflow/workflow-lib.sh; list_open_workflow_type_issues'
```

When the provider is `github_issues`, use the repository's configured
classification convention. Older repositories may still use:

<!-- workflow-shell-contract: bash-zsh -->
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

<!-- workflow-shell-contract: bash-zsh -->
```bash
gh pr edit <pr_number> --add-label "ready-for-regression"
```

This mirrors Step 7b in `91` for implementation PRs, but scoped here to the release PR targeting `main`.

### 7.4 CI loop

Run `pr-ci-loop.sh` and wait until required checks settle (including the e2e/regression check when configured):

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

| Result    | Action                                                                                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `green`   | Apply `ready-for-human-review` per [`92-pr-readiness-signal-protocol.md`](92-pr-readiness-signal-protocol.md); the production PR is ready for human merge review. |
| `red`     | Apply `needs-fixes`, fix, push, then return to the artifact validation step (§7.2) and repeat through the CI loop step (§7.4).                                                        |
| `timeout` | Escalate to a human; do not apply `ready-for-human-review`.                                                                                                       |

### 7.5 Backport PR (`RELEASE_BASE` target)

Skip this step under the one-PR flow (`RELEASE_BASE=main`, §Step 6) — there is
no separate backport PR to drive.

Otherwise: do **not** require `ready-for-regression` on the backport PR as part of this protocol. It may proceed on its own CI; merge order remains: **merge `main` first**, then backport.

---

## Step 8: Inform the Human

Under the one-PR flow (`RELEASE_BASE=main`), there is only one PR to merge:

1. **Merge the production PR** — the tag `v[X.Y.Z]` is created automatically by CI on merge (`.github/workflows/auto-tag-release.yml`)
2. Run Step 9 post-merge cleanup after it is merged

Otherwise, when the production PR is ready (or clearly escalated):

1. **Merge the `main` PR first** — the tag `v[X.Y.Z]` is created automatically by CI on merge (`.github/workflows/auto-tag-release.yml`)
2. Then merge the `RELEASE_BASE` backport PR
3. Run Step 9 post-merge cleanup only after both PRs are merged

> **Use regular merge commits — not squash or rebase.** Squash-merging release PRs breaks the gitflow history chain: `main` won't share commit ancestors with the release base, causing future comparisons to show accumulated historical divergence instead of just new changes. Regular merge commits preserve the relationship so `git log main.."$RELEASE_BASE"` accurately reflects pending work.

If Step 7 escalated or CI timed out, report status and blockers before merge.

---

## Step 9: Post-Merge Cleanup (Branch + Tracker)

Run this step only after the release PR(s) from `RELEASE_BRANCH` are merged:
both PRs under the normal two-PR flow, or the single production PR under the
one-PR flow (`RELEASE_BASE=main`).

### 9.1 Verify merged state before deletion

Confirm the release branch has:

- One merged PR to `main`
- One merged PR to `RELEASE_BASE` (the same PR as above under the one-PR flow — `RELEASE_BASE=main` reuses the production PR)
- No remaining open PRs to either base

If either merged PR is missing, or one PR is still open, stop. Do **not** delete the release branch and do **not** run release stamping or tracker release transitions.

Before running cleanup, derive the explicit shipped issue set from the finalized
`## [X.Y.Z]` section in `CHANGELOG.md`. Use only issue references that actually
shipped in that release section. Prefer the helper's `--from-changelog` parser,
or pass the same explicit scope with `--issue` / `--issues`. Do not infer release
scope from the whole project board.

### 9.2 Preferred command (single entry point)

Use the helper script:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh "$RELEASE_BRANCH" --backport-base "$RELEASE_BASE" --from-changelog
```

For workflow-hub component releases, run cleanup from the hub checkout and pass
the same selected product repository plus the persisted evidence file:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  "$RELEASE_BRANCH" \
  --repo <product-repo> \
  --repo-root "$(pwd)" \
  --evidence-file /path/to/component-release-evidence.json \
  --from-changelog
```

The script performs all required checks and actions in order:

1. Verifies both merged PRs exist (`main` and `RELEASE_BASE`) and no open PR remains.
2. In workflow-hub component mode, re-resolves the current release target and
   rejects mismatched repository identity, release correlation key, artifact
   owners, or `contract_revision` before mutation.
3. Acquires a per-release cleanup lease keyed by `release_correlation_key`.
4. Deletes remote branch `RELEASE_BRANCH` in the artifact-owning checkout (or
   logs that it is already absent).
5. Deletes local branch `RELEASE_BRANCH` in the artifact-owning checkout when safe.
6. Records the production release version on each explicit in-scope tracker item.
7. Transitions explicit in-scope tracker items from merged-to-integration to released-to-production.

Use `--issues <issue1,issue2,...>` or repeated `--issue <issue>` only when the
CHANGELOG section cannot be used and a human has confirmed the shipped issue
scope.

### 9.3 Manual equivalent (when script cannot be used)

<!-- workflow-shell-contract: bash-zsh -->
```bash
# verify merged PRs first (examples)
gh pr list --head "$RELEASE_BRANCH" --base main --state merged --json number
gh pr list --head "$RELEASE_BRANCH" --base "$RELEASE_BASE" --state merged --json number

# delete remote branch (only after both merges)
git push origin --delete "$RELEASE_BRANCH"

# delete local branch (switch away first if currently checked out)
git switch "$RELEASE_BASE"
git branch -D "$RELEASE_BRANCH"
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

- If `RELEASE_BASE` is branch-protected (requires PR to merge), the backport PR is the correct mechanism — do not attempt to push directly.
- If no CI workflow exists for auto-tagging, instruct the human to run after the `main` merge: `git tag v[X.Y.Z] && git push origin v[X.Y.Z]`
- Reference-style links follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Removing them makes version headers plain text instead of comparison links on GitHub.
