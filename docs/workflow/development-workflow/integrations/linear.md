# Integration: Linear (Tracker Work Items)

This document describes how to connect the AI development workflow with [Linear](https://linear.app) as the tracker system for workflow work items.

Linear is **optional**. The workflow functions without it — the **Portfolio Orchestrator** simply requires human input to determine what to work on next.

---

## What Linear Adds

- The **Portfolio Orchestrator** can read work item status, priority, and due dates autonomously
- Status fields in Linear map directly to workflow stages
- Labels in Linear map to work item types and scope
- Priority and due date drive automated prioritization
- Agents will read the **current brief** following tracker-agnostic rules in [`issue-tracker.md`](issue-tracker.md)

---

## Work Item Setup

### Status Field → Workflow Stage Mapping

Configure the following statuses in your Linear team settings:

| Linear Status         | Workflow Stage                                                                                     |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| Backlog               | Backlog                                                                                            |
| Writing Spec          | Spec is being drafted and driven to human-ready (draft PR, internal review, reviewer tools, CI)    |
| Spec in Review        | Spec PR is ready for human review / merge                                                          |
| Spec Ready            | Spec PR is merged                                                                                  |
| Writing Plan          | Implementation plan is being drafted and driven to human-ready (same PR-readiness pattern as spec) |
| Plan in Review        | Plan PR is ready for human review / merge                                                          |
| Plan Ready            | Plan PR is merged                                                                                  |
| In Development        | Feature/fix PR in progress (draft through PR readiness, until human-ready)                         |
| Development in Review | Feature/fix PR is ready for human review / merge                                                   |
| Merged                | Feature/fix PR merged to `develop`                                                                 |
| Released              | Released to production                                                                             |

### Labels

**Type labels** (one per work item):

- `Feature` — new capability
- `Bug` — something broken
- `Refactor` — code restructuring or tech-debt cleanup

**Scope labels** (one or more per work item):

- Add labels matching your app/service names (e.g., `Admin Portal`, `API`, `Mobile`)

### Priority

Use Linear's built-in priority field:

- Urgent (1) → Urgent
- High (2) → High
- Medium (3) → Normal
- Low (4) → Low

### Due Date

Set due dates on work items that have a deadline. The **Portfolio Orchestrator** treats work items due within 2 weeks as higher priority than the abstract priority field.

---

## Status: Tracker as Source of Truth

Workflow status (Spec Ready, Plan Ready, In Development) is **not** stored in the spec document. The tracker work item in Linear is the source of truth. The helper script `workflow-next-action.sh --development <path>` derives the next action from **repo state** (presence of implementation plan file, feature branch) so it works without reading a status field from the spec. See `scripts/development-workflow/README.md` and `workflow-next-action.sh` for the logic. Orchestrators and agents with Linear access should read and update work item status in Linear at stage transitions. **Do not call this script for work items in Merged or Released status;** the script cannot distinguish a not-yet-created branch from a deleted one.

---

## Orchestrator Instructions (with Linear)

When the **Portfolio Orchestrator** has Linear access, it should:

1. Query work items by status to find items eligible for advancement
2. Check the `Depends on` field (or linked work item relationships) for dependencies
3. Sort eligible items: due within 2 weeks → priority → creation date
4. Update work item status as stages complete (e.g., set to "In Development" when the feature branch is created)

---

## Branch Naming with Linear

When a Linear work item exists, use the Linear identifier as the branch slug prefix:

| Branch type         | Pattern                                     | Example                                 |
| ------------------- | ------------------------------------------- | --------------------------------------- |
| Spec                | `spec/[work-item-id]-[slug]`                | `spec/ENG-123-user-auth`                |
| Implementation plan | `implementation-plan/[work-item-id]-[slug]` | `implementation-plan/ENG-123-user-auth` |
| Feature             | `feature/[work-item-id]-[slug]`             | `feature/ENG-123-user-auth`             |
| Refactor            | `refactor/[work-item-id]-[slug]`            | `refactor/ENG-321-extract-auth-service` |
| Bug fix             | `fix/[work-item-id]-[slug]`                 | `fix/ENG-456-login-redirect`            |
| Hotfix              | `hotfix/[work-item-id]-[slug]`              | `hotfix/ENG-789-payment-crash`          |

The `[slug]` is a short kebab-case description derived from the work item title (omit common words like "add", "fix", "update" to keep it short). Linear also auto-suggests a branch name on each work item — use it directly if preferred.

---

## Custom Fields

The `issue_tracker.custom_fields` flat map in `.ai-dev-workflow.yaml` holds provider-specific fields that extend the standard `issue_tracker` configuration. For the Linear provider, the following keys are recognised by workflow scripts:

| Key                    | Format                   | Effect                                                                                                                                                                                                            |
| ---------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `project`              | Linear project ID string | When set, issue creation associates the new issue with the specified Linear project. The project ID is found in the Linear project URL (`https://linear.app/<team>/projects/<project-id>`) or via the Linear API. |
| `release_field`        | Custom field key/name    | Optional future write target for recording the shipped release on a Linear issue. Shell helpers warn that MCP/API access is required.                                                                             |
| `release_label_prefix` | Label prefix string      | Label fallback for release stamping. Defaults to `release/`, producing labels like `release/v1.2.0`. Shell helpers warn that MCP/API access is required to apply it.                                               |

When `project` is absent from `custom_fields` (or `custom_fields` itself is absent), issue creation proceeds without a project association — this is the current default behaviour and is fully backward-compatible.

To set a project association, add the following to `.ai-dev-workflow.yaml` under `issue_tracker`:

```yaml
issue_tracker:
  provider: linear
  custom_fields:
    project: my-linear-project-id
    release_label_prefix: release/
```

Read the value in a script using the `workflow_issue_tracker_custom_field` helper:

```bash
source scripts/development-workflow/workflow-lib.sh
project_id=$(workflow_issue_tracker_custom_field project)
```

Unrecognised keys in `custom_fields` are silently ignored by all current scripts.

### Release Stamping

Linear has no global first-class release object. The default workflow release
marker is a label named `release/vX.Y.Z`, using the configurable
`release_label_prefix` above. Teams that maintain a Linear custom field for
release tracking can set `release_field`; an MCP/API-backed implementation can
write that field during release cleanup.

Shell-only cleanup helpers cannot mutate Linear labels or custom fields directly.
They emit release-stamp guidance plus `TRACKER_ACTION=linear_mcp_or_api_required`
and exit non-zero unless `--best-effort` was explicitly accepted. The
orchestrator or a Linear MCP runner must apply the release label/custom field
and then transition every listed `TRACKER_ISSUES` item from `Merged` to
`Released` before reporting the release as complete.

---

## Workflow: Advancing Statuses

The **Portfolio Orchestrator**, **Work Item Runner**, or stage agent updates the Linear work item status at each stage transition:

| Action                                                                                          | Status transition                                               |
| ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `product-manager` | → Writing Spec                                                  |
| Spec PR is human-ready (automation clean; ready for humans)                                     | → Spec in Review                                                |
| Spec PR merged                                                                                  | → Spec Ready                                                    |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `tech-lead`       | → Writing Plan (Refactor items skip directly here from Backlog) |
| Plan PR is human-ready (automation clean)                                                       | → Plan in Review                                                |
| Plan PR merged                                                                                  | → Plan Ready                                                    |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `developer`       | → In Development                                                |
| Feature/fix PR is human-ready (automation clean)                                                | → Development in Review                                         |
| Feature/fix PR merged to develop                                                                | → Merged                                                        |
| Release deployed to production                                                                  | → Released                                                      |

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

If you don't use Linear, the **Portfolio Orchestrator** asks the human:

> "What should I work on next? Please provide:
>
> - Feature name and slug
> - Path: Full Pipeline / Refactor / Fast Track / Hotfix
> - Priority context (if any)
> - Dependencies (if any)"

This works fine for small teams or early-stage projects.
