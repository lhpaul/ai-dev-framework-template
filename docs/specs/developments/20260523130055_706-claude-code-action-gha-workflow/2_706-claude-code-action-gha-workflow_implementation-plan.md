# Claude Code Action PR-Review GHA Workflow — Implementation Plan

**Spec**: [1_706-claude-code-action-gha-workflow_specs.md](./1_706-claude-code-action-gha-workflow_specs.md)
**Smoke test runbook**: [docs/testing/workflow/706-claude-code-action-gha-workflow.smoke-test.md](../../../testing/workflow/706-claude-code-action-gha-workflow.smoke-test.md)

---

## Summary

**Approach**: Create a single GitHub Actions workflow file at `.github/workflows/claude-code-review.yml` that is triggered exclusively by `workflow_dispatch` with a required `pr_number` input. The workflow invokes `anthropics/claude-code-action@v1` pointed at that PR, authenticates via `ANTHROPIC_API_KEY`, uses `claude-sonnet-4-6` as the default model, and follows all existing GHA conventions in this repository (pinned action refs, explicit `permissions` block, `concurrency` group keyed on PR number).

**Estimated complexity**: S

**Rationale**: The change is a single new YAML file with no schema changes, no backend logic, and no dependency on other items in this batch beyond what the spec already defines. The workflow itself is thin: it delegates all review logic to the `anthropics/claude-code-action@v1` action. The only design decisions are YAML-level: trigger type, permissions, concurrency group, input validation, and model selection.

**Dependencies**: None. This workflow is self-contained. Issues #705, #707, and #708 (runner integration, docs, and config reslotting) are sibling items that depend on this one, but this item has no upstream dependency.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `0e984a7` |
| Existing workflow files | `ls .github/workflows/` | `apply-regression-label.yml`, `auto-tag-release.yml`, `deploy.yml`, `e2e-regression.yml`, `markdown-lint.yml`, `pr-agent.yml`, `remove-regression-label-on-push.yml`, `reviewer-loop-guard.yml`, `shellcheck.yml`, `test-pr-review-loop.yml`, `update-tracker-on-merge.yml` |
| Existing claude-code-action references | `grep -r "anthropics/claude-code-action" .github/` | 0 matches — no existing workflow |
| Target filename conflict | `ls .github/workflows/claude-code-review.yml` | File does not exist |
| Concurrency pattern used in existing workflows | `grep -A1 "concurrency:" .github/workflows/reviewer-loop-guard.yml` | `group: reviewer-loop-guard-${{ github.event.pull_request.number }}` |
| Permissions pattern used in existing workflows | `grep -A3 "permissions:" .github/workflows/reviewer-loop-guard.yml` | `pull-requests: read`, `statuses: write` |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Create `.github/workflows/claude-code-review.yml` — new GitHub Actions workflow file with the following structure:
  - `name`: `Claude Code Action PR Review`
  - `on`: `workflow_dispatch` only, with a required input `pr_number` (type: `number`, description: `Pull request number to review`)
  - `concurrency`: group `claude-code-review-${{ inputs.pr_number }}`, `cancel-in-progress: true`
  - `permissions`: `pull-requests: write`, `contents: read`
  - `jobs.review`: runs on `ubuntu-latest`
  - Single step: `uses: anthropics/claude-code-action@v1` with inputs pinned to the action's latest release tag at plan-write time (implementer must pin to the current SHA or version tag from <https://github.com/anthropics/claude-code-action/releases>), `env.ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}`, and model defaulting to `claude-sonnet-4-6`
  - Inline YAML comments documenting: (a) Sonnet 4.6 model rationale (cost vs. quality), (b) that public-repo Actions minutes are free so per-invocation compute cost is zero

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. Workflow exists and is syntactically valid: confirm `gh workflow list` shows the workflow as available. (Maps to AC: workflow file exists)
2. Workflow dispatch with a valid PR number: run `gh workflow run claude-code-review.yml -f pr_number=<N>`, poll for completion, and confirm a review comment appears on PR `<N>`. (Maps to AC: workflow triggers on `workflow_dispatch` with `pr_number`; Claude reviews the PR)
3. Model is Sonnet 4.6: inspect the workflow run logs via `gh run view <run-id> --log` to confirm the model used is `claude-sonnet-4-6`. (Maps to AC: model set to `claude-sonnet-4-6`)
4. Authentication only via `ANTHROPIC_API_KEY`: confirm no other Anthropic credential is referenced in the workflow file. (Maps to BR-1 and AC: authentication via `ANTHROPIC_API_KEY` only)
5. Permissions block present and minimal: verify `permissions` block grants `pull-requests: write` and `contents: read` and no broader grants. (Maps to AC: `permissions` block with minimum required permissions)
6. Concurrency group present: verify `concurrency.group` is keyed on `inputs.pr_number` to prevent duplicate simultaneous runs. (Maps to AC: `concurrency` group keyed on PR number)
7. Action ref is pinned: confirm the `uses:` line references a specific version tag or SHA, not a floating `main` or `latest`. (Maps to AC: action reference is pinned)
8. Workflow does not trigger on PR events: confirm the workflow only lists `workflow_dispatch` in its `on` section. (Maps to AC: workflow does not trigger automatically on PR open/push/synchronize)
9. Manual dispatch by maintainer: a maintainer with write access can trigger the workflow via `gh workflow run` or the GitHub Actions tab without any secrets beyond `ANTHROPIC_API_KEY`. (Maps to Use Case 2)

