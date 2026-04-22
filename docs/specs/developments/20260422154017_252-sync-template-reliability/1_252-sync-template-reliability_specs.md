# Sync-Template Reliability — Spec

**Depends on**: 251-rename-docs-ai-to-workflow (merged)

---

## Overview

Downstream repositories that adopt this template must periodically pull in
framework updates (new agents, revised protocols, updated scripts). The current
sync-template command/skill relies on the AI agent reading and interpreting an
inline file list at runtime, and provides no systematic way to handle files that
intentionally mix template-owned content with project-owned content. As a result,
syncs are incomplete or inconsistent across runs and tools.

This feature introduces a machine-readable manifest that becomes the single
authoritative source for which files must be synced, and defines a structured
approach for mixed-content files so the agent can always determine which sections
belong to the template and which belong to the project.

---

## Use Cases

### Use Case 1: Downstream maintainer runs a full sync

**Actor**: Developer (maintainer of a downstream repo that was created from this
template)
**Preconditions**: The maintainer has a downstream repo on a clean integration
branch. A newer version of the upstream template exists.

**Steps**:
1. The maintainer invokes the sync-template command (e.g., `/sync-template`,
   `workflow-sync-template` skill, or equivalent).
2. The command reads the sync manifest from the upstream template.
3. The command compares the files listed in the manifest against the downstream
   repo.
4. The command presents a structured diff summary categorised by sync category
   (always-sync, special handling, project-specific additive).
5. The maintainer approves the changes to apply.
6. The command applies only the approved changes.

**Postconditions**:
- Every file listed as "always-sync" in the manifest is either added or updated
  in the downstream repo to match the upstream template version.
- Project-specific files are never overwritten without explicit approval.
- The maintainer can confirm that no always-sync file was silently skipped.

**Information shown**:
- Number and list of files to be added, updated, unchanged, and requiring manual
  review, grouped by manifest category.
- For mixed-content files: which template-owned sections changed and which
  project-owned sections are preserved.

**Actions available**:
- Approve the always-sync batch.
- Approve or skip individual special-handling files.
- Accept or decline individual additive suggestions for project-specific files.

**Considerations**:
- If the manifest does not exist in the upstream template, the command falls back
  to its current embedded file list and warns the maintainer.
- Files present in the downstream repo but absent from the manifest are never
  deleted.

---

### Use Case 2: Template author adds a new file to the framework

**Actor**: Template author (developer working directly in the upstream template
repo)
**Preconditions**: The template author has created a new file that downstream
repos must receive on their next sync.

**Steps**:
1. The template author adds the new file to the appropriate location.
2. The template author adds a corresponding entry to the sync manifest, specifying
   the file path and its sync category (always-sync, special-handling, or
   project-specific).
3. The template author commits the file and the manifest update together.

**Postconditions**:
- The new file entry appears in the manifest.
- On the next downstream sync, the file is automatically detected and categorised
  correctly.

**Information shown**:
- No output at this stage; the change is captured in the manifest file itself.

**Actions available**:
- Choose the sync category for the new file.
- Add a note to the manifest entry explaining the file's purpose (optional).

**Considerations**:
- If the template author forgets to update the manifest, the new file will not be
  included in future always-sync batches (it will only be discovered if the
  downstream already has the file listed in the manifest).

---

### Use Case 3: Downstream maintainer syncs a mixed-content file

**Actor**: Developer (maintainer of a downstream repo)
**Preconditions**: The upstream template has updated the template-owned sections
of a mixed-content file (e.g., `AGENTS.md` workflow table, `.ai-dev-workflow.yaml`
schema description). The downstream project has already filled in its own
project-specific sections.

**Steps**:
1. The maintainer invokes the sync-template command.
2. The command identifies the file as mixed-content in the manifest.
3. The command shows which template-owned sections differ from the upstream.
4. The command shows that the project-owned sections are unchanged and will be
   preserved.
5. The maintainer approves the update to the template-owned sections.
6. The command merges the template update into the file, leaving project-owned
   sections intact.

**Postconditions**:
- The file reflects the latest template-owned content.
- Project-specific content (e.g., filled-in TODO sections) is preserved verbatim.

**Information shown**:
- A diff limited to the template-owned sections of the file.
- A confirmation that project-owned sections were detected and will not change.

**Actions available**:
- Approve or decline the merge for the template-owned sections.

**Considerations**:
- If the template-owned section markers are missing or malformed in the downstream
  file, the command treats the file as unstructured and falls back to showing a
  full diff and asking the maintainer to decide.

