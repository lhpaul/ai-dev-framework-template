# Validate Existing Workflow Branches Before Reuse - Spec

---

## Overview

When `/run-item` finds an existing workflow branch for the selected item, it
must verify that the branch is compatible with the run's approved integration
base before reusing it. A matching item number alone is not enough: a branch
left by an earlier attempt may track a stale remote or descend from a different
base and can contaminate the resumed workflow.

This feature makes branch reuse a safe, visible decision. Compatible branches
continue through the normal resume path; incompatible or unverifiable branches
stop before mutation and tell the operator exactly what must be inspected or
removed before retrying.

## Brief Objective List

Derived from issue #1179:

1. Validate a pre-existing item branch against the current approved integration
   base before `/run-item` reuses it.
2. Prevent a branch with the correct item number but the wrong or stale base
   from being treated as resumable work.
3. Distinguish integration-base compatibility from local-versus-remote tracking
   divergence so stale tracking refs do not produce misleading reuse decisions.
4. Preserve normal resume behavior for an existing branch that is compatible
   with the approved base.
5. Stop safely, without deleting or rewriting branch history automatically,
   when compatibility cannot be established.
6. Give the operator clear evidence and a concrete recovery action when branch
   reuse is blocked.
7. Cover local, remote-only, and worktree-owned branch discovery paths so the
   validation cannot be bypassed by where the branch was found.

## Use Cases

### Use Case 1: Resume a compatible existing item branch

**Actor**: Workflow operator running `/run-item`.
**Preconditions**: The selected item already has a workflow branch, and the run
has resolved an approved integration base.

**Steps**:

1. The runner finds the existing branch associated with the selected item.
2. Before reusing the branch or mutating workflow state, the runner checks the
   branch against the approved integration base.
3. The check confirms that the current approved base is part of the branch's
   accepted history.
4. The runner reports that branch reuse is valid and resumes the existing item
   work.

**Postconditions**: Work continues on the existing branch without creating a
duplicate branch or silently changing the approved base.

**Information shown**:

- The selected item and discovered branch.
- The approved integration base used for validation.
- A successful compatibility result.
- Any local-versus-remote tracking divergence as separate diagnostic
  information.

**Actions available**:

- Continue the canonical resume path.
- Inspect non-blocking tracking-ref diagnostics when they are relevant.

**Considerations**:

- A stale remote-tracking ref does not by itself prove that the local branch has
  the wrong integration base.
- Branch reuse remains subject to the existing duplicate-artifact, worktree,
  and approved-base guards.

### Use Case 2: Stop before reusing an incompatible branch

**Actor**: Workflow operator running `/run-item`.
**Preconditions**: A branch matches the selected item identifier, but the
approved integration base is not established as part of its accepted history.

**Steps**:

1. The runner finds the item-matching branch.
2. The compatibility check compares it with the approved integration base.
3. The check reports that the branch is based on a different or stale line of
   history.
4. The runner stops before branch reuse, file changes, commits, pushes, PR
   mutations, or tracker mutations.
5. The runner tells the operator how to inspect the mismatch and retry after
   choosing whether to remove the stale branch or explicitly authorize a
   different recovery path.

**Postconditions**: The stale branch is not reused and no workflow artifact is
mutated under an unverified base.

**Information shown**:

- The selected item and incompatible branch.
- The expected integration base.
- The observed compatibility failure.
- Relevant branch and tracking-reference evidence that explains the mismatch.
- A concrete human recovery action.

**Actions available**:

- Inspect and remove the stale branch, then retry from the approved base.
- Preserve the branch for investigation and stop the workflow.
- Explicitly authorize a different recovery path through the existing human
  approval mechanism.

**Considerations**:

- The runner must not automatically delete the branch or rewrite its history.
- A branch may contain valuable work even when it is incompatible with the
  current run, so destructive recovery always remains a human decision.

### Use Case 3: Stop when branch compatibility cannot be verified

**Actor**: Workflow operator running `/run-item`.
**Preconditions**: An existing branch is found, but the approved base, branch
history, remote state, or repository query needed for the compatibility check
is unavailable or ambiguous.

**Steps**:

1. The runner attempts the compatibility check.
2. Required evidence cannot be read or produces an ambiguous result.
3. The runner distinguishes this verification failure from a confirmed
   incompatible result.
4. The runner stops before mutation and reports the missing or ambiguous
   evidence.

**Postconditions**: The workflow does not guess that an unverified branch is
safe to reuse.

**Information shown**:

- The evidence that could not be resolved.
- The affected item, branch, and approved base.
- Whether the failure came from missing base context, repository state, or an
  unavailable branch-history query.
- The action required to retry the verification.

**Actions available**:

- Restore the missing base or repository access and retry.
- Correct ambiguous branch ownership or worktree state.
- Ask for a human decision when the evidence cannot be made deterministic.

**Considerations**:

- Verification infrastructure failures must not be reported as compatible
  branches.
- The result must remain distinct from "no existing branch found," which follows
  the normal fresh-branch path.

## Business Rules

- An existing workflow branch must not be reused solely because its name
  contains the selected item identifier.
- The run's already-approved integration base is the source of truth for the
  compatibility decision; the runner must not silently substitute the
  repository default branch or a branch's remote-tracking ref.
- Compatibility requires positive evidence that the current approved
  integration base is in the existing branch's accepted ancestry.
- Local-versus-remote tracking divergence and integration-base compatibility
  are separate facts and must be reported separately.
