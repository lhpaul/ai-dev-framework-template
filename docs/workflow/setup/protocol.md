# Protocol: Project Setup (Onboarding)

**Agent role**: Project Setup
**Purpose**: Guide a structured conversation to generate all project-specific documentation and configure the framework for a new project.

This protocol is **tool-agnostic**. It is invoked via:

- Claude Code: `project-setup` agent
- Cursor: `/setup-project` command
- Any other AI tool: "Follow the setup protocol at `docs/workflow/setup/protocol.md`"

---

## Overview

When a team clones this template, the project-specific docs (`docs/project/`) are empty placeholders, `AGENTS.md` has a generic project description, and `docs/best-practices/STACK-SPECIFIC.md` is empty.

This protocol fills all of that in through a structured conversation with the human. At the end, the AI commits the generated docs to a setup branch and opens a PR.

Estimated time: 20–45 minutes depending on project complexity.

---

## Step 0: Repository Mode Selection

Before asking project-specific questions, determine which repository mode this
setup run is targeting:

| Mode | Use when | Skeleton to inspect |
| --- | --- | --- |
| `single_repo` | One repository owns tracker work, specs, plans, implementation branches, PRs, CI, reviewer-loop checks, and releases. This is the default path. | Current repository root |
| `workflow_hub` | One repository coordinates workflow for one or more product repositories. | `template/workflow-hub/` |
| `product_repo` | A product repository receives routed implementation work from a workflow hub and owns product code validation. | `template/product-repo-injection/` |

Ask:

> "Which repository mode are we setting up: `single_repo`, `workflow_hub`, or
> `product_repo`?"

If the user is unsure, recommend `single_repo` unless they already have a
separate workflow hub or are explicitly splitting workflow coordination from
product code repositories.

Rules:

- The current root template remains the valid `single_repo` setup path.
- `workflow_hub` setup should inspect `template/workflow-hub/` and
  `docs/workflow/development-workflow/repository-modes.md` before generating
  docs or configuration.
- `product_repo` setup should inspect `template/product-repo-injection/` and
  must not copy hub-owned tracker artifacts, historical specs, implementation
  plans, or hub-only smoke runbooks unless a later workflow explicitly marks a
  specific artifact as required.
- Skeleton inspection is passive. It must not run sync, copy files, update a
  tracker, or inject content by itself.
- Record the selected mode in `.ai-dev-workflow.yaml` when workflow
  configuration is generated. Omitting `mode` remains equivalent to
  `single_repo`.

---

## Step 1: Introduction

Begin the conversation with:

> "Welcome! I'll help you set up the AI dev framework for your project. We'll
> first confirm whether this is a `single_repo`, `workflow_hub`, or
> `product_repo` setup, then go through the questions needed to generate your
> project documentation. You can answer as much or as little as you know right
> now — we can refine everything later.
>
> Let's start with the basics. What is the name of this project and what does it do?"

---

## Step 2: Business Domain

Ask the following questions to fill `docs/project/1-business-domain.md`. Ask them conversationally — not as a checklist dump. Adapt based on answers.

**Core questions**:

- What does this product do? What problem does it solve?
- Who are the main users? What roles exist?
- What are the core entities (the main "things" the system manages)?
- What are the key business rules or constraints that always apply?
- Is there any domain-specific vocabulary the team uses that I should know?
- What is explicitly **out of scope** for this product (now or ever)?

**Probe if needed**:

- Are there different user permissions or access levels?
- Are there any status lifecycles (e.g., an order goes from pending → active → completed)?
- Are there any third-party systems this integrates with?

---

## Step 3: Repository Architecture

Ask the following to fill `docs/project/2-repo-architecture.md`:

- Is this a monorepo or a single app?
- What are the top-level directories and what does each contain?
- Are there shared packages or libraries? What do they do and who uses them?
- What are the key development commands (install, dev server, build, test, lint)?
- How is the project deployed? Any special deployment steps?

---

## Step 4: Software Architecture & Tech Stack

Ask the following to fill `docs/project/3-software-architecture.md`:

**Stack**:

- What language(s) are used?
- What frameworks or runtimes? (e.g., Next.js, Django, Rails, Spring Boot)
- What does the frontend use? (framework, styling, component library)
- What does the backend use? (framework, ORM, API style)
- How is authentication handled?
- Where is the project hosted?
- What CI/CD tooling is used?

**Architecture decisions**:

