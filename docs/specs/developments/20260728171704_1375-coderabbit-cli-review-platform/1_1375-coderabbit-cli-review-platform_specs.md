# CodeRabbit CLI Review Platform — Spec

## Overview

Workflow operators need an optional CodeRabbit command-line review source for pull requests, including public repositories where an installed review App is not desired. CLI review must remain distinct from the existing App option and must visibly report when no fresh review occurred.

## Use Cases

### Configure CLI review

**Actor**: Workflow operator.
**Preconditions**: The repository selects the CLI review option for a pull-request stage.

**Steps**:

1. The workflow runs the configured CLI review against the pull request's base.
2. It records whether the result is clean, needs changes, or was skipped.
3. It continues with other configured review sources as applicable.

**Postconditions**: The pull request has an auditable CLI-review disposition.

### Handle a CLI rate limit

**Actor**: Workflow operator.
**Preconditions**: The CLI review service has reached its review limit.

**Steps**:

1. The workflow identifies the rate limit separately from review findings.
2. The default warning policy records a visible warning and continues.
3. A strict policy stops or escalates rather than treating the skipped review as clean.

**Postconditions**: Operators know whether a fresh CLI review ran and may select a stricter policy.

## Business Rules

- CLI review is separately named and never changes the existing CodeRabbit App behavior.
- Clean, needs-changes, and skipped outcomes remain distinct.
- A rate limit is skipped with an explicit rate-limit reason, not a clean review.
- The default rate-limit policy warns and continues; strict policy blocks or escalates.
- Missing installation or authentication is reported as unavailable, never clean.
- CLI review may run alone, with other review sources, or not at all.

## Operational Visibility

- **Logs**: Review output records result, reason, policy, and any retry hint.
- **Notifications**: Warning-policy continuation is visible in the pull-request review summary.
- **Audit trail**: The pull request distinguishes code findings from reviewer availability.

## Acceptance Criteria

- [ ] Operators can configure CLI review independently from the existing App option at supported review stages.
- [ ] CLI review produces clean, needs-changes, or skipped outcomes that combine with other review sources.
- [ ] Missing access or authentication is an unavailable skipped outcome, never a clean review.
- [ ] A rate limit is identified explicitly and defaults to a visible warn-and-continue outcome.
- [ ] Strict rate-limit policy prevents a rate-limited review from silently becoming ready.
- [ ] Documentation and pull-request evidence state when warning-policy continuation did not perform a fresh review.
- [ ] Tests cover result mapping, dispatch, and warning versus strict rate-limit behavior.

## Out of Scope (MVP)

- Posting CLI findings as native pull-request review threads.
- Replacing or changing the existing CodeRabbit App integration.
- Automatically waiting for a rate-limit window to reset.

## Brief Objective List

1. Support a separately named CLI review option.
2. Use the workflow review-result contract.
3. Preserve App and empty-list compatibility.
4. Allow CLI-only template configuration.
5. Provide warning and strict rate-limit behavior.
6. Document the trade-offs and test the behavior.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Separate CLI option and compatibility | AC1, AC2 |
| CLI-only configuration | AC1, AC6 |
| Result contract and unavailable state | AC2, AC3 |
| Rate-limit policy | AC4, AC5, AC6 |
| Documentation and tests | AC6, AC7 |

## Complex Workflow Decision Matrix

| CLI outcome | Policy | Workflow result | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- | --- |
| Clean | Any | Clean | Continue to the next configured gate. | Review-loop summary, pull-request readiness | A completed CLI review has no blocking findings. |
| Blocking findings | Any | Needs changes | Return the pull request for fixes. | Review-loop summary, fixer handoff | The CLI identifies a blocking change request. |
| Unavailable | Any | Skipped | Surface the reason. | Review-loop summary, operator guidance | The CLI is not installed or authenticated. |
| Rate limited | Warn | Skipped | Warn and continue without claiming fresh review. | Review-loop summary, pull-request evidence | The hourly CLI limit is reached. |
| Rate limited | Strict | Escalated | Stop readiness for operator action. | Review-loop summary, readiness gate | A repository requires a fresh CLI review. |
