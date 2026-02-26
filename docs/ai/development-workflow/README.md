# AI-Assisted Development Workflow

This document is the **canonical master reference** for how development is structured in this project. AI agents and human team members follow this workflow.

**Core principle**: AI agents handle execution; humans participate at two points per stage — giving direction at the start and reviewing the output (via PR) at the end.

---

## Workflow Stages

```
┌─────────────────────────────────────────────────────────────────┐
│                         BACKLOG                                 │
│   Ideas, bugs, improvements tracked in your issue tracker       │
└─────────────────────┬───────────────────────────────────────────┘
                      │  Human: decide to start a feature
                      │  AI: product-manager agent dispatched
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SPEC IN REVIEW                               │
│   Spec PR open; pending human review and merge                  │
│   Branch: spec/[feature-slug]                                   │
│   Protocol: 01-generate-specs-protocol.md                       │
└─────────────────────┬───────────────────────────────────────────┘
                      │  Human: merge spec PR
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                       SPEC READY                                │
│   Spec merged; implementation plan pending                      │
│   AI: tech-lead agent dispatched                                │
└─────────────────────┬───────────────────────────────────────────┘
                      │  AI: implementation-plan-reviewer dispatched
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PLAN IN REVIEW                               │
│   Implementation plan PR open; pending human review and merge   │
│   Branch: implementation-plan/[feature-slug]                    │
│   Protocol: 02-generate-implementation-plan-protocol.md         │
└─────────────────────┬───────────────────────────────────────────┘
                      │  Human: merge plan PR
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                      PLAN READY                                 │
│   Plan merged; ready for implementation                         │
│   AI: developer agent dispatched                                │
└─────────────────────┬───────────────────────────────────────────┘
                      │  AI: PR opened
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    IN DEVELOPMENT                               │
│   Implementation in progress; PR open                           │
│   Branch: feature/[feature-slug]                                │
│   Protocol: 04-implement-development-protocol.md                │
└─────────────────────┬───────────────────────────────────────────┘
                      │  Human: merge implementation PR
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                       MERGED                                    │
│   PR merged into develop                                        │
│   CI validates; deployed to staging if configured               │
└─────────────────────┬───────────────────────────────────────────┘
                      │  Human: prepare release
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RELEASED                                   │
│   Merged to main, tagged, deployed to production                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Product-first boundary (important)

The **Spec Ready** stage is intentionally **product-focused**: it defines what the feature should do (actors, rules, UX, acceptance criteria). Avoid prescribing technical design (DB/schema details, file paths, specific endpoints/classes). Those decisions belong in the **Plan Ready (Implementation Plan)** stage.

## Commands by Stage

| Stage | Claude Code | Cursor | Any AI tool |
|---|---|---|---|
| Write Spec | `product-manager` agent | `/generate-new-feature` | `docs/ai/development-workflow/protocols/01-generate-specs-protocol.md` |
| Review Spec | `spec-reviewer` agent | `/review-spec` | `docs/ai/development-workflow/protocols/01-review-specs-protocol.md` |
| Write Plan | `tech-lead` agent | `/generate-implementation-plan` | `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Review Plan | `implementation-plan-reviewer` agent | `/review-implementation-plan` | `docs/ai/development-workflow/protocols/02-review-implementation-plan-protocol.md` |
| Implement | `developer` agent | `/implement-development` | `docs/ai/development-workflow/protocols/04-implement-development-protocol.md` |
| Review Code | `code-reviewer` agent | `/review-code` | `docs/ai/development-workflow/protocols/04-review-implemented-development-protocol.md` |
| Orchestrate | `orchestrator` agent | `/run-work` | `docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md` |

---

## Branch Naming

| Branch type | Pattern | Base branch |
|---|---|---|
| Spec | `spec/[slug]` | `develop` |
| Implementation plan | `implementation-plan/[slug]` | `develop` |
| Feature | `feature/[slug]` | `develop` |
| Bug / simple fix | `fix/[slug]` | `develop` |
| Hotfix | `hotfix/[slug]` | `main` |
| Release | `release/v[X.Y.Z]` | `develop` |

**Slug format:**
- **With issue tracker** → `[issue-id]-[short-description]` (e.g., `feature/ENG-123-user-auth`)
- **Without issue tracker** → `[short-description]` (e.g., `feature/user-auth`)

See `docs/best-practices/2-version-control.md` for the full slug convention.

---

## Development Artifacts

Feature development creates a folder structure under `docs/specs/`:

```
docs/specs/developments/
└── [YYYYMMDDHHMMSS]_[feature-slug]/
    ├── 1_[feature-slug]_specs.md              ← Created in Spec Ready
    └── 2_[feature-slug]_implementation-plan.md ← Created in Plan Ready
```

Smoke test runbooks are created in:

```
docs/testing/[app-or-section]/[feature-slug].smoke-test.md
```

---

## Special Development Paths

### Fast Track (Bugs & Simple Changes)

For bugs or simple changes that don't need a spec or plan:

