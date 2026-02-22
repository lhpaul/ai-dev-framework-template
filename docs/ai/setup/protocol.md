# Protocol: Project Setup (Onboarding)

**Agent role**: Project Setup
**Purpose**: Guide a structured conversation to generate all project-specific documentation and configure the framework for a new project.

This protocol is **tool-agnostic**. It is invoked via:
- Claude Code: `project-setup` agent
- Cursor: `@setup-project` command
- Any other AI tool: "Follow the setup protocol at `docs/ai/setup/protocol.md`"

---

## Overview

When a team clones this template, the project-specific docs (`docs/project/`) are empty placeholders, `AGENTS.md` has a generic project description, and `docs/best-practices/STACK-SPECIFIC.md` is empty.

This protocol fills all of that in through a structured conversation with the human. At the end, the AI commits the generated docs to a setup branch and opens a PR.

Estimated time: 20–45 minutes depending on project complexity.

---

## Step 1: Introduction

Begin the conversation with:

> "Welcome! I'll help you set up the AI dev framework for your project. We'll go through a series of questions to generate your project documentation. You can answer as much or as little as you know right now — we can refine everything later.
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

Based on the tech stack identified in Step 4, generate appropriate best practices for `docs/best-practices/STACK-SPECIFIC.md`.

Ask:
- Are there any coding conventions already established on the team I should document?
- Any patterns you want to enforce or avoid?
- Any linting rules or formatters configured?

Then generate the STACK-SPECIFIC.md based on the stack and any conventions provided. Cover:
- Language-specific conventions (naming, types, patterns)
- Framework-specific patterns and anti-patterns
- Styling/UI conventions (if applicable)
- Database/ORM conventions (if applicable)
- API design conventions (if applicable)

---

## Step 7: Optional Integrations

Ask:
- Do you use an issue tracker? (Linear, GitHub Issues, Jira, Notion, other, none)
- Do you want to use automated PR review? (Greptile, CodeRabbit, other, none)
- Do you use any MCP servers with your AI tool? (for context: Supabase, database access, etc.)

Document the answers and point to the relevant integration docs:
- Issue tracker → `docs/ai/development-workflow/integrations/linear.md` (or note the alternative)
- Automated review → `docs/ai/development-workflow/integrations/greptile.md` (or note the alternative)

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
> - **Project**: [name and description]
> - **Stack**: [summary]
> - **Repo structure**: [summary]
> - **Database**: [yes/no + engine]
> - **Integrations**: [list]
> - **Branch strategy**: [develop / main]
>
> I'll now generate the following files:
> - `docs/project/1-business-domain.md`
> - `docs/project/2-repo-architecture.md`
> - `docs/project/3-software-architecture.md`
> - `docs/project/4-database-model.md` (or note deletion if no DB)
> - `docs/best-practices/STACK-SPECIFIC.md`
> - Updated `AGENTS.md`
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

**Update `AGENTS.md`**:
- Fill in the Project Overview section with the project description
- Fill in the Repository Structure section with a real directory tree
- Fill in the Common Commands section with the actual commands
- Update the Troubleshooting section with any project-specific tips mentioned

---

## Step 11: Git Execution

After generating all files:

1. Create branch: `git checkout -b setup/project-documentation` from the default branch
2. Write all generated files
3. Commit: `docs: initialize project documentation via setup agent`
4. Push and open PR targeting the default branch with:
   - Title: `docs: initialize project documentation`
   - Body: summary of what was generated, list of TODOs for the team to review

---

## Step 12: Next Steps

After the PR is opened, tell the human:

> "The setup PR is open. Before merging, review the generated docs and fill in any `TODO` items.
>
> Once merged, you're ready to start development. To kick off your first feature:
> - Claude Code: use the `product-manager` agent
> - Cursor: run `@generate-new-feature`
> - Any other tool: ask your AI to follow `docs/ai/development-workflow/protocols/01-generate-specs-protocol.md`"
