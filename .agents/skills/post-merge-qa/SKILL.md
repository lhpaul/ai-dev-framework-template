---
name: post-merge-qa
description: "Primary command: QA work already on develop or develop-<slug>. Use when the user asks for /post-merge-qa or /merged-qa-tester (identical alias). Proposes confirmed scope, preflights environment, exercises flows, optional design-asset fidelity, and opens one fix PR for safe defects without a new backlog item."
---

# Post-Merge QA

Follow `docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md`
exactly. `/merged-qa-tester` is a compatibility alias with identical behavior.

1. Resolve allowed QA base (`develop` or `develop-<slug>`).
2. Propose scope (prefer helper below); confirm with the human before testing.
3. Preflight runnable environment; ask when missing.
4. Exercise flows / critical UX; optional design-asset fidelity via
   `docs/workflow/development-workflow/design-assets.md`.
5. Clean pass → no fix PR. Safe defects → one fix PR on the QA base (no backlog
   item). Product decisions → ask the human.

## Scope helper

```bash
./scripts/development-workflow/post-merge-qa-scope.sh \
  --base <develop|develop-slug> \
  [--epic <n>] [--issues <csv>] [--recent-merged-prs <n>] \
  --json
```

Read-only. Present output and wait for confirmation.