**Criteria** (all must be true):
- The scope is clear and bounded from the start
- ≤ 3 files affected (estimate)
- No new architectural patterns introduced
- No new database migrations
- Human provides a clear, self-contained brief

**Path**: branch `fix/[slug]` from `develop` → implement → open PR → merge

**Important**: If the change turns out to be larger than described, **stop and report** to the human. Don't silently expand scope. The developer agent should surface this immediately.

### Hotfix (Critical Production Bugs)

For critical bugs that need immediate production deployment, bypassing the normal staged workflow:

**Criteria**: Active production incident or critical security issue.

**Path**: branch `hotfix/[slug]` from `main` → implement → open PR targeting `main` → merge → **mandatory backport to `develop`**

The backport (main → develop) is non-negotiable to prevent branch drift.

---

## Issue Tracker Integration

The workflow can be paired with any issue tracker. For each development unit, the issue tracks:

- **Status**: maps to the workflow stage (Backlog → Spec In Review → Spec Ready → Plan In Review → Plan Ready → In Development → Merged → Released)
- **Type**: Feature / Bug / Improvement / Chore
- **Priority**: Urgent → High → Normal → Low
- **Due date**: items due within 2 weeks take priority over abstract priority levels
- **Brief & decisions**: treated as the current brief per `integrations/issue-tracker.md`

See [`integrations/linear.md`](integrations/linear.md) for setup with Linear.
See [`integrations/issue-tracker.md`](integrations/issue-tracker.md) for full tracker-agnostic rules and agent expectations.

---

## Prioritization Logic

When the orchestrator selects what to work on next:

1. Items with a due date within 2 weeks take precedence (sorted by due date)
2. Remaining items sorted by priority (Urgent → High → Normal → Low)
3. Within the same priority, earlier-created items first
4. Dependencies must be Merged or Released before a dependent item can start

If a due date conflicts with priority ordering, flag it to the human rather than silently choosing.

---

## Parallel Developments

Multiple features can advance simultaneously across different stages. Rules:

- Parallel work across different stages is safe (e.g., one feature in Plan Ready while another is In Development)
- Parallel implementations are safe if they touch different areas of the codebase
- Avoid parallelizing implementations that both include database schema migrations — apply sequentially to avoid conflicts

Dependency declarations in specs (e.g., "Depends on: feature-X") must be respected.

---

## Spec Gaps & Workflow Hardening Loop

When implementation reveals something not covered by the spec or plan:

1. **Stop** — do not make unilateral decisions on spec-level questions
2. **Report** to the human: "The spec doesn't cover X. Here are my options: A, B, C."
3. Human provides the delta (clarification or decision)
4. **Update the spec/plan** with the clarification
5. **Resume** implementation
6. If the gap reveals a recurring spec weakness, update the relevant protocol or template to prevent it in the future

---

## Release Process

### Prepare Release

1. Create branch `release/v[X.Y.Z]` from `develop`
2. Move `[Unreleased]` entries in `CHANGELOG.md` to a new `[X.Y.Z] - YYYY-MM-DD` section
3. Update version numbers in any manifest files (`package.json`, etc.)
4. Open PR targeting `main`

### Finalize Release

5. Human reviews and merges the release PR into `main`
6. Tag `main` with `vX.Y.Z`
7. **Mandatory backport**: merge `main` back into `develop` to prevent branch drift

### Version Numbering

This project follows [Semantic Versioning](https://semver.org/):
- `MAJOR.MINOR.PATCH`
- MAJOR: breaking changes
- MINOR: new features, backwards-compatible
- PATCH: bug fixes, backwards-compatible

---

## Automated PR Review Integration

If an automated PR review tool is configured, the development agent must complete the review loop before handing off to humans:

1. Open PR
2. Wait for automated review
3. Address all **blocking** issues
4. Re-trigger the review if needed
5. Once clean, signal readiness for human review

See [`integrations/greptile.md`](integrations/greptile.md) for setup with Greptile.

---

## PR Labels

Two labels signal agent work status:

- `agent:ready-for-review` — CI green, automated review clean, ready for human review
- `agent:needs-fixes` — human requested changes, CI failing, or automated review has blocking issues

See [`protocols/91-pr-readiness-signal-protocol.md`](protocols/91-pr-readiness-signal-protocol.md) for full definition.

---

## Agent Roles Summary

| Agent | Operates on items in... | Advances item to... | Protocol |
|---|---|---|---|
| Product Manager | Backlog | Spec In Review | `01-generate-specs-protocol.md` |
| Spec Reviewer | Spec In Review | Spec Ready | `01-review-specs-protocol.md` |
| Tech Lead | Spec Ready | Plan In Review | `02-generate-implementation-plan-protocol.md` |
| Implementation Plan Reviewer | Plan In Review | Plan Ready | `02-review-implementation-plan-protocol.md` |
| Developer | Plan Ready | In Development | `04-implement-development-protocol.md` |
| Code Reviewer | In Development | Merged (via human) | `04-review-implemented-development-protocol.md` |
| Orchestrator | All stages | — (coordination only) | `90-orchestrate-work-protocol.md` |
