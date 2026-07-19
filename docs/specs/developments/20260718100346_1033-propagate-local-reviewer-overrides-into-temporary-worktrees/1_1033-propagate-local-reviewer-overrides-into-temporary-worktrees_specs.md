# Local Reviewer Override Continuity - Spec

---

## Overview

Workflow operators may use local reviewer settings that are intentionally not
committed to the shared repository. When an automated workflow creates a
temporary worktree for pull-request processing, it must apply the same local
reviewer policy as the initiating checkout so reviews are performed by the
operator-selected reviewers rather than silently falling back to a shared
default.

## Brief Objective List

1. Preserve the initiating operator's local reviewer override when review work
   moves into a temporary worktree.
2. Prevent temporary worktrees from selecting a different reviewer platform
   solely because a local setting is absent there.
3. Keep local-only settings uncommitted and retain existing reviewer gates.

## Use Cases

### Use Case 1: Operator starts PR review with a local reviewer override

**Actor**: Workflow operator.
**Preconditions**: The operator has a valid local reviewer override in the
initiating checkout and starts a pull-request workflow that uses a temporary
worktree.

**Steps**:

1. The workflow records the effective reviewer policy selected by the
   initiating checkout.
2. The workflow creates or enters its temporary worktree.
3. The review process uses the same effective reviewer policy.
4. The workflow records that a local override supplied the effective policy.

**Postconditions**: The pull request is reviewed with the operator-selected
policy regardless of the temporary execution location.

**Information shown**:

- The effective draft and ready-phase reviewer policy.
- Whether the policy came from a local override or shared configuration.
- A visible warning when the local policy cannot be used.

**Actions available**:

- Continue the review under the effective local policy.
- Stop and request operator action when the required local policy is
  unavailable.

**Considerations**:

- Local settings must remain private to the operator and must not be added to
  commits or pull requests.

### Use Case 2: No local override is configured

**Actor**: Workflow operator.
**Preconditions**: The initiating checkout has no local reviewer override.

**Steps**:

1. The workflow resolves the shared reviewer policy.
2. The temporary worktree uses that same shared policy.
3. The workflow continues through the existing review gates.

**Postconditions**: The behavior matches the current shared-configuration path
without introducing a new local dependency.

**Information shown**:

- The shared reviewer policy that applies to the pull request.

## Business Rules

- Temporary-worktree review execution must use the reviewer policy effective
  in the initiating checkout.
- A local reviewer override contributes only the reviewer-policy choices it
  defines; the temporary worktree must preserve the fully resolved effective
  policy, including applicable shared choices.
- Local reviewer settings must not be committed, pushed, copied into pull
  request artifacts, or exposed in review output beyond their policy source.
- If the effective local reviewer policy cannot be safely applied, the workflow
  must stop or warn according to the existing reviewer-availability policy; it
  must not silently substitute a different reviewer platform.
- Without a local override, the workflow must preserve the shared-policy
  behavior.
- Existing blocking-review, CI, readiness-label, tracker-status, and merge
  authority remain unchanged.

## Operational Visibility

- **Review summary**: The review record identifies the effective reviewer
  policy and whether it was sourced locally or from shared configuration.
- **Failure signal**: An unavailable effective local policy is visible as an
  actionable review-workflow condition, not a hidden fallback.
- **Privacy**: The workflow does not place the local configuration contents in
  repository files, commits, or pull-request comments.

## Workflow Decision-Gate Matrix

| Initiating local policy | Temporary worktree | Required outcome | Next action | Mirror surfaces | Visibility |
| --- | --- | --- | --- | --- | --- |
| Present and valid | Able to use the effective policy | Use the fully resolved effective policy | Continue normal review | Initiating checkout, temporary review location, and PR review record | Record local policy source |
| Present and valid | Cannot use the effective policy | Do not substitute a different reviewer policy silently | Apply existing availability stop or warning policy | Initiating checkout, temporary review location, and PR review record | Report the unavailable effective policy |
| Absent | Shared policy available | Use the shared policy | Continue normal review | Initiating checkout, temporary review location, and PR review record | Record shared policy source |
| Absent | Shared policy unavailable | Apply the existing availability policy | Stop or warn as configured | Initiating checkout, temporary review location, and PR review record | Report the unavailable shared policy |

## Acceptance Criteria

- [ ] AC1: Given a valid local reviewer override in the initiating checkout,
      review work in a temporary worktree uses the same effective reviewer
      policy.
- [ ] AC2: Given the local policy cannot be applied in the temporary worktree,
      the workflow does not silently replace it with a different shared
      reviewer platform.
- [ ] AC3: Given no local reviewer override, review work continues with the
      existing shared-policy behavior.
- [ ] AC4: A review record identifies whether the effective reviewer policy
      came from a local override or shared configuration without disclosing the
      local configuration contents.
- [ ] AC5: Local reviewer configuration is not added to commits or pull-request
      artifacts.
- [ ] AC6: Existing blocking-review, CI, readiness-label, tracker-status, and
      merge-authority behavior remains unchanged.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Preserve local override in temporary worktrees | Use Case 1, Business Rules | AC1, AC4 |
| Prevent an unintended reviewer fallback | Use Case 1, Decision-Gate Matrix | AC2 |
| Keep settings local and retain reviewer gates | Business Rules, Operational Visibility | AC5, AC6 |

## Out of Scope (MVP)

- Changing the shared default reviewer policy.
- Committing or sharing operator-local reviewer configuration.
- Changing reviewer availability, CI, readiness, tracker, or merge policies.
- Adding new reviewer platforms.
