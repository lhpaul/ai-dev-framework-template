# AGENTS.md

This is the primary AI agent guidance file for this project. It follows the [AGENTS.md](https://github.com/agentsmd/agents.md) open format and is read by all AI coding assistants (Claude Code, Cursor, Codex, Gemini CLI, etc.).

> **Note for Claude Code users**: `CLAUDE.md` is a symlink to this file.

---

## Project Overview

> **TODO**: Fill this section via the project setup agent (`docs/ai/setup/protocol.md`), or manually describe your project here.
>
> - What does this project do?
> - Who are the users?
> - What problem does it solve?

---

## Repository Structure

> **TODO**: Fill this section after running the project setup. Reference `docs/project/2-repo-architecture.md` for details.

---

## Key Documentation

Always refer to these docs for authoritative guidance:

| Document | Purpose |
|---|---|
| [`docs/project/1-business-domain.md`](docs/project/1-business-domain.md) | Domain entities, business rules, glossary |
| [`docs/project/2-repo-architecture.md`](docs/project/2-repo-architecture.md) | Repository structure, packages, apps |
| [`docs/project/3-software-architecture.md`](docs/project/3-software-architecture.md) | Tech stack, design patterns, architecture decisions |
| [`docs/project/4-database-model.md`](docs/project/4-database-model.md) | Data model, schema, access patterns (if applicable) |
| [`docs/best-practices/1-general.md`](docs/best-practices/1-general.md) | General coding standards |
| [`docs/best-practices/2-version-control.md`](docs/best-practices/2-version-control.md) | Git conventions |
| [`docs/best-practices/3-testing.md`](docs/best-practices/3-testing.md) | Testing standards |
| [`docs/best-practices/STACK-SPECIFIC.md`](docs/best-practices/STACK-SPECIFIC.md) | Stack-specific conventions |
| [`docs/ai/development-workflow/README.md`](docs/ai/development-workflow/README.md) | AI development workflow (master doc) |

---

## Development Workflow

This project uses a staged AI-assisted development workflow. See [`docs/ai/development-workflow/README.md`](docs/ai/development-workflow/README.md) for the full specification.

### Workflow Commands

| Stage | Claude Code | Cursor | Any other tool |
|---|---|---|---|
| Project Setup | `project-setup` agent | `@setup-project` | Follow `docs/ai/setup/protocol.md` |
| Write Spec | `product-manager` agent | `@generate-new-feature` | Follow `docs/ai/development-workflow/protocols/01-generate-specs-protocol.md` |
| Review Spec | `spec-reviewer` agent | `@review-spec` | Follow `docs/ai/development-workflow/protocols/01-review-specs-protocol.md` |
| Write Plan | `tech-lead` agent | `@generate-implementation-plan` | Follow `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Review Plan | `implementation-plan-reviewer` agent | `@review-implementation-plan` | Follow `docs/ai/development-workflow/protocols/02-review-implementation-plan-protocol.md` |
| Implement | `developer` agent | `@implement-development` | Follow `docs/ai/development-workflow/protocols/04-implement-development-protocol.md` |
| Review Code | `code-reviewer` agent | `@review-code` | Follow `docs/ai/development-workflow/protocols/04-review-implemented-development-protocol.md` |
| Prepare Commit | — | `@prepare-commit` | Follow `docs/best-practices/2-version-control.md` |
| Prepare Release | — | `@prepare-release` | Follow workflow README release section |
| Orchestrate Work | `orchestrator` agent | `@run-work` | Follow `docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md` |

---

## Common Commands

> **TODO**: Fill with your project's actual commands after setup.

```bash
# Development
# [your dev server command]

# Build
# [your build command]

# Test
# [your test command]

# Lint / Format
# [your lint/format commands]
```

---

## Important Conventions

### Git & Branching

- Follow conventions in `docs/best-practices/2-version-control.md`
- Branch naming:
  - Features: `feature/[feature-slug]`
  - Bugs (fast track): `fix/[slug]`
  - Hotfixes: `hotfix/[slug]` from `main`
  - Specs: `spec/[feature-slug]`
  - Implementation plans: `implementation-plan/[feature-slug]`
  - Releases: `release/v[X.Y.Z]`

### CHANGELOG

- **Every PR must add a `[Unreleased]` entry** in `CHANGELOG.md` before merge
- Never defer CHANGELOG entries to release time
- Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format

### Safety Rules

- **No `git push --force`**, `git reset --hard`, or rebase on shared branches without explicit human approval
- **Stop and ask** if an action seems destructive or has wide blast radius
- Human approval is required before opening PRs for spec, plan, and implementation stages

---

## Troubleshooting

> **TODO**: Add project-specific troubleshooting tips here after setup.
