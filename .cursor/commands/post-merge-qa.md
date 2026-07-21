---
description: "QA work already on develop or develop-<slug>. Usage: /post-merge-qa [--base <branch>] [scope hints]"
---

# Cursor Command: Post-Merge QA

Invoke the `post-merge-qa` agent to quality-check work already merged to
`develop` or sitting on an integration branch (`develop-<slug>`).

Pass any scope hints (base branch, epic, issues, recent merged PRs) to the agent.

The agent follows the protocol exactly:

`docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md`

Compatibility alias: `/merged-qa-tester` (identical behavior).
