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

## Step 2b: Capture graphical design assets (when candidates are present)

When the invocation includes candidate files (chat attachments, local paths, or
explicit mockup references), follow the canonical convention in
[`design-assets.md`](../design-assets.md) before creating the item:

1. **Detect** candidate files from the invocation.
2. **Classify** each file as likely design, clearly non-design, or ambiguous
   using the extension heuristics in `design-assets.md`.
3. **Clarify once** when any file is ambiguous (or a mixed batch is unclear): ask
   one brief question covering the whole ambiguous set. Clearly non-design files
   are not staged as design references unless the human explicitly says so.
4. Proceed to create **exactly one** backlog item (Step 3) — asset handling must
   not create duplicate items across clarification turns.
5. **Attach or stage** confirmed design assets via provider-native means when
   available. On attach/upload failure, record local paths in the issue body and
   ask the human to attach manually; do **not** fail item creation solely because
   upload failed. Reliable binary attach is agent-driven for GitHub (see the
   attach recipe in `design-assets.md`); the shell helper creates the issue and
   fields only.
6. **Record** a `## Design assets` section in the item body (include it in the
   initial body or append after create) using the template in `design-assets.md`.
   State locations and that plan/smoke stages should use the assets as fidelity
   references.

When no candidate files are present, skip this step entirely — do not invent
assets or a fidelity baseline.

---

## Step 3: Create exactly one backlog item

1. Create **one** item in the **confirmed** destination.
2. For **GitHub Issues** (including when `issue_tracker.provider` is `github_projects`), prefer:
   - `./scripts/development-workflow/add-backlog-item.sh create --title "..." --body-file - [--priority <value>] [--size <value>]` (requires `gh` authenticated), **or**
   - Equivalent `gh issue create` with the same title/body, followed by manual project field updates.
3. For **Linear**, use the Linear API/MCP per [`linear.md`](../integrations/linear.md). `add-backlog-item.sh create` now emits `TRACKER_ACTION_REQUIRED=create_item title=<title>` to stdout and exits 0 (not non-zero) when the configured provider is Linear. Multi-word titles are single-quoted (e.g., `title='My New Feature'`); strip the quotes before passing to the Linear MCP `createIssue` tool. Guidance referencing `linear.md` is also written to stderr for operator visibility.
4. For **GitHub Projects** after the issue exists: if the team uses a project board, add/update the project item per `github-projects.md` (optional field updates such as Status = Backlog and Type = Feature/Bug/Refactor/Workflow) **only when** the human or repo docs supply enough context (project number, owner). If project context is missing, **ask** rather than guessing.
5. When GitHub Projects is configured, use the project **Type** field for classification instead of repository labels. Set `Type = Workflow` for AI-development-framework/process/tooling work, `Type = Feature` for full-pipeline product work, `Type = Bug` for fast-track fixes, and `Type = Refactor` for plan-only refactors. Do not apply legacy classification labels such as `workflow`, `bug`, `enhancement`, or `type:*`; operational labels such as `integration-branch:<slug>` remain valid when the protocol requires them.
6. When GitHub Projects is configured, set **Priority** and **Size** on the project item. Use the inference heuristics below to determine values without asking the human for every routine item.

### Priority and Size inference heuristics (GitHub Projects)

**Priority** — infer from the request. When no explicit urgency/low signal
applies (the routine case), **omit `--priority` entirely** and let the
helper script's adaptive default resolve it against the board's actual
Priority field options (`Medium` if present, else `Normal` for a board not
yet migrated off the framework's pre-#1501 setup docs — see
[`github-projects.md`](../integrations/github-projects.md) and
`workflow_tracker_default_priority_value` in `workflow-lib.sh`). Do
**not** hardcode an explicit `--priority Medium` (or `Normal`) for the
routine case: an explicit value is validated against the board's real
options and is a hard error if it does not resolve, so hardcoding either
literal can break on a board configured with the other one.

`Urgent`, `High`, and `Low` are common to both the current and legacy
Priority vocabularies, so it is safe to pass those explicitly whenever a
genuine signal applies — a value that does not resolve against the board's
Priority options is a hard error from the helper script (see below), not a
silent no-op:

| Signal | Priority |
| ------ | -------- |
| Human uses words like "urgent", "blocking", "ASAP", "critical", or "production issue" | `--priority Urgent` or `--priority High` |
| Item blocks another in-progress item or a pending release | `--priority High` |
| Standard new feature, improvement, or process fix | Omit `--priority` (adaptive default) |
| Nice-to-have, polish, or exploratory work | `--priority Low` |

**Size** — infer from the scope of the change implied by the request:

| Scope | Size |
| ----- | ---- |
| Tiny doc fix, single-line config tweak, one-word rename | `XS` |
| Single narrow file: typo fix, one-protocol update, single-field doc change | `S` |
| 2–4 files, one feature toggle, small helper addition | `M` |
| Multiple scripts + protocol + docs touched, or new reusable function | `L` |
| New subsystem, major refactor spanning many files, cross-cutting change | `XL` |

Pass inferred values directly to the helper:

```bash
./scripts/development-workflow/add-backlog-item.sh create \
  --title "..." \
  --body-file - \
  --size S
```

This example omits `--priority` for the routine case shown in the table above, so the helper script's adaptive default applies. Pass `--priority Urgent`, `--priority High`, or `--priority Low` explicitly only when the corresponding signal from the table applies.

When the scope is genuinely unclear after reading the request, omit `--size` (leave it unset) rather than guessing.

---

## Step 4: Confirm to the user

Return a short confirmation including:

