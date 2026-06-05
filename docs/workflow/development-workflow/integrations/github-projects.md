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

| Status Option         | Workflow Stage                                               |
| --------------------- | ------------------------------------------------------------ |
| Backlog               | Backlog                                                      |
| Writing Spec          | Spec is being drafted                                        |
| Spec in Review        | Spec PR is ready for human review / merge                    |
| Spec Ready            | Spec approved and merged. Implementation plan pending        |
| Writing Plan          | Implementation plan is being drafted                         |
| Plan in Review        | Plan PR is ready for human review / merge                    |
| Plan Ready            | Implementation plan approved and merged. Development pending |
| In Development        | Development in progress                                      |
| Development in Review | Development PR is ready for human review / merge             |
| Merged                | Development PR merged to `develop`                           |
| Released              | Released to production                                       |

To add or rename status options, use the project settings UI at `https://github.com/users/<OWNER>/projects/<NUMBER>/settings` (or the equivalent org URL).

### 3. Add Custom Fields

Add these custom fields to the project (via project settings UI or GraphQL):

| Field    | Type                                             | Purpose                                                        |
| -------- | ------------------------------------------------ | -------------------------------------------------------------- |
| Priority | Single select: `Urgent`, `High`, `Normal`, `Low` | Drives orchestrator prioritization                             |
| Due date | Date                                             | Items due within 2 weeks get priority boost                    |
| Type     | Single select: `Feature`, `Bug`, `Refactor`      | Maps to workflow path (Full Pipeline, Refactor, or Fast Track) |

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

Workflow status (Spec Ready, Plan Ready, In Development) is **not** stored in the spec document. The project item's Status field is the source of truth. The helper script `workflow-next-action.sh --development <path>` derives the next action from **repo state** (presence of implementation plan file, feature branch) so it works without reading a status field from the spec. See `scripts/development-workflow/README.md` and `workflow-next-action.sh` for the logic. Orchestrators and agents with `gh` CLI access should read and update work item status in the project at stage transitions.

When `gh` is available, the script detects merged PRs via `gh pr list --state merged` and returns `NEXT_ACTION=skip` for items whose branch has already been merged — so calling it on Merged or Released items is safe in that configuration. Without `gh` CLI access, the script cannot distinguish a not-yet-created branch from a deleted one; in that case, prefer filtering work items by tracker status (e.g. exclude Merged/Released) before invoking the script.

---

## CLI Update Patterns for Agents and Subagents

GitHub Projects status updates can be performed entirely via `gh` CLI and Bash — no MCP server is required. This means subagent Work Item Runners dispatched from parallel batch runs can update tracker status directly at Step 8b without deferring to the orchestrator.

### Board membership check (ensure_on_project_board)

Before updating tracker status, each stage agent (spec-writer, plan-writer, developer) must ensure the issue is registered on the project board. The `ensure_on_project_board` function in `scripts/development-workflow/workflow-lib.sh` handles this idempotently:

```bash
# Source workflow-lib.sh to get ensure_on_project_board
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source scripts/development-workflow/workflow-lib.sh

# Call before tracker status update in the agent completion sequence.
# initial_status: "Writing Spec" (spec agent), "Writing Plan" (plan agent), "In Development" (developer agent)
ensure_on_project_board "$ISSUE_NUMBER" "$INITIAL_STATUS"
```

The function is **fail-open**: if the issue is already on the board it returns 0 immediately without modifying the existing status; if the board-add API call fails for any reason (rate limit, permissions error) it logs a warning and returns 0 so the agent can continue to open the PR. The initial status is only applied when the issue is newly added to the board — the subsequent `update_tracker_status_best_effort` call handles the normal stage-progression update independently.

### One-shot status update (recommended pattern)

Use the shared helper when a stage completes and the tracker status must advance. It performs a targeted `repository.issue(...).projectItems` lookup for the single issue and avoids `gh project item-list`, which paginates the whole board and can drain the GraphQL rate-limit bucket.

