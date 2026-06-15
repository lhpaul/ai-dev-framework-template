---
description: Run the implementation review gate by manually reviewing against REVIEW.md. Applies fixes directly for blocking/important issues. Usage: /review-code [optional file paths or patterns]
---

Use `REVIEW.md` as the primary review contract.

For compatibility with the repo workflow, also follow:

`docs/workflow/development-workflow/protocols/03-review-implementation-protocol.md`

Resolve and report the implementation artifact owner before reviewing. In
`workflow_hub`, product implementation PRs are reviewed in the selected product
repository while hub-only workflow PRs remain hub-owned.

If invoked as part of a reviewer loop, apply fixes, commit, and push until the review gate reaches approval or a real human decision is required.

Locate the code to review using this priority:

1. Explicit file paths provided in the command argument
2. Files edited in the current conversation
3. All files changed in the current branch (`git diff develop...HEAD`)
4. Ask the user
