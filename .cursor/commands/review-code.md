---
description: Review implemented code against the spec, plan, and best practices. Applies fixes directly for blocking/important issues. Usage: @review-code [optional file paths or patterns]
---

Follow the code review protocol exactly as defined in:

`docs/ai/development-workflow/protocols/04-review-implemented-development-protocol.md`

Locate the code to review using this priority:
1. Explicit file paths provided in the command argument
2. Files edited in the current conversation
3. All files changed in the current branch (`git diff develop...HEAD`)
4. Ask the user
