# Release Reviewer Check Exclusion — Spec

**Issue**: [#1970](https://github.com/lhpaul/ai-dev-framework-template/issues/1970)

## Overview

Release maintainers must be able to complete the existing release CI and readiness flow without waiting for configured external reviewers. Pending or failed PR-Agent reviews currently block that flow despite the release policy. This correction applies the existing reviewer exemption consistently while retaining all other release and implementation safeguards.

## Scope Alignment

Luis approved the issue scope and the approach in the development session: consistently exclude configured external-reviewer checks from release readiness, preserve ordinary CI and current-head validation, and preserve implementation review gates. The technical checkpoint is satisfied. Risk authority is limited to medium for this issue; historical exceptions for earlier releases grant no additional authority.

## Use Cases

### Use Case 1: Complete release readiness

**Actor**: Release maintainer or authorized workflow runner.

**Preconditions**: A release pull request exists and the repository declares its external reviewers.

**Steps**:

1. Run the normal release CI and readiness flow.
2. Evaluate ordinary CI independently of configured external-reviewer checks.
3. Recheck live CI and the current head before applying readiness.

**Postconditions**: Pending or failed configured reviewer checks alone do not prevent readiness. Ordinary CI failures, pending ordinary checks where completion is required, missing expected workflow evidence, ownership failures and head changes retain their existing blocking behavior.

**Information shown**: Existing CI and readiness results, including the reason when a gate refuses advancement.

**Actions available**: Continue the existing authorized release flow after all applicable gates pass, or address the reported blocker.

### Use Case 2: Preserve implementation review requirements

**Actor**: Developer or authorized workflow runner.

**Preconditions**: An implementation pull request requires configured review evidence.

**Steps**:

1. Run its existing review and readiness flow.
2. Supply current, complete reviewer evidence and required ordinary CI evidence.

**Postconditions**: The release exemption does not satisfy or waive implementation review requirements.

**Information shown**: Existing reviewer and CI refusal reasons.

**Actions available**: Complete the required review or fix CI before advancement.

## Business Rules

- Only exact, recognized check names belonging to configured external reviewers qualify for exclusion; arbitrary jobs and unconfigured reviewers remain subject to CI evaluation.
- The CI loop and both the initial and live pre-apply readiness evaluations agree on the release exclusion.
- The effective PR-Agent draft reviewer and local AI ready reviewer configuration must recognize the PR-Agent review check.
- Ordinary CI, regression, expected-workflow evidence, ownership and current-head gates remain in force.
- Unknown or malformed evidence must never be silently discarded to manufacture a passing result.
- No new merge bypass, administrative authority, branch deletion or historical release exception is introduced.

## Decision Matrix

Rows are independent constraints, not an ordered decision tree. For every reachable combination, any applicable blocking row prevents readiness; every applicable blocker must be resolved before advancement. A reviewer exemption removes only that reviewer's contribution and cannot override another row. Existing gate execution order and first-error reporting remain unchanged: this correction defines no new precedence. Ownership failure, missing expected evidence, failing ordinary CI and head changes can coexist and all remain blocking.

| Input | Outcome | Required next action | Surfaces |
| --- | --- | --- | --- |
| Release with pending or failed configured reviewer check; other gates pass | Reviewer does not block | Continue normal readiness | CI loop; initial and live readiness |
| Release with unrelated pending or failing CI | Existing CI block remains | Wait or fix CI | CI loop; initial and live readiness |
| Release missing expected workflow evidence | Existing evidence block remains | Restore required evidence | CI loop |
| Ownership verification fails | Existing ownership block remains | Correct the target identity before mutation | Readiness ownership guard |
| Release head changes during evaluation | Readiness refuses | Reevaluate the current head | Live readiness |
| Implementation lacking required reviewer evidence | Review gate refuses | Complete required review | Implementation readiness |
| Unconfigured or similarly named job | No reviewer exemption | Evaluate as ordinary CI | CI loop; release readiness |
| Unknown or malformed evidence | No silent exclusion | Existing fail-closed handling remains | CI loop; readiness |

## Operational Visibility

Existing CI and readiness output remains the operator-facing evidence. This correction does not add a notification channel or lifecycle status.

## Acceptance Criteria

- [ ] AC-1: With the effective PR-Agent and local AI reviewer configuration, release CI and readiness do not wait on pending or failed PR-Agent review checks.
- [ ] AC-2: The initial readiness evaluation and its live pre-apply revalidation apply the same configured reviewer exclusion.
- [ ] AC-3: Unrelated pending or failed CI and missing expected workflow evidence still block at their existing gates.
- [ ] AC-4: A head change during readiness evaluation prevents readiness from being applied for stale evidence.
- [ ] AC-5: Implementation pull requests retain their existing strict reviewer requirements.
- [ ] AC-6: Unknown, malformed, unconfigured or similarly named evidence is not hidden by reviewer classification.
- [ ] AC-7: Synthetic regression tests cover the affected release behavior and the retained blocking behavior without accessing private configuration or real service data.

## Brief Objective Coverage

| Issue objective | Coverage |
| --- | --- |
| Consistent release exclusion, including live revalidation | AC-1, AC-2 |
| Effective reviewer configuration and exact PR-Agent check | AC-1, AC-6 |
| Preserve implementation and ordinary CI gates | AC-3, AC-4, AC-5 |
| No arbitrary reviewer classification or hidden evidence | AC-6 |
| Synthetic pending, failing, missing and head-change regressions | AC-7 |

## Out of Scope

- Changing reviewer configuration, branch protections, review requirements or release policy.
- Retrying, merging or bypassing checks on the historical release pair.
- Broad CI/readiness refactors, new architecture or unrelated bug fixes.
- Reading or copying private configuration into tests or changing checkpoint-policy.json.

No issue objectives are deferred. The existing release policy supplies the behavioral contract; the implementation plan will select the minimal code changes.
