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
   - Resolve the current repository role from `.ai-dev-workflow.yaml` (`single_repo` when missing).
   - If found, run `scripts/development-workflow/select-sync-manifest-entries.py` from the template source and use only the selected `categories.always_sync`, `categories.special_handling`, and `categories.project_specific` entries for the resolved role.
   - Report skipped entries by `mode_scope` in dry-run and apply summaries.
   - Reuse the same selected entry set for dry-run comparison and apply; do not rebuild the file list independently.
   - If found and `rename_detections` is present, apply the rename cleanup detection defined in the protocol's "Rename cleanup detection" section (Step 2) and display the "Rename cleanup" section in Step 3 when candidates are found.
   - If absent, fall back to the embedded file list in the protocol and display the warning message.
   - For mixed-content files (`mixed_content: true`, `annotation_scheme: html_comments`), apply the extraction logic defined in the protocol's "Mixed-content extraction logic" section.
5. Present the structured sync summary (always-sync counts, optional additive / discretionary items, escalation hard-stops, rename cleanup) before asking for confirmation. The primary confirmation offers **"Decide with me"** and **"Accept recommendations"** as defined in the protocol Step 3 confirmation block. Do not present `"apply all"` / `"apply always-sync only"` as the primary peer pair. Hard-stop items (special-handling, rename cleanup, placeholder-guard) escalate and require explicit naming. `"always-sync only"` remains only as a demoted advanced/escape hatch.
6. Do not apply any changes until the user explicitly confirms a primary mode (and, for Accept recommendations, the disposition plan). For Decide with me: apply always-sync, then walk discretionary items with recommendation + yes/skip. For Accept recommendations: show the planned disposition table, obtain one confirmation, apply recommended dispositions, and print the disposition log. Hard stops are never auto-applied.
7. After applying template changes, execute Step 5 of the canonical sync-template protocol: record `TEMPLATE_VERSION` to `.ai-dev-workflow.yaml` under `template.last_synced_version`, create the sync branch, stage approved paths, commit, push, and open a draft PR with `gh pr create` — do not print git instructions for the user to run manually.
8. After the PR is open, execute Step 6 of the canonical sync-template protocol: run the internal review gate (Step 7a per `.ai-dev-workflow.yaml` `review.on_draft.runner`), convert the PR to non-draft once draft reviewers approve, run the automated reviewer loop (`pr-review-loop.sh`), apply `ready-for-regression` and `ready-for-human-review` labels, and print the PR URL. Oversized sync PRs may receive Haystack's authoritative `analysis_skipped_file_limit` outcome by design, but that skip is permissive only for Haystack: other configured reviewers, CI, unresolved-thread, regression, and readiness gates remain mandatory. Do not stop after opening the PR — continue until the PR is labeled `ready-for-human-review` or an escalation condition is reached. Before reporting the PR terminal, include Protocol 91's `Ground-Truth Completion Verification` output from `item-completion-self-check.sh`, passing `--require-review-summary true` and `--require-review-threads true` when Step 7 was configured (helper defaults are false).
