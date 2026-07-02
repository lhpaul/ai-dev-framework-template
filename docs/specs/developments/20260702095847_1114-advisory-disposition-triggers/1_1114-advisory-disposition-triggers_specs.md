# Advisory Disposition Triggers - Spec

**Epic**: #1112 External review loop - Haystack advisory hardening
**Depends on**: #1113 Structured Haystack Advisory Findings

---

## Overview

Workflow operators need every clean external-review run with actionable advisory
evidence to record how those advisories were handled. Today, PR-Agent advisory
labels can trigger disposition work, but Haystack-only advisory results can pass
with only a suggestion count and no per-finding summary or disposition record.

This feature expands the advisory-disposition trigger model so clean review-loop
results still require advisory handling when any configured reviewer reports
advisory evidence. The outcome is a review summary that tells humans not only
that advisories existed, but also which advisories were fixed, accepted, or left
for follow-up before a pull request is marked ready.

## Brief Objective List

Derived from issue #1114:

1. Require the Protocol 93 advisory-disposition step when the review-loop output
   reports advisory count, policy-review-required, or advisory-label evidence.
2. Show Haystack advisory details from the structured output introduced by
   #1113 in the reviewer-loop summary comment, not only an advisory count.
3. Cover the Haystack-only clean-with-advisories path with a smoke test or
   harness scenario.

## Use Cases

### Use Case 1: Haystack-only advisories require disposition

**Actor**: Workflow operator running `/run-reviewer-loop`, `/run-item`, or
`/run-epic`.
**Preconditions**: A pull request has completed external review, no blocking
findings remain, and Haystack reported one or more advisory findings.

**Steps**:

1. The operator runs the normal reviewer loop for the pull request.
2. The reviewer loop receives a clean result with Haystack advisory evidence.
3. The reviewer-loop summary lists each Haystack advisory that needs a
   disposition.
4. The operator or delegated runner reviews each listed advisory.
5. Each advisory is marked as fixed, accepted with rationale, or deferred with a
   follow-up explanation before the pull request is treated as ready.

**Postconditions**: The pull request remains non-blocked by advisory-only
findings, but readiness evidence includes a visible disposition for every
Haystack advisory.

**Information shown**:

- The clean review-loop result.
- Total advisory count.
- Individual Haystack advisory summaries and available details.
- One disposition per advisory.

**Actions available**:

- Fix an advisory and rerun the reviewer loop.
- Accept an advisory with rationale.
- Defer an advisory with explicit follow-up context.
- Stop for human input when an advisory raises risk outside the active policy.

**Considerations**:

- Advisory-only results must not become blocking solely because they require a
  disposition.
- Missing optional location or fix guidance must not prevent a disposition when
  the advisory summary and detail are available.

### Use Case 2: Policy-review-required clean results require disposition

**Actor**: Workflow operator or delegated workflow runner.
**Preconditions**: A reviewer reports no blocking findings, but the review-loop
result indicates that reviewer policy still requires human attention.

**Steps**:

1. The operator runs the reviewer loop for the pull request.
2. The review result is clean for blocking readiness, but policy-review-required
   evidence is present.
3. The summary explains that the clean result still needs an advisory or policy
   disposition.
4. The operator records the policy disposition before the pull request is marked
   ready.

**Postconditions**: Clean reviewer-policy findings do not disappear into a
generic clean result; the summary records the operator's decision.

**Information shown**:

- Review status and policy-review-required indication.
- The reviewer or policy source that requested attention.
- Disposition and rationale.

**Actions available**:

- Accept the policy finding with rationale.
- Fix or adjust the pull request if the policy finding is material.
- Stop for human input when the policy finding cannot be evaluated safely.

**Considerations**:

- Policy-review-required evidence is non-blocking only after it has been
  acknowledged through a disposition.

### Use Case 3: PR-Agent advisory labels keep existing disposition behavior

**Actor**: Workflow operator reviewing a clean PR-Agent result.
**Preconditions**: PR-Agent reports advisory labels in a clean review-loop run.

**Steps**:

1. The operator runs the reviewer loop.
2. The summary lists PR-Agent advisory labels and their linked source comment.
3. The operator reviews the source comment.
4. The operator records a disposition for each advisory label, as the current
   workflow expects.

**Postconditions**: Existing PR-Agent advisory disposition behavior continues to
work while sharing the same readiness expectation as Haystack advisory results.

**Information shown**:

