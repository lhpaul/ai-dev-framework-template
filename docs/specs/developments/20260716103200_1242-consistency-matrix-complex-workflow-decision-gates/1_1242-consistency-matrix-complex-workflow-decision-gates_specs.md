# Complex Workflow Decision Gate Consistency Matrix - Spec

---

## Overview

Complex workflow decision-gate changes should include a visible consistency
matrix before they are sent to PR review. The matrix gives authors and reviewers
a single place to verify gate inputs, allowed outcomes, next actions, and mirror
surfaces before external reviewers have to discover contradictions late in the
loop. This keeps complex protocol changes easier to review without changing the
normal staged workflow, automated review loop, or human merge gates.

## Brief Objective List

1. Require complex workflow decision-gate documentation changes to enumerate
   gate inputs, outcomes, next actions, and mirror surfaces before PR handoff.
2. Reduce late external-review churn caused by inconsistent gate wording,
   examples, labels, exit codes, or mirrored instructions.
3. Give authors and reviewers a repeatable pre-PR check for complex gate
   changes.
4. Allow simple documentation changes that do not alter a decision gate to stay
   outside the matrix requirement.
5. Preserve existing review, CI, readiness, and merge requirements.

## Use Cases

### Use Case 1: Author prepares a complex gate documentation PR

**Actor**: Workflow author changing decision-gate documentation.
**Preconditions**: The change adds or modifies a workflow gate whose behavior
depends on multiple inputs, outcomes, labels, status checks, examples, mirror
surfaces, or next-action branches.

**Steps**:

1. The author identifies that the change is a complex decision-gate change.
2. Before opening the PR, the author records a consistency matrix for the gate.
3. The matrix lists each gate input, every allowed outcome, the next action for
   each outcome, and every workflow surface that must use matching wording.
4. The author uses the matrix to check that the affected protocol, review
   contract, command guidance, skill guidance, and examples tell the same story.
5. The author includes the matrix or a pointer to it in the PR evidence expected
   by the workflow.

**Postconditions**: The PR reaches reviewer handoff with explicit evidence that
the gate behavior and mirrored wording were checked before external review.

**Information shown**:

- Gate name or decision point being changed.
- Inputs that influence the gate.
- Allowed outcomes and required next actions.
- Mirror surfaces that must stay consistent.
- Any input, outcome, example, or surface declared not applicable, with
  rationale.

**Actions available**:

- Proceed to PR handoff when the matrix is complete and internally consistent.
- Revise the change when the matrix exposes a missing outcome or contradictory
  mirror surface.
- Mark the matrix not applicable only when the change does not alter decision
  gate behavior.

**Considerations**:

- The matrix is evidence for consistency, not a replacement for the spec, plan,
  implementation, or reviewer-loop gates.
- The matrix should be concise enough to help reviewers scan the gate behavior.

### Use Case 2: Reviewer checks a complex gate PR

**Actor**: Spec, plan, or code reviewer evaluating a workflow decision-gate PR.
**Preconditions**: The PR changes a complex workflow decision gate.

**Steps**:

1. The reviewer looks for the consistency matrix or equivalent evidence.
2. The reviewer verifies that each gate input has a defined outcome and next
   action, or a not-applicable rationale when the input does not apply to this
   gate.
3. The reviewer compares the listed mirror surfaces against the PR diff.
4. The reviewer flags missing outcomes, contradictory wording, or omitted mirror
   surfaces before external review churn accumulates.

**Postconditions**: The reviewer can approve the consistency evidence or request
specific corrections before the PR is considered ready.

**Information shown**:

- Matrix coverage for the changed gate.
- Any unmatched or contradictory surface in the PR diff.
- Any missing example needed to make the gate behavior testable.

**Actions available**:

- Approve the matrix evidence.
- Request changes for a missing input, outcome, next action, mirror surface, or
  example.
- Accept a not-applicable rationale when the PR does not change gate behavior.

**Considerations**:

- Reviewers should not require a matrix for ordinary typo fixes, copy edits, or
  documentation changes that do not change decision-gate behavior.

### Use Case 3: Simple documentation PR bypasses the matrix

