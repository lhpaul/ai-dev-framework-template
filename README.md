# AI Dev Framework Template

A tool-agnostic framework for AI-assisted software development. It structures the entire development lifecycle — from idea to production — with canonical protocols that any AI coding assistant can follow: Claude Code, Cursor, Codex, Gemini CLI, or any other tool.

## What This Is

This template provides:

- **A staged development workflow** (Spec → Plan → Implement → Review → Release) with clear human approval gates
- **Canonical protocol documents** that AI agents execute — one per workflow stage
- **Agent definitions** for Claude Code (`.claude/agents/`) and Cursor (`.cursor/commands/`) that point to those protocols
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
@setup-project
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
│           ├── tooling-assumptions.md     # Required vs optional tools
│           ├── protocols/                 # Canonical stage protocols
│           │   ├── 01-generate-specs-protocol.md
│           │   ├── 01-review-specs-protocol.md
│           │   ├── 02-generate-implementation-plan-protocol.md
│           │   ├── 02-review-implementation-plan-protocol.md
│           │   ├── 04-implement-development-protocol.md
│           │   ├── 04-review-implemented-development-protocol.md
│           │   ├── 90-orchestrate-work-protocol.md
│           │   └── 91-pr-readiness-signal-protocol.md
│           ├── templates/                 # Spec, plan, and test templates
│           │   ├── spec-template.md
│           │   ├── implementation-plan-template.md
│           │   └── smoke-test-runbook-template.md
│           └── integrations/             # Optional tool integrations
│               ├── linear.md             # Issue tracker integration (Linear)
│               └── greptile.md           # Automated PR review (Greptile)
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
│       └── orchestrator.md
│
└── .cursor/
    ├── rules/                            # Cursor context rules
    └── commands/                         # Cursor slash commands
```

---

## The Development Workflow

```
Backlog
  │
  ▼  @generate-new-feature / product-manager agent
Spec Ready ──────────────────────────────── (Human approves PR)
  │
  ▼  @generate-implementation-plan / tech-lead agent
Plan Ready ──────────────────────────────── (Human approves PR)
  │
  ▼  @implement-development / developer agent
In Development ─────────────────────────── (Human approves PR)
  │
  ▼
Merged
  │
  ▼  @prepare-release
Released
```

**Special paths:**
- **Fast Track** (`fix/[slug]` from default branch): bugs and simple changes that don't need a spec or plan
- **Hotfix** (`hotfix/[slug]` from main): critical production bugs that need immediate deployment

See [`docs/ai/development-workflow/README.md`](docs/ai/development-workflow/README.md) for the full workflow specification.

---

## Using With Different AI Tools

### Claude Code
- Agents are defined in `.claude/agents/`
- `CLAUDE.md` (symlink to `AGENTS.md`) is auto-loaded
- Invoke agents via the Task tool or by mentioning the agent name

### Cursor
- Rules in `.cursor/rules/` provide automatic context
- Commands in `.cursor/commands/` are invoked with `@command-name`
- MCP servers can be configured in `.cursor/.mcp.json`

### Other AI Tools (Codex, Gemini CLI, etc.)
- Point your tool at `AGENTS.md` for project context
- Ask it to follow protocols in `docs/ai/development-workflow/protocols/`
- The protocols are plain markdown — any AI can follow them

---

## Optional Integrations

- **Issue Tracker (e.g., Linear)**: See [`docs/ai/development-workflow/integrations/linear.md`](docs/ai/development-workflow/integrations/linear.md)
- **Automated PR Review (e.g., Greptile)**: See [`docs/ai/development-workflow/integrations/greptile.md`](docs/ai/development-workflow/integrations/greptile.md)

---

## Mandatory Conventions

- **CHANGELOG.md is required**: every feature/fix/hotfix PR must add an entry under `[Unreleased]` before merge. Never defer CHANGELOG entries to release time.
- **Human approval gates**: PRs for spec, plan, and implementation are opened by agents but merged by humans.
- **No destructive Git operations** without explicit human approval (no `--force`, `reset --hard`, `rebase` on shared branches).
