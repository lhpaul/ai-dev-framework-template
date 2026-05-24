# Smoke Test Runbook: Claude Code Action PR-Review GHA Workflow

**Feature**: Claude Code Action PR-Review GHA Workflow (#706)
**Spec**: [1_706-claude-code-action-gha-workflow_specs.md](../../specs/developments/20260523130055_706-claude-code-action-gha-workflow/1_706-claude-code-action-gha-workflow_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The `claude-code-review.yml` workflow file is merged into the target branch
- [ ] The `ANTHROPIC_API_KEY` secret is configured in the repository's GitHub Actions secrets
- [ ] You have write access to the repository (to trigger `workflow_dispatch`)
- [ ] The `gh` CLI is installed and authenticated: `gh auth status`
- [ ] At least one open pull request exists on the repository; note its PR number

---

## Test Data

| Item | Value |
| --- | --- |
| Target PR number | Any open PR number (e.g., the plan PR for this issue) |
| Repository | `lhpaul/ai-dev-framework-template` |
| Workflow file | `.github/workflows/claude-code-review.yml` |
| Expected model | `claude-sonnet-4-6` |

---

## Smoke Test Steps

### Step 1: Verify workflow file exists and is listed

- Run:
  ```bash
  gh workflow list --repo lhpaul/ai-dev-framework-template
  ```
- Confirm: `Claude Code Action PR Review` appears in the list with status `active`

**Expected result**: The workflow is listed and active. If the workflow is not listed, confirm the file is on the default branch of the repository.

### Step 2: Inspect workflow structure for spec compliance

- Run:
  ```bash
  cat .github/workflows/claude-code-review.yml
  ```
- Confirm each of the following:
  1. The `on:` section contains only `workflow_dispatch` (no `pull_request`, `push`, or `issue_comment`)
  2. The `workflow_dispatch.inputs.pr_number` field has `required: true`
  3. The `concurrency.group` is keyed on `inputs.pr_number` (not `github.event.pull_request.number`)
  4. The `permissions` block contains exactly `pull-requests: write` and `contents: read`
  5. The `uses:` line for the action is pinned to a specific version tag or commit SHA (not `main` or `latest`)
  6. The `env.ANTHROPIC_API_KEY` is set via `${{ secrets.ANTHROPIC_API_KEY }}` and is not echoed or printed
  7. Inline comments are present explaining the model choice and free compute minutes

**Maps to**: BR-1, BR-2, BR-3, BR-5, BR-7, BR-8; AC: workflow file exists, `permissions` block, `concurrency` group, pinned action ref, inline comments

**Expected result**: All seven structural checks pass. Flag any that do not.

### Step 3: Trigger workflow dispatch manually and observe run

- Choose an open PR number (e.g., `<PR_NUMBER>`).
- Run:
  ```bash
  gh workflow run claude-code-review.yml -f pr_number=<PR_NUMBER>
  ```
- Confirm: the command exits with status 0 and prints no error.
- Poll for run completion:

  ```bash
  gh run list --workflow claude-code-review.yml --limit 1
  ```

  Wait for the run status to show `completed` (may take 30–120 seconds depending on PR size).

**Maps to**: UC-1, UC-2; BR-3, BR-4; AC: workflow triggers on `workflow_dispatch`; maintainer can trigger via `gh workflow run`

**Expected result**: The workflow run is created and completes. The run appears in `gh run list`.

### Step 4: Verify review comment posted on the PR

- Run:
  ```bash
  gh pr view <PR_NUMBER> --comments
  ```
- Confirm: a review comment from the Claude Code Action bot appears on the PR.

**Maps to**: UC-1 Postconditions; AC: Claude reviews the PR and posts comments

**Expected result**: At least one review comment (inline or summary thread) posted by the `claude-code-action` bot is visible on the target PR.

### Step 5: Verify model in run logs

- Get the run ID from Step 3:
  ```bash
  gh run list --workflow claude-code-review.yml --limit 1 --json databaseId --jq '.[0].databaseId'
  ```
- Run:
  ```bash
  gh run view <run-id> --log | grep -i "sonnet\|claude-sonnet-4-6\|model"
  ```
- Confirm: the log mentions `claude-sonnet-4-6` as the model used.

**Maps to**: BR-2; AC: model set to `claude-sonnet-4-6` as default

**Expected result**: The run log references `claude-sonnet-4-6` as the model. If the action does not log the model name explicitly, confirm by inspecting the workflow file `model:` input.

### Step 6: Verify secret is not logged

- Run:
  ```bash
  gh run view <run-id> --log | grep -i "ANTHROPIC_API_KEY\|sk-ant-"
  ```
- Confirm: the raw secret value (starting with `sk-ant-`) does not appear in the logs. The variable name `ANTHROPIC_API_KEY` may appear in logs as a reference but must not expose the secret value.

**Maps to**: BR-8; AC: `ANTHROPIC_API_KEY` is not stored or logged

**Expected result**: The secret value does not appear in the run logs.

### Step 7: Verify workflow does not auto-trigger on PR events

- Push a trivial change to a branch with an open PR (or observe an existing PR push).
- Confirm: `gh run list --workflow claude-code-review.yml --limit 5` does not show a new run triggered automatically by the push event (no run should appear with trigger `push`).

**Maps to**: BR-7; AC: workflow does not trigger automatically on PR open/push/synchronize

**Expected result**: No automatic run is triggered. Only `workflow_dispatch` events start the workflow.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Workflow file exists at `.github/workflows/claude-code-review.yml` (or equivalent clearly-named file)
- [ ] Workflow triggers exclusively on `workflow_dispatch` with a required `pr_number` input
- [ ] `anthropics/claude-code-action@v1` is invoked with `model: claude-sonnet-4-6`
- [ ] Authentication is via `ANTHROPIC_API_KEY` only; no other Anthropic credential is referenced
- [ ] `permissions` block grants `pull-requests: write` and `contents: read` (no broader grants)
- [ ] `concurrency` group is keyed on the PR number to prevent duplicate simultaneous runs
- [ ] Action `uses:` reference is pinned to a specific version tag or commit SHA
- [ ] Inline comments document: Sonnet 4.6 model rationale and that public-repo Actions minutes are free
- [ ] Maintainer can manually trigger via `gh workflow run claude-code-review.yml -f pr_number=<N>`
- [ ] Review comment appears on the target PR after a successful run
- [ ] Workflow does not trigger automatically on PR open, push, or synchronize events

---

## Seed Data Reference

The following resources must be present before the smoke test:

| Entity | Scenario | How to set up |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` secret | Valid Anthropic API key | Set in GitHub repo settings → Secrets → Actions |
| Open pull request | Any open PR to use as the review target | Create with `gh pr create` or use an existing open PR |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `gh workflow run` exits non-zero with "workflow not found" | Workflow file not on the repository default branch | Merge the implementation PR, then retry |
| Run completes but no review comment appears on the PR | `ANTHROPIC_API_KEY` secret is not set or is invalid | Set the secret in repository settings; check run logs for auth errors |
| Run fails with "Input required and not supplied: pr_number" | `required: true` was not set on the input in the workflow YAML | Verify the `pr_number` input has `required: true` |
| Run log shows model other than `claude-sonnet-4-6` | `model` input not passed to the action, or action default changed | Confirm `model: claude-sonnet-4-6` is in the `with:` block |
| Workflow auto-triggers on PR push | `pull_request` trigger accidentally added to `on:` | Remove any `pull_request` or `push` entries from the `on:` section |

---

## Known Limitations

- The smoke test requires a live `ANTHROPIC_API_KEY` secret; it cannot be run in environments without access to Anthropic's API.
- The `gh run view --log` step may require a brief wait after the run completes before logs are fully indexed by GitHub's API.
- Run time varies depending on PR diff size; allow up to 3 minutes for a standard-sized PR.
