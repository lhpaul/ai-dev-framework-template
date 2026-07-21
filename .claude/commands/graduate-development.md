---
description: Graduate a completed integration branch (develop-<slug>) to develop. Opens the graduation PR after confirming all sub-items are merged and getting human approval. Usage: /graduate-development <slug>
---

# Claude Code Command: Graduate Development

Follow the graduation protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`

Key responsibilities:

- Accept `<slug>` as the integration branch identifier (e.g., `/graduate-development claude-review-platform`)
- Run Step 0: surface all sub-items with their merged PRs and wait for explicit human approval before taking any action
- Verify all planned sub-items are merged to `develop-<slug>` (Step 2)
- Check CHANGELOG handling (Step 2.5)
- Open the graduation PR from `develop-<slug>` to `develop` using a merge-commit strategy (Step 3)
- Run the automated reviewer loop and apply `ready-for-human-review` (Step 4); do NOT apply `ready-for-regression`
- After human merges: delete the remote/local integration branch, run
  `graduation-closeout.sh` (Step 5 primary closeout), reconcile delivered
  sub-items to terminal tracker status before closing the epic, and surface
  skipped optional/deferred items or failed closeout entries for human
  disposition. Merge-time automation may also invoke the same reconciler via
  `graduation-closeout-from-merged-pr.sh` as a fallback; double-runs are
  idempotent.
