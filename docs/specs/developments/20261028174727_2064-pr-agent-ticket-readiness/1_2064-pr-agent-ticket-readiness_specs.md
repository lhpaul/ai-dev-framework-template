# PR-Agent ticket analysis and downstream readiness — Spec

## Overview

PR-Agent can mistake an epic or a contextual issue reference for the full scope
of a pull request. Ticket analysis must not prevent an otherwise clean code
review from reaching readiness. Downstream maintainers must receive this
behavior through ordinary template synchronization, without editing their
existing PR-Agent configuration or forcing reviewer overrides.

Source: issue #2064. This is a bug correction to the existing reviewer workflow.
The issue's acceptance criteria and the invocation's scope restriction are the
alignment baseline. No new application UI, analytics, actors, or permissions
are introduced.

## Use Cases

### Use Case 1: Review a pull request that mentions an epic

**Actor**: Maintainer or workflow runner.
**Preconditions**: A downstream repository has synchronized the correction; its
existing PR-Agent configuration may still enable ticket analysis.

**Steps**:

1. Submit a pull request mentioning an epic or a contextual issue.
2. Run the normal configured reviewers and CI.
3. Inspect the reviewer outcome and readiness decision.

**Postconditions**: A structurally valid ticket analysis reporting partial or
missing compliance, or asking for human verification of ticket requirements,
does not independently produce a blocking code finding or escalation. Clean
code reviews can advance through the existing reviewer sequence.

**Information shown**: Ticket commentary remains available in the review.
**Actions available**: Address actual code findings through the existing loop.

### Use Case 2: Synchronize an older downstream configuration

**Actor**: Downstream maintainer running template synchronization.
**Preconditions**: The downstream PR-Agent configuration lacks the setting that
disables ticket analysis, or explicitly enables it.

**Steps**:

1. Run normal template synchronization.
2. Inspect configuration guidance emitted by synchronization.
3. Run the normal review workflow without a manual configuration edit.

**Postconditions**: The maintainer receives an actionable warning about enabled
or unspecified ticket analysis. The corrected readiness behavior applies even
if the maintainer keeps the existing configuration. Synchronization preserves
project-owned configuration and the configured model and credentials.

## Business Rules

- BR1: Recognized ticket compliance commentary is informational for automated
  readiness. This includes partial compliance, non-compliance, and requests to
  verify ticket requirements. It does not certify that an epic is complete.
- BR2: Informational treatment applies only to a structurally valid, recognized
  ticket-analysis section. Unknown statuses, missing evidence, duplicate or
  malformed sections, and incomplete review output continue to escalate.
- BR3: Human-verification requests outside the ticket-analysis section continue
  to escalate. Security findings and blocking code focus areas retain their
  existing classifications.
- BR4: The correction must not suppress separate verification requests, bypass
  configured reviewers, resolve review threads automatically, or weaken CI,
  checkpoint, or merge gates.
- BR5: Existing downstream configuration remains project-owned. Synchronization
  must not overwrite it just to disable ticket analysis. Its warning identifies
  the relevant setting and the supported corrective action without exposing
  configuration values unrelated to the warning.
- BR6: Configuration guidance must describe the actual readiness behavior and
  explain why ticket analysis is disabled in the template.

## Decision-Gate Consistency Matrix

Rows are evaluated with malformed output and independent blocking findings
taking precedence over informational ticket commentary.

| Inputs | Allowed outcome | Required next action | Surfaces |
| --- | --- | --- | --- |
| Valid ticket analysis; partial or non-compliant ticket; code review clean | Clean | Continue normal reviewer sequence | Classifier, reviewer loop, readiness |
| Valid ticket analysis; ticket-only human verification; code review clean | Clean | Continue normal reviewer sequence | Classifier, reviewer loop, readiness |
| Valid ticket analysis; blocking code finding | Needs fixes | Correct code and rerun review | Classifier, reviewer loop, readiness |
| Valid ticket analysis; independent human-verification request | Escalate | Preserve existing escalation path | Classifier, reviewer loop, readiness |
| Unknown ticket status, malformed or duplicate heading, missing or truncated analysis | Escalate | Preserve existing escalation path | Classifier, reviewer loop, readiness |
| No ticket analysis | Existing classification | Follow existing reviewer result | Classifier, reviewer loop, readiness |
| Downstream ticket setting absent or enabled | Configuration warning | Explain supported disabling setting; preserve configuration | Template synchronization, integration guidance |
| Downstream ticket analysis explicitly disabled | No ticket-setting warning | Continue synchronization | Template synchronization, integration guidance |

The examples above are synthetic behavioral cases. This correction introduces
no new readiness labels, lifecycle states, or machine-readable outcomes.

## Operational Visibility

Ticket commentary stays visible in PR-Agent's review, while the existing
reviewer-loop summary reports code-review outcomes. Synchronization explains
the downstream configuration warning and the maintainer's next action. No new
notification destination or audit store is required.

## Acceptance Criteria

- [ ] AC1: After synchronization, a downstream pull request mentioning an epic
  and a contextual issue reaches normal readiness with clean code reviewers
  and green CI, without forcing reviewers or editing its existing PR-Agent
  configuration.
- [ ] AC2: Synthetic cases covering valid partial compliance, non-compliance,
  and ticket-only human-verification commentary classify as clean when the
  remainder of the code review is clean.
- [ ] AC3: Synthetic malformed, ambiguous, duplicate, unknown-status, and
  truncated reviews still escalate. Existing regression coverage for #1946,
  #1948, and #1985 remains passing.
- [ ] AC4: Synthetic reviews combining informational ticket commentary with
  blocking code findings or independent human-verification requests retain
  their existing needs-fixes or escalation outcome, respectively.
- [ ] AC5: Synthetic synchronization scenarios warn when ticket analysis is
  absent or enabled, do not warn when explicitly disabled, and leave downstream
  configuration unchanged.
- [ ] AC6: The template configuration comment and integration guidance agree
  with the corrected classifier behavior. The implementation includes a
  changelog fragment.

## Brief Objective List and Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Deliver correction through a synchronized surface | AC1, AC5; BR5 |
| Make ticket commentary non-blocking without weakening malformed-output handling | AC2–AC4; BR1–BR4 |
| Correct the stale configuration comment | AC6; BR6 |
| Preserve expensive-reviewer progress | AC1; normal sequence advances after clean classification |
| Synthetic regression tests and changelog | AC2–AC6 |

## Out of Scope (MVP)

- Altering the expensive-reviewer gate or introducing a forced-reviewer path.
- Changing GitHub workflow permissions, triggers, or container environment.
- Overwriting downstream PR-Agent configuration, changing its model, or
  introducing a separate configurable ticket-compliance enforcement mode.
- Reworking issue linking, epic completion, manual checkpoints, review-thread
  resolution, or the independent evidence-verification workflow.
- Live changes to consumer repositories or tests using private data.

## Deferral Notes

The optional independent expensive-reviewer bypass is omitted because removing
the false ticket blocker lets the existing sequence advance. The synchronized
configuration warning is the alternative explicitly offered by the issue;
changing the GitHub workflow is unnecessary for the acceptance criteria.
