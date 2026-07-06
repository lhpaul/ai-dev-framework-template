# Consolidate Lightweight PR Policy Workflows - Spec

---

## Overview

Template maintainers need a clear decision on whether the current lightweight
PR policy workflows should stay split or move into a single policy workflow.
The decision should be based on the remaining Actions-minute value after the
template's existing cost-reduction work, while preserving reviewer readiness,
regression readiness, fork safety, and PR-scoped status guarantees.

The outcome is either a documented recommendation to keep the current shape, or
a consolidated policy workflow that behaves the same from a maintainer's point
of view. Downstream private repositories should not inherit avoidable one-minute
jobs, but they also should not lose the safeguards that make implementation PRs
safe to review, regress, and merge.

## Brief Objective List

Derived from issue #1150:

1. Evaluate whether consolidating lightweight PR policy workflows still saves
   enough runner minutes after the existing Actions-cost epic changes.
2. Consider consolidation across `apply-regression-label`,
   `remove-regression-label-on-push`, and `reviewer-loop-guard` behavior.
3. Preserve the event-driven reviewer-loop guard, including the summary-comment
   path that can turn the guard status green.
4. Preserve reviewer-loop summary markers as the readiness source of truth
   unless the replacement contract is documented and tested.
5. Preserve PR-number-scoped guard status semantics, or document and verify a
   replacement that avoids shared-SHA status collisions.
6. Preserve fork PR safety and avoid checking out untrusted fork code from
   privileged PR policy workflows.
7. Preserve the intended `ready-for-regression` lifecycle for implementation
   PRs and configured regression checks.
8. If consolidation proceeds, replace redundant short-job fan-out with one PR
   policy workflow.
9. Document minimal workflow permissions, especially for privileged PR events.
10. Cover trigger matrix, fork behavior, status context behavior, and stale
    `ready-for-regression` handling with tests or static checks.
11. Update CI enforcement and e2e-regression documentation to match the final
    workflow shape.

## Use Cases

### Use Case 1: Maintainer decides whether consolidation is worthwhile

**Actor**: Template maintainer.
**Preconditions**: The current lightweight PR policy workflows exist in the
template and the maintainer can inspect their purpose and recent cost context.

**Steps**:

1. The maintainer reviews the current split workflow shape and the behaviors
   each workflow protects.
2. The maintainer reviews the remaining runner-minute savings opportunity for
   downstream private repositories.
3. The maintainer records a recommendation to consolidate or keep the workflows
   split.

**Postconditions**: The recommendation states whether consolidation is still
worth doing and why.

**Information shown**:

- Current policy behaviors covered by the lightweight workflows.
- Expected cost or runner-minute benefit of consolidation.
- Risks to readiness, fork safety, status isolation, and regression labeling.
- Final recommendation with enough context for implementation planning.

**Actions available**:

- Proceed to a consolidation plan.
- Keep the current split workflows and document why.
- Defer with a concrete follow-up if the cost data is insufficient.

**Considerations**:

- A public template repository may show no direct billable-minute impact while
  downstream private repositories still pay for inherited one-minute jobs.
- The recommendation should not treat cost savings as more important than
  reviewer readiness, regression readiness, or fork safety.

### Use Case 2: Implementation PR receives policy labels and statuses

**Actor**: Template maintainer, downstream maintainer, or automated PR policy
workflow.
**Preconditions**: An implementation PR is opened, reopened, marked ready for
review, updated with new commits, or receives a reviewer-loop summary comment.

**Steps**:

1. The PR policy workflow evaluates whether the PR branch is in scope for
   implementation policy checks.
2. For in-scope implementation PRs, the workflow keeps regression-readiness
   labels and reviewer-loop guard statuses aligned with the PR's current review
   state.
3. For out-of-scope branches, the workflow exits without applying
   implementation-only policy.

**Postconditions**: Implementation PRs have the expected readiness policy
signals, while spec, plan, docs, and other non-implementation PRs are not
incorrectly labeled or blocked.

**Information shown**:

- Whether the branch is in scope for implementation policy checks.
- Whether the reviewer-loop summary is present.
- Whether the regression-readiness label is present, removed as stale, or left
  untouched because the reviewer loop owns it.
