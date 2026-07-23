# Haystack Large-PR Analysis Skip - Spec

---

## Overview

The automated reviewer loop must recognize when Haystack declines to analyze a
pull request because the change exceeds its supported file limit. That outcome
is a terminal platform skip, not an unresolved review, so operators should
receive a prompt aggregate result instead of waiting through an extended
large-diff polling window.

This change also preserves durable reviewer-loop evidence: the workflow-owned
summary must record the skip reason and history even when Haystack never
produces a normal review. Template-sync pull requests are the primary recurring
case, but the behavior applies to any pull request with an authoritative
Haystack file-limit skip.

## Brief Objective List

Derived from issue #1311:

1. Detect an authoritative Haystack “Analysis Skipped” or equivalent file-limit
   outcome from the review surfaces available to the reviewer loop.
2. Treat the recognized outcome as a terminal Haystack skip and stop waiting
   through the extended large-diff polling window.
3. Allow the aggregate reviewer-loop result to remain clean/skipped when
   Haystack's file-limit skip is the only non-clean platform outcome.
4. Document that large template-sync pull requests may skip Haystack by design
   while other configured review platforms still determine aggregate
   readiness.
5. Ensure the workflow-owned Automated Reviewer Loop Summary retains durable
   reviewer-loop history when Haystack is skipped for the file limit.

---

## Use Cases

### Use Case 1: Large pull request receives a terminal Haystack skip

**Actor**: Workflow operator running the automated reviewer loop.
**Preconditions**: A pull request is eligible for Haystack review, Haystack has
reported that analysis was skipped because the pull request exceeds its file
limit, and no other configured reviewer has reported a blocking finding.

**Steps**:

1. The operator runs or resumes the automated reviewer loop.
2. The loop observes Haystack's authoritative file-limit skip outcome.
3. The loop records Haystack as skipped with a file-limit reason and stops
   waiting for a normal Haystack review.
4. The loop evaluates the remaining configured reviewer outcomes.
5. The loop posts or updates its workflow-owned summary with the aggregate
   outcome and durable history.

**Postconditions**: The reviewer loop completes without consuming the extended
large-diff wait solely for Haystack, and the pull request may continue through
readiness when every other required gate is clean or permissibly skipped.

**Information shown**:

- Haystack's platform outcome is `Skipped`.
- The reason identifies the analysis file limit rather than a timeout or
  reviewer failure.
- The aggregate reviewer-loop outcome and durable history are visible in the
  workflow-owned pull-request summary.

**Actions available**:

- Continue to the remaining readiness gates when the aggregate result permits.
- Investigate another reviewer outcome when it remains blocking.
- Re-run the reviewer loop safely; the same terminal skip remains observable.

**Considerations**:

- A file-limit skip must not be presented as a successful Haystack analysis.
- Ambiguous, unrelated, or stale messages must not be mistaken for the
  authoritative file-limit skip.

### Use Case 2: Another reviewer still blocks the pull request

**Actor**: Workflow operator.
**Preconditions**: Haystack has a recognized file-limit skip, but another
configured reviewer reports a blocking finding or required action.

**Steps**:

1. The reviewer loop records Haystack's terminal skip.
2. The loop continues evaluating the other configured reviewer outcomes.
3. The aggregate result reflects the outstanding blocker rather than being
   made clean by Haystack's skip.
4. The operator follows the existing reviewer-fix or escalation path.

**Postconditions**: Haystack no longer causes unnecessary polling, while real
blocking feedback from another platform remains authoritative.

**Information shown**:

- Haystack's skip reason.
- The platform and finding that keep the aggregate result blocked.
- The normal next action for fixes or escalation.

**Actions available**:

- Address blocking feedback and re-run the loop.
- Escalate under the existing retry and timeout policy when necessary.

### Use Case 3: Template-sync review explains expected Haystack coverage

