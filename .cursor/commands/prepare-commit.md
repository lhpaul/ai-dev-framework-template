---
description: Review staged changes and propose a Conventional Commits message. Usage: @prepare-commit [optional description hint]
---

Follow the git conventions defined in:

`docs/best-practices/2-version-control.md`

Steps:
1. Run `git diff --staged` to see what is staged
2. If nothing is staged, run `git status` and ask which files to stage
3. Review the staged diff for any issues (lint, secrets, unrelated changes)
4. Propose a commit message following Conventional Commits format: `<type>([scope]): <description>`
5. Ask the user to confirm before committing
6. Run the commit with the approved message

Do not automate the commit — always show the message and wait for confirmation.
