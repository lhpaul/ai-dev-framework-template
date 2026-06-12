---
description: Run the implementation-plan review gate by manually reviewing against REVIEW.md. Usage: /review-implementation-plan [optional dev folder path]
---

Use `REVIEW.md` as the primary review contract.

For compatibility with the repo workflow, also follow:

`docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md`

Resolve and report the plan artifact owner before reviewing. Plans are
hub-owned in `workflow_hub` mode unless a future protocol explicitly changes
that.

If invoked as part of a reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.

Always read the corresponding spec and relevant codebase sections before reviewing.