---

## Business Rules

- **BR-1 Manifest is authoritative**: The sync manifest is the single source of
  truth for which files belong to each sync category. The agent must read the
  manifest; it must not rely solely on an internally embedded file list that may
  drift out of sync with the actual template contents.
- **BR-2 Always-sync files are non-negotiable for addition/update**: Files
  categorised as always-sync in the manifest must be surfaced to the maintainer as
  requiring an update; the maintainer may choose to skip individual files but the
  agent must not silently omit them.
- **BR-3 Project-owned content is never overwritten**: For mixed-content files,
  any section not annotated as template-owned must be preserved exactly as-is.
- **BR-4 Graceful fallback when manifest is absent**: If the upstream template
  does not yet contain a manifest, the command falls back to its existing embedded
  file list and displays a visible warning that manifest-driven sync is not
  available.
- **BR-5 Manifest is multi-tool compatible**: The manifest format and any
  mixed-content annotation scheme must be readable by all supported AI tools
  (Claude Code, Cursor, Codex) without tool-specific parsing logic. Human
  readability is also required — a developer must be able to review the manifest
  in a standard text editor or GitHub diff view.
- **BR-6 Manifest and mixed-content annotations ship together**: A manifest entry
  for a mixed-content file must reference the annotation scheme used in that file,
  so both artefacts are updated together when the file changes sync category.
- **BR-7 No silent skips**: After a sync run completes, the command must be able
  to confirm (or produce a report stating) that no always-sync file was omitted due
  to interpretation differences between runs or tools.

---

## UX Rules

- The sync-template command output must show a count of files in each category
  before asking for confirmation, so the maintainer can quickly detect an
  unexpectedly small "always-sync" list that might signal a stale manifest.
- When a mixed-content file is encountered and annotation markers are present, the
  diff shown to the maintainer must be limited to the template-owned sections only;
  project-owned sections must be explicitly labelled as "preserved — no change".
- When annotation markers are absent or malformed in a mixed-content file, the
  command must clearly flag the file as "unstructured — full review required"
  rather than attempting an automatic merge.
- The sync summary must distinguish between files that were skipped because they
  are up-to-date versus files that were explicitly declined by the maintainer.

---

## Acceptance Criteria

- [ ] AC-1: Running the sync-template command on a downstream repo that has an
  older version of always-sync files causes every out-of-date always-sync file to
  appear in the "will be updated" section of the summary. No always-sync file that
  differs from the upstream template is silently absent from the summary.
- [ ] AC-2: Running the sync-template command on two different tools (e.g., Claude
  Code and Cursor) with the same upstream template version produces the same set of
  always-sync files listed in the summary. (Verified by comparing the two summaries
  — the always-sync file list must be identical.)
- [ ] AC-3: When the upstream template updates a template-owned section of a
  mixed-content file (e.g., updates the workflow table in `AGENTS.md`), the
  sync-template command shows only the changed template-owned section in the diff
  and confirms that project-owned sections are preserved.
- [ ] AC-4: When the sync manifest is absent from the upstream template, the
  sync-template command completes with a warning message (not an error) and falls
  back to the embedded file list for that run.
- [ ] AC-5: After a sync run, the maintainer can verify completeness: the sync
  summary explicitly lists every file from the always-sync manifest category and
  shows its disposition (updated, up-to-date, or skipped by maintainer).
- [ ] AC-6: A new file added to the template by a template author, with a
  corresponding manifest entry, is detected and listed as "to be added" on the
  next sync run against a downstream repo that does not yet have that file.
- [ ] AC-7: The sync manifest file can be opened and reviewed in a standard text
  editor or GitHub diff view without requiring any special tool support.

---

## Out of Scope (MVP)

- Automated conflict resolution or three-way merge for mixed-content files; the
  MVP approach is annotation-guided extraction and presentation, with the
  maintainer approving each merge.
- Version-pinning or rollback of individual manifest-tracked files to a specific
  upstream version.
- CI-enforced validation that the manifest is complete (i.e., no template file
  exists outside the manifest). This may be addressed in a follow-on item.
- Support for syncing from multiple upstream templates simultaneously.
- An interactive TUI or web UI for the sync workflow; the command-line / AI-agent
  interface is the only supported mode in this iteration.
- Automatic detection of when the template-owned section markers are missing from
  a mixed-content file in the upstream template itself (authoring-time lint).
  This is a template-author tooling concern outside the scope of the sync command.