- Any major architectural decisions already made that I should know about?
- How are environments structured (local / staging / production)?
- Any external services or third-party APIs integrated?

**Security**:

- Where is authorization enforced? (database level, API layer, frontend)
- Any specific security model I should know about?

---

## Step 5: Database Model (Conditional)

Ask:

- Does this project use a database?

If yes:

- What database engine? (PostgreSQL, MySQL, MongoDB, SQLite, etc.)
- How is the schema managed? (migrations, ORM, manual)
- What are the main tables/collections and their purpose?
- How is data access controlled? (RLS, application-level auth, etc.)
- Is there seed data? How is it loaded?

If no: skip this section and note that `docs/project/4-database-model.md` can be deleted.

---

## Step 6: Stack-Specific Best Practices

Based on the tech stack identified in Step 4 and the database info from Step 5, generate stack-specific best practices using the coordinator + detail-files pattern.

Ask:

- Are there any coding conventions already established on the team I should document?
- Any patterns you want to enforce or avoid?
- Any linting rules or formatters configured?

Then generate the following files:

**`docs/best-practices/STACK-SPECIFIC.md`** (always generated) — coordinator document with:

- **Stack Summary**: one-line list of all technologies used
- **Best Practices by Technology**: table linking to the `stack/` files below
- **Quick Reference**: the 5–10 most important cross-cutting rules for the project (the "always remember" list)

**`docs/best-practices/stack/[technology].md`** (one file per technology area) — detail documents covering:

- Naming conventions specific to that technology
- Recommended patterns and when to use them
- Anti-patterns to avoid and why
- Concrete examples where the rule isn't obvious

Generate one file per distinct technology area. Typical areas:

| Area                                                 | Generate if...                                               |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| Language (e.g., `typescript.md`, `python.md`)        | Always                                                       |
| Primary framework (e.g., `nextjs.md`, `django.md`)   | Always                                                       |
| Styling system (e.g., `tailwind.md`, `scss.md`)      | Project has a UI layer                                       |
| Database/ORM (e.g., `postgresql.md`, `prisma.md`)    | Project has a database                                       |
| API style (e.g., `rest.md`, `graphql.md`, `trpc.md`) | Project has an API with design conventions worth documenting |

Name each file after the specific technology, not the category (e.g., `typescript.md` not `language.md`).

---

## Step 7: Optional Integrations

Ask:

- If this is a `workflow_hub`, what product repositories should it know about?
  Capture stable non-secret identity only: `name`, `github_repo` or `git_url`,
  default branch, role, scope, and tracker hints.
- If this is a `product_repo`, which workflow hub owns portfolio state for this
  product repository? Capture `github_repo` or `git_url`.
- Do you use an issue tracker? (Linear, GitHub Issues, Jira, Notion, other, none)
- What Git hosting / pull-request platform do you use? (GitHub, GitLab, Bitbucket, other)
- What browser automation tool, if any, should the workflow assume for smoke tests? (Cursor browser MCP, Playwright MCP, Playwright CLI, other, none)
- Do you want to use automated PR review? (Greptile, Devin, both, other, none)
- Which internal AI reviewers should run on draft PRs before external review? (Claude, Codex, both, other, none — default: Claude only)
- Do you want branch-based CI/CD deployments? (yes/no)
  - If yes: what is the deploy branch strategy (`develop` -> non-production, `main` -> production, or custom)?
  - What deployment provider/tool should downstream repos wire in? (or `TBD`)
  - What GitHub Environments and secret names are required? (names only, never secret values)
- Do you use any MCP servers with your AI tool? (for context: Supabase, database access, etc.)

Document the answers and point to the relevant integration docs:

- Issue tracker → `docs/workflow/development-workflow/integrations/linear.md` (or note the alternative)
- Automated review → `docs/workflow/development-workflow/integrations/greptile.md` and/or `docs/workflow/development-workflow/integrations/devin.md`
- CI/CD deployment placeholders → `docs/workflow/development-workflow/integrations/ci-cd-deployment.md` (if enabled)

If the user selects any workflow integration providers, generate `.ai-dev-workflow.yaml` at the repo root. Prefer the versioned nested schema:

```yaml
schema_version: 2

mode: single_repo

review:
  on_draft:
    runner:
      - codex
    github:
      - pr-agent
  on_ready:
    github:
      - greptile

issue_tracker:
  provider: linear

vcs:
  provider: github

browser_automation:
  provider: cursor_ide_browser_mcp
```

