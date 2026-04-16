# AI Dev Framework Template

A tool-agnostic framework for AI-assisted software development. It structures the entire development lifecycle — from idea to production — with canonical protocols that any AI coding assistant can follow: Claude Code, Cursor, Codex, Gemini CLI, or any other tool.

## What This Is

This template provides:

- **A staged development workflow** (Spec → Plan → Implement → Review → Release) with persistent orchestration until PRs are actually clean
- **Canonical protocol documents** that AI agents execute — one per workflow stage
- **Thin tool wrappers** for Claude Code (`.claude/agents/`), Cursor (`.cursor/agents/`, `.cursor/commands/`), and Codex (`.codex/skills/`) that point to those protocols
- **A guided project setup** so any AI assistant can help you fill in the project-specific docs

The key principle: **protocols live in `docs/`** and are tool-agnostic. Tool-specific configs (`.claude/`, `.cursor/`) are thin wrappers that reference those protocols. Add support for a new AI tool by creating a thin wrapper — no protocol duplication needed.

---

## Getting Started: Project Setup

When you first clone this template into a new project, run the **Project Setup** workflow to generate your project-specific documentation:

### With Claude Code
```
Use the project-setup agent: Task the agent with "Initialize this project using the setup protocol"
```

### With Cursor
```
/setup-project
```

### With any other AI tool
Ask your AI assistant to:
```
Follow the project setup protocol at docs/ai/setup/protocol.md
```

The setup agent will have a structured conversation with you to understand your project, then generate:
- `docs/project/1-business-domain.md` — Domain model, entities, business rules
- `docs/project/2-repo-architecture.md` — Monorepo/repository structure
- `docs/project/3-software-architecture.md` — Tech stack, design patterns, architectural decisions
- `docs/project/4-database-model.md` — Data model (if applicable)
- `docs/best-practices/STACK-SPECIFIC.md` — Best practices tailored to your stack
- Updated `AGENTS.md` with your project context

---

## Repository Structure

