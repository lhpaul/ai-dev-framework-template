# AI-Assisted Development Workflow

This document is the canonical reference for how development moves through this repository.

The goal of this workflow is simple: AI agents should do most of the execution work, while humans focus on the parts that matter most from a human perspective: choosing direction, making decisions when the requirements are unclear, and reviewing the final result before merge or release.

The workflow is designed around a persistent execution contract. Once a run starts, it should keep advancing the work until it reaches a real stopping point: the pull request is ready for human review, a human decision is required, a dependency blocks progress, or an automated loop escalates after retry or timeout limits. Opening a branch, opening a PR, or finishing one sub-step is not enough by itself.

---

## Why This Workflow Exists

Software delivery gets more reliable when each stage answers a different question:

- **Backlog**: Is this the right thing to work on now?
- **Spec**: What should be built, and how will we know it is correct?
- **Implementation plan**: How should we build it in this codebase?
- **Implementation**: Does the code, its supporting tests, and its documentation match the agreed plan?
- **Merge**: Is the change ready to join the integration branch?
- **Release**: Is the integrated work ready to ship to production?

Each piece of tracked work usually starts as a row in an issue tracker such as Linear, Jira, GitHub Issues, or ClickUp. From this point on, this document calls that tracked unit a **work item**.

Comments, review threads, automated findings, and failing checks on a pull request are a different kind of issue entirely. From this point on, this document calls that pull-request-side work **PR feedback**.

---

## The Stages And Their Value

The process moves through the stages below in order. The point of this section is not automation yet; it is to explain what each stage does and why it exists.

| Stage | What this stage does | Why it matters |
| --- | --- | --- |
| **Backlog** | Collects candidate work items, priorities, dependencies, and deadlines. | Keeps the team from starting work without context or priority. |
| **Spec** | Defines the user-facing or business-facing outcome: behavior, rules, acceptance criteria, and scope. | Prevents building the wrong thing or solving the wrong problem. |
| **Implementation plan** | Converts the spec into a technical approach for this repository: files, sequencing, risks, migrations, rollout details, the edge cases and test approach the implementation must cover, and any observability or analytics work needed to operate and understand the feature. | Prevents costly implementation churn and keeps design decisions explicit. |
| **Implementation** | Produces the actual code, supporting automated tests, and documentation changes. | Turns approved intent into a concrete change set while keeping developer-facing verification close to the work. |
| **Merge** | Moves the approved change into `develop`. | Creates a stable integration point for completed work. |
| **Release** | Ships integrated work from `develop` to `main` using the release flow. | Separates "merged" from "in production" and keeps release discipline explicit. |

### Backlog

The backlog is where work starts. A work item exists here before the team commits to a solution. This stage is about priority, timing, dependencies, and clarity of the request.

### Spec

The spec explains **what** should happen and **why** it matters. It should describe actors, workflows, business rules, acceptance criteria, scope boundaries, and any product-facing measurement requirements in product terms.

This workflow intentionally keeps the spec product-first. The spec should not lock in detailed technical design unless the product decision genuinely depends on it.

When user-behavior analytics matter, the spec should define the product intent behind them: which user actions or outcomes matter, what questions the team wants to answer, and what privacy or consent constraints apply. The implementation plan should then translate those requirements into concrete instrumentation, data pipelines, dashboards, or alerting.

### Implementation Plan

The implementation plan picks up after the spec is merged. It explains **how** the repository should satisfy the spec: which files change, what order the work should happen in, what risks exist, what data or migration steps are needed, which edge cases must be validated, what observability and analytics support the feature requires, and what smoke test runbook should prove the change works.

This stage protects the codebase from "understood in my head" engineering. It also gives future reviewers a concrete basis for deciding whether the implementation stayed on course, including whether the testing strategy covers the tricky or failure-prone cases rather than only the happy path.

When relevant, the plan should make observability and analytics explicit instead of leaving them implicit. That can include frontend crash reporting, backend logging and alerting, product analytics events, and any downstream analytical-data handling needed to make the feature measurable and supportable in production.

### Implementation

Implementation turns the approved plan into code, tests, docs, and changelog updates. This is where the repository changes, but it is not a license to improvise on scope. If implementation reveals a missing requirement or a design gap that the plan cannot safely answer, the workflow stops and asks for a decision instead of silently inventing one.

This stage also includes the validation work needed to prove the implementation is truly ready. That means keeping automated tests in sync during development and, later, running the final smoke-test checkpoint before humans treat the change as ready.

The final implementation-validation checkpoint in this workflow is the smoke test: a targeted run driven by a smoke test runbook or an existing committed automated spec.

