# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.24.1] - 2026-04-30

### Fixed

- **GitHub Actions SHA pinning**: pin `actions/checkout` and `actions/setup-node` to commit SHAs instead of version tags in `deploy.yml`, `e2e-regression.yml`, and `shellcheck.yml` for supply chain security
- **`add-backlog-item.sh` empty value validation**: `--body-file` and `--label` options now reject empty strings in addition to missing arguments
- **`workflow-batch-plan.sh` issue-number skip logic**: gate the "no issue number" skip on GitHub Projects being configured — repos using Linear (no `GITHUB_PROJECT_NUMBER`) no longer incorrectly skip all folders without numeric prefixes in their slugs

## [Unreleased]

### Added

- **External feedback pipeline: GitHub Discussions staging and triage protocol** (#459): Adds `CONTRIBUTING.md` directing external users to submit feedback via GitHub Discussions, a triage protocol (`07-feedback-triage-protocol.md`) for periodic review and promotion of high-signal community feedback to tracked issues, and the `feedback-staging` label for promoted issues.
- **PR-Agent integration**: self-hosted automated PR review via GitHub Actions using a configurable LLM backend (DeepSeek or Kimi K2.6) — no per-seat pricing; cost is LLM API token usage only. Adds `pr-agent` platform support to `pr-review-loop.sh` with a new `run_pr_agent_review()` adapter, `.github/workflows/pr-agent.yml`, `.pr_agent.toml`, and an integration guide at `docs/workflow/development-workflow/integrations/pr-agent.md`. (#499) Fixes a config race condition where PR-Agent merges TOML settings after its initial fallback check — a TOML-only configuration silently fell back to OpenAI defaults (`gpt-5.4` / `gpt-5.4-mini`) and failed with `dummy_key` auth errors. Pins `config.model`, `config.fallback_models`, `config.model_weak`, `github_action_config.pr_actions`, `auto_review`, `auto_describe`, and `auto_improve` as GHA env vars in the workflow so they take effect before the fallback fires; `model_weak` is also added to `.pr_agent.toml` as defense-in-depth.
- **Add structured retro metrics and meta-retrospective protocol** (#458): Adds a required metrics block step (Step 3d) to the retrospective protocol and a new `06b-meta-retrospective-protocol.md` for periodic verification of improvement effectiveness, along with the initial `docs/workflow/retro-metrics.md` tracking log. Updates agent, skill, and documentation files to reference the metrics block and the meta-retrospective protocol.
- **Add Playwright-based design review for frontend changes** (#450): Adds a `design-reviewer` agent (`.claude/agents/design-reviewer.md` and `.cursor/agents/design-reviewer.md`) that uses `playwright_cli` to render affected pages, capture screenshots, check browser console errors, and run axe-core accessibility checks (WCAG 2.1 Level AA). Protocol 91 Step 7a is updated to invoke the design-reviewer agent during the internal review gate for implementation PRs that include frontend file changes. Gracefully skips when no frontend changes are detected, when the browser automation provider is unavailable, or when the preview URL cannot be reached.
- **Split code review into spec-compliance and code-quality passes** (#449): Step 7a internal review gate now runs two sequential passes for implementation PRs — Pass 1 (Spec Compliance) before Pass 2 (Code Quality). Spec and plan PRs remain single-pass. REVIEW.md Code Review Checklist is split accordingly, and code-reviewer agent/skill files are updated to scope evaluation per pass.
- **Add attempt tracking to reviewer loop prompts** (#448): Fixer agents dispatched on retry (cycle ≥ 2) now receive an attempt-context prefix in their prompt summarising what prior attempts addressed and what findings remain open, enabling them to avoid repeating failing approaches and converge faster. Protocol 91 Step 7 and Protocol 93 both document the injection rule and required prompt format.
- **Add pre-merge setup signal for PRs requiring human configuration** (#367): Adds a `needs-setup` label and a standardised `## Pre-merge Setup` PR body section so agents surface infrastructure dependencies (env vars, secrets, DNS records) at PR readiness time rather than requiring the human to read the diff. Protocol 91 Step 8a now includes a diff-scan heuristic step; protocol 92 defines the label semantics and valid co-label combinations.
- **Add `custom_fields` support for issue tracker config** (#453): Adds a `custom_fields` flat map under `issue_tracker` in `.ai-dev-workflow.yaml` and a `workflow_issue_tracker_custom_field` helper function in `workflow-lib.sh` to read individual custom field values. Updates Linear and GitHub Projects integration docs to document recognised fields.

### Fixed

- **Apply mechanical reviewer findings inline before dispatching a fixer sub-agent** (#495): Protocols 91 (Step 7) and 93 now include an inline fix rule — when all blocking findings are mechanical (single file, fully described, ≤ 5 lines), the orchestrator applies them directly using Edit/Bash tools without spawning a sub-agent, eliminating the 10–20 minute startup overhead for one-line changes.
- **Automate GitHub Projects tracker status update on PR merge** (#463): adds `.github/workflows/update-tracker-on-merge.yml` — a GitHub Actions workflow triggered when a `spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `refactor/*`, or `hotfix/*` PR is merged to `develop`. The workflow extracts the issue number from the branch name and updates the GitHub Projects v2 Status field to `Spec Ready`, `Plan Ready`, or `Merged` accordingly; implementation branches also close the linked issue. Eliminates stale statuses that persisted until the next orchestrator run. Requires `GITHUB_PROJECT_NUMBER` and `GITHUB_PROJECT_OWNER` repository variables. Updates `docs/workflow/development-workflow/integrations/github-projects.md` with setup instructions.
- **Branch-type-aware timeout in `pr-review-loop.sh`** (#462): on `spec/*` and `implementation-plan/*` branches, Devin has no trigger condition and exits immediately with `REASON=no_check_run`. The script now automatically reduces `--max-wait` from 1200 s to 60 s and `--poll-interval` from 120 s to 30 s for these branch types when the caller does not pass the respective flag explicitly, preventing 20-minute wait-budget waste on non-implementation PRs.
- **Fixer agents must fix all occurrences of flagged literal values** (#426): added mandatory all-occurrences rule to Protocol 93 fix-cycle guidance — when a reviewer flags a literal value (numeric constant, hex value, identifier, repeated string), fixer agents must `grep -n` the old value across all affected files and fix every occurrence in the same commit before pushing.
- **Mandatory "Automated Reviewer Loop Summary" comment after `pr-review-loop.sh`** (#461): Protocol 91 Step 7 now uses explicit mandatory language ("You MUST post a PR comment...") for the summary comment after every non-skipped exit result (`clean`, `needs_fixes`/escalate, `max_cycles`). The result table is updated to call out the requirement per exit path. Previously, the language was passive and agents omitted the comment when the loop exited cleanly, causing the Step 8c `hasReviewSummary` hard gate to block `ready-for-human-review`.
- **Cross-section consistency check in tech-lead plan protocol** (#427): added mandatory self-check step in `02-generate-implementation-plan-protocol.md` requiring the tech-lead to verify all function names, constants, and decision indices are defined consistently across plan sections before committing; added matching blocking checklist entry in `REVIEW.md` plan review
- **CHANGELOG duplicate section headers after clean parallel merge** (#468): `batch-merge.sh` now runs `check-changelog-duplicate-headers.sh` immediately after each clean merge; if duplicate `### Category` headers are detected within `[Unreleased]`, they are auto-consolidated (bullets merged under the first occurrence, original section order preserved) and the merge commit is amended before pushing. Protocol 94 Step 4.1 documents the new `CHANGELOG_DEDUPED` output field and deduplication behavior.
- **Async bot thread re-check in Step 8a.1** (#486): adds a mandatory 10-second wait + GraphQL re-query after the label readiness checklist passes to catch late-arriving review threads from async bots (e.g., `codex-github`). If new unresolved threads are detected, the agent removes `ready-for-human-review`, adds `needs-fixes`, and returns to Step 7a. Introduces exit code 5 (`late-arriving async bot threads detected`). Uses a shell-interpolated `JQ_FILTER` variable (instead of the unsupported `--jq --arg` flag combination) in both the pre-Check-4 gate and the Step 8a.1 re-check, injecting `CODEX_GITHUB_BOT_LOGIN` at assignment time so the correct bot login is always matched. Strips the `[bot]` suffix from `CODEX_BOT_LOGIN` before use in the JQ filter and in `run_codex_github_review()` before calling `check_unresolved_threads()` — GraphQL `author.login` values omit the `[bot]` suffix that REST API logins carry, so the default `"codex-ai[bot]"` would otherwise never match any Codex-authored thread.
- **`codex-github-reviewer.sh` response detection**: script now polls both `issues/{PR}/comments` (matching bot login with and without `[bot]` suffix) and `pulls/{PR}/reviews` (for finding-based reviews), eliminating the 5-minute timeout on clean PRs and detecting findings immediately instead of waiting for a timeout
- **`codex-github-reviewer.sh` retry-on-timeout** (#497): default `--max-wait` raised from 300 s to 600 s (10 min) per attempt, and a new `--max-retriggers` option (default `1`) automatically re-posts the trigger comment once after a timeout before exiting. Handles the recurring failure mode where Codex silently drops the first `@codex review` request — a re-post usually produces a response. Worst-case wait is `(MAX_RETRIGGERS + 1) * MAX_WAIT` (default 20 min); set `--max-retriggers 0` to keep the previous single-attempt behavior.

### Changed

- **Retrospective command dispatches agent; balanced model tier** (#457): `/retrospective` (Claude Code and Cursor) now dispatches the `retrospective` agent instead of running inline. The `retrospective` agent model is upgraded from `economy` (`claude-haiku-4-5-20251001` / `fast`) to `balanced` (`claude-sonnet-4-6` / `inherit`) — synthesis and pattern-recognition across multiple PRs requires a capable model.
- **Default internal reviewer switched from `codex` to `codex-github`**: replaced the `codex` CLI reviewer (unreachable from Claude Code and Cursor subagent runners, causing a warning on every automated PR) with `codex-github` (Codex GitHub App — universally reachable via `gh` CLI from any runner context) in the default `.ai-dev-workflow.yaml` `internal_reviewers` list. Requires the Codex GitHub App to be installed on the repository.
- **`codex-github` promoted from `internal_reviewers` (Step 7a) to `review.platforms` (Step 7)** (#486): `codex-github` now behaves like `greptile` and `devin` — handled deterministically by `pr-review-loop.sh` with idempotent pre-check, trigger, poll, and result phases. Removes the async race condition inherent in the synchronous internal-reviewer gate. Adds `run_codex_github_review()` to `pr-review-loop.sh`, updates `bot_login_for_platform()` to return the configured bot login, moves the `codex-github` entry from `internal_reviewers` to `platforms` in `.ai-dev-workflow.yaml`, and removes `codex-github` from the Step 7a reviewer dispatch table and reachability table in Protocol 91.
- **Exit code contract table in Protocol 91 Step 8a** (#433): added a prominent table documenting exit codes 0–4 at the top of the Label Readiness Checklist to prevent future exit code collisions
- **`product-manager` agent upgraded to `premium` model tier** (#456): spec writing is the highest-leverage task in the pipeline — a weak spec cascades into worse plans and worse implementations. Updated `agent-model-config.md` rationale, model IDs in `.claude/agents/product-manager.md` and `.cursor/agents/product-manager.md` (to `claude-opus-4-7`), and Codex skill tier in `.codex/skills/workflow-spec-writer/SKILL.md` (to `premium`).

## [0.24.0] - 2026-04-29

### Added

- **`codex-github` integration reviewer path** (#309): runner-agnostic internal reviewer that posts a trigger comment to a PR and polls for the Codex GitHub App bot response. Works from Claude Code, Cursor, headless CI, and Codex runner contexts.
- **Parallel batch file-level conflict detection** (#324): batch orchestrator extracts declared file sets from implementation plans and automatically serializes items with overlapping files before dispatch.
- **Async/concurrency safety checklist** (#348): conditional checklist in plan protocol and review contract for concurrent event sources — covers shared mutable state, re-entrancy, event deduplication, listener cleanup, and race conditions.
- **Template-fit check in plan protocol** (#413): Step 0 gate verifies specs are sufficiently generic for template repositories before writing plan content. Prevents wasted cycles on framework-specific specs.
- **Sync-template migration notes**: versioned manual migration steps in `sync-manifest.yaml` with pre-sync checklist presentation when downstream `last_synced_version` predates a breaking change.

### Changed

- **Bash 3.2 compatibility rule**: workflow scripts must avoid bash 4+-only syntax (`local -A`, `declare -A`, etc.) since macOS ships bash 3.2. Added to developer agent rules and Protocol 03 ShellCheck blocks.

### Fixed

#### Review verification gates

- **GraphQL `reviewThreads` verification before `ready-for-human-review`** (#425): mandatory gate runs the query inline and blocks with exit code 4 if unresolved bot-authored threads exist.
- **`ready-for-regression` verification before `ready-for-human-review`** (#424): hard blocking gate with exit code 3 prevents skipping Step 7b under token pressure.
- **Re-query `reviewThreads` after each push** (#330): mandatory fresh query after every fixer push before proceeding to Step 7b/8.
- **Commit SHA verification before marking findings resolved**: agents must confirm cited commits exist in `git log` before recording `resolved_commit`.

#### Worktree isolation

- **Runtime CWD guard** (#411): new `worktree-cwd-guard.sh` provides wrapper functions that assert CWD is inside the worktree before executing state-changing git commands.
- **CWD safety for Step 5.2** (#383): `MAIN_REPO_ROOT` derived via `git-common-dir` instead of `--show-toplevel` to prevent false results when CWD drifts.
- **Worktree discipline pre-operation checklist**: explicit confirmation required before state-changing git commands in Protocol 91, 93, and all four Protocol 03 branching paths.

#### Batch merge and PR state

- **`batch-merge.sh` now pushes and calls `gh pr merge`** (#412): PRs no longer left in `OPEN` state after batch push.
- **Branch deletion waits for MERGED confirmation**: new `delete-branch` subcommand re-checks PR state before deletion.
- **Pre-merge conflict marker guard**: exits non-zero with diagnostic if unresolved markers present.
- **Sequential merge calls required** (protocol 94): explicit sequencing rule prevents conflicted working tree cascade.

#### Shell script robustness

- **Shell script quality checklist** (#388): covers jq variable injection, SIGPIPE handling, exit code semantics, `local` trap, `gh` error handling, and input validation.
- **`jq` control character handling** (#375): replaced `jq` pipelines with Python3 `json.load()` for tracker API responses.
- **GraphQL mutation parameterization**: switched to `-f` typed variables, eliminating shell interpolation injection risk.

#### Tracker and project board

- **Project board update before issue close** (#361): ensures project item is visible during lookup.
- **`GITHUB_PROJECT_NUMBER` fallback to YAML config**: reads `issue_tracker.project_number` from `.ai-dev-workflow.yaml` when env var absent.
- **Team-prefixed issue identifiers** (#341): extended regex to match Linear-style `<team>-<number>` patterns.

#### Sync-template

- **Post-apply path verification**: verifies cross-references resolve to actual files after applying synced content.
- **Rename detection and cleanup**: detects stale old directories after template renames and offers cleanup actions.
- **Wildcard `rm -rf` fix**: scoped cleanup to `$TEMPLATE_TEMP_DIR` instead of `/tmp/template-sync-*`.

#### Protocol enforcement

- **`ready-for-regression` enforcement at Step 5.1** (#422): orchestrator is primary enforcement point, applies label directly and re-runs CI loop.
- **Pre-dispatch environment validation** (#423): Step 3.3 checks for stale worktrees and integration-branch divergence before dispatch.
- **Spec-plan ordering gate** (#373): plan PR cannot open until spec PR is merged.
- **Trivial-fix skip rule** (#402): skips Step 7a re-run for cosmetic fixes under 10 lines.
- **Retrospective timing guardrail** (#410, #419): structural separation prevents retrospective offer before PRs merge.
- **Step 5.2 recurrence tracking** (#362): tallies violations across batches with escalation threshold.

#### Other fixes

- **Stale Devin error status bypass** (#404): `pr-ci-loop.sh` detects stale commit-status errors with no remaining findings.
- **Stale development folders without issue numbers** (#399): emits `skip` instead of false Plan Ready status.
- **Plan reviewer technical accuracy checklist** (#403): requires verification of behavioral claims against source files.
- **`hasReviewSummary` check false negatives**: extended patterns to match both full and abbreviated comment titles.
- **CHANGELOG exemption for spec/plan PRs** (#340): explicit steps and blocking review finding.
- **Cross-cutting checklist file enumeration** (#389): plans must list all affected agent/skill files.
- **Fixer batching rule** (#372): all fixes applied and pushed once per dispatch cycle.
- **`.worktrees/` gitignored**: both worktree path conventions now excluded.

## [0.23.2] - 2026-04-27

### Fixed

- **`shift 2` without guarding `$2` in `add-backlog-item.sh`**: Option parsing for `--title`, `--body`, `--body-file`, and `--label` called `shift 2` even when no value argument followed, which aborts the script under `set -e`. Fixed by validating `$# -lt 2` before each shift and emitting a clear error message.

- **`local IFS=','` leaking across function scope in `batch-merge.sh`**: Setting `local IFS=','` inside the explicit-PR parsing block left IFS altered for all subsequent code in the same function. Replaced with `IFS=',' read -r -a _pr_tokens <<< "$explicit_prs"` (IFS scoped to the read command only) and declared the array with `local -a` to prevent it from escaping the function.

- **Branch name used as unescaped grep regex in `post-merge-cleanup.sh`**: The worktree lookup used `grep -B2 "branch refs/heads/$TO_DELETE$"`, interpreting the branch name as a regex pattern. Branch names containing `.`, `+`, or other metacharacters could produce false matches, and `grep -F` without a line-boundary check would additionally match branch names that are a prefix of another checked-out branch. Replaced the grep pipeline with an `awk` exact-string comparison (`$0 == branch`) against the structured porcelain output, eliminating both the regex-injection risk and the prefix-match false positive.

## [0.23.1] - 2026-04-26

### Fixed

- **Bot login format mismatch in GraphQL thread audit** (`pr-review-loop.sh`):
  `bot_login_for_platform()` passed `[bot]`-suffixed bot logins to `check_unresolved_threads`,
  but the GitHub GraphQL API returns `author.login` without the suffix for bot-authored comments.
  The string comparison always failed, causing the unresolved thread gate to report zero unresolved
  threads even when unresolved bot threads existed. Fixed by removing the `[bot]` suffix from
  `bot_login_for_platform()` return values to match the GraphQL API contract. Updated documentation
  and smoke test to reflect that GraphQL returns bare bot login strings.

## [0.23.0] - 2026-04-25

### Added

- **Retrospective template-aware backlog cross-reference with version tracking** (#299): Adds optional `template.repository` and `template.last_synced_version` fields to `.ai-dev-workflow.yaml`. Extends retrospective Step 3 to classify findings against the upstream template backlog (already tracked / already fixed / contribute upstream). Updates sync-template skill to record the last-synced version automatically. Backwards-compatible — silently skipped when not configured.

- **Sync-template manifest-driven reliability** (#252): Introduce `sync-manifest.yaml` as the authoritative file list for sync-template; add `<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->` HTML-comment annotation markers to mixed-content files (`AGENTS.md`, `.ai-dev-workflow.yaml`); update all sync-template artefacts (`.claude/commands/sync-template.md`, `.claude/skills/sync-template.md`, `.cursor/commands/sync-template.md`) to consume the manifest with graceful fallback when absent; add new Codex skill `workflow-sync-template`; update `AGENTS.md` Maintenance Commands table to include `workflow-sync-template` in the Codex column.

- **Database migration review checklist** (`REVIEW.md`): trigger/backfill arithmetic parity when both exist in the same migration.

- **Scope-drift guardrails for spec and plan authoring**: protocol updates now require brief-objective coverage matrices and PR-visible deferral notes in spec writing, plus live repo verification logs for pattern-based plan scope checks; review checklists and agent/skill entrypoints were aligned, and a workflow fixture was added for stale-enumeration validation.
- **Release post-merge cleanup command** (`prepare-release-post-merge-cleanup.sh`): verifies both release PRs are merged before deleting `release/vX.Y.Z`, removes remote/local release branches safely, and transitions explicitly scoped tracker items from `Merged` to `Released`.

### Changed

- **Rename docs/ai/ to docs/workflow/** (#251): renamed the `docs/ai/` directory to `docs/workflow/` to clarify framework ownership. Updated all cross-references across agent definitions, Cursor/Codex wrappers, scripts, protocol files, and root documentation. No content changes — pure structural refactor.

- **Sync-template skill and commands** (GitHub #239, #240, #243): include `.codex/skills/` in always-sync paths; require deterministic directory enumeration and `diff`/`cmp` comparison; treat "apply all" as always-sync only (never bulk-applies special-handling files); add placeholder guard for `deploy.yml` / `e2e-regression.yml`; scope `git add` paths in the Claude command variant instead of `git add .`.

- **Retrospective protocol** (GitHub #248): optional **Contribute upstream** action for workflow-only insights via labeled issues on the template repository.

- **Spec authoring guardrails** (GitHub #260, #261): `spec-template.md` and `01-generate-spec-protocol.md` reinforce product language, consistency, testable acceptance criteria, and a pre-PR self-check pass.

- **Automated reviewer loop protocol** (GitHub #241): shell workflow fixes require `bash -n` and a narrow behavioral verification before push.

- **GitHub Actions workflow security checklist** (`03-implement-development-protocol.md`): developer guidance now requires least-privilege `permissions`, full-SHA `uses:` pinning, scoped path filters, and `concurrency` controls whenever `.github/workflows/*.yml` files are created or materially updated.
- **Parser-risk implementation-plan requirements** (`02-generate-implementation-plan-protocol.md`, `implementation-plan-template.md`, `REVIEW.md`, `tech-lead` agents): plans that touch parser/regex/structured-text scanning now require deterministic classification plus mandatory edge-case enumeration, unit-test mapping, and conditional suppression semantics.
- **Prepare-release protocol and command wrappers** now include a required post-merge Step 9 that runs branch cleanup plus tracker transition guidance after both release PRs merge.

### Fixed

- **Protocol 91 Step 8c: require explicit GraphQL reviewThreads query** (#319): Step 8c now includes a standalone `gh api graphql` bash block (matching the Protocol 90 Step 5.1 pattern) that agents must execute to verify all bot-authored review threads are resolved before labeling a PR `ready-for-human-review`. Previously the query was embedded inline in a dense table cell, causing agents to rely on their own thread-tracking state rather than querying the API directly. The table row for this check is simplified to reference the new standalone block.

- **Re-trigger CodeRabbit for skipped (no_review) PRs after parallel batch completes** (#300): Protocol 90 Step 5.3 (new) instructs the orchestrator to scan all batch PRs for a `REASON=no_review` signal (emitted by `pr-review-loop.sh` when CodeRabbit exhausts its rate-limit budget without producing a review) in their reviewer loop summary comments after every Work Item Runner returns. For any affected PR, the orchestrator posts `@coderabbitai review`, re-runs `pr-review-loop.sh`, and re-applies readiness labels before declaring the batch complete. Step 3.7 is updated to cross-reference Step 5.3 so the per-PR rate-limit description and the post-batch recovery step are linked. This eliminates the manual second-reviewer-loop that humans previously had to run when CodeRabbit exhausted its per-hour budget across a parallel batch.
- **Skip development folders with terminal tracker status in `workflow-batch-plan.sh`** (#301): when `GITHUB_PROJECT_NUMBER` is set, `workflow-batch-plan.sh` now queries the GitHub Projects tracker for each candidate development folder and skips any whose status is `Released`, `Merged`, or `Cancelled` before invoking `workflow-next-action.sh`. This eliminates false-positive "Plan Ready" candidates for already-completed items and removes unnecessary tracker lookups from batch runs. Added `is_terminal_tracker_status()` and `get_tracker_status_for_issue()` helpers to `workflow-lib.sh`; issue numbers are resolved from `**Issue**: #NNN` frontmatter in spec/plan files, with a fallback to the leading numeric prefix of the folder slug.
- **Spec template Open Questions removal instruction** (#302): clarified the instruction comment in `spec-template.md` and the Step 2 rule in `01-generate-spec-protocol.md` to explicitly require deleting the entire `## Open Questions` heading and body (not replacing content with a placeholder comment) when all questions are resolved. <!-- markdown-heuristic-disable COUNT001 -->
- **Document Codex-reviewer runner-context constraint in `.ai-dev-workflow.yaml`** (#291): added an inline comment after the `- codex` entry and an explanatory comment block above `internal_reviewers` clarifying that `codex` is typically only reachable when Codex is the top-level runner itself — not from Claude Code subagents, Cursor subagents, headless environments, or any nested runner context. The `warn` policy (default) already handles this gracefully; the new comments make the constraint visible in the config file that operators edit directly, so the recurring "Skipped: codex" PR warnings are no longer surprising. A future GitHub-integration-based path will enable Codex review from any runner. For now, operators can suppress the warning by removing `codex` from the list or using a `.tmp/template-config.json` local override.
- **Worktree gotcha: `git rev-parse --show-toplevel` returns worktree path** (#293): Protocol 91 Step 3 now documents that `git rev-parse --show-toplevel` returns the *worktree* path (e.g., `.claude/worktrees/agent-xyz/`) rather than the main repo root when run inside an isolated worktree. The correct alternative — `$(git rev-parse --git-common-dir)/..` — is shown alongside the existing worktree git discipline block; `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` add a matching concise gotcha note.
- **Pre-push ShellCheck self-check for `.sh` file changes** (#292): `03-implement-development-protocol.md` now requires running `shellcheck --severity=warning` on any modified or newly created `.sh` files before committing, across all four implementation paths (Full Pipeline, Refactor, Fast Track, Hotfix). This agent-side gate mirrors the existing CI `shellcheck.yml` check and prevents ShellCheck violations from surfacing in the external reviewer loop (CodeRabbit/Devin), reducing unnecessary review-loop churn. `.claude/agents/developer.md` and `.cursor/agents/developer.md` key-rules sections were updated with a matching rule.
- **Tracker status routing for subagents** (#310): Protocol 91 Step 8b now documents two explicit routing paths for tracker status updates. For GitHub Projects (`provider: github_projects`), subagents must use `gh` CLI via Bash — no MCP server required — and update status directly from their execution context. For other providers (Linear, Jira, etc.) where no CLI equivalent exists, subagents cannot reach MCP and must instead emit a `TRACKER_UPDATE_REQUIRED:` line in their summary; Protocol 90 Step 5 (Supervise Until Terminal) now codifies that the Portfolio Orchestrator owns all such deferred transitions and must scan each returning subagent's summary to apply them. Protocol 90 Step 2.5 documents the same CLI-vs-MCP routing choice and the invariant that the orchestrator always has MCP access for pre-dispatch updates. `docs/workflow/development-workflow/integrations/github-projects.md` gains a new "CLI Update Patterns for Agents and Subagents" section with a ready-to-use one-shot status update script, a status-value lookup table for Step 8b targets, and a field/option-ID caching strategy.
- **Skip tracker status update when current status is unrecognized** (#304): `update_tracker_status_best_effort()` in `workflow-lib.sh` now skips the GraphQL mutation and emits a warning when `workflow_status_order()` returns `-1` for the item's current status — indicating a custom or unknown label not present in the hardcoded ordering map. Previously the rollback guard (`current_order > target_order`) never triggered for `-1`, so the mutation would silently overwrite an advanced status (e.g., "Development in Review") with an earlier one. The guard is bypassed only when the caller explicitly provides a `required_current_status` argument that matches the actual current status, which is treated as an intentional opt-in.
- **`prepare-release-post-merge-cleanup.sh` fails non-zero on zero tracker updates** (#305): when `--issues` is supplied the script now tracks `updated / skipped / failed` counters per issue, emits a structured `UPDATED=N SKIPPED=N FAILED=N` summary line, and exits non-zero if `UPDATED=0` or any hard failure occurred. Adds `--best-effort` flag to restore the previous always-exit-0 behaviour for callers that require it.
- **Thread-audit GraphQL failure now escalates instead of emitting RESULT=clean** (#303): `coderabbit_thread_gate_clean()` and the aggregate thread gate in `pr-review-loop.sh` previously treated `check_unresolved_threads` exit code 3 (GraphQL query failure) as "not blocking on threads", returning 0 and allowing `RESULT=clean` to propagate even when the thread audit was skipped. Both gates now retry up to `THREAD_AUDIT_MAX_RETRIES` times (default: 3) with a 5-second wait between attempts; after all retries are exhausted they emit `RESULT=escalate` with `REASON=review_thread_audit_failed`. Any other unexpected non-zero exit code also escalates. `RESULT=clean` is never emitted when the thread audit could not be completed.

- **Require all review threads resolved before ready-for-human-review** (#167): `pr-review-loop.sh` now enumerates all review threads on a PR via the GitHub GraphQL API (cursor-based pagination, up to 10 pages), filters to threads authored by configured bot logins (`coderabbitai[bot]`, `devin-ai-integration[bot]`, `greptile-apps[bot]`), and exits `needs_fixes` with `UNRESOLVED_THREAD_COUNT=N` when any thread is unresolved — regardless of severity (Critical, Major, Minor, Nitpick, Trivial). A thread is considered resolved when `isResolved=true` or the first comment body contains `✅ Addressed`. The check runs as the final gate in the aggregate exit block after all platforms return `clean` or `skipped`. Bot logins are derived at runtime from `review.platforms` in `.ai-dev-workflow.yaml`. Protocol 91 Step 8c is updated with a `reviewThreads` GraphQL verification row as a hard gate; the Step 7 Automated Reviewer Loop Summary template is extended with a "Reply-only resolutions" subsection listing threads resolved via reply + `resolveReviewThread` mutation with their rationale. Protocol 90 Step 5.1 post-dispatch PR verification checklist includes the same `reviewThreads` check.
- **Pre-label orphaned PR detection in Step 5.1** (#269): Protocol 90 "Stale / Incomplete PR Detection" now covers the case where an agent times out before any post-review labels are applied, leaving a non-draft PR with no `ready-for-regression`, no `ready-for-human-review`, and no reviewer loop summary comment. A classification table formalises all detection states and identifies this pattern as a pre-label orphaned run requiring redispatch from Step 7a. `workflow-next-action.sh` now emits `ORPHANED_PR=true` for non-draft, labelless PRs without a reviewer loop summary comment so orchestrators can detect and log the pattern without changing the existing `NEXT_ACTION=resolve-pr-readiness` output.
- **Pre-label ordering gate in developer protocol** (#270, #346): `03-implement-development-protocol.md` Step 9 now documents an explicit hard sequential two-phase gate that agents must pass before applying readiness labels — Phase 1 requires the reviewer loop summary comment to be present and all automated-reviewer threads to be resolved before applying `ready-for-regression`; Phase 2 requires all CI checks to reach a terminal state with no failures before applying `ready-for-human-review`. The gate was originally written as prose, which allowed agents to skip it accidentally (#346); Phase 1 and Phase 2 are now each expressed as a numbered checklist of executable steps: Step 1.1 runs `gh pr view --json comments` to confirm the summary comment exists, Step 1.2 runs the GraphQL thread-resolution audit and requires empty output, Step 1.3 applies `ready-for-regression`, Step 2.1 runs `pr-ci-loop.sh` and requires `RESULT=green`, and Step 2.2 applies `ready-for-human-review`. Skipping any step is explicitly labelled a protocol violation.
- **Orchestrator parallel impl batch merges must use batch-merge.sh** (#273): Protocol 90 Step 5.5 now includes an explicit batch-merge routing rule clarifying that parallel implementation batches must always be merged via `batch-merge.sh discover --prs <list>` + Protocol 94 (which provides CHANGELOG auto-resolution and active-worktree awareness); direct `gh pr merge` calls are only acceptable for single-PR or non-implementation (spec/plan) merges. A summary table and reference to the Batch 4 incident are included.
- **Devin `COMMENTED` review with inline findings treated as blocking** (#274): `pr-review-loop.sh` now treats a `COMMENTED` review from `devin-ai-integration[bot]` as blocking when it is accompanied by unresolved inline PR review comments, not only when the review body starts with `**Devin Review**`. Previously, a Devin review that submitted findings exclusively as inline comments (without a matching summary body) was silently treated as non-blocking, allowing PRs with real bugs to be incorrectly labeled `ready-for-human-review`. Protocol docs (`91-orchestrate-work-protocol.md`, `93-automated-reviewer-loop-protocol.md`) updated to document the full blocking classification rules.
- **CodeRabbit retry loop skips SUCCESS status before retry wait** (`pr-review-loop.sh`): script now checks for an existing CodeRabbit SUCCESS commit status on the current HEAD before entering the rate-limit retry sleep; if SUCCESS is already present (and thread gate passes), the loop exits immediately via `coderabbit_status_success_fallback` rather than waiting indefinitely.
- **Single-instance guard** (`pr-review-loop.sh`): added atomic mkdir lock directory (`/tmp/pr-review-loop-<pr>.lockdir`) at script startup so a second invocation for the same PR exits immediately with `RESULT=escalate` / `REASON=lock_contention` (exit code 75) rather than running in parallel.
- **Plan verification step simplicity** (#280): added guidance to `02-generate-implementation-plan-protocol.md` requiring verification commands in Implementation Order steps to be simple and human-readable (prefer prose assertions over exact counts, avoid complex multi-flag grep one-liners); added a corresponding `important`-severity reviewer note to `REVIEW.md` Plan Review Checklist instructing plan reviewers to flag complex shell verification commands and suggest simpler "run and confirm output" assertions.
- **Mass-rename reference-type coverage** (#281): `03-implement-development-protocol.md` Refactor path now includes a mandatory mass-rename sub-step requiring post-substitution verification of three reference categories — link targets (both href and display text when text mirrors the old path), display text in already-updated links, and non-link occurrences (prose, code blocks, directory trees, YAML values) — plus a residual-occurrence grep command to confirm no old-string instances remain before staging.
- **Document complete hotfix protocol** (#295): closes five documentation gaps in the hotfix workflow. (1) `03-implement-development-protocol.md` Path 4 Step 6 now specifies that hotfix CHANGELOG entries go in a new versioned section (e.g., `[1.0.1] - YYYY-MM-DD`) above `[Unreleased]`, not under `[Unreleased]`, since hotfixes patch released code and are released immediately on merge. (2) Step 9 now includes concrete backport steps: create a dedicated `backport/hotfix/[slug]` branch from `origin/main` post-merge, open a draft PR targeting `develop`, and run the standard review + CI loop. (3) Branch lifecycle is now explicit: `hotfix/[slug]` merges to `main` and is not reused; the backport uses a separate branch. (4) `auto-tag-release.yml` now triggers on `hotfix/*` merges to `main` and extracts the version from the topmost versioned CHANGELOG section (since hotfix branch names do not encode the version). (5) `workflow-next-action.sh` `--branch` mode already handles `fix|hotfix|refactor` prefixes correctly (no code change needed). `docs/workflow/development-workflow/README.md` hotfix section, `docs/best-practices/2-version-control.md` CHANGELOG rules, `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `AGENTS.md`, and `.cursor/rules/workflow.mdc` updated consistently.

- **Post-agent main working tree sanity check** (#229): Protocol 90 Step 5.2 now runs immediately after each Work Item Runner returns — before PR verification, before the next dispatch, and before any action that assumes the integration branch context; the Case 1 postcondition table now documents the root-cause implication of a wrong-branch + clean result (agent ran in main tree instead of worktree). Protocol 91 post-terminal check upgraded from a single error branch to the same four-case handling (auto-correct Case 1, halt-and-escalate Cases 2 and 4, proceed Case 3) with explicit cross-reference to Protocol 90 Step 5.2.

- **MD047 trailing-newline pre-staging check** (#227): `03-implement-development-protocol.md` (all four paths) now includes an explicit MD047 check that scans every modified `.md` file for a missing trailing newline before `git add`; `.claude/agents/developer.md` and `.cursor/agents/developer.md` key-rules sections were updated with the matching rule (parity with the #178 trailing-whitespace step).

- **Tech-lead CHANGELOG literal format** (#226): plan protocol, plan template, and `REVIEW.md` plan-review checklist now require and enforce the project's `**Bold Title** (#N):` CHANGELOG entry format; conventional-commit-style literals (`fix(scope): message`) in Implementation Order steps are now a blocking plan-review finding.

- **CodeRabbit review pass vs unresolved threads** (GitHub #242, `pr-review-loop.sh`): Phase 3 clean and SUCCESS commit-status fallback now honor the GraphQL review-thread audit so old unresolved CodeRabbit threads cannot coexist with a "clean" platform result. Follow-up: emit `UNRESOLVED_THREAD_COUNT` from the per-platform gate and restore shell `errexit` after `check_unresolved_threads` so aggregate output stays contract-correct.

- **`workflow-next-action.sh`**: `--development` path always exits zero after emitting key=value lines (empty `LINEAR_ISSUE` no longer yields exit status 1), restoring `workflow-batch-plan.sh` parsing.

- **`post-merge-cleanup.sh` worktrees** (GitHub #250): run `git worktree unlock` before remove to clear common agent lock files without manual intervention.

- **Duplicate check-name handling in CI polling** (`pr-ci-loop.sh`): GitHub `statusCheckRollup` can contain historical entries for the same check name (for example an older `CANCELLED` run plus a newer `SKIPPED` run). The CI loop now evaluates only the latest entry per check name so stale results do not incorrectly force `RESULT=red`.

- **Internal reviewers now fix `suggestion`-level findings by default** (`REVIEW.md`): `suggestion` severity was previously "report or fix at discretion", meaning internal reviewers (Step 7a) could skip them. This left low-risk improvements for external reviewers to re-raise, lengthening the review loop. The default action is now "fix by default; report only if scope-expanding or requires a product decision."

- **`UNRESOLVED_THREAD_COUNT` now emits `-1` (not `"unknown"`) on page-cap escalation** (`pr-review-loop.sh`): the output contract specifies an integer field; using the string `"unknown"` violated the contract and required a defensive string-guard on the downstream consumer. Replaced with `-1` as an integer sentinel and removed the now-redundant guard.

- **`PR_IS_DRAFT` and `PR_HAS_NEEDS_FIXES` documented in discovery output contract** (`batch-merge.sh`): these fields were emitted by `fetch_pr_meta` but absent from the script header comment, leaving the documented contract out of sync with actual output.

- **Draft-state revalidation in `cmd_merge` to close TOCTOU gap** (`batch-merge.sh`): a PR could be switched to draft between discovery and merge execution. Added `isDraft` revalidation immediately before merge so the guard reflects current state.

- **CodeRabbit completion via issue comments** (`pr-review-loop.sh`): when CodeRabbit posts only an issue-thread summary (no `pulls/{id}/reviews` entry) for the current HEAD, the poll loop now proceeds to Phase 3 instead of spinning until `timeout` and returning a false `escalate`.

- **Plan-writer pre-commit lint step** (#271): `02-generate-implementation-plan-protocol.md` Step 5 now includes a mandatory `markdownlint-cli2` run on the plan file and smoke test runbook before staging. This catches broken relative links (wrong `../../` depth), trailing spaces, and missing trailing newlines before the first push, preventing Devin fix cycles caused by off-by-one path errors. The lint command resolves `node_modules/` from the git repo root so it works inside isolated worktrees.

- **Silent workaround loophole in item-orchestrator permission-denial contract** (#228): when `Edit`/`Write` is denied on `.claude/agents/**` or any other path, subagents were silently falling back to Bash redirects, Python subprocess writes, or `gh api --method PUT` instead of returning `SUBAGENT_PERMISSION_DENIAL`. Protocol 91 Step 3 now explicitly prohibits all alternative write mechanisms and requires the denied path(s) to be listed in the exit string; `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` add a matching enforcement note; `.claude/settings.json` adds `Edit(.claude/agents/**)`, `Write(.claude/agents/**)`, `Edit(.cursor/agents/**)`, and `Write(.cursor/agents/**)` allow-list entries to close the root-cause permission gap that triggered the workarounds.

- **Duplicate CHANGELOG section headers in developer protocol** (#272): `03-implement-development-protocol.md` (all four paths) now includes an explicit duplicate-section prevention step that requires reading the existing `[Unreleased]` block before writing an entry, appending to an existing category section rather than creating a new header, and verifying with an awk-scoped `grep -c` that each category header appears exactly once **within the `[Unreleased]` block**; `.claude/agents/developer.md` and `.cursor/agents/developer.md` key-rules sections were updated with the matching rule.
- **Duplicate CHANGELOG section-header lint check** (#318): `scripts/lint/check-changelog-duplicate-headers.sh` (new) detects duplicate `### ` headers (e.g., repeated `### Fixed`) within the same `## ` section of CHANGELOG.md. The script is added as a CI step in `.github/workflows/markdown-lint.yml` (runs unconditionally on every triggered push) and documented in the `AGENTS.md` "Common Commands" section. Protocol guidance alone (added in #272) had not prevented recurrence; this automated check enforces the constraint at CI time.

- **Policy grep coverage before multi-file changes** (#316): `03-implement-development-protocol.md` Step 1b item 6 (all four paths) and the Quality Rules section now require grepping for all existing references to a policy **before writing any code** — the grep is the discovery step, not a confirmation step. Instructions no longer say "if documented in more than one location" (which assumed prior knowledge of sibling files); they now direct agents to run the grep unconditionally to discover all locations, list every matched file as a candidate, and explicitly confirm coverage of each before submitting. `.claude/agents/developer.md` and `.cursor/agents/developer.md` were updated with a matching key rule.

- **Script-emitted signal verification in developer protocol** (#317): `03-implement-development-protocol.md` Step 1b (all four paths) now includes a mandatory item 7 requiring developers to read the relevant source script and verify the exact string before committing whenever protocol text cites a script-emitted signal value (`REASON=`, `RESULT=`, `STATUS=`, etc.). The Quality Rules section adds a matching bullet with an example `grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh` command. `.claude/agents/developer.md` and `.cursor/agents/developer.md` were updated with a matching key rule.

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

- **CodeRabbit integration**: CodeRabbit is now available as an automated PR reviewer platform (`coderabbit` in `review.platforms`) and as a pre-push CLI tool. Includes adapter in `pr-review-loop.sh` with severity-based blocking (Critical/Major block, Minor/Low don't), `CHANGES_REQUESTED` review handling, stale-findings recovery with resolved-comment filtering, `.coderabbit.yaml` config, and setup guide at `docs/workflow/development-workflow/integrations/coderabbit.md`.
- **`/run-work` command for Claude Code**: batch orchestrator command (`.claude/commands/run-work.md`), matching the existing Cursor `/run-work`.

### Changed

- **Multi-reviewer internal review gate (Step 7a)**: Step 7a now runs all configured internal reviewers (`review.internal_reviewers` in `.ai-dev-workflow.yaml`) sequentially on draft PRs before converting to non-draft. Added `max_internal_review_cycles` (default: 5) to prevent infinite loops and local override support via `.tmp/template-config.json`. Codex reviewer dispatch uses stage-specific skills. Step 9 feedback loop corrected to include Step 7a before Step 7.
- **Post-merge status transitions (Step 10)**: new Step 10 in `91-orchestrate-work-protocol.md` maps branch type to tracker status (`spec/*` → Spec Ready, `implementation-plan/*` → Plan Ready, implementation branches → Merged). All post-merge-cleanup commands updated accordingly.

### Fixed

- **Missing `/sync-template` command for Claude Code**: added `.claude/commands/sync-template.md` covering template source resolution, categorized diff, approval gate, file application, and git/PR instructions.

## [0.20.0] - 2026-04-10

### Added

- **Label-gated e2e/regression test workflow**: new `.github/workflows/e2e-regression.yml` runs only when the `ready-for-regression` label is applied, with a Playwright-based `e2e/` placeholder project for downstream projects to customize. The orchestrator applies the label automatically on implementation PRs after automated review is clean (new Step 7b, documented in protocols 91 and 92), and the release protocol applies it on production PRs targeting `main`. See `docs/workflow/development-workflow/integrations/e2e-regression.md` for the label-gate pattern.
- **Backlog intake stage**: new protocol `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` and `/add-backlog-item` command (Cursor + Claude Code) create work items in the configured issue tracker, backed by `scripts/development-workflow/add-backlog-item.sh` (`resolve` / `create` for GitHub) and destination helpers in `workflow-lib.sh`.
- **Template deployment scaffold**: new `.github/workflows/deploy.yml` triggers on `develop` and `main`, maps to `develop`/`production` environments, and keeps deploy steps as explicit no-op placeholders. Accompanied by `docs/workflow/development-workflow/integrations/ci-cd-deployment.md` and new CI/CD onboarding prompts in `docs/workflow/setup/protocol.md` plus branch-to-environment guidance in `docs/project/3-software-architecture.md`.
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
- Workflow docs were refreshed, including a full rewrite of `docs/workflow/development-workflow/README.md` and terminology updates to "Portfolio Orchestrator" and "Work Item Runner".

### Removed

- `docs/workflow/development-workflow/tooling-assumptions.md`; capability assumptions and fallback guidance now live in the workflow README.

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

- Devin automated PR review adapter: `pr-review-loop.sh` now supports `--platform devin`, polling Devin check runs for completion and collecting inline findings. Added `docs/workflow/development-workflow/integrations/devin.md` with setup, bot identity, and adapter contract details.
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
- Post-merge cleanup: the agent now updates the related issue in the issue tracker after running the cleanup script. When the merged branch name contains an issue identifier (e.g. `ENG-123`), the skill/command instructs the agent to set that issue to the merged/done state (e.g. Linear → **Merged**). See `docs/workflow/development-workflow/integrations/linear.md` and the post-merge-cleanup skill/command docs.

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

- `AGENTS.md`, `README.md`, and `docs/workflow/development-workflow/README.md` to document Codex skill usage and installation alongside the existing Claude Code and Cursor wrappers.
- `.codex/skills/*/SKILL.md`, `AGENTS.md`, and `README.md` to document recommended model tiers for each Codex skill, with `workflow-orchestrator` positioned as the default `economy` entrypoint.
- `README.md` to include copy-paste starter examples for Claude Code, Cursor, and Codex users testing the orchestration flow in downstream repositories.
- `docs/workflow/development-workflow/README.md` to use "default integration branch" wording where the template previously hard-coded `develop`, so repository-level branch overrides in `AGENTS.md` remain consistent.
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` to document the Codex helper scripts and Codex-specific execution behavior while preserving the shared orchestration protocol.

## [0.10.0] - 2026-02-26

### Added

- `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` — authoritative release protocol: pre-flight checks, versioning guidance, CHANGELOG update, two-PR approach (main + mandatory develop backport), and CI auto-tagging note.
- `.claude/commands/prepare-release.md` — Claude Code `/prepare-release` command (thin wrapper delegating to the new protocol).
- `.github/workflows/auto-tag-release.yml` — GitHub Actions workflow that automatically creates a git tag and GitHub release when a `release/*` PR is merged into `main`. Extracts the version from the branch name and release notes from `CHANGELOG.md`.

### Changed

- `.cursor/commands/prepare-release.md` — refactored to thin wrapper delegating to `05-prepare-release-protocol.md`; previously had inline steps.
- `docs/workflow/development-workflow/README.md` — Release Process section replaced with a summary and link to the new protocol.
- `AGENTS.md` — Prepare Release row now lists `/prepare-release` for Claude Code (was `—`) and references the protocol in the "Any other tool" column.
- `.claude/skills/sync-template.md` — added `.claude/commands/` to always-sync paths; added `.github/workflows/auto-tag-release.yml` to special-handling paths.

## [0.9.0] - 2026-02-26

### Added

- `docs/workflow/development-workflow`: Added automated reviewer loop to `protocols/91-orchestrate-work-protocol.md` (Step 8). The orchestrator polls for feedback after every push, dispatches the appropriate fixing agent when blocking issues are found, and escalates to human after timeout or 3 fix cycles. Updated Steps 1, 2, 6, and 7 for consistency.
- `docs/workflow/development-workflow/integrations/pr-review-platform.md`: New platform-agnostic integration doc defining what any automated code review tool must provide and what each platform-specific integration doc must specify. Mirrors the `issue-tracker.md` / `linear.md` pattern.
- `docs/workflow/development-workflow/integrations/greptile.md`: Added Greptile-specific Step 8 implementation (bot identity, re-trigger command, review completion detection, inline comment fetch). Generic loop mechanics remain in the protocol; only tool-specific commands live here.

## [0.8.0] - 2026-02-26

### Added

- `docs/workflow/development-workflow`: Added `Spec In Review` and `Plan In Review` stages to the workflow. These stages make PR-open states explicit so the orchestrator agent knows not to re-dispatch when a spec or plan PR is already awaiting human review. Updated `README.md` (stage diagram, issue tracker status list, Agent Roles Summary table) and `protocols/91-orchestrate-work-protocol.md` (mental map, eligibility table, pre-dispatch branch check).

## [0.7.1] - 2026-02-26

### Changed

- Sync-template workflow now stores template source config in `.tmp/template-config.json` (framework-agnostic, gitignored) instead of `.claude/template-config.json`. Single source for Claude Code remains `.claude/skills/sync-template.md`; Cursor uses `.cursor/commands/sync-template.md`.

## [0.7.0] - 2026-02-26

### Added

- `.claude/commands/code-review.md` — new pipeline for automated PR reviews using parallel Claude agents and confidence scoring.

### Changed

- `docs/workflow/development-workflow/protocols/03-review-implementation-protocol.md` — updated implementation review protocol to include Step 2 (Run code-review command) and improved section navigation with an explicit Flow Overview.

## [0.6.1] - 2026-02-26

### Added

- `.claude/agents/smoke-tester.md` — missing Claude Code sub-agent for the smoke test stage; delegates execution to `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` and `docs/testing/README.md`.

## [0.6.0] - 2026-02-25

### Added

- `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` — new agnostic smoke test execution protocol with a two-path decision (run committed spec if it exists, fall back to ad-hoc script), standard output format, pass criteria, and fail handling rules. References the project testing README for all project-specific details.
- `docs/testing/README.md` — template for the project-specific smoke test execution guide: decision tree, committed suite path, ad-hoc fallback scaffold (Node.js + Playwright example), selector/waiting conventions, and troubleshooting sections for projects to fill in during setup.
- Testing Strategy section in `docs/project/3-software-architecture.md` — placeholder documenting the two-tier model (committed automated suite as primary path, ad-hoc scripts as stepping stone), the runbook-to-spec relationship, and setup instructions.

### Changed

- `docs/best-practices/3-testing.md` — testing strategy ownership moved to `docs/project/3-software-architecture.md`; this file now points there and focuses on principles and conventions only. Added two-tier execution model note and link to `docs/testing/README.md` in the Smoke Tests section.
- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — Step 5 now includes an explicit e2e spec maintenance instruction (keep committed specs in sync; create one when adding a feature with a runbook). Step 6 pre-commit verification separates unit/integration tests from the e2e suite command. Fast Track path updated accordingly.
- Refactored issue tracker integration protocols to remove redundant field definitions and fallback logic.
- Centralized "current brief" definitions and agent expectations in `docs/workflow/development-workflow/integrations/issue-tracker.md`.
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

- Moved `docs/workflow/agent-model-config.md` to `docs/workflow/development-workflow/agent-model-config.md` for better repository organization.
- Updated documentation links in `AGENTS.md` and `CHANGELOG.md` to reflect the new path for `agent-model-config.md`.

### Changed

- `docs/workflow/development-workflow/README.md` — Updated the development lifecycle diagram to specify the `develop` branch as the merge target.

## [0.3.0] - 2026-02-24

### Added

- `docs/workflow/development-workflow/agent-model-config.md` — documents model assignments, tool restrictions, and override instructions for all Claude Code agents
- Link to `agent-model-config.md` in the Key Documentation table in `AGENTS.md`

### Changed

- All Claude Code agents (`.claude/agents/`) now declare an explicit `model` field in their YAML frontmatter:
  - `tech-lead` → `claude-opus-4-6` (highest-reasoning stage; architecture decisions benefit from Opus depth)
  - `developer`, `product-manager`, `spec-reviewer`, `implementation-plan-reviewer`, `code-reviewer`, `project-setup` → `claude-sonnet-4-6` (capable and cost-effective for their respective tasks)
  - `orchestrator` → `claude-haiku-4-5-20251001` (mechanical dispatch work; speed and cost matter at orchestration frequency)
- `product-manager`, `spec-reviewer`, and `implementation-plan-reviewer` agents: `Bash` removed from `tools` (least-privilege — these agents only read and write documentation files)
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` Step 5: expanded with explicit parallel subagent dispatch instructions — the orchestrator now uses the Claude Code `Task` tool to launch all eligible agents simultaneously in a single message rather than sequentially
- AI development workflow: clarified the Spec Ready stage is product-focused and technical design details belong in the Plan Ready stage.

### Removed

- Framework sync scripts (manual propagation/backporting only).

## [0.2.0] - 2026-02-24

### Added

- Issue tracker branch naming convention: when an issue tracker is in use, branch slugs are prefixed with the issue identifier (e.g., `feature/ENG-123-user-auth`); without a tracker the existing slug convention applies. Documented in `docs/best-practices/2-version-control.md`, `docs/workflow/development-workflow/README.md`, all three development protocols, and `docs/workflow/development-workflow/integrations/linear.md`

### Changed

- `AGENTS.md` — Git & Branching and CHANGELOG sections updated with project-specific overrides: no `develop` branch (all PRs target `main`), and every merged PR releases a new version
- `docs/best-practices/STACK-SPECIFIC.md` — fixed broken Markdown in placeholder table: replaced nested-bracket links with backtick paths and an inline example for the setup agent

## [0.1.0] - 2026-02-24

### Added

- Staged AI-assisted development workflow (Spec → Plan → Implement → Review → Release) with 8 protocol documents in `docs/workflow/development-workflow/protocols/`
- Claude Code agents for all workflow stages (`.claude/agents/`): `product-manager`, `spec-reviewer`, `tech-lead`, `implementation-plan-reviewer`, `developer`, `code-reviewer`, `orchestrator`, `project-setup`
- Cursor commands and rules (`.cursor/`) mirroring the full Claude Code workflow
- Project setup onboarding agent (`docs/workflow/setup/protocol.md`) — 12-step structured conversation to generate all project-specific documentation
- Project documentation placeholders (`docs/project/`): business domain, repo architecture, software architecture, database model
- General best practices: coding standards (`1-general.md`), version control (`2-version-control.md`), testing (`3-testing.md`)
- `docs/best-practices/STACK-SPECIFIC.md` as a coordinator document — provides stack summary, quick reference, and links to `docs/best-practices/stack/[technology].md` detail files generated by the setup agent per technology area
- Optional integrations for Linear and Greptile (`docs/workflow/development-workflow/integrations/`)
- Spec, implementation plan, and smoke test runbook templates (`docs/workflow/development-workflow/templates/`)
- `AGENTS.md` as the universal AI entry point (AGENTS.md open format), with `CLAUDE.md` and `GEMINI.md` symlinks for Claude Code and Gemini CLI compatibility
- `.claude/settings.json` with pre-approved permissions for common git and fetch operations; `.claude/settings.local.json.example` documenting machine-specific overrides for optional integrations
- `.gitignore` covering local Claude settings, `.env` files, and common system files

[Unreleased]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.24.1...HEAD
[0.24.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.2...v0.24.0
[0.23.2]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.22.0...v0.23.0
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
