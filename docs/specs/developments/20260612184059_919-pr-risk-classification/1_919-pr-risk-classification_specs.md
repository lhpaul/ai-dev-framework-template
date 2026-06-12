# PR Risk Classification for Delegated Merge Decisions - Spec

**Depends on**: 917-run-epic-scope-resolver

---

## Overview

Delegated epic runs need a conservative, repeatable way to decide whether a PR
is safe for an agent to merge without another human checkpoint. This feature
adds PR risk classification to `/run-epic` delegated decision-making so every
candidate PR receives a visible risk level, reasons, and a merge/no-merge
decision against the invocation's maximum allowed risk. The classifier is a
gate: it does not replace reviewer-loop, CI, labels, merge-state, or unresolved
thread checks.

## Brief Objective List

1. Produce machine-readable and human-readable risk classification for each PR
   considered by `/run-epic`.
2. Explain the reasons for each assigned risk level.
3. Block autonomous merge when risk exceeds `--max-risk`.
4. Always block autonomous merge for reviewer failures, failing or pending
   required CI, unresolved blocking review threads, `needs-setup`, missing
   credentials, ambiguous scope, unsafe merge state, destructive action
   requirements, force-push requirements, or unclear tracker/base state.
5. Define conservative low, medium, high, and blocked risk levels.
6. Require representative test coverage for low, medium, high, and blocked
   cases.
7. Require medium-risk autonomous merge decisions to include a visible "why
   safe to merge" explanation covering scope, tests, reviewer outcome, CI, and
   rollback or cleanup risk.
8. Keep the rules easy to update as the workflow learns from real delegated
   runs.

## Use Cases

### Use Case 1: Classify a PR before delegated merge

**Actor**: Workflow owner agent running an explicitly delegated `/run-epic`
session
**Preconditions**: A resolved epic or item-list run has found a PR that reached
the delegated review gate, and the invocation includes a maximum allowed risk.

**Steps**:

1. The actor evaluates the PR using current PR state, reviewer-loop outcome,
   CI outcome, labels, thread state, merge state, tracker state, target base,
   and changed-work category.
2. The classifier assigns one risk level: Low, Medium, High, or Blocked.
3. The classifier records the reasons that led to that level.
4. The actor compares the assigned level to the invocation's maximum allowed
   risk.
5. The actor either permits the delegated merge decision to continue or blocks
   the merge and reports why.

**Postconditions**: The PR has a visible risk classification and the delegated
run has a deterministic merge/no-merge gate before any merge action occurs.

**Information shown**:

- Assigned risk level and display label.
- Reasons for the assigned level.
- Maximum allowed risk for the invocation.
- Whether the risk gate permits merge consideration.
- Any blocking conditions that must be fixed or escalated.

**Actions available**:

- Continue to merge only if all other readiness gates are also clean.
- Fix blocking conditions and rerun classification.
- Escalate to a human when the PR exceeds the allowed risk.
- Record the decision in the delegated audit trail when that feature is
  available.

**Considerations**:

- Risk classification is conservative. If the classifier cannot prove that a PR
  is within the allowed risk, it must block or escalate rather than guess.
- A permitted risk level does not by itself authorize a merge; review, CI,
  labels, merge state, and thread checks must still pass.

### Use Case 2: Explain why a medium-risk PR is safe to merge

**Actor**: Workflow owner agent running an explicitly delegated `/run-epic`
session
**Preconditions**: A PR is classified as Medium risk and the invocation permits
medium-risk autonomous merges.

**Steps**:

1. The classifier identifies the PR as Medium risk because it changes workflow
   scripts, orchestration behavior, merge or cleanup automation, or other shared
   workflow tooling with contained blast radius.
2. The actor confirms that reviewer-loop, CI, readiness labels, merge state, and
   unresolved thread checks are clean.
3. The classifier emits a "why safe to merge" explanation.
4. The actor uses that explanation as part of the delegated merge decision.

