---
description: In Development stage. Implements a feature via Full Pipeline (with spec+plan), Fast Track (bug/simple change), or Hotfix (critical production bug). Usage: /implement-development [dev folder path | brief description of fix | "hotfix: [description]"]
---

Follow the implementation protocol exactly as defined in:

`docs/ai/development-workflow/protocols/04-implement-development-protocol.md`

### Which path?

- **Full Pipeline**: provide the dev folder path (e.g., `docs/specs/developments/20250101_my-feature/`)
- **Fast Track**: provide a brief description of the bug or simple change
- **Hotfix**: prefix with "hotfix:" (e.g., "hotfix: users can't log in after password reset")

Key rules:
- Full Pipeline: read spec + plan + runbook BEFORE writing any code
- Fast Track: stop and report if scope expands beyond the brief
- Hotfix: branch from `main`, not `develop`
- Always update CHANGELOG before opening the PR
