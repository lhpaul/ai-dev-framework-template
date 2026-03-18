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
| [`REVIEW.md`](REVIEW.md) | Canonical review contract for spec, plan, and code review gates |
| [`docs/ai/development-workflow/README.md`](docs/ai/development-workflow/README.md) | AI development workflow (master doc) |
| [`docs/ai/development-workflow/agent-model-config.md`](docs/ai/development-workflow/agent-model-config.md) | Model assignments, tool restrictions, and override guide for all agents |

> **Note for Cursor users**: Workflow agents are also available as Cursor subagents in `.cursor/agents/`. Invoke them directly (e.g., `/developer`, `/orchestrator`, `/item-orchestrator`) or let Agent delegate to them. Each subagent's model is configured in its file — see [`docs/ai/development-workflow/agent-model-config.md`](docs/ai/development-workflow/agent-model-config.md) for how to set or override models.

---

## Development Workflow

This project uses a staged AI-assisted development workflow. See [`docs/ai/development-workflow/README.md`](docs/ai/development-workflow/README.md) for the full specification.

### Workflow Commands

| Stage | Claude Code | Cursor | Codex | Any other tool |
|---|---|---|---|---|
| Project Setup | `project-setup` agent | `/setup-project` | `workflow-project-setup` skill | Follow `docs/ai/setup/protocol.md` |
| Write Spec | `product-manager` agent | `/generate-new-feature` | `workflow-spec-writer` skill | Follow `docs/ai/development-workflow/protocols/01-generate-specs-protocol.md` |
| Write Plan | `tech-lead` agent | `/generate-implementation-plan` | `workflow-plan-writer` skill | Follow `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Implement | `developer` agent | `/implement-development` | `workflow-implementer` skill | Follow `docs/ai/development-workflow/protocols/04-implement-development-protocol.md` |
| Review Gate (Spec / Plan / Code) | Native review against `REVIEW.md` | `/review-spec`, `/review-implementation-plan`, `/review-code` | Native review against `REVIEW.md` | Follow `REVIEW.md` and the compatibility wrapper protocols under `docs/ai/development-workflow/protocols/` when needed |
| Smoke Test | `smoke-tester` agent | `/smoke-tester` | — | Follow `docs/ai/development-workflow/protocols/05-smoke-test-protocol.md` |
| Run reviewer loop (PR) | `/run-reviewer-loop` command (or `automated-reviewer-loop` agent) | `/run-reviewer-loop` | `workflow-reviewer-loop` skill | Follow `docs/ai/development-workflow/protocols/92-automated-reviewer-loop-protocol.md` |
| Advance One Item | `/run-item-work` command (or `item-orchestrator` agent) | `/run-item-work` | `workflow-item-orchestrator` skill | Follow `docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md` |
| Prepare Commit | — | `/prepare-commit` | Follow `docs/best-practices/2-version-control.md` | Follow `docs/best-practices/2-version-control.md` |
| Prepare Release | `/prepare-release` | `/prepare-release` | Follow `docs/ai/development-workflow/protocols/06-prepare-release-protocol.md` | Follow `docs/ai/development-workflow/protocols/06-prepare-release-protocol.md` |
| Orchestrate Work | `orchestrator` agent | `/run-work` | `workflow-orchestrator` skill | Follow `docs/ai/development-workflow/protocols/89-batch-orchestrate-work-protocol.md` |

### Codex Skills

The repository ships Codex skill definitions in `.codex/skills/`. Install them into your local Codex skill directory before first use:

```bash
./scripts/development-workflow/install-codex-skills.sh
```

Installed skills are thin wrappers around the canonical workflow protocols. They do not redefine the workflow; they load the same documents used by other tools and, for orchestration, rely on the helper scripts in `scripts/development-workflow/` to inspect state, resume partial work, and resolve PR readiness deterministically. The bundled skills also include optional `agents/openai.yaml` metadata so downstream projects created from this template have cleaner Codex skill labels and default prompts out of the box.

For normal Codex usage, start with `workflow-orchestrator`. It is the primary portfolio-wide entrypoint: it discovers eligible items, builds safe parallel batches, and routes each item into `workflow-item-orchestrator`. Run it on an `economy` tier by default, then escalate only when the routed stage recommends a higher tier. Use `workflow-item-orchestrator` when you already know the exact development / branch / PR to resume. Whether work is batch-orchestrated or item-scoped, runs should continue until they reach a real terminal condition: waiting on human review / merge, blocked dependency, unresolved decision, or escalation. For review gates, prefer the runner's native review capability against `REVIEW.md`; use the compatibility wrapper protocols only when a command, skill, or legacy workflow explicitly points to them.

### Maintenance Commands

| Task | Claude Code | Cursor | Codex |
|---|---|---|---|
| Sync framework updates from template | `/sync-template` | `/sync-template` | — |
| Post-merge cleanup (fetch, develop, pull, delete local branch; update issue tracker) | `/post-merge-cleanup` | `/post-merge-cleanup` | `post-merge-cleanup` skill |

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

This repository follows the default template workflow (documented in `docs/ai/development-workflow/`).

- Integration branch: `develop` (spec/plan/feature/fix PRs target `develop`)
- Release branch: `main` (release PR targets `main`, plus a mandatory backport PR to `develop`)
- Branch naming:
  - Features / improvements: `feature/[feature-slug]` (from `develop`)
  - Bug fixes (fast track): `fix/[slug]` (from `develop`)
  - Hotfixes: `hotfix/[slug]` (from `main`, then backport to `develop`)
  - Releases: `release/v[X.Y.Z]` (from `develop`)

### CHANGELOG & Versioning

- Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.
- Use [Semantic Versioning](https://semver.org/): patch for fixes/tweaks, minor for new features or meaningful improvements, major for breaking changes to the template structure.
- **Feature and fix PRs** merged into `develop` add entries under `[Unreleased]` in `CHANGELOG.md`; do not convert to a version number on merge.
- **A new version is created only when releasing**: run the Prepare Release workflow (`/prepare-release` or `docs/ai/development-workflow/protocols/06-prepare-release-protocol.md`). That creates a `release/v[X.Y.Z]` branch, renames `[Unreleased]` to `[X.Y.Z]` in the CHANGELOG, and opens PRs to `main` and backport to `develop`.

### Stack Conventions

Read [`docs/best-practices/STACK-SPECIFIC.md`](docs/best-practices/STACK-SPECIFIC.md) for the stack summary and the most important cross-cutting rules. For detailed conventions per technology, see the files in [`docs/best-practices/stack/`](docs/best-practices/stack/).

### Safety Rules

- **No `git push --force`**, `git reset --hard`, or rebase on shared branches without explicit human approval
- **Stop and ask** if an action seems destructive or has wide blast radius
- Human review is required before merging PRs; opening a PR is not a terminal condition by itself

---

## Troubleshooting

> **TODO**: Add project-specific troubleshooting tips here after setup.