### Merge

Merge is the point where a change joins `develop`. A merged change is integrated, but not necessarily released. Treating merge as its own stage keeps integration quality and production release quality from getting conflated.

### Release

Release is the step where the team decides that `develop` is ready to ship. The workflow uses a dedicated release branch and a controlled PR flow so versioning, changelog curation, tagging, and backports happen deliberately.

---

## Workflow At A Glance

```mermaid
flowchart TD
    backlog[Backlog] --> spec[Spec]
    spec --> plan[ImplementationPlan]
    plan --> implement[Implementation]
    implement --> validate[SmokeTestCheckpoint]
    validate --> merge[MergedToDevelop]
    merge --> release[ReleasedToMain]
```

For the three authored artifacts in the middle of the workflow, the same review pattern repeats:

1. Draft the artifact or code on a workflow branch.
2. Run an internal review gate.
3. Resolve automated PR feedback and CI findings.
4. Hand the PR to a human only when it is actually ready.
5. Merge, then move to the next stage.

After implementation is code-review ready, the workflow can still run a smoke test as a final validation checkpoint. That checkpoint is intentionally different from the spec, plan, and implementation review loops: it produces a pass/fail validation result, not another reviewed artifact PR.

That repeated pattern is one of the main reasons the workflow scales well with AI assistance: it creates a predictable loop for authored artifacts without pretending every checkpoint has the same review semantics.

---

## How AI Agents Fit Into The Process

The sections above describe the process in human terms. This section explains how AI agents are layered onto that process.

At the broadest level, humans still choose what matters. A human decides which work item should start, clarifies ambiguous requirements, reviews the final PR, and decides whether to merge or release. The automation exists to compress the execution between those human touchpoints.

### Entry Modes

Humans usually enter the workflow in one of two ways:

1. **Targeted mode**: start or resume one known item.
2. **Portfolio mode**: ask the system to scan the portfolio and advance all safe eligible work.

The portfolio-wide coordinator is the **Portfolio Orchestrator** (`orchestrator`). From this point on, this document uses that name for the agent that inspects the whole portfolio, selects eligible items, groups parallel-safe work, and dispatches one item-level runner per item.

The single-item coordinator is the **Work Item Runner** (`item-orchestrator`). From this point on, this document uses that name for the agent that owns one work item, branch, development folder, or PR and keeps it moving until it reaches a real terminal condition.

Stage agents such as `product-manager`, `tech-lead`, and `developer` do not decide portfolio priority on their own. They are dispatched for a specific item by a human or by the Work Item Runner.

### Agent Layers

| Layer | Role in the workflow |
| --- | --- |
| **Portfolio Orchestrator** | Scans the portfolio, selects safe work, and dispatches item-level runs. |
| **Work Item Runner** | Resolves exactly one item and drives it through the next deterministic steps without stopping early. |
| **Stage agent** | Produces the stage output itself, such as a spec, plan, or implementation. |
| **Internal review agent** | Reviews the draft output against the repository's review contract before the PR is handed to external systems or humans. |
| **Automated reviewer loop** | Resolves third-party PR review findings until the PR is clean or escalated. |
| **CI loop** | Waits for required checks to pass and handles fix cycles when they fail. |
| **Human reviewer** | Reviews the final PR when the automated work is already clean. |

### Stage Agents

The main stage agents map to the authored stages and the final validation checkpoint:

| Stage | Primary agent | Purpose |
| --- | --- | --- |
| **Spec** | `product-manager` | Produces the spec PR. |
| **Implementation plan** | `tech-lead` | Produces the plan PR. |
| **Implementation** | `developer` | Produces the implementation PR. |
| **Smoke test** | `smoke-tester` | Executes the smoke test runbook and reports pass/fail. |

### Internal Review And External Review

This workflow uses two kinds of review that are easy to confuse, so it is worth naming them clearly.

Review performed by repository-managed agents using local protocols such as `REVIEW.md`, `01-review-spec-protocol.md`, `02-review-implementation-plan-protocol.md`, or `03-review-implementation-protocol.md` is called **internal AI review**.

Review performed by external PR review products such as CodeRabbit, Greptile, Devin Review, or similar Git-hosted tools is called a **third-party reviewer**. These tools are useful, but they are not the same thing as the repository's internal review agents.

### The Execution Loop

For a typical spec, plan, or implementation item, the AI-assisted flow looks like this:

