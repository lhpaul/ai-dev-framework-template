---
description: Prepare a release from develop. Creates the release branch, updates CHANGELOG, bumps version, and opens PRs targeting both main and develop. Usage: /prepare-release [version number, e.g. 1.2.0]
---

Follow the release protocol exactly as defined in:

`docs/ai/development-workflow/protocols/06-prepare-release-protocol.md`

Key rules:
- Confirm the version with the human before creating the branch
- Open **two** PRs: one to `main`, one backport to `develop`
- Merge `main` PR first; the tag is created automatically by CI
- Do not delete the release branch until both PRs are merged