```
├── AGENTS.md                              # Universal AI guidance (all tools read this)
├── CLAUDE.md -> AGENTS.md                 # Symlink for Claude Code
├── CHANGELOG.md
├── e2e/                                   # Placeholder e2e/regression test project (Playwright)
│   ├── playwright.config.ts               # Minimal Playwright config
│   ├── tests/
│   │   └── baseline.spec.ts               # Always-passing placeholder test
│   └── package.json
├── .github/
│   └── workflows/
│       ├── auto-tag-release.yml           # Tags release branches after merge to main
│       ├── deploy.yml                     # Placeholder branch-based deployment workflow
│       └── e2e-regression.yml             # Label-gated e2e/regression placeholder
│
├── docs/
│   ├── README.md                          # Documentation index
│   │
│   ├── project/                           # Project-specific docs (fill via setup agent)
│   │   ├── 1-business-domain.md           # PLACEHOLDER
│   │   ├── 2-repo-architecture.md         # PLACEHOLDER
│   │   ├── 3-software-architecture.md     # PLACEHOLDER
│   │   └── 4-database-model.md            # PLACEHOLDER (delete if no DB)
│   │
│   ├── best-practices/                    # Coding standards and conventions
│   │   ├── 1-general.md                   # General development standards
│   │   ├── 2-version-control.md           # Git conventions
│   │   ├── 3-testing.md                   # Testing standards
│   │   └── STACK-SPECIFIC.md              # PLACEHOLDER (fill via setup agent)
│   │
│   └── ai/
│       └── development-workflow/
│           ├── README.md                  # Master workflow document
│           ├── agent-model-config.md      # Model tier policy and overrides
│           ├── protocols/                 # Canonical stage protocols
│           │   ├── 01-generate-spec-protocol.md
│           │   ├── 01-review-spec-protocol.md
│           │   ├── 02-generate-implementation-plan-protocol.md
│           │   ├── 02-review-implementation-plan-protocol.md
│           │   ├── 03-implement-development-protocol.md
│           │   ├── 03-review-implementation-protocol.md
│           │   ├── 04-smoke-test-protocol.md
│           │   ├── 05-prepare-release-protocol.md
│           │   ├── 90-batch-orchestrate-work-protocol.md
│           │   ├── 91-orchestrate-work-protocol.md
│           │   ├── 92-pr-readiness-signal-protocol.md
│           │   └── 93-automated-reviewer-loop-protocol.md
│           ├── templates/                 # Spec, plan, and test templates
│           │   ├── spec-template.md
│           │   ├── implementation-plan-template.md
│           │   └── smoke-test-runbook-template.md
│           └── integrations/             # Optional tool integrations
│               ├── linear.md             # Issue tracker integration (Linear)
│               ├── greptile.md           # Automated PR review (Greptile)
│               ├── github-projects.md    # GitHub Projects board integration
│               ├── ci-cd-deployment.md   # CI/CD deployment placeholders and customization
│               └── e2e-regression.md     # E2E/regression test integration
│
├── .codex/
│   └── skills/                           # Codex skills that wrap the workflow protocols and ship UI metadata
│
├── scripts/
│   ├── development-workflow/            # AI workflow helpers (orchestrator, PR/CI loops, state discovery)
│   │   ├── add-backlog-item.sh          # Resolves tracker destination; creates GitHub issues when configured
│   │   ├── discover-workflow-state.sh   # Summarizes branches, worktrees, development folders, and open PRs
│   │   ├── check-workflow-branch.sh     # Checks whether a workflow branch already exists
│   │   ├── pr-review-loop.sh      # Polls Greptile PR review until clean / fix / escalate
│   │   ├── pr-ci-loop.sh                # Polls CI checks until green / red / timeout
│   │   ├── workflow-batch-plan.sh       # Classifies development folders into batch-planning candidates
│   │   ├── workflow-next-action.sh      # Classifies the next deterministic workflow action
│   │   └── install-codex-skills.sh      # (Codex only) Installs repo skills into your local Codex config
│   └── README.md                        # Points to development-workflow; add your own scripts here
│
├── .claude/
│   └── agents/                           # Claude Code subagent definitions
│       ├── project-setup.md
│       ├── product-manager.md
│       ├── spec-reviewer.md
│       ├── tech-lead.md
│       ├── implementation-plan-reviewer.md
│       ├── developer.md
│       ├── code-reviewer.md
│       ├── item-orchestrator.md
│       └── orchestrator.md
│
└── .cursor/
    ├── rules/                            # Cursor context rules
    ├── agents/                           # Cursor workflow subagents (orchestrator, item-orchestrator, developer, etc.)
    └── commands/                         # Cursor slash commands
```

---

## The Development Workflow

```
Backlog
  │
  ▼  /generate-new-feature / product-manager agent
Spec Ready ──────────────────────────────── (Human approves PR)
  │
  ▼  /generate-implementation-plan / tech-lead agent
Plan Ready ──────────────────────────────── (Human approves PR)
  │
  ▼  /implement-development / developer agent
In Development ─────────────────────────── (Human approves PR)
  │
  ▼
Merged
  │
  ▼  /prepare-release
Released
```

**Special paths:**
- **Refactor** (`refactor/[slug]` from develop): code restructuring or tech-debt cleanup with a plan but no spec
- **Fast Track** (`fix/[slug]` from develop): bugs and simple changes that don't need a spec or plan
- **Hotfix** (`hotfix/[slug]` from main): critical production bugs that need immediate deployment

See [`docs/ai/development-workflow/README.md`](docs/ai/development-workflow/README.md) for the full workflow specification.

---

## Using With Different AI Tools

### Claude Code
- Agents are defined in `.claude/agents/`
- `CLAUDE.md` (symlink to `AGENTS.md`) is auto-loaded
- Invoke agents via the Task tool or by mentioning the agent name

