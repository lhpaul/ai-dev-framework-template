# Changelog Fragments — Spec

---

## Overview

Today every work item records its release note in one shared block at the top of the changelog. When several items are worked in parallel, they all edit the same few lines, so each one collides with the ones merged before it. Resolving a collision is quick; what follows is not — the resolution changes the branch, and every approval that was granted against the previous version of that branch is discarded and has to be earned again.

This feature gives each work item its own changelog file. Two items worked at the same time no longer touch the same place, so the collisions stop happening rather than being resolved more cleverly. At release time the individual files are gathered into the changelog as a draft section, which the person cutting the release edits before publishing, exactly as they do today.

---

## Use Cases

### Use Case 1: Recording a release note while working an item

**Actor**: Anyone completing a work item — a person or an AI agent
**Preconditions**: The item has changes worth telling users about, and a work branch exists.

**Steps**:

1. The author writes their release note in a new file that belongs to their item alone.
2. The author states which kind of change it is, using the same kinds the changelog already uses (Added, Changed, Deprecated, Removed, Fixed, Security).
3. The author opens the pull request as usual.

**Postconditions**: The item carries its own release note. No other in-flight item is affected by it.

**Information shown**:

- Readiness checks confirm the item carries a release note, without requiring the shared changelog to have been edited.

**Actions available**:

- Edit the note at any time before release, without affecting other items.
- Omit the note deliberately for changes that need no release note, as is permitted today.

**Considerations**:

- Two items completed on the same day must never be able to claim the same file.
- An author must not have to know what any other in-flight item is doing.

---

### Use Case 2: Cutting a release

**Actor**: The person preparing a release
**Preconditions**: One or more merged items carry release notes that have not yet been released.

**Steps**:

1. The releaser starts release preparation as they do today.
2. Every unreleased note is gathered into a single draft section for the new version, grouped by kind of change.
3. The releaser reads the draft as a whole and edits it — tightening wording, merging duplicates, cutting implementation detail — which is the same editorial pass performed today.
4. The releaser publishes the release.

**Postconditions**: The changelog contains a finished section for the new version. The individual notes that fed it are gone, so nothing can be released twice.

**Information shown**:

- The assembled draft, grouped by kind of change, with every unreleased note present.

**Actions available**:

- Edit any part of the draft before publishing.
- Re-run the gathering step safely if the first attempt was interrupted.

**Considerations**:

- The releaser sees the whole release at once. This is the point of the step, and it is why gathering produces a draft rather than a finished section.
- For one release only, notes may exist in both the old shared block and the new per-item files. Both must appear in the draft.

---

### Use Case 3: Shipping an urgent fix to production

**Actor**: Anyone completing an urgent production fix
**Preconditions**: A defect in released software needs to ship immediately, outside the normal release cycle.

**Steps**:

1. The author writes the release note directly into the changelog as a finished, versioned section, as they do today.

**Postconditions**: The changelog carries the new version. Nothing about the urgent path changes.

**Considerations**:

- Urgent fixes release on merge, so there is no later gathering step for them to feed. Routing them through per-item files would add a step that never pays off.

---

## Business Rules

- A work item's release note belongs to that item alone. No two in-flight items may need to edit the same content to record their notes.
- Every release note carries one kind of change, drawn from the set the changelog already uses.
- A release note is written once and survives unchanged until a release consumes it, unless its author edits it.
- Gathering consumes notes: once a note has been released it cannot be gathered again, and no unreleased note may be silently left behind.
- Gathering is repeatable. Running it twice in a row must leave the same result as running it once.
- The changelog remains the permanent record of everything released. This feature changes only how notes accumulate before a release, never the released history.
- Readiness checks that today confirm an item recorded a release note must accept a per-item note as satisfying that requirement.
- Urgent production fixes keep writing finished versioned sections directly, and are never gathered.
- For the single release that spans the transition, notes already recorded in the shared block are released alongside per-item notes, with nothing lost or duplicated.

---

## Operational Visibility

- **Logs**: The gathering step reports how many notes it consumed and which items they came from, so a releaser can confirm nothing was missed.
- **Audit trail**: Consumed notes are removed as part of the release, making "released" and "not yet released" visible from the repository state rather than inferred.

---

## Acceptance Criteria

- [ ] Two work items completed at the same time, both recording release notes, merge one after the other without either needing a conflict resolved, and both notes are present afterwards.
- [ ] A pull request that records a release note the new way passes the readiness check that confirms a release note exists, without editing the shared changelog.
- [ ] Preparing a release gathers every unreleased note into a draft section for the new version, grouped by kind of change, with no note missing.
- [ ] The releaser can edit the assembled draft before publishing, and the published section reflects their edits.
- [ ] After a release, no consumed note remains, and running the gathering step again produces no duplicate entries.
- [ ] A release cut during the transition includes both the notes already in the shared block and the per-item notes, each appearing exactly once.
- [ ] An urgent production fix still writes its own finished versioned section and is unaffected by gathering.
- [ ] A project created from this template records release notes the new way without additional setup.
- [ ] The changelog's existing published history is unchanged by adopting this feature.

---

## Out of Scope (MVP)

- Converting the release notes already sitting in the shared block into per-item files. They stay where they are and are released from there once.
- Any change to how urgent production fixes are recorded.
- Automatic generation of release notes from commits, pull request titles, or issue text. Notes stay author-written.
- Changing which kinds of change the changelog recognises, or the format of published version sections.
- A migration tool for projects already created from this template that want to convert existing shared-block entries.
- Enforcing a quality bar on individual notes at the time they are written. The release editorial pass remains where quality is set.
