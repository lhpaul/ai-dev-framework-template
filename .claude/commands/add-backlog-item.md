---
description: Backlog stage. Creates one backlog work item from natural-language input with tracker destination detection and clarifying questions when needed. Usage: /add-backlog-item [optional brief description]
---

# Claude Code Command: Add Backlog Item

Follow the backlog-item protocol exactly as defined in:

`docs/ai/development-workflow/protocols/00-add-backlog-item-protocol.md`

Key responsibilities:

- Read `issue_tracker.provider` from `.ai-dev-workflow.yaml` (or run `./scripts/development-workflow/add-backlog-item.sh resolve` for machine-readable destination hints).
- If destination is unclear, contradictory, or unsupported without MCP/API access, ask clarifying questions **before** creating anything.
- If the user request is missing title, problem/outcome, or other essential context, ask **targeted** clarifying questions before creating anything.
- Create **exactly one** backlog item in the confirmed destination.
- For GitHub Issues (including when the provider is `github_projects`), prefer `./scripts/development-workflow/add-backlog-item.sh create --title "..." --body-file -` when `gh` is authenticated; otherwise follow the protocol manually.
- For Linear, use Linear MCP/API per `docs/ai/development-workflow/integrations/linear.md` when the shell helper cannot create the item.
- Do not silently assume a tracker or duplicate items across clarification turns.
- Return the created item identifier, URL, and a short recap to the user.