**Actor**: Workflow operator reviewing a large template-sync pull request.
**Preconditions**: The template-sync pull request exceeds Haystack's supported
analysis size and the reviewer loop recognizes the terminal skip.

**Steps**:

1. The operator consults the template-sync or reviewer-loop guidance.
2. The guidance explains that Haystack may skip oversized template-sync pull
   requests by design.
3. The operator verifies that other configured reviewer, CI, and readiness
   gates completed according to their normal contracts.

**Postconditions**: The operator can distinguish an expected Haystack coverage
limit from a hung reviewer loop or a bypass of the remaining review gates.

**Information shown**:

- The documented meaning of a Haystack file-limit skip.
- The requirement that other configured readiness gates still pass.

**Actions available**:

- Proceed when all remaining gates permit.
- Investigate when the skip reason is absent or another gate is blocked.

---

## Business Rules

- BR-1: Only an authoritative Haystack outcome that explicitly states analysis
  was skipped because the pull request exceeds the supported file limit may be
  classified as the terminal file-limit skip.
- BR-2: Once that outcome is observed for the current review attempt, the
  reviewer loop must stop waiting for a normal Haystack review within the next
  standard observation cycle; it must not consume the remaining extended
  large-diff wait solely for Haystack.
- BR-3: The Haystack platform result must be `Skipped`, with a distinct
  file-limit reason visible to operators and durable review history.
- BR-4: A Haystack file-limit skip is permissive only for Haystack. It must not
  suppress, downgrade, or bypass blocking findings, required actions, CI
  failures, unresolved review threads, or readiness requirements from any
  other source.
- BR-5: When every other configured reviewer is clean or permissibly skipped,
  Haystack's file-limit skip must allow the aggregate reviewer-loop result to
  be clean/skipped rather than escalated or marked as needing fixes.
- BR-6: The workflow-owned Automated Reviewer Loop Summary must be posted or
  updated for this terminal skip and must include the durable reviewer-loop
  history expected by retrospective tooling.
- BR-7: Re-running the reviewer loop against the same authoritative skip must
  remain stable and must not restart an extended wait for a review Haystack has
  already declined to perform.
- BR-8: Template-sync guidance must explain that oversized pull requests may
  skip Haystack by design and that all other configured gates remain required.
- BR-9: Shared reviewer-loop terminology with sibling backlog items does not
  create an ordering dependency for this spec.

---

## Statuses / Enum Values

| Platform outcome | Display label | Description |
| --- | --- | --- |
| Terminal file-limit skip | Skipped | Haystack explicitly declined analysis because the pull request exceeded its supported file limit |
| Normal clean review | Clean | Haystack completed analysis without blocking findings |
| Blocking review outcome | Needs fixes | A configured reviewer reported actionable blocking feedback |
| Reviewer failure or exhausted wait | Escalated | The existing reviewer policy requires human intervention for an outcome other than the recognized file-limit skip |

**Valid transitions**:

- Awaiting Haystack review → `Skipped` when an authoritative file-limit skip is
  observed for the current review attempt.
- Awaiting Haystack review → `Clean`, `Needs fixes`, or `Escalated` under the
  existing reviewer-loop rules when the file-limit skip does not apply.
- Haystack `Skipped` + all other reviewers clean/permissibly skipped →
  aggregate clean/skipped.
- Haystack `Skipped` + any other blocking result → the existing aggregate
  blocking or escalation outcome.

---

## Operational Visibility

- **Pull-request summary**: The workflow-owned Automated Reviewer Loop Summary
  shows Haystack as skipped, identifies the file-limit reason, reports the
  aggregate result, and carries durable reviewer-loop history.
- **Runner output**: The operator can see that polling ended because a terminal
  skip was recognized, rather than because the review timed out or was
  manually aborted.
- **Documentation**: Template-sync and reviewer-loop guidance describes the
  expected skip and makes clear that remaining review and readiness gates are
  unchanged.

