# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Markdown lint CI for spec, plan, and CHANGELOG docs** (issue #173): a new GitHub Actions workflow (`.github/workflows/markdown-lint.yml`) runs automatically on every pull request touching `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`. Two complementary checks run in sequence: `markdownlint-cli2` with a root `.markdownlint.jsonc` config enforces trailing-whitespace (MD009, hard-break exception), relative-link resolution via the `markdownlint-rule-relative-links` plugin, and file-ending newline (MD047); a custom Python script (`scripts/lint/markdown-heuristic-lint.py`) adds two heuristic rules — GLOB001 (non-recursive glob in a code block whose surrounding prose uses recursive-language cues) and COUNT001 (narrative count phrase disagreeing with the list that follows). Both rules support inline `<!-- markdown-heuristic-disable RULEXX -->` suppression for confirmed false positives. All baseline violations in existing documents are resolved or suppressed in this PR so the check is green from day one. Local run commands are documented in `AGENTS.md` (Common Commands) and `docs/best-practices/1-general.md`.

- **ShellCheck static analysis for workflow scripts** (issue #136): a new GitHub Actions workflow (`.github/workflows/shellcheck.yml`) runs ShellCheck with `--severity=warning` against all `*.sh` files under `scripts/development-workflow/` on pull requests that touch those files. The workflow uses a `paths` filter so it only gates PRs that include shell script changes; PRs that touch only non-shell files are not affected. A `.shellcheckrc` file suppresses SC1007 project-wide — a ShellCheck false positive for the `CDPATH= cd` idiom (POSIX inline env-var assignment used to prevent `cd` from printing paths) that appears consistently across all workflow scripts. With the `.shellcheckrc` in place, ShellCheck exits green against the current script set from day one.

- **Agent timeout handling guidance**: added timeout-handling documentation across three workflow files (issue #125). `agent-model-config.md` gains an "Expected Run Durations" table (`item-orchestrator`: typical 5–15 min, escalate at ~25 min; `automated-reviewer-loop`: typical 2–10 min, escalate at ~20 min) and a "Resume a Timed-Out Agent Run" section with a PR state detection checklist, resume command, and a bold warning not to manually apply `ready-for-human-review` without completing Step 7. `91-orchestrate-work-protocol.md` Step 8c's reviewer loop summary comment check is now explicitly marked as a hard requirement that agents must not remove or skip. `90-batch-orchestrate-work-protocol.md` Step 5.1 gains a new "Stale / Incomplete PR Detection" subsection with the canonical detection heuristic (non-draft + regression label + no reviewer loop summary comment = incomplete), a one-line `gh pr view` detection command, and the required action (re-dispatch item-orchestrator to resume from Step 7).

- **Pre-dispatch tracker status update (Protocol 90 Step 2.5 and Protocol 91 Step 2)**: the Portfolio Orchestrator now explicitly updates each eligible item's tracker status to the correct in-flight value (`Writing Spec`, `Writing Plan`, or `In Development`) and ensures it is on the project board **before** dispatching any Work Item Runner. Protocol 91 adds a matching note for the single-item dispatch path: when the Work Item Runner is invoked directly and the tracker status is stale, it must apply the same status transition before invoking the creator agent. Both protocols share the same idempotent transition table — resume items (already in-flight) are skipped. Fixes the Batch 3 retro finding where items were not added to the project board or status-updated before dispatch (issue #159).

- **Batch merge command** (`/batch-merge`): a new command and shell script that merge all ready PRs in a parallel batch into `develop` sequentially. Discovers PRs labeled `ready-for-human-review` automatically or accepts an explicit PR list; presents a merge plan for human confirmation before any merge; auto-resolves CHANGELOG `[Unreleased]` conflicts (entries combined, none dropped) and non-overlapping documentation file conflicts; pauses for human input on non-trivial conflicts; runs `post-merge-cleanup` after each successful merge; and produces a structured outcome summary (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, `failed`, `not_attempted`). Available as `/batch-merge` in Claude Code, `/batch-merge` in Cursor, and the `batch-merge` Codex skill. Protocol 90 (batch orchestrator) now includes a Step 5.5 handoff path for merge-ready parallel batches.

- **Retrospective analysis protocol**: a new `/retrospective` command and `06-retrospective-protocol.md` allow developers (or agents) to analyze completed work — a batch or individual item — and identify process improvement opportunities. Each finding is categorized (Workflow & Process, Agent Behavior, Configuration, Documentation, Code Quality, Tooling) and assigned a severity signal (High, Medium, Low). The human chooses an action for each: "Address now" (agent applies a simple fix, commits, and pushes — no new PR), "Add to backlog" (agent creates a GitHub issue directly), or "Skip". Works in two modes: with conversation context (preferred, richer findings) or with GitHub data only (on-demand fallback). Protocol 90 (batch orchestrator) suggests a retrospective after the batch PRs have been merged (not after the Step 6 summary — the retrospective is deferred until after human confirms PRs are merged, via `/batch-merge`, `/post-merge-cleanup`, or an explicit signal); Protocol 91 (work item runner) does the same for standalone item runs only — after the human confirms the PR has been merged (suppressed when `BATCH_CONTEXT=true`). Available as `/retrospective` in Claude Code, `/retrospective` in Cursor, and the `workflow-retrospective` Codex skill.

- **Worktree isolation for parallel batch dispatch**: protocols `90-batch-orchestrate-work-protocol.md` and `91-orchestrate-work-protocol.md` now require each Work Item Runner in a parallel batch to operate in a dedicated git worktree. Includes `BATCH_CONTEXT=true` handoff signal, pre-flight worktree checks, base-branch table for all item types, stage protocol compatibility notes, CWD safety mandate (`cd` to repo root before `git worktree remove`), and corrected Step 10 cleanup sequence (worktree removal before branch deletion).

- **CHANGELOG conflict mitigation for parallel batches** (Protocol 90, Step 3.6): simplified strategy — each PR adds its own CHANGELOG entry as normal; merge conflicts are resolved at merge time by the batch-merge auto-resolution (protocol 94 Step 4.3). The previous consolidation strategy (only last item updates CHANGELOG, others skip via `SKIP_CHANGELOG=true`) was impractical because external reviewers enforce per-PR diff scope and agents don't reliably parse skip signals.

### Changed

- AI Workflow: `93-automated-reviewer-loop-protocol.md` — added mandatory cross-reference check requiring agents to grep edited files for stale references before committing fixes; links to the existing re-read verification section for post-commit confirmation.
- AI Workflow: `implementation-plan-template.md` — added a "Code Samples" section with guidance to mark code samples as illustrative and to ensure all cross-section references are consistent before marking the plan ready.
- **Workflow agent model bump to Opus 4.7**: updated `.claude/agents/tech-lead.md` (`model: claude-opus-4-6` → `model: claude-opus-4-7`) and refreshed the two Opus model-ID examples in `docs/ai/development-workflow/agent-model-config.md` (in-session override example `claude-opus-4-5-20251101` → `claude-opus-4-7`; Cursor permanent-change example `claude-opus-4-6` → `claude-opus-4-7`). Sonnet 4.6 and Haiku 4.5 remain unchanged — only Opus had a newer latest model to pick up. No tier reassignments, no tool restriction changes (issue #160).

### Fixed

- **CHANGELOG trailing-whitespace prevention** (issue #178): all four implementation paths in `03-implement-development-protocol.md` (Full Pipeline Step 6, Refactor Step 6, Fast Track Step 6, Hotfix Step 6) now include an explicit CHANGELOG format verification sub-step. The sub-step instructs the developer agent to check for trailing whitespace and trailing blank lines after writing a CHANGELOG entry and before staging; provides the shell command `git diff CHANGELOG.md | grep '^+' | grep -P '\s+$'` for automated detection; and explicitly exempts intentional two-space Markdown hard line breaks. The matching key rule is added to both `.claude/agents/developer.md` and `.cursor/agents/developer.md` so the check is surfaced at agent initialization for both Claude Code and Cursor runners.

- **Remove boilerplate "Guiding principle" section from spec template** (issue #165): deleted the `## Guiding principle (important)` section and its 4-line body from `docs/ai/development-workflow/templates/spec-template.md` and from all 7 existing merged spec files that contained it (`retrospective-protocol`, `batch-merge`, `136-shellcheck-workflow-scripts`, `agent-timeout-handling`, `batch-merge-ff-pull-retry`, `coderabbit-success-fallback`, `173-markdown-lint-plan-spec-docs`). The guidance already lives in `01-generate-spec-protocol.md` under "Product-first boundary (critical)" and is enforced by `REVIEW.md`; the per-spec copy was dead-weight boilerplate that added no information for readers.

- **Missing `.cursor/commands/retrospective.md` command file**: created the Cursor command file for the retrospective workflow, which was omitted when the retrospective protocol feature (#113) was implemented. Every other workflow stage has a corresponding file in `.cursor/commands/`; the retrospective now has parity with its Claude Code counterpart at `.claude/commands/retrospective.md`.
- **Unbound variable in `add-backlog-item.sh create`**: fixed `labels[@]: unbound variable` error (bash `set -u`) that occurred when no `--label` flags were passed. The array iteration now uses the `${var[@]+"${var[@]}"}` guard so an empty `labels` array expands safely to nothing rather than triggering an error.
- **Worktree blocking post-merge-cleanup branch deletion**: `post-merge-cleanup.sh` now detects when the branch being deleted is still checked out in a worktree, removes that worktree with `git worktree remove --force`, and then deletes the branch — preventing the `error: cannot delete branch used by worktree` failure that left issues unclosed during batch merges. Protocol `94-batch-merge-protocol.md` Step 4.2 adds a matching pre-cleanup step to check for and remove worktrees associated with the merged branch.
- **Worktree leak prevention**: added three safeguards to prevent worktree agent file modifications from leaking into the main working tree during parallel batch runs. (1) Protocol 91 post-worktree verification now checks `git status --porcelain` on the main working tree in addition to the branch check, and stops with an error and escalation if any unexpected modifications are found. (2) Protocol 90 Step 5.2 (new) instructs the Portfolio Orchestrator to run a `git status` check on the main working tree after each Work Item Runner returns in a parallel batch, halting further agent dispatch if modifications are detected. (3) Protocol 94 Step 3.5 (new) adds a pre-merge clean-state check that aborts batch merge if the main working tree is dirty or on the wrong branch before any `git merge` is executed (issue #150).

- **Cross-reference consistency check in developer protocol**: `03-implement-development-protocol.md` now requires a cross-reference consistency check in the pre-implementation scope checklist (item 6, all four paths) and the Quality Rules section. When a change modifies policy or rule text that appears in multiple files, developers must grep for key phrases, list every matched location, and confirm all locations are updated consistently before opening a PR. This addresses the root cause of multi-cycle review loops on cross-cutting documentation changes (e.g., PR #120 required 8 cycles due to inconsistencies across 10+ files).
- **Worktree agent main-branch safety rule (Protocol 91)**: added an explicit safety rule to the worktree isolation section of `91-orchestrate-work-protocol.md` prohibiting agents running inside a worktree from running `git checkout`, `git switch`, or any other branch-switching command that targets the main working tree. Violations leave the main repo checked out on a `worktree-agent-*` branch, breaking all subsequent agent and human operations. The rule requires agents to use `git -C <main-repo-root>` for read-only main-repo queries and to verify that the main working tree is still on `develop` before worktree cleanup — stopping with an error and escalating to the human if the branch has changed (issue #111).

- **Pre-implementation scope checklist in Protocol 03**: all four implementation paths (Full Pipeline, Refactor, Fast Track, Hotfix) in `03-implement-development-protocol.md` now require a scope checklist before writing any code. The checklist asks the agent to enumerate all files to be changed, describe the specific change needed per file, verify all changes are within the issue's scope, consider edge cases (existing branch, worktree context, failure modes), and cross-reference related protocols for consistency. This prevents implementation gaps that lead to multi-round review cycles.

- **Item-orchestrator model upgrade to balanced tier**: upgraded `item-orchestrator` agent from economy (haiku) to balanced (sonnet) tier in `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md`. Economy models struggle with the multi-step reasoning required to parse review findings, determine correct fixes, and verify fixes are present during review-fix-review cycles. This upgrade ensures the Work Item Runner can reliably supervise these cycles without requiring manual takeover (issue #109).
- **Audit confirms `.gitignore` covers all agent-created temporary paths**: `.gitignore` is complete for agent-orchestration scenarios, with proper exclusions for `.claude/worktrees/` (agent worktree isolation), `.tmp/` (local developer overrides like `template-config.json`), `.claude/settings.local.json` (local settings), and system files. Prevents accidental re-introduction of agent-created artifacts into version control, following the issue resolution from PR #99.
- **Enforce `develop` as default PR base branch (Protocol 03)**: all four implementation paths in `03-implement-development-protocol.md` now use explicit `--base develop` (or `--base main` for hotfixes) in their `gh pr create` commands, with accompanying documentation notes. This prevents accidental PR creation to `main` or other branches when agents open pull requests. Path 3 (Fast Track) now includes its own command example instead of only referencing Path 1. Path 4 (Hotfix) clarifies that `--base main` is required for production fixes.
- **Label readiness checklist gate (Steps 8a/8b in Protocol 91)**: added a hard gate before applying `ready-for-human-review`. Step 8a verifies the PR is non-draft, confirms the `ready-for-regression` label is present on implementation PRs, and removes a stale `needs-fixes` label if present (since CI is green and reviews are clean at this point) before applying `ready-for-human-review`. Step 8b extracts the tracker status update into its own distinct step. This prevents the PR from briefly holding both `ready-for-human-review` and `needs-fixes` simultaneously, enforcing the mutual exclusivity required by Protocol 92.
- **Scope boundary rule (agent enforcement)**: added explicit "scope boundary" rule to protocols `03-implement-development-protocol.md` and `91-orchestrate-work-protocol.md` to prevent agents from making changes outside their assigned issue's scope. When implementing any path or dispatching a stage agent, modify only files directly related to the assigned issue; if a review finding requires changes outside scope, document it as a separate issue and move on — do not fix it in the current PR. This prevents merge conflicts, scope creep, and wasted review cycles, especially critical in parallel batch orchestration.
- **Implementation protocol pre-branch fetch**: all four paths (Full Pipeline, Refactor, Fast Track, Hotfix) in protocol `03-implement-development-protocol.md` now include `git fetch origin` before branching from `develop` or `main`, matching the pattern already used in the prepare-release protocol (`05`). This prevents merge conflicts caused by stale local remote-tracking refs when creating feature/refactor/fix/hotfix branches.
- **Reviewer loop verification (Protocol 93)**: added explicit "Verification: Re-read to confirm each fix" section requiring fixer agents to re-read specific file/line references in review findings before marking them resolved. This prevents premature dismissal of findings based on memory alone and ensures substantive code changes are actually present in the PR.
- **Stuck-loop detection for review cycles (Protocol 93)**: added protocol-level heuristics to detect stuck fix-review loops — no-progress detection across consecutive cycles, reappearing findings after resolution, and a hard maximum cycle count with mandatory escalation. Complements existing per-platform timeouts in `pr-review-loop.sh`.
- **Prepare-release pre-flight sync**: the release protocol now runs `git fetch origin && git pull origin develop` (with a code block and failure guidance) before creating the release branch, preventing stale local state from being released. The `/prepare-release` command wrappers (Claude Code and Cursor) also now explicitly list this as a key rule. `git fetch` is also added to the Claude Code command's `allowed-tools`.
- **Post-dispatch PR verification step for orchestrator (issue #123)**: protocol `90-batch-orchestrate-work-protocol.md` Step 5.1 and protocol `91-orchestrate-work-protocol.md` Step 8c now require the orchestrator to independently verify actual PR state via `gh pr view` before reporting any PR as ready for human review. Verification covers base branch correctness, non-draft state, required labels (`ready-for-regression`, `ready-for-human-review`, absence of `needs-fixes`), presence of the automated reviewer loop summary comment, and green CI checks. Trusting Work Item Runner self-reports without verification caused 50% of batch 1 PRs to have at least one issue requiring human correction.
- **Pre-dispatch merged-PR cross-check (issue #142)**: protocol `90-batch-orchestrate-work-protocol.md` Step 1a now cross-checks each candidate item against `gh pr list --state merged` before building the portfolio map. If a merged PR already exists for an item whose tracker status is stale, the orchestrator updates the tracker to Merged, closes the issue, and excludes it — preventing duplicate agent runs on already-completed work.
- **Post-merge cleanup now closes GitHub issues (issue #144)**: `post-merge-cleanup.sh` now detects the issue number from the branch name (e.g., `fix/123-slug` → issue #123) and closes the GitHub issue with a comment linking the merged PR. This prevents issues from remaining open after their PRs are merged.
- **CodeRabbit rate-limit handling in `pr-review-loop.sh`**: when CodeRabbit posts a rate-limit comment instead of a review (common in parallel batches with 3+ PRs), the script now detects the comment, waits 3 minutes, and retries with `@coderabbitai review` (up to 2 retries, configurable via `CODERABBIT_RATE_LIMIT_MAX_RETRIES` and `CODERABBIT_RATE_LIMIT_WAIT`). Also added Step 3.7 to `90-batch-orchestrate-work-protocol.md` documenting this behavior and fallback guidance for human reviewers.
- **Transient `git pull --ff-only` failure retry in `batch-merge.sh`** (issue #174): the `cmd_merge` function now retries a failed fast-forward pull once instead of immediately failing. If the first `git pull --ff-only origin "$TARGET_BASE"` fails, a diagnostic message is emitted to stderr, the script sleeps 2 seconds, runs `git fetch origin "$TARGET_BASE"` to refresh the remote-tracking ref, then retries the pull. Only if the retry also fails is `merge_die` called with the original divergence message. Genuine divergences still produce `MERGE_RESULT=failed`; clean first-attempt pulls have zero added latency.
- **CodeRabbit SUCCESS commit-status fallback in `pr-review-loop.sh`** (issue #166): when the CodeRabbit retry budget is exhausted and no inline review comment has appeared, `run_coderabbit_review()` now queries the GitHub commit-status contexts for the current HEAD SHA. If a CodeRabbit status context with `state: SUCCESS` is found, the script exits with `RESULT=clean` and `REASON=coderabbit_status_success_fallback` instead of falling through to stale-findings recovery or escalating. This eliminates spurious `timeout` escalations on parallel batches where CodeRabbit signals results via commit status during rate-limit windows. Step 3.7 of `90-batch-orchestrate-work-protocol.md` is updated to document the new fallback path.
- **Require all review threads resolved before ready-for-human-review** (issue #167): `pr-review-loop.sh` now calls a new `check_unresolved_threads` function as the final gate in its aggregate exit block when all platforms return `clean` or `skipped`. The function uses the GitHub GraphQL `reviewThreads` API with cursor-based pagination (up to 10 pages, warning emitted beyond that), filters to threads whose first comment is authored by a configured bot login (derived via the new `bot_login_for_platform` helper), and counts threads where `isResolved=false` and body does not contain `✅ Addressed`. If any unresolved threads remain, the script exits `needs_fixes` with `REASON=unresolved_review_threads` and `UNRESOLVED_THREAD_COUNT=N`. This prevents Nitpick/Trivial threads from being silently bypassed. Protocol 91 Step 8c gains a new "All automated-reviewer `reviewThreads` resolved" verification row. Protocol 90 Step 5.1 gains the same check. The Step 7 Automated Reviewer Loop Summary template gains a "Reply-only resolutions" subsection listing threads resolved via reply + `resolveReviewThread` mutation (no code fix) for human-reviewer auditability.
- **Subagent permission-denial mitigation** (issue #172): `item-orchestrator` subagents that encounter a tool-permission denial (`Edit` or `Bash`) during a parallel batch run now exit immediately with a structured `SUBAGENT_PERMISSION_DENIAL:` message rather than proceeding with partial work. `90-batch-orchestrate-work-protocol.md` gains a new **Step 4.1** that detects this signal after each Work Item Runner returns, logs the denial, switches to inline execution from the main session using the same pre-created worktree, and marks the item in the batch summary as `inline fallback (permission denial: [tools])`. If both the subagent and inline fallback fail, the item is marked `blocked` and the human is notified — no further retries and no `needs-fixes` label (permission denial is an infrastructure failure, not a content failure). `91-orchestrate-work-protocol.md` gains a new **Step 3.5** pre-flight permission self-check (optional but recommended) and an early-exit rule in the worktree isolation section that applies throughout the subagent run. A smoke-test runbook is available at `docs/testing/workflow/subagent-permission-denial.smoke-test.md`.
- **Locked-worktree handling in `post-merge-cleanup.sh`** (issue #177): `post-merge-cleanup.sh` now handles the `fatal: cannot remove a locked working tree` error that caused cleanup to fail after parallel batch merges when Claude Code subagent runtimes left worktrees in a locked state. When the initial `git worktree remove --force` fails with the locked-worktree message, the script emits a force-override warning (including the worktree path and detected lock reason), attempts `git worktree unlock` followed by `git worktree remove --force`, and falls back to `git worktree remove --force --force` (double-force) if unlock is unavailable or fails. If both paths fail, the script exits non-zero with a clear error. Non-locked worktrees and branches with no worktree continue to use the existing code path unchanged.
- **Same-batch tool-fix ordering hazard detection** (issue #199): `workflow-batch-plan.sh` now classifies each development folder as a tool-fix item by scanning all `*.md` files in the folder for exact-path references to the canonical workflow tool file set (`pr-review-loop.sh`, `pr-ci-loop.sh`, `batch-merge.sh`, `post-merge-cleanup.sh`, any `docs/ai/development-workflow/protocols/*.md`, `.ai-dev-workflow.yaml`). Delimiter-aware regex boundaries (not plain `grep -F`) prevent superstring false positives (e.g., `pr-review-loop.sh.bak` does not match). `TOOL_FIX=yes|no|unknown` is emitted per item before the `workflow-next-action.sh` call so it appears even for folders without spec/plan documents (`unknown`). When `TOOL_FIX=yes`, `TOOL_FIX_FILES=<comma-separated paths>` is also emitted. `90-batch-orchestrate-work-protocol.md` Step 3 gains a new "Same-batch tool-fix ordering hazard" subsection documenting the serialize-first rule, multiple-tool-fix-item ordering (due date → priority → creation date), already-waiting handling, `TOOL_FIX=unknown` treatment (same as `yes`), tracker-derived conservative override, and the human override path.

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

[Unreleased]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.21.0...HEAD
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
