---
name: workflow-sync-template
description: Sync framework updates from the upstream template into this downstream project. Reads sync-manifest.yaml from the upstream template for the authoritative file list; falls back to the embedded list when the manifest is absent. Use when a downstream project needs to pull in the latest framework files from the template.
---

# Workflow Sync Template

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules.
2. Read `.claude/commands/sync-template.md` (the canonical sync-template protocol).
3. Follow that protocol exactly, starting from Step 0.
4. Apply the same manifest-driven procedure as the Claude Code and Cursor sync-template artefacts:
   - Check for `sync-manifest.yaml` at the template root after resolving the template source.
   - If found, use `categories.always_sync`, `categories.special_handling`, and `categories.project_specific` from the manifest.
   - If absent, fall back to the embedded file list in the protocol and display the warning message.
   - For mixed-content files (`mixed_content: true`, `annotation_scheme: html_comments`), apply the extraction logic defined in the protocol's "Mixed-content extraction logic" section.
5. Present the structured sync summary (always-sync counts, new/modified/up-to-date breakdown) before asking for confirmation.
6. Do not apply any changes until the user explicitly confirms.
7. After applying template changes and before generating git instructions, record `TEMPLATE_VERSION` to `.ai-dev-workflow.yaml` under `template.last_synced_version` per the canonical sync-template protocol Step 5. Include `.ai-dev-workflow.yaml` in the `git add` instructions shown to the user.
