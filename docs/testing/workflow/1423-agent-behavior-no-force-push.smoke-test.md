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

1. Run the guard harness and confirm unauthorized destructive updates stop
   before mutation:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh
   ```

   Expected: the `missing_auth_blocks`, `missing_auth_no_push`,
   `stale_tip_blocks`, and `untrusted_source_blocks` cases pass.

2. Confirm normal branch updates remain allowed:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh
   ```

   Expected: the `normal_published_allowed` and `normal_unpublished_allowed`
   cases pass.

3. Confirm narrowly authorized destructive updates are single-use and
   conditional:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-branch-push-guard.sh
   ```

   Expected: `authorized_allowed`, `authorized_consumed`,
   `existing_claim_blocks`, and `conditional_failure_blocks` pass.

4. Confirm delegated merge risk blockers remain independent from branch-push
   authorization:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
   ```

   Expected: the `push_authorization_does_not_clear_*` cases pass.

5. Inspect the implementation PR self-review log for the branch-update guidance
   inventory. Expected: spec, plan, implementation, review-fix, item
   orchestration, and batch supervision surfaces either reference
   `workflow-branch-push-guard.sh` or are documented as out of scope.

## Acceptance Mapping

| Acceptance criterion | Evidence |
| --- | --- |
| Unauthorized force push blocks before mutation | Guard harness missing-authorization and no-push assertions |
| Stop message names branch/action/missing authorization | Stable `PUSH_GUARD_*` output fields |
| Safe follow-up push proceeds | Guard harness normal published branch assertion |
| Local-only unpublished publish remains allowed | Guard harness unpublished ref assertion |
| Exact human authorization proceeds once | Guard harness authorized and consumed assertions |
| Scope mismatch or stale tip blocks | Guard harness wrong-repo, stale-tip, untrusted-source assertions |
| Conditional update failure does not consume success | Guard harness rollback/conditional failure assertion |
| Risk blockers remain hard blockers | Risk-classifier authorization regression |
| Guard applies across workflow stages | Protocol and agent/skill guidance inventory |
