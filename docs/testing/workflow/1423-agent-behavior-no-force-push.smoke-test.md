# No-Force-Push Guard Smoke Test

## Scope

Issue #1423 adds an execution-time guard for workflow PR branch updates that
would rewrite published history.

## Preconditions

- `gh` is authenticated for the repository when running a real authorization
  check.
- The implementation PR has run the unit harness:
  `bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh`.

## Checks

1. Run the guard harness:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh
   ```

   Expected: the harness reports zero failures.

2. Confirm delegated merge risk blockers remain independent from branch-push
   authorization:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
   ```

   Expected: the `push_authorization_does_not_clear_*` cases pass.

3. Inspect the implementation PR self-review log for the branch-update guidance
   inventory. Expected: spec, plan, implementation, review-fix, item
   orchestration, and batch supervision surfaces either reference
   `workflow-branch-push-guard.sh` or are documented as out of scope.

## Acceptance Mapping

| Acceptance criterion | Evidence |
| --- | --- |
| Unauthorized force push blocks before mutation | Guard harness `missing_auth_blocks`, `missing_auth_no_push`, stale-tip, and untrusted-source assertions |
| Stop message names branch/action/missing authorization | Stable `PUSH_GUARD_*` output fields |
| Safe follow-up push proceeds | Guard harness `normal_published_allowed` and `normal_published_push_executed` assertions |
| Local-only unpublished publish remains allowed | Guard harness `normal_unpublished_allowed` and `normal_unpublished_push_executed` assertions |
| Exact human authorization proceeds once | Guard harness authorized, consumed, lock, and exact force-with-lease push assertions |
| Scope mismatch or stale tip blocks | Guard harness wrong-repo, stale-tip, untrusted-source assertions |
| Conditional update failure does not consume success | Guard harness `conditional_failure_unconsumed` and `conditional_failure_rolled_back_marker` assertions |
| Risk blockers remain hard blockers | Risk-classifier authorization regression |
| Guard applies across workflow stages | Protocol and agent/skill guidance inventory |
