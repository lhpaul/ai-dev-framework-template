# Smoke Test Runbook: Enforce Ready-for-Regression Label and Reviewer-Loop Handoff via CI

**Feature**: Enforce ready-for-regression label and reviewer-loop handoff via CI/GitHub Actions
**Spec**: [1\_613-enforce-regression-label-and-reviewer-loop-via-ci\_specs.md](../../specs/developments/20260515162721_613-enforce-regression-label-and-reviewer-loop-via-ci/1_613-enforce-regression-label-and-reviewer-loop-via-ci_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The two new GitHub Actions workflows are merged to `develop` (or to the branch under test).
- [ ] You have a GitHub repository with the workflows active (can be this repository or a downstream fork).
- [ ] You have a local checkout of the repository with `gh` CLI authenticated.
- [ ] No pre-existing open PRs from the fixture branches listed below are open on the repo.

---

## Test Data

| Item | Value |
| --- | --- |
| In-scope fixture branch | `fix/613-smoke-test-fixture` |
| Out-of-scope fixture branch | `spec/613-smoke-test-fixture` |
| Target branch for fixture PRs | `develop` |
| Label to verify | `ready-for-regression` |
| Guard check name | `Reviewer-loop completion guard (#<PR_NUMBER>)` (PR-number-scoped) |

---

## Smoke Test Steps

### Step 1: Create an in-scope fixture PR (implementation branch)

1. From `develop`, create a temporary fixture branch:

   ```bash
   git checkout -b fix/613-smoke-test-fixture develop
   git commit --allow-empty -m "chore: smoke test fixture for #613"
   git push -u origin fix/613-smoke-test-fixture
   ```

2. Open a draft PR targeting `develop`:

   ```bash
   gh pr create \
     --base develop \
     --head fix/613-smoke-test-fixture \
     --title "chore: smoke test fixture for #613 CI enforcement" \
     --body "Smoke test fixture PR — delete after verification." \
     --draft
   ```

3. Note the PR number:

   ```bash
   PR_NUM=$(gh pr view --json number --jq '.number')
   ```

**Expected result after CI runs**:

- The `apply-regression-label` workflow completes successfully.
- `gh pr view "$PR_NUM" --json labels --jq '.labels[].name'` includes `ready-for-regression`.
- **Maps to**: Acceptance Criterion #1 (opening an implementation PR applies the label).

---

### Step 2: Verify the reviewer-loop guard fails on the new PR

1. Wait for the `reviewer-loop-guard` workflow run to complete on the fixture PR.
2. Check the commit status:

   ```bash
   HEAD_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid')
   gh api "repos/$(gh repo view --json nameWithOwner --jq '.nameWithOwner')/commits/$HEAD_SHA/statuses" \
     --jq "[.[] | select(.context | startswith(\"Reviewer-loop completion guard (#\"))] | first | {state, description}"
   ```

**Expected result**:

- `state` is `"failure"`.
- `description` mentions that no reviewer-loop summary was found.
- **Maps to**: Acceptance Criterion #5 (guard fails when no summary comment is present).

---

### Step 3: Verify a draft-to-non-draft conversion still carries the label

1. Convert the fixture PR to non-draft:

   ```bash
   gh pr ready "$PR_NUM"
   ```

2. Check labels after CI runs:

   ```bash
   gh pr view "$PR_NUM" --json labels --jq '.labels[].name'
   ```

**Expected result**:

- `ready-for-regression` is still present (or reapplied by the `ready_for_review` trigger).
- **Maps to**: Acceptance Criterion #3 (converting a draft PR results in the label being present).

---

### Step 4: Simulate the reviewer-loop summary comment

1. Post a synthetic summary comment that matches the canonical marker:

   ```bash
   gh pr comment "$PR_NUM" --body "### Automated Reviewer Loop Summary

**Result:** CLEAN
**Platforms:** pr-agent, coderabbit
**Findings:** 0 blocking, 0 suggestions

*Posted automatically by \`pr-review-loop.sh\`.*"
   ```

2. Wait for the guard's `issue_comment` event path to complete, then re-check
   the commit status:

   ```bash
   HEAD_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid')
   gh api "repos/$(gh repo view --json nameWithOwner --jq '.nameWithOwner')/commits/$HEAD_SHA/statuses" \
     --jq "[.[] | select(.context | startswith(\"Reviewer-loop completion guard (#\"))] | first | {state, description}"
   ```

**Expected result**:

- `state` is `"success"`.
- `description` indicates the reviewer-loop summary is present.
- No extra push is required; the summary comment event refreshes readiness for
  the current PR head SHA.
- **Maps to**: Acceptance Criterion #6 (guard passes once the summary comment is present).

---

### Step 5: Verify the guard re-evaluates on every push

1. Push another empty commit to trigger `synchronize` and force guard re-evaluation:

   ```bash
   git commit --allow-empty -m "chore: second push to verify guard re-evaluation"
   git push
   ```

2. Wait for the `reviewer-loop-guard` workflow to complete.

3. Check the guard status on the new SHA:

   ```bash
   HEAD_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid')
   gh api "repos/$(gh repo view --json nameWithOwner --jq '.nameWithOwner')/commits/$HEAD_SHA/statuses" \
     --jq "[.[] | select(.context | startswith(\"Reviewer-loop completion guard (#\"))] | first | {state, description}"
   ```

**Expected result**:

- A new status is posted quickly for the new `HEAD_SHA` under context `Reviewer-loop completion guard (#<PR_NUMBER>)`.
- `state` reflects whether the canonical summary comment is present on the PR at evaluation time.
- **Maps to**: Acceptance Criterion #7 (guard re-evaluates on every push).

---

### Step 6: Verify an out-of-scope branch does NOT receive the label

1. Create a second fixture branch with an out-of-scope prefix:

   ```bash
   git checkout -b spec/613-smoke-test-fixture develop
   git commit --allow-empty -m "chore: out-of-scope smoke test fixture for #613"
   git push -u origin spec/613-smoke-test-fixture
   ```

2. Open a draft PR:

   ```bash
   gh pr create \
     --base develop \
     --head spec/613-smoke-test-fixture \
     --title "chore: out-of-scope fixture for #613 CI enforcement" \
     --body "Smoke test fixture PR — delete after verification." \
     --draft
   ```

3. Note this PR number:

   ```bash
   PR_NUM_2=$(gh pr view --json number --jq '.number')
   ```

4. After CI runs:

   ```bash
   gh pr view "$PR_NUM_2" --json labels --jq '.labels[].name'
   ```

**Expected result**:

- `ready-for-regression` is NOT in the label list.
- The `apply-regression-label` workflow run completed successfully (not a workflow error).
- **Maps to**: Acceptance Criterion #2 (out-of-scope branches do not receive the label).

---

### Step 7: Verify idempotency (label already present)

1. Manually add the `ready-for-regression` label to the fixture PR (`$PR_NUM`):

   ```bash
   gh pr edit "$PR_NUM" --add-label "ready-for-regression"
   ```

2. Push another empty commit to trigger the `apply-regression-label` workflow:

   ```bash
   git checkout fix/613-smoke-test-fixture
   git commit --allow-empty -m "chore: idempotency test"
   git push
   ```

3. After CI runs, check labels and the workflow run result:

   ```bash
   gh pr view "$PR_NUM" --json labels --jq '.labels[].name'
   # Also check the workflow run for "Label 'ready-for-regression' already present" log message
   ```

**Expected result**:

- The label is still present (not duplicated, not removed by the apply workflow).
- The workflow run exit code is 0 (no failure on duplicate label).
- **Maps to**: Acceptance Criterion #4 (workflow is idempotent when label is already present).

---

### Last Step: Clean up fixture PRs and branches

1. Close and delete the fixture PRs:

   ```bash
   gh pr close "$PR_NUM" --delete-branch
   gh pr close "$PR_NUM_2" --delete-branch
   ```

2. If branches were not deleted automatically:

   ```bash
   git switch develop
   git push origin --delete fix/613-smoke-test-fixture
   git push origin --delete spec/613-smoke-test-fixture
   git branch -d fix/613-smoke-test-fixture spec/613-smoke-test-fixture
   ```

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] **AC #1**: Opening a PR from `fix/613-smoke-test-fixture` caused `ready-for-regression` to be applied automatically without any agent or human action.
- [ ] **AC #2**: Opening a PR from `spec/613-smoke-test-fixture` did not result in `ready-for-regression` being applied.
- [ ] **AC #3**: Converting the draft implementation PR to non-draft resulted in the label being present.
- [ ] **AC #4**: Re-running the PR policy workflow when the label was already present completed without failure and without duplicating the label.
- [ ] **AC #5**: The implementation PR with no reviewer-loop summary comment showed a failing `Reviewer-loop completion guard (#<PR_NUMBER>)` check.
- [ ] **AC #6**: After posting the canonical summary comment, the guard check transitioned to passing.
- [ ] **AC #7**: A subsequent push caused the guard to re-evaluate and post a fresh status on the new SHA.
- [ ] **AC #9** (defer to CI): The PR policy workflow passes `actionlint` with no new warnings (verified in the implementation PR's CI run).
- [ ] **AC #10** (defer to CI): The PR policy workflow declares only the minimum permissions required (`issues: read`, `pull-requests: write`, and `statuses: write`).

