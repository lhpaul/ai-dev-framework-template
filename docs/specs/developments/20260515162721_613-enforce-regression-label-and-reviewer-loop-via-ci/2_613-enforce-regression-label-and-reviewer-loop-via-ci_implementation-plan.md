# Enforce Ready-for-Regression Label and Reviewer-Loop Handoff via CI — Implementation Plan

**Spec**: [1\_613-enforce-regression-label-and-reviewer-loop-via-ci\_specs.md](./1_613-enforce-regression-label-and-reviewer-loop-via-ci_specs.md)
**Smoke test runbook**: [docs/testing/workflow/613-enforce-regression-label-and-reviewer-loop-via-ci.smoke-test.md](../../../../docs/testing/workflow/613-enforce-regression-label-and-reviewer-loop-via-ci.smoke-test.md)

---

## Summary

**Approach**: Add two new GitHub Actions workflow files to `.github/workflows/`. The first (`apply-regression-label.yml`) triggers on `pull_request` events (opened, reopened, ready_for_review, synchronize) and applies the `ready-for-regression` label when the head branch matches any configured in-scope implementation prefix. The second (`reviewer-loop-guard.yml`) triggers on the same PR events and posts a failing commit status check when the PR's comment timeline does not contain a canonical "Automated Reviewer Loop Summary" comment posted by `pr-review-loop.sh`. Both workflows are idempotent, require only `GITHUB_TOKEN`, and carry the minimum permissions needed for their job.

**Estimated complexity**: S

**Rationale**: The work is fully scoped to two self-contained GitHub Actions YAML files and minimal documentation. No existing code is modified; no new secrets or external services are introduced; the canonical summary marker is already defined and stable. The label workflow pattern mirrors the existing `remove-regression-label-on-push.yml` file, reducing net authoring risk.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `50b337d` |
| Existing regression-label workflow count | `ls .github/workflows/ \| grep regression` | 1 (`remove-regression-label-on-push.yml`) |
| Reviewer-loop summary marker (exact string) | `grep "Automated Reviewer Loop Summary" scripts/development-workflow/pr-review-loop.sh` | Present at lines 123, 3151, 3155, 3304, 3321, 3335 |
| Secondary marker (unique to script-posted comments) | `grep "Posted automatically by" scripts/development-workflow/pr-review-loop.sh` | Present; combined with `### Automated Reviewer Loop Summary` to uniquely identify script-posted summaries |
| Existing action pin (checkout) | `grep "actions/checkout" .github/workflows/remove-regression-label-on-push.yml` | `actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5.0.1` |
| Existing in-scope branch prefixes in template | `grep -h "feature/\|fix/\|refactor/\|hotfix/" .github/workflows/remove-regression-label-on-push.yml` | Not present (prefixes defined as env var in workflow) |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Add `.github/workflows/apply-regression-label.yml` — new GitHub Actions workflow that auto-applies `ready-for-regression` to implementation PRs based on branch prefix.
- [ ] Add `.github/workflows/reviewer-loop-guard.yml` — new GitHub Actions workflow that posts a failing commit status when the PR lacks a canonical reviewer-loop summary comment.
- [ ] Add documentation section to `docs/workflow/development-workflow/integrations/ci-enforcement.md` (new file) explaining: (a) which branch prefixes are in scope by default, (b) how downstream repos override the prefix list, (c) how to configure the reviewer-loop guard as a required status check in branch protection.

No database, backend, shared package, or frontend layers are affected.

---

## Testing Strategy

**Test types**: Smoke / Manual (GitHub Actions run in CI; no unit test framework exists for workflow YAML in this repository).

**Key scenarios to test**:

