# Reject Unsafe Generated Workflow Branch Names - Spec

---

## Overview

Workflow operators need generated workflow branches to use names that GitHub
can process reliably. A generated name that includes an unsafe character can
leave a pull request without the expected push-triggered checks, delaying
review and obscuring the real cause of the missing automation.

This change makes the workflow produce convention-compliant issue-prefixed
branch names, reject unsafe names before they are pushed, and give an operator
clear recovery guidance when existing work must move to a compliant branch.

## Brief Objective List

Derived from issue #1286:

1. Generated workflow branch names use the bare tracker identifier and never
   embed `#`.
2. A branch-creation or pre-push guard rejects `#` and other characters
   forbidden by the repository workflow convention, with a corrective example.
3. Tests cover accepted issue-prefixed branch names and rejected hash-bearing
   names.
4. Recovery guidance explains how to move work to a convention-compliant
   branch without force-pushing shared history.

## Use Cases

### Use Case 1: Runner starts a tracked workflow item

**Actor**: Work Item Runner.
**Preconditions**: An operator has approved a tracked item and the runner is
preparing its workflow branch.

**Steps**:

1. The runner derives the workflow branch name from the item identifier and
   item summary.
2. The runner uses the bare item identifier in the generated name.
3. The runner validates the generated name against the repository workflow
   convention before a push can occur.
4. If the name is valid, the runner continues through the existing branch and
   pull-request workflow.

**Postconditions**: New generated branches use a GitHub-compatible,
issue-prefixed workflow name.

**Information shown**:

- The generated branch name when the workflow reports its branch choice.
- Existing branch and pull-request progress when validation succeeds.

**Actions available**:

- Continue the normal workflow when the branch name is valid.
- Correct a generated or supplied name before creating or pushing the branch.

**Considerations**:

- The validation must run before a bad branch can be pushed and silently miss
  expected automation.
- The rule applies to generated names and to names supplied to the workflow
  path that performs the same push.

### Use Case 2: Runner encounters an unsafe branch name

**Actor**: Work Item Runner.
**Preconditions**: The workflow is about to create or push a branch name that
does not conform to the repository convention.

**Steps**:

1. The validation identifies the unsafe character or format.
2. The workflow stops before the push.
3. The workflow reports why the name is rejected and shows a compliant
   issue-prefixed example.
4. The operator or runner corrects the name and repeats the normal workflow
   from the approved base.

**Postconditions**: The unsafe branch is not pushed through the workflow path.

**Information shown**:

- The rejected branch name or unsafe format.
- A concise explanation that the repository branch convention was violated.
- A compliant replacement example using the bare tracker identifier.

**Actions available**:

- Use the corrected branch name.
- Escalate when a valid exception is needed rather than bypassing the guard.

**Considerations**:

- The message must distinguish a branch-naming failure from ordinary failing
  CI so operators can recover without waiting for checks that will not start.

### Use Case 3: Operator recovers already-started work

**Actor**: Workflow operator or maintainer.
**Preconditions**: Work already exists on a branch whose name does not meet the
repository convention.

**Steps**:

1. The operator consults the documented recovery guidance.
2. The operator creates a convention-compliant replacement branch from the
   approved work and updates the pull-request workflow through the safe path.
3. The operator verifies that normal push-triggered checks run for the
   replacement branch.

**Postconditions**: The work continues on a compliant branch without rewriting
shared branch history.

**Information shown**:

- The safe recovery sequence and the requirement to preserve shared history.
- The expected confirmation that normal automation has resumed.

**Actions available**:

- Continue review from the compliant branch.
- Escalate if the recovery would require a destructive or shared-history
  operation.

## Business Rules

- Generated workflow branch names must use the bare tracker identifier, not an
  issue-reference form that includes `#`.
- A workflow branch name containing `#` is invalid and must be rejected before
  push.
- The repository workflow branch convention treats `#`, `?`, `^`, `~`, `:`,
  backslash, and spaces as unsafe in generated workflow names; each must be
  rejected by the same validation boundary.
- A rejected branch name must produce an actionable correction that includes a
  compliant issue-prefixed example.
- The validation must fail safely: it must not create a pull request, push the
  invalid branch, or report the item as ready for review.
- Existing valid branch names must remain acceptable so routine workflow runs
  do not gain an unnecessary manual step.
- Recovery guidance must not instruct operators to force-push or rewrite shared
  branch history.

## Operational Visibility

- **Validation result**: The runner reports whether a candidate branch name is
  accepted or rejected before pushing it.
- **Failure guidance**: A rejection reports the convention failure and a
  compliant replacement example.
- **Recovery evidence**: The recovery guidance tells operators to confirm that
  normal push-triggered checks appear on the replacement branch.

## Acceptance Criteria

- [ ] A generated issue-prefixed workflow branch name uses the bare numeric
      tracker identifier and does not include `#`.
- [ ] A workflow branch name containing `#` is rejected before it is pushed.
- [ ] Branch names containing `?`, `^`, `~`, `:`, backslash, or spaces are
      rejected at the same validation boundary as `#`.
- [ ] A rejection explains that the name violates the branch convention and
      provides a compliant issue-prefixed example.
- [ ] A rejected name does not result in a push, pull request, or
      ready-for-review outcome through the guarded workflow path.
- [ ] Valid issue-prefixed workflow branch names continue through the existing
      workflow without a new manual approval.
- [ ] Automated coverage verifies both accepted compliant names and rejected
      hash-bearing names.
- [ ] Documentation provides a non-destructive recovery path for work already
      started on a non-compliant branch and instructs operators to verify that
      push-triggered checks resume.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Use bare tracker identifier; never embed `#` | Use Case 1, Business Rules, AC1, AC6 |
| 2. Reject forbidden characters with corrective example | Use Case 2, Business Rules, Operational Visibility, AC2-AC5 |
| 3. Test valid and hash-bearing names | Acceptance Criteria AC7 |
| 4. Document non-destructive recovery | Use Case 3, Business Rules, Operational Visibility, AC8 |

## Out of Scope (MVP)

- Proving a universal causal relationship between every unsafe character and a
  GitHub webhook failure. **Deferral Note**: this change enforces the repository
  convention and prevents known unsafe names; platform-specific incident
  diagnosis remains operational work.
- Renaming, rebasing, or repairing historical branches and pull requests.
  **Deferral Note**: the feature provides safe guidance for future recovery but
  does not alter shared history automatically.
- Broad changes to CI trigger configuration or temporary manual-dispatch
  workarounds. **Deferral Note**: the MVP prevents unsafe branch names before
  they enter the normal push workflow.

## PR-Visible Deferral Notes

- **Platform-causality claim**: Deferred because the acceptance scope is
  convention enforcement and clear pre-push validation, not a claim that every
  rejected character has the same external effect.
- **Historical branch repair**: Deferred to an operator-led recovery using the
  documented non-destructive path.
- **CI trigger redesign**: Deferred because a compliant workflow branch should
  proceed through the existing CI configuration.
