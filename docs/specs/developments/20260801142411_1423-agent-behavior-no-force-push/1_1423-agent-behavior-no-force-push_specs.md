# Agent Behavior No-Force-Push Guard - Spec

---

## Overview

Workflow operators need the agent to obey the repository's no-force-push policy
while updating pull-request branches. This change makes unauthorized branch
history rewrites visible and blocked before an agent can use them during normal
workflow execution.

The guard protects review continuity, reviewer findings, and shared branch
history. It is orthogonal to issue #1424, which covers batch mergeability
rechecks after sibling merges; this item focuses only on preventing
unauthorized force-push behavior.

## Brief Objective List

Derived from issue #1423:

1. Prevent agent-driven force-push operations on workflow PR branches unless
   explicit human authorization exists for that exact action.
2. Make the no-force-push policy an execution-time guard rather than a
   memory-dependent convention.
3. Preserve reviewer context and branch history when an already-pushed PR branch
   needs additional updates.
4. Provide actionable stop guidance when the agent would otherwise need to
   rewrite shared history.
5. Add regression coverage for unauthorized force-push attempts and authorized
   exception handling.

## Actors

- **Workflow operator**: approves bounded workflow runs and provides explicit
  authorization only when a destructive branch-history action is truly needed.
- **Work Item Runner**: updates workflow branches and must stop before
  unauthorized history rewrites.
- **Reviewer platform**: relies on stable PR branch history and review context.

## Use Cases

### Use Case 1: Agent updates a pushed PR branch safely

**Actor**: Work Item Runner.
**Preconditions**: A workflow PR branch already exists remotely and needs a
normal follow-up commit after review, CI, or local validation.

**Steps**:

1. The runner prepares the branch update.
2. The runner checks whether the intended operation rewrites remote branch
   history.
3. The runner uses a non-rewriting update path when possible.
4. The runner reports the pushed update through the normal PR readiness flow.

**Postconditions**: The PR branch advances without rewriting shared history.

**Information shown**:

- The branch being updated.
- The safe update outcome.
- Any PR readiness or review status that follows the update.

**Actions available**:

- Continue review and CI supervision.
- Add another normal follow-up commit if further fixes are needed.

**Considerations**:

- Amending local commits is allowed only while it remains local-only and does
  not require rewriting a pushed branch.
- A normal fix commit is preferred once the branch has been pushed.

### Use Case 2: Agent attempts an unauthorized force push

**Actor**: Work Item Runner.
**Preconditions**: A workflow action would require `force` or
`force-with-lease` behavior against a remote PR branch, and no explicit human
authorization for that exact branch and action is recorded.

**Steps**:

1. The runner detects that the pending branch update would rewrite remote
   history.
2. The workflow stops before the push.
3. The runner reports that the repository no-force-push policy blocks the
   action.
4. The runner presents a non-destructive recovery path or asks for explicit
   authorization when no safe path exists.

**Postconditions**: The remote branch is not rewritten without authorization.

**Information shown**:

- The branch that would have been rewritten.
- The missing authorization evidence.
- The safe alternative, such as creating a follow-up commit.

**Actions available**:

- Continue with a non-destructive branch update.
- Provide explicit, named authorization for the exact destructive action.
- Stop and let a human perform the recovery manually.

**Considerations**:

- General approval to continue a workflow run is not authorization to rewrite
  shared branch history.
- Delegated merge authority does not authorize force-pushing.

### Use Case 3: Human authorizes a narrowly scoped exception

**Actor**: Workflow operator.
**Preconditions**: A branch-history rewrite is the selected recovery path and a
safe non-destructive alternative is not appropriate.

**Steps**:

1. The runner asks for explicit authorization naming the branch and destructive
   action.
2. The operator confirms that exact action.
3. The runner records the authorization evidence in the run summary.
4. The runner performs only the authorized branch update and resumes the normal
   readiness flow.

**Postconditions**: Any destructive branch update is traceable to a specific
human authorization.

**Information shown**:

- The branch and action covered by the exception.
- The authorization evidence and scope.
- The follow-up verification that the PR branch remains reviewable.