**Postconditions**: A medium-risk autonomous merge decision is auditable and
includes enough evidence to understand why the agent did not escalate to a
human.

**Information shown**:

- Scope of changed behavior.
- Tests or validation that cover the behavior.
- Reviewer-loop disposition.
- CI outcome.
- Rollback or cleanup risk notes.

**Actions available**:

- Continue to merge if all merge gates permit it.
- Accept low-value advisories with rationale.
- Fix advisories that materially affect safety, maintainability, test
  coverage, security, or workflow reliability.
- Escalate if the "why safe" explanation cannot be completed.

**Considerations**:

- Medium risk is expected for many workflow-script changes even when reviewers
  are clean.
- Missing evidence for any required explanation field blocks autonomous merge.

### Use Case 3: Block unsafe or high-risk PRs

**Actor**: Workflow owner agent running an explicitly delegated `/run-epic`
session
**Preconditions**: A PR has one or more conditions that make autonomous merge
unsafe.

**Steps**:

1. The classifier evaluates hard-blocking conditions before assigning ordinary
   Low, Medium, or High risk.
2. If a hard-blocking condition exists, the classifier assigns Blocked.
3. If no hard blocker exists but the PR touches high-risk areas, the classifier
   assigns High.
4. The actor blocks merge when the risk level exceeds the invocation's maximum
   risk or when the level is Blocked.
5. The actor reports the blocker or escalation reason.

**Postconditions**: Unsafe PRs are not merged autonomously, and the delegated
run has an actionable explanation for what must change or who must decide.

**Information shown**:

- Blocking condition or High-risk reason.
- Whether the condition is fixable by the agent or requires human decision.
- The next deterministic action, if one exists.

**Actions available**:

- Remove readiness labels and fix concrete reviewer or CI failures.
- Re-run validation, reviewer-loop, CI-loop, and risk classification.
- Escalate to a human when the risk exceeds delegated authority.
- Stop when credentials, external services, or destructive action approval is
  required.

**Considerations**:

- Blocked is not a mergeable risk level.
- High risk may be mergeable only when the invocation explicitly permits high
  risk and no hard-blocking condition remains.

## Business Rules

- Every PR considered by delegated `/run-epic` merge behavior must receive one
  risk classification before merge.
- Risk levels are Low, Medium, High, and Blocked.
- Blocked takes precedence over Low, Medium, and High.
- Merge is blocked when the assigned risk exceeds the invocation's maximum
  allowed risk.
- Merge is always blocked for failing, pending, unavailable, or ambiguous
  required CI.
- Merge is always blocked for configured reviewer failure, unresolved blocking
  review threads, `needs-setup`, missing credentials, ambiguous tracker state,
  unclear target or base branch, dirty or ambiguous merge state, required
  force-push, or destructive action requirement.
- Low risk is limited to docs, tests, narrow workflow text, or isolated helper
  changes with clean review, clean CI, clear tracker/base state, and no
  unresolved blockers.
- Medium risk includes workflow scripts, orchestration behavior, merge or
  cleanup automation, and other shared workflow tooling with contained blast
  radius.
- High risk includes auth, secrets, GitHub permissions, release automation,
  branch deletion behavior, cross-repo PR credentials, broad shared libraries,
  and unclear behavior changes.
- Medium-risk autonomous merge decisions require a visible "why safe to merge"
  explanation.
- The classifier must explain every assigned level with specific reasons.
- The risk rules must be conservative and updateable without changing the
  delegated workflow contract.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `low` | Low | The PR has narrow, low-blast-radius changes and all readiness evidence is clean. |
| `medium` | Medium | The PR changes workflow behavior or shared tooling with contained blast radius and clean readiness evidence. |
| `high` | High | The PR touches sensitive or broad areas that usually require explicit human tolerance. |
| `blocked` | Blocked | The PR has a hard blocker, ambiguous state, unavailable dependency, or required human/destructive action. |

