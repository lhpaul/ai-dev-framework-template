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

## Scenario 2: Summary fixture + workflow_dispatch posts readiness success

Comments no longer start `pr-policy.yml` (#1998). Post a current-head clean
summary fixture (both canonical markers plus history `head_sha` equal to the
live head), then dispatch the workflow explicitly.

1. On the same pull request, resolve the live head and post:

   ```bash
   set -euo pipefail
   HEAD_SHA=$(gh pr view "$PR_NUM" --json headRefOid --jq '.headRefOid')
   DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')
   BODY_FILE=$(mktemp)
   cat > "$BODY_FILE" <<EOF
### Automated Reviewer Loop Summary

**Result:** clean — no blocking findings

<details>

\`\`\`json
{"schema":"reviewer_loop_history.v1","entries":[{"head_sha":"${HEAD_SHA}"}]}
\`\`\`

</details>

*Posted automatically by \`pr-review-loop.sh\`.*
EOF
   gh pr comment "$PR_NUM" --body-file "$BODY_FILE"
   rm -f "$BODY_FILE"
   ```

2. Dispatch PR policy (the path `pr-review-loop.sh` uses after a real summary):

   ```bash
   gh workflow run pr-policy.yml \
     --ref "$DEFAULT_BRANCH" \
     -f "pr_number=${PR_NUM}"
   ```

3. Wait for that `workflow_dispatch` run to finish, then inspect the PR-scoped
   status context again.

**Expected result**: The status becomes passing for the pull request head SHA and
the description indicates the reviewer loop ran clean for the current head.

---

## Scenario 3: Ordinary comments do not start PR policy

1. Push a new commit to the implementation pull request or otherwise inspect a
   pull request head without a valid summary status.
2. Post a normal PR comment that does not include the canonical summary markers.
3. Confirm no new `pr-policy.yml` run is created for that comment (the workflow
   has no `issue_comment` trigger).
4. Inspect the PR-scoped status context.

**Expected result**: The normal comment does not start a PR policy runner and
does not mark reviewer-loop readiness as passing.

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

## Scenario 6: Fork-head pull requests are skipped by the guard

1. Open or inspect a pull request whose head repository differs from the base
   repository.
2. Trigger the pull request path and, if possible, dispatch
   `pr-policy.yml` with that PR's number after posting a summary fixture.
3. Inspect the guard workflow logs and PR-scoped status contexts.

**Expected result**: The guard does not post reviewer-loop readiness statuses for
the fork-head pull request, matching the existing same-repository restriction.

---

## Scenario 7: Local tests cover guard behavior

1. Run the focused guard tests added by the implementation.

   ```bash
   bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh
   ```

2. Run markdown and workflow shell validation.

**Expected result**: The focused test passes and covers the configured triggers
(`pull_request_target` plus `workflow_dispatch`, no `issue_comment`), absence of
default polling, summary marker matching, fork-head skips, out-of-scope success,
and the unchanged PR-scoped status context (#1998).

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
      cases, including the same-repository guard on fork-head PRs.

---

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Missing-summary status remains after the summary comment is posted | `pr-policy.yml` was not dispatched after the summary, or the dispatch run could not fetch the PR head SHA | Confirm `PR_POLICY_DISPATCH=requested`, rerun `workflow_dispatch` with `pr_number`, and inspect Actions logs (#1998). |
| A normal comment starts a PR policy runner | An `issue_comment` trigger was re-added to `pr-policy.yml` | Remove `issue_comment` from the workflow; summary refresh is via `workflow_dispatch` only. |
| Fork-head PR receives a reviewer-loop readiness status | The dispatch or PR-event path did not preserve the same-repository head guard | Fetch head repository metadata before posting statuses and skip fork heads. |
| Out-of-scope branches fail the guard | Branch-prefix detection changed | Verify the configured in-scope prefixes and expected branch name. |
| Branch protection no longer recognizes the guard | Required status pattern points at an obsolete context | Use the documented `Reviewer-loop completion guard (#*)` pattern or repository-supported equivalent. |
