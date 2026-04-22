# Smoke Test Runbook: Sync-Template Reliability (#252)

**Feature**: Sync-Template Reliability — manifest-driven sync with mixed-content support
**Spec**: `docs/specs/developments/20260422154017_252-sync-template-reliability/1_252-sync-template-reliability_specs.md`
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You have a downstream test repository (can be a temporary clone of this template or a separate downstream project)
- [ ] The upstream template has `sync-manifest.yaml` at its root (from this implementation)
- [ ] You have at least two AI tools available to test AC-2 (e.g., Claude Code and Cursor)
- [ ] The downstream test repo has an older version of at least one always-sync file (to verify AC-1)
- [ ] The downstream test repo has `AGENTS.md` and `.ai-dev-workflow.yaml` with project-specific content already filled in (for Use Case 3 / AC-3 verification)

---

## Test Data

| Item | Value |
|---|---|
| Upstream template path | local copy of `ai-dev-framework-template` (post-implementation) |
| Downstream test repo | temporary clone with older always-sync files |
| Mixed-content file | `AGENTS.md` with a filled-in `## Project Overview` section and the workflow table at the template version |
| Mixed-content file 2 | `.ai-dev-workflow.yaml` with `provider: github` set (project-specific), schema comments from template |

---

## Smoke Test Steps

### Step 1: Verify manifest exists and is human-readable (AC-7)

1. Open `sync-manifest.yaml` at the root of the upstream template in a text editor (or view it on GitHub).
2. Verify the file is valid YAML, readable without any special tooling, and lists files under `always_sync`, `special_handling`, and `project_specific` categories.

**Expected result**: The manifest opens and is readable in a standard text editor. The categories and paths are clear. No binary content or encoded data.

---

### Step 2: Full sync with manifest present — always-sync coverage (AC-1, AC-5)

**Maps to**: AC-1, AC-5, BR-1, BR-2, BR-7, Use Case 1

1. In the downstream test repo (with at least one outdated always-sync file), invoke the sync-template command:
   - Claude Code: `/sync-template --local=/path/to/upstream-template`
   - Cursor: `/sync-template --local=/path/to/upstream-template`
2. Before confirming any changes, read the sync summary.

**Expected result**:
- The summary shows a count of files per category (always-sync, special-handling, project-specific) before asking for confirmation.
- Every always-sync file that differs from the upstream appears in the "will be updated" section — no always-sync file with a diff is silently absent.
- The summary includes a disposition row for every always-sync manifest entry: "updated", "up-to-date", or "skipped by maintainer".

---

### Step 3: No silent skips after sync (AC-5, BR-7)

**Maps to**: AC-5, BR-7

1. After the sync run from Step 2 completes (whether or not changes were applied), inspect the final summary.

**Expected result**:
- The summary explicitly lists every always-sync file from the manifest and its disposition (updated, up-to-date, or skipped by maintainer).
- The count of files in each disposition bucket is shown.
- "Skipped because up-to-date" and "declined by maintainer" appear as separate counts (not merged into one bucket).

---

### Step 4: Cross-tool consistency (AC-2)

**Maps to**: AC-2, BR-5

1. Using the same upstream template and downstream repo state (before applying any changes), run the sync-template command in Claude Code and record the always-sync file list from the summary.
2. Run the same command in Cursor and record the always-sync file list.
3. Compare the two lists.

**Expected result**: The always-sync file list is identical between both tools. No file appears in one tool's summary but not the other's.

---

### Step 5: Mixed-content file sync with annotation markers (AC-3, Use Case 3)

**Maps to**: AC-3, BR-3, BR-6, UX Rule 2, Use Case 3

1. In the downstream test repo, ensure `AGENTS.md` has:
   - `## Project Overview` filled in with fake project content (project-owned)
   - The workflow table section at an older template version (template-owned, differs from upstream)
2. Run the sync-template command.
3. When the `AGENTS.md` entry appears in the summary, inspect the diff shown.

**Expected result**:
- The diff shown for `AGENTS.md` is limited to the template-owned section (workflow table) only.
- The `## Project Overview` section is labelled "preserved — no change" in the summary.
- No project-specific content is shown in the diff or modified after applying the sync.

---

