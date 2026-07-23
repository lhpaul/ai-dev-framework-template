# Advisory Checks Hook for Reviewer Loop - Spec

---

## Overview

Projects using the automated pull-request reviewer loop need an optional way to
surface project-specific, diff-scoped static-analysis results alongside the
normal platform-review summary. Today these checks require downstream projects
to maintain local reviewer-loop modifications, making template updates harder to
adopt.

This feature adds a standard, opt-in advisory-check extension point. Projects
can customize the supplied no-op entry point to report additional findings in
the existing reviewer summary without changing the reviewer-loop result,
readiness decision, or exit behavior.

## Brief Objective List

Derived from issue #1279:

1. Provide reviewer-summary support for a dedicated advisory-checks section.
2. Run a project-provided advisory-check extension after platform reviews and
   before the final reviewer result is reported.
3. Ship a minimal no-op advisory-check entry point that downstream projects can
   customize or leave unchanged.
4. Preserve safe no-op behavior when the pull request identifier is absent or
   the advisory-check extension is unavailable.
5. Keep advisory-check output informational: it must not change the aggregate
   reviewer result or process exit outcome.
6. Verify the missing-input, missing-extension, and summary-ordering paths.

## Use Cases

### Use Case 1: Project surfaces additional static-analysis findings

**Actor**: Project maintainer configuring the automated reviewer workflow.
**Preconditions**: The project has customized the advisory-check extension, and
the reviewer loop is processing a pull request with a valid identifier.

**Steps**:

1. The reviewer loop completes its configured platform-review phases.
2. The project advisory-check extension evaluates the pull-request change.
3. The reviewer loop includes any returned advisory output in the existing
   final reviewer summary under a distinct advisory-checks section.
4. The reviewer loop reports its aggregate result using the same platform
   review and blocking-finding rules that applied before this feature.

**Postconditions**: Humans can see project-specific advisory findings in the
reviewer summary, while the reviewer-loop result and exit outcome remain
unchanged by those findings.

**Information shown**:

- The existing aggregate reviewer result.
- Existing platform-review finding counts and phase information.
- A distinct advisory-checks section when the project extension returns
  non-empty output.
- Existing regression-readiness annotations, when applicable.

**Actions available**:

- A maintainer can customize the project advisory checks.
- A reviewer can inspect advisory findings and decide whether to act on them.
- The workflow can continue according to the normal reviewer-loop result.

**Considerations**:

- Advisory output may identify useful cleanup without creating a new blocking
  severity or readiness gate.
- Multiple lines of advisory output must remain readable within the stable
  reviewer summary.

### Use Case 2: Project leaves advisory checks unconfigured

**Actor**: Workflow operator running the automated reviewer loop.
**Preconditions**: The project uses the supplied no-op entry point, or the
project advisory-check extension is unavailable.

**Steps**:

1. The reviewer loop completes its configured platform-review phases.
2. The loop finds no project advisory output to report.
3. The loop posts or updates the normal reviewer summary without an empty
   advisory-checks section.
4. The loop returns its normal aggregate result and exit outcome.

**Postconditions**: Projects that do not customize advisory checks observe the
same reviewer-loop behavior and summary content as before this feature.

**Information shown**:

- The existing reviewer summary, without empty advisory-check noise.

**Actions available**:

- Continue using the reviewer loop without project customization.
- Customize the supplied entry point later.

**Considerations**:

- An unavailable optional extension is a supported no-op state, not a workflow
  failure.

### Use Case 3: Reviewer loop has no pull request identifier

**Actor**: Workflow operator or test harness invoking the reviewer loop without
a pull request identifier.
**Preconditions**: The advisory-check phase is reached without a usable pull
request identifier.

**Steps**:

1. The reviewer loop recognizes that the advisory check lacks the pull-request
   context it needs.
2. The loop skips the optional advisory-check extension.
3. The loop preserves its existing result, summary behavior, and exit outcome.

**Postconditions**: Missing pull-request context cannot cause an advisory check
to run against an unintended target or turn an optional check into a failure.

**Information shown**:

- No advisory-check section is added solely because the optional phase was
  skipped.

**Actions available**:

- Correct the invocation when pull-request-specific advisory output is desired.
- Continue exercising non-pull-request reviewer-loop paths safely.

**Considerations**:

- The skip must not mask an otherwise blocking platform-review result.

### Use Case 4: Advisory extension reports an error

**Actor**: Workflow operator running a project-customized advisory extension.
**Preconditions**: A valid pull request is being reviewed, but the optional
advisory extension cannot complete successfully.

**Steps**:

1. The reviewer loop attempts the optional advisory extension after platform
   reviews.
2. The extension returns an error and may return diagnostic advisory text.
3. The loop preserves any useful returned text as advisory information when
   available.
4. The loop still derives its aggregate result and exit outcome exclusively
   from the normal reviewer-loop gates.

**Postconditions**: An advisory-extension failure cannot convert a clean review
to a blocking result or override an existing blocking result.

**Information shown**:

- Useful advisory diagnostic text when the extension provides it.
- The unchanged platform-derived reviewer result.

**Actions available**:

- Maintainers can repair the project advisory extension independently.
- Reviewers can continue or stop based on the normal reviewer-loop result.

**Considerations**:

- Optional advisory failures must not be presented as successful blocking-gate
  enforcement.

## Business Rules

- BR-1: The advisory-check extension is opt-in and project-customizable; its
  supplied default behavior produces no advisory findings.
- BR-2: The advisory-check phase runs only after configured platform reviews
  have completed and before the final reviewer result is reported.
