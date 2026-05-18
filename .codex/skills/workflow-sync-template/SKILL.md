---
name: workflow-sync-template
description: Sync framework updates from the upstream template into this downstream project. Reads sync-manifest.yaml from the upstream template for the authoritative file list; falls back to the embedded list when the manifest is absent. Use when a downstream project needs to pull in the latest framework files from the template.
---

# Workflow Sync Template

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.claude/commands/sync-template.md` (the canonical sync-template protocol).
3. Follow that protocol exactly, starting from Step 0.
   3a. After Step 0 (template source resolved), run Step 0.5 — the comprehensive pre-flight diagnostic. This step surfaces all foreseeable conflict categories (file-level conflicts, CI configuration issues, CHANGELOG structure issues, protocol file incompatibilities) in a single pass before any files are modified. If `--dry-run` was passed, stop after printing the diagnostic report and do not proceed to Step 1. The diagnostic report format is defined in the protocol's Step 0.5 section.
4. Apply the same manifest-driven procedure as the Claude Code and Cursor sync-template artefacts:
   - Check for `sync-manifest.yaml` at the template root after resolving the template source.
   - If found, use `categories.always_sync`, `categories.special_handling`, and `categories.project_specific` from the manifest.
   - If found and `rename_detections` is present, apply the rename cleanup detection defined in the protocol's "Rename cleanup detection" section (Step 2) and display the "Rename cleanup" section in Step 3 when candidates are found.
   - If absent, fall back to the embedded file list in the protocol and display the warning message.
   - For mixed-content files (`mixed_content: true`, `annotation_scheme: html_comments`), apply the extraction logic defined in the protocol's "Mixed-content extraction logic" section.
5. Present the structured sync summary (always-sync counts, new/modified/up-to-date breakdown) before asking for confirmation. The confirmation prompt offers two options — "apply all" and "apply always-sync only" — as defined in the protocol Step 3 confirmation block. "apply all" means always-sync files are applied in one batch, then every manual-review and optional-additive item is walked through inline (present diff, state recommendation, ask confirm/skip). Special-handling paths are never included in "apply all".
6. Do not apply any changes until the user explicitly confirms. When the user answers "apply all", apply the always-sync batch first, then walk through manual-review and optional-additive items one at a time per Step 4.
7. After applying template changes and before generating git instructions, record `TEMPLATE_VERSION` to `.ai-dev-workflow.yaml` under `template.last_synced_version` per the canonical sync-template protocol Step 5. Include `.ai-dev-workflow.yaml` in the `git add` instructions shown to the user.
