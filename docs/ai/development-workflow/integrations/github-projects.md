# Integration: GitHub Projects (Tracker Work Items)

This document describes how to connect the AI development workflow with [GitHub Projects (v2)](https://docs.github.com/en/issues/planning-and-tracking-with-projects) as the tracker system for workflow work items.

GitHub Projects is **optional**. The workflow functions without it — the **Portfolio Orchestrator** simply requires human input to determine what to work on next.

---

## What GitHub Projects Adds

- The **Portfolio Orchestrator** can read work item status, priority, and iteration autonomously via `gh` CLI
- A custom **Status** field on the project board maps directly to workflow stages
- Custom fields (Priority, Due date, Type) drive automated prioritization
- Labels on issues map to work item types and scope
- Agents will read the **current brief** following tracker-agnostic rules in [`issue-tracker.md`](issue-tracker.md)

---

## Concepts

GitHub Projects v2 sits on top of GitHub Issues:

- **Issues** are the work items (title, body, comments, labels, assignees)
- **Project** is the workflow layer (custom fields like Status, Priority, Due date, views)
- Each issue added to the project gets project-specific field values (e.g., Status = "Spec Ready")
- The `gh` CLI and GraphQL API are used to read and update both issues and project fields

---

## Project Setup

### 1. Create the Project

Create a GitHub Project (v2) linked to your repository:

```bash
# Create a project owned by the repo owner (user or org)
gh project create --owner <OWNER> --title "<Project Name>"
```

Note the **project number** returned — you will use it in all `gh project` commands.

### 2. Configure the Status Field

GitHub Projects v2 creates a default **Status** single-select field. Configure it with the following options to match workflow stages:

| Status Option | Workflow Stage |
|---|---|
| Backlog | Backlog |
| Writing Spec | Spec is being drafted |
| Spec in Review | Spec PR is ready for human review / merge |
| Spec Ready | Spec approved and merged. Implementation plan pending |
| Writing Plan | Implementation plan is being drafted |
| Plan in Review | Plan PR is ready for human review / merge |
| Plan Ready | Implementation plan approved and merged. Development pending |
| In Development | Development in progress |
| Development in Review | Development PR is ready for human review / merge |
| Merged | Development PR merged to `develop` |
| Released | Released to production |

To add or rename status options, use the project settings UI at `https://github.com/users/<OWNER>/projects/<NUMBER>/settings` (or the equivalent org URL).

### 3. Add Custom Fields

Add these custom fields to the project (via project settings UI or GraphQL):

| Field | Type | Purpose |
|---|---|---|
| Priority | Single select: `Urgent`, `High`, `Medium`, `Low` | Drives orchestrator prioritization |
| Due date | Date | Items due within 2 weeks get priority boost |
| Type | Single select: `Feature`, `Bug`, `Refactor` | Maps to workflow path (Full Pipeline, Refactor, or Fast Track) |

### 4. Issue Labels (on the Repository)

Labels live on the repository, not the project. Create labels for scope:

```bash
gh label create "scope:api" --description "API / backend"
gh label create "scope:frontend" --description "Frontend / UI"
# Add more as needed for your project's components
```

Type labels are optional if you use the project-level **Type** field instead. If you prefer labels:

```bash
gh label create "type:feature" --description "New capability"
gh label create "type:bug" --description "Something broken"
gh label create "type:refactor" --description "Code restructuring or tech-debt cleanup"
```

---

## Status: Tracker as Source of Truth

Workflow status (Spec Ready, Plan Ready, In Development) is **not** stored in the spec document. The project item's Status field is the source of truth. The helper script `workflow-next-action.sh --development <path>` derives the next action from **repo state** (presence of implementation plan file, feature branch) so it works without reading a status field from the spec. See `scripts/development-workflow/README.md` and `workflow-next-action.sh` for the logic. Orchestrators and agents with `gh` CLI access should read and update work item status in the project at stage transitions. **Do not call this script for work items in Merged or Released status;** the script cannot distinguish a not-yet-created branch from a deleted one.

---

## Orchestrator Instructions (with GitHub Projects)

When the **Portfolio Orchestrator** has `gh` CLI access, it should:

1. Query project items by status to find items eligible for advancement
2. Check for linked issues or task lists for dependencies
3. Sort eligible items: due within 2 weeks -> priority -> creation date
4. Update the project item's Status field as stages complete

### Reading Project Items

```bash
# List all items in the project with their fields
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json

# Get a specific issue's project fields
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json | jq '.items[] | select(.content.number == <ISSUE_NUMBER>)'
```

### Updating Status via GraphQL

Updating project item fields requires GraphQL. The general pattern:

```bash
# 1. Get the project node ID
PROJECT_ID=$(gh project view <PROJECT_NUMBER> --owner <OWNER> --format json | jq -r '.id')

# 2. Get the Status field ID and option IDs
gh project field-list <PROJECT_NUMBER> --owner <OWNER> --format json

# 3. Get the item ID for the issue
ITEM_ID=$(gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json \
  | jq -r '.items[] | select(.content.number == <ISSUE_NUMBER>) | .id')

# 4. Update the status
gh api graphql -f query='
  mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: "<PROJECT_ID>"
      itemId: "<ITEM_ID>"
      fieldId: "<STATUS_FIELD_ID>"
      value: { singleSelectOptionId: "<OPTION_ID>" }
    }) {
      projectV2Item { id }
    }
  }'
```

### Closing Issues

When a work item reaches **Merged** status, close the corresponding GitHub issue:

```bash
gh issue close <ISSUE_NUMBER>
```

---

## Branch Naming with GitHub Issues

When a GitHub issue exists, use the issue number as the branch slug prefix:

| Branch type | Pattern | Example |
|---|---|---|
| Spec | `spec/<issue-number>-<slug>` | `spec/42-user-auth` |
| Implementation plan | `implementation-plan/<issue-number>-<slug>` | `implementation-plan/42-user-auth` |
| Feature | `feature/<issue-number>-<slug>` | `feature/42-user-auth` |
| Refactor | `refactor/<issue-number>-<slug>` | `refactor/33-extract-auth-service` |
| Bug fix | `fix/<issue-number>-<slug>` | `fix/56-login-redirect` |
| Hotfix | `hotfix/<issue-number>-<slug>` | `hotfix/89-payment-crash` |

The `<slug>` is a short kebab-case description derived from the issue title.

---

## Workflow: Advancing Statuses

The **Portfolio Orchestrator**, **Work Item Runner**, or stage agent updates the project item Status at each stage transition:

| Action | Status transition |
|---|---|
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `product-manager` | -> Writing Spec |
| Spec PR is human-ready (automation clean; ready for humans) | -> Spec in Review |
| Spec PR merged | -> Spec Ready |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `tech-lead` | -> Writing Plan (Refactor items skip directly here from Backlog) |
| Plan PR is human-ready (automation clean) | -> Plan in Review |
| Plan PR merged | -> Plan Ready |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `developer` | -> In Development |
| Feature/fix PR is human-ready (automation clean) | -> Development in Review |
| Feature/fix PR merged to develop | -> Merged |
| Release deployed to production | -> Released |

---

## Post-Merge Cleanup

When a PR is merged, the `post-merge-cleanup` command will:

1. Extract the issue number from the branch name (e.g., `feature/42-user-auth` -> `42`)
2. Close the GitHub issue: `gh issue close 42`
3. Update the project item Status to **Merged** (via GraphQL)

---

## Prerequisites

- **`gh` CLI** authenticated with a token that has `project` and `repo` scopes:
  ```bash
  gh auth login
  # Verify access:
  gh project list --owner <OWNER>
  ```
- **Project number** — find it via `gh project list --owner <OWNER>` or from the project URL

---

## Without GitHub Projects

If you don't use GitHub Projects, the **Portfolio Orchestrator** asks the human:

> "What should I work on next? Please provide:
> - Feature name and slug
> - Path: Full Pipeline / Refactor / Fast Track / Hotfix
> - Priority context (if any)
> - Dependencies (if any)"

This works fine for small teams or early-stage projects.