1. A human starts a work item directly or asks for portfolio-wide advancement.
2. The appropriate orchestrator resolves the next deterministic action.
3. A stage agent creates or updates the branch and draft PR.
4. An internal review agent drives the draft PR to a clean review state.
5. The automated reviewer loop resolves third-party PR feedback.
6. The CI loop waits for required checks to pass.
7. The PR is marked ready for human review.
8. A human reviews and either merges or requests changes.

This means the AI system is not just writing a first draft. It is responsible for most of the execution between the initial brief and the point where a human is justified in spending review time.

---

## Key Boundaries And Rules

### Spec Versus Plan

The spec defines what should happen. The implementation plan defines how this repository should make it happen. If a document needs detailed file paths, architecture sequencing, migration steps, or low-level technical trade-offs, it belongs in the implementation plan rather than the spec.

### Ready For Review Versus Still In Progress

Opening a PR does not mean a stage is done. A PR is only ready when the internal review gate is clean, configured automated reviewers are clean or intentionally skipped, CI is green, and previous human feedback has been addressed. The operational `PR Readiness` section below defines how to signal that state.

### Spec Gaps

When implementation reveals a missing requirement or unresolved choice, the workflow should stop and report the gap. The fix is to update the spec or plan and then resume, not to let an agent silently invent product or architecture decisions.

---

## Operational Reference

The sections below keep this document usable as a master reference after the narrative introduction.

### Commands By Stage

| Stage | Claude Code | Cursor | Codex | Any AI tool |
| --- | --- | --- | --- | --- |
| Add backlog item | `/add-backlog-item` | `/add-backlog-item` | — | `docs/ai/development-workflow/protocols/00-add-backlog-item-protocol.md` |
| Write spec | `product-manager` agent | `/generate-new-feature` | `workflow-spec-writer` skill | `docs/ai/development-workflow/protocols/01-generate-spec-protocol.md` |
| Write plan | `tech-lead` agent | `/generate-implementation-plan` | `workflow-plan-writer` skill | `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Implement | `developer` agent | `/implement-development` | `workflow-implementer` skill | `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` |
| Review gate (spec / plan / code) | Native review against `REVIEW.md` | `/review-spec`, `/review-implementation-plan`, `/review-code` | Native review against `REVIEW.md` | `REVIEW.md` plus compatibility wrappers in `docs/ai/development-workflow/protocols/` |
| Smoke test | `smoke-tester` agent | `/smoke-tester` | — | `docs/ai/development-workflow/protocols/04-smoke-test-protocol.md` |
| Run reviewer loop | `/run-reviewer-loop` command (or `automated-reviewer-loop` agent) | `/run-reviewer-loop` | `workflow-reviewer-loop` skill | `docs/ai/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Advance one item | `/run-item-work` command (or `item-orchestrator` agent) | `/run-item-work` | `workflow-item-orchestrator` skill | `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Orchestrate portfolio | `/run-work` command (or `orchestrator` agent) | `/run-work` | `workflow-orchestrator` skill | `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` |
| Prepare release | `/prepare-release` | `/prepare-release` | — | `docs/ai/development-workflow/protocols/05-prepare-release-protocol.md` |

After opening release PRs, protocol `05` runs the automated reviewer loop, applies `ready-for-regression` on the **PR targeting `main`**, and runs the CI loop until checks are green (or escalation) — same persistence contract as other PR readiness work.

Codex skills are stored in `.codex/skills/`. Install them into the local Codex environment with:

```bash
./scripts/development-workflow/install-codex-skills.sh
```

These skills are thin wrappers around the same workflow protocols used by the other tools.

### Workflow Capabilities And Fallbacks

This workflow depends on a few capabilities more than on any specific vendor or product:

- Git plus a remote pull-request workflow are required so agents can create branches, push work, and hand off reviewable PRs.
- CI is required so build, lint, and test checks can act as the automated merge gate.
- A repository CLI such as `gh` is recommended. Without one, agents can still prepare the branch locally and hand the human the information needed to open or update the PR manually.
- Automated PR reviewers are optional. Without them, the workflow proceeds from the internal review gate directly to CI and then to human review.
- An issue tracker is optional. Without one, portfolio-wide prioritization and "current brief" lookup require more direct human guidance.
- Browser automation is optional. Without it, smoke tests should be run manually from the committed smoke test runbook.

### Branch Naming

| Branch type | Pattern | Base branch |
| --- | --- | --- |
| Spec | `spec/[slug]` | `develop` |
| Implementation plan | `implementation-plan/[slug]` | `develop` |
| Feature | `feature/[slug]` | `develop` |
| Refactor | `refactor/[slug]` | `develop` |
| Bug or simple fix | `fix/[slug]` | `develop` |
| Hotfix | `hotfix/[slug]` | `main` |
| Release | `release/v[X.Y.Z]` | `develop` |

Slug format:

- With an issue tracker: `[issue-id]-[short-description]`
- Without an issue tracker: `[short-description]`

### Development Artifacts

The spec and implementation plan for a development live under `docs/specs/developments/`:

```text
docs/specs/developments/
└── [YYYYMMDDHHMMSS]_[feature-slug]/
    ├── 1_[feature-slug]_specs.md
    └── 2_[feature-slug]_implementation-plan.md
