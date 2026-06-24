---
description: Plan Ready stage. Reads the approved spec (or work item brief for Refactor items) and codebase, resolves technical approach questions, then writes the implementation plan, runs its reviewer gate, and resolves PR readiness. Usage: /generate-implementation-plan [optional feature slug or dev folder path]
---

Follow the implementation plan generation protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`

Resolve repository mode, artifact owner, and artifact base branch before
writing: `single_repo` uses the current repository, while `workflow_hub` keeps
plans and plan PRs hub-owned on the hub artifact base branch, even when the
product implementation base is different.

Always read the approved spec (or the work item brief for Refactor items) and relevant codebase sections before proposing an approach. Once ambiguity is resolved, continue through reviewer gate, PR creation, and PR readiness unless the protocol requires human input.
