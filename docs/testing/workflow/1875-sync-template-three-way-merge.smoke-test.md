# #1875 — Preserve Local Template Patches During Sync

Use isolated temporary Git repositories; do not sync a live consumer for this test.
Use the helper CLI documented in `scripts/README.md` after implementation.

## Preconditions

- A committed template baseline and a newer committed incoming revision.
- A consumer copied from the baseline, with a verified baseline SHA.
- A selected regular text file and relative skill alias; private preview scratch.

## Steps

1. Edit separate lines in the consumer and incoming template. Preview: expect a
   clean merge named under **Locally modified template files**, with reconciled
   category counts. Approve the existing sync mode and apply the preview.
   Verify both edits remain and the ledger references the incoming template,
   without storing the merged consumer content as its baseline.
2. Commit a further independent upstream edit and repeat. Verify the first local
   edit survives and the prior incoming revision supplies the per-path base.
3. Change the same line on both sides. Preview: expect a named conflict and a
   non-success apply result. Verify all selected files and prior ledger bytes
   remain unchanged; no consumer conflict markers appear.
4. Remove baseline evidence in a separate legacy fixture. Differing existing and
   uncertain missing paths must show baseline unavailable and block the batch.
   Supply a verified bootstrap SHA, re-preview and confirm preservation resumes.
5. Decline a path explicitly, re-preview the approved remainder and apply.
   Confirm the declined path and its baseline are unchanged. Change a consumer
   file after a preview: stale apply must stop before writes and require approval
   of a fresh preview.
6. Keep upstream unchanged while deleting a consumer file. Verify deletion is
   reported and retained; an upstream modification of that path must conflict.
   Confirm a consumer-only file and nested project-owned retro metrics are kept.
7. Include relative skill aliases and executable files. Confirm aliases resolve
   inside the final consumer tree, executable-bit changes follow three-way
   decisions, and a link escape blocks before writes. Untracked source files
   must never appear in the selected committed batch.
8. Run the automated rollback case and affected sync suites. Confirm a failed
   write/validation restores original content/modes/links and ledger. Inspect
   canonical, Cursor and Codex instructions for the same preview/apply behavior,
   existing approvals and PR/CI gates. Do not invoke Claude.

## Evidence

Record actual helper dispositions, before/after fingerprints, commit provenance
and suite results in the implementation PR. No supplied design assets exist, so
there is no expected-vs-actual visual fidelity step.
