# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Scope-drift guardrails for spec and plan authoring**: protocol updates now require brief-objective coverage matrices and PR-visible deferral notes in spec writing, plus live repo verification logs for pattern-based plan scope checks; review checklists and agent/skill entrypoints were aligned, and a workflow fixture was added for stale-enumeration validation.

### Changed

- **GitHub Actions workflow security checklist** (`03-implement-development-protocol.md`): developer guidance now requires least-privilege `permissions`, full-SHA `uses:` pinning, scoped path filters, and `concurrency` controls whenever `.github/workflows/*.yml` files are created or materially updated.

### Fixed

- **Internal reviewers now fix `suggestion`-level findings by default** (`REVIEW.md`): `suggestion` severity was previously "report or fix at discretion", meaning internal reviewers (Step 7a) could skip them. This left low-risk improvements for external reviewers to re-raise, lengthening the review loop. The default action is now "fix by default; report only if scope-expanding or requires a product decision."

- **`UNRESOLVED_THREAD_COUNT` now emits `-1` (not `"unknown"`) on page-cap escalation** (`pr-review-loop.sh`): the output contract specifies an integer field; using the string `"unknown"` violated the contract and required a defensive string-guard on the downstream consumer. Replaced with `-1` as an integer sentinel and removed the now-redundant guard.

- **`PR_IS_DRAFT` and `PR_HAS_NEEDS_FIXES` documented in discovery output contract** (`batch-merge.sh`): these fields were emitted by `fetch_pr_meta` but absent from the script header comment, leaving the documented contract out of sync with actual output.

- **Draft-state revalidation in `cmd_merge` to close TOCTOU gap** (`batch-merge.sh`): a PR could be switched to draft between discovery and merge execution. Added `isDraft` revalidation immediately before merge so the guard reflects current state.

- **CodeRabbit completion via issue comments** (`pr-review-loop.sh`): when CodeRabbit posts only an issue-thread summary (no `pulls/{id}/reviews` entry) for the current HEAD, the poll loop now proceeds to Phase 3 instead of spinning until `timeout` and returning a false `escalate`.

## [0.22.0] - 2026-04-20

### Added

- **Batch merge command** (`/batch-merge`): merges all `ready-for-human-review` PRs into `develop` sequentially; auto-resolves CHANGELOG conflicts; produces a structured outcome summary. Available in Claude Code, Cursor, and as a Codex skill.
- **Retrospective analysis command** (`/retrospective`): analyze completed batches or individual items for process improvement opportunities; findings are categorized and actioned interactively. Available in Claude Code, Cursor, and as a Codex skill.
- **Worktree isolation for parallel batch dispatch**: each Work Item Runner in a parallel batch now operates in a dedicated git worktree, preventing cross-item interference.
- **Worktree git switch guardrail** (Protocol 91): explicit prohibited-command list (`switch`, `checkout`, `reset`, `restore`) against the main repo root in batch context; Protocol 90 handles all four postcondition states after each runner returns.
- **Markdown lint CI** (`.github/workflows/markdown-lint.yml`): gates PRs touching spec, plan, and CHANGELOG docs with `markdownlint-cli2` (trailing whitespace, relative links, file newline) and a custom heuristic script (GLOB001, COUNT001).
- **ShellCheck CI** (`.github/workflows/shellcheck.yml`): gates PRs touching workflow scripts with ShellCheck `--severity=warning`.
- **Agent timeout handling guidance**: expected run durations table, resume checklist, and stale-PR detection heuristic added to `agent-model-config.md` and Protocols 90/91.
- **Pre-dispatch tracker status update** (Protocol 90 Step 2.5 / Protocol 91 Step 2): orchestrator sets the item's tracker status to the correct in-flight value and ensures it is on the project board before dispatching any runner.
- **CHANGELOG conflict mitigation** (Protocol 90 Step 3.6): each PR adds its own entry; batch-merge auto-resolution handles conflicts at merge time.

### Changed

- **Workflow agent model bump**: `tech-lead` upgraded from Opus 4.6 to Opus 4.7; Sonnet and Haiku unchanged.
- Protocol 93 (`automated-reviewer-loop`): mandatory cross-reference check before committing fixes.
- `implementation-plan-template.md`: new "Code Samples" section with guidance on illustrative samples and cross-section consistency.

### Fixed