- The guard status context associated with the specific PR.

**Actions available**:

- Run the reviewer loop when the guard reports that no summary is present.
- Re-run policy workflow checks after a transient API failure.
- Continue normal review when the readiness signals are present and current.

**Considerations**:

- New commits after an implementation PR is labeled for regression must not
  leave stale readiness in place.
- Reviewer-loop-owned labels should not be removed merely because a new push
  occurred after the reviewer loop already established its summary.

### Use Case 3: Fork PR is evaluated safely

**Actor**: External contributor or downstream maintainer.
**Preconditions**: A PR originates from a fork or otherwise untrusted head
repository.

**Steps**:

1. The PR policy workflow identifies that the PR head repository differs from
   the base repository.
2. The workflow avoids privileged operations that would depend on untrusted fork
   code.
3. The workflow reports the safe skip or limited evaluation behavior.

**Postconditions**: Fork PRs do not run untrusted code with privileged policy
permissions and do not receive misleading policy statuses.

**Information shown**:

- That the PR is fork-originated or otherwise outside same-repository policy
  mutation scope.
- Which policy behavior was skipped or limited.
- Whether maintainers need to run a trusted follow-up process.

**Actions available**:

- Review the fork PR using normal human review.
- Ask the contributor to make changes.
- Re-run policy checks only after the code is trusted or mirrored into a safe
  branch.

### Use Case 4: Maintainer configures CI enforcement after the final shape

**Actor**: Template maintainer or downstream repository maintainer.
**Preconditions**: The final policy workflow shape is documented.

**Steps**:

1. The maintainer reads the updated CI enforcement and regression documentation.
2. The maintainer identifies the policy status contexts or labels that branch
   protection and regression checks should rely on.
3. The maintainer applies or verifies the matching repository configuration.

**Postconditions**: Repository enforcement points match the final policy
workflow shape and do not refer to removed or obsolete workflow behavior.

**Information shown**:

- Which status checks are expected for implementation PRs.
- How PR-number-scoped guard statuses should be treated.
- How `ready-for-regression` is applied, removed, and re-established.
- Any fork PR limitation that maintainers must understand.

**Actions available**:

- Update branch-protection or ruleset configuration.
- Run an implementation PR smoke test.
- Keep existing enforcement unchanged when the recommendation is not to
  consolidate.

## Business Rules

- The recommendation must compare remaining cost value against behavioral risk;
  cost reduction alone is not sufficient if current workflow guarantees would be
  weakened.
- Implementation PR policy must remain limited to configured implementation
  branch prefixes.
- Non-implementation PRs must not receive implementation-only
  `ready-for-regression` labels.
- Reviewer-loop readiness must be based on the canonical summary markers unless
  the final design explicitly defines and documents a replacement readiness
  source.
- Reviewer-loop guard status must remain isolated per PR, or the replacement
  must prevent two PRs with the same commit SHA from overwriting each other's
  readiness signal.
- Privileged PR policy workflows must not check out or execute untrusted fork PR
  code.
- Same-repository implementation PRs must still receive a clear failed or
  passing reviewer-loop guard signal when the workflow can evaluate them.
- New commits must not leave stale regression-readiness in place before the
  reviewer loop has established readiness.
- Once the reviewer loop has established readiness, policy behavior must not
  fight the reviewer loop by removing labels that the loop is responsible for
  restoring on the next run.
- Workflow permissions must be the minimum needed for the policy behavior being
  performed.
- Documentation must describe the final policy signals that maintainers should
  configure or inspect.

## Operational Visibility

- **Recommendation**: Maintainers can see whether the final decision is
  "consolidate", "keep split", or "defer", with rationale.
- **Policy evaluation**: Workflow output identifies the PR number, branch scope,
  fork/same-repository classification, reviewer-loop summary state, and
  regression-label state when relevant.
- **Status signal**: Maintainers can see the reviewer-loop guard outcome for the
  specific PR being evaluated.
- **Regression-readiness signal**: Maintainers can see whether
  `ready-for-regression` was applied, removed as stale, or intentionally left in
  place.
- **Permission posture**: Documentation states why each workflow permission is
  needed for the final shape.
- **Failure recovery**: Transient API failures produce retry-oriented output
  rather than silent policy drift.

