---
name: post-merge-qa
model: claude-sonnet-4-6
description: Post-merge QA on develop or develop-<slug>. Confirmed scope, environment preflight, flow/UX exercise, optional design-asset fidelity, one fix PR for safe defects (no backlog item).
---

Follow the post-merge QA protocol exactly:

**`docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md`**

Primary command: `/post-merge-qa`. Compatibility alias: `/merged-qa-tester` (identical).

## Required behavior

1. Resolve `QA_BASE` (`develop` or `develop-<slug>` only).
2. Propose scope with `scripts/development-workflow/post-merge-qa-scope.sh` when useful; **confirm with the human** before testing. Empty confirmed scope → stop.
3. Preflight the runnable environment; ask when missing (docs-only path only with human confirmation).
4. Exercise critical flows/UX for the confirmed scope.
5. When design assets are discoverable per `docs/workflow/development-workflow/design-assets.md`, run light fidelity checks; otherwise skip silently.
6. Clean pass → no fix PR. Safely actionable defects → **one** fix PR targeting `QA_BASE`; do **not** create a backlog item. Product-decision defects → ask the human.
7. Do not auto-merge the fix PR. Do not replace pre-merge smoke tests.
