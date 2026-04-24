# Retrospective: Template-Aware Backlog Cross-Reference with Version Tracking — Spec

**Depends on**: <!-- No dependencies -->

---

## Overview

When a downstream project runs a retrospective, the analyst currently has no way to know whether a finding already exists in the upstream template's backlog, has already been fixed in a newer template version, or is genuinely new. This feature adds a template cross-reference step to the retrospective protocol: when the downstream project is configured with an upstream template repository and a last-synced version, each finding is automatically classified against three buckets — already tracked, already fixed (sync opportunity), or new (contribute upstream candidate). If the upstream template is not configured, the step is silently skipped for full backward compatibility.

---

## Use Cases

### Use Case 1: Retrospective Analyst Cross-References Findings Against Template Backlog

**Actor**: Retrospective Analyst (the AI agent running the retrospective protocol, or a human following it)
**Preconditions**:
- A retrospective is in progress and Step 3 findings have been categorized
- The downstream project's workflow configuration includes an upstream template repository reference
- The analyst has network access to query the template repository's issue tracker

**Steps**:
1. The analyst reads the workflow configuration and detects the template repository reference
2. The analyst queries the template repository for open issues
3. For each retrospective finding, the analyst compares it against the open template issues
4. For each finding that does not match an open issue, the analyst checks closed template issues whose associated fix version is newer than the downstream project's last-synced version
5. Each finding is labeled with one of three classifications (see Business Rules)
6. The classification is carried into the findings presentation (Step 4) alongside the existing tracker-match results

**Postconditions**: Every retrospective finding carries a template cross-reference classification label

**Information shown**:
- For each finding: its classification label and the relevant template issue number or version, if applicable
- A summary line indicating how many findings were cross-referenced and what tool was used

**Actions available**:
- The human can accept or override any classification during the review step

**Considerations**:
- If the template repository is unreachable at analysis time, the analyst records a warning for each finding and continues without the cross-reference (graceful degradation)
- If the configured template repository reference is malformed, the analyst reports an error and marks all findings as "Template check unavailable" (same outcome as an unreachable repository)

---

### Use Case 2: Retrospective Analyst Skips Cross-Reference (Template Not Configured)

**Actor**: Retrospective Analyst
**Preconditions**:
- A retrospective is in progress
- The downstream project's workflow configuration does not include a template repository reference

**Steps**:
1. The analyst reads the workflow configuration
2. The template repository reference is absent or empty
3. The analyst silently skips the template cross-reference step

**Postconditions**: The retrospective proceeds exactly as it did before this feature was introduced; no change in behavior or output

**Information shown**: Nothing — the step is invisible to the analyst and the human when not configured

**Considerations**:
- This use case covers all existing downstream projects that have not yet added the new configuration fields

---

### Use Case 3: Sync-Template Skill Records Last-Synced Version

**Actor**: Developer (human running the sync-template skill)
**Preconditions**:
- The developer has successfully completed a template sync operation using the sync-template skill
- The downstream project's workflow configuration file is writable

**Steps**:
1. The sync-template skill determines the template version it just synced from
2. After all changes are applied and before generating git instructions, the skill writes the version into the workflow configuration file under the `template.last_synced_version` field
3. The git instructions shown to the developer include staging the updated workflow configuration file

**Postconditions**: The workflow configuration file contains an up-to-date `template.last_synced_version` value that reflects the template version just applied

**Information shown**:
- A confirmation line in the sync summary: "Recorded last_synced_version: vX.Y.Z in .ai-dev-workflow.yaml"
- The git stage instructions include `.ai-dev-workflow.yaml`

**Considerations**:
- If the workflow configuration file does not yet contain a `template` section, the skill creates it
- If the field already exists with a different value, the skill overwrites it with the new version

---

## Business Rules

- **BR-1 — Opt-in only**: The template cross-reference step runs if and only if `template.repository` is set in the workflow configuration. An absent or empty value means the step is skipped silently.
- **BR-2 — Three-bucket classification**: When the template repository is reachable, each finding must be assigned exactly one of the following labels:
  - "Already in template backlog" — a matching open issue exists in the template repository; include the template issue number
  - "Already fixed upstream" — a matching closed issue exists whose fix shipped in a template version newer than the downstream project's `last_synced_version`; include both the fix version and the downstream's current synced version
  - "Contribute upstream candidate" — no matching open or relevant closed issue found; the finding appears to be new and is a candidate for upstream contribution