---

## Decision-Gate Consistency Matrix

| Gate input | Haystack outcome | Other reviewer outcomes | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- | --- |
| Authoritative file-limit skip for current attempt | Skipped with file-limit reason | All clean or permissibly skipped | Stop Haystack polling, post/update durable summary, continue to remaining readiness gates | Reviewer-loop behavior, Haystack integration guidance, template-sync guidance, workflow-owned summary | A 168-file template-sync pull request is explicitly declined by Haystack while the draft reviewer is clean |
| Authoritative file-limit skip for current attempt | Skipped with file-limit reason | At least one blocking result | Stop Haystack polling, preserve the other blocker, follow the existing fix/escalation path | Reviewer-loop behavior and workflow-owned summary | Haystack skips an oversized pull request but another reviewer requests changes |
| No authoritative file-limit skip | Existing clean, needs-fixes, timeout, or escalation behavior | Any | Follow the existing reviewer-loop contract without applying this exception | Reviewer-loop behavior and Haystack integration guidance | Haystack remains pending without an explicit file-limit message |
| Ambiguous, unrelated, or stale skip-like text | Not classified as the file-limit skip | Any | Continue normal validation/polling or use the existing escalation path | Reviewer-loop behavior and workflow-owned summary | An old comment mentions a file limit but does not represent the current Haystack attempt |

---

## Acceptance Criteria

- [ ] AC-1: Given a pull request with an authoritative Haystack
  “Analysis Skipped” file-limit outcome, the reviewer loop reports Haystack as
  `Skipped` with a distinct file-limit reason within the next standard
  observation cycle.
- [ ] AC-2: After AC-1's outcome is recognized, the reviewer loop completes
  without consuming the remaining extended large-diff polling window solely
  for Haystack.
- [ ] AC-3: When Haystack's recognized file-limit skip is the only non-clean
  platform outcome, the aggregate reviewer-loop result is clean/skipped and the
  pull request may advance to its remaining readiness gates.
- [ ] AC-4: When another configured reviewer has a blocking result, Haystack's
  file-limit skip does not change that aggregate blocking result or bypass the
  existing fix/escalation path.
- [ ] AC-5: The script-owned Automated Reviewer Loop Summary is posted or
  updated for the file-limit skip and contains the skip reason plus durable
  reviewer-loop history used by retrospective reporting.
- [ ] AC-6: Re-running the loop while the same authoritative file-limit skip is
  current produces the same terminal classification without beginning another
  extended wait.
- [ ] AC-7: Ambiguous, unrelated, or stale skip-like text is not classified as
  the terminal file-limit skip.
- [ ] AC-8: Reviewer-loop and template-sync guidance explain that oversized
  template-sync pull requests may skip Haystack by design and that other
  configured reviewer, CI, thread-resolution, and readiness gates remain
  required.

---

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Detect authoritative Haystack file-limit skip outcomes | BR-1, AC-1, AC-7 |
| 2. Stop extended polling after the terminal skip | BR-2, BR-7, AC-2, AC-6 |
| 3. Preserve clean/skipped aggregate behavior when other reviewers pass | BR-4, BR-5, AC-3, AC-4 |
| 4. Document expected template-sync behavior and remaining gates | BR-8, AC-8 |
| 5. Preserve a workflow-owned summary with durable reviewer history | BR-3, BR-6, AC-5 |

---

## Out of Scope (MVP)

- Increasing or removing Haystack's external analysis file limit.
- Splitting, shrinking, or otherwise rewriting template-sync pull requests to
  make them eligible for Haystack analysis.
- Treating a generic timeout, unavailable check, permission failure, or
  non-file-limit skip as the terminal file-limit outcome.
- Changing the blocking classification, retry budget, or readiness contract of
  any other automated reviewer, CI check, or review-thread gate.
- Replacing the workflow-owned reviewer-loop summary with a manual recovery
  comment.