Rules:

- Include only the sections the user actually chose.
- Include `mode` when the user selected `workflow_hub` or `product_repo`. For
  `single_repo`, including `mode: single_repo` is allowed but not required.
- For `workflow_hub`, include `workflow_hub.product_repos[]` only with stable
  non-secret fields.
- For `product_repo`, include `product_repo.workflow_hub` with the hub identity.
- Keep the file declarative; do not store secrets or tokens in it.
- `review.on_draft.runner` is consumed by the Step 7a internal review gate protocol.
- `review.on_draft.github` and `review.on_ready.github` are consumed by
  `pr-review-loop.sh` for external automated PR review.
- If the file is absent, or both GitHub review lists are omitted or empty,
  automated PR review is treated as not configured and the review loop reports
  `skipped`.

---

## Step 8: Workflow Configuration

Ask:

- Do you have a `develop` branch or do you work directly off `main`?
  - If `develop`: the workflow uses `develop` as the base branch
  - If `main` only: replace `develop` with `main` throughout the workflow docs
- Is there anything in the workflow (spec stage, plan stage, fast track criteria) you want to adjust for your team?

Note any customizations needed in `AGENTS.md` or the workflow docs.

---

## Step 9: Approval Gate

Summarize everything collected:

> "Here's what I've gathered:
>
> - **Project**: [name and description]
> - **Stack**: [summary]
> - **Repo structure**: [summary]
> - **Database**: [yes/no + engine]
> - **Integrations**: [list]
> - **Branch strategy**: [develop / main]
> - **Deployment strategy**: [enabled/disabled + branch->environment mapping + provider/tool + required environment secret names]
>
> I'll now generate the following files:
>
> - `docs/project/1-business-domain.md`
> - `docs/project/2-repo-architecture.md`
> - `docs/project/3-software-architecture.md`
> - `docs/project/4-database-model.md` (or note deletion if no DB)
> - `docs/best-practices/STACK-SPECIFIC.md` (coordinator)
> - `docs/best-practices/stack/[technology].md` × [N] files (one per technology area)
> - Updated `AGENTS.md`
> - `.ai-dev-workflow.yaml` (if integrations were selected)
>
> Shall I proceed?"

Wait for explicit approval.

---

## Step 10: Generate Files

Generate all files using the information collected. Follow the placeholder structure in each file.

**Quality rules**:

- Fill in real content based on the conversation — do not leave placeholder text where real content is known
- Where information is missing, use `> TODO: [specific question]` so the team knows what to fill in
- Keep docs concise — they will be read by AI agents on every task, so clarity and brevity matter
- Cross-reference between docs where relevant (e.g., `3-software-architecture.md` references `4-database-model.md`)
- `STACK-SPECIFIC.md` must have a complete table with working links to all `stack/` files generated
- Each `stack/[technology].md` must contain real conventions for that technology — not generic placeholders
- The Quick Reference section in `STACK-SPECIFIC.md` must reflect the project's actual priorities, not generic advice

**Update `AGENTS.md`**:

- Fill in the Project Overview section with the project description
- Fill in the Repository Structure section with a real directory tree
- Fill in the Common Commands section with the actual commands
- Update the Troubleshooting section with any project-specific tips mentioned
- Remove the "template overrides" block from the Git & Branching section (the "No `develop` branch" rule), as that only applies to the framework repository itself

---

## Step 10.5: Reset Inherited Retrospective Metrics Logs

**Self-protection (check this first, before anything else in this step)**:
this step only ever applies within a freshly bootstrapped downstream
project's own working copy. It is never appropriate to run this step against
the upstream template repository itself.

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
if grep -Eq '^\s*is_template:\s*true\s*$' .ai-dev-workflow.yaml 2>/dev/null; then
  echo "template.is_template: true — skipping Step 10.5 entirely (this is the template repository itself)."
  exit 0