---

## Seed Data Reference

No seed data is required. The smoke test uses fixture branches and PRs created inline.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| PR policy workflow fails with "Label not found" | The `ready-for-regression` label does not exist in the repo and label creation was not included | Verify the workflow includes the `gh label create` step before `gh pr edit --add-label` |
| Guard workflow fails with a GitHub API error instead of a status check | `statuses: write` permission missing from the workflow | Add `statuses: write` under `permissions` in `pr-policy.yml` |
| Guard reports "failure" even after posting the summary comment | Comment body does not contain both required markers, or the `issue_comment` workflow did not run | Confirm the comment contains exactly `### Automated Reviewer Loop Summary` and `*Posted automatically by \`pr-review-loop.sh\`.*`; inspect the guard workflow run for the comment event |
| Out-of-scope branch (`spec/*`) receives the label | `IN_SCOPE_PREFIXES` env var contains an unexpected value | Check the env var default in `pr-policy.yml`; ensure `spec/` is not included |
| `actionlint` reports warnings on the workflow file | YAML syntax issue or unsupported action reference | Fix the reported lines; re-run `actionlint` |

---

## Known Limitations

- The guard check uses the GitHub Commit Statuses API (not Checks API). Some branch protection UIs surface statuses and checks in separate sections. Downstream maintainers must search for `Reviewer-loop completion guard (#<PR_NUMBER>)` in the "Statuses" section, not only under "GitHub Actions checks", when configuring branch protection. Because the context name includes the PR number, wildcard matching (e.g. via GitHub Rulesets) is required to enforce it as a required status check.
- The smoke test steps require a repository where the workflows are active. This runbook cannot be executed entirely offline.
- Fork-head PRs are skipped by the PR policy workflow and do not receive guard
  statuses or implementation-only label mutations from this workflow.