- **Subagent permission-denial mitigation** (Protocol 90 Step 4.1 / Protocol 91 Step 3.5): subagents that hit a tool-permission denial exit with a structured signal; orchestrator falls back to inline execution from the main session.
- **Require all review threads resolved** (`pr-review-loop.sh`): new `check_unresolved_threads` gate (GraphQL `reviewThreads` API) blocks `ready-for-human-review` until all bot threads are resolved.
- **CodeRabbit SUCCESS commit-status fallback** (`pr-review-loop.sh`): avoids spurious `timeout` escalations when CodeRabbit signals via commit status during rate-limit windows.
- **CodeRabbit rate-limit handling** (`pr-review-loop.sh`): detects rate-limit comments, waits 3 min, and retries up to 2 times before falling back.
- **Transient `git pull --ff-only` retry** (`batch-merge.sh`): one automatic retry with a fresh `git fetch` before failing the merge.
- **Locked-worktree handling** (`post-merge-cleanup.sh`): tries `git worktree unlock` then double-force removal before failing.
- **Worktree blocking branch deletion** (`post-merge-cleanup.sh`): detects and removes worktrees before deleting their branch.
- **Post-merge cleanup tracker status update** (`post-merge-cleanup.sh`): unified issue-number extraction; new `update_tracker_status` helper sets `Spec Ready`, `Plan Ready`, or `Merged` with rollback prevention.
- **Post-merge cleanup closes GitHub issues**: issue number extracted from branch name; issue closed with a PR-linking comment on merge.
- **Worktree leak prevention**: three safeguards added across Protocols 90, 91, and 94 to catch unexpected main-working-tree modifications during parallel batch runs.
- **Label readiness checklist gate** (Protocol 91 Steps 8a/8b): `ready-for-human-review` now requires non-draft state, `ready-for-regression` label, and absence of `needs-fixes`; tracker update extracted to Step 8b.
- **Codex reviewer runtime fallback** (Protocol 91 Step 7a): unreachable reviewers are skipped with a PR warning; zero reachable reviewers hard-fails the gate.
- **Enforce `develop` as default PR base branch** (Protocol 03): all four paths now use explicit `--base develop` or `--base main`.
- **Scope boundary rule** (Protocols 03/91): agents must not fix out-of-scope findings in the current PR; document as a separate issue instead.
- **Pre-implementation scope checklist** (Protocol 03): enumerate all files to change before writing code.
- **Cross-reference consistency check** (Protocol 03): grep all locations of modified policy text before opening a PR.
- **Implementation protocol pre-branch fetch** (Protocol 03): `git fetch origin` before branching, matching the release protocol.
- **Reviewer loop verification** (Protocol 93): re-read file/line references before marking findings resolved.
- **Stuck-loop detection** (Protocol 93): max cycle count with mandatory escalation; no-progress and reappearing-finding heuristics.
- **Post-dispatch PR verification** (Protocols 90/91 Step 8c): orchestrator independently verifies PR state via `gh pr view` before reporting ready.
- **Pre-dispatch merged-PR cross-check** (Protocol 90 Step 1a): stale tracker items with merged PRs are closed and excluded before dispatch.
- **Prepare-release pre-flight sync**: `git fetch origin && git pull origin develop` added to the release protocol and command wrappers.
- **CHANGELOG trailing-whitespace prevention** (Protocol 03): explicit format verification sub-step in all four implementation paths.
- **Worktree Write/Edit path discipline** (item-orchestrator): reminder to target worktree paths in all Write/Edit calls.
- **Item-orchestrator upgraded to balanced tier** (Sonnet): economy (Haiku) was insufficient for multi-step review-fix-review cycles.
- **Same-batch tool-fix ordering hazard detection** (`workflow-batch-plan.sh`): classifies items that modify canonical workflow tool files; serializes them to run before the rest of the batch.
- **Unbound variable in `add-backlog-item.sh`**: `labels[@]` guard prevents `set -u` failure when no labels are passed.
- **Missing Cursor retrospective command**: `.cursor/commands/retrospective.md` created for parity with Claude Code.
- **Removed boilerplate "Guiding principle" section** from spec template and all existing spec files.

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
- CHANGELOG policy: spec-only and plan-only PRs are exempt from CHANGELOG updates; fixes to unreleased work update the existing `[Unreleased]` entry instead of adding a new one. Hotfixes still require a new entry since they fix released code.
- `03-implement-development-protocol.md`: Path 2 (Refactor) and Fast Track / Hotfix paths now spell out their own draft PR metadata and `gh pr create` examples (`feat(...)` with spec/plan link for refactor; `fix(...)` with incident-focused body for hotfix) instead of reusing Path 1 Step 8; handoff steps correctly reference Step 8–9 and the Work Item Runner lifecycle.