**Actions available**:

- Authorize the exact action.
- Reject the exception and choose a non-destructive recovery path.

**Considerations**:

- Authorization for one branch or action does not apply to other branches,
  later pushes, admin merges, rebases, or unrelated destructive operations.

## Business Rules

- A workflow runner must not force-push or force-with-lease a remote workflow PR
  branch without explicit human authorization for the exact branch and action.
- General bounded-run confirmation, delegated review authority, delegated merge
  authority, and risk acceptance are not force-push authorization.
- Once a workflow branch has been pushed, follow-up fixes should preserve remote
  history by adding new commits unless a named exception is approved.
- Local-only amend or squash work is allowed only before the branch is pushed
  and before review context can be affected.
- A blocked force-push attempt must stop before mutating the remote branch and
  must present a safe alternative or request explicit authorization.
- Any approved exception must be recorded in the run output with the branch,
  action, and authorization source.
- The guard must apply to workflow branch update paths used by spec, plan,
  implementation, review-fix, and batch supervision flows.

## Operational Visibility

- **Policy check**: The runner reports when a branch update is safe or when the
  no-force-push policy blocks it.
- **Blocked action**: A stop message names the branch, the prohibited action,
  and the missing authorization evidence.
- **Exception record**: A narrowly approved exception records the branch,
  action, and human authorization in the run summary.
- **Review continuity**: The PR readiness flow continues to show reviewer and
  CI state after safe follow-up commits.

## Acceptance Criteria

- [ ] A workflow runner attempting to force-push or force-with-lease a remote
      PR branch without explicit human authorization stops before the push.
- [ ] The stop message identifies the branch, the prohibited action, and that
      general workflow confirmation does not authorize shared-history rewrite.
- [ ] A pushed PR branch that needs review or CI fixes can be updated through a
      non-destructive follow-up commit path.
- [ ] Local-only amend behavior remains allowed before a workflow branch has
      been pushed.
- [ ] A human can authorize one exact destructive branch update by naming the
      branch and action, and that authorization is recorded in the run summary.
- [ ] Authorization for one destructive branch update does not carry over to a
      different branch, later push, merge action, or unrelated recovery.
- [ ] The guard applies consistently across spec, plan, implementation,
      review-fix, and batch-supervision branch update flows.
- [ ] Regression coverage verifies unauthorized force-push blocking, safe
      follow-up commits, local-only amend allowance, and a narrowly authorized
      exception.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Prevent unauthorized force pushes | Use Cases 2-3, Business Rules, AC1-AC2, AC5-AC6 |
| 2. Make policy execution-time | Business Rules, Operational Visibility, AC1, AC7 |
| 3. Preserve reviewer context and history | Use Case 1, Business Rules, AC3-AC4 |
| 4. Provide actionable stop guidance | Use Case 2, Operational Visibility, AC2 |
| 5. Add regression coverage | Acceptance Criteria AC8 |

## Out of Scope (MVP)

- Redesigning every Git command wrapper in the repository. **Deferral Note**:
  the MVP covers workflow branch update paths where agents can affect PR
  history; broader command abstraction can be evaluated separately.
- Automatically repairing branches that were previously rewritten. **Deferral
  Note**: historical recovery requires operator judgment and is not part of the
  prevention guard.
- Changing delegated merge, reviewer, or risk-classification authority.
  **Deferral Note**: those authorities remain distinct and do not authorize
  force-push behavior.
- Batch mergeability rechecks after sibling merges. **Deferral Note**: issue
  #1424 covers that separate workflow correctness problem.

## PR-Visible Deferral Notes

- **Broad Git abstraction**: Deferred because the product requirement is to
  prevent unauthorized agent force-push behavior in workflow PR branch paths.
- **Historical branch repair**: Deferred to operator-led recovery rather than
  automatic shared-history mutation.
- **Delegated authority model changes**: Deferred because the existing
  guardrails model can remain intact while force-push authorization stays
  separately explicit.
- **Sibling mergeability rechecks**: Deferred to #1424, which is an orthogonal
  sibling workflow-safety item from the same retrospective.