- A compatible existing branch follows the normal resume path and does not
  create a duplicate workflow branch.
- An incompatible or unverifiable branch blocks reuse before any item artifact,
  PR, label, or tracker mutation.
- The blocking result must name the affected item, existing branch, approved
  base, observed reason, and concrete human recovery action.
- The runner must not automatically delete, reset, rebase, force-push, or
  otherwise rewrite an incompatible branch.
- The same compatibility requirement applies whether the existing branch is
  local, remote-only, or checked out in a registered worktree.
- Existing duplicate-artifact and worktree-isolation safeguards remain in
  force; this validation complements rather than replaces them.

## Operational Visibility

- **Successful reuse**: The run output identifies the branch, approved base,
  and successful compatibility result before resuming.
- **Blocked reuse**: The output distinguishes a confirmed incompatible base from
  an unavailable or ambiguous verification.
- **Divergence diagnostics**: Local-versus-remote ahead/behind information is
  presented as supporting evidence rather than as the compatibility decision.
- **Recovery guidance**: Every blocked result includes a concrete next action,
  such as inspecting and removing a stale branch or restoring missing base
  context before retrying.
- **Final summary**: The Work Item Runner summary records whether the item used a
  fresh branch, reused a compatible branch, or stopped because reuse was unsafe.

## Decision-Gate Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| No item-matching branch exists; approved base is resolved | Fresh branch | Continue the canonical new-branch path from the approved base | `/run-item` orchestration protocol, item-orchestrator skill, branch-discovery helper/tests | Item `1526` has no prior branch, so the runner creates the expected workflow branch from the approved integration base |
| Item-matching branch exists; approved base is positively verified in its accepted history | Compatible reuse | Report compatibility and resume the existing branch without creating a duplicate | `/run-item` orchestration protocol, item-orchestrator skill, branch-resume helper/tests | The existing item branch contains the current approved integration base and can be resumed |
| Item-matching branch exists; approved base is not in its accepted history | Incompatible branch | Stop before mutation and require human inspection/removal or explicit recovery authorization | `/run-item` orchestration protocol, item-orchestrator skill, branch-resume helper/tests | A branch has the right item number but descends from an older or different integration line |
| Item-matching branch exists; compatibility evidence is missing, unavailable, or ambiguous | Verification blocked | Stop before mutation, identify missing evidence, and require a successful retry or human decision | `/run-item` orchestration protocol, item-orchestrator skill, branch-resume helper/tests | The approved base cannot be resolved or the branch-history query fails |
| Item branch is compatible but its local tip is far ahead of a stale tracking ref | Compatible reuse with diagnostic | Resume based on integration-base evidence and report tracking divergence separately | Branch-resume helper/tests and operator-facing output | The local branch appears 98 commits ahead of its remote-tracking ref but has no item-specific divergence from the integration base |

## Acceptance Criteria

- [ ] When `/run-item` discovers an existing branch for the selected item, it
      validates that branch against the run's approved integration base before
      reusing it.
- [ ] A matching item identifier in the branch name is insufficient by itself
      to authorize branch reuse.
- [ ] A branch is treated as compatible only when the runner obtains positive
      ancestry evidence for the current approved integration base.
- [ ] A compatible local, remote-only, or worktree-owned branch follows the
      normal resume path without creating a duplicate branch.
- [ ] A branch with an incompatible base stops the item before file, branch, PR,
      label, or tracker mutation.
- [ ] A failed or ambiguous compatibility query also stops before mutation and
      is reported separately from a confirmed incompatible base.
- [ ] The blocked output names the item, existing branch, approved base,
      observed reason, and concrete human recovery action.
- [ ] The workflow does not automatically delete, reset, rebase, force-push, or
      otherwise rewrite an incompatible existing branch.
- [ ] Local-versus-remote ahead/behind divergence is not used as a substitute
      for approved-base compatibility and is shown separately when relevant.
- [ ] Existing duplicate-artifact and worktree-isolation checks continue to run
      alongside the branch compatibility gate.
- [ ] Automated coverage exercises: no existing branch, compatible local
      branch, compatible remote-only branch, compatible worktree branch,
      incompatible base, stale remote-tracking ref, missing approved base, and
      failed or ambiguous history verification.
- [ ] Operator-facing guidance and supported `/run-item` surfaces describe the
      same outcomes and required next actions shown in the consistency matrix.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Validate before reuse | AC1, AC3; Use Cases 1-3; Business Rules |
| 2. Prevent wrong/stale-base reuse | AC2, AC5, AC8; Use Case 2 |
| 3. Separate base compatibility from tracking divergence | AC9; Use Case 1; Operational Visibility |
| 4. Preserve compatible resume behavior | AC4; Use Case 1 |
| 5. Stop safely without automatic destructive recovery | AC5, AC6, AC8; Use Cases 2 and 3 |
| 6. Provide evidence and recovery guidance | AC7; Operational Visibility |
| 7. Cover all branch discovery locations | AC4, AC11; Business Rules |

## Out of Scope (MVP)

- Automatically deleting, rebasing, resetting, force-pushing, or otherwise
  rewriting a stale or incompatible branch.
- Recovering or migrating work from an incompatible branch onto a new branch.
- Changing workflow branch naming conventions or item-to-branch matching rules.
- Replacing the existing duplicate-artifact or worktree-isolation guards.
- Treating a stale remote-tracking ref alone as proof that a local branch is
  incompatible.
- Auditing or cleaning all historical stale branches outside the selected
  `/run-item` invocation.
