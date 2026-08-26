# Regression After Reviewer Clean - Implementation Plan

**Spec**: Refactor item #1615 brief in GitHub Issues
**Smoke test runbook**: [1615-regression-after-reviewer-clean.smoke-test.md](../../../testing/workflow/1615-regression-after-reviewer-clean.smoke-test.md)

---

## Summary

**Approach**: Align the PR policy automation with the existing Protocol 91
ordering by moving the normal regression label and dispatch path from PR
lifecycle events to the canonical reviewer-loop summary event. Keep the
`e2e-regression.yml` label gate and workflow-dispatch contract intact, but make
`pr-policy.yml` apply `ready-for-regression` only after current-head reviewer
evidence is clean or legitimately skipped.

**Estimated complexity**: M

**Rationale**: The behavior is narrow, but it changes a privileged GitHub
Actions policy workflow and must preserve fork safety, stale-head guards,
summary parsing, status posting, and downstream regression dispatch behavior.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `20927834` |
| Current policy trigger and dispatch locations | `rg -n "opened\\|reopened\\|ready_for_review|issue_comment|Automated Reviewer Loop Summary|ready-for-regression|workflow run|dispatch_regression" .github/workflows/pr-policy.yml .github/workflows/e2e-regression.yml scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | `pr-policy.yml` applies and dispatches regression on `opened|reopened|ready_for_review`, while Protocol 91 Step 7b states regression follows reviewer-loop `clean` or allowed `skipped`. |
| Current static workflow test expectations | `rg -n "label_applies_on_open_reopen_ready|regression_workflow_dispatch_present|dispatch_redispatches_on_stale_head|synchronize_removes_stale_label" scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` | The test suite currently encodes the old early-label behavior and must be retargeted. |
| Readiness signal contract | `sed -n '1,190p' docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | `ready-for-regression` already means automated reviews are clean or skipped and is not intended for spec or plan PRs. |
| Regression integration docs | `sed -n '1,120p' docs/workflow/development-workflow/integrations/e2e-regression.md` | The doc describes both correct Step 7b ordering and the obsolete PR-open auto-apply path, so it needs a focused update. |
| Existing smoke runbooks | `find docs/testing -maxdepth 3 -type f | sort | sed -n '1,160p'` | Workflow smoke runbooks live under `docs/testing/workflow/`; add the new runbook there and update stale related runbook expectations if implementation changes them. |

---

## Cross-Cutting Operational Assumption Check

**Result**: `Not applicable` - this plan does not rely on a changing external
environment target, approved base beyond the prelude-resolved `develop`, linked
resource, product repository, or canonical configuration value. The work is a
single-item refactor of repository-owned workflow policy behavior.

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Refactor `.github/workflows/pr-policy.yml` so `opened`, `reopened`, and
      `ready_for_review` events no longer apply `ready-for-regression` or
      dispatch `e2e-regression.yml` solely from the PR lifecycle event.
- [ ] Keep `pull_request_target` event handling for reviewer-loop guard status
      and stale-label removal on `synchronize`.
- [ ] On canonical reviewer-loop summary `issue_comment` events, parse the
      latest applicable summary and only proceed when the summary result is
      `clean` or allowed `skipped`.
- [ ] Bind summary evidence to the current PR head before label or dispatch:
      prefer durable reviewer-loop history or explicit current-head fields when
      available, and fail closed when the latest clean summary cannot be proven
      to describe the live `HEAD_SHA`.
- [ ] Preserve same-repository fork safety before any privileged mutation or
      dispatch.
- [ ] Preserve the existing `workflow_dispatch` inputs and
      `PR_POLICY_REGRESSION_WORKFLOW` /
      `PR_POLICY_REGRESSION_DISPATCH_ENABLED` controls so downstream replacement
      regression workflows keep working.

### Workflow Tests

- [ ] Update
      `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`
      to reject the old open/reopen/ready regression label path.
- [ ] Add static assertions for the new clean-summary path:
      non-summary comments exit, non-clean summaries do not label or dispatch,
      clean/skipped current-head summaries label and dispatch, stale-head clean
      summaries fail closed, and fork-head PRs skip privileged mutation.
- [ ] Keep coverage that the old split workflows stay removed and that the
      consolidated workflow remains API-only with no checkout.
