# Prepare release: post-merge release branch and tracker cleanup — Spec

**Depends on**: none

---

## Overview

When a versioned release finishes, maintainers follow the prepare-release workflow so changes ship to production and return to the integration branch. Today, after both release pull requests merge, the release branch can remain on the remote and locally, and work items in the issue tracker can stay in a “shipped but not closed out” state instead of a terminal shipped state. This specification defines what the prepare-release experience must guarantee after those merges: safe cleanup of the release branch and a clear tracker signal that shipped work items have reached production.

---

## Use Cases

### Use Case 1: Release branch cleanup after both PRs merge

**Actor**: Repository maintainer or AI agent following the prepare-release protocol  
**Preconditions**: The production release PR (release branch → `main`) and the backport PR (release branch → `develop`) have both merged successfully; the release was version `vX.Y.Z` on branch `release/vX.Y.Z`.

**Steps**:

1. Confirm both PRs are merged (production first, then backport, per existing release guidance).
2. Remove the remote release branch for that version.
3. Remove the local release branch for that version when it is no longer needed for traceability.

**Postconditions**: The named `release/vX.Y.Z` branch no longer exists on the remote; the maintainer’s local clone no longer keeps that release branch checked out, and the local branch is deleted when safe to do so.

**Information shown**:

- Clear protocol steps that state when deletion is allowed and which commands or automation correspond to remote vs local cleanup.

**Actions available**:

- The maintainer (or agent) can perform the documented cleanup sequence without guessing whether it is safe.

**Considerations**:

- If only one of the two PRs has merged, the release branch must not be deleted yet.
- If local deletion fails because the branch is still checked out elsewhere, the protocol should say what to do (e.g., switch away, then retry).

---

### Use Case 2: Advance shipped work items to a terminal tracker status

**Actor**: Repository maintainer or AI agent performing post-release cleanup  
**Preconditions**: GitHub Projects (or configured tracker) is in use; one or more work items were in a “development merged to integration” status (e.g. **Merged** in this template’s project) and the corresponding release that includes their work has fully shipped (both release PRs merged).

**Steps**:

1. Identify work items that represent shipped work for this release and are still in the pre-shipped merged state.
2. Transition each such item to the configured terminal shipped status (e.g. **Released**).

**Postconditions**: Shipped items no longer appear as only “merged to develop”; they reflect that the release has reached production, consistent with how the tracker is used elsewhere in the workflow.

**Information shown**:

- Documentation explains which tracker status means “merged to integration” vs “released to production,” and how projects that use different option names should configure the mapping.

**Actions available**:

- Same GraphQL / `gh project` style updates as other tracker transitions in the repo (e.g. post-merge cleanup patterns), applied in bulk or per item as defined in the implementation plan.

**Considerations**:

- The exact single-select option name for the terminal status may differ per project; the protocol must describe how to configure it without assuming a hard-coded label beyond sensible defaults.
- Items not part of this release must not be bulk-transitioned incorrectly (scope of “which issues” is a product rule: only items that were in the merged-to-integration state and are confirmed shipped with this release, or as otherwise agreed in the plan).

---

## Business Rules

- Release branch deletion is allowed only after **both** the production and backport release PRs for that version are merged.
- Remote and local branch cleanup must both be addressed in the documented sequence so the branch does not linger indefinitely on `origin`.
- Tracker updates must use the same integration approach as existing workflow scripts (e.g. `gh project` / GraphQL) so operators have one mental model for status changes.
- Terminal shipped status (**Released** or configured equivalent) must be distinguishable from “merged to `develop`” (**Merged** or configured equivalent) in the protocol text.

---

## Statuses / Enum Values

| Code value (template default) | Display label | Description |
|---|---|---|
| `merged` | Merged | Work merged to the integration branch; not necessarily in production yet. |
| `released` | Released | Work has shipped via the production release for the relevant version. |

**Valid transitions**:

- `merged` → `released` when the prepare-release post-merge sequence confirms the item’s work is included in a release whose production and backport PRs have merged.

---

## Operational Visibility

- **Logs / console**: Branch deletion and tracker updates should emit clear success or skip reasons (e.g., missing project config, item not on board) so a human can audit a release run.
- **Audit trail**: Tracker history on the issue shows the transition to the terminal status after release.

---

## Acceptance Criteria

- [ ] The prepare-release protocol documentation lists, after merge of both release PRs, explicit steps to delete the remote `release/vX.Y.Z` branch and to delete the local branch when applicable, including the precondition that both PRs are merged.
- [ ] The same documentation describes transitioning tracker work items from the integration-merged status to the terminal shipped status, using the same class of GitHub Projects / GraphQL mechanism as existing cleanup scripts, and documents how to configure the terminal status name when it differs from **Released**.
- [ ] A human can verify the above by reading the updated protocol (and any linked wrapper docs such as command references) and checking that no step tells them to delete the release branch before both PRs are merged.
- [ ] Edge case “only one PR merged” is explicitly called out: no branch deletion and no incorrect bulk status transition.

---

## Out of Scope (MVP)

- Changing semantic versioning, changelog editing, or PR opening steps that already exist earlier in prepare-release.
- Non-GitHub trackers (unless the implementation plan chooses a minimal “document only” note).
- Automatically determining which issues belong to which release beyond what the implementation plan defines (e.g., label-based vs manual list).

---

## Open Questions

1. Should bulk “Merged → Released” apply to every project item in **Merged**, or only items linked to the release (e.g. via milestone, label, or explicit list)? *Resolution deferred to implementation plan; default preference: only items confirmed in scope for the shipped version.*