Example prompts:

```text
Use the orchestrator agent to inspect this repository's AI development workflow state, determine what work can safely advance next, and keep advancing each eligible item until it reaches a real terminal condition. Follow AGENTS.md and the workflow protocols exactly. If multiple items are eligible, prioritize by the documented rules and explain any blockers or escalations.
```

```text
Use the orchestrator agent to review the current backlog, specs, plans, branches, and open PRs in this repository, then keep advancing eligible work until each item reaches a real terminal condition. Minimize human interaction, but stop for human decisions, merge review, blocked dependencies, or escalations.
```

```text
Use the item-orchestrator agent to start and advance work for [feature or issue name]. Resolve the request to one workflow item, then keep progressing that item through creator, reviewer, PR, automated review, and CI until it is waiting on a human, blocked, or escalated.
```

### Cursor
- Rules in `.cursor/rules/` provide automatic context
- Commands in `.cursor/commands/` are invoked with `/command-name`
- Workflow agents in `.cursor/agents/` (e.g. `/developer`, `/orchestrator`, `/item-orchestrator`) run stage-specific protocols; see `docs/ai/development-workflow/agent-model-config.md` for model config
- MCP servers can be configured in `.cursor/.mcp.json`

Example commands:

```text
/run-work
```

```text
/run-work Review the current backlog, specs, plans, branches, and open PRs in this repository, then keep advancing eligible work until each item reaches a real terminal condition. Minimize human interaction, but stop for human decisions, merge review, blocked dependencies, or escalations.
```

```text
/run-work Start and advance work for [feature or issue name]. Inspect the current workflow state first, then keep progressing that item through creator, reviewer, PR, automated review, and CI until it is waiting on a human, blocked, or escalated.
```

```text
/run-item-work Start and advance work for [feature or issue name]. Resolve the request to one workflow item, then keep progressing that item through creator, reviewer, PR, automated review, and CI until it is waiting on a human, blocked, or escalated.
```

### Codex
- Install the bundled skills with `./scripts/development-workflow/install-codex-skills.sh`
- Start with `workflow-orchestrator` as the default portfolio-wide entrypoint for the workflow
- Run `workflow-orchestrator` on an `economy` tier by default; only escalate when the stage-specific skill recommends it
- Use `workflow-item-orchestrator` when you want to resume or advance one specific development, branch, or PR
- Use the other skills in `.codex/skills/` when you want to run a specific stage directly
- The skills are thin wrappers around the same protocol docs used by the other tools
- Each skill can also ship `agents/openai.yaml` metadata for cleaner labels and starter prompts in Codex-compatible UIs

Example prompts:

```text
Use $workflow-orchestrator to inspect this repository's AI development workflow state, determine what work can safely advance next, and keep advancing each eligible item until it reaches a real terminal condition. Follow AGENTS.md and the workflow protocols exactly. If multiple items are eligible, prioritize by the documented rules and explain any blockers or escalations.
```

```text
Use $workflow-orchestrator to review the current backlog, specs, plans, branches, and open PRs in this repository, then keep advancing eligible work until each item reaches a real terminal condition. Minimize human interaction, but stop for human decisions, merge review, blocked dependencies, or escalations.
```

```text
Use $workflow-item-orchestrator to start and advance work for [feature or issue name]. Resolve the request to one workflow item, then keep progressing that item through creator, reviewer, PR, automated review, and CI until it is waiting on a human, blocked, or escalated.
```

### Other AI Tools (Gemini CLI, etc.)
- Point your tool at `AGENTS.md` for project context
- Ask it to follow protocols in `docs/ai/development-workflow/protocols/`
- The protocols are plain markdown — any AI can follow them

---

## Optional Integrations

