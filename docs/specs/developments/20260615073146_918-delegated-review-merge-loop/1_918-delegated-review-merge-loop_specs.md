# Delegated Review and Merge Loop for Run Epic - Spec

**Depends on**: 917-run-epic-scope-resolver, 919-pr-risk-classification, 920-autonomous-epic-audit-trail

---

## Overview

Delegated `/run-epic` runs should let an explicitly authorized agent carry an
epic from resolved scope through review, fixes, merge, cleanup, tracker updates,
and rediscovery without stopping at the normal human-review handoff. This
feature defines the invocation-level behavior and safety gates for that
workflow-owner role. The behavior remains bounded by explicit authorization,
the resolved epic or item-list scope, review and CI evidence, risk policy,
audit trail requirements, and repository merge protocols.

## Brief Objective List

1. Reuse existing `/run-work`, `/run-item-work`, reviewer-loop, CI-loop,
   batch-merge, and post-merge cleanup protocols rather than duplicating their
   behavior.
2. Allow an explicitly delegated agent to inspect reviewer-loop and Haystack
   output and make the human-review gate decision for the invocation.
3. Require fix-and-rerun behavior when blocking reviewer findings appear.
4. Require explicit fix-or-accept judgment for advisory findings.
5. Merge only when review disposition, CI, readiness labels, branch state,
   unresolved threads, setup labels, and risk policy allow it.
6. After every merge, verify the PR is merged, perform branch cleanup, update
   tracker state, and rerun discovery so newly unblocked items can advance.
7. Stop only on blocked dependencies, risk or authority limits, unavailable
   services, missing credentials, destructive action requirements, ambiguous
   decisions, or backlog-start policy boundaries.
8. Add delegated-review hygiene rules from the retrospective, including no
   force-push amendments, readiness-label removal before fixes, final readiness
   verification, parent epic closeout checks, and advisory rationale recording.

## Use Cases

### Use Case 1: Start a delegated epic run

**Actor**: Workflow owner agent with explicit delegated authority
**Preconditions**: The operator invokes `/run-epic` for a native epic or
explicit item list and supplies the delegation boundaries for review, merge,
backlog starts, maximum merge risk, and base branch when needed.

**Steps**:

1. The actor resolves the execution scope.
2. The actor confirms which items are eligible, blocked, already merged, in
   review, ambiguous, or out of scope.
3. The actor records the invocation boundaries that determine whether Backlog
   items may start, whether review may be delegated, whether merges may occur,
   what maximum risk is allowed, and which base branch applies.
4. The actor advances each eligible item through the existing item workflow.

**Postconditions**: The run has a bounded execution set and a clear authority
contract before any item is created, reviewed, merged, or cleaned up.

**Information shown**:

- Scope source and item list.
- Base branch source.
- Delegated review and merge authority.
- Backlog-start policy.
- Maximum allowed autonomous merge risk.
- Groups of eligible, blocked, merged, in-review, ambiguous, and out-of-scope
  items.

**Actions available**:

- Advance eligible in-scope items.
- Skip out-of-scope items.
- Stop on ambiguous scope or authority.
- Record the run state in the audit trail.

**Considerations**:

- Explicit item-list runs must not mutate items outside the supplied list.
- Backlog items require explicit authorization before starting.

### Use Case 2: Act as the delegated human review gate

**Actor**: Workflow owner agent with delegated review authority
**Preconditions**: An in-scope PR has reached the normal human-review handoff
or has reviewer results that can be deterministically assessed.

**Steps**:

1. The actor inspects the latest reviewer-loop and Haystack outcome.
2. If blocking findings are present, the actor removes readiness labels, fixes
   the issue when deterministic, reruns validation, reruns reviewer-loop, and
   reassesses.
3. If advisory findings are present, the actor decides whether to fix or accept
   each advisory based on risk, maintainability, security, test coverage, and
   workflow reliability.
4. The actor records accepted advisories with concise rationale.
5. The actor proceeds only when the review disposition is acceptable.

**Postconditions**: The PR either has clean enough review evidence for the next
gate, has deterministic fixes applied and rechecked, or is escalated with a
clear reason.

**Information shown**:

- Latest reviewed head SHA.
- Reviewer-loop result.
- Blocking findings and their disposition.
- Advisory findings and their fix-or-accept decisions.
- Whether unresolved automated-reviewer threads remain.

**Actions available**:

- Remove readiness labels before fixes.
- Push normal follow-up commits.
- Rerun reviewer-loop and CI-loop.
- Accept non-blocking advisories with rationale.
- Escalate when the review result cannot be safely resolved.

**Considerations**:

- Published PR commits must not be amended and force-pushed during delegated
  review or merge work.
- Reviewer blockers are must-fix unless proven false positives.

### Use Case 3: Merge an acceptable PR and continue the epic

**Actor**: Workflow owner agent with delegated merge authority
**Preconditions**: A PR has acceptable review disposition, green CI, required
readiness labels, clean merge state, no unresolved blocking threads, no setup
labels, and risk classification within the invocation's maximum allowed risk.

**Steps**:

1. The actor confirms final readiness evidence.
2. The actor records the PR disposition audit entry.
3. The actor merges the PR through the repository merge protocol.
4. The actor verifies the PR is merged.
5. The actor performs post-merge branch cleanup and tracker updates.
6. The actor reruns scope discovery so newly unblocked items can advance.

**Postconditions**: The PR is merged, cleanup and tracker updates are verified,
and the run has resumed from fresh live scope state.

**Information shown**:

- Final readiness checklist result.
- Risk classification and allowed threshold.
- Merge commit or merged state.
- Branch cleanup result.
- Issue and Project status after cleanup.
- Updated epic ledger.

**Actions available**:

- Merge if every gate passes.
- Fix and rerun if a gate regresses.
- Stop when authority or safety policy blocks merge.
- Close the parent epic when all native sub-issues are terminal and tracker
  state is verified.

**Considerations**:

- A risk gate pass does not replace review, CI, labels, merge state, or thread
  checks.
- Epic closeout must be based on live sub-issue and Project state, not stale
  assumptions.

## Business Rules

- Delegated review and merge behavior must be enabled by explicit invocation
  authority; it is not an always-on repository mode.
- Scope resolution remains read-only and must complete before item mutation.
- Delegated runs may mutate only in-scope items.
- Explicit item-list runs may not mutate out-of-scope items.
- Backlog items may start only when the invocation explicitly allows them.
- Existing workflow protocols remain authoritative for stage execution,
  reviewer-loop, CI-loop, merge, cleanup, and tracker updates.
- When reviewer blockers appear, readiness labels must be removed before
  pushing fixes.
- Fixes to open PRs must use normal follow-up commits; delegated review must
  not amend and force-push published PR commits.
- After every fix push, the actor must rerun validation, reviewer-loop, CI-loop,
  unresolved-thread checks, and readiness verification before restoring
  readiness labels.
- Advisory findings require an explicit fix-or-accept decision.
- Accepted advisories require a concise rationale in the PR disposition audit
  trail.
- Merge is permitted only when final readiness verifies non-draft state,
  acceptable reviewer disposition, required readiness labels, green CI, clean
  merge state, no unresolved blocking threads, no setup labels, and risk within
  authority.
- After every merge, the actor must verify the PR is merged, clean/delete the
  branch as appropriate, update issue tracker state, and rerun discovery.
- After the final child item reaches a terminal state, the actor must verify
  whether the parent epic can be closed using native sub-issues and Project
  statuses.
- The run stops when remaining work is blocked by dependencies, external
  services, missing credentials, ambiguous decisions, destructive action
  requirements, risk limits, or backlog-start boundaries.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `delegated_review_allowed` | Delegated review allowed | The invocation authorizes the agent to make the normal human-review gate decision for in-scope PRs. |
| `delegated_merge_allowed` | Delegated merge allowed | The invocation authorizes the agent to merge acceptable in-scope PRs within the risk policy. |
| `backlog_start_allowed` | Backlog start allowed | The invocation authorizes starting Backlog items that are in scope and dependency-safe. |
| `backlog_start_denied` | Backlog start denied | The invocation does not authorize starting Backlog items, even when they are otherwise eligible. |
| `human_required` | Human required | The run needs a decision, credential, external service, or authority beyond the invocation. |

**Valid transitions**:

- Backlog start denied -> Backlog start allowed only when the operator expands
  invocation authority.