- BR-3: The advisory-check phase runs only when both a usable pull-request
  identifier and an available project advisory extension are present.
- BR-4: Missing pull-request context, an unavailable extension, or empty
  advisory output produces a no-op without an empty summary section.
- BR-5: Non-empty advisory output appears in a distinct advisory-checks section
  of the stable reviewer summary.
- BR-6: Within the summary's findings area, advisory-check output follows
  platform-review and phase/comparison details and precedes any
  regression-readiness annotation.
- BR-7: Advisory output and advisory-extension failures never change the
  aggregate reviewer result, blocker count, readiness decision, or process exit
  outcome.
- BR-8: Existing behavior for clean, skipped, needs-fixes, and escalated
  reviewer-loop outcomes remains authoritative and unchanged.
- BR-9: Advisory output is informational; acting on it is a reviewer or
  maintainer decision unless a separate existing gate independently reports the
  same concern as blocking.

## Operational Visibility

- **Reviewer summary**: Non-empty project advisory output is visible under a
  distinct advisory-checks section in the existing stable summary comment.
- **No-op visibility**: Unconfigured or empty advisory checks add no empty
  headings, placeholders, or failure noise to the summary.
- **Result integrity**: The normal aggregate result, blocking count, and exit
  outcome remain visible and authoritative.
- **Failure containment**: A broken optional advisory extension cannot suppress
  or replace platform-review findings.

## Workflow Decision-Gate Matrix

| Pull request context | Advisory extension state | Advisory output | Allowed reviewer outcome | Required next action | Mirror surfaces / examples |
| --- | --- | --- | --- | --- | --- |
| Valid identifier | Available and successful | Non-empty | Preserve platform-derived `clean`, `skipped`, `needs_fixes`, or `escalate` result | Append distinct advisory-checks content, then report the normal final result | Reviewer-loop summary format and reviewer-loop tests |
| Valid identifier | Available and successful | Empty | Preserve platform-derived result | Omit advisory-checks section, then report the normal final result | Reviewer-loop summary format and no-op test |
| Valid identifier | Unavailable | Not applicable | Preserve platform-derived result | Skip advisory phase without noise, then report the normal final result | Optional-extension guard and missing-extension test |
| Missing or empty identifier | Available or unavailable | Not applicable | Preserve the existing non-advisory path outcome | Do not invoke the advisory extension; do not target an inferred pull request | Input guard and empty-identifier test |
| Valid identifier | Available but returns an error | Diagnostic text may be present | Preserve platform-derived result and exit outcome | Include useful returned text as advisory information when present; never promote it to a blocker | Advisory-only invariant and error-path test |
| Any | Any | Any | Existing platform review reports blocking findings | Keep the existing blocking outcome | Advisory content may be shown, but the normal fix/escalation path remains authoritative |

## Acceptance Criteria

- [ ] AC1: Given a valid pull request and a customized advisory extension that
      returns non-empty output, the final reviewer summary includes that output
      in a distinct advisory-checks section.
- [ ] AC2: Given advisory output is included, it appears after existing
      platform-review phase/comparison details and before any
      regression-readiness annotation in the findings area.
- [ ] AC3: Given the supplied advisory extension is left unchanged, the reviewer
      summary contains no empty advisory-checks section and existing result and
      exit behavior are unchanged.
- [ ] AC4: Given the project advisory extension is unavailable, the reviewer
      loop skips it without error and preserves its existing summary, aggregate
      result, and exit outcome.
- [ ] AC5: Given the pull request identifier is empty or missing, the reviewer
      loop does not invoke the advisory extension and does not infer a target.
- [ ] AC6: Given the advisory extension returns diagnostic output and a
      non-success outcome, useful returned text may be shown as advisory, but
      the aggregate result, blocker count, readiness decision, and process exit
      outcome remain determined only by the existing reviewer-loop gates.
- [ ] AC7: Given the normal reviewer platforms return `needs_fixes` or
      `escalate`, advisory output does not downgrade, replace, or hide that
      outcome.
- [ ] AC8: Given a project wants custom diff-scoped analysis, it can customize
      the supplied no-op advisory entry point without maintaining a private
      modification to the reviewer-loop summary flow.
- [ ] AC9: Automated coverage verifies the empty-identifier,
      missing-extension, empty-output, non-empty-output ordering, and
      advisory-only result-integrity paths.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Add a dedicated advisory-checks section to the reviewer summary | Use Case 1, BR-5, BR-6, Operational Visibility | AC1, AC2 |
| 2. Run project advisory checks after platform reviews and before final reporting | Use Case 1, BR-2, Decision-Gate Matrix | AC1, AC2 |
| 3. Ship a customizable minimal no-op entry point | Use Case 2, BR-1 | AC3, AC8 |
| 4. Safely handle empty pull-request context and unavailable extension | Use Cases 2 and 3, BR-3, BR-4 | AC4, AC5 |
| 5. Keep all advisory behavior non-blocking | Use Cases 1 and 4, BR-7 through BR-9 | AC6, AC7 |
| 6. Test guard paths and summary ordering | Decision-Gate Matrix | AC9 |

## Out of Scope (MVP)

- Defining a universal catalog of project advisory checks.
- Making advisory findings blocking or adding a new readiness severity.
- Changing platform-review aggregation, retry budgets, reviewer ordering, or
  blocker classification.
- Changing CI, regression, tracker-status, merge-authority, or human-checkpoint
  gates.
- Prescribing which static-analysis tools downstream projects must use.
- Backfilling advisory output into reviewer summaries created before this
  feature ships.
