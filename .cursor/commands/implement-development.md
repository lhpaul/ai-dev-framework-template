---
description: In Development stage. Implements a feature via Full Pipeline (with spec+plan), Refactor (plan only, no spec), Fast Track (bug/simple change), or Hotfix (critical production bug), then keeps the PR moving until reviewer and CI readiness are resolved. Usage: /implement-development [dev folder path | brief description of fix | "hotfix: [description]"]
---

Follow the implementation protocol exactly as defined in:

`docs/ai/development-workflow/protocols/03-implement-development-protocol.md`

### Which path?

- **Full Pipeline**: provide the dev folder path (e.g., `docs/specs/developments/20250101_my-feature/`)
- **Refactor**: provide the dev folder path (plan-only folder, no spec)
- **Fast Track**: provide a brief description of the bug or simple change
- **Hotfix**: prefix with "hotfix:" (e.g., "hotfix: users can't log in after password reset")

Key rules:
- Full Pipeline: read spec + plan + runbook BEFORE writing any code
- Refactor: read plan + runbook BEFORE writing any code (no spec)
- Fast Track: stop and report if scope expands beyond the brief
- Hotfix: branch from `main`, not `develop`
- Always update CHANGELOG before opening the PR
- Do not stop at "PR opened"; continue through code review, automated review, and CI until the PR is ready or escalated
