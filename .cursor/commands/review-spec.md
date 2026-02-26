---
description: Review a spec PR for completeness, clarity, and testability. Applies fixes directly where possible. Usage: /review-spec [optional path to dev folder]
---

Follow the spec review protocol exactly as defined in:

`docs/ai/development-workflow/protocols/01-review-specs-protocol.md`

Locate the spec to review using this priority:
1. Explicit path provided in the command argument
2. Files changed in the current branch (`git diff main...HEAD`)
3. Ask the user
