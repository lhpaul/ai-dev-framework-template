---
name: prepare-release
description: Command-style Codex alias for preparing a release. Use when the user asks for /prepare-release or wants to run the repository release preparation protocol.
---

# Prepare Release

This is the Codex command-style alias for Claude Code `/prepare-release`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`.
3. Follow the protocol exactly.
4. Continue through release PR creation, release-branch reviewer-loop skip handling, regression readiness, and CI readiness until the protocol reaches a real terminal condition.
5. After both release PRs merge, run post-merge cleanup with `--from-changelog`
   or an explicit `--issues` scope, then complete any emitted tracker handoff
   such as `TRACKER_ACTION=linear_mcp_or_api_required` before calling the
   release done.
