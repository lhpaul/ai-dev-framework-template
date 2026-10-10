# Paired release merge sessions — Spec

## Overview

Release operators need to ship a production PR and its backport as one coordinated,
budget-admitted operation. The shared release branch stays available until both
merges are verified, while the production tag and published GitHub Release are
verified before the backport merge. The operation freezes all shipped work items
and their release reconciliation duties before admission and remains recoverable
when execution or remote evidence is interrupted.

The scope is issue [#1941](https://github.com/lhpaul/ai-dev-framework-template/issues/1941).
The v0.48.0 exception is historical evidence, not an ongoing authorization.

## Use Cases

### Use Case 1: Ship a paired release

**Actor**: A release operator or agent with existing review and merge authority.
**Preconditions**: A finalized release changelog, a production PR to main and a
backport PR from the same release branch to the approved integration base; both
PRs have green current-head CI and satisfy all existing readiness gates.

**Steps**:

1. Select the ordered pair and freeze its release version, repository, reviewed
   heads, target branches, finalized shipped-item scope and all follow-up duties.
2. Observe quota and admit the whole operation only when its remaining duties
   plus the configured reserve fit the observed GraphQL balance.
3. Merge the production PR using a regular merge commit and verify the merge.
4. Verify the version tag resolves to the production merge commit and the
   corresponding GitHub Release is published and not draft.
5. Revalidate the backport's current-head readiness, merge it using a regular
   merge commit, and independently verify the backport merge.
6. Perform authorized shared cleanup, release stamping, tracker transitions,
   release-marker finalization and required audit updates through the same session.
7. Read back each duty independently before reporting completion.

**Postconditions**: Both merges and every owned duty are verified; the operation
reports Completed. Existing deletion restrictions remain binding.

**Information shown**: The selected pair, release identity, shipped-item scope,
quota/reset, projected cost, reserve, verified merge states and pending duties.
**Actions available**: Proceed after admission, inspect the journal, or explicitly
recover a stopped operation.
**Considerations**: An unaffordable pair admits neither fresh merge. Unknown or
inconsistent release identity, scope or provider evidence stops execution.

### Use Case 2: Recover an interrupted release

**Actor**: The operator resuming the owning release session.
**Preconditions**: A durable journal exists with completed, uncertain or pending
work, including an interruption after production merge, during publication
verification, after backport merge or during cleanup.

**Steps**:

1. Inspect the local journal and its recovery command, even if APIs are unavailable.
2. Explicitly resume, reconcile live PR, tag, Release, branch, tracker and audit
   evidence, and preserve earlier verified facts when evidence is unavailable.
3. Observe quota and re-admit only known outstanding work.
4. Continue from the next allowed duty without submitting an already submitted
   merge or replaying an uncertain mutation.

**Postconditions**: Verified work stays discharged; unknown outcomes stay
uncertain until resolved. The backport cannot precede production publication
verification, and cleanup cannot precede both verified merges.

**Information shown**: Last verified facts, unresolved outcomes, pending duties,
quota/reset when readable and the exact recovery command.
**Actions available**: Inspect, wait for evidence/quota or explicitly resume.
**Considerations**: Queue or auto-merge submission is Waiting, not a completed
merge. An unavailable or mismatched tag/Release never permits the backport.

### Use Case 3: Continue ordinary implementation merges

**Actor**: An operator merging ordinary reviewed implementation PRs.
**Preconditions**: A selected sequence of implementation PRs.
**Steps**:

1. Admit the entire selected sequence under its existing budget rules.
2. Merge the first PR and verify all its required follow-up.
3. Attempt the next merge only after that follow-up independently completes.

**Postconditions**: The paired release ordering exception is unavailable to
ordinary implementation PRs or unrelated releases.
**Information shown**: The incomplete preceding duty when progression is refused.
**Actions available**: Reconcile the preceding duty through explicit recovery.
**Considerations**: Simply sharing a branch name or requesting a cleanup skip
cannot establish a coordinated release pair.

## Business Rules

- BR1: Existing authority, risk, current-head CI, review, ownership and human
  checkpoint gates remain in force. Budget admission creates no additional
  merge, administration or branch-deletion authority.
- BR2: A coordinated pair must bind one release in one repository, its shared
  reviewed release branch/head, production target and distinct approved backport
  target. Missing, malformed, mismatched or duplicate pairing evidence is refused.
- BR3: Production merge verification and tag/published-Release verification
  precede the backport merge. Both merges use regular merge commits.
- BR4: Shared branch cleanup and shipped-item release reconciliation occur only
  after both merges are independently verified. Pair-specific deferred duties
  do not remove the sequential follow-up gate for other selected PRs.
- BR5: The complete finalized changelog scope and all actual release duties are
  frozen before admission. This includes any applicable omitted-shipped-item
  reconciliation required by the existing release flow; cleanup cannot silently
  add work outside the frozen projection. Changed scope requires a new verified
  admission before affected mutation, without losing earlier historical facts.
- BR6: Projection accounts for each owning tracker transition, release stamp,
  release-marker finalization, shared cleanup and audit duty, with conservative
  headroom. Repeated and shared duties must have explicit ownership and cannot
  vanish from cost estimation or be discharged twice.
- BR7: Completed requires independent evidence for every owned duty. A helper's
  zero exit, best-effort marker or deferred provider action is insufficient.
- BR8: Recovery resolves uncertain outcomes and surviving executors before any
  mutation replay. Remote unavailability retains durable local facts and stops
  progression; it never authorizes a fallback bypass.
- BR9: Existing single-PR release routing, repository ownership and provider
  routing remain applicable. This change does not generalize paired ordering to
  arbitrary batches or reopen the historical v0.48.0 exception.

## Statuses / Enum Values

No new operator-facing session statuses are introduced. Existing outcomes retain
these meanings for the paired release:

| Outcome | Required next action |
| --- | --- |
| Deferred | Report quota/reset and pending work; perform no operation-owned remote writes. |
| Admitted | Execute the next authorized ordered duty; this is intermediate. |
| Waiting | Retain verified submission and pending duties; stop further merges and explicitly recover after fresh evidence. |
| Interrupted | Preserve completed/uncertain/pending work locally; explicitly reconcile before continuing. |
| Completed | Report independently verified merges, cleanup, tracker/stamping and audit completion. |

Recovery from Deferred, Waiting or Interrupted may return to Admitted after
live reconciliation and budget admission; otherwise it remains stopped with
preserved facts. Admitted may enter any stopped outcome or Completed according
to observed evidence. Historical Completed sessions remain inspectable.

## Operational Visibility

The durable operation report identifies both PRs, the frozen release/item scope,
verified production and backport merge commits, tag/Release evidence, remaining
cleanup, release stamping, tracker and audit duties. It retains individual
quota observations and reports aggregate spend only when observations are
comparable. Terminal reports include the recovery command and existing
Ground-Truth Completion Verification.

## Acceptance Criteria

- [ ] AC1: A valid pair completes production merge → verified tag/published
  Release → backport merge → authorized shared cleanup under one admitted
  session, without an early branch deletion or budget bypass.
- [ ] AC2: Admission freezes all finalized shipped issues and all owning
  tracker/stamping/finalization/audit duties; increasing these duties increases
  projected work. An unaffordable selected set submits no fresh merge or audit.
- [ ] AC3: Missing or mismatched pair identity, release version, changelog scope,
  heads or target branches refuses affected mutation; changed scope is never
  silently accepted by cleanup.
- [ ] AC4: The backport is refused until the production merge and matching tag
  and published non-draft Release are independently verified. Shared cleanup is
  refused until both regular merges are independently verified.
- [ ] AC5: Recovery tests interrupt after production merge, during tag/Release
  verification, after backport merge and during cleanup. Each resumes only
  verified outstanding duties and never repeats a completed/submitted merge or
  blindly replays an uncertain mutation.
- [ ] AC6: With remote evidence unavailable, the local report preserves known
  merges and uncertain/pending duties and prints recovery guidance. Waiting
  prevents subsequent selected merges and keeps merge-dependent follow-up pending.
- [ ] AC7: Release cleanup accepts the owning durable session and independently
  verifies each stamp, owning tracker transition, marker finalization and audit
  before the operation can report Completed; partial failure stays recoverable.
- [ ] AC8: A regression test proves an ordinary implementation sequence still
  refuses its second merge while any required first-PR follow-up is incomplete;
  unrelated or malformed release pairs cannot use the release-specific ordering.
- [ ] AC9: Existing single-PR releases and supported ownership/provider routes
  retain their current authority and readiness requirements. No new deletion
  permission or repository-specific assumption is imposed on template consumers.

## Brief Objective List and Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Coordinated two-PR release with shared cleanup after both merges | AC1, AC4; BR2–BR4 |
| Current-head CI, production-first regular merges and tag/Release verification | AC1, AC4, AC9; BR1, BR3 |
| Finalized changelog scope and every release-stamp/tracker duty before admission | AC2, AC3, AC7; BR5–BR7 |
| Same session in release cleanup with independently verified completion | AC1, AC7; BR7 |
| Recovery at each release interruption boundary without duplicate mutation replay | AC5, AC6; BR8 |
| Preserve ordinary sequential implementation cleanup | AC8; BR4 |

No brief objective is deferred.

## Workflow Decision-Gate Consistency Matrix

Rows are evaluated in order; refusal or a stopped session prevents later mutation.
Each gate uses the frozen identity and fresh live evidence for its own boundary.

| Inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Unknown identity/scope, invalid pairing or unreadable admission evidence | Refused / Deferred | Resolve evidence before operation-owned mutation | Protocols 05 and 94; budget/cleanup guidance | Different heads in purported pair |
| Entire outstanding set plus reserve exceeds quota | Deferred | Report reset and no fresh operation-owned writes | Protocol 94; budget guidance | Several shipped tracker duties exceed balance |
| Session Waiting or Interrupted, or any uncertain/in-flight duty | Progression stopped | Explicitly reconcile live evidence; never repeat submission | Protocols 05 and 94; recovery guidance | Production merge outcome unknown |
| Required authority/readiness gates for the next action fail or are unknown | Action refused | Resolve the existing gate before mutation | Protocols 05 and 94; gate guidance | Backport current-head CI red |
| Valid Admitted pair; production known unmerged and not submitted; gates pass | Production merge allowed | Verify regular merge independently | Protocol 05; budget execution guidance | First merge in the pair |
| Production merged; publication missing, mismatched or unknown | Backport refused; recovery pending | Verify matching tag and published Release | Protocol 05; budget recovery guidance | Interrupted while tag workflow runs |
| Admitted pair; production/publication verified; backport known unmerged and not submitted; gates pass | Backport merge allowed | Verify regular merge; retain shared branch | Protocols 05 and 94 | First PR cleanup remains deferred within pair |
| Either merge unverified | Shared cleanup refused | Reconcile missing merge evidence | Protocol 05; release cleanup guidance | Backport queue submission is Waiting |
| Admitted pair; both merges verified; known pending follow-up remains | Follow-up allowed only under existing authority | Execute/verify remaining frozen duties | Protocols 05 and 94; release cleanup guidance | Tracker duty pending after verified branch cleanup |
| All owned duties independently verified | Completed | Report recovery command and ground truth | Protocols 05 and 94; helper guidance | Both stamps and tracker read-back complete |
| Ordinary implementation sequence with prior follow-up incomplete | Next merge refused | Finish preceding follow-up | Protocol 94; ordinary cleanup guidance | First implementation tracker duty pending |

## Out of Scope (MVP)

- Other issues, unrelated workflow fixes, release creation or deployment changes.
- New merge methods, risk limits, authority policy or exceptional admin bypasses.
- Automatic rollback of remote merges, blanket tracker transitions or journal deletion.
- General grouping of arbitrary implementation PRs; the existing sequential gate remains.
- A live production release as part of developing #1941; release scenarios are
  validated in isolated fixtures and through the existing review/CI workflow.