- Delegated review allowed -> Human required when reviewer findings require a
  product or architecture decision.
- Delegated merge allowed -> Human required when risk exceeds the invocation's
  maximum allowed risk.
- Any delegated state -> Human required when destructive action approval,
  missing credentials, or unavailable services block progress.

## Operational Visibility

- **Invocation summary**: Each run reports scope source, base branch, delegation
  authority, backlog-start policy, and maximum merge risk.
- **PR disposition**: Each delegated review or merge decision updates the
  standard PR disposition audit comment.
- **Epic ledger**: Native epic runs update the parent epic ledger after item
  advancement, merge, block, or closeout.
- **Stop reason**: The final run summary identifies whether all items merged,
  specific items remain blocked, or the remaining work cannot start because of
  policy boundaries.

## Acceptance Criteria

- [ ] AC1: Given an explicitly delegated `/run-epic` invocation, the run records
      review authority, merge authority, backlog-start policy, maximum allowed
      risk, and base branch before mutating items.
- [ ] AC2: Given an explicit item-list scope, the run does not mutate branches,
      PRs, tracker state, labels, comments, or changelog entries for items
      outside the list.
- [ ] AC3: Given a Backlog item in scope, the run starts it only when the
      invocation explicitly allows Backlog starts.
- [ ] AC4: Given a PR with blocking reviewer findings, the run removes
      readiness labels, applies deterministic fixes when possible, reruns local
      validation, reviewer-loop, CI-loop, unresolved-thread checks, and final
      readiness verification before restoring readiness labels.
- [ ] AC5: Given advisory reviewer findings, the run records a fix-or-accept
      decision for each advisory, and every accepted advisory has a rationale.
- [ ] AC6: Given a published PR needing fixes, the run uses normal follow-up
      commits and does not require amend plus force-push behavior.
- [ ] AC7: Given a PR candidate for delegated merge, the run verifies non-draft
      state, acceptable review disposition, required readiness labels, green CI,
      clean merge state, no unresolved blocking threads, no setup labels, and
      risk within invocation authority before merge.
- [ ] AC8: Given an acceptable PR, the run records the PR disposition audit
      entry before merge.
- [ ] AC9: Given a successful merge, the run verifies the PR is merged, performs
      branch cleanup, updates issue tracker state, updates the epic ledger when
      applicable, and reruns discovery.
- [ ] AC10: Given the final native epic child reaches a terminal state, the run
      verifies native sub-issue state and Project statuses before closing or
      leaving the parent epic open.
- [ ] AC11: Given blocked dependencies, unavailable services, missing
      credentials, ambiguous decisions, destructive action requirements, risk
      limits, or backlog-start boundaries, the run stops with a clear reason and
      no unsafe mutation.
- [ ] AC12: Tests or workflow fixtures cover delegated review authority,
      advisory decisions, readiness-label removal/restoration, final merge
      gating, post-merge rediscovery, and parent epic closeout behavior.

## Out of Scope (MVP)

- Always-on repository autonomy profiles.
- Merging PRs that exceed the invocation's maximum allowed risk.
- Force-pushing or rewriting published PR history as part of delegated fixes.
- Replacing existing `/run-work`, `/run-item-work`, reviewer-loop, CI-loop,
  batch-merge, or post-merge cleanup protocols.
- Long-term metrics dashboards for delegated runs.
- External audit storage outside GitHub comments and tracker state.

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Reuse existing workflow protocols. | BR6, AC1, AC4, AC7, AC9 |
| Allow delegated human-review gate decisions. | Use Case 2, BR1, AC1, AC4-AC5 |
| Fix blocking reviewer findings and rerun. | Use Case 2, BR7-BR9, AC4 |
| Make advisory fix-or-accept decisions. | Use Case 2, BR10-BR11, AC5 |
| Merge only when all readiness and risk gates allow it. | Use Case 3, BR12, AC7 |
| Verify merge, cleanup, tracker updates, and rerun discovery. | Use Case 3, BR13, AC9 |
| Stop on blocked dependencies, risk, services, credentials, destructive action, ambiguity, or backlog boundaries. | BR15, AC11 |
| Add delegated-review hygiene requirements from the retrospective. | BR7-BR14, AC4-AC10, AC12 |