**Actor**: Workflow author making a simple documentation update.
**Preconditions**: The PR changes documentation but does not add or modify a
workflow decision gate.

**Steps**:

1. The author determines that the change does not affect gate behavior.
2. The author records that the consistency matrix is not applicable, when the PR
   evidence format asks for the check.
3. The PR proceeds through normal review without creating unnecessary matrix
   work.

**Postconditions**: Simple documentation work is not burdened by a gate-specific
check that does not apply.

**Information shown**:

- A short not-applicable rationale when matrix evidence is requested.

**Actions available**:

- Continue through normal documentation review.
- Reclassify as a complex gate change if review discovers gate behavior was
  affected.

**Considerations**:

- The not-applicable path prevents the requirement from becoming generic
  documentation bureaucracy.

## Business Rules

- A complex workflow decision-gate change must include consistency-matrix
  evidence before PR readiness is claimed.
- A decision-gate change is complex when it has multiple inputs, outcomes,
  next-action branches, status labels, exit states, examples, or mirrored
  workflow surfaces.
- The matrix must identify the gate, every relevant input, every allowed
  outcome, the required next action for each outcome, and every mirror surface
  that must use matching wording.
- The matrix must require a rationale when an expected input, outcome, example,
  or surface is declared not applicable.
- Reviewers must treat missing or contradictory matrix evidence as a review
  finding for complex gate PRs.
- Simple documentation updates that do not alter decision-gate behavior do not
  require a matrix, though they may include a not-applicable rationale.
- Matrix evidence does not replace internal review, automated reviewer loops,
  CI, readiness labels, or human merge policy.

## Operational Visibility

- **PR evidence**: Complex gate PRs show the matrix or a clear pointer to it in
  the readiness evidence expected for the stage.
- **Review signal**: Reviewers can identify missing input, outcome,
  next-action, mirror-surface, or example coverage directly from the matrix.
- **Not-applicable signal**: Non-gate documentation PRs can state why the matrix
  is not applicable without adding extra sections to the changed docs.

## Acceptance Criteria

- [ ] AC1: Given a PR that changes a complex workflow decision gate, the PR
      readiness evidence includes a consistency matrix or equivalent evidence
      before the PR is marked ready for human review.
- [ ] AC2: Given a consistency matrix for a complex gate PR, it lists the gate
      inputs, allowed outcomes, required next actions, and mirror surfaces that
      must stay consistent.
- [ ] AC3: Given a matrix row where an expected input, outcome, example, or
      mirror surface is not applicable, the row includes a short rationale.
- [ ] AC4: Given a reviewer evaluates a complex gate PR with missing or
      contradictory matrix evidence, the reviewer can flag the gap as a finding
      before the PR is considered ready.
- [ ] AC5: Given a documentation PR that does not alter decision-gate behavior,
      the workflow permits a not-applicable matrix rationale instead of
      requiring a full matrix.
- [ ] AC6: Given a complex gate PR includes mirrored workflow surfaces, the
      matrix identifies each affected surface so wording consistency can be
      checked.
- [ ] AC7: Given the matrix requirement is satisfied, the PR still must pass the
      existing internal review, automated reviewer loop, CI, readiness-label,
      and human merge gates.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Require complex gate documentation changes to enumerate inputs, outcomes, next actions, and mirror surfaces | Use Cases 1 and 2, Business Rules | AC1, AC2, AC6 |
| 2. Reduce late review churn from inconsistent gate wording and examples | Overview, Use Case 2, Operational Visibility | AC2, AC4, AC6 |
| 3. Give authors and reviewers a repeatable pre-PR check | Use Cases 1 and 2 | AC1, AC2, AC4 |
| 4. Keep simple non-gate documentation changes outside the full matrix requirement | Use Case 3, Business Rules | AC5 |
| 5. Preserve existing review, CI, readiness, and merge requirements | Business Rules, Operational Visibility | AC7 |

## Out of Scope (MVP)

- Defining the exact matrix storage location or file format.
- Automatically detecting every complex gate change.
- Changing reviewer-loop, CI-loop, readiness-label, tracker-status, or merge
  authority behavior.
- Requiring consistency matrices for ordinary typo fixes or non-gate
  documentation updates.