**Smoke test runbook**: `docs/testing/workflow/706-claude-code-action-gha-workflow.smoke-test.md`

---

## Seed Data

No database seed data required. The smoke test requires:

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Open pull request on the repository | Any open PR against `develop-claude-review-platform` (or `develop`); note the PR number | Created ad hoc or use an existing open PR during test run |
| `ANTHROPIC_API_KEY` secret | Set in GitHub repository secrets before running | GitHub repository settings |

---

## Documentation Updates

None. This item ships the workflow file only. Documentation for integrating `claude-code-action` with `pr-review-loop.sh` is covered by sibling issue #707. No files in `docs/project/`, `docs/best-practices/`, or `AGENTS.md` need updating for this item alone.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| `anthropics/claude-code-action@v1` API changes before the implementation PR merges | Low | Med | Pin to a specific SHA or version tag at implementation time; update the pin if the action releases a breaking change before merge |
| `ANTHROPIC_API_KEY` secret is not set in the repository | Low | High | Document the secret requirement in the workflow file's comments and in the smoke test prerequisites; the workflow fails fast with a clear error if the secret is absent |
| Concurrency group does not prevent simultaneous runs for the same PR | Low | Low | Use `inputs.pr_number` (not `github.event.pull_request.number`, which is unavailable on `workflow_dispatch`) as the concurrency group key |
| `pr_number` input is optional or accepts invalid values | Low | Med | Declare the input as `required: true` in the YAML; `anthropics/claude-code-action@v1` will fail fast if given an invalid PR number |
| Workflow triggers accidentally on push or PR events | Low | Med | The `on:` section must list only `workflow_dispatch`; include this as a verification step in the smoke test |

---

## Code Samples

> All samples below are illustrative — adapt during implementation.

