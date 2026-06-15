# Autonomous Epic Audit Trail - Spec

**Depends on**: 917-run-epic-scope-resolver

---

## Overview

Delegated `/run-epic` runs need a compact, durable audit trail for review and
merge decisions. When an agent is authorized to act as the workflow owner, the
repository should record why each PR was merged, blocked, fixed, or escalated,
and should summarize epic progress in one place. This feature adds standard PR
disposition comments and, for native epic runs, a rolling epic ledger comment.

## Brief Objective List

1. Record a standard PR disposition comment for each PR that reaches a delegated
   review or merge decision.
2. Record enough evidence to reconstruct why a PR was merged, blocked, fixed,
   accepted with advisories, or escalated to a human.
3. Update an epic ledger comment for epic-scoped runs so the workflow owner can
   see every child item's state without scanning each PR.
4. Use stable comment markers so reruns update existing audit comments instead
   of creating duplicates.
5. Avoid secrets, credentials, and local-only paths while preserving normal
   workflow evidence.
6. Work for explicit item-list runs even when no parent epic ledger exists.

## Use Cases

### Use Case 1: Record a PR disposition decision

**Actor**: Workflow owner agent running an explicitly delegated `/run-epic`
session
**Preconditions**: An in-scope item has a PR that reached the delegated review
gate.

**Steps**:

1. The actor gathers the current PR readiness evidence.
2. The actor records the scope source, item, PR number, head SHA, reviewer-loop
   result, blocking count, advisory count, risk classification, merge authority,
   and final decision.
3. The actor records advisory decisions as fixed, accepted, deferred, or
   false/stale with brief rationale when applicable.
4. The actor creates or updates one standard PR disposition comment.

**Postconditions**: The PR contains a current disposition comment that explains
what decision was made and why.

**Information shown**:

- Scope source: epic, item list, label, or integration branch.
- Item and PR identifiers.
- Head SHA reviewed.
- Reviewer-loop and Haystack result.
- Blocking and advisory counts.
- Advisory disposition and rationale.
- Risk classification and reasons.
- Merge authority from invocation flags.
- Final decision: merge approved, fixes required, human required, or blocked.
- Verification evidence used for the final decision.

**Actions available**:

- Update the same comment on rerun.
- Record a fix decision after addressing a blocking finding.
- Record an accepted advisory with rationale.
- Record an escalation when human input is required.

**Considerations**:

- The comment is an audit artifact, not an approval bypass.
- The comment must not include secrets, credentials, local-only paths, or
  irrelevant environment details.

### Use Case 2: Maintain an epic ledger

**Actor**: Workflow owner agent running `/run-epic --epic <issue-number>`
**Preconditions**: The resolver produced a native epic execution set.

**Steps**:

1. The actor updates one rolling comment on the parent epic.
2. The ledger lists each child item with issue number, title, PR number, tracker
   status, risk level, review result, decision, merge/cleanup verification, and
   notes.
3. The actor updates the same comment after each item advances or merges.

**Postconditions**: The epic issue contains a current ledger showing the state
of every in-scope child item.

**Information shown**:

- Issue number and title.
- PR number or absence of PR.
- Current tracker status.
- Risk level.
- Reviewer result.
- Decision.
- Merge and cleanup verification.
- Follow-up or retrospective notes.

**Actions available**:

- Update child item rows on rerun.
- Add merge/cleanup evidence after successful merge.
- Add blocker notes when work stops.
- Add epic closeout evidence when every child reaches a terminal state.

**Considerations**:

- Epic ledger updates are optional for explicit item-list runs with no parent
  epic.
- PR disposition comments remain required for explicit item-list runs.

### Use Case 3: Capture accepted advisory rationale

**Actor**: Workflow owner agent reviewing automated advisory findings
**Preconditions**: A reviewer reports non-blocking advisories and the agent
decides not to fix one or more of them.

**Steps**:

1. The actor classifies each advisory as fixed, accepted, deferred, or
   false/stale.
2. For accepted, deferred, or false/stale advisories, the actor records a short
   rationale.
3. The PR disposition comment and epic ledger reflect the advisory decision.

**Postconditions**: Future reviewers can see which advisories were considered
and why they did or did not block merge.

**Information shown**:

- Advisory source and count.
- Advisory category.
- Decision.
- Brief rationale.

**Actions available**:

- Fix the advisory and rerun review.
- Accept the advisory with rationale.
- Defer the advisory with follow-up notes.
- Mark stale or false-positive with evidence.

**Considerations**:

- Blocking reviewer findings remain must-fix unless proven false-positive.
- Advisory rationale should be compact and evidence-backed.

## Business Rules

- A delegated run must create or update a PR disposition comment before an
  autonomous merge or human escalation decision is considered complete.
- Native epic runs must create or update one parent epic ledger comment.
- Explicit item-list runs must still write PR disposition comments, but do not
  require a parent epic ledger.
- Stable comment markers must identify PR disposition comments and epic ledger
  comments.
- Reruns must update existing audit comments rather than creating duplicates.
- Audit comments must include the reviewed head SHA so stale evidence is visible.
- Audit comments must include reviewer-loop result, blocking count, advisory
  count, risk classification, risk reasons, merge authority, and final decision.
- Accepted, deferred, or false/stale advisories require a brief rationale.
- Protocol deviations require command or action, impact, and mitigation.
- Final merge evidence must include labels, CI result, reviewer-loop summary
  presence, unresolved-thread count, PR merge state, issue state, and Project
  status update when applicable.
- Epic closeout evidence must include native sub-issues all closed, child
  Project statuses terminal, parent issue closed, and parent Project status
  updated when applicable.
- Audit output must not include secrets, credentials, tokens, or local-only paths
  beyond normal repository-relative evidence.

## Statuses / Enum Values

| Code value | Display label | Description |
| --- | --- | --- |
| `merge_approved` | Merge approved | Evidence is clean and delegated authority permits merge. |
| `fixes_required` | Fixes required | A deterministic blocker or worthwhile advisory fix remains. |
| `human_required` | Human required | The run needs a human decision, credentials, or higher authority. |
| `blocked` | Blocked | The item cannot advance because of dependency, service, setup, or unsafe state. |

**Advisory disposition values**:

- `fixed`
- `accepted`
- `deferred`
- `false_or_stale`

## Operational Visibility

- **PR disposition**: One standard comment per PR records reviewed SHA, evidence,
  advisory decisions, risk, authority, and decision.
- **Epic ledger**: One standard comment per parent epic summarizes each child
  item and updates on rerun.
- **Decision trace**: The final comment state lets a maintainer reconstruct why
  a PR was merged, blocked, fixed, or escalated.
- **Closeout evidence**: Merge cleanup and epic closeout checks appear in the
  ledger when available.

## Acceptance Criteria

- [ ] AC1: Given a delegated PR review or merge decision, the run creates or
      updates one PR disposition comment with a stable marker.
- [ ] AC2: Given a rerun for the same PR, the previous PR disposition comment is
      updated instead of duplicating comments.
- [ ] AC3: The PR disposition comment includes scope source, item, PR number,
      reviewed head SHA, reviewer result, blocking count, advisory count, risk
      classification, risk reasons, merge authority, final decision, and
      verification evidence.
- [ ] AC4: Advisory decisions are recorded as fixed, accepted, deferred, or
      false/stale, and every non-fixed advisory includes a brief rationale.
- [ ] AC5: Given an epic-scoped run, the run creates or updates one parent epic
      ledger comment with a stable marker.
- [ ] AC6: The epic ledger lists child issue number/title, PR number, tracker
      status, risk level, review result, decision, merge/cleanup verification,
      and notes.
- [ ] AC7: Given an explicit item-list run with no parent epic, PR disposition
      comments are still created and the missing epic ledger is reported as not
      applicable.
- [ ] AC8: Audit comments omit secrets, credentials, tokens, and local-only paths
      while preserving repository-relative workflow evidence.
- [ ] AC9: Protocol deviations are recorded with command/action, impact, and
      mitigation.
- [ ] AC10: Tests cover comment creation, comment update, PR disposition content,
      epic ledger table updates, explicit item-list behavior, and secret/path
      redaction.

## Out of Scope (MVP)

- Long-term metrics dashboards.
- External log sinks.
- Storing audit data outside GitHub comments.
- Replacing issue tracker status fields.
- Automatically closing the epic.

## Brief Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Record a standard PR disposition comment for delegated decisions. | Use Case 1, BR1, AC1-AC3 |
| Reconstruct why a PR was merged, blocked, fixed, accepted with advisories, or escalated. | Use Cases 1 and 3, BR6-BR10, AC3-AC4, AC9 |
| Update an epic ledger comment for epic-scoped runs. | Use Case 2, BR2, AC5-AC6 |
| Use stable comment markers and update on rerun. | BR4-BR5, AC1-AC2, AC5 |
| Avoid secrets and local-only paths. | BR12, AC8 |
| Work for explicit item-list runs. | Use Case 2, BR3, AC7 |