fi
```

If `template.is_template` is `true`, **stop here and skip the rest of this
step** regardless of row counts — do not run the count, prompt, archive, or
reset commands below. The template's own rows are its genuine history, not
inherited data. Only continue past this point when the flag is absent or
`false`.

The template repository's own `docs/workflow/retro-metrics.md` and
`docs/workflow/retro-metrics-platforms.md` describe the **template
repository's own** batch/retrospective history. When a project is bootstrapped
from the template (cloned, or created via "Use this template"), these files
are copied verbatim along with everything else, so a freshly bootstrapped
project may already contain rows that describe someone else's PR history, not
this project's. Left in place, `06b-meta-retrospective-protocol.md` would
trend that inherited data as if it were this project's own, and the project's
first genuine retrospective row would be silently appended after it with
nothing distinguishing the two (see issue reference: retro-metrics.md ships to
downstream projects with another project's history).

**Check for inherited data** (a freshly-initialized file has 0 rows). Fails
closed — a missing file is reported explicitly rather than silently skipped,
and a read/count failure aborts with a visible error instead of resolving to
a false `0`. The counter stops at the first non-table line after the header
separator, so it only ever counts actual data rows:

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
for f in docs/workflow/retro-metrics.md docs/workflow/retro-metrics-platforms.md; do
  if [ ! -f "$f" ]; then
    echo "$f: not found (skipping)"
    continue
  fi
  if ! count=$(awk '
    /^\| *-+/ { found=1; next }
    found && /^\|/ { print; next }
    found && !/^\|/ { exit }
  ' "$f" | wc -l | tr -d ' '); then
    echo "ERROR: failed to count data rows in $f" >&2
    exit 1
  fi
  echo "$f: $count existing data row(s)"
done
```

**If both files report 0 rows**: nothing to do — skip the rest of this step.

**If either file reports 1 or more rows**: tell the human, for example:

> "`docs/workflow/retro-metrics.md` already contains N row(s) describing PR/batch
> history. Since this is a fresh project, these almost certainly describe the
> template repository's own history, not yours — carrying them forward would
> mislead the meta-retrospective protocol's trend analysis. I recommend
> archiving them to `docs/workflow/retro-metrics.inherited-<date>.md` (nothing
> is deleted) and resetting the tracked file to header-only so your own
> retrospectives start a clean, accurate log. Proceed? (recommended: yes)"

Ask the same question for `retro-metrics-platforms.md` if it also reports rows.
**Do not archive or reset either file without an explicit "yes" from the human
for that specific file** — this is a project-owned log, and a human who
deliberately wants to keep the inherited rows (for example, a fork of an
established downstream project rather than a fresh bootstrap) must be able to
decline.

**On explicit approval**, for each approved file: archive first, refusing to
overwrite an existing archive from an earlier attempt, and only reset once the
archive is confirmed written — if archiving fails or an archive already
exists, stop before touching the tracked file:

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
today="$(date +%Y-%m-%d)"
archive="docs/workflow/retro-metrics.inherited-${today}.md"
if [ -e "$archive" ]; then
  echo "ERROR: archive destination already exists: $archive — refusing to overwrite. Resolve manually (e.g. rename the prior archive) before re-running this step." >&2
  exit 1
fi
cp docs/workflow/retro-metrics.md "$archive"
# Reset: keep the preamble and table header/separator rows, drop all data rows below them.
awk '
  /^\| *-+/ { print; found=1; next }
  found && /^\|/ { next }
  { print }
' docs/workflow/retro-metrics.md > docs/workflow/retro-metrics.md.tmp \
  && mv docs/workflow/retro-metrics.md.tmp docs/workflow/retro-metrics.md
```

Apply the equivalent commands for `docs/workflow/retro-metrics-platforms.md`
when approved (same archive-then-reset pattern, substituting the file name).
Verify each reset file still has its header/preamble intact and zero data
rows before continuing, then include the archive file(s) and reset file(s) in
the Step 11 commit below.

---

## Step 11: Git Execution

After generating all files:

1. Create branch: `git checkout -b setup/project-documentation` from the default branch
2. Write all generated files (including any retro-metrics archive/reset files from Step 10.5)
3. Stage everything generated in this run, including the Step 10.5 archive and
   reset files (`git commit` only picks up staged changes — untracked archive
   files and the reset log would otherwise be silently omitted): `git add -A`
4. Commit: `docs: initialize project documentation via setup agent`
5. Push and open PR targeting the default branch with:
   - Title: `docs: initialize project documentation`
   - Body: summary of what was generated, list of TODOs for the team to review

---

## Step 12: Next Steps

After the PR is opened, tell the human:

> "The setup PR is open. Before merging, review the generated docs and fill in any `TODO` items.
>
> Once merged, you're ready to start development. To kick off your first feature:
>
> - Claude Code: use the `product-manager` agent
> - Cursor: run `/generate-new-feature`
> - Any other tool: ask your AI to follow `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`"
