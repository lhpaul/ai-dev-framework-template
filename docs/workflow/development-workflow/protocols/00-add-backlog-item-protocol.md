# Protocol: Add Backlog Item

**Agent role**: Any launcher or orchestrator entrypoint (often invoked via `/add-backlog-item` in Cursor or the matching Claude command)

**Purpose**: Create exactly one backlog work item from natural-language input, choose the correct tracker destination when possible, and ask clarifying questions when destination or intent is ambiguous.

This protocol runs **before** spec/plan/implementation stages. It does not write repository development artifacts under `docs/specs/developments/`.

---

## Prerequisites

Before creating anything, read:

- [`docs/workflow/development-workflow/integrations/issue-tracker.md`](../integrations/issue-tracker.md) — tracker-agnostic rules (do not guess; ask when unclear).
- [`.ai-dev-workflow.yaml`](../../../../.ai-dev-workflow.yaml) — `issue_tracker.provider` declares the configured tracker integration.
- Tracker-specific guides as needed:
  - [`docs/workflow/development-workflow/integrations/linear.md`](../integrations/linear.md)
  - [`docs/workflow/development-workflow/integrations/github-projects.md`](../integrations/github-projects.md)

Optional deterministic helper (destination resolution and GitHub issue creation):

```bash
./scripts/development-workflow/add-backlog-item.sh resolve
./scripts/development-workflow/add-backlog-item.sh create --title "..." --body-file -
```

---

## Step 1: Resolve destination (no silent assumptions)

1. Read `issue_tracker.provider` from `.ai-dev-workflow.yaml` (or run `add-backlog-item.sh resolve` for machine-readable output).
2. Map provider to destination **kind**:
   - `github_issues` or `github_projects` → GitHub Issues (issues are the work items; GitHub Projects layers fields on top of issues — see `github-projects.md`).
   - `linear` → Linear work items.
   - `jira`, `clickup`, `notion`, or other values → use the matching integration guide if present; if none exists, **stop and ask** the human where to create the item.
3. If the provider is missing, empty, `none`, or **ambiguous** (multiple plausible destinations, or config contradicts what the user asked for), **ask clarifying questions** and do **not** create an item until the human confirms the destination.
4. If tracker APIs/MCP are unavailable (e.g. Linear MCP not configured), **warn explicitly** (same spirit as protocols `90` / `91`: do not silently assume). Offer: paste tracker details, fix MCP/`gh` auth, or confirm a one-off destination.

---

## Step 2: Clarify the request (intent)

Before creating the work item, ensure you have enough signal. Minimum:

- **Title** (or a clear one-line summary you can turn into a title).
- **Problem / outcome** — what should change and why it matters.
- **Type / path hint** (when relevant): Full Pipeline (feature), Refactor, Fast Track, or bug — only if the team uses these distinctions in the tracker.

If any of the above are missing or contradictory, ask **targeted** clarifying questions. Do **not** create duplicate items across clarification turns: one creation per successful completion of this protocol.

---

## Step 3: Create exactly one backlog item

1. Create **one** item in the **confirmed** destination.
2. For **GitHub Issues** (including when `issue_tracker.provider` is `github_projects`), prefer:
   - `./scripts/development-workflow/add-backlog-item.sh create --title "..." --body-file -` (requires `gh` authenticated), **or**
   - Equivalent `gh issue create` with the same title/body.
3. For **Linear**, use the Linear API/MCP per [`linear.md`](../integrations/linear.md). The `add-backlog-item.sh create` command exits with a non-success code for Linear when the shell helper cannot perform the operation — follow the protocol manually instead of failing silently.
4. For **GitHub Projects** after the issue exists: if the team uses a project board, add/update the project item per `github-projects.md` (optional field updates such as Status = Backlog) **only when** the human or repo docs supply enough context (project number, owner). If project context is missing, **ask** rather than guessing.

---

## Step 4: Confirm to the user

Return a short confirmation including:

- **Destination** (e.g. GitHub issue vs Linear issue).
- **Identifier** (e.g. issue number, Linear key).
- **URL** to the item.
- **Title** and one-line recap of scope.

---

## Non-goals

- Do not silently pick a tracker when uncertain.
- Do not create multiple items for one user request.
- Do not start spec/plan/implementation work unless the user explicitly asks to advance stages afterward.

---

## Relationship to other protocols

- Advancing from **Backlog** into **Writing Spec** / **Writing Plan** is owned by orchestration protocols [`90-batch-orchestrate-work-protocol.md`](90-batch-orchestrate-work-protocol.md) and [`91-orchestrate-work-protocol.md`](91-orchestrate-work-protocol.md) once a work item exists and is selected.
