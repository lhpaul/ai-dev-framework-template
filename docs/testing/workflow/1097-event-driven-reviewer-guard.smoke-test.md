# Smoke Test Runbook: Event-Driven Reviewer Guard Readiness

**Feature**: Event-Driven Reviewer Guard Readiness
**Spec**: `docs/specs/developments/20260630160033_1097-event-driven-reviewer-guard/1_1097-event-driven-reviewer-guard_specs.md`
**Plan**: `docs/specs/developments/20260630160033_1097-event-driven-reviewer-guard/2_1097-event-driven-reviewer-guard_implementation-plan.md`

---

## Purpose

Verify that reviewer-loop readiness no longer relies on a default long-polling
GitHub Actions job, while implementation pull requests still require the
canonical automated reviewer-loop summary before merge readiness.

---

## Preconditions

- A branch contains the implementation for #1097.
- The repository can run GitHub Actions and post PR comments/statuses.
- The tester has permission to open or inspect a scratch implementation pull
  request, or can run the shell/static test suite locally.

---

## Scenario 1: Missing summary fails quickly for in-scope branches

1. Open or inspect an implementation-branch pull request with no automated
   reviewer-loop summary comment.
2. Wait for the reviewer-loop guard workflow to complete.
3. Inspect the PR-scoped status context:

   ```bash
   gh api "repos/OWNER/REPO/commits/HEAD_SHA/status" \
     --jq '.statuses[] | select(.context | startswith("Reviewer-loop completion guard (#")) | {state, description, context}'
   ```

**Expected result**: The status is non-passing, the description says the
reviewer-loop summary is missing, and the workflow does not spend several
minutes sleeping by default.

---

## Scenario 2: Summary comment event posts readiness success

1. On the same pull request, post a comment containing the canonical reviewer-loop
   summary markers:

   ```markdown
   ### Automated Reviewer Loop Summary

   **Result:** clean - no blocking findings

   *Posted automatically by `pr-review-loop.sh`.*
   ```

2. Wait for the guard's comment-event path to complete.
3. Inspect the PR-scoped status context again.

**Expected result**: The status becomes passing for the pull request head SHA and
the description indicates the reviewer-loop summary is present.

---

## Scenario 3: Non-summary comments do not mark readiness

1. Push a new commit to the implementation pull request or otherwise inspect a
   pull request head without a valid summary status.
2. Post a normal PR comment that does not include the canonical summary markers.
3. Wait long enough for issue-comment workflows to enqueue if they are going to
   run.
4. Inspect the PR-scoped status context.

**Expected result**: The normal comment does not mark reviewer-loop readiness as
passing.

---

## Scenario 4: Existing summary passes on pull request events

1. Ensure the pull request contains a valid automated reviewer-loop summary
   comment for the current review state.
2. Rerun the guard workflow or trigger a pull request update.
3. Inspect the PR-scoped status context.

**Expected result**: The guard posts a passing status without default long
polling.

---

## Scenario 5: Out-of-scope branches remain fast and non-blocking

1. Open or inspect a spec or implementation-plan pull request.
2. Wait for the reviewer-loop guard workflow to complete.
3. Inspect the PR-scoped status context.

**Expected result**: The guard reports that the branch is not an implementation
branch and exits quickly with the existing non-blocking behavior.

---

## Scenario 6: Local tests cover guard behavior

1. Run the focused guard tests added by the implementation.
2. Run markdown and workflow shell validation.

**Expected result**: Tests cover missing-summary, summary-present,
summary-comment, non-summary comment, and out-of-scope scenarios.

---

## Acceptance Criteria Coverage

- [ ] AC1: Default reviewer-loop guard execution does not sleep or poll for
      several minutes on GitHub-hosted runners.
- [ ] AC2: Implementation pull requests with a valid reviewer-loop summary
      receive a passing readiness result.
- [ ] AC3: Implementation pull requests without a valid reviewer-loop summary do
      not receive a passing readiness result.
- [ ] AC4: Pull requests outside implementation branch scope complete the guard
      path quickly and preserve non-blocking semantics.
- [ ] AC5: The reviewer-loop summary marker remains the documented source of
      truth for readiness.
- [ ] AC6: Branch-protection and readiness documentation identifies the result
      downstream repositories should require.
- [ ] AC7: Tests cover missing-summary, summary-present, and out-of-scope branch
      cases.

---

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Missing-summary status remains after the summary comment is posted | The issue-comment workflow did not run or could not fetch the PR head SHA | Rerun the guard workflow and inspect the Actions logs for API failures. |
| A normal comment marks readiness passing | The comment-event path is not checking both canonical summary markers | Tighten marker matching and add a regression test for non-summary comments. |
| Out-of-scope branches fail the guard | Branch-prefix detection changed | Verify the configured in-scope prefixes and expected branch name. |
| Branch protection no longer recognizes the guard | Required status pattern points at an obsolete context | Use the documented `Reviewer-loop completion guard (#*)` pattern or repository-supported equivalent. |
