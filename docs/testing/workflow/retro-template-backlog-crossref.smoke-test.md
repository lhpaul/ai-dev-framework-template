# Smoke Test Runbook: Retrospective Template-Aware Backlog Cross-Reference

**Feature**: Retrospective template-aware backlog cross-reference with version tracking
**Spec**: [1_retro-template-backlog-crossref_specs.md](../../specs/developments/20260424165259_retro-template-backlog-crossref/1_retro-template-backlog-crossref_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR for this feature has been merged to `develop`
- [ ] You have `gh` CLI access to the repository and to a test template repository (a real or test GitHub repo you control)
- [ ] The repository under test has a `.ai-dev-workflow.yaml` file
- [ ] You have access to a recent retrospective scenario (or can simulate one by reading the retrospective protocol)
- [ ] No application server is required — all tests are protocol walkthroughs and file inspection

---

## Test Data

| Item                                                                | Value                                                                                         |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Test template repository                                            | A GitHub repo you control in `owner/repo` format (e.g., `your-org/ai-dev-framework-template`) |
| Open template issue (for `already-tracked` test)                    | Any open issue in the test template repository                                                |
| Closed template issue with known version (for `already-fixed` test) | Any closed issue in the test template repository                                              |
| Malformed repository reference                                      | `not-a-valid-format` (missing `/` separator)                                                  |
| Unreachable repository reference                                    | `nonexistent-owner-xyz123/nonexistent-repo-xyz123`                                            |

---

## Smoke Test Steps

### Step 1: Backward-compatibility check — template not configured

**Maps to**: AC "when template repository reference is absent, retrospective runs identically to pre-feature behavior"

1. Open `.ai-dev-workflow.yaml` in the project under test
2. Confirm there is no `template:` section, or that `template.repository` is empty or absent
3. Run a retrospective (follow `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` Step 3)
4. Observe Step 3 output

**Expected result**: Step 3b is completely absent from the output. No mention of "template cross-reference", "Already in template backlog", "Contribute upstream candidate", or similar labels. The retrospective output is identical to pre-feature behavior.

---

### Step 2: Template repository configured — all three classification buckets

**Maps to**: AC "each finding carries one of the three classification labels before findings are presented"

1. Add the `template:` section to `.ai-dev-workflow.yaml`:
   ```yaml
   template:
     repository: "your-org/ai-dev-framework-template"
     last_synced_version: "v0.22.0"
   ```
2. Run a retrospective with at least three findings:
   - One finding that matches an open issue in the template repository
   - One finding that matches a closed issue whose fix shipped in a version newer than `v0.22.0`
   - One finding with no match in the template repository
3. Observe Step 3b output

**Expected result**:

- Finding matching open issue: labeled "Already in template backlog: template#NNN" **and the presentation suggests Skip or Expand as alternatives to creating a new upstream issue** (per AC 3)
- Finding matching newer closed issue: labeled "Already fixed upstream in vX.Y.Z — you are on v0.22.0; consider syncing instead of contributing"
- Finding with no match: labeled "Contribute upstream candidate"
- All three labels appear before Step 4 presentation

---

### Step 3: `last_synced_version` absent — closed issue fallback

**Maps to**: AC "when recorded last-synced version is absent and a closed issue would otherwise match, finding is classified as Contribute upstream candidate with a note"

1. Set `template.repository` to a valid repository and set `template.last_synced_version` to `""` (empty)
2. Run a retrospective where a finding would match a closed template issue
3. Observe the classification for that finding

**Expected result**: Finding is labeled "Contribute upstream candidate" with a note indicating "synced version is unknown". The "Already fixed upstream" classification does not appear.

---

### Step 4: Fix version unknown fallback

**Maps to**: AC "when a finding matches a closed template issue whose fix version cannot be determined, finding is classified as Contribute upstream candidate with a note that the fix version is unknown"

1. Set `template.repository` to a valid repository with `last_synced_version` set
2. Find or simulate a closed issue that has no version tag or release reference in its body/labels
3. Run a retrospective where a finding matches that closed issue
4. Observe the classification

**Expected result**: Finding is labeled "Contribute upstream candidate" with a note indicating "fix version unknown" rather than "Already fixed upstream".

---

### Step 5: Malformed repository reference

**Maps to**: AC "when template repository reference is configured but its value is malformed, retrospective completes with an error and all findings show Template check unavailable"

1. Set `template.repository: "not-a-valid-format"` in `.ai-dev-workflow.yaml`
2. Run a retrospective
3. Observe Step 3b output and Step 4 presentation

**Expected result**:

- Step 3b reports an error (not a warning) about the malformed reference
- All findings show "Template check unavailable" classification
- The retrospective does not fail entirely — it continues to Step 4 and completes

---

### Step 6: Unreachable repository

**Maps to**: AC "when the template repository is unreachable, retrospective completes with a warning and all findings show Template check unavailable"

1. Set `template.repository: "nonexistent-owner-xyz123/nonexistent-repo-xyz123"` in `.ai-dev-workflow.yaml`
2. Run a retrospective
3. Observe Step 3b output

**Expected result**:

- Step 3b reports a warning (not an error) about the unreachable repository
- All findings show "Template check unavailable" classification
- The retrospective does not fail entirely — it continues and completes

---

### Step 7: Sync-template records last-synced version

**Maps to**: AC "after a successful sync-template run, workflow configuration file contains the recorded last-synced template version" and "sync-template git instructions include the workflow configuration file"

1. Run the sync-template skill (`/sync-template` or `.claude/commands/sync-template.md`) against a template source with a known version (e.g., `v0.24.0`)
2. Confirm the sync summary shows `"Recorded last-synced template version: v0.24.0"`
3. Inspect `.ai-dev-workflow.yaml` after the sync step runs

**Expected result**:

- `.ai-dev-workflow.yaml` shows `template.last_synced_version: "v0.24.0"` (or the actual version from the template's CHANGELOG)
- The git instructions printed by Step 5 include `.ai-dev-workflow.yaml` in the `git add` command
- If `template.last_synced_version` already existed with a different value, it was overwritten with the new version

---

### Step 8: Verify `.ai-dev-workflow.yaml` documentation

**Maps to**: AC "workflow configuration file in this template repository documents the template repository reference and recorded last-synced template version with comments"

1. Open `.ai-dev-workflow.yaml` in the repository
2. Locate the `template:` section

**Expected result**:

- The `template:` section exists with both `repository:` and `last_synced_version:` fields
- Each field has a comment explaining its purpose and how it is used

---

### Step 9: BR-4 matching heuristic — exact match, keyword overlap, category match

**Maps to**: AC 12 (exact path match), AC 13 (keyword overlap), AC 14 (shared root-cause category)

Prerequisites: `template.repository` is configured and the test template repo is reachable.

Set up three retrospective findings in the session:

1. **Finding A** (exact path match): a finding whose affected area is an exact file path that also appears verbatim in a template issue's title or body (e.g., `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`)
2. **Finding B** (keyword overlap): a finding that shares 3+ significant keywords with a template issue but no exact path or name match (e.g., both mention "retrospective", "backlog", "cross-reference")
3. **Finding C** (category match): a finding tagged `workflow-process` in a template issue that also describes overlapping workflow symptoms, but without an exact path or keyword overlap threshold

Run Step 3b cross-reference and observe the classification for each.

**Expected result**:

- Finding A classified as "Already in template backlog: template#NNN" (exact match criterion per BR-4, AC 12)
- Finding B classified as "Already in template backlog: template#NNN" or another bucket, depending on open/closed status (keyword overlap criterion per BR-4, AC 13)
- Finding C classified based on category label overlap (shared root-cause category criterion per BR-4, AC 14)
- No finding is left unclassified when a match criterion applies

---

### Last Step: Revert test configuration

- Restore `.ai-dev-workflow.yaml` to its original state (remove or clear the `template:` section if you added it only for testing)

---

## Assertions Checklist

- [ ] When `template.repository` is absent or empty, Step 3b produces no output and the retrospective is identical to pre-feature behavior
- [ ] When `template.repository` is configured and reachable, each finding carries exactly one of the three classification labels before Step 4 presentation
- [ ] Finding matching an open template issue shows "Already in template backlog: template#NNN" with the issue number and suggests Skip or Expand as alternatives to creating a new upstream issue (AC 3)
- [ ] Finding matching a closed issue with a newer fix version shows "Already fixed upstream in vX.Y.Z — you are on vA.B.C; consider syncing instead of contributing"
- [ ] When `last_synced_version` is absent, a would-be "already-fixed" finding falls back to "Contribute upstream candidate" with a note about unknown synced version
- [ ] When fix version cannot be determined, the finding falls back to "Contribute upstream candidate" with a note about unknown fix version
- [ ] When `template.repository` is malformed, Step 3b emits an error and all findings show "Template check unavailable"
- [ ] When `template.repository` is unreachable, Step 3b emits a warning and all findings show "Template check unavailable"
- [ ] After a successful sync-template run, `.ai-dev-workflow.yaml` has `template.last_synced_version` set to the synced version
- [ ] The sync-template git instructions include `.ai-dev-workflow.yaml` in the staged files list
- [ ] `.ai-dev-workflow.yaml` `template:` section has comments explaining both fields
- [ ] A finding whose affected area matches an exact protocol name or file path in a template issue's title or body is classified as "Already in template backlog" (exact match criterion, AC 12)
- [ ] A finding sharing three or more significant keywords with a template issue (no exact match) is classified via keyword overlap criterion (AC 13)
- [ ] A finding sharing the same categorization taxonomy label and overlapping symptoms with a template issue is classified via shared root-cause category criterion (AC 14)

---

## Seed Data Reference

| Entity                | Scenario                                                                                      | How to load |
| --------------------- | --------------------------------------------------------------------------------------------- | ----------- |
| No seed data required | All scenarios are protocol walkthroughs; test template repo is a real GitHub repo you control | N/A         |

---

## Troubleshooting

| Symptom                                                            | Likely cause                                                                 | Fix                                                                   |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `gh issue list --repo owner/repo` returns 0 results                | Wrong repo reference or no issues in test repo                               | Create a test issue in the template repo before running the test      |
| Step 3b does not appear even with `template.repository` configured | Implementation not complete or file not saved                                | Confirm the protocol file was updated and saved                       |
| `last_synced_version` not written after sync                       | Sync-template Step 5 update not implemented or TEMPLATE_VERSION not resolved | Verify the sync-template file was updated per the implementation plan |
| Malformed reference test shows warning instead of error            | Implementation uses wrong severity                                           | Error severity is required for malformed references (BR-9 vs. BR-5)   |

---

## Known Limitations

- The "already-fixed" classification requires a closed template issue to have its fix version determinable from labels or body text; highly informal issue descriptions may produce false "Contribute upstream candidate" results
- This smoke test requires network access to a real GitHub repository; air-gapped environments cannot run Steps 2–7 as written