### Fixed

- `workflow-next-action.sh --development`: branch existence and merged-PR checks now use `feature/` when the folder has a spec (full pipeline) and `refactor/` when plan-only, so parallel items with the same slug are not cross-matched across prefixes.

## [0.19.0] - 2026-04-02

### Added

- GitHub Projects v2 integration guide (status mapping, custom fields, `gh`/GraphQL, branch naming).
- Implementation plan template: regression suite checklist reminder.

### Changed

- Orchestration treats the issue tracker as the source of truth for work-item status; development folders and Git state supplement it.
- **Refactor** path: `refactor/[slug]` (plan → implement, no spec); plan-only development folders supported. Renamed `Improvement` label to `Refactor`.
- Default issue tracker: `github_projects` (was `github_issues`). Greptile removed from default review platforms in this repo.
- Renamed stage `Implementation in Review` → `Development in Review` across protocols and integration docs.
- `gh pr ready` runs after the internal review gate (Step 7a), before external reviewers and CI, so automation sees a ready PR after internal approval.

### Removed

- `Chore` tracker label; track that work as **Refactor**.

### Fixed

- Automated reviewer loop recovers stale unresolved findings from full PR history so blockers are not dropped when the latest HEAD has no fresh automated review (e.g. after base-branch merges).
- Next-action detection uses merged GitHub PRs (and slug match) so items are not misclassified as Plan Ready after the feature branch is deleted.

## [0.18.1] - 2026-03-30

### Fixed

- Automated Devin review loops now recover stale unresolved findings from PR history when the latest HEAD has no fresh Devin review, preventing blocking issues from being dropped after base-branch merges.
- Devin resolved-confirmation comments (`✅ **Resolved**`) are excluded from blocking issue counts so previously fixed findings are not reclassified as new blockers.
- Devin review detection now considers both GitHub Check Runs and Status Contexts (deduplicated by context), avoiding false `no_check_run` skips when Devin reports via statuses.

### Changed

- Automated reviewer-loop protocol pre-flight now explicitly defines unresolved findings and blocking Devin outcomes, and documents ledger bootstrap from full PR history before fix cycles.
- Workflow protocols were renumbered and normalized (`04-*` -> `03-*`, `05-*` -> `04-*`, `06-*` -> `05-*`, `89-*` -> `90-*`, `90-*` -> `91-*`, `91-*` -> `92-*`, `92-*` -> `93-*`) and several protocol filenames were standardized (`generate-specs` -> `generate-spec`, `review-specs` -> `review-spec`, `review-implemented-development` -> `review-implementation`).
- PR readiness labels were renamed to simpler defaults: `agent:ready-for-review` -> `ready-for-human-review` and `agent:needs-fixes` -> `needs-fixes`.
- `.ai-dev-workflow.yaml` now uses a versioned nested schema (`review.platforms`) and includes declarative sections for `issue_tracker`, `vcs`, and `browser_automation`.
- Stage protocols now open draft PRs first, then mark them ready with `gh pr ready` after the internal review gate (Step 7a) passes.
- Orchestration now includes an explicit Step 7a internal review gate before external automated reviewers.
- Workflow docs were refreshed, including a full rewrite of `docs/ai/development-workflow/README.md` and terminology updates to "Portfolio Orchestrator" and "Work Item Runner".

### Removed

- `docs/ai/development-workflow/tooling-assumptions.md`; capability assumptions and fallback guidance now live in the workflow README.

## [0.18.0] - 2026-03-18

### Added

