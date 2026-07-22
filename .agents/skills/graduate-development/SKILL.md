---
name: graduate-development
description: Command-style Codex alias for graduating an integration branch. Use when the user asks for /graduate-development or wants to merge an integration branch back to develop.
---

# Graduate Development

This is the Codex command-style alias for Claude Code `/graduate-development`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
3. Follow the protocol exactly for the provided development slug or integration branch.
4. Do not merge without the human approval gates required by the protocol.
5. After the graduation PR merges, run the Protocol 05b Step 5 graduation
   closeout helper (`graduation-closeout.sh`) so delivered sub-items and the
   parent epic are closed or moved to the terminal tracker status in the right
   order. Step 5 remains the primary path; merge-time automation may also run
   the same reconciler via `graduation-closeout-from-merged-pr.sh` as a
   fallback (idempotent if both run).
6. Stop and surface the closeout summary if any delivered sub-item fails
   reconciliation or any skipped optional/deferred item needs human disposition.
