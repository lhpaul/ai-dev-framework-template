# Sync-Template Reliability — Implementation Plan

**Spec**: `docs/specs/developments/20260422154017_252-sync-template-reliability/1_252-sync-template-reliability_specs.md`
**Smoke test runbook**: `docs/testing/workflow/252-sync-template-reliability.smoke-test.md`

---

## Summary

**Approach**: Introduce a YAML manifest file (`sync-manifest.yaml`) at the repository root that declares every framework-managed file and its sync category (always-sync, special-handling, project-specific). Update all three sync-template artefacts (`.claude/commands/sync-template.md`, `.claude/skills/sync-template.md`, `.cursor/commands/sync-template.md`) to read and consume the manifest at runtime instead of relying on the inline hard-coded file list. For mixed-content files, define a comment-based annotation scheme (`<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->`) and document it in the manifest entry so both artefacts are kept in sync. Add a Codex skill (`workflow-sync-template`) thin-wrapper that delegates to the same manifest-driven procedure.

**Estimated complexity**: M

**Rationale**: The changes are confined to documentation-format files (`.md`, `.yaml`) and one new YAML manifest. No compiled code, no migrations, no service dependencies. The manifest schema and annotation markers are straightforward. Verification against all three sync artefacts and the Codex skill adds breadth but no new complexity per file. Two to three days of focused work covers manifest design, artefact updates, smoke-test authoring, and CHANGELOG.

**Dependencies**: #251 (rename docs/ai to docs/workflow) — merged per spec.

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `284b8b4` |
| Sync artefact locations | `find . -path "./.claude/worktrees" -prune -o -name "sync-template.md" -print` | `./.claude/commands/sync-template.md`, `./.claude/skills/sync-template.md`, `./.cursor/commands/sync-template.md` |
| Codex sync skill present? | `find .codex/skills -name "*sync*"` | empty — no existing Codex sync skill |
| Inline always-sync list exists? | `grep -c "Always sync" .claude/commands/sync-template.md` | 1 (confirmed: hard-coded list in all three artefacts) |
| docs/testing/workflow/ existing runbooks | `ls docs/testing/workflow/` | 24 files — naming pattern confirmed as `<issue-id>-<slug>.smoke-test.md` |
| AGENTS.md sync-related mention | `grep -n "sync" AGENTS.md` | Line 92: `/sync-template` command in Maintenance Commands table; Codex column is `—` (skill to be added by this plan) |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Create `sync-manifest.yaml` at the repository root. Schema:
  ```yaml
  # Illustrative — adapt during implementation
  schema_version: 1
  categories:
    always_sync:
      - path: REVIEW.md
        note: canonical review contract
      - path: docs/workflow/
        glob: "**/*"
        note: full workflow tree
      - path: .claude/agents/
        glob: "*.md"
      - path: .claude/commands/
        glob: "*.md"
      - path: .claude/skills/
        glob: "*.md"
      - path: .codex/skills/
        glob: "**/*"
      - path: .cursor/commands/
        glob: "*.md"
      - path: .cursor/agents/
        glob: "*.md"
      - path: .cursor/rules/
        glob: "*.mdc"
      - path: scripts/development-workflow/
        glob: "**/*"
      - path: scripts/README.md
      - path: docs/best-practices/1-general.md
      - path: docs/best-practices/2-version-control.md
      - path: docs/best-practices/3-testing.md
    special_handling:
      - path: .claude/settings.json
        note: may have project-specific permissions
      - path: .claude/settings.local.json.example
      - path: .github/workflows/auto-tag-release.yml
        note: automated release tagging
      - path: .github/workflows/deploy.yml
        note: placeholder deployment workflow
      - path: .github/workflows/e2e-regression.yml
        note: label-gated e2e/regression placeholder
      - path: e2e/
        glob: "**/*"
        note: placeholder e2e test project
    project_specific:
      - path: AGENTS.md
        mixed_content: true
        annotation_scheme: html_comments
        note: workflow table is template-owned; project fills TODO sections
      - path: README.md
      - path: CHANGELOG.md
      - path: .ai-dev-workflow.yaml
        mixed_content: true
        annotation_scheme: html_comments
        note: schema description is template-owned; provider selections are project-owned
      - path: docs/project/
        glob: "**/*"
      - path: docs/best-practices/STACK-SPECIFIC.md
      - path: docs/best-practices/stack/
        glob: "**/*"
      - path: .gitignore
      - path: CLAUDE.md
      - path: GEMINI.md
  ```
  The manifest is the single authoritative source of truth per BR-1. It must be human-readable per AC-7 and BR-5.