## Acceptance Criteria

- [ ] A recommendation documents whether consolidation still saves enough
      runner minutes to justify changing the current lightweight PR policy
      workflow shape.
- [ ] The recommendation explicitly weighs downstream private-repository
      runner-minute risk against reviewer readiness, regression readiness, fork
      safety, and PR-scoped status safety.
- [ ] If consolidation proceeds, one PR policy workflow covers the current
      apply-regression-label, remove-regression-label-on-push, and
      reviewer-loop-guard behavior without creating redundant short-job fan-out.
- [ ] If consolidation does not proceed, the final documentation explains why
      the split workflow shape is being kept and what future evidence would
      justify revisiting it.
- [ ] Same-repository implementation PRs still receive the expected
      `ready-for-regression` lifecycle across open, ready-for-review, reviewer
      loop, and new-push events.
- [ ] Non-implementation PRs do not receive implementation-only regression
      labels and do not fail implementation-only reviewer-loop policy.
- [ ] Reviewer-loop readiness is still derived from the canonical summary
      markers, or a documented replacement readiness source is covered by tests.
- [ ] Reviewer-loop guard status remains scoped to the PR being evaluated, or
      a documented replacement prevents shared-SHA status collisions.
- [ ] Fork-originated PRs do not check out or execute untrusted fork code from a
      privileged PR policy workflow.
- [ ] The final workflow permissions are minimal and documented, including the
      reason for any privileged PR event permissions.
- [ ] Tests or static checks cover trigger behavior for PR open, reopen,
      ready-for-review, synchronize, and reviewer-loop summary comment events.
- [ ] Tests or static checks cover fork behavior, status context behavior, and
      stale `ready-for-regression` handling.
- [ ] CI enforcement documentation and e2e-regression documentation match the
      final workflow shape and signal names.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Evaluate whether consolidation still saves enough runner minutes | Use Case 1, Business Rules, Operational Visibility | AC1, AC2 |
| Consider consolidation across the three lightweight policy behaviors | Use Case 1, Use Case 2 | AC3, AC4 |
| Preserve event-driven reviewer-loop guard and summary-comment path | Use Case 2, Business Rules | AC7, AC11 |
| Preserve summary markers as readiness source of truth unless replaced | Use Case 2, Business Rules | AC7 |
| Preserve PR-number-scoped guard semantics or safe replacement | Use Case 2, Use Case 4, Business Rules | AC8, AC13 |
| Preserve fork PR safety and no privileged checkout of untrusted code | Use Case 3, Business Rules | AC9, AC10, AC12 |
| Preserve ready-for-regression lifecycle | Use Case 2, Business Rules, Operational Visibility | AC5, AC6, AC12, AC13 |
| Replace redundant short-job fan-out if consolidation proceeds | Use Case 1, Use Case 2 | AC3 |
| Document minimal workflow permissions | Use Case 3, Use Case 4, Business Rules | AC10 |
| Cover trigger matrix, fork behavior, status contexts, and stale labels | Use Case 2, Use Case 3 | AC11, AC12 |
| Update CI enforcement and e2e-regression documentation | Use Case 4, Operational Visibility | AC13 |

## Out of Scope

- Consolidating workflows that are not part of the PR policy surface named in
  the brief.
- Changing the reviewer-loop summary format unless the implementation plan
  explicitly chooses a tested replacement contract.
- Changing which branch prefixes count as implementation branches beyond the
  current configurable policy.
- Replacing GitHub branch protection, repository rulesets, or regression jobs.
- Making downstream repositories adopt a specific branch-protection provider or
  ruleset implementation.
- Running untrusted fork PR code from privileged PR policy workflows.

## PR-Visible Deferral Notes

- **Unrelated workflow consolidation**: Deferred because the brief is specifically
  about lightweight PR policy workflows. Release, deployment, lint, and other
  workflows have different risk and value profiles.
- **Reviewer-loop marker redesign**: Deferred by default because the existing
  summary markers are the current readiness source of truth. A redesign is only
  acceptable if the implementation plan documents and tests the replacement.
- **Branch-protection provider changes**: Deferred because this work should keep
  the template's policy signals accurate; repository-specific enforcement
  providers remain a downstream configuration choice.