- New Claude Code slash commands: `/run-item-work` (single-item workflow orchestration, mirrors Cursor), `/run-reviewer-loop` (automated reviewer + CI loop, mirrors Cursor), and `/post-merge-cleanup` (post-merge branch cleanup and issue tracker update, mirrors Cursor). All three are now autocompleted in Claude Code and listed as the primary entry points in the CLAUDE.md workflow table.
- Pre-flight check for existing unresolved review findings in `/run-reviewer-loop` (Claude Code and Cursor): before running the review scripts, the agent now inspects existing PR reviews for blocking findings posted by configured platforms after a previous run timed out, and dispatches a fixer first. Protocol 92 updated to document this step.
- Automated issue ledger tracking for PR review loops: the `automated-reviewer-loop` agent now maintains an issue ledger across cycles, keyed by `(platform, path, body_snippet)` to survive line shifts. After each fixer push, agents post a fix-commit comment listing resolved vs. remaining issues. When the loop terminates, agents post a final summary table with resolution status and commit SHAs.
- Devin review state expansion: `pr-review-loop.sh` now treats `COMMENTED`-state reviews from Devin as blocking findings (previously only `CHANGES_REQUESTED` was captured). This ensures out-of-diff findings posted by Devin are surfaced in the review loop.
- Protocol 90 blocking classification documentation: updated "Blocking vs. suggestion classification" section to clarify that both `CHANGES_REQUESTED` and `COMMENTED` reviews are treated as blocking.

### Fixed

- `pr-review-loop.sh`: Devin adapter now returns `skipped` instead of polling until timeout when no Devin check run exists for the HEAD commit. Subsequent pushes to an already-reviewed PR often have no check run, causing spurious timeouts and escalations.

## [0.17.0] - 2026-03-17

### Added

- Devin automated PR review adapter: `pr-review-loop.sh` now supports `--platform devin`, polling Devin check runs for completion and collecting inline findings. Added `docs/ai/development-workflow/integrations/devin.md` with setup, bot identity, and adapter contract details.
- Workflow config file (`.ai-dev-workflow.yaml`): declares which review platforms are active for the repository. `pr-review-loop.sh` reads this file automatically when no `--platform` flag is passed, replacing the hardcoded `greptile` default. The project setup protocol generates this file during onboarding.

## [0.16.0] - 2026-03-14

### Changed

- Workflow-next-action: `--development` mode now discovers spec and implementation-plan files with either `.md` or `.doc.md` suffixes (`1_*_specs.md` / `1_*_specs.doc.md` and `2_*_implementation-plan.md` / `2_*_implementation-plan.doc.md`), taking the first match so Cursor/Notion-style doc filenames are supported without requiring a single canonical pattern.
- Prepare-release protocol: added instructions for updating reference-style link definitions in `CHANGELOG.md` so version headers remain clickable comparison links on GitHub; retain existing definitions and use the same tag format as CI (e.g. `v1.2.0`).
- Sync-template: project-specific files are now "review for additive updates" instead of "never touch". The agent compares template vs project and may propose adding template improvements while preserving project-specific content; differences are classified as optional additive updates. Step 3 summary, Step 4 apply rules, and PR description wording updated in the sync-template skill/command.
- Auto-tag-release workflow: upgraded `actions/checkout` from v4 to v5; refactored release notes extraction to use a variable and improved clarity (version stripping and awk escaping for CHANGELOG section matching).

- Review workflow: `REVIEW.md` is now the canonical review contract for spec, plan, and code review gates. Claude Code and Codex now default to native review flows against `REVIEW.md`, Cursor review commands explicitly follow the same contract, and the old review-stage protocols are reduced to compatibility wrappers.
- Automated PR review: `pr-review-loop.sh` and the workflow docs now support ordered multi-platform review loops. Review platforms run sequentially, all gating platforms must be clean or skipped before `ready-for-human-review`, and unsupported adapters such as the planned Devin integration are documented explicitly.
- Workflow orchestration is now split into two supporting protocols: `90-batch-orchestrate-work-protocol.md` for portfolio-level discovery, batching, dispatch, and supervision, and `91-orchestrate-work-protocol.md` for single-item orchestration through reviewer/PR/CI readiness. Added `workflow-batch-plan.sh`, `workflow-item-orchestrator` wrappers for Codex/Cursor/Claude, and updated docs so `workflow-orchestrator` / `/run-work` remain the portfolio-wide entrypoint while targeted resume/advance uses the new item-orchestrator path.

### Fixed

