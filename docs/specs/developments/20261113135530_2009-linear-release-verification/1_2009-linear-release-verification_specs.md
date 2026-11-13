# Verified Linear release completion — Spec

## Overview

When a project tracks work in Linear, release cleanup cannot apply release
labels or move items to Released by itself, so it hands those steps to the
release operator. Today nothing checks that the handoff was carried out, and a
release can be reported complete while shipped items have no release label or
are still in Merged. This feature makes Linear release completion depend on an
independent read of each shipped item's tracker state: the release is reported
complete only when every in-scope item is verified as labelled for the release
and Released, and otherwise the report names each item and what is missing.

The scope is issue [#2009](https://github.com/lhpaul/ai-dev-framework-template/issues/2009),
reported by a downstream repository using the Linear tracker. GitHub Projects
and GitHub Issues release behaviour is unchanged.

## Use Cases

### Use Case 1: Complete a Linear release with verified items

**Actor**: The release operator (a human or the agent running the Prepare
Release cleanup step).
**Preconditions**: The release PRs are merged, release cleanup has resolved the
release version and the in-scope Linear items, and the operator has tracker
access through the Linear integration the workflow already documents.

**Steps**:

1. Run release cleanup for the release version.
2. Cleanup lists every in-scope item with the release label it must carry and
   the required Released status, and reports the release as not yet verified.
3. The operator makes sure the release label exists in the owning Linear team,
   applies it to every listed item, and moves every listed item to Released.
4. The operator reads each listed item back from Linear, independently of the
   write, and supplies that read to release verification.
5. Release verification compares each item's read state with the requirement.

**Postconditions**: Every in-scope item is reported as Verified with the label
and status that were read, and the release cleanup outcome is Complete.

**Information shown**:

- The release version and the release label it requires.
- For each in-scope item: its identifier, the label and status that were read,
  when they were read, and its verification result.
- The overall outcome (Complete or Incomplete) and the counts per result.

**Actions available**:

- Report the release as complete once the outcome is Complete.

**Considerations**:

- A release with no in-scope items keeps its existing empty-scope behaviour;
  there is nothing to verify and nothing is reported as verified.

---

### Use Case 2: An item is left in Merged or without its release label

**Actor**: The release operator.
**Preconditions**: As in Use Case 1, but at least one item was not labelled or
not moved to Released, or the read shows a different state than the operator
expected.

**Steps**:

1. The operator supplies the read-back for the release items.
2. Release verification finds an item whose read state lacks the release label,
   or whose status is not Released, or both.

**Postconditions**: The outcome is Incomplete. Each affected item is named with
what is missing; items that passed are still listed as Verified.

**Information shown**:

- Per affected item: Missing release label, Not released, or both, with the
  label and status that were actually read.
- The list of items still missing, ready to act on.

**Actions available**:

- Fix the named items in Linear, read them back again, and re-run verification.
- Accept tracker completion outside the workflow only through the existing
  explicit best-effort acceptance; that acceptance never turns the outcome into
  Complete.

**Considerations**:

- An item that is already Released and labelled before cleanup runs is
  verified like any other; it is not an error.

---

### Use Case 3: The release label does not exist yet (including hotfix versions)

**Actor**: The release operator.
**Preconditions**: The release version's label does not exist in the owning
Linear team. This includes patch and hotfix versions such as `v1.29.1`.

**Steps**:

1. Cleanup names the exact release label each item must carry. When no read
   of an in-scope item shows that label, cleanup also reports, as an explicit
   action item, that the label may be missing from the owning team and must
   exist before items can be labelled.
2. The operator creates the label through the Linear integration, then labels
   the items as in Use Case 1.
3. If the operator cannot create the label, the read-back shows the items
   without it.

**Postconditions**: Either the label was created and the items verify, or the
outcome is Incomplete and the missing label is named as an action item. A
missing label is never skipped silently and never reported as verified.

**Information shown**:

- The exact release label name and whether it was observed in the read-back.
- Each item that cannot be verified because the label is missing.

**Actions available**:

- Create the label and re-run verification.

**Considerations**:

- A hotfix release is verified with exactly the same rules as any other
  release version; the version's patch number does not change any rule.

---

### Use Case 4: No read-back, or read-back that does not count

**Actor**: The release operator.
**Preconditions**: Release cleanup runs for a Linear release, and the operator
either supplies no read-back, or supplies one that does not belong to this
release verification.

**Steps**:

1. Release verification looks for a usable read for every in-scope item.
2. Items without a usable read are reported as Not verified, with the reason.

**Postconditions**: The outcome is Incomplete whenever any in-scope item is Not
verified. Guidance that was printed, or a write that was echoed back, is never
accepted in place of an independent read.

**Information shown**:

- Per item, the reason the read does not count: no read supplied, read for a
  different item or release version, read taken before this release's cleanup
  started, read from a team other than the owning one, or a read that cannot be
  understood.

**Actions available**:

- Read the items again and re-run verification.

**Considerations**:

- A read supplied for an item that is not in the release scope is reported as
  ignored and does not affect the outcome.

---

### Use Case 5: Release with a GitHub tracker

**Actor**: The release operator.
**Preconditions**: The project uses GitHub Projects or GitHub Issues.

**Steps**:

1. Run release cleanup as today.

**Postconditions**: Release stamping, status transitions, outcome reporting and
exit behaviour are unchanged from the current release.

## Business Rules

- BR1: For a Linear release, release cleanup reports Complete only when every
  in-scope item is Verified. Any other per-item result makes the outcome
  Incomplete.
- BR2: An item is Verified only when an independent read of that item, from
  the owning Linear team, taken after this release's cleanup started, shows
  both the release label for this exact version and the Released status.
- BR3: Printed guidance, a deferred action signal, the operator's assertion, or
  the response echoed by the write itself never counts as a read.
- BR4: The release label is the configured release label prefix followed by the
  release version (default `release/vX.Y.Z`), including patch and hotfix
  versions. When the project records releases in a configured release field
  instead of a label, the same rules apply to that field's value.
- BR5: A missing release label in the owning team is either created by the
  operator before stamping or reported as an explicit action item naming the
  label. It is never skipped silently.
- BR6: Every Incomplete report names every item that is not Verified, with the
  per-item result and what was read.
- BR7: Explicit best-effort acceptance keeps its current meaning (the operator
  takes over tracker completion outside the workflow). It may end the cleanup
  run without an error, but the reported outcome stays Incomplete and the
  unverified items are still listed.
- BR8: Verification reads tracker state; it never moves items, never removes
  labels, and never changes items outside the release scope.
- BR9: Release scope is decided exactly as today. This feature does not change
  which items are in a release.
- BR10: GitHub Projects and GitHub Issues release behaviour is unchanged.
- BR11: The verification can be re-run any number of times; each run evaluates
  only the reads supplied to it and the current release scope.

## Statuses / Enum Values

Per-item verification results:

| Code value | Display label | Description |
| --- | --- | --- |
| `verified` | Verified | Read shows the release label and the Released status. |
| `missing_label` | Missing release label | Read shows Released but not the release label. |
| `not_released` | Not released | Read shows the release label but a status other than Released. |
| `missing_label_and_not_released` | Missing release label and not released | Read shows neither requirement. |
| `not_verified` | Not verified | No usable read for the item; the reason is shown. |

Overall release cleanup outcome for Linear:

| Code value | Display label | Description |
| --- | --- | --- |
| `complete` | Complete | Every in-scope item is Verified. |
| `incomplete` | Incomplete | At least one in-scope item is not Verified. |

**Valid transitions**:

- An item moves from any non-Verified result to Verified only on a later
  verification run with a usable read that satisfies BR2.
- The outcome moves from Incomplete to Complete only on a verification run in
  which every in-scope item is Verified.

## Operational Visibility

- **Logs**: Every Linear release cleanup run prints the release version, the
  release label, one line per in-scope item with its result and read state,
  counts per result, and the overall outcome. Missing labels appear as explicit
  action items.
- **Notifications**: None beyond the cleanup output and the existing release
  completion report.
- **Audit trail**: The read-back used for a Complete outcome is retained with
  the run so a reviewer can see what was read and when.

## Acceptance Criteria

- [ ] AC1: In a Linear release where every in-scope item is read back with the
  release label and Released, release cleanup reports Complete and lists each
  item as Verified with the label and status read.
- [ ] AC2: In a Linear release where one item is read back in Merged, cleanup
  reports Incomplete, names that item as Not released, and lists the others as
  Verified.
- [ ] AC3: In a Linear release where one item is read back without the release
  label, cleanup reports Incomplete and names that item as Missing release
  label.
- [ ] AC4: In a Linear hotfix release (for example `v1.29.1`) whose label does
  not exist yet, cleanup names the label as an action item; with no read-back
  showing it applied, the outcome is Incomplete and the label gap is named, not
  skipped.
- [ ] AC5: With no read-back supplied, every in-scope item is Not verified and
  the outcome is Incomplete; printed guidance alone never yields Complete.
- [ ] AC6: A read for a different release version, a different item, a team
  other than the owning one, a read taken before the cleanup run started, or an
  unreadable read leaves the item Not verified with the reason shown.
- [ ] AC7: With explicit best-effort acceptance and unverified items, the run
  may end without an error but still reports Incomplete and lists the
  unverified items.
- [ ] AC8: A read for an item outside the release scope is reported as ignored
  and does not change the outcome.
- [ ] AC9: GitHub Projects and GitHub Issues release cleanup keep their
  existing stamping, transitions, output and exit behaviour, proven by the
  existing release cleanup tests passing unchanged.
- [ ] AC10: The Prepare Release completion step and the Linear integration
  guide describe the verification and state that a Linear release is not
  complete until it reports Complete.

## Brief Objective List and Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Linear release cleanup is not complete while any in-scope item lacks the release label or is not Released | AC1, AC2, AC3; BR1, BR2 |
| Verification reads tracker state back instead of trusting guidance | AC5, AC6; BR2, BR3 |
| Missing release labels, including hotfix versions, are created or reported as an action item | AC4; BR4, BR5 |
| Output lists per item the verified label and state, and which items are still missing | AC1, AC2, AC3; BR6 |
| Regression: all items stamped and Released reports complete | AC1 |
| Regression: one item left in Merged or without its label reports incomplete and names it | AC2, AC3 |
| Regression: hotfix label not existing yet is created or flagged, not skipped | AC4 |
| Regression: GitHub Projects behaviour unchanged | AC9; BR10 |
| Evidence: release scope false negatives (items missing from scope) | Out of Scope (deferral note 1) |
| Evidence: hotfix commits without the tracker ID in their text | Out of Scope (deferral note 2) |
| Evidence: historical releases left unlabelled | Out of Scope (deferral note 3) |

**Deferral notes**:

1. *Scope false negatives* — items that shipped but never entered the release
   scope. Rationale: scope derivation is tracked by #1982; this feature
   verifies the items that are in scope (BR9). Human confirmation: not
   requested; #1982 owns it.
2. *Hotfix commits that do not mention the tracker ID* — attribution of such
   commits to items. Rationale: this is scope derivation (#1982), and the
   current scope already uses the PR's branch and title rather than commit
   text. Human confirmation: not requested.
3. *Backfilling past releases* — the downstream repository already backfilled
   its historical releases by hand on 2026-10-21. Rationale: a one-off data
   repair, not workflow behaviour. Human confirmation: not requested.

## Workflow Decision-Gate Consistency Matrix

Provider rows are evaluated first. For Linear, item rows are evaluated per
in-scope item in order, and the first matching row decides that item's result.
Release-level rows are evaluated once per run, after the item rows, and add
action items without changing any item's result. The overall outcome is
Complete only when every in-scope item ends in the Verified row.

| Inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Provider is GitHub Projects or GitHub Issues | Existing behaviour | None new | Protocol 05 §9.4–9.5; release cleanup tests | GitHub milestone stamping |
| Provider is none or another non-Linear provider | Existing behaviour | None new | Protocol 05 §9.4 | Release stamp skipped as today |
| Linear, release scope empty | Existing empty-scope behaviour | As today | Protocol 05 §9.1; Linear guide | Range with no Linear IDs |
| Linear, no read supplied for the item | Not verified (no read) | Read the item back and re-run | Protocol 05 §9.4–9.5; Linear guide | Operator skipped the read |
| Linear, read cannot be understood | Not verified (unreadable) | Supply a well-formed read | Same | Truncated read |
| Linear, read for another item, version or team | Not verified (mismatch) | Read the right item from the owning team | Same | Read for `v1.29.0` during `v1.29.1` |
| Linear, read taken before cleanup started | Not verified (stale) | Read again after stamping | Same | Read reused from a previous run |
| Linear, current read, label present, status Released | Verified | None | Same | Item stamped and Released |
| Linear, current read, label absent, status Released | Missing release label | Create the label if needed, apply it, re-read | Same | Label never applied |
| Linear, current read, label present, status not Released | Not released | Move to Released, re-read | Same | Item left in Merged |
| Linear, current read, label absent, status not Released | Missing release label and not released | Apply label and status, re-read | Same | Handoff not done |
| Linear (release level), release label not observed on any in-scope item read | Action item naming the label as possibly missing from the owning team | Create the label if absent, apply, re-read | Same | Hotfix `release/v1.29.1` never created |
| Linear (release level), read for an item outside scope | Ignored; no effect on outcome | None | Same | Extra item read |
| Linear (release level), best-effort accepted, any item not Verified | Run may end without error; outcome Incomplete | Complete tracker work outside the workflow | Protocol 05 §9.5 | Human accepted manual completion |

## Out of Scope (MVP)

- Changing which items are in a release scope (tracked by #1982), including
  attribution of hotfix commits that do not mention the tracker ID.
- Backfilling labels or statuses for releases that already shipped.
- A new direct Linear connection inside the shell helpers; the operator keeps
  performing Linear writes and reads through the integration the workflow
  already documents.
- Automatically moving items to Released or applying labels from the shell
  helpers.
- Any change to GitHub Projects or GitHub Issues release behaviour, or to other
  providers.
- Merge-session (Protocol 94) bridge semantics, which already require
  independent Linear read-back for admitted sessions.
