---
description: Spec Ready stage. Conducts an alignment conversation and writes the feature spec, then continues through reviewer gate, PR creation, and PR readiness. Usage: /generate-new-feature [optional brief description of the feature]
---

Follow the spec generation protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`

Resolve repository mode, artifact owner, and artifact base branch before
writing: `single_repo` uses the current repository, while `workflow_hub` keeps
specs and spec PRs hub-owned on the hub artifact base branch, even when the
product implementation base is different.

Do not skip the alignment conversation. Once ambiguity is resolved, continue through reviewer gate, PR creation, and PR readiness unless the protocol requires human input.