- [ ] Define the HTML-comment annotation scheme for mixed-content files. Canonical marker format (unlabeled — same syntax used in all references throughout this plan):
  - Block: `<!-- TEMPLATE-OWNED-START -->` ... `<!-- TEMPLATE-OWNED-END -->`
  - Inline: `<!-- TEMPLATE-OWNED -->` (single-line sections where a block is not needed)

  These markers work in all three AI tools (Claude Code, Cursor, Codex) because they parse Markdown and YAML files as text, and HTML comments are valid in both. Human-readable in editors and GitHub diff view (AC-7, BR-5).

- [ ] Add `<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->` markers to the workflow table section of `AGENTS.md`. The table between the `## Development Workflow` heading and the `### Codex Skills` heading is template-owned. Project fills in the `## Project Overview` and `## Repository Structure` sections.

- [ ] Add similar markers around the `review:` / `issue_tracker:` / `vcs:` / `browser_automation:` schema documentation block in `.ai-dev-workflow.yaml` (comment block at the top of each section heading). Note: the `platforms:` and `providers:` values under each section are project-specific.

### Shared Packages / Libraries (Sync Artefacts)

All three sync-template artefacts must be updated to consume `sync-manifest.yaml`. Changes are parallel across all three files.

**`.claude/commands/sync-template.md`**:

- [ ] **Step 0**: After resolving the template source, also check for `sync-manifest.yaml` at the template root. If found, read it and store as `SYNC_MANIFEST`. If absent, set `SYNC_MANIFEST=absent` (graceful fallback per BR-4 / AC-4).
- [ ] **Step 2 — Always sync**: Replace the hard-coded path list with: "If `SYNC_MANIFEST` is loaded, read `categories.always_sync` from the manifest and enumerate those paths from the template. If `SYNC_MANIFEST=absent`, fall back to the embedded list below and display the warning: `Warning: sync manifest not found in upstream template. Using embedded file list — results may be incomplete.`" Keep the embedded list as the fallback.
- [ ] **Step 2 — Special handling**: Same pattern — read `categories.special_handling` from manifest when available, fall back to embedded list.
- [ ] **Step 2 — Project-specific**: Same pattern — read `categories.project_specific` from manifest. For entries with `mixed_content: true`, additionally read the `annotation_scheme` field and apply the mixed-content extraction logic described below.
- [ ] **Mixed-content extraction logic** (new subsection in Step 2): When a file has `mixed_content: true` and `annotation_scheme: html_comments`, extract only the template-owned sections (delimited by `<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->`) when comparing to the upstream. Show only those sections in the diff. Label unextracted sections as "preserved — no change" (UX Rule 2). If markers are absent or malformed in the downstream copy, flag the file as "unstructured — full review required" (UX Rule 3).
- [ ] **Step 3 — Summary format**: Update the summary to show file counts per category before asking for confirmation (UX Rule 1 / AC-5). Add a new section: "Files skipped (up-to-date): N" and "Files declined by maintainer: N" to satisfy AC-5 and UX Rule 4. The disposition of every always-sync file (updated, up-to-date, skipped by maintainer) must appear in the summary.
- [ ] **Step 5 — Git instructions**: Update the `git add` staging instruction to reference `sync-manifest.yaml` in addition to the always-sync paths. Add a note: "If sync-manifest.yaml was updated, stage it as well."

**`.claude/skills/sync-template.md`**:

- [ ] Apply all the same changes as `.claude/commands/sync-template.md` above (skills and commands share the same protocol text; they must stay in sync).

**`.cursor/commands/sync-template.md`**:

- [ ] Apply all the same changes as `.claude/commands/sync-template.md` above.

**New: `.codex/skills/workflow-sync-template/SKILL.md`**:

- [ ] Create the directory `.codex/skills/workflow-sync-template/`.
- [ ] Create `SKILL.md` as a thin wrapper that loads `.claude/commands/sync-template.md` and delegates to the same manifest-driven procedure. Follow the existing Codex skill pattern (see `.codex/skills/workflow-plan-writer/SKILL.md` for structure).
- [ ] Register the skill in AGENTS.md under the Workflow Commands table row for `Sync framework updates`.

---

## Testing Strategy

**Test types**: Smoke / Manual

This feature affects documentation-format artefacts (Markdown, YAML). There is no executable code to unit-test. Verification is via manual smoke test against the sync command in a downstream repo or against a test project.

**Key scenarios to test**:

1. Full sync with manifest present — all always-sync files appear in summary with correct disposition (AC-1, AC-2, AC-5)
2. Sync on two tools with same upstream → same always-sync file list (AC-2)
3. Mixed-content file with annotation markers — only template-owned diff shown, project sections preserved (AC-3, Use Case 3)
4. Manifest absent → warning shown, fallback to embedded list, command completes (AC-4, BR-4)
5. New file added to manifest → "to be added" on next sync against downstream without that file (AC-6)
6. Manifest file opens in editor/GitHub without special tooling (AC-7)

**Smoke test runbook**: `docs/testing/workflow/252-sync-template-reliability.smoke-test.md`

**Regression suite**: No automated regression suite exists in this repository. Smoke test runbook is the verification record.

---

## Seed Data

| Entity | Values / Scenario | File |
|---|---|---|
| N/A | This feature has no runtime data dependencies | — |

---

## Documentation Updates

- [ ] `AGENTS.md` — Two updates after implementation: (1) Add `workflow-sync-template` to the Codex column of the Maintenance Commands table row for "Sync framework updates from template" (currently `—`); (2) if the Workflow Commands table also has a sync-template entry for Codex, update that column as well.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Manifest drift: developer adds a new template file but forgets to update `sync-manifest.yaml` | Med | Med | The spec explicitly notes this as a known limitation (Out of Scope: CI-enforced manifest completeness). Document in the manifest's header comment. |
| HTML comment markers not preserved in some Markdown editors | Low | Low | Markers are valid HTML comments, invisible in rendered Markdown. All major editors preserve them verbatim. |
| Three sync artefacts diverging from each other | Med | Med | Plan explicitly requires identical changes in all three files. Plan reviewer and code reviewer should cross-check. |
| Codex skill referencing stale embedded list if manifest not present | Low | Low | The fallback logic in the skill is the same as in the command — only activates when manifest is absent. |

---

## Implementation Order

1. Create `sync-manifest.yaml` at the repository root (full path list from the always-sync embedded lists; add mixed-content annotations for `AGENTS.md` and `.ai-dev-workflow.yaml`).
2. Add `<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->` markers to the workflow table section in `AGENTS.md`.
3. Add annotation markers to the schema description block in `.ai-dev-workflow.yaml` (comment blocks above `review:`, `issue_tracker:`, `vcs:`, `browser_automation:` section headings).
4. Update `.claude/commands/sync-template.md` — Steps 0, 2, 3, and 5 as described in Layer-by-Layer Changes above.
5. Update `.claude/skills/sync-template.md` with the same changes as step 4 (skills mirror commands).
6. Update `.cursor/commands/sync-template.md` with the same changes as step 4.
7. Create `.codex/skills/workflow-sync-template/SKILL.md` thin wrapper.
8. Update project docs per **Documentation Updates** section above (`AGENTS.md` Workflow Commands table, `docs/workflow/development-workflow/README.md` Maintenance Commands table).
9. Verify smoke test runbook (`docs/testing/workflow/252-sync-template-reliability.smoke-test.md`).
10. Update `CHANGELOG.md` under `[Unreleased]`:
    ```
    - **Sync-template manifest-driven reliability** (#252): Introduce `sync-manifest.yaml` as the authoritative file list for sync-template; add HTML-comment annotation markers for mixed-content files; update all sync-template artefacts (Claude Code, Cursor, Codex) to consume the manifest; add graceful fallback when manifest is absent.
    ```