```yaml
# Illustrative — adapt during implementation
name: Claude Code Action PR Review

on:
  # Triggered on demand by pr-review-loop.sh or a repository maintainer.
  # Not triggered automatically on PR open, push, or synchronize events.
  workflow_dispatch:
    inputs:
      pr_number:
        description: "Pull request number to review"
        required: true
        type: number

# Prevent duplicate simultaneous runs for the same PR.
# uses inputs.pr_number (not github.event.pull_request.number,
# which is unavailable on workflow_dispatch events).
concurrency:
  group: claude-code-review-${{ inputs.pr_number }}
  cancel-in-progress: true

jobs:
  review:
    name: Claude Code Action review
    runs-on: ubuntu-latest

    # Minimum permissions required:
    #   pull-requests: write — to post review comments on the PR
    #   contents: read — to read the repository checkout during review
    permissions:
      pull-requests: write
      contents: read

    steps:
      - name: Run Claude Code Action PR review
        # Pin to a specific version tag or commit SHA (never 'main' or 'latest').
        # Check https://github.com/anthropics/claude-code-action/releases for the
        # current release tag and update this ref at implementation time.
        uses: anthropics/claude-code-action@v1  # pin to SHA at implementation time
        with:
          pr_number: ${{ inputs.pr_number }}
          # Default model: claude-sonnet-4-6
          # Rationale: Sonnet 4.6 is Anthropic's recommended CI review model.
          # It provides adequate review quality at ~1/5 the token cost of Opus.
          # Model selection is fixed for v1; size-based routing is out of scope
          # (see issue #706 Out of Scope section).
          model: claude-sonnet-4-6
        env:
          # Authenticate exclusively via the repository secret ANTHROPIC_API_KEY.
          # No other Anthropic credential (OAuth, personal token) is used.
          # Public-repo Actions minutes are free; the only cost is token consumption
          # (~$0.30 per review pass with claude-sonnet-4-6).
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

---

## Implementation Order

1. **Look up the current `anthropics/claude-code-action` release tag or SHA**: Visit <https://github.com/anthropics/claude-code-action/releases> or run `gh release view --repo anthropics/claude-code-action` to get the latest stable version tag (e.g., `v1.0.3`) and its corresponding commit SHA. Record both for use in the `uses:` line.

2. **Create `.github/workflows/claude-code-review.yml`** using the illustrative sample above as a starting point. Substitute the actual version tag and/or SHA into the `uses:` line. Confirm the file:
   - Has `on: workflow_dispatch` as the only trigger (no `pull_request`, `push`, or `issue_comment` entries)
   - Has a `concurrency.group` keyed on `inputs.pr_number`
   - Has a `permissions` block with exactly `pull-requests: write` and `contents: read`
   - Has `required: true` on the `pr_number` input
   - Passes the `pr_number` input and the `model: claude-sonnet-4-6` to the action's `with:` block
   - Sets `ANTHROPIC_API_KEY` as an environment variable (not an inline secret echo or script variable)
   - Contains inline comments explaining the model rationale and that public-repo compute minutes are free

3. **Run shellcheck on the workflow file** (only the shell `run:` steps, if any are added beyond the action step): `shellcheck --shell=bash .github/workflows/claude-code-review.yml` — the current design has no `run:` steps, so this may be a no-op. Verify there are no shell issues.

4. **Verify the workflow file is syntactically valid**: run `cat .github/workflows/claude-code-review.yml` and confirm the YAML parses without errors (use `python3 -c "import yaml, sys; yaml.safe_load(sys.stdin)" < .github/workflows/claude-code-review.yml` for a quick lint).

5. **Update `CHANGELOG.md`** under `[Unreleased]`:

   ```markdown
   - **Ship Claude Code Action PR-review GHA workflow** (#706): add `.github/workflows/claude-code-review.yml` that invokes `anthropics/claude-code-action@v1` as an on-demand PR reviewer triggered by `workflow_dispatch` with a `pr_number` input; uses `claude-sonnet-4-6` by default and authenticates via `ANTHROPIC_API_KEY`.
   ```

6. **Run the markdown lint pre-commit check** on the plan and smoke test runbook:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260523130055_706-claude-code-action-gha-workflow/2_706-claude-code-action-gha-workflow_implementation-plan.md" \
     "docs/testing/workflow/706-claude-code-action-gha-workflow.smoke-test.md"
   ```

   Fix any reported violations before committing.

7. **Verify smoke test runbook covers all acceptance criteria**: confirm each AC from the spec maps to at least one testable step in the runbook.
