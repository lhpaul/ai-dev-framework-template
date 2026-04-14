# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Retrospective analysis protocol**: a new `/retrospective` command and `06-retrospective-protocol.md` allow developers (or agents) to analyze completed work — a batch or individual item — and identify process improvement opportunities. Each finding is categorized (Workflow & Process, Agent Behavior, Configuration, Documentation, Code Quality, Tooling) and assigned a severity signal (High, Medium, Low). The human chooses an action for each: "Address now" (agent applies a simple fix, commits, and pushes — no new PR), "Add to backlog" (agent creates a GitHub issue directly), or "Skip". Works in two modes: with conversation context (preferred, richer findings) or with GitHub data only (on-demand fallback). Protocol 90 (batch orchestrator) now suggests a retrospective after its Step 6 summary; Protocol 91 (work item runner) does the same for standalone item runs only (suppressed when `BATCH_CONTEXT=true`). Available as `/retrospective` in Claude Code, `/retrospective` in Cursor, and the `workflow-retrospective` Codex skill.

- **Worktree isolation for parallel batch dispatch**: protocols `90-batch-orchestrate-work-protocol.md` and `91-orchestrate-work-protocol.md` now require each Work Item Runner in a parallel batch to operate in a dedicated git worktree. Includes `BATCH_CONTEXT=true` handoff signal, pre-flight worktree checks, base-branch table for all item types, stage protocol compatibility notes, CWD safety mandate (`cd` to repo root before `git worktree remove`), and corrected Step 10 cleanup sequence (worktree removal before branch deletion).

- **CHANGELOG conflict mitigation for parallel batches** (Protocol 90, Step 3.6): when multiple PRs in a batch touch `CHANGELOG.md`, merge conflicts cascade after the first PR merges. New strategy: only the last item in a parallel batch updates CHANGELOG; other items skip CHANGELOG modifications and document their entries separately. Last item consolidates all batch CHANGELOG entries in a single commit. Applies to feature/fix implementations; spec/plan PRs and hotfix batches have exceptions detailed in the protocol.

### Fixed