```

Smoke test runbooks live under `docs/testing/`:

```text
docs/testing/[app-or-section]/[feature-slug].smoke-test.md
```

### Tracker Status Model

If an issue tracker is configured, the work item status usually maps to the workflow like this:

`Backlog -> Writing Spec -> Spec in Review -> Spec Ready -> Writing Plan -> Plan in Review -> Plan Ready -> In Development -> Development in Review -> Merged -> Released`

Refactor items skip the spec stages: `Backlog -> Writing Plan -> Plan in Review -> Plan Ready -> In Development -> Development in Review -> Merged -> Released`

Typical tracker fields worth keeping current:

- Status
- Type
- Priority
- Due date
- Dependency links
- Brief and decision history

### Prioritization And Dependencies

When multiple items could advance, use this order:

1. Due date within the next two weeks, earliest first.
2. Priority: Urgent -> High -> Normal -> Low.
3. Earlier-created items before newer items.

Dependencies override priority. If a work item depends on another item that is not yet `Merged` or `Released`, it should wait.

### Parallel Work

Parallel work is encouraged when it is safe:

- Different stages can usually proceed in parallel without conflict.
- Multiple implementations can proceed in parallel if they touch different areas of the codebase.
- Parallel database schema work should usually be serialized to avoid migration conflicts.

### Special Paths

#### Refactor

Refactor is the path for code restructuring or tech-debt cleanup that does not need a product spec but benefits from a planned approach.

Use it when all of the following are true:

- The change is code restructuring, tech-debt cleanup, or internal reorganization — not a new user-facing feature.
- The scope is understood well enough to write an implementation plan without a product spec.
- The work item brief (from a tracker or human) is sufficient context for the tech lead to plan the work.

Path: `refactor/[slug]` from `develop` -> write plan -> plan review gate -> implement -> code review gate -> smoke test as needed -> merge.

The development folder contains only a plan file (no spec). The tech lead uses the work item brief as input instead of an approved spec.

#### Fast Track

Fast track is the shortened path for bugs or simple changes that do not need the full spec-and-plan pipeline.

Use it only when all of the following are true:

- The scope is clear from the start.
- The change is expected to touch three files or fewer.
- No new architectural pattern is being introduced.
- No database migration is involved.
- The human brief is self-contained.

Path: `fix/[slug]` from `develop` -> implement -> review gate -> smoke test as needed -> merge.

If the change turns out to be larger than expected, stop and expand back into the normal staged workflow instead of silently widening scope.

#### Hotfix

Hotfix is the path for critical production bugs or urgent security issues.

Path: `hotfix/[slug]` from `main` -> implement -> review gate -> smoke test as needed -> PR to `main` -> merge -> mandatory backport to `develop`.

The backport is not optional. It prevents `main` and `develop` from drifting apart.

### PR Readiness

Use the following labels consistently when label tooling is available:

| Label | Meaning |
| --- | --- |
| `ready-for-human-review` | Internal review is clean, configured automated reviewers are clean or skipped, CI is green, and the PR is ready for a human reviewer. |
| `needs-fixes` | CI is failing, blocking automated feedback exists, or human requested changes are still unresolved. |

Opening a PR is not a terminal condition. A workflow run should continue until the PR is ready for a human checkpoint or the process escalates.

### Workflow Configuration

Repository-specific workflow integrations are declared in `.ai-dev-workflow.yaml` at the repo root.

The file is versioned and intentionally declarative. It is the right place to record which workflow providers this repository uses for:

- Automated PR review
- Issue tracking
- Git hosting / pull-request workflow
- Browser automation for smoke tests or similar validation

Current schema:

```yaml
schema_version: 1

review:
  platforms:
    - greptile
    - devin
  internal_reviewers:
    - claude
    - codex

issue_tracker:
  provider: linear

vcs:
  provider: github

browser_automation:
  provider: playwright_mcp
