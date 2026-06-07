# Release stamping for shipped issues — Spec

---

## Overview

When a production release is prepared, each shipped issue should show which production version delivered it. Today the workflow moves issues from Merged to Released, but the release version is only inferable from the changelog. This feature adds a tracker-agnostic release stamp so operators can answer "what version shipped this issue?" directly from the issue tracker, using each provider's native release mechanism where one exists.

---

## Brief Objective List

- OBJ-1: Record the production release on every issue that ships in a release.
- OBJ-2: Use GitHub Milestones as the GitHub Issues / GitHub Projects release primitive.
- OBJ-3: Create the release marker for a version if it does not already exist.
- OBJ-4: Determine the shipped issue set from the released CHANGELOG section.
- OBJ-5: Apply the release stamp during the same Merged to Released transition.
- OBJ-6: Close or finalize the release marker once the release is published, where the provider supports that lifecycle.
- OBJ-7: Document the GitHub milestone-per-release convention and board visibility.
- OBJ-8: Reference release stamping from the prepare-release workflow surfaces.
- OBJ-9: Provide a structured issue-to-version source for retrospectives.
- OBJ-10: Define a tracker-agnostic release-stamp operation routed by `issue_tracker.provider`.
- OBJ-11: Use GitHub CLI for GitHub providers and MCP/API-backed writes for non-GitHub providers.
- OBJ-12: Make provider-specific field, label, or version names configurable when the provider needs repository-specific mapping.
- OBJ-13: Document the provider mechanism in each relevant tracker integration guide.
- OBJ-14: Fail soft when a configured provider has no wired release-stamp mechanism.

---

## Use Cases

### Use Case 1: Prepare release stamps shipped issues

**Actor**: Release operator running the prepare-release workflow
**Preconditions**: A release version has been selected, the changelog contains the versioned release section, and one or more referenced issues are ready to move from Merged to Released

**Steps**:

1. The operator runs the prepare-release workflow through the point where the production release is published.
2. The workflow reads the released changelog section to identify every issue reference included in that version.
3. For each issue, the workflow records the release version using the configured tracker provider's release primitive.
4. The workflow moves each successfully processed issue from Merged to Released.
5. The workflow finalizes the provider's release marker if the provider supports a final or closed state.

**Postconditions**: Each shipped issue has a visible release stamp for the production version, and the issue status reflects Released.

**Information shown**:

- The release version associated with each shipped issue.
- A warning summary for any issue whose release stamp could not be written.
- The normal release workflow status and issue transition output.

**Actions available**:

- The operator can inspect an issue and see the release version without parsing the changelog manually.
- The operator can filter or group issues by the release marker when the tracker provider supports that view.
- The operator can rerun or manually repair release stamping for issues that logged warnings.

**Considerations**:

- The changelog release section is the provider-independent source of truth for which issues shipped.
- A release-stamp write failure must not block publishing or backport completion by itself; the workflow logs the warning and continues.
- If an issue reference appears in the changelog but is not present in the configured tracker, the workflow records a warning and continues with the remaining issues.

---

### Use Case 2: Operator queries shipped version from the tracker

**Actor**: Maintainer reviewing a completed issue after release
**Preconditions**: The issue was included in a production release processed by the release-stamping workflow

**Steps**:

1. The maintainer opens the issue in the configured tracker.
2. The maintainer reads the provider-native release marker on the issue.
3. When supported by the provider, the maintainer filters or groups issues by that release marker.

**Postconditions**: The maintainer can identify the production version that shipped the issue without searching release PRs or changelog history.

**Information shown**:

- The release marker, displayed in the provider's native issue UI.
- For GitHub providers, the marker is visible as a milestone and on the GitHub Projects board through the built-in Milestone field.

**Actions available**:

- Maintainers can audit all issues shipped in a release.
- Maintainers can answer support or retrospective questions about when a specific issue shipped.

**Considerations**:

- Provider display names may differ, but the user-facing meaning is always "Released in version vX.Y.Z."
- Provider-specific release markers should not create unbounded classification labels when a native release primitive exists.

---

### Use Case 3: Unsupported provider degrades gracefully

**Actor**: Release operator running prepare-release in a repository with an unsupported or partially configured tracker provider
**Preconditions**: The workflow has identified shipped issues, but the configured provider has no implemented release-stamp writer or is missing required configuration

**Steps**:

1. The workflow attempts to resolve the configured provider's release-stamp mechanism.
2. The workflow determines that no supported write path is available, or that required provider configuration is missing.
3. The workflow logs a clear best-effort warning for the skipped release stamp.
4. The workflow continues the release process and status transitions that remain available.

**Postconditions**: The release is not blocked solely because release stamping is unavailable, and the operator has enough warning detail to repair configuration later.

**Information shown**:

- Provider name.
- Release version.
- Issue identifier.
- Reason the release stamp was skipped.

**Actions available**:

- The operator can add the missing provider configuration.
- The operator can manually stamp the issue in the tracker.
- The operator can proceed with the release when the missing stamp is acceptable.

---

## Business Rules

