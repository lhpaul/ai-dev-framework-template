# Integration: Linear (Issue Tracker)

This document describes how to connect the AI development workflow with [Linear](https://linear.app) as the issue tracker.

Linear is **optional**. The workflow functions without it — the orchestrator simply requires human input to determine what to work on next.

---

## What Linear Adds

- The orchestrator can read issue status, priority, and due dates autonomously
- Status fields in Linear map directly to workflow stages
- Labels in Linear map to issue types and scope
- Priority and due date drive automated prioritization

---

## Issue Setup

### Status Field → Workflow Stage Mapping

Configure the following statuses in your Linear team settings:

| Linear Status | Workflow Stage |
|---|---|
| Backlog | Backlog |
| Spec Ready | Spec Ready |
| Plan Ready | Plan Ready |
| In Development | In Development |
| Merged | Merged |
| Released | Released |

### Labels

**Type labels** (one per issue):
- `Feature` — new capability
- `Bug` — something broken
- `Improvement` — enhancement to existing capability
- `Chore` — non-functional work (deps, tooling, docs)

**Scope labels** (one or more per issue):
- Add labels matching your app/service names (e.g., `Admin Portal`, `API`, `Mobile`)

### Priority

Use Linear's built-in priority field:
- Urgent (1) → Urgent
- High (2) → High
- Medium (3) → Normal
- Low (4) → Low

### Due Date

Set due dates on issues that have a deadline. The orchestrator treats issues due within 2 weeks as higher priority than the abstract priority field.

---

## Orchestrator Instructions (with Linear)

When the orchestrator has Linear access, it should:

1. Query issues by status to find items eligible for advancement
2. Check the `Depends on` field (or linked issue relationships) for dependencies
3. Sort eligible items: due within 2 weeks → priority → creation date
4. Update issue status as stages complete (e.g., set to "In Development" when the feature branch is created)

---

## Workflow: Advancing Statuses

The orchestrator or developer agent updates the Linear issue status at each stage transition:

| Action | Status transition |
|---|---|
| Spec branch created | → Spec Ready |
| Plan branch created | → Plan Ready |
| Feature branch created | → In Development |
| Feature PR merged to develop | → Merged |
| Release deployed to production | → Released |

---

## Linear MCP Server (for Claude Code / Cursor)

To give your AI agent direct Linear access, configure the Linear MCP server:

```json
// .cursor/.mcp.json or equivalent MCP config
{
  "mcpServers": {
    "linear": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-linear"],
      "env": {
        "LINEAR_API_KEY": "your-linear-api-key"
      }
    }
  }
}
```

With the MCP server, agents can read and update issues directly without the human copying issue data into the chat.

---

## Without Linear

If you don't use Linear, the orchestrator asks the human:

> "What should I work on next? Please provide:
> - Feature name and slug
> - Path: Full Pipeline / Fast Track / Hotfix
> - Priority context (if any)
> - Dependencies (if any)"

This works fine for small teams or early-stage projects.
