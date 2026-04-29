# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [Unreleased]

### Added

- **Add `codex-github` integration reviewer path for Step 7a** (#309): adds a runner-agnostic internal reviewer that posts a trigger comment to a PR and polls for the Codex GitHub App bot response; works from Claude Code, Cursor, headless CI, and Codex runner contexts. New `scripts/development-workflow/codex-github-reviewer.sh` implements the trigger/poll/parse/timeout loop. `codex-github` is classified as universally reachable in Protocol 91's reachability table (requires only `gh` CLI). `.ai-dev-workflow.yaml`, `.claude/agents/item-orchestrator.md`, and `.cursor/agents/item-orchestrator.md` updated to document the new reviewer path.
- **Parallel batch file-level conflict detection** (#324): the batch orchestrator now extracts declared file sets from implementation plan documents and automatically serializes items with overlapping file sets before dispatch; items without an explicit file list are flagged as unknown-set in the batch summary.
- **Add async/concurrency safety checklist to plan protocol and review contract** (#348): adds a conditional async/concurrency safety checklist to `02-generate-implementation-plan-protocol.md` (triggered when a plan has concurrent event sources) and a matching conditional additional-checks block to `REVIEW.md` (triggered when a PR introduces or modifies concurrent event source code). Covers shared mutable state guards, re-entrancy / in-flight tracking, event deduplication, listener cleanup, initialization/teardown race conditions, and error propagation across async boundaries.
- **Template-fit check added to plan protocol** (#413): `02-generate-implementation-plan-protocol.md` now begins with a new Step 0 that requires the tech lead to verify whether a spec is sufficiently generic for a framework template repository before writing any plan content. When `template.is_template` is set to `true` in `.ai-dev-workflow.yaml`, the check is mandatory: if the spec references a framework-specific language or runtime not used by the template's own toolchain, the agent surfaces a structured warning and halts until the human confirms how to proceed (confirm generic, narrow scope, or cancel). Also adds the `template.is_template` field (set to `true`) to `.ai-dev-workflow.yaml` for this repository and updates `docs/workflow/development-workflow/README.md` with the new field documentation. This prevents wasted plan-writing cycles on framework-specific content, as occurred with issue #384 (React hooks safety checklist) in Batch 22.

- **Sync-template migration notes** (`sync-manifest.yaml`, sync-template skill and commands): `sync-manifest.yaml` gains a `migration_notes` section for versioned manual migration steps. The sync-template skill and command variants now read this section and present a required pre-sync checklist whenever the downstream project's `last_synced_version` predates a breaking structural change. First entry: `docs/ai/ → docs/workflow/` rename (v0.23.0). Fully backwards-compatible — silently skipped when no applicable notes exist.

### Changed

- **Bash 3.2 compatibility rule added to developer agent and Protocol 03** (`.claude/agents/developer.md`, `.cursor/agents/developer.md`, `03-implement-development-protocol.md`): workflow scripts must be bash 3.2 compatible (macOS ships bash 3.2 by default); `local -A` / `declare -A` and other bash 4+-only syntax are prohibited. ShellCheck does not warn on this by default with a `#!/usr/bin/env bash` shebang. Added to developer agent key rules and to all four ShellCheck blocks in Protocol 03 (one per implementation path).

### Fixed

- **Step 7a re-run skipped for trivial fixer pushes** (`91-orchestrate-work-protocol.md`, #402): the Step 7a internal review gate was re-run in full after every fixer push triggered by Step 7 (external reviewers), regardless of how small the change was. For purely textual/cosmetic fixes (e.g., correcting a number, removing a stale reference, rewording a description), this added significant overhead with no safety benefit. Added a "Trivial-fix skip rule" to Protocol 91 Step 7a: a fixer push qualifies as trivial when the fixer self-certifies `TRIVIAL_FIX: non-structural` in its commit message or response, the diff contains only changes to string literals, comments, documentation prose, or inline numeric values (no logic, control-flow, declarations, imports, or structural markup changes), and the total changed line count is 10 or fewer. When all criteria above are met, the orchestrator skips the Step 7a re-run, posts a one-line PR comment noting the skip, and proceeds directly to Step 7. The orchestrator independently verifies the diff-based criteria via `git diff` before accepting the self-certification.

- **Stale Devin `error` commit status blocks CI loop after all findings resolved** (`pr-ci-loop.sh`, #404): after all Devin review threads were resolved and the review loop reported `RESULT=clean`, the Devin commit-status context on GitHub remained `error` until a fresh Devin run refreshed it. `pr-ci-loop.sh` treated this stale `error` as a real CI failure, requiring an extra manual review-loop trigger. Fixed by adding an `is_devin_status_stale` helper that is invoked whenever the only failing checks are Devin commit-status contexts with `state=ERROR`: it checks for blocking Devin inline comments and reviews on the current PR HEAD (mirroring Phase 1 of `pr-review-loop.sh`); if none are found, the stale error is bypassed and the loop continues as if those checks were green. Non-Devin failures and Devin failures that still have unresolved findings are unaffected.

- **Stale development folders without issue-number slugs cause false Plan Ready noise** (`workflow-batch-plan.sh`, #399): development folders with a spec and plan but no numeric issue-number prefix in their slug (and no `**Issue**: #NNN` reference in the documents) caused `workflow-batch-plan.sh` to report `STATUS=Plan Ready, NEXT_ACTION=implement`. `extract_github_issue_number` returned empty, the tracker cross-check was skipped, and `workflow-next-action.sh` classified the folder based on content alone. Fixed by detecting the empty-issue-number case early and emitting `STATUS=Done / NEXT_ACTION=skip` with `SKIP_REASON=no issue number found`, preventing spurious batch dispatches for folders that cannot be linked to a tracker item.

- **Step 5.2 false results when shell CWD leaks into worktree after agent completes** (`90-batch-orchestrate-work-protocol.md`, #383): When a Work Item Runner's isolated worktree is the shell's CWD after the runner returns, `git rev-parse --show-toplevel` returns the worktree path instead of the main repo root. Any `git -C` command built from that path then runs against the wrong tree, causing Step 5.2 to report an incorrect branch (false Case 1), phantom dirty files, or a spurious `git switch` failure. Fixed by adding a "CWD safety" note to Step 5.2 mandating that `MAIN_REPO_ROOT` must be derived with `$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` — which produces an absolute path that always resolves to the main repo regardless of CWD — rather than `--show-toplevel`. The `cd ... && pwd` wrapper is required because `--git-common-dir` returns a relative `.git` path when run from the repo root; without it the stored path resolves relative to wherever CWD drifts. Updated the Step 5.2 code block to use `"$MAIN_REPO_ROOT"` consistently throughout and to recommend storing the absolute value before dispatching any Work Item Runner.

- **`GITHUB_PROJECT_NUMBER` missing fallback causes silent tracker skips** (`workflow-lib.sh`, `.ai-dev-workflow.yaml`): `update_tracker_status_best_effort` and `get_tracker_status_for_issue` set `project_number` from `GITHUB_PROJECT_NUMBER` with no fallback, so tracker updates silently skipped on every run in normal shell sessions where the env var is not set. Fixed by reading `project_number` from the `issue_tracker.project_number` field in `.ai-dev-workflow.yaml` when the env var is absent (via a new `workflow_config_field` awk-based YAML section/field parser and `workflow_issue_tracker_project_number` named wrapper in `workflow-lib.sh`). Also removed the now-redundant `GITHUB_PROJECT_NUMBER` guard in `workflow-batch-plan.sh` that prevented the terminal-status skip from activating when project number was configured only via YAML. Added a `project_number: 1` field to `.ai-dev-workflow.yaml` with documentation comment.

- **Plan reviewer misses implementation-level technical accuracy issues** (`REVIEW.md`, #403): the Plan Review Checklist did not require verifying behavioral claims (guard logic, config inheritance, scope, API contracts) against actual source files before approval. Internal plan reviewers were approving plans with unverified or incorrect technical claims (e.g., guard redirect behavior, baseURL inheritance, storageState scoping), leaving Devin to catch these in external review cycles. Fixed by adding an explicit technical accuracy checklist block to the Plan Review Checklist in `REVIEW.md`: reviewers must now identify each framework/runtime behavioral claim, verify it against the codebase (not just other parts of the plan), flag unverified claims, and check cross-reference consistency (line numbers, counts, symbolic references). Added a matching `blocking` issue entry for unverified behavioral claims and an `important` issue entry for unconfirmed numeric cross-references.

- **Project board status update skipped after issue close in `post-merge-cleanup.sh`** (#361): `gh project item-list` only returns items whose linked issue is still open, so the "Merged" tracker status update was silently skipped whenever the issue was closed first. Fixed by moving `update_tracker_status_best_effort` to run before `gh issue close`, ensuring the project item is still visible during the lookup.
- **Batch-merge remote branch deleted before MERGED confirmation** (`batch-merge.sh`, protocol 94): Deleting the feature branch before `git push origin develop` is reflected by GitHub causes the PR to transition to `CLOSED` instead of `MERGED`, permanently losing merge attribution even though the commits land in `develop`. Added a new `delete-branch` subcommand to `batch-merge.sh` that re-checks `gh pr view <N> --json state` immediately before deletion and emits a warning (skipping deletion) if the state is not `MERGED`. Updated protocol 94 Step 4.2 to use this guarded command and to document the failure mode.
- **Protocol 94 Step 4.2 redundant awk worktree-detection block removed** (#376): Step 4.2 contained an `awk` command to detect and force-remove a worktree for the merged branch before calling `post-merge-cleanup.sh`. The `awk` pattern only matches multi-line porcelain output and always returns empty on macOS git (which emits single-line output even with `--porcelain`). The block was also redundant because `post-merge-cleanup.sh` already implements the same logic with robust locked-worktree handling (unlock, retry, double-force fallback). Removed the broken block and replaced it with a clarifying note that agents must not attempt manual worktree removal before calling `post-merge-cleanup.sh`.
- **Tech-lead omits agent/skill files when plan adds cross-cutting checklist category** (#389): when a plan introduces or modifies a cross-cutting checklist (safety, quality, or compliance items applying across multiple feature implementations), the tech-lead lacked a rule requiring enumeration of all affected guidance files. Added a "Cross-cutting checklist plans" block to `02-generate-implementation-plan-protocol.md` mandating that the plan's "Files to modify" section list all applicable targets (developer protocol, all agent/skill files for tech-lead and developer, `REVIEW.md`, and any Codex skill files). Added matching guidance to `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and `.codex/skills/workflow-plan-writer/SKILL.md`.
- **Pre-dispatch stale-worktree and integration-branch divergence check** (`90-batch-orchestrate-work-protocol.md`, #423): Added Step 3.3 "Pre-Dispatch Environment Validation" to the Portfolio Orchestrator protocol. The new step runs two portfolio-wide checks before any Work Item Runner is dispatched: (1) detect orphaned/locked worktrees from prior runs whose branches are merged, closed, or no longer active — report them with suggested `git worktree remove --force` cleanup commands and block dispatch until resolved; (2) detect all four integration-branch divergence states — in sync (proceed), local ahead only (push needed), local behind only (fast-forward pull available, suggest `git pull origin <branch>`), or true divergence (both ahead and behind — show top commits on each side, present rebase/merge/reset options to human, block until resolved). Check 2 runs `git fetch origin` before measuring both AHEAD and BEHIND counts so it reflects current remote state. Both checks run in parallel and are reported together to minimize human interruptions. Prevents the silent `git reset --hard origin/develop` workaround observed during Batch 23 pre-dispatch.
- **Step 8a blocking gate: verify ready-for-regression before ready-for-human-review** (`91-orchestrate-work-protocol.md`, #424): In Batch 22 and Batch 23, agents under token pressure skipped Step 7b (apply `ready-for-regression`) and jumped directly to applying `ready-for-human-review`, bypassing e2e/regression CI. Added a hard blocking gate immediately before Check 4 (apply `ready-for-human-review`) that requires an explicit `gh pr view --json labels` verification confirming `ready-for-regression` is present on implementation PRs. The gate emits a `⛔ STOP` message, runs the verification, and exits with code 3 if the label is missing (maintaining the distinct-exit-code contract: Check 1 = exit 1, Check 2 = exit 2, pre-Check-4 gate = exit 3) — agents cannot proceed to Check 4 until Step 7b is completed and CI is re-run. Also added a "Step 7b completion confirmation" block requiring agents to verify the label was applied before leaving Step 7b. Complements the orchestrator-side enforcement added in #422.
- **Commit SHA verification before marking reviewer findings resolved** (`91-orchestrate-work-protocol.md`, `93-automated-reviewer-loop-protocol.md`): Added a mandatory commit SHA verification step requiring agents to confirm a cited commit exists in `git log` before recording it as `resolved_commit` in the PR feedback ledger and before posting fix commit comments. If the SHA is absent, the agent must commit staged changes first and use the real SHA from `git log`. Prevents fabricated SHA references (as observed in PR #321) from propagating into the audit trail and causing PRs to be labeled `ready-for-human-review` with uncommitted fixes.
- **Runtime CWD guard to prevent Step 5.2 branch leaks** (`scripts/development-workflow/worktree-cwd-guard.sh`, `91-orchestrate-work-protocol.md`, `90-batch-orchestrate-work-protocol.md`, #411): After Batch 22 exceeded the escalation threshold with 3 Step 5.2 violations (items #384, #367, #401 all left the main working tree on the wrong branch), the protocol-text-only pre-op checklist from PR #345 was reinforced with a runtime enforcement mechanism. New `scripts/development-workflow/worktree-cwd-guard.sh` provides sourced shell wrapper functions (`git_switch`, `git_checkout`, `git_reset`, `git_restore`) that assert the current working directory is inside the isolated worktree — not the main repo root — before executing. Violations emit a `GUARDRAIL WARNING` with a corrected command suggestion and return exit code 1 (non-blocking by design, matching Protocol 91's existing advisory-hook pattern). Protocol 91 Step 3 gains a "Runtime CWD guard" block instructing agents to source and initialise the guard immediately after entering the worktree. Protocol 90 Step 5.2 recurrence-tracking text updated to reference PR #411 and the new guard, and to replace the generic escalation message with specific guidance on verifying whether the guard was active.
- **Re-query `reviewThreads` after each push before Step 8c** (`91-orchestrate-work-protocol.md`, `93-automated-reviewer-loop-protocol.md`): Agents were checking reviewer thread state once (before the final push) and then labeling PRs `ready-for-human-review` without re-querying. New bot-created threads from the push were missed, causing PRs to be labeled with unresolved comments. Added a mandatory "Re-query reviewThreads after each push" section to both Protocol 91 Step 7 and Protocol 93, requiring a fresh GraphQL `reviewThreads` query after every fixer push before proceeding to Step 7b/Step 8 or reporting readiness. Closes #330.
- **`batch-merge.sh merge` left PRs in `OPEN` state after batch push** (#412): `cmd_merge()` performed a local `git merge` but never pushed the merge commit or called `gh pr merge`, so GitHub left PRs in `OPEN` state (requiring manual cleanup each batch). Added `git push origin develop` and targeted `gh pr merge --merge` error handling inside `cmd_merge()` immediately after a successful local merge. The `gh pr merge` call now logs a warning to stderr when it fails for a non-idempotent reason (PR not yet MERGED) rather than silently swallowing the error. Protocol 94 Step 4.2 updated to note that the push is now handled inside the script.
- **Team-prefixed issue identifiers not detected in `post-merge-cleanup.sh`** (#341): The script's regex only matched pure numeric IDs (e.g. `fix/42-slug`), causing it to log "No issue number detected" and skip tracker updates for branches using Linear-style team-prefixed identifiers (e.g. `implementation-plan/lh-97-buscar-propiedades-vista-tabla`, `fix/rad-42-something`). Extended the regex to also match `<team>-<number>` patterns (2–6 alpha chars, case-insensitive). The numeric part is extracted for `gh issue` and `update_tracker_status_best_effort` calls (both require a numeric GitHub issue number); the full identifier (e.g. `lh-97`) is captured in `ISSUE_IDENTIFIER` for informational log output.
- **Worktree isolation: agents still switching branches in main working tree** (`03-implement-development-protocol.md`, `91-orchestrate-work-protocol.md`, `93-automated-reviewer-loop-protocol.md`): Protocol 91's "Critical: Worktree Git Discipline" block now includes an explicit pre-operation checklist — agents must confirm they are inside the worktree path (not the main repo root) and must skip base-branch checkout steps before any state-changing git command. All four branching steps in Protocol 03 (Full Pipeline, Refactor, Fast Track, Hotfix) gain a "Worktree context" note instructing agents to skip `git checkout <base> && git checkout -b` when the worktree was already created on the correct branch. Protocol 93 adds a "Worktree discipline for fixer agents" section that carries the same pre-operation checklist to reviewer-loop fixer dispatch in batch contexts.- **Shell variable interpolation in GraphQL mutation** (`workflow-lib.sh`): `update_tracker_status_best_effort` was interpolating `${project_id}`, `${item_id}`, `${field_id}`, and `${option_id}` directly into the query string. Switched to `-f` parameterized variables with a typed mutation signature (`$projectId: ID!`, `$itemId: ID!`, `$fieldId: ID!`, `$optionId: String!`), eliminating the injection risk and aligning with the safe pattern used elsewhere in the codebase.
- **Sync-template: post-apply path verification** (`.claude/skills/sync-template.md`, `.claude/commands/sync-template.md`, `.cursor/commands/sync-template.md`): After applying any file that contains cross-references to workflow doc paths, the sync-template skill now instructs the agent to verify that every resulting path resolves to an actual file in the project. This catches cases where a path-prefix rename (e.g., `docs/ai/` → `docs/workflow/`) is applied correctly but protocol numbers that shifted between the old and new directory trees are not — the root cause of the broken references in PR #188.
- **Sync-template leaves stale renamed directory in place** (`sync-manifest.yaml`, `.claude/commands/sync-template.md`, `.claude/skills/sync-template.md`, `.cursor/commands/sync-template.md`): When the template renames an always-sync directory (e.g., `docs/ai/` → `docs/workflow/`), the "never delete project-only files" rule previously prevented removal of the old directory, leaving both trees in place with stale cross-references. Added a `rename_detections` section to `sync-manifest.yaml` and updated all sync-template skill/command variants to detect stale old directories during Step 2 and present a "Rename cleanup" section in Step 3 — offering to delete the old directory and update cross-references in project-specific files. Each action requires separate maintainer approval; neither is applied silently. Bulk approval phrases ("apply all", "yes to all") do not cover rename cleanup actions.
- **Shell variable interpolation in GraphQL mutation** (`workflow-lib.sh`): `update_tracker_status_best_effort` was interpolating `${project_id}`, `${item_id}`, `${field_id}`, and `${option_id}` directly into the query string. Switched to `-f` parameterized variables with a typed mutation signature (`$projectId: ID!`, `$itemId: ID!`, `$fieldId: ID!`, `$optionId: String!`), eliminating the injection risk and aligning with the safe pattern used elsewhere in the codebase.
- **`.worktrees/` not gitignored** (`.gitignore`): Some item-orchestrator agents choose `.worktrees/<slug>/` as the worktree base path instead of `.claude/worktrees/<slug>/`. Both are valid isolation paths, but only the `.claude/worktrees/` prefix was gitignored, causing `.worktrees/` directories to appear as untracked noise in `git status` after parallel batch runs. Added `.worktrees/` to `.gitignore` alongside the existing `.claude/worktrees/` entry.
- **Plan-writing and spec-writing agents adding CHANGELOG entries to exempt PRs** (#340): `implementation-plan/*` and `spec/*` branches are exempt from CHANGELOG updates per the project changelog policy, but agents occasionally added entries anyway, triggering an unnecessary internal-review fix cycle. Added explicit `Do NOT update CHANGELOG` steps to `02-generate-implementation-plan-protocol.md` and `01-generate-spec-protocol.md`, and added a blocking finding to the Spec and Plan Review checklists in `REVIEW.md` so the exemption is caught at review time if missed at authoring time.
- **`hasReviewSummary` check false negatives** (`workflow-next-action.sh`, `90-batch-orchestrate-work-protocol.md`, `91-orchestrate-work-protocol.md`, `03-implement-development-protocol.md`, `agent-model-config.md`): Protocol 90 Step 5.1, Protocol 91 Step 8c, `workflow-next-action.sh`, `03-implement-development-protocol.md`, and `agent-model-config.md` all checked for the exact strings `"Automated Reviewer Loop Summary"` or `"No blocking PR feedback"` in PR comments. The `automated-reviewer-loop` agent posts a comment titled `## Reviewer Loop Summary` (without the word "Automated"), causing every completed reviewer loop run to be misclassified as incomplete and triggering unnecessary redispatches. Extended all check patterns to also match `"Reviewer Loop Summary"` so detection is robust to both the full and the abbreviated comment title.
- **Wildcard `rm -rf` in sync-template cleanup** (`.claude/skills/sync-template.md`, `.cursor/commands/sync-template.md`): The Step 0 clone block did not assign the temp directory to `TEMPLATE_TEMP_DIR`, and the cleanup step used `rm -rf /tmp/template-sync-*` (a wildcard that could delete dirs from concurrent or prior runs). Updated both files to assign `TEMPLATE_TEMP_DIR="/tmp/template-sync-$(date +%s)"` in Step 0 and use `rm -rf "$TEMPLATE_TEMP_DIR"` in the cleanup step, consistent with the already-fixed `.claude/commands/sync-template.md`.
- **Step 5.2 recurrence tracking** (`90-batch-orchestrate-work-protocol.md`, #362): Added an explicit recurrence-tracking requirement to Step 5.2 (Post-Agent Main Working Tree Verification). After PR #345 (worktree pre-op checklist) was merged, orchestrators must now tally Step 5.2 Case 1 (wrong branch + clean) violations across batches. If the guardrail fires more than once per 5 batches after that fix, the orchestrator escalates to the human with a recommendation to implement a runtime enforcement mechanism (e.g., a pre-commit hook or CWD guard in the worktree setup script). Also added a Step 5.2 tally reminder to the retrospective notes section to ensure violations are reliably recorded across sessions.
- **Batch-merge orchestrator must not wrap merge calls in a single shell loop** (`94-batch-merge-protocol.md`, `batch-merge.sh`): Added an explicit sequencing rule to protocol Step 4.1 requiring that `batch-merge.sh merge --pr N` be called for exactly one PR at a time with `MERGE_RESULT` fully resolved before advancing to the next PR. Batching multiple calls in a non-interactive loop left the working tree in a conflicted state when any PR produced `MERGE_RESULT=conflict`, causing all subsequent merge attempts to fail. Added a pre-merge guard to `batch-merge.sh` that checks for unresolved conflict markers via `git status --porcelain` and exits non-zero with a clear diagnostic message before attempting `git checkout develop`.
- **Devin review cycles outracing fix commits** (#372): fixer agents were addressing findings one-by-one and pushing after each individual fix, causing reviewer bots (e.g. Devin) to start re-reviewing stale state mid-fix and triggering unnecessary extra review cycles. Protocols `91-orchestrate-work-protocol.md` (Step 7) and `93-automated-reviewer-loop-protocol.md` now include an explicit mandatory batching rule: fixer agents must read all blocking findings first, apply all addressable fixes, and push exactly once per dispatch cycle rather than once per finding.
- **Plan PR opened before spec PR merged** (#373): when spec and plan are written in the same agent run, the item-orchestrator was opening the plan PR before the spec PR merged, causing reviewer bots to block the plan PR with "spec file not present on branch." Added a "Spec-Plan ordering gate" to `91-orchestrate-work-protocol.md` Step 2: if a plan branch exists locally but the spec PR is not yet merged, the orchestrator must not open the plan PR. It stops after the spec PR reaches `ready-for-human-review` and reports to the orchestrator that the plan PR will be opened in the next dispatch after spec merge is confirmed. A verification step (`gh pr view <spec_pr> --json state`) is now required before `gh pr create` for any `implementation-plan/*` branch.
- **`jq` parse error on `gh project item-list` output with control characters** (`workflow-lib.sh`, #375): `jq` failed with `Invalid string: control characters from U+0000 through U+001F must be escaped` when any project item's linked issue body contained literal control characters (newlines, tabs, backslash sequences). Replaced the two `gh project item-list ... | jq` pipelines in `get_tracker_status_for_issue` and `update_tracker_status_best_effort` with Python3 `json.load()` equivalents, which handle unescaped control characters correctly. All downstream field extractions (`id`, `status`) in the same functions were also migrated to Python3 to keep the parse chain consistent.
- **Shell script quality checklist added to developer protocol and agent rules** (#388): PR #385 required 14 Devin review cycles (94% fix-commit ratio) due to systematic bash anti-patterns in the initial draft. Added a "Shell Script Quality Checklist" top-level section to `03-implement-development-protocol.md`, triggered when a change creates or significantly modifies a `.sh` file. Covers: jq variable injection (always use `--arg`/`--argjson`, never interpolate shell vars in filter strings); `set -o pipefail` SIGPIPE false-positives (exit 141 from `head`/`grep -m` — use `trap ... EXIT` or `|| true`; note: `trap ... PIPE` does not fire in the parent shell for pipeline SIGPIPE); exit code semantics under `set -e` (`result=$(cmd)` aborts on non-zero just like a bare command; use `if !` or `|| true` to safely handle failures); timestamp sourcing (use server-returned timestamps, not local `date`); the `local` exit-code trap (`local VAR=$(cmd)` always sets `$?` to 0 because `local` itself exits 0 — declare with `local VAR` then assign on a separate line); `gh` CLI/API error handling (always guard against non-zero exits and empty output); input validation (use `${VAR:?...}` for all positional parameters at script entry). Added a corresponding key-rule bullet to `.claude/agents/developer.md` and `.cursor/agents/developer.md` summarizing all seven checklist items.
- **Retrospective offer timing violation in Protocol 90 Step 6** (#410, #419): the batch orchestrator was offering the retrospective in the final batch summary while PRs were still `ready-for-human-review` and not yet merged. Added a prominent blockquote guardrail warning at the top of Step 6 labelled "STOP — retrospective timing rule" that explicitly prohibits including a retrospective offer in the batch summary and names it a guardrail violation. Added a `<!-- DO NOT add a retrospective offer here -->` comment to the summary template itself to make the exclusion structurally present in the template output. Bolded the "Retrospective timing" label on the existing prose rule to increase visual salience. Follow-up (#419): the positive prohibition remained too weak and continued to be overridden at the natural closing moment. Reinforced by (A) adding a hard `❌ Do NOT append this` negative example block directly inside Step 6 after the summary template, and (B) moving the retrospective offer into a new structural **Step 6.5: Post-Merge Follow-up** section explicitly gated on post-merge confirmation — making it structurally impossible to conflate with the summary step.
- **`ready-for-regression` label enforcement at orchestrator Step 5.1** (`90-batch-orchestrate-work-protocol.md`, `91-orchestrate-work-protocol.md`, #422): In Batches 22 and 23, agents applied `ready-for-human-review` but omitted `ready-for-regression` on `fix/*` PRs, preventing the e2e/regression CI workflow from triggering. Two changes close this gap: (1) Protocol 90 Step 5.1 verification table now includes per-check remediation actions — the `ready-for-regression` row designates the orchestrator as the **primary enforcement point** that applies the label directly, logs `PROTOCOL_DEVIATION`, and then re-runs `pr-ci-loop.sh` to wait for the label-triggered e2e workflow before re-evaluating the CI row (without this re-poll the e2e check would not yet be in `statusCheckRollup` and the PR would be declared ready prematurely); (2) Protocol 91 Step 8a Check 2 is strengthened with a critical notice and a self-healing sentinel: if the label is absent the agent applies it inline and exits with code 2 ("label applied — re-run Step 8 CI loop before re-entering 8a"), ensuring the e2e/regression check triggered by the label is waited upon before `ready-for-human-review` is applied.

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

[Unreleased]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.2...HEAD
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
