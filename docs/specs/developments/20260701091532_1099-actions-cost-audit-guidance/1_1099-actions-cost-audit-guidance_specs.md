# Actions Cost-Audit Guidance - Spec

**Epic**: #1095 Actions cost reduction

---

## Overview

Template maintainers and downstream repository owners need a lightweight way to
understand recent GitHub Actions activity before they decide which workflows to
keep, narrow, disable, or replace. The guidance should work with normal
repository-level permissions and should help teams identify high-volume,
low-value workflow runs without requiring billing-admin access.

The product outcome is a repeatable cost-audit workflow that can be used during
retrospectives, template-sync reviews, and maintenance planning. It should make
the cost tradeoff visible while preserving high-signal checks such as release
gates, reviewer readiness, and real regression or deployment workflows.

## Brief Objective List

Derived from issue #1099:

1. Maintainers can inspect recent workflow run counts and wall time by workflow
   using available GitHub repository permissions.
2. Guidance distinguishes public-repository zero-billable runs from private
   downstream runner-minute cost risk.
3. Guidance explains when to keep workflows despite cost, including high-signal
   checks, release gates, and real regression or deploy jobs.
4. Output and recommendation format is usable during retrospectives or
   template-sync reviews.

## Use Cases

### Use Case 1: Maintainer audits recent Actions activity

**Actor**: Template maintainer or downstream repository maintainer.
**Preconditions**: The maintainer can read workflow run history for the
repository.

**Steps**:

1. The maintainer starts a lightweight Actions cost-audit review.
2. The maintainer chooses a recent time window or run count to inspect.
3. The audit output groups recent activity by workflow.
4. The maintainer reviews run counts, wall time, and recurring high-volume
   workflows.

**Postconditions**: The maintainer can identify which workflows appear most
active or time-consuming during the inspected window.

**Information shown**:

- Workflow name.
- Recent run count.
- Recent wall-time total or comparable duration signal.
- Notes about unavailable or incomplete run data.

**Actions available**:

- Keep the workflow as-is.
- Mark the workflow for follow-up review.
- Use the output in a retrospective or template-sync review.

### Use Case 2: Maintainer evaluates cost risk for downstream private repositories

**Actor**: Template maintainer or downstream repository maintainer.
**Preconditions**: Recent workflow activity has been summarized.

**Steps**:

1. The maintainer reviews the workflow activity summary.
2. The guidance separates public-repository billing assumptions from private
   downstream runner-minute risk.
3. The maintainer identifies workflows that are harmless in a public template
   but may become expensive after sync into a private downstream repository.

**Postconditions**: The maintainer can explain whether a workflow's cost concern
is immediate, downstream-only, or not material.

**Information shown**:

- Cost-risk framing for public and private repositories.
- Reminder that zero billable minutes in the template is not proof that the same
  default is safe downstream.
- Examples of inherited workflows that may require opt-in defaults or narrower
  triggers.

**Actions available**:

- Keep public-template behavior unchanged.
- Recommend an opt-in or narrower downstream default.
- Capture a follow-up backlog item for workflow cost hardening.

### Use Case 3: Maintainer decides whether to keep a costly workflow

**Actor**: Workflow operator or template maintainer.
**Preconditions**: A workflow has visible run volume or wall-time cost.

**Steps**:

1. The maintainer compares the workflow's cost signal against its value.
2. The guidance identifies high-signal categories that should not be removed
   solely because they cost runner time.
3. The maintainer records a keep, narrow, disable, replace, or investigate
   recommendation.

**Postconditions**: The recommendation captures both the cost reason and the
quality or release-safety reason for the decision.

**Information shown**:

- When to keep a workflow despite cost.
- When to narrow automatic triggers.
- When to make placeholder or low-value work opt-in.
- When more data is needed before changing behavior.

**Actions available**:

- Keep high-signal workflows.
- Narrow low-value trigger fan-out.
- Make placeholder workflows opt-in.
- Create a follow-up work item.

### Use Case 4: Maintainer uses audit output in a retrospective or sync review