1. Opening a PR from `feature/`, `fix/`, `refactor/`, or `hotfix/` branch applies `ready-for-regression` automatically — maps to Acceptance Criteria #1 and #3.
2. Opening a PR from `spec/`, `implementation-plan/`, `docs/`, or `chore/` branch does not apply the label — maps to Acceptance Criterion #2.
3. Re-running the label workflow when the label is already present completes without error and without duplicating the label — maps to Acceptance Criterion #4.
4. An implementation PR with no reviewer-loop summary comment shows a failing check — maps to Acceptance Criterion #5.
5. After `pr-review-loop.sh` posts its summary, the guard check transitions to passing — maps to Acceptance Criterion #6.
6. A new push to the PR branch (synchronize) causes the guard to re-evaluate — maps to Acceptance Criterion #7.
7. Both workflow YAML files pass `actionlint` with no warnings — maps to Acceptance Criterion #9.
8. Permissions declared in each workflow are the minimum required — maps to Acceptance Criterion #10.

**Smoke test runbook**: `docs/testing/workflow/613-enforce-regression-label-and-reviewer-loop-via-ci.smoke-test.md`

**Regression suite**: No automated regression suite exists for GitHub Actions workflow files in this repository. Smoke test covers the acceptance criteria via manual or fixture-PR verification.

---

## Seed Data

No seed data is required. The feature operates entirely on GitHub Actions events and PR metadata.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/ci-enforcement.md` (new file, created as part of this implementation) — explains default branch prefix list, downstream override, and branch protection wiring. This file IS part of implementation; it is not a post-implementation update.
- [ ] `CLAUDE.md` / `AGENTS.md` — No update required; this feature adds CI enforcement and does not change agent protocols or project overview conventions.
- [ ] `docs/project/` docs — No update required; these are placeholder docs and the feature does not affect architecture, business domain, or data model.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| `ready-for-regression` label does not exist in the repo, causing `gh pr edit --add-label` to fail | Low | Med | Create the label in the workflow with `gh label create --force` before applying; `--force` is a no-op when the label already exists |
| Guard workflow uses a commit status API that requires a SHA, which is unavailable in certain PR event contexts | Low | High | Use `gh pr comment`-based approach or the GitHub Checks API with `github.event.pull_request.head.sha` — always available in `pull_request` events |
| Downstream repos have customised the reviewer-loop script's summary format | Low | Med | Guard matches on the same two-marker combination already used by `pr-review-loop.sh` itself (lines 3335–3337); downstream repos that fork the script must keep the markers |
| `actionlint` is not available in the CI runner or locally, blocking the acceptance criterion | Low | Low | `actionlint` is available as a standalone binary via `brew install actionlint` locally, and via `docker run rhysd/actionlint:latest` in CI; the implementation step documents the invocation |

---

## Code Samples

```yaml
# apply-regression-label.yml — Illustrative — adapt during implementation
name: Apply ready-for-regression label

on:
  pull_request:
    types: [opened, reopened, ready_for_review, synchronize]