- **Item-orchestrator model upgrade to balanced tier**: upgraded `item-orchestrator` agent from economy (haiku) to balanced (sonnet) tier in `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md`. Economy models struggle with the multi-step reasoning required to parse review findings, determine correct fixes, and verify fixes are present during review-fix-review cycles. This upgrade ensures the Work Item Runner can reliably supervise these cycles without requiring manual takeover (issue #109).
- **Audit confirms `.gitignore` covers all agent-created temporary paths**: `.gitignore` is complete for agent-orchestration scenarios, with proper exclusions for `.claude/worktrees/` (agent worktree isolation), `.tmp/` (local developer overrides like `template-config.json`), `.claude/settings.local.json` (local settings), and system files. Prevents accidental re-introduction of agent-created artifacts into version control, following the issue resolution from PR #99.
- **Enforce `develop` as default PR base branch (Protocol 03)**: all four implementation paths in `03-implement-development-protocol.md` now use explicit `--base develop` (or `--base main` for hotfixes) in their `gh pr create` commands, with accompanying documentation notes. This prevents accidental PR creation to `main` or other branches when agents open pull requests. Path 3 (Fast Track) now includes its own command example instead of only referencing Path 1. Path 4 (Hotfix) clarifies that `--base main` is required for production fixes.
- **Label readiness checklist gate (Steps 8a/8b in Protocol 91)**: added a hard gate before applying `ready-for-human-review`. Step 8a verifies the PR is non-draft, confirms the `ready-for-regression` label is present on implementation PRs, and removes a stale `needs-fixes` label if present (since CI is green and reviews are clean at this point) before applying `ready-for-human-review`. Step 8b extracts the tracker status update into its own distinct step. This prevents the PR from briefly holding both `ready-for-human-review` and `needs-fixes` simultaneously, enforcing the mutual exclusivity required by Protocol 92.
- **Scope boundary rule (agent enforcement)**: added explicit "scope boundary" rule to protocols `03-implement-development-protocol.md` and `91-orchestrate-work-protocol.md` to prevent agents from making changes outside their assigned issue's scope. When implementing any path or dispatching a stage agent, modify only files directly related to the assigned issue; if a review finding requires changes outside scope, document it as a separate issue and move on — do not fix it in the current PR. This prevents merge conflicts, scope creep, and wasted review cycles, especially critical in parallel batch orchestration.
- **Implementation protocol pre-branch fetch**: all four paths (Full Pipeline, Refactor, Fast Track, Hotfix) in protocol `03-implement-development-protocol.md` now include `git fetch origin` before branching from `develop` or `main`, matching the pattern already used in the prepare-release protocol (`05`). This prevents merge conflicts caused by stale local remote-tracking refs when creating feature/refactor/fix/hotfix branches.
- **Reviewer loop verification (Protocol 93)**: added explicit "Verification: Re-read to confirm each fix" section requiring fixer agents to re-read specific file/line references in review findings before marking them resolved. This prevents premature dismissal of findings based on memory alone and ensures substantive code changes are actually present in the PR.
- **Stuck-loop detection for review cycles (Protocol 93)**: added protocol-level heuristics to detect stuck fix-review loops — no-progress detection across consecutive cycles, reappearing findings after resolution, and a hard maximum cycle count with mandatory escalation. Complements existing per-platform timeouts in `pr-review-loop.sh`.
- **Prepare-release pre-flight sync**: the release protocol now runs `git fetch origin && git pull origin develop` (with a code block and failure guidance) before creating the release branch, preventing stale local state from being released. The `/prepare-release` command wrappers (Claude Code and Cursor) also now explicitly list this as a key rule. `git fetch` is also added to the Claude Code command's `allowed-tools`.

## [0.21.0] - 2026-04-13

### Added

- **CodeRabbit integration**: CodeRabbit is now available as an automated PR reviewer platform (`coderabbit` in `review.platforms`) and as a pre-push CLI tool. Includes adapter in `pr-review-loop.sh` with severity-based blocking (Critical/Major block, Minor/Low don't), `CHANGES_REQUESTED` review handling, stale-findings recovery with resolved-comment filtering, `.coderabbit.yaml` config, and setup guide at `docs/ai/development-workflow/integrations/coderabbit.md`.
- **`/run-work` command for Claude Code**: batch orchestrator command (`.claude/commands/run-work.md`), matching the existing Cursor `/run-work`.

### Changed

- **Multi-reviewer internal review gate (Step 7a)**: Step 7a now runs all configured internal reviewers (`review.internal_reviewers` in `.ai-dev-workflow.yaml`) sequentially on draft PRs before converting to non-draft. Added `max_internal_review_cycles` (default: 5) to prevent infinite loops and local override support via `.tmp/template-config.json`. Codex reviewer dispatch uses stage-specific skills. Step 9 feedback loop corrected to include Step 7a before Step 7.
- **Post-merge status transitions (Step 10)**: new Step 10 in `91-orchestrate-work-protocol.md` maps branch type to tracker status (`spec/*` → Spec Ready, `implementation-plan/*` → Plan Ready, implementation branches → Merged). All post-merge-cleanup commands updated accordingly.

### Fixed

- **Missing `/sync-template` command for Claude Code**: added `.claude/commands/sync-template.md` covering template source resolution, categorized diff, approval gate, file application, and git/PR instructions.

## [0.20.0] - 2026-04-10

### Added

- **Label-gated e2e/regression test workflow**: new `.github/workflows/e2e-regression.yml` runs only when the `ready-for-regression` label is applied, with a Playwright-based `e2e/` placeholder project for downstream projects to customize. The orchestrator applies the label automatically on implementation PRs after automated review is clean (new Step 7b, documented in protocols 91 and 92), and the release protocol applies it on production PRs targeting `main`. See `docs/ai/development-workflow/integrations/e2e-regression.md` for the label-gate pattern.
- **Backlog intake stage**: new protocol `docs/ai/development-workflow/protocols/00-add-backlog-item-protocol.md` and `/add-backlog-item` command (Cursor + Claude Code) create work items in the configured issue tracker, backed by `scripts/development-workflow/add-backlog-item.sh` (`resolve` / `create` for GitHub) and destination helpers in `workflow-lib.sh`.
- **Template deployment scaffold**: new `.github/workflows/deploy.yml` triggers on `develop` and `main`, maps to `develop`/`production` environments, and keeps deploy steps as explicit no-op placeholders. Accompanied by `docs/ai/development-workflow/integrations/ci-cd-deployment.md` and new CI/CD onboarding prompts in `docs/ai/setup/protocol.md` plus branch-to-environment guidance in `docs/project/3-software-architecture.md`.
- **Prepare release drives production PR readiness**: after opening release PRs, `05-prepare-release-protocol.md` and `/prepare-release` run the automated reviewer loop, apply `ready-for-regression` on the PR targeting `main`, and run the CI loop (including label-gated e2e/regression) before handing off for human merge.

### Changed

- `92-pr-readiness-signal-protocol.md` and `integrations/e2e-regression.md`: align `ready-for-regression` conditions with production release PRs (`release/*` → `main`) per protocol `05`, removing the implementation-only contradiction.