```bash
# Source workflow-lib.sh to get the targeted GitHub Projects helpers.
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source scripts/development-workflow/workflow-lib.sh

ISSUE_NUMBER=<ISSUE>                         # GitHub issue number to update
TARGET_STATUS="Development in Review"        # Use a value from the table below

update_tracker_status_best_effort "$ISSUE_NUMBER" "$TARGET_STATUS"
```

For manual debugging, call `workflow_github_project_item_for_issue <issue> <project-number>` after sourcing `workflow-lib.sh`; it returns the project item ID, project ID, and current Status for exactly one issue.

### Status values by workflow stage (Step 8b targets)

| PR type                                                                  | Target status string    |
| ------------------------------------------------------------------------ | ----------------------- |
| `spec/*` PR ready for human review                                       | `Spec in Review`        |
| `implementation-plan/*` PR ready for human review                        | `Plan in Review`        |
| `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` PR ready for human review | `Development in Review` |

### Caching field and option IDs

Field IDs and option IDs are stable within a project. `update_tracker_status_best_effort`
caches the Status field metadata in memory for the current shell process after the first
targeted lookup, so repeated status updates in the same run do not need repeated field
metadata queries. Re-run the helper in a fresh shell if the project field configuration changes.

---

## Orchestrator Instructions (with GitHub Projects)

When the **Portfolio Orchestrator** has `gh` CLI access, it should:

1. Query project items by status to find items eligible for advancement
2. Check for linked issues or task lists for dependencies
3. Sort eligible items: due within 2 weeks -> priority -> creation date
4. Update the project item's Status field as stages complete

### Reading Project Items

**Performance note**: `gh project item-list` paginates all board items, including closed and merged
ones. On boards with 300+ items this exhausts the 5 000-point GraphQL rate limit, causing a
~3.5-minute pause that grows as more items accumulate. Prefer the open-issue approach below.

**Recommended: query open issues first, then cross-reference with a single item-list call**

GitHub Projects v2 has no server-side open-issue filter on the items node, so a full `item-list`
fetch is unavoidable. The key optimisation is to fetch open issues from the GitHub Issues API
(which supports state filtering) and then cross-reference them against the project board items
client-side — this ensures downstream processing only touches open candidates:

```bash
# Step 1: list open issues only (the only candidates for orchestrator advancement)
OPEN_ISSUES=$(gh issue list --state open --limit 1000 --json number,title,labels,createdAt)

# Step 2: fetch all project board items once and filter to only open-issue candidates
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --limit 10000 --format json \
  | jq --argjson open "$OPEN_ISSUES" \
    '[.items[] | . as $item | ($open[] | select(.number == $item.content.number)) // empty | {number: .number, title: .title, status: $item.status}]'
```

**Alternative: client-side terminal-status filter (simpler, same single item-list call)**

When you want a simpler filter without loading the open-issue list separately, fetch all items
and immediately discard terminal-status entries client-side:

```bash
# Fetch all items and filter out terminal statuses client-side
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --limit 10000 --format json \
  | jq '[.items[] | select(.status != null and (.status | IN("Done","Merged","Released","Cancelled")) | not)]'
```

**Rate-limit check**: check remaining GraphQL quota before and after large pagination:

```bash
gh api rate_limit --jq '.resources.graphql | {limit, remaining, used, reset: (.reset | todate)}'
```

Warn the human when `remaining` falls below 1 000 points. Pause dispatch when below 200 points
and report the reset time. See Protocol 90 Step 1a for the full rate-limit guidance.

### Updating Status via GraphQL

Updating project item fields requires GraphQL. For agent and script use, prefer `update_tracker_status_best_effort` from `workflow-lib.sh`; it resolves the item ID through a targeted single-issue query and caches Status field metadata for the run.

If you must issue the GraphQL manually, do not use `gh project item-list` for a single issue. Resolve the item through the issue's projectItems connection:

```bash
gh api graphql \
  -f owner=<REPO_OWNER> \
  -f repo=<REPO_NAME> \
  -F issueNumber=<ISSUE_NUMBER> \
  -F projectNumber=<PROJECT_NUMBER> \
  -f query='
    query($owner: String!, $repo: String!, $issueNumber: Int!, $projectNumber: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $issueNumber) {
          projectItems(first: 50) {
            nodes {
              id
              project { id number }
              fieldValueByName(name: "Status") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
            }
          }
        }
      }
    }' \
  | jq --argjson projectNumber <PROJECT_NUMBER> \
    '.data.repository.issue.projectItems.nodes[]
     | select(.project.number == $projectNumber)
     | {item_id: .id, project_id: .project.id, status: .fieldValueByName.name}'
```

Then use the returned `project_id` with a Status field/option lookup and apply the mutation:

```bash
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

| Branch type         | Pattern                                     | Example                            |
| ------------------- | ------------------------------------------- | ---------------------------------- |
| Spec                | `spec/<issue-number>-<slug>`                | `spec/42-user-auth`                |
| Implementation plan | `implementation-plan/<issue-number>-<slug>` | `implementation-plan/42-user-auth` |
| Feature             | `feature/<issue-number>-<slug>`             | `feature/42-user-auth`             |
| Refactor            | `refactor/<issue-number>-<slug>`            | `refactor/33-extract-auth-service` |
| Bug fix             | `fix/<issue-number>-<slug>`                 | `fix/56-login-redirect`            |
| Hotfix              | `hotfix/<issue-number>-<slug>`              | `hotfix/89-payment-crash`          |

The `<slug>` is a short kebab-case description derived from the issue title.

---

## Workflow: Advancing Statuses

The **Portfolio Orchestrator**, **Work Item Runner**, or stage agent updates the project item Status at each stage transition:

| Action                                                                                          | Status transition                                                |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `product-manager` | -> Writing Spec                                                  |
| Spec PR is human-ready (automation clean; ready for humans)                                     | -> Spec in Review                                                |
| Spec PR merged                                                                                  | -> Spec Ready                                                    |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `tech-lead`       | -> Writing Plan (Refactor items skip directly here from Backlog) |
| Plan PR is human-ready (automation clean)                                                       | -> Plan in Review                                                |
| Plan PR merged                                                                                  | -> Plan Ready                                                    |
| Human or Portfolio Orchestrator selects the item; Work Item Runner dispatches `developer`       | -> In Development                                                |
| Feature/fix PR is human-ready (automation clean)                                                | -> Development in Review                                         |
| Feature/fix PR merged to develop                                                                | -> Merged                                                        |
| Release deployed to production                                                                  | -> Released                                                      |

---

## Automated Tracker Updates on PR Merge (GitHub Actions)

The repository ships a GitHub Actions workflow (`.github/workflows/update-tracker-on-merge.yml`)
that automatically updates the GitHub Projects status whenever a workflow PR is merged to `develop`.
This eliminates the stale-status problem that occurs between orchestrator runs.

### Branch-to-status mapping

| Branch prefix           | Status after merge | Issue closed? |
| ----------------------- | ------------------ | ------------- |
| `spec/*`                | Spec Ready         | No            |
| `implementation-plan/*` | Plan Ready         | No            |
| `feature/*`             | Merged             | Yes           |
| `fix/*`                 | Merged             | Yes           |
| `refactor/*`            | Merged             | Yes           |
| `hotfix/*`              | Merged             | Yes           |

### How it works

1. Triggered on `pull_request` closed events targeting `develop` where `merged == true`
2. Extracts the branch prefix to determine the stage type
3. Extracts the issue number from the branch name (e.g., `fix/463-some-slug` → `463`)
4. Queries the GitHub Projects v2 GraphQL API to find the project item for that issue
5. Updates the `Status` field to the appropriate value
6. For implementation branches (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`): also closes the GitHub issue

### Required configuration

Set the following as **repository variables** (not secrets — these are not sensitive):

| Variable                | Description                                                                                    |
| ----------------------- | ---------------------------------------------------------------------------------------------- |
| `GITHUB_PROJECT_NUMBER` | The integer project number (e.g. `1`)                                                          |
| `GITHUB_PROJECT_OWNER`  | The GitHub user or org owning the project (falls back to `github.repository_owner` when unset) |

To set them via CLI:

```bash
gh variable set GITHUB_PROJECT_NUMBER --body "1"
gh variable set GITHUB_PROJECT_OWNER --body "<your-github-username-or-org>"
```

### Security model

- Uses the built-in `GITHUB_TOKEN` — no personal access token (PAT) required
- Minimum permissions: `pull-requests: read`, `issues: write`, `projects: write`
- All external action SHAs are pinned to exact commit hashes (no floating `@v7` tags)

### Relationship to `post-merge-cleanup`

The GitHub Actions workflow and the `post-merge-cleanup` CLI command perform the same tracker
update logic. They are complementary:

- **GitHub Actions workflow**: runs automatically on every PR merge, no human action needed
- **`post-merge-cleanup` command**: run manually by a developer or orchestrator after merging;
  also handles local branch deletion and `develop` pull

If both are active, the tracker update from `post-merge-cleanup` is idempotent (same status
written twice is harmless).

---

## Post-Merge Cleanup

When a PR is merged, the `post-merge-cleanup` command will:

1. Extract the issue number from the branch name (e.g., `feature/42-user-auth` -> `42`)
2. Apply the action appropriate for the branch type:
   - `spec/*`: issue stays open; update project item Status to **Spec Ready**
   - `implementation-plan/*`: issue stays open; update project item Status to **Plan Ready**
   - `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`: close the GitHub issue (`gh issue close 42`) and update project item Status to **Merged**
3. Each tracker update is best-effort: if `GITHUB_PROJECT_NUMBER` is unset or the API call fails, a warning is logged and the script continues without aborting

---

## Release Post-Merge Cleanup

After a release branch has merged to both `main` and `develop`, use:

```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh vX.Y.Z --issues 101,102
```

This script:

1. Verifies both release PRs are merged before any branch deletion
2. Deletes `release/vX.Y.Z` on `origin` and locally (when safe)
3. Transitions explicit scoped issues from merged-to-integration to released-to-production

Status label defaults and overrides:

- `GITHUB_PROJECT_STATUS_MERGED` (default: `Merged`)
- `GITHUB_PROJECT_STATUS_RELEASED` (default: `Released`)

Use explicit issue numbers to avoid accidental broad transitions. Items not included in the shipped release should remain unchanged.

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

## Custom Fields

The `issue_tracker.custom_fields` flat map in `.ai-dev-workflow.yaml` is available for provider-specific configuration extensions. For the `github_projects` provider, **no `custom_fields` keys are currently recognised by workflow scripts**.

Key points:

- The `project_number` field is a standard top-level `issue_tracker` field — it is not a custom field and must remain under `issue_tracker` directly, not under `custom_fields`.
- Any keys placed under `custom_fields` are silently ignored by all current GitHub Projects scripts.
- Future provider-specific fields (e.g., additional project metadata) may be added here as the integration evolves.

Read the `workflow_issue_tracker_custom_field` helper documentation in `scripts/development-workflow/workflow-lib.sh` for the parsing API available to future consumers.

---

## Without GitHub Projects

If you don't use GitHub Projects, the **Portfolio Orchestrator** asks the human:

> "What should I work on next? Please provide:
>
> - Feature name and slug
> - Path: Full Pipeline / Refactor / Fast Track / Hotfix
> - Priority context (if any)
> - Dependencies (if any)"

This works fine for small teams or early-stage projects.