concurrency:
  group: apply-regression-label-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  apply-label:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - name: Apply ready-for-regression label for implementation branches
        env:
          GH_TOKEN: ${{ github.token }}
          BRANCH: ${{ github.head_ref }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          REPO: ${{ github.repository }}
          # Override IN_SCOPE_PREFIXES in your repository to customise which branches
          # receive the label. Default covers the four standard implementation prefixes.
          IN_SCOPE_PREFIXES: "feature/ fix/ refactor/ hotfix/"
        run: |
          # Check whether the branch matches any in-scope prefix
          in_scope=false
          for prefix in $IN_SCOPE_PREFIXES; do
            if [[ "$BRANCH" == "${prefix}"* ]]; then
              in_scope=true
              break
            fi
          done
          if [ "$in_scope" = "false" ]; then
            echo "Branch '$BRANCH' is not in scope — skipping label."
            exit 0
          fi
          # Ensure the label exists (idempotent)
          gh label create "ready-for-regression" \
            --repo "$REPO" --color "e4e669" \
            --description "PR is ready for regression testing" \
            --force || true
          # Apply the label (idempotent via --add-label)
          gh pr edit "$PR_NUMBER" \
            --repo "$REPO" \
            --add-label "ready-for-regression"
          echo "Label 'ready-for-regression' applied to PR #${PR_NUMBER}."
```

```yaml
# reviewer-loop-guard.yml — Illustrative — adapt during implementation
name: Reviewer-loop completion guard

on:
  pull_request:
    types: [opened, reopened, ready_for_review, synchronize]

concurrency:
  group: reviewer-loop-guard-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  guard:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: read
      statuses: write
    steps:
      - name: Check for Automated Reviewer Loop Summary comment
        env:
          GH_TOKEN: ${{ github.token }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          REPO: ${{ github.repository }}
          HEAD_SHA: ${{ github.event.pull_request.head.sha }}
          BRANCH: ${{ github.head_ref }}
          IN_SCOPE_PREFIXES: "feature/ fix/ refactor/ hotfix/"
        run: |
          # Check whether the branch matches any in-scope prefix
          in_scope=false
          for prefix in $IN_SCOPE_PREFIXES; do
            if [[ "$BRANCH" == "${prefix}"* ]]; then
              in_scope=true
              break
            fi
          done
          if [ "$in_scope" = "false" ]; then
            echo "Branch '$BRANCH' is not in scope — skipping guard check (pass)."
            gh api \
              --method POST \
              "repos/$REPO/statuses/$HEAD_SHA" \
              -f state="success" \
              -f description="Not an implementation branch; check skipped." \
              -f context="Reviewer-loop completion guard"
            exit 0
          fi

          MARKER1="### Automated Reviewer Loop Summary"
          MARKER2="*Posted automatically by \`pr-review-loop.sh\`.*"

          FOUND=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" \
            --paginate \
            --jq '[.[] | select(
              (.body // "" | contains("### Automated Reviewer Loop Summary")) and
              (.body // "" | contains("*Posted automatically by `pr-review-loop.sh`.*"))
            )] | length')

          if [ "${FOUND:-0}" -gt 0 ]; then
            STATE="success"
            DESCRIPTION="Reviewer-loop summary present."
          else
            STATE="failure"
            DESCRIPTION="No reviewer-loop summary found. Run the automated reviewer loop before merging."
          fi

          gh api \
            --method POST \
            "repos/$REPO/statuses/$HEAD_SHA" \
            -f state="$STATE" \
            -f description="$DESCRIPTION" \
            -f context="Reviewer-loop completion guard"
```

---

## Implementation Order

1. **Confirm the `ready-for-regression` label exists in the repository** (or let the workflow create it): verify with `gh label list --repo <repo> | grep ready-for-regression`. Note the current label color/description for the idempotent `gh label create --force` call.

2. **Create `.github/workflows/apply-regression-label.yml`**: implement the workflow based on the code sample above. Key requirements:
   - Trigger on `pull_request` types: `opened`, `reopened`, `ready_for_review`, `synchronize`.
   - Read `IN_SCOPE_PREFIXES` from an env var (defaulting to `feature/ fix/ refactor/ hotfix/`) to allow downstream override.
   - Call `gh label create --force` before `gh pr edit --add-label` so the label always exists.
   - Use `pull-requests: write` permission (minimum required).
   - Pin `actions/checkout` to the same SHA used in other workflows (`93cb6efe18208431cddfb8368fd83d5badbf9bfd`) if a checkout step is needed (the label workflow does not need checkout — the `gh` CLI uses the repo slug from `${{ github.repository }}`).
   - Add a `concurrency` group keyed on the PR number (`apply-regression-label-${{ github.event.pull_request.number }}`) with `cancel-in-progress: true` to avoid race conditions when multiple events fire in quick succession.

3. **Create `.github/workflows/reviewer-loop-guard.yml`**: implement the workflow based on the code sample above. Key requirements:
   - Trigger on `pull_request` types: `opened`, `reopened`, `ready_for_review`, `synchronize`.
   - Scope to in-scope implementation branch prefixes only (same `IN_SCOPE_PREFIXES` check as the label workflow — branches outside scope always pass).
   - Fetch all PR comments via `gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate`.
   - Match comments that contain **both** `### Automated Reviewer Loop Summary` and `*Posted automatically by \`pr-review-loop.sh\`.*` (same two-marker combination used in `pr-review-loop.sh` line 3335).
   - Post a GitHub commit status on `HEAD_SHA` (`${{ github.event.pull_request.head.sha }}`): `success` when found, `failure` when absent.
   - Use context string `"Reviewer-loop completion guard"` so downstream repos can add it to branch protection as a required check by name.
   - Use `pull-requests: read` and `statuses: write` permissions (minimum required).
   - Add a `concurrency` group keyed on the PR number (`reviewer-loop-guard-${{ github.event.pull_request.number }}`) with `cancel-in-progress: true`.

4. **Create `docs/workflow/development-workflow/integrations/ci-enforcement.md`**: write a new integration doc that covers:
   - What the two CI workflows do and when they run.
   - Default in-scope branch prefixes (`feature/`, `fix/`, `refactor/`, `hotfix/`).
   - How downstream repos override the prefix list (override the `IN_SCOPE_PREFIXES` environment variable in the workflow file, or fork and edit the `pull_request` trigger/scope logic).
   - How to add `"Reviewer-loop completion guard"` to branch protection as a required status check (Settings → Branches → Branch protection rules → Require status checks to pass → search for the check name).
   - A note that `ready-for-regression` label auto-creation is idempotent; no manual label setup is required.

5. **Cross-section consistency self-check**: confirm that the `IN_SCOPE_PREFIXES` default value, the context string `"Reviewer-loop completion guard"`, and the two-marker combination are consistent between the workflow files, the code samples in this plan, and the integration doc.

6. **Pre-commit lint check**: run `markdownlint-cli2` on the plan file and the smoke test runbook before staging:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260515162721_613-enforce-regression-label-and-reviewer-loop-via-ci/2_613-enforce-regression-label-and-reviewer-loop-via-ci_implementation-plan.md" \
     "docs/testing/workflow/613-enforce-regression-label-and-reviewer-loop-via-ci.smoke-test.md"
   ```

7. **Validate workflow YAML syntax**: run `actionlint` on both new workflow files:

   ```bash
   # If actionlint is installed locally:
   actionlint .github/workflows/apply-regression-label.yml .github/workflows/reviewer-loop-guard.yml

   # Fallback via Docker if actionlint is not installed:
   docker run --rm -v "$(pwd):/repo" rhysd/actionlint:latest \
     /repo/.github/workflows/apply-regression-label.yml \
     /repo/.github/workflows/reviewer-loop-guard.yml
   ```

   Fix any reported issues before committing.

8. **Commit and push**: stage the three new implementation files:
   - `.github/workflows/apply-regression-label.yml`
   - `.github/workflows/reviewer-loop-guard.yml`
   - `docs/workflow/development-workflow/integrations/ci-enforcement.md`

9. **Verify smoke test runbook**: execute the runbook steps against a test PR (or fixture PR in this repo) to confirm:
   - A `feature/*` PR receives the `ready-for-regression` label automatically.
   - The guard check fails on a PR with no reviewer-loop summary.
   - The guard check passes after `pr-review-loop.sh` posts its summary comment.

10. **Update project docs per Documentation Updates section**: as noted above, no post-implementation project doc updates are required beyond the `ci-enforcement.md` file created in Step 4.

11. **Update `CHANGELOG.md`** under `[Unreleased]`:

    ```markdown
    - **Enforce ready-for-regression label and reviewer-loop handoff via CI** (#613): add two GitHub Actions workflows — one that auto-applies the `ready-for-regression` label to implementation PRs based on branch prefix, and one that asserts the automated reviewer-loop summary comment is present before a PR can be treated as merge-eligible.
    ```