**Valid transitions**:

- Blocked -> Low, Medium, or High after the hard blocker is fixed and the run
  reclassifies the PR.
- High -> Medium or Low only when the changed scope or evidence changes enough
  to justify a lower classification.
- Medium -> Blocked when a readiness gate fails, reviewer blocker appears, or
  required evidence becomes unavailable.
- Any level -> Blocked when required state is ambiguous or stale.

## Operational Visibility

- **Risk summary**: Each classified PR shows risk level, max allowed risk, merge
  gate result, and reasons.
- **Blocked reason**: Blocked PRs show the specific failed gate or missing
  decision.
- **Medium-risk merge rationale**: Medium-risk PRs that remain mergeable include
  a "why safe to merge" explanation covering scope, tests, reviewer outcome, CI,
  and rollback or cleanup risk.
- **Audit handoff**: The classification output is suitable for PR disposition
  comments and epic ledger entries when the audit trail feature is available.

## Acceptance Criteria

- [ ] AC1: Given a PR considered by delegated `/run-epic`, the classifier
      produces both a machine-readable and human-readable risk classification.
- [ ] AC2: Every classification includes specific reasons for the assigned risk
      level.
- [ ] AC3: Given a PR whose risk exceeds the invocation's maximum allowed risk,
      the classifier blocks autonomous merge and explains the mismatch.
- [ ] AC4: Given failing or pending required CI, configured reviewer failure,
      unresolved blocking review threads, `needs-setup`, missing credentials,
      ambiguous tracker state, unclear target/base branch, dirty merge state,
      required force-push, or required destructive action, the classifier assigns
      Blocked.
- [ ] AC5: Given docs, tests, narrow workflow text, or isolated helper changes
      with clean evidence and no blockers, the classifier can assign Low.
- [ ] AC6: Given workflow scripts, orchestration behavior, merge or cleanup
      automation, or shared workflow tooling with contained blast radius and
      clean evidence, the classifier can assign Medium.
- [ ] AC7: Given auth, secrets, GitHub permissions, release automation, branch
      deletion behavior, cross-repo PR credentials, broad shared libraries, or
      unclear behavior changes, the classifier can assign High.
- [ ] AC8: Given a Medium-risk PR that is allowed by `--max-risk`, the classifier
      produces a "why safe to merge" explanation covering scope, tests, reviewer
      outcome, CI, and rollback or cleanup risk.
- [ ] AC9: Representative Low, Medium, High, and Blocked cases are covered by
      tests or fixtures.
- [ ] AC10: The risk rules are visible enough for maintainers to update as the
      workflow learns from future delegated runs.

## Out of Scope (MVP)

- Merging PRs directly from the classifier.
- Writing PR disposition comments or epic ledger entries.
- Replacing reviewer-loop, CI-loop, unresolved-thread audits, readiness labels,
  or repository merge protocols.
- Persistent repository-wide autonomy defaults.
- Non-PR work item risk scoring.

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Produce machine-readable and human-readable risk classification for each PR considered by `/run-epic`. | Use Case 1, BR1, AC1 |
| Explain the reasons for each assigned risk level. | Use Case 1, Use Case 3, BR11, AC2 |
| Block autonomous merge when risk exceeds `--max-risk`. | Use Case 1, Use Case 3, BR4, AC3 |
| Always block autonomous merge for reviewer, CI, setup, credential, scope, merge-state, destructive-action, and tracker/base ambiguity hazards. | Use Case 3, BR5-BR6, AC4 |
| Define conservative low, medium, high, and blocked risk levels. | Business Rules, Statuses / Enum Values, AC5-AC7 |
| Require representative test coverage for low, medium, high, and blocked cases. | AC9 |
| Require medium-risk autonomous merge decisions to include a "why safe to merge" explanation. | Use Case 2, BR10, Operational Visibility, AC8 |
| Keep the rules easy to update as the workflow learns from real delegated runs. | BR12, AC10 |