- Advisory label names.
- Source comment links.
- Disposition and rationale.

**Actions available**:

- Fix, accept, defer, or escalate each advisory label.

**Considerations**:

- Existing PR-Agent advisory handling should not regress while Haystack
  advisory handling is added.

## Business Rules

- A clean reviewer-loop result still requires advisory disposition when any of
  these evidence types are present:
  - Advisory count is greater than zero.
  - Policy review is required.
  - Advisory labels are present.
- Each listed advisory finding must receive an explicit disposition before the
  pull request is treated as ready for human review or delegated merge.
- Haystack advisory details must appear in the reviewer-loop summary when
  structured Haystack advisory data is available.
- Reviewer-loop summaries must preserve the existing blocking/advisory counts
  and readiness result.
- Advisory-only findings remain non-blocking unless a disposition determines the
  finding is material enough to require changes or escalation.
- Missing optional advisory metadata, such as file location or fix guidance,
  must not suppress a required disposition.
- The workflow must continue to support existing PR-Agent advisory-label
  disposition behavior.

## Statuses / Enum Values

No workflow item statuses are introduced. The feature preserves existing
review-loop result values:

| Result value  | Display label | Description |
| ------------- | ------------- | ----------- |
| `clean`       | Clean         | No blocking findings remain; advisory dispositions may still be required. |
| `needs_fixes` | Needs fixes   | One or more blocking findings must be addressed before readiness. |
| `skipped`     | Skipped       | A reviewer did not produce a completed review result. |
| `escalate`    | Escalate      | The review loop cannot determine readiness safely. |

Advisory disposition uses these user-facing decision labels:

| Decision value | Display label | Description |
| -------------- | ------------- | ----------- |
| `fixed`        | Fixed         | The advisory was addressed in the pull request. |
| `accepted`     | Accepted      | The advisory was reviewed and intentionally accepted with rationale. |
| `deferred`     | Deferred      | The advisory was not fixed now and has explicit follow-up context. |
| `escalated`    | Escalated     | The advisory needs human input before readiness can continue. |

## Operational Visibility

- **Reviewer-loop summary**: Lists advisory findings from PR-Agent labels,
  Haystack structured advisory output, and policy-review-required evidence.
- **Disposition record**: Shows one disposition per advisory finding, including
  rationale for accepted, deferred, or escalated findings.
- **Readiness signal**: A pull request is not considered fully ready until
  advisory evidence has been dispositioned.
- **Audit trail**: Delegated runs can reuse the summary and disposition evidence
  when preparing PR disposition audit comments.

## Acceptance Criteria

- [ ] AC-1: When a clean reviewer-loop result includes an advisory count greater
      than zero, the advisory-disposition step is required before readiness is
      complete.
- [ ] AC-2: When a clean reviewer-loop result indicates policy review is
      required, the advisory-disposition step is required before readiness is
      complete.
- [ ] AC-3: When a clean reviewer-loop result includes advisory labels, existing
      advisory-label disposition behavior still runs.
- [ ] AC-4: When Haystack structured advisory details are available, the
      reviewer-loop summary lists the individual Haystack advisories instead of
      only reporting an advisory count.
- [ ] AC-5: Every advisory shown in the summary can be marked fixed, accepted
      with rationale, deferred with follow-up context, or escalated for human
      input.
- [ ] AC-6: Advisory-only Haystack results remain non-blocking after required
      dispositions are recorded.
- [ ] AC-7: A smoke test or harness case covers a Haystack-only clean result with
      advisory findings and verifies that disposition handling is triggered.

## Coverage Matrix

| Brief objective | Covered by |
| --------------- | ---------- |
| Require the Protocol 93 advisory-disposition step when advisory count, policy-review-required, or advisory-label evidence is present. | AC-1, AC-2, AC-3 |
| Show Haystack advisory details from structured output in the reviewer-loop summary comment. | AC-4, AC-5 |
| Cover the Haystack-only clean-with-advisories path with a smoke test or harness scenario. | AC-6, AC-7 |

## Out of Scope (MVP)

- Changing reviewer severity classification rules.
- Making all advisory findings blocking by default.
- Creating the machine-readable false-positive catalog tracked by #1115.
- Adding new Haystack configuration fields tracked by #1116.
- Unifying advisory contracts across every review platform beyond the evidence
  needed for this trigger behavior.
- Changing GitHub project statuses or workflow item lifecycle states.