```

Important implementation notes:

- `review.platforms` is consumed by `scripts/development-workflow/pr-review-loop.sh` for external automated PR review (Step 7). If the config file is absent, or `review.platforms` is omitted or empty, automated PR review is treated as not configured and the review loop reports `skipped`.
- `review.internal_reviewers` is consumed by the Step 7a internal review gate protocol (`91-orchestrate-work-protocol.md`). If omitted, the gate falls back to running the stage-appropriate `claude` reviewer once. Developers can override the list locally via `.tmp/template-config.json` (gitignored).

Provider-specific setup still lives in the integration guides under `docs/ai/development-workflow/integrations/`.

### Automated Review And CI

When an automated PR review platform is configured, the Work Item Runner should keep operating after each push instead of stopping at "PR opened".

The expected sequence is:

1. Run the stage-appropriate internal review gate.
2. Run the automated reviewer loop until blocking PR feedback is resolved or the process escalates.
3. Run the CI loop until required checks are green or the process escalates.
4. Mark the PR ready for human review only after both loops are clean.

Review platforms are declared in `.ai-dev-workflow.yaml` under `review.platforms`. The repository helpers that support this loop are:

- `scripts/development-workflow/pr-review-loop.sh`
- `scripts/development-workflow/pr-ci-loop.sh`

### Release Summary

Release is triggered by a human when `develop` is ready to ship.

Summary:

1. Create `release/v[X.Y.Z]` from `develop`.
2. Curate `CHANGELOG.md`, move `[Unreleased]` into the versioned release section, and bump any versioned manifests.
3. Open two PRs from the release branch: one to `main`, one back to `develop`.
4. Merge the `main` PR first so the release tag is created, then merge the backport PR.

Versioning follows Semantic Versioning:

- `PATCH`: backwards-compatible fixes
- `MINOR`: backwards-compatible features or improvements
- `MAJOR`: breaking changes

---

## Protocol And Integration Index

Use these documents when you need the detailed rules behind a part of the workflow:

### Protocol Numbering

Protocol prefixes are stable family identifiers, not a promise of contiguous numbering.

- `01`-`05` are the current primary stage families in workflow order.
- `00` is reserved for pre-stage backlog intake (creating tracker work items before spec work).
- Generate and review protocols for the same stage share the same family number.
- `90`-`99` are orchestration, readiness, and other cross-cutting operational protocols.
- The numbering was normalized after an older stage was removed, so the current primary stages are contiguous again.

### Core Protocols

- `docs/ai/development-workflow/protocols/00-add-backlog-item-protocol.md`
- `docs/ai/development-workflow/protocols/01-generate-spec-protocol.md`
- `docs/ai/development-workflow/protocols/01-review-spec-protocol.md`
- `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
- `docs/ai/development-workflow/protocols/02-review-implementation-plan-protocol.md`
- `docs/ai/development-workflow/protocols/03-implement-development-protocol.md`
- `docs/ai/development-workflow/protocols/03-review-implementation-protocol.md`
- `docs/ai/development-workflow/protocols/04-smoke-test-protocol.md`
- `docs/ai/development-workflow/protocols/05-prepare-release-protocol.md`
- `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`
- `docs/ai/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
- `docs/ai/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`

### Review Contract

- `REVIEW.md`

### Tooling And Configuration

- `docs/ai/development-workflow/agent-model-config.md`
- `.ai-dev-workflow.yaml` - repo-level workflow integration manifest (`review.platforms`, `review.internal_reviewers`, `issue_tracker.provider`, `vcs.provider`, `browser_automation.provider`)

Repository helpers:

- `scripts/development-workflow/add-backlog-item.sh`
- `scripts/development-workflow/discover-workflow-state.sh`
- `scripts/development-workflow/workflow-batch-plan.sh`
- `scripts/development-workflow/workflow-next-action.sh`
- `scripts/development-workflow/pr-review-loop.sh`
- `scripts/development-workflow/pr-ci-loop.sh`

### Integration Guides

- `docs/ai/development-workflow/integrations/issue-tracker.md`
- `docs/ai/development-workflow/integrations/linear.md`
- `docs/ai/development-workflow/integrations/pr-review-platform.md`
- `docs/ai/development-workflow/integrations/greptile.md`
- `docs/ai/development-workflow/integrations/devin.md`
- `docs/ai/development-workflow/integrations/github-projects.md`
- `docs/ai/development-workflow/integrations/ci-cd-deployment.md`
- `docs/ai/development-workflow/integrations/e2e-regression.md`

---

## Final Reminder

This workflow is intentionally opinionated.

Humans should choose direction, resolve ambiguity, review high-quality PRs, and decide when to merge or release. Agents should draft, revise, fix, test, and keep advancing the work until it reaches a real human checkpoint.