- Claude Code orchestrator agents: added the `Agent` tool to `orchestrator`, `item-orchestrator`, and `automated-reviewer-loop` so they can dispatch sub-agents (developer, code-reviewer, etc.) instead of running all stages inline in a single session.
- pr-review-loop.sh: existing-findings path now correctly counts and reports existing soft-suggestion comments; COMMENT_COUNT and SUGGESTION_COUNT were previously undercounting.
- pr-review-loop.sh: fallback date when neither BSD nor GNU date is available now uses epoch (1970-01-01T00:00:00Z) instead of current time, so all comments are considered rather than none.
- sync-template: include `.cursor/agents/` in the Always sync list so `/sync-template` detects and propagates Cursor agent files; aligns with README framework-level propagation paths.

### Added

- Smoke tester agent: added `smoke-tester` to the AGENTS.md workflow commands table and `agent-model-config.md` (tier assignment, per-agent model recommendations, and tool restrictions) to complete documentation coverage for the smoke test stage.
- Cursor subagents: workflow agents (orchestrator, developer, tech-lead, etc.) are now defined in `.cursor/agents/` with per-agent model selection (`fast`, `inherit`, or specific model ID). Orchestration protocol and `agent-model-config.md` document how to execute with Cursor subagents and override models.

## [0.15.0] - 2026-03-10

### Changed

- Workflow status derivation: `workflow-next-action.sh --development` now infers the current workflow stage from repo state (presence of implementation plan file, feature branch) instead of requiring a `**Status**` line in the spec file. When an issue tracker (e.g. Linear) is the source of truth, the spec file's status field is optional. Updated protocols (01-review-specs, 02-generate-implementation-plan, 02-review-implementation-plan, 04-implement-development, 04-review-implemented-development, 90-orchestrate-work) and `integrations/linear.md` to document the tracker-as-source-of-truth model.
- Post-merge cleanup: the agent now updates the related issue in the issue tracker after running the cleanup script. When the merged branch name contains an issue identifier (e.g. `ENG-123`), the skill/command instructs the agent to set that issue to the merged/done state (e.g. Linear → **Merged**). See `docs/ai/development-workflow/integrations/linear.md` and the post-merge-cleanup skill/command docs.

### Fixed

- Reviewer loop: `pr-review-loop.sh` now checks for existing blocking findings from the bot (e.g. from a review that already ran on PR open) before posting a new trigger. If any exist, it reports `needs_fixes` and exits without triggering so the fixer addresses them first; avoids triggering a new review and ignoring issues already raised. Protocol 92 is now a thin wrapper (scope + follow 90) with no duplicated Step 7/8 procedure.

### Added