- [ ] Update any adjacent smoke/static expectations that still assert
      open/reopen/ready auto-labeling, especially the consolidated policy
      runbook if it is still used as implementation evidence.

### Documentation

- [ ] Update
      `docs/workflow/development-workflow/integrations/e2e-regression.md` to
      describe the new summary-driven dispatch owner and remove the obsolete
      open/reopen/ready auto-label language.
- [ ] Review
      `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      for small wording updates only if implementation needs to clarify skipped
      or current-head evidence.
- [ ] Do not update `AGENTS.md` unless the implementation changes command-level
      workflow behavior beyond the policy workflow internals.

---

## Testing Strategy

**Test types**: Static workflow tests, smoke runbook, markdown lint, workflow
shell guard, and full workflow test suite selection if required by changed files.

**Key scenarios to test**:

1. PR lifecycle events do not trigger regression readiness before reviewer-loop
   clean evidence. Maps to #1615 AC1.
2. Non-clean reviewer summaries keep regression readiness absent. Maps to
   #1615 AC2.
3. Clean or allowed-skipped reviewer summaries for the current head apply
   `ready-for-regression` and dispatch regression idempotently. Maps to #1615
   AC3.
4. A new push after a clean summary prevents old clean evidence from triggering
   regression for the new head. Maps to #1615 AC4.
5. Spec, plan, graduation, and fork-head PRs remain exempt or non-mutating as
   appropriate. Maps to #1615 AC5.
6. Step 8a remains a recovery guard for a missing regression label, not the
   normal trigger path. Maps to #1615 AC6.

**Smoke test runbook**: `docs/testing/workflow/1615-regression-after-reviewer-clean.smoke-test.md`

**Regression suite**: Update
`scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` as the
focused regression suite for the PR policy workflow. Run broader workflow tests
selected by the repository's changed-file test selection if available.

### Complex workflow decision-gate matrix

This plan modifies the `pr-policy.yml` event-routing gate that decides whether
an event may apply `ready-for-regression` and dispatch regression.

| Gate input | Allowed outcome | Required next action | Mirror surfaces / docs | Test coverage |
| --- | --- | --- | --- | --- |
| `pull_request_target` `opened`, `reopened`, or `ready_for_review` for an in-scope same-repo implementation branch | No regression label or dispatch from this event | Continue reviewer-loop guard status evaluation only | `pr-policy.yml`, `e2e-regression.md`, consolidated policy smoke runbook | Static assertion that lifecycle events do not call the regression label/dispatch path |
| `pull_request_target` `synchronize` before any current-head clean reviewer evidence | Remove or leave absent stale regression readiness | Keep reviewer-loop guard status failing until Step 7 completes | `pr-policy.yml`, Protocol 91 Step 7b/Step 8a | Static assertion that stale labels are not preserved without current-head clean evidence |
| Non-summary `issue_comment` | No label, dispatch, or status mutation | Exit early | `pr-policy.yml` | Existing non-summary skip assertion remains |
| Canonical summary with non-clean result (`needs_fixes`, `escalate`, `pending_timeout`, `timeout`) | No regression label or dispatch | Post/keep reviewer-loop guard failure and require reviewer-loop/fixer path | `pr-policy.yml`, Protocol 92 readiness signal | Static assertions for non-clean result tokens |
| Canonical summary with `Result: clean` bound to the live PR head | Apply `ready-for-regression` and dispatch regression idempotently | Revalidate metadata immediately before mutation; preserve guard success | `pr-policy.yml`, `e2e-regression.yml`, Protocol 91 Step 7b | Static assertion for current-head clean summary label/dispatch path |
| Canonical summary with allowed `Result: skipped` bound to the live PR head | Apply `ready-for-regression` and dispatch regression only when the skip reason is allowed for Step 7 | Revalidate metadata immediately before mutation; otherwise fail closed | `pr-policy.yml`, Protocol 91/92 skipped semantics | Static assertion for allowed skipped summary and a negative assertion for unrecognized skip text |
| Canonical clean/skipped summary whose recorded head differs from live PR head, or whose head cannot be proven | No regression label or dispatch | Fail closed and require fresh reviewer-loop evidence for the live head | `pr-policy.yml`, Protocol 91 `POST_CLEAN_HEAD_SHA` / reviewer-loop history concepts | Static assertion for stale-head summary rejection |
| Fork-head PR for any otherwise matching event | No privileged mutation | Exit before label, status, or dispatch mutation | `pr-policy.yml` fork guard | Existing fork-safety assertions remain and cover dispatch too |
| `spec/*`, `implementation-plan/*`, or graduation PR | No implementation-only regression label | Treat as exempt/non-implementation for regression readiness | Protocol 91 label derivation, Protocol 05b graduation exemption | Static assertion for exempt branch behavior |

### Parser-risk addendum

- **Edge-case enumeration**:
  - Summary comment with `Result: clean` for the current head.
  - Summary comment with `Result: skipped` and an allowed skip reason.
  - Summary comment with `Result: needs_fixes`, `escalate`,
    `pending_timeout`, or `timeout`.
  - Summary comment missing one canonical marker.
  - Multiple summary comments where only the newest applies.
  - Clean summary whose recorded head differs from the live PR head.
  - Fork-head PR with otherwise clean summary evidence.
- **Unit test mapping**: Add or retarget assertions in
  `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` for
  each edge case above.
- **Suppression semantics**: Not applicable - this refactor does not introduce
  suppression directives.

---

## Seed Data

No runtime seed data is required. Test fixtures are static workflow text and
synthetic PR/comment examples embedded in the shell test harness.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/e2e-regression.md` -
      explain that `pr-policy.yml` dispatches regression from clean
      reviewer-loop summary events, not PR open/reopen/ready events.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      - update only if needed to clarify allowed skipped summaries and
      current-head binding for automated policy dispatch.
- [ ] `docs/testing/workflow/1150-consolidate-lightweight-pr-policy-workflows.smoke-test.md`
      - update stale smoke expectations if they still describe early
      open/reopen/ready labeling.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Labels applied by `GITHUB_TOKEN` do not trigger downstream workflows reliably. | Medium | High | Keep explicit `workflow_dispatch` from `pr-policy.yml`, but invoke it only after current-head clean reviewer evidence. |
| The policy workflow treats any old clean summary as current. | Medium | High | Require current-head binding before label or dispatch, and fail closed when the summary cannot be tied to the live head. |
| A non-clean summary accidentally passes through broad marker detection. | Medium | High | Add explicit result parsing tests for clean, skipped, needs-fixes, timeout, pending, and escalate variants. |
| Downstream docs still imply early regression on open PRs. | Medium | Medium | Update `e2e-regression.md` and any stale smoke runbook text in the same implementation PR. |
| Step 8a fallback becomes the normal path and hides policy failure. | Low | Medium | Keep Step 8a fallback, but require policy tests to prove the normal summary-driven path labels and dispatches before CI polling. |

---

## Code Samples

No production-ready code samples. Implementation should adapt the existing
`pr-policy.yml` shell style and static test helpers.

---

## Implementation Order

1. Refactor `.github/workflows/pr-policy.yml` comments and event routing so
   PR lifecycle events keep guard/status behavior but do not apply
   `ready-for-regression` or dispatch regression before reviewer-loop clean
   evidence.
2. Add summary-result and current-head gating inside the `issue_comment` summary
   path, reusing the existing refreshed PR metadata checks before any label or
   dispatch mutation.
3. Keep or adapt `dispatch_regression_workflow()` so the dispatch occurs for the
   live PR head and the label is applied only after successful dispatch and
   metadata revalidation.
4. Preserve stale-label removal on `synchronize`, but make the condition
   compatible with the new head-bound summary model so a post-clean push cannot
   reuse old reviewer evidence.
5. Update `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`
   to remove assertions for open/reopen/ready auto-labeling and add the
   summary-driven, non-clean, stale-head, exempt-branch, and fork-safety
   assertions listed in the Testing Strategy.
6. Update `docs/workflow/development-workflow/integrations/e2e-regression.md`
   and any stale smoke runbook language that describes early auto-labeling.
7. Add the implementation changelog entry under `[Unreleased]` using:
   `- **Trigger regression after reviewer clean** (#1615): Moved the normal regression dispatch path behind current-head reviewer-loop clean evidence so implementation PRs no longer run regression from open/reopen/ready events.`
8. Run focused validation:
   `bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`
9. Run workflow shell/static validation:
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
10. Run markdown validation for changed docs:
    `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
11. If available, run the repository's changed-file test selector or the full
    workflow test suite required by the changed files before opening the
    implementation PR.