### Step 6: Mixed-content file with missing annotation markers (UX Rule 3)

**Maps to**: BR-3, UX Rule 3

1. In the downstream test repo, modify `AGENTS.md` to remove the `<!-- TEMPLATE-OWNED-START -->` and `<!-- TEMPLATE-OWNED-END -->` markers (simulating a downstream repo that hasn't added them yet).
2. Run the sync-template command.
3. Observe how `AGENTS.md` is handled in the summary.

**Expected result**:
- The file is flagged as "unstructured — full review required" in the summary.
- The command does NOT attempt an automatic merge.
- A full diff is shown instead.

---

### Step 7: Graceful fallback when manifest is absent (AC-4)

**Maps to**: AC-4, BR-4

1. Temporarily rename or remove `sync-manifest.yaml` from the upstream template source (or point `--local` to a directory without the manifest).
2. Run the sync-template command.

**Expected result**:
- The command completes without an error (only a warning).
- A visible warning message is shown: something indicating that the manifest was not found and the embedded file list is being used.
- The sync still proceeds with the embedded file list.
- The exit code is 0 (success with warning), not an error exit.

---

### Step 8: New file in manifest is detected (AC-6)

**Maps to**: AC-6, BR-1, Use Case 2

1. In the upstream template, add a new dummy file (e.g., `docs/workflow/test-new-file.md`) with the corresponding entry in `sync-manifest.yaml` under `always_sync`.
2. In the downstream test repo (which does not have this file), run the sync-template command.

**Expected result**:
- The new file appears in the "will be added" section of the summary.
- After approval, the file is added to the downstream repo.

---

### Step 9: Codex skill invocation (workflow-sync-template)

**Maps to**: BR-5, AGENTS.md Workflow Commands table

1. In a Codex-enabled environment, invoke the `workflow-sync-template` skill with the same `--local` argument.
2. Verify the skill produces the same summary structure as the Claude Code command.

**Expected result**:
- The skill runs without error.
- The sync summary structure and always-sync file list matches the Claude Code output.

---

### Last Step: Validate and clean up

- Verify all assertions in the checklist below are met.
- Remove any temporary files added for Step 8 testing.
- Revert the `AGENTS.md` marker removal from Step 6.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Every out-of-date always-sync file appears in the "will be updated" section — no silent omission.
- [ ] AC-2: Running on Claude Code and Cursor with the same upstream produces identical always-sync file lists.
- [ ] AC-3: Mixed-content file diff shows only the template-owned section; project-owned sections are labelled "preserved — no change".
- [ ] AC-4: When the manifest is absent, the command completes with a warning and falls back to the embedded list.
- [ ] AC-5: The sync summary explicitly shows the disposition of every always-sync manifest entry (updated / up-to-date / skipped by maintainer) with separate counts.
- [ ] AC-6: A new always-sync file with a manifest entry is detected as "to be added" against a downstream that lacks it.
- [ ] AC-7: `sync-manifest.yaml` is readable in a standard text editor or GitHub diff view without special tooling.

---

## Seed Data Reference

| Entity | Scenario | How to load |
|---|---|---|
| Downstream test repo | Older always-sync files, `AGENTS.md` with project content | Manual: clone template at a prior commit and add project-specific content to `AGENTS.md` |
| Upstream template | Post-implementation with `sync-manifest.yaml` and annotation markers | This repository after implementing #252 |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Manifest not found even though file exists | Wrong path passed to `--local` | Verify the path points to the upstream template root, not a subdirectory |
| Mixed-content diff shows entire file | Annotation markers not added to upstream AGENTS.md | Re-run Step 2 of the implementation order to add markers |
| Cross-tool list differs (AC-2 fails) | One sync artefact still has the old hard-coded list | Re-check that all three sync artefacts were updated in implementation step 4-6 |
| Fallback warning not shown (AC-4) | Manifest fallback logic not implemented in the artefact under test | Verify implementation step 4 includes the graceful fallback branch |

---

## Known Limitations

- AC-2 (cross-tool consistency) requires manual comparison of summaries from two separate tool invocations. No automated test for this.
- Step 9 (Codex skill) requires a Codex-enabled environment; skip if unavailable and note the skip.
