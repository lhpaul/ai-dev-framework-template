---
description: Run the spec review gate by manually reviewing against REVIEW.md. Applies fixes directly where possible. Usage: /review-spec [optional path to dev folder]
---

Use `REVIEW.md` as the primary review contract.

For compatibility with the repo workflow, also follow:

`docs/ai/development-workflow/protocols/01-review-spec-protocol.md`

If invoked as part of a reviewer loop, apply fixes, commit, and push until the protocol reaches approval or a real human decision is required.

Locate the spec to review using this priority:
1. Explicit path provided in the command argument
2. Files changed in the current branch (`git diff main...HEAD`)
3. Ask the user
