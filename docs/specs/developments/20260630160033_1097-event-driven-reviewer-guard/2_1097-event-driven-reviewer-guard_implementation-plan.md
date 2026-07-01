# Event-Driven Reviewer Guard Readiness - Implementation Plan

**Spec**: [1_1097-event-driven-reviewer-guard_specs.md](1_1097-event-driven-reviewer-guard_specs.md)
**Smoke test runbook**: [1097-event-driven-reviewer-guard.smoke-test.md](../../../testing/workflow/1097-event-driven-reviewer-guard.smoke-test.md)

---

## Summary

**Approach**: Keep the reviewer-loop summary comment as the readiness contract,
but stop the guard workflow from sleeping by default. The pull request guard path
will do a fast summary check and post the PR-scoped status immediately, while an
`issue_comment` path will re-check and post success when `pr-review-loop.sh`
posts the canonical summary comment.

**Estimated complexity**: M

**Rationale**: The change touches a GitHub Actions readiness gate, PR-scoped
commit statuses, reviewer-loop documentation, and regression tests. It is
moderate rather than large because the readiness source of truth remains the
existing summary comment and no reviewer platform behavior changes.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `809be99` |
| Current guard workflow | `sed -n '1,220p' .github/workflows/reviewer-loop-guard.yml` | Guard currently runs on `pull_request_target` and defaults to `GUARD_MAX_WAIT=600` with `GUARD_POLL_INTERVAL=30`. |
| Summary contract references | `rg "Automated Reviewer Loop Summary|Reviewer-loop completion guard" .github scripts docs -g '*.yml' -g '*.sh' -g '*.md'` | Confirmed the guard, reviewer loop, CI enforcement docs, protocol docs, and smoke runbooks depend on the canonical summary markers and PR-number-scoped status context. |
| Existing smoke coverage | `sed -n '1,220p' docs/testing/workflow/613-enforce-regression-label-and-reviewer-loop-via-ci.smoke-test.md` | Existing runbook validates missing summary, simulated summary, new commit reset, and branch-protection guidance for the current polling guard. |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Update `.github/workflows/reviewer-loop-guard.yml` so the default
      `pull_request_target` path performs a fast summary check and posts the
      PR-scoped commit status without sleeping for several minutes. Maps to AC1,
      AC2, and AC3.
- [ ] Add an `issue_comment` trigger path for comments on pull requests. The
      workflow should ignore non-PR comments and comments that do not contain the
      canonical reviewer-loop summary markers. Maps to AC2 and AC5.
- [ ] On the `issue_comment` path, fetch the pull request's current head SHA and
      branch from the API, apply the same in-scope branch-prefix rules, and post
      the PR-scoped success status when a valid summary exists. Maps to AC2, AC3,
      and AC4.
- [ ] Preserve the existing same-repository head guard on both event paths. Fork
      pull requests must not receive reviewer-loop guard statuses from this
      workflow because the current `pull_request_target` path intentionally skips
      fork heads rather than evaluating untrusted head branches. Maps to AC2,
      AC3, and AC7.
- [ ] Preserve the existing out-of-scope branch success behavior for non-feature,
      non-fix, non-refactor, and non-hotfix branches. Maps to AC4.
- [ ] Keep the status context format `Reviewer-loop completion guard (#<PR>)`
      unchanged so existing branch-protection guidance remains recognizable.
      Maps to AC5 and AC6.

### Shared Packages / Libraries

- [ ] If the workflow shell grows beyond a small inline block, extract reusable
      guard logic into a shell helper under `scripts/development-workflow/` and
      invoke it from the workflow after checking out the base repository code.
      The helper must not execute untrusted pull request head code. Maps to AC1,
      AC2, and AC7.

### Documentation

- [ ] Update `docs/workflow/development-workflow/integrations/ci-enforcement.md`
      to describe the fast pull request path, the summary-comment event path,
      the missing-summary failure state, and the unchanged PR-scoped context.
      Maps to AC5 and AC6.
- [ ] Update any existing smoke-test language that refers to the long polling
      wait so it reflects the new short default behavior. Maps to AC1 and AC7.
- [ ] Add or update `docs/testing/workflow/1097-event-driven-reviewer-guard.smoke-test.md`
      with implementation-specific verification steps. Maps to AC7.

---

## Testing Strategy

**Test types**: Shell/unit, workflow static checks, smoke/manual.

**Key scenarios to test**:

1. In-scope implementation branch with no summary posts a non-passing
   missing-summary status quickly. Maps to AC1 and AC3.
2. In-scope implementation branch with a valid summary posts a passing status.
   Maps to AC2.