- Standalone automated reviewer loop: new protocol `93-automated-reviewer-loop-protocol.md`, Cursor command `/run-reviewer-loop`, Claude Code agent `automated-reviewer-loop`, and Codex skill `workflow-reviewer-loop`. Run the automated reviewer and CI loop for a specific PR (or current branch's PR) until ready for human review or escalated, without full orchestration.
- Post-merge cleanup: `scripts/development-workflow/post-merge-cleanup.sh` plus `/post-merge-cleanup` for Cursor and Claude Code and `post-merge-cleanup` Codex skill. After a development PR is merged and the remote branch deleted, fetches origin, checks out develop, pulls, and deletes the local branch to keep the repo clean.

## [0.14.0] - 2026-03-08

### Fixed

- Implementation plans now explicitly consider project documentation in `docs/`: generate-plan protocol and template require listing doc updates (or "None" with justification), and plan review checks that docs were considered ([#25](https://github.com/lhpaul/ai-dev-framework-template/issues/25)).

### Added

- Workflow helper scripts: `scripts/greptile-review-loop.sh`, `scripts/pr-ci-loop.sh`, `scripts/workflow-next-action.sh`, and `scripts/workflow-lib.sh` so any AI agent or human can deterministically inspect state, poll automated review, and poll CI.

### Changed

- Workflow scripts moved into `scripts/development-workflow/` so template workflow helpers are separate from scripts that downstream repositories add (e.g. `scripts/build.sh`, `scripts/deploy.sh`). All references in docs, AGENTS.md, and skills updated to the new paths.
- AI workflow protocols now treat creator stages as subroutines instead of terminal steps: spec, plan, and implementation runs continue through reviewer gate, PR creation, automated review, and CI until they are actually waiting on a human or escalated.
- Orchestration guidance across Codex skills, Claude agents, Cursor commands, `README.md`, and `AGENTS.md` now defines a persistent control loop with explicit terminal conditions instead of stopping after the next stage finishes.
- Claude agent tool restrictions now allow spec and plan stage agents to use `Bash` when needed for branch creation, commits, pushes, and PR readiness loops.
- Workflow docs now describe the optional GitHub Actions + Codex runtime needed for truly background Greptile fix loops.

## [0.13.0] - 2026-03-02

### Changed

- AI workflow: add a reviewer-agent gate before opening PRs for spec, plan, and implementation stages (so automated PR review tools run only after reviewer approval).
- AI workflow: keep the template's `develop` integration branch + `main` releases, and enforce the reviewer gate before opening PRs.

## [0.12.0] - 2026-03-02

### Added

- `scripts/README.md` documenting the purpose and usage of each helper script in the `scripts/` directory.

## [0.11.0] - 2026-03-02

### Added

- `.codex/skills/` workflow skills for Codex (`workflow-project-setup`, `workflow-spec-writer`, `workflow-spec-reviewer`, `workflow-plan-writer`, `workflow-plan-reviewer`, `workflow-implementer`, `workflow-code-reviewer`, `workflow-orchestrator`) as thin wrappers over the existing protocol documents.
- `.codex/skills/*/agents/openai.yaml` metadata so downstream projects get human-friendly skill names, descriptions, and starter prompts in Codex-compatible UIs.
- `scripts/install-codex-skills.sh` to symlink the repository's Codex skills into the local Codex skill directory.
- `scripts/discover-workflow-state.sh` and `scripts/check-workflow-branch.sh` to give the orchestrator deterministic shell helpers for state discovery and branch/worktree checks.

### Changed

- `AGENTS.md`, `README.md`, and `docs/ai/development-workflow/README.md` to document Codex skill usage and installation alongside the existing Claude Code and Cursor wrappers.
- `.codex/skills/*/SKILL.md`, `AGENTS.md`, and `README.md` to document recommended model tiers for each Codex skill, with `workflow-orchestrator` positioned as the default `economy` entrypoint.
- `README.md` to include copy-paste starter examples for Claude Code, Cursor, and Codex users testing the orchestration flow in downstream repositories.
- `docs/ai/development-workflow/README.md` to use "default integration branch" wording where the template previously hard-coded `develop`, so repository-level branch overrides in `AGENTS.md` remain consistent.
- `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` to document the Codex helper scripts and Codex-specific execution behavior while preserving the shared orchestration protocol.

## [0.10.0] - 2026-02-26

### Added

- `docs/ai/development-workflow/protocols/05-prepare-release-protocol.md` — authoritative release protocol: pre-flight checks, versioning guidance, CHANGELOG update, two-PR approach (main + mandatory develop backport), and CI auto-tagging note.
- `.claude/commands/prepare-release.md` — Claude Code `/prepare-release` command (thin wrapper delegating to the new protocol).
- `.github/workflows/auto-tag-release.yml` — GitHub Actions workflow that automatically creates a git tag and GitHub release when a `release/*` PR is merged into `main`. Extracts the version from the branch name and release notes from `CHANGELOG.md`.

### Changed

- `.cursor/commands/prepare-release.md` — refactored to thin wrapper delegating to `05-prepare-release-protocol.md`; previously had inline steps.
- `docs/ai/development-workflow/README.md` — Release Process section replaced with a summary and link to the new protocol.
- `AGENTS.md` — Prepare Release row now lists `/prepare-release` for Claude Code (was `—`) and references the protocol in the "Any other tool" column.
- `.claude/skills/sync-template.md` — added `.claude/commands/` to always-sync paths; added `.github/workflows/auto-tag-release.yml` to special-handling paths.

## [0.9.0] - 2026-02-26

### Added

- `docs/ai/development-workflow`: Added automated reviewer loop to `protocols/91-orchestrate-work-protocol.md` (Step 8). The orchestrator polls for feedback after every push, dispatches the appropriate fixing agent when blocking issues are found, and escalates to human after timeout or 3 fix cycles. Updated Steps 1, 2, 6, and 7 for consistency.
- `docs/ai/development-workflow/integrations/pr-review-platform.md`: New platform-agnostic integration doc defining what any automated code review tool must provide and what each platform-specific integration doc must specify. Mirrors the `issue-tracker.md` / `linear.md` pattern.
- `docs/ai/development-workflow/integrations/greptile.md`: Added Greptile-specific Step 8 implementation (bot identity, re-trigger command, review completion detection, inline comment fetch). Generic loop mechanics remain in the protocol; only tool-specific commands live here.

## [0.8.0] - 2026-02-26

### Added

- `docs/ai/development-workflow`: Added `Spec In Review` and `Plan In Review` stages to the workflow. These stages make PR-open states explicit so the orchestrator agent knows not to re-dispatch when a spec or plan PR is already awaiting human review. Updated `README.md` (stage diagram, issue tracker status list, Agent Roles Summary table) and `protocols/91-orchestrate-work-protocol.md` (mental map, eligibility table, pre-dispatch branch check).

## [0.7.1] - 2026-02-26

### Changed

- Sync-template workflow now stores template source config in `.tmp/template-config.json` (framework-agnostic, gitignored) instead of `.claude/template-config.json`. Single source for Claude Code remains `.claude/skills/sync-template.md`; Cursor uses `.cursor/commands/sync-template.md`.

## [0.7.0] - 2026-02-26

### Added

- `.claude/commands/code-review.md` — new pipeline for automated PR reviews using parallel Claude agents and confidence scoring.

### Changed

- `docs/ai/development-workflow/protocols/03-review-implementation-protocol.md` — updated implementation review protocol to include Step 2 (Run code-review command) and improved section navigation with an explicit Flow Overview.

## [0.6.1] - 2026-02-26

### Added

- `.claude/agents/smoke-tester.md` — missing Claude Code sub-agent for the smoke test stage; delegates execution to `docs/ai/development-workflow/protocols/04-smoke-test-protocol.md` and `docs/testing/README.md`.

## [0.6.0] - 2026-02-25

### Added

- `docs/ai/development-workflow/protocols/04-smoke-test-protocol.md` — new agnostic smoke test execution protocol with a two-path decision (run committed spec if it exists, fall back to ad-hoc script), standard output format, pass criteria, and fail handling rules. References the project testing README for all project-specific details.
- `docs/testing/README.md` — template for the project-specific smoke test execution guide: decision tree, committed suite path, ad-hoc fallback scaffold (Node.js + Playwright example), selector/waiting conventions, and troubleshooting sections for projects to fill in during setup.
- Testing Strategy section in `docs/project/3-software-architecture.md` — placeholder documenting the two-tier model (committed automated suite as primary path, ad-hoc scripts as stepping stone), the runbook-to-spec relationship, and setup instructions.

### Changed

- `docs/best-practices/3-testing.md` — testing strategy ownership moved to `docs/project/3-software-architecture.md`; this file now points there and focuses on principles and conventions only. Added two-tier execution model note and link to `docs/testing/README.md` in the Smoke Tests section.
- `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` — Step 5 now includes an explicit e2e spec maintenance instruction (keep committed specs in sync; create one when adding a feature with a runbook). Step 6 pre-commit verification separates unit/integration tests from the e2e suite command. Fast Track path updated accordingly.
- Refactored issue tracker integration protocols to remove redundant field definitions and fallback logic.
- Centralized "current brief" definitions and agent expectations in `docs/ai/development-workflow/integrations/issue-tracker.md`.
- Updated `Spec Ready`, `Plan Ready`, and `In Development` protocols to delegate issue-tracker-specific logic to the centralized source.

### Fixed

- Updated all Cursor slash commands to use the correct `/` prefix (replacing incorrect `@` prefix) in all documentation, command descriptions, and protocols.

## [0.5.0] - 2026-02-24

### Added

- `.claude/skills/sync-template.md` — Claude Code skill (`/sync-template`) to sync framework updates from the upstream template into a downstream project; compares files, shows a categorized diff, applies changes only after explicit approval, and generates ready-to-use git instructions
- `.cursor/commands/sync-template.md` — Cursor equivalent (`/sync-template`) with identical behaviour
- `.claude/skills/` added to the list of framework-level paths to propagate in `README.md`
- "Maintenance Commands" table in `AGENTS.md` documenting `/sync-template` and `/sync-template`

## [0.4.0] - 2026-02-24

### Refactored

- Moved `docs/ai/agent-model-config.md` to `docs/ai/development-workflow/agent-model-config.md` for better repository organization.
- Updated documentation links in `AGENTS.md` and `CHANGELOG.md` to reflect the new path for `agent-model-config.md`.

### Changed

- `docs/ai/development-workflow/README.md` — Updated the development lifecycle diagram to specify the `develop` branch as the merge target.

## [0.3.0] - 2026-02-24

### Added

- `docs/ai/development-workflow/agent-model-config.md` — documents model assignments, tool restrictions, and override instructions for all Claude Code agents
- Link to `agent-model-config.md` in the Key Documentation table in `AGENTS.md`

### Changed

- All Claude Code agents (`.claude/agents/`) now declare an explicit `model` field in their YAML frontmatter:
  - `tech-lead` → `claude-opus-4-6` (highest-reasoning stage; architecture decisions benefit from Opus depth)
  - `developer`, `product-manager`, `spec-reviewer`, `implementation-plan-reviewer`, `code-reviewer`, `project-setup` → `claude-sonnet-4-6` (capable and cost-effective for their respective tasks)
  - `orchestrator` → `claude-haiku-4-5-20251001` (mechanical dispatch work; speed and cost matter at orchestration frequency)
- `product-manager`, `spec-reviewer`, and `implementation-plan-reviewer` agents: `Bash` removed from `tools` (least-privilege — these agents only read and write documentation files)
- `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` Step 5: expanded with explicit parallel subagent dispatch instructions — the orchestrator now uses the Claude Code `Task` tool to launch all eligible agents simultaneously in a single message rather than sequentially
- AI development workflow: clarified the Spec Ready stage is product-focused and technical design details belong in the Plan Ready stage.

### Removed

- Framework sync scripts (manual propagation/backporting only).

## [0.2.0] - 2026-02-24

### Added

- Issue tracker branch naming convention: when an issue tracker is in use, branch slugs are prefixed with the issue identifier (e.g., `feature/ENG-123-user-auth`); without a tracker the existing slug convention applies. Documented in `docs/best-practices/2-version-control.md`, `docs/ai/development-workflow/README.md`, all three development protocols, and `docs/ai/development-workflow/integrations/linear.md`

### Changed

- `AGENTS.md` — Git & Branching and CHANGELOG sections updated with project-specific overrides: no `develop` branch (all PRs target `main`), and every merged PR releases a new version
- `docs/best-practices/STACK-SPECIFIC.md` — fixed broken Markdown in placeholder table: replaced nested-bracket links with backtick paths and an inline example for the setup agent

## [0.1.0] - 2026-02-24

### Added

- Staged AI-assisted development workflow (Spec → Plan → Implement → Review → Release) with 8 protocol documents in `docs/ai/development-workflow/protocols/`
- Claude Code agents for all workflow stages (`.claude/agents/`): `product-manager`, `spec-reviewer`, `tech-lead`, `implementation-plan-reviewer`, `developer`, `code-reviewer`, `orchestrator`, `project-setup`
- Cursor commands and rules (`.cursor/`) mirroring the full Claude Code workflow
- Project setup onboarding agent (`docs/ai/setup/protocol.md`) — 12-step structured conversation to generate all project-specific documentation
- Project documentation placeholders (`docs/project/`): business domain, repo architecture, software architecture, database model
- General best practices: coding standards (`1-general.md`), version control (`2-version-control.md`), testing (`3-testing.md`)
- `docs/best-practices/STACK-SPECIFIC.md` as a coordinator document — provides stack summary, quick reference, and links to `docs/best-practices/stack/[technology].md` detail files generated by the setup agent per technology area
- Optional integrations for Linear and Greptile (`docs/ai/development-workflow/integrations/`)
- Spec, implementation plan, and smoke test runbook templates (`docs/ai/development-workflow/templates/`)
- `AGENTS.md` as the universal AI entry point (AGENTS.md open format), with `CLAUDE.md` and `GEMINI.md` symlinks for Claude Code and Gemini CLI compatibility
- `.claude/settings.json` with pre-approved permissions for common git and fetch operations; `.claude/settings.local.json.example` documenting machine-specific overrides for optional integrations
- `.gitignore` covering local Claude settings, `.env` files, and common system files

[Unreleased]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.22.0...HEAD
[0.22.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.18.1...v0.19.0
[0.18.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lhpaul/ai-dev-framework-template/releases/tag/v0.1.0
