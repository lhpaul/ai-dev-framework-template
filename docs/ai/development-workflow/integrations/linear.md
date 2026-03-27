# Integration: Linear (Tracker Work Items)

This document describes how to connect the AI development workflow with [Linear](https://linear.app) as the tracker system for workflow work items.

Linear is **optional**. The workflow functions without it — the orchestrator simply requires human input to determine what to work on next.

---

## What Linear Adds

- The orchestrator can read work item status, priority, and due dates autonomously
- Status fields in Linear map directly to workflow stages
- Labels in Linear map to work item types and scope
- Priority and due date drive automated prioritization
- Agents will read the **current brief** following tracker-agnostic rules in [`issue-tracker.md`](issue-tracker.md)

---

## Work Item Setup

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

**Type labels** (one per work item):
- `Feature` — new capability
- `Bug` — something broken
- `Improvement` — enhancement to existing capability
- `Chore` — non-functional work (deps, tooling, docs)

**Scope labels** (one or more per work item):
- Add labels matching your app/service names (e.g., `Admin Portal`, `API`, `Mobile`)

### Priority

Use Linear's built-in priority field:
- Urgent (1) → Urgent
- High (2) → High
- Medium (3) → Normal
- Low (4) → Low

### Due Date

Set due dates on work items that have a deadline. The orchestrator treats work items due within 2 weeks as higher priority than the abstract priority field.

---

## Status: Tracker as Source of Truth

Workflow status (Spec Ready, Plan Ready, In Development) is **not** stored in the spec document. The tracker work item in Linear is the source of truth. The helper script `workflow-next-action.sh --development <path>` derives the next action from **repo state** (presence of implementation plan file, feature branch) so it works without reading a status field from the spec. See `scripts/development-workflow/README.md` and `workflow-next-action.sh` for the logic. Orchestrators and agents with Linear access should read and update work item status in Linear at stage transitions. **Do not call this script for work items in Merged or Released status;** the script cannot distinguish a not-yet-created branch from a deleted one.

---

## Orchestrator Instructions (with Linear)

When the orchestrator has Linear access, it should:

1. Query work items by status to find items eligible for advancement
2. Check the `Depends on` field (or linked work item relationships) for dependencies
3. Sort eligible items: due within 2 weeks → priority → creation date
4. Update work item status as stages complete (e.g., set to "In Development" when the feature branch is created)

---

## Branch Naming with Linear

When a Linear work item exists, use the Linear identifier as the branch slug prefix:

| Branch type | Pattern | Example |
|---|---|---|
| Spec | `spec/[work-item-id]-[slug]` | `spec/ENG-123-user-auth` |
| Implementation plan | `implementation-plan/[work-item-id]-[slug]` | `implementation-plan/ENG-123-user-auth` |
| Feature | `feature/[work-item-id]-[slug]` | `feature/ENG-123-user-auth` |
| Bug fix | `fix/[work-item-id]-[slug]` | `fix/ENG-456-login-redirect` |
| Hotfix | `hotfix/[work-item-id]-[slug]` | `hotfix/ENG-789-payment-crash` |

The `[slug]` is a short kebab-case description derived from the work item title (omit common words like "add", "fix", "update" to keep it short). Linear also auto-suggests a branch name on each work item — use it directly if preferred.

---

## Workflow: Advancing Statuses

The orchestrator or developer agent updates the Linear work item status at each stage transition:

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

With the MCP server, agents can read and update work items directly without the human copying tracker data into the chat.

---

## Without Linear

If you don't use Linear, the orchestrator asks the human:

> "What should I work on next? Please provide:
> - Feature name and slug
> - Path: Full Pipeline / Fast Track / Hotfix
> - Priority context (if any)
> - Dependencies (if any)"

This works fine for small teams or early-stage projects.