3. Summary comment event on a pull request posts or refreshes the passing status
   for the current PR head SHA. Maps to AC2 and AC5.
4. Non-summary issue comments do not change readiness. Maps to AC5.
5. Fork-head pull requests do not receive reviewer-loop guard statuses from this
   workflow. Maps to AC2, AC3, and AC7.
6. Out-of-scope branch prefixes pass or skip quickly with the existing
   non-blocking semantics. Maps to AC4.
7. Documentation and smoke runbooks identify the new readiness signal and remove
   default long-polling expectations. Maps to AC6 and AC7.

**Smoke test runbook**: `docs/testing/workflow/1097-event-driven-reviewer-guard.smoke-test.md`

**Regression suite**: Add focused shell coverage if guard logic is extracted to a
helper. If the implementation remains entirely inline in the workflow, add a
static workflow test that verifies the trigger set, absence of default 600-second
polling, summary marker matching, and unchanged status context.

### Concurrent-event-source addendum

- **Shared mutable state guards**: The readiness state is the PR-scoped commit
  status for the PR head SHA. The existing workflow concurrency group remains
  PR-number scoped so newer guard runs supersede older runs for the same PR.
- **Re-entrancy / in-flight tracking**: Multiple events can arrive for the same
  PR. Each event re-evaluates the current PR comments and posts the status for
  the current head SHA, making repeated events idempotent.
- **Event deduplication**: Duplicate summary-comment events may occur if a
  summary is edited or reposted. The guard should re-post the same success
  status for the same head SHA; this is acceptable and avoids local state.
- **Listener and resource cleanup**: Not applicable - GitHub Actions jobs are
  short-lived and do not register persistent listeners.
- **Race conditions at initialization**: A summary can be posted shortly after a
  pull request event. The pull request event may post a missing-summary status,
  and the later summary-comment event should replace it with success for the
  same head SHA.
- **Race conditions at teardown**: Not applicable - each workflow run computes a
  single status from current GitHub API state and exits.
- **Error propagation across async boundaries**: GitHub API read failures should
  post a failure status with a retry-oriented description and exit non-zero.

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/ci-enforcement.md` -
      update reviewer-loop guard behavior, trigger model, branch-protection
      guidance, and troubleshooting.
- [ ] `docs/testing/workflow/613-enforce-regression-label-and-reviewer-loop-via-ci.smoke-test.md`
      - adjust existing guard timing expectations if they mention the old long
      polling behavior.
- [ ] `docs/testing/workflow/1097-event-driven-reviewer-guard.smoke-test.md` -
      add the new feature-specific smoke runbook.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Summary-comment event does not run for the target PR | Medium | Medium | Include explicit `issue_comment` trigger tests and document manual rerun/check behavior. |
| Missing-summary status briefly appears before the reviewer-loop summary event posts success | High | Low | Treat this as expected eventual readiness behavior and document that the summary event updates the status. |
| Workflow accidentally trusts untrusted PR head code | Low | High | Keep logic inline or check out only trusted base-repository code in `pull_request_target` context. |
| Comment-event path posts statuses for fork-head PRs | Low | High | Fetch the PR head repository from the API and skip when it does not match the base repository, matching the existing pull request guard behavior. |
| Branch protection points at an obsolete check name | Medium | Medium | Keep the existing context name and update documentation with the unchanged required status pattern. |
| Status is posted to the wrong SHA on comment events | Low | High | Fetch the PR head from the API during `issue_comment` runs and cover it in tests. |

---

## Code Samples

No production code samples are included in this plan.

---

## Implementation Order

1. Update `.github/workflows/reviewer-loop-guard.yml` trigger definitions to add
   the summary-comment event path while retaining pull request events.
2. Refactor the guard logic so branch scope, summary-marker validation,
   current-head lookup, and status posting are shared between event paths.
3. Change the default pull request path to a fast check with no long default
   sleep or polling.
4. Add the summary-comment event behavior that posts a passing status when the
   canonical summary is present.
5. Preserve and verify the same-repository head guard on pull request and
   comment-event paths.
6. Preserve and verify the out-of-scope branch success path.
7. Add shell/static tests for missing-summary, summary-present, summary-comment,
   non-summary comment, fork-head, and out-of-scope scenarios.
8. Update CI enforcement documentation and existing guard smoke-test language.
9. Add `docs/testing/workflow/1097-event-driven-reviewer-guard.smoke-test.md`.
10. Run markdown, workflow shell, and focused guard/reviewer-loop tests.
11. Update `CHANGELOG.md` under `[Unreleased]` using the project's
    `**Bold Title** (#1097):` format.