- The release stamp means "this issue shipped in production release vX.Y.Z."
- The changelog version section is the authoritative provider-independent source for the issue set included in a release.
- Release stamping occurs as part of the release workflow that moves issues from Merged to Released.
- The release stamp write is best effort. A failed stamp write produces a warning and does not block release publication.
- Provider routing is based on the configured issue tracker provider.
- GitHub Issues and GitHub Projects use a milestone named for the release version, such as `v1.2.0`.
- Jira uses the provider's native Fix Version/s release field.
- Linear defaults to a release label such as `release/v1.2.0` unless a repository configures a custom release field.
- ClickUp and Notion use a configured custom field, tag, or select property that represents "Released In."
- A repository with no issue tracker skips release stamping.
- Provider-specific field names, custom-field keys, label prefixes, or version identifiers are configurable for providers that need repository-specific mapping.
- Non-GitHub providers are written by the orchestrator-owned release workflow layer because subagent contexts may not have MCP access.
- GitHub providers use the GitHub issue UI's native release marker instead of release labels.
- The workflow must avoid creating one-off classification labels for providers that already have a native release field.
- The release marker is created if absent before assigning it to shipped issues.
- The release marker is closed or finalized after publication where the provider has a release-marker lifecycle.

---

## Operational Visibility

- **Logs**: The release workflow reports each issue that was stamped, each issue that was skipped, and the reason for each skip.
- **Warnings**: Provider configuration gaps, missing tracker records, provider API failures, and unsupported providers are reported as best-effort warnings.
- **Audit trail**: The tracker provider's native issue history records the release marker assignment when the provider exposes such history.

---

## Acceptance Criteria

- [ ] AC-1: Given a release version with a populated changelog section, the release workflow identifies every referenced issue in that section as the shipped issue set.
- [ ] AC-2: For GitHub Issues and GitHub Projects providers, each shipped issue is assigned a milestone named for the release version, and the milestone is created first if it does not already exist.
- [ ] AC-3: For GitHub Projects, the release version is visible through the issue milestone and the project board's built-in Milestone field.
- [ ] AC-4: For Jira providers, the release version is recorded using the native Fix Version/s release mechanism when the repository has the required provider configuration.
- [ ] AC-5: For Linear providers, the release version is recorded using the configured custom release field when present, otherwise by applying the configured release label prefix.
- [ ] AC-6: For ClickUp and Notion providers, the release version is recorded using the configured custom field, tag, or select property when present.
- [ ] AC-7: For repositories with `issue_tracker.provider` set to `none`, release stamping is skipped without an error.
- [ ] AC-8: If a provider write fails, the workflow logs the provider, issue identifier, version, and failure reason, then continues the release flow.
- [ ] AC-9: Issue status transition to Released and release stamping are performed in the same release workflow stage for each shipped issue.
- [ ] AC-10: Where the provider supports a releasable marker lifecycle, the release marker is finalized or closed after the release is published.
- [ ] AC-11: The prepare-release protocol and command/skill entrypoints mention release stamping as part of the post-publication release workflow.
- [ ] AC-12: The GitHub Projects integration guide documents the milestone-per-release convention and explains that GitHub Projects can surface milestones through the built-in Milestone field.
- [ ] AC-13: Each tracker integration guide that exists in the repository documents that provider's release-stamp mechanism or explicitly states that the provider currently degrades gracefully.
- [ ] AC-14: A retrospective or audit workflow can use the tracker release stamp as a structured issue-to-version source alongside the changelog.

---

## Coverage Matrix

| Brief objective | Coverage |
| ---------------- | -------- |
| OBJ-1: Record the production release on every issue that ships in a release. | AC-1, AC-2, AC-4, AC-5, AC-6, AC-9 |
| OBJ-2: Use GitHub Milestones as the GitHub Issues / GitHub Projects release primitive. | AC-2, AC-3, AC-12 |
| OBJ-3: Create the release marker for a version if it does not already exist. | AC-2, AC-10 |
| OBJ-4: Determine the shipped issue set from the released CHANGELOG section. | AC-1 |
| OBJ-5: Apply the release stamp during the same Merged to Released transition. | AC-9 |
| OBJ-6: Close or finalize the release marker once the release is published, where the provider supports that lifecycle. | AC-10 |
| OBJ-7: Document the GitHub milestone-per-release convention and board visibility. | AC-12 |
| OBJ-8: Reference release stamping from the prepare-release workflow surfaces. | AC-11 |
| OBJ-9: Provide a structured issue-to-version source for retrospectives. | AC-14 |
| OBJ-10: Define a tracker-agnostic release-stamp operation routed by `issue_tracker.provider`. | Business Rules, AC-2, AC-4, AC-5, AC-6, AC-7 |
| OBJ-11: Use GitHub CLI for GitHub providers and MCP/API-backed writes for non-GitHub providers. | Business Rules, AC-2, AC-4, AC-5, AC-6 |
| OBJ-12: Make provider-specific field, label, or version names configurable when the provider needs repository-specific mapping. | Business Rules, AC-4, AC-5, AC-6 |
| OBJ-13: Document the provider mechanism in each relevant tracker integration guide. | AC-13 |
| OBJ-14: Fail soft when a configured provider has no wired release-stamp mechanism. | AC-7, AC-8, AC-13 |

---

## Out of Scope (MVP)

- Backfilling release stamps onto issues shipped by historical releases.
- Building dashboards, charts, or reports over releases.
- Making release-stamp failures block release publication.
- Replacing the changelog as the authoritative release contents record.
- Choosing exact helper names, command-line flags, scripts, workflow files, or MCP calls; those details belong in the implementation plan.
- Migrating existing label-based release markers, if any, into provider-native release markers.
