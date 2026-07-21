---
description: >
  QA work already on develop or an integration branch (develop-<slug>).
  Usage: /post-merge-qa [--base <branch>] [scope hints]
allowed-tools: Bash(./scripts/development-workflow/post-merge-qa-scope.sh:*), Bash(git:*), Bash(gh:*), Read, Grep, Glob
---

Follow the post-merge QA protocol exactly:

`docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md`

Compatibility alias: `/merged-qa-tester` (identical behavior).

Use `./scripts/development-workflow/post-merge-qa-scope.sh` for read-only scope
proposals. Confirm scope with the human before exercising flows. When safely
actionable defects exist, open one fix PR targeting the QA base — do not create
a new backlog item.
