# Pushed Branch Update Discipline - Spec

---

## Overview

Workflow contributors need clear, durable guidance for updating a branch after
it has been published for review. The guidance prevents history-rewriting
recovery work, keeps review evidence easy to follow, and preserves the
repository's no-force-push safety rule.

## Brief Objective List

1. Clarify the expected workflow when a branch has already been pushed.
2. Prevent repeat use of amend-and-reconcile recovery that produces noisy PR
   history.
3. Preserve the existing no-force-push policy.

## Use Cases

### Use Case 1: Contributor addresses feedback on a published branch

**Actor**: Workflow contributor.
**Preconditions**: The contributor has pushed a branch and opened or updated a
pull request.

**Steps**:

1. The contributor identifies a change needed after publication.
2. The contributor consults the repository guidance.
3. The contributor records the correction in a follow-up commit.
4. The pull request receives the new commit without rewriting published
   history.

**Postconditions**: The pull request keeps a coherent chronological record of
the published work and its follow-up corrections.

**Information shown**:

- The rule that published branch history must remain intact.
- The approved follow-up-commit approach.
- The prohibition on force-pushing published branch changes.

**Actions available**:

- Add a focused follow-up commit for a correction.
- Continue the normal review and CI workflow.

**Considerations**:

- A correction may be documentation-only, test-only, or code-related; the same
  published-history rule applies.

### Use Case 2: Contributor notices an amend was attempted after publication

**Actor**: Workflow contributor.
**Preconditions**: A contributor discovers that an already-published branch
would diverge if its amended local history were pushed.

**Steps**:

1. The contributor stops before force-pushing or otherwise rewriting the
   remote branch.
2. The contributor restores a coherent published-history path using normal
   follow-up commits.
3. The contributor records any necessary recovery as part of the pull-request
   history.

**Postconditions**: The published branch remains reviewable without an unsafe
force-push.

**Information shown**:

- The no-force-push constraint still applies during recovery.
- Recovery work must be understandable from the pull-request history.

**Actions available**:

- Seek human help if a safe recovery path is unclear.

## Business Rules

- Once a branch is published for review, contributors must preserve its shared
  history.
- Corrections to a published branch must use follow-up commits rather than
  rewriting the published commits.
- The no-force-push policy remains in effect for normal development work and
  for recovery from an attempted amend.
- Guidance must distinguish unpublished local cleanup from updates to a branch
  already visible to reviewers.
- The guidance must not change existing review, CI, merge, or branch-protection
  authority.

## Operational Visibility

- **Pull-request history**: Reviewers can see each post-publication correction
  as a normal follow-up commit.
- **Guidance**: Contributors can find the rule at the point where repository
  workflow and version-control practices are documented.
- **Escalation**: A contributor with no safe recovery path can pause and request
  human direction before changing remote history.

## Acceptance Criteria

- [ ] AC1: A contributor can find clear guidance that a branch already pushed
      for review must be updated with follow-up commits.
- [ ] AC2: The guidance explicitly preserves the repository's no-force-push
      rule for published branches and recovery situations.
- [ ] AC3: The guidance distinguishes unpublished local amendments from
      updates to a branch that reviewers can already see.
- [ ] AC4: A reviewer can verify from a post-publication correction that the
      pull-request history remains coherent without a forced update.
- [ ] AC5: Existing review, CI, merge, and branch-protection behavior remains
      unchanged.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Clarify updates after a branch is pushed | Use Case 1, Business Rules | AC1, AC3 |
| Prevent amend-and-reconcile recovery noise | Use Cases 1 and 2, Operational Visibility | AC1, AC4 |
| Preserve the no-force-push policy | Business Rules, Use Case 2 | AC2, AC5 |

## Out of Scope (MVP)

- Adding a hook that automatically blocks amendments or force-push attempts.
- Rewriting or repairing history for existing merged pull requests.
- Changing repository branch protections or merge permissions.