- **BR-3 — Version comparison requires last_synced_version**: The "Already fixed upstream" classification is only possible when `template.last_synced_version` is set. When it is absent, closed issues are treated as "unknown sync status" and findings that would match them fall back to "Contribute upstream candidate" with a note that the synced version is unknown
- **BR-4 — Matching heuristic**: A finding matches a template issue when the finding's affected area (protocol name, file path, or category) overlaps with the issue's title or labels. The same three-criterion matching heuristic used in the existing Step 3a tracker query applies: exact path/name match, strong keyword overlap, or shared root-cause category
- **BR-5 — Graceful degradation**: If the template repository is unreachable, the step adds a warning to the retrospective output and marks all findings as "Template check unavailable" rather than blocking the retrospective
- **BR-6 — Closed-issue version resolution**: The fix version for a closed template issue is the template release version in which the issue's fix first shipped. If the fix version cannot be determined, the finding falls back to "Contribute upstream candidate" with a note that the fix version is unknown (parallel to the BR-3 fallback for absent `last_synced_version`)
- **BR-7 — last_synced_version is written by sync-template only**: Only the sync-template skill writes `template.last_synced_version`. The retrospective protocol reads it but never writes it
- **BR-8 — Backward compatibility**: Projects that have not added the `template` section to their workflow configuration must experience zero behavior change in their retrospective runs
- **BR-9 — Malformed repository reference**: If `template.repository` is set but its value is malformed (e.g., not a valid `owner/repo` slug), the step reports an error to the retrospective output and marks all findings as "Template check unavailable", the same classification outcome as BR-5 (unreachable repository) but with error severity instead of warning severity. The step never silently skips when a value is present but invalid

---

## Acceptance Criteria

- [ ] When `template.repository` is set in `.ai-dev-workflow.yaml` and the template repository is reachable, each retrospective finding in Step 3 carries one of the three classification labels before the findings are presented in Step 4
- [ ] When `template.repository` is absent or empty, the retrospective runs to completion with no mention of the template cross-reference step, and its output is identical to pre-feature behavior
- [ ] When a finding matches an open template issue, the presentation includes the template issue number (e.g., "Already in template backlog: template#123") and suggests Skip or Expand as alternatives to creating a new issue
- [ ] When a finding matches a closed template issue whose fix version is newer than `template.last_synced_version`, the presentation includes both the fix version and the downstream's current synced version (e.g., "Already fixed upstream in v0.24.0 — you are on v0.22.0; consider syncing instead of contributing")
- [ ] When `template.last_synced_version` is absent and a closed issue would otherwise match, the finding is classified as "Contribute upstream candidate" with a note that the synced version is unknown
- [ ] When a finding matches a closed template issue whose fix version cannot be determined, the finding is classified as "Contribute upstream candidate" with a note that the fix version is unknown
- [ ] When `template.repository` is set but its value is malformed, the retrospective completes with an error message and all findings show "Template check unavailable" rather than failing silently
- [ ] When the template repository is unreachable, the retrospective completes with a warning and all findings show "Template check unavailable" rather than failing
- [ ] After a successful sync-template run, `.ai-dev-workflow.yaml` contains `template.last_synced_version` set to the version that was just synced
- [ ] The sync-template git instructions include `.ai-dev-workflow.yaml` in the staged files list
- [ ] `.ai-dev-workflow.yaml` in this template repository documents the `template.repository` and `template.last_synced_version` fields with comments explaining their purpose

---

## Out of Scope (MVP)

- Automatic creation of template issues from retrospective findings (the feature surfaces "Contribute upstream" candidates but does not create the issues automatically)
- Cross-referencing against multiple upstream template repositories (single repository only)
- Caching of template issue data between retrospective runs (each run queries fresh)
- UI or dashboard for viewing template sync status across multiple downstream projects
- Automated PR creation to sync a version gap identified during retrospective (the feature surfaces the opportunity; acting on it is a separate manual step)