**Actor**: Retrospective facilitator, template maintainer, or downstream
maintainer.
**Preconditions**: An Actions cost-audit summary has been generated or prepared.

**Steps**:

1. The maintainer includes the audit summary in a retrospective or template-sync
   review.
2. The group reviews top workflows, risk framing, and recommendations.
3. The group records accepted decisions and follow-up work.

**Postconditions**: Actions-cost decisions are visible, reviewable, and reusable
across maintenance sessions.

**Information shown**:

- A concise summary table or equivalent structured output.
- Recommendation text that can be pasted into a retrospective or issue.
- Follow-up actions with enough context to become backlog items.

**Actions available**:

- Accept a recommendation.
- Defer pending more data.
- Convert a recommendation into a workflow item.

## Business Rules

- The audit must be lightweight and usable without billing-admin access.
- The audit must report when available permissions or run history are
  insufficient rather than presenting incomplete data as complete.
- Workflow activity should be grouped by workflow so maintainers can compare
  relative run volume and wall time.
- Public-template zero-billing assumptions must not be used as proof that the
  same workflow defaults are safe for private downstream repositories.
- Recommendations must preserve high-signal checks when they provide real
  quality, safety, release, regression, or deployment value.
- Recommendations must distinguish "keep", "narrow", "make opt-in", "replace",
  "disable", and "investigate" outcomes.
- The output must be concise enough to include in retrospectives or
  template-sync reviews.

## Operational Visibility

- **Audit summary**: Maintainers can see recent workflow activity grouped by
  workflow.
- **Cost-risk framing**: Maintainers can see whether the concern is immediate
  runner cost, downstream private-repository risk, or low material risk.
- **Decision rationale**: Recommendations include a short reason, not just an
  action label.
- **Data limitations**: Missing permissions, missing run history, or partial
  data are visible in the output.
- **Follow-up readiness**: Recommendations can be copied into backlog items or
  retrospective notes without rewriting the context.

## Acceptance Criteria

- [ ] Maintainers can inspect recent workflow run counts by workflow using
      normal repository workflow-run visibility.
- [ ] Maintainers can inspect recent workflow wall time or an equivalent
      duration signal by workflow using normal repository workflow-run
      visibility.
- [ ] The audit output identifies when workflow run data is unavailable,
      incomplete, or permission-limited.
- [ ] The guidance distinguishes public-repository zero-billable template runs
      from private downstream runner-minute cost risk.
- [ ] The guidance explains when to keep workflows despite cost, including
      high-signal checks, release gates, and real regression or deployment jobs.
- [ ] The guidance supports at least these recommendation outcomes: keep, narrow,
      make opt-in, replace, disable, and investigate.
- [ ] The output format is suitable for retrospectives or template-sync reviews,
      including a compact summary and decision rationale.
- [ ] Tests or static validation cover the recommended output structure and the
      public-vs-private cost-risk framing.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Inspect recent workflow run counts and wall time | Use Case 1, Business Rules | AC1, AC2, AC3 |
| Distinguish public template and private downstream cost risk | Use Case 2, Business Rules | AC4, AC8 |
| Explain when to keep workflows despite cost | Use Case 3, Business Rules | AC5, AC6 |
| Make output usable in retrospectives and template-sync reviews | Use Case 4, Operational Visibility | AC7, AC8 |

## Out of Scope

- Direct billing API integration or billing-admin-only reporting.
- Exact dollar-cost calculation for an organization account.
- Automatic workflow disabling or trigger mutation based on audit output.
- Replacing GitHub's native billing or usage dashboards.
- Auditing non-Actions compute costs.

## PR-Visible Deferral Notes

- **Billing-admin usage data**: Deferred because the desired workflow should work
  with normal repository-level visibility and should not require organization
  billing permissions.
- **Automatic remediation**: Deferred because disabling or rewriting workflows is
  a separate change with higher operational risk. This feature only prepares
  evidence and recommendations.
- **Exact dollar estimates**: Deferred because billing rates and included minutes
  vary by account, runner type, and plan. The audit should focus on run volume,
  wall time, and downstream risk framing.