- **Issue Tracker (e.g., Linear)**: See [`docs/ai/development-workflow/integrations/linear.md`](docs/ai/development-workflow/integrations/linear.md)
- **Automated PR Review (e.g., Greptile)**: See [`docs/ai/development-workflow/integrations/greptile.md`](docs/ai/development-workflow/integrations/greptile.md)
- **GitHub Projects board**: See [`docs/ai/development-workflow/integrations/github-projects.md`](docs/ai/development-workflow/integrations/github-projects.md)
- **CI/CD deployment placeholders**: See [`docs/ai/development-workflow/integrations/ci-cd-deployment.md`](docs/ai/development-workflow/integrations/ci-cd-deployment.md)

---

## Mandatory Conventions

- **CHANGELOG.md is required**: every feature/fix/hotfix PR must add an entry under `[Unreleased]` before merge, with exceptions for spec/plan-only PRs (no entry needed) and fixes to unreleased work (update the existing entry instead of adding a new one). Never defer CHANGELOG entries to release time. In parallel batches, each PR adds its own CHANGELOG entry as normal; merge conflicts are resolved by batch-merge auto-resolution at merge time.
- **Human merge gates**: PRs for spec, plan, and implementation are opened by agents and kept moving until they are actually review-ready; humans still review and merge them.
- **No destructive Git operations** without explicit human approval (no `--force`, `reset --hard`, `rebase` on shared branches).

---

## Managing This Template Alongside Your Projects

### Recommended local setup

```
~/Git/
├── ai-dev-framework-template/   ← this repo (upstream)
├── project-a/                   ← downstream: has its own copy of framework files
├── project-b/                   ← downstream: has its own copy of framework files
└── ...
```

Each project created from this template carries its own copy of the framework files. This keeps projects fully self-contained — every team member, CI/CD system, and AI agent has access to the docs without external dependencies.

### Starting a new project

1. Click **"Use this template"** on GitHub to create a new repository
2. Clone it locally
3. Run the setup agent to generate project-specific docs (see [Getting Started](#getting-started-project-setup))

### Propagating framework improvements to existing projects

When you improve a protocol, agent, or best practice in this template repo, copy the framework-level files into existing projects and commit the changes there.

Framework-level paths to propagate:

- `docs/ai/`
- `.claude/agents/`
- `.claude/skills/`
- `.codex/skills/`
- `.cursor/rules/`
- `.cursor/agents/`
- `.cursor/commands/`
- `scripts/development-workflow/install-codex-skills.sh`
- `scripts/development-workflow/add-backlog-item.sh`
- `scripts/development-workflow/discover-workflow-state.sh`
- `scripts/development-workflow/check-workflow-branch.sh`
- `docs/best-practices/1-general.md`
- `docs/best-practices/2-version-control.md`
- `docs/best-practices/3-testing.md`

Project-specific paths to avoid overwriting:

- `docs/project/`
- `AGENTS.md`
- `README.md`
- `CHANGELOG.md`
- `docs/best-practices/STACK-SPECIFIC.md`

#### Using the sync-template skill (Claude Code / Cursor)

If your project has the `.claude/skills/sync-template.md` skill, you can automate this process:

| Tool | Command |
|---|---|
| Claude Code | `/sync-template` |
| Cursor | `/sync-template` |

The skill compares your project against the template, shows exactly what changed (categorized by auto-apply vs. manual review vs. skipped), and applies updates only after your explicit approval. It also generates ready-to-use git instructions for branching, committing, and opening a PR.

On first run, the skill will ask you for the template source (local path or remote URL) and save it to `.tmp/template-config.json` for future runs (`.tmp/` is gitignored).

### Backporting improvements from a project to the template

When you improve a framework file while working on a specific project, port the relevant changes back into this template repo via a normal PR (copy only the framework-level paths listed above, and avoid importing project-specific content).

### Setting GitHub as a template repository

To enable the **"Use this template"** button on GitHub:

1. Go to the repository **Settings**
2. Under **General**, check **"Template repository"**
3. Save

New projects will be created as independent repositories (not forks), with a clean Git history.