- **Destination** (e.g. GitHub issue vs Linear issue).
- **Identifier** (e.g. issue number, Linear key).
- **URL** to the item.
- **Title** and one-line recap of scope.
- When Step 2b ran: which files were treated as design assets, where they are
  stored (tracker attachment and/or path note), and any clarifying question asked.

---

## Step 5: Multi-Item Epic Detection (Optional — when two or more related items are requested)

When a human requests the creation of two or more related backlog items that together form a single coherent feature, the agent must also:

1. **Identify the multi-item nature** — confirm that the requested items form a coherent unit where partial delivery would be incomplete or misleading. When in doubt, ask: "Do you want these items to land on `develop` independently as each one completes, or as a group only when all are done?"

2. **Choose a slug** — derive a human-readable kebab-case slug from the shared feature name (e.g., `multi-tenant-billing`). The slug must be unique among existing `integration-branch:*` labels.

3. **Create an epic (GitHub providers only)** — when `issue_tracker.provider` is `github_issues` or `github_projects`, create a GitHub issue with the `epic` label as the grouping container. The title should reflect the overall feature. Record the epic's issue number.

   For non-GitHub providers (e.g., Linear), do not run `gh` commands. Ask the human for the equivalent parent/initiative container and linking convention, then proceed using that tracker's integration guide.

4. **Label each sub-item (GitHub providers only)** — apply the label `integration-branch:<slug>` to each sub-item issue created in Step 3. If the label does not exist in the repository, create it:

   ```bash
   gh label create "integration-branch:<slug>" --color "#0075ca" --description "Sub-item of the <slug> integration branch"
   ```

   For non-GitHub providers, use the tracker's native grouping or tagging mechanism to associate sub-items with the parent initiative.

5. **Link native GitHub sub-issues when supported (GitHub providers only)** — after the epic and sub-item issues exist, link each sub-item to the epic with GitHub's native sub-issue relationship. Keep the `integration-branch:<slug>` label from Step 4; existing orchestration uses that label to derive `develop-<slug>` even when native sub-issues are available.

   ```bash
   set -euo pipefail

   # Substitute the actual issue numbers before running.
   EPIC_ID=$(gh issue view <epic-issue-number> --json id --jq '.id')
   SUB_ISSUE_ID=$(gh issue view <sub-item-issue-number> --json id --jq '.id')
   [ -n "$EPIC_ID" ] || { echo "ERROR: could not resolve epic issue node ID" >&2; exit 1; }
   [ -n "$SUB_ISSUE_ID" ] || { echo "ERROR: could not resolve sub-item issue node ID" >&2; exit 1; }

   gh api graphql \
     -f issueId="$EPIC_ID" \
     -f subIssueId="$SUB_ISSUE_ID" \
     -F replaceParent=false \
     -f query='
       mutation($issueId: ID!, $subIssueId: ID!, $replaceParent: Boolean) {
         addSubIssue(input: {
           issueId: $issueId
           subIssueId: $subIssueId
           replaceParent: $replaceParent
         }) {
           issue { number }
           subIssue { number }
         }
       }
     '
   ```

   If the repository or API does not support native sub-issues, fall back to label-only grouping and report the fallback explicitly in the confirmation.

6. **Verify both sides of the native relationship (GitHub providers only)** — when native sub-issues were linked, verify that the epic lists the expected children and that every child points back to the epic:

   ```bash
   # Epic-side verification: lists child issue numbers and titles.
   gh api graphql \
     -F owner=<owner> \
     -F repo=<repo> \
     -F number=<epic-issue-number> \
     -f query='
       query($owner: String!, $repo: String!, $number: Int!) {
         repository(owner: $owner, name: $repo) {
           issue(number: $number) {
             number
             subIssues(first: 50) {
               nodes { number title state }
               pageInfo { hasNextPage endCursor }
             }
           }
         }
       }
     '

   # Child-side verification: confirms the parent epic for one sub-item.
   gh api graphql \
     -F owner=<owner> \
     -F repo=<repo> \
     -F number=<sub-item-issue-number> \
     -f query='
       query($owner: String!, $repo: String!, $number: Int!) {
         repository(owner: $owner, name: $repo) {
           issue(number: $number) {
             number
             parent { number title }
           }
         }
       }
     '
   ```

   If `pageInfo.hasNextPage` is `true`, continue querying with the returned `endCursor` and merge every page before deciding that the epic-side sub-issue list is complete. Do not verify only the first page for large epics.

7. **Confirm to the user** — include in the Step 4 confirmation:
   - The epic issue number and URL
   - The shared label `integration-branch:<slug>` applied to each sub-item
   - Whether native GitHub sub-issues were linked and verified, or whether the run fell back to label-only grouping
   - The note that sub-item PRs will target `develop-<slug>` (to be created by the orchestrator before the first PR)

**Single-item exemption**: When only a single item is requested, skip this step entirely. Single-item developments target `develop` directly and are not subject to the integration-branch workflow.

---

## Non-goals

- Do not silently pick a tracker when uncertain.
- Do not create multiple items for one user request.
- Do not start spec/plan/implementation work unless the user explicitly asks to advance stages afterward.
- Do not invent design assets or a visual-regression baseline when none were supplied.
- Do not implement `/merged-qa` (#1283) or promote design-reviewer as the primary fidelity gate here.

---

## Relationship to other protocols

- Advancing from **Backlog** into **Writing Spec** / **Writing Plan** is owned by orchestration protocols [`90-batch-orchestrate-work-protocol.md`](90-batch-orchestrate-work-protocol.md) and [`91-orchestrate-work-protocol.md`](91-orchestrate-work-protocol.md) once a work item exists and is selected.
