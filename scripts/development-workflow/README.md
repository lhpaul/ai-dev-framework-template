# Development workflow scripts

Scripts used by the staged AI development workflow. Referenced by `docs/workflow/development-workflow/` and by the Codex skills in `.agents/skills/` and `.codex/skills/`. Run from the repository root.

## `install-codex-skills.sh`

Installs the repository's bundled Codex skills into the local Codex skill directories by creating symlinks.

What it does:

- Reads repo-discoverable skills and command aliases from `.agents/skills/`
- Keeps legacy canonical skill compatibility from `.codex/skills/`
- Installs into `AGENTS_HOME/skills` if `AGENTS_HOME` is set, otherwise `~/.agents/skills`
- Also installs into `CODEX_HOME/skills` if `CODEX_HOME` is set, otherwise `~/.codex/skills`, for older local setups
- Skips an existing destination if it is not a symlink

Use this when:

- You want to make the template's bundled Codex skills and command-style aliases available in your local Codex environment
- You are testing the workflow skills in a downstream repository created from this template

### `add-backlog-item.sh`

Resolves the configured issue tracker destination for backlog creation and can create a GitHub issue when `issue_tracker.provider` maps to GitHub Issues / GitHub Projects.

Usage:

```bash
./scripts/development-workflow/add-backlog-item.sh resolve
./scripts/development-workflow/add-backlog-item.sh create --title "Title" --body "Body"
./scripts/development-workflow/add-backlog-item.sh create --title "Title" --body-file path/to/body.md
```

What it does:

- `resolve` prints `ISSUE_TRACKER_PROVIDER`, `DESTINATION_KIND` (`github`, `linear`, `other`, `none`), and a `CREATE_VIA` hint for agents.
- `create` runs `gh issue create` when the destination kind is `github` (requires authenticated `gh`).
- For Linear or unsupported providers, exits non-zero with guidance so agents follow `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` instead of guessing.

Use this when:

- An agent needs a deterministic destination check before creating a backlog item.
- You want to create a GitHub issue from a shell environment without manual `gh` typing.

### `discover-workflow-state.sh`

Prints a compact snapshot of the repository's workflow-related state.

What it does:

- Shows `git status --short --branch`
- Lists workflow branches (`spec/`, `implementation-plan/`, `feature/`, `refactor/`, `fix/`, `hotfix/`, `release/`)
- Lists active git worktrees
- Lists directories under `docs/specs/developments/` if they exist
- Lists open pull requests, labels, and check summaries when `gh` is available

Use this when:

- You want a quick view of what work is already in progress
- The orchestrator needs a deterministic summary before choosing the next stage

### `check-workflow-branch.sh`

Checks whether a specific workflow branch already exists locally, remotely, or in an active worktree.

Usage:

```bash
./scripts/development-workflow/check-workflow-branch.sh <branch-name>
```

What it does:

- Reports matching local branches
- Reports matching remote branches
- Reports matching worktrees
- Exits with status `0` if the branch exists anywhere
- Exits with status `1` if the branch is missing

Use this when:

- The orchestrator needs to verify whether a workflow item has already been started
- You want to avoid re-dispatching work for an item that already has a branch or worktree

### `pr-ci-loop.sh`

Polls GitHub status checks for a PR until they are green, failing, or timed out.

Usage:

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr-number> [--poll-interval 60] [--max-wait 1800]
```

What it does:

- Reads the PR's `statusCheckRollup` via `gh`
- Reports a stable `RESULT=green|red|timeout`
- Emits parseable `key=value` lines for failing and pending checks

Use this when:

- A stage has opened a PR and needs to wait for CI before signaling readiness
- The orchestrator is resuming a partially completed PR

### `pr-review-loop.sh`

Runs one or more automated PR review platforms in order, then classifies findings into blocking vs suggestion.

Usage:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch feature/my-branch] [--platform greptile] [--platform devin] [--platform coderabbit]
```

What it does:

- Evaluates configured draft and ready GitHub review platforms sequentially
- Runs the platform adapter for each supported platform
- Stops on the first platform that reports blocking findings or escalation
- Reports a stable aggregate `RESULT=clean|needs_fixes|escalate|skipped`
- Emits ordered per-platform `PLATFORM_<n>_*` records plus the matching compatibility fixer
- If no GitHub reviewers are configured, reports `RESULT=skipped`

Use this when:

- A stage has pushed to a PR branch and must resolve automated review before requesting human review
- The orchestrator is resuming a PR after a prior push or interruption
- More than one automated reviewer is configured for a repository

### `workflow-next-action.sh`

Classifies the next deterministic workflow action for a branch, PR, or development folder.

Usage:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch feature/my-branch
./scripts/development-workflow/workflow-next-action.sh --pr 42
./scripts/development-workflow/workflow-next-action.sh --development docs/specs/developments/20260307120000_my-feature
```

What it does:

- Detects whether a branch still needs reviewer-gate work or PR readiness work
- Detects whether a PR is waiting on fixes or on human review
- For `--development`: derives workflow status from repo state (presence of implementation plan file, feature branch) so the **issue tracker remains the source of truth**; no `**Status**` line in the spec is required. Outputs `LINEAR_ISSUE` when the spec has `**Linear Issue**: <id>` (note the space after the colon) for orchestrator use. Runs `git fetch --prune origin` unless `WORKFLOW_SKIP_FETCH` is set (e.g. run one fetch before looping over many development folders); if fetch fails, a warning is printed to stderr and refs may be stale. Without an issue tracker, items that were merged and had their branch deleted can appear as Plan Ready; prefer filtering by tracker status when available. The `--development` branch-detection logic has no automated tests; edge cases (slugs with regex metacharacters, Linear-prefixed branch names) should be validated manually when changing that path.

Use this when:

- The orchestrator needs to resume work after an interrupted run
- A stage-specific agent needs to determine whether work is still in-progress or already waiting on a human

For resume behavior, run `workflow-next-action.sh` with `--branch`, `--pr`, or `--development`; it reports the next deterministic action for a partially completed run.

### `workflow-batch-plan.sh`

Classifies development folders into batch-planning candidates for the batch orchestrator.

Usage:

```bash
./scripts/development-workflow/workflow-batch-plan.sh
./scripts/development-workflow/workflow-batch-plan.sh docs/specs/developments/20260307120000_my-feature
```

What it does:

- Scans one or more development folders
- Uses `workflow-next-action.sh --development` to derive the next deterministic action
- Emits stable `key=value` records including `BATCH_HINT` and `PARALLEL_SAFE`

Use this when:

- The batch orchestrator needs a deterministic first-pass list of development-folder candidates
- You want to separate portfolio-level batch planning from single-item orchestration

### Workflow hub product repository commands

These commands run only when `.ai-dev-workflow.yaml` resolves to
`mode: workflow_hub`. They use the shared repository-context resolver, support
`--repo <name>` for one configured product repository and `--all` for every
configured product repository, and fail before checkout inspection when the
current repository is not a workflow hub.

#### `hub-status.sh`

Inspects local product repository checkouts without modifying them.

Usage:

```bash
./scripts/development-workflow/hub-status.sh --repo mobile-app
./scripts/development-workflow/hub-status.sh --all
```

What it reports:

- Product repository name and local checkout path
- Current branch when the checkout exists
- `clean`, `dirty`, `missing_path`, `missing_checkout`, or `failed` status
- Origin remote visibility
- A final categorized summary across all selected repositories

Use this before routing implementation work from a workflow hub to confirm that
the selected checkout exists and that dirty state is visible.

### Workflow hub smoke fixture

Run the non-secret workflow-hub smoke fixture with:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
```

The harness copies the committed seed under
`scripts/development-workflow/tests/fixtures/workflow-hub-smoke/` into a
temporary hub checkout, creates two dummy product repositories, and validates
configuration parsing, local checkout resolution, product status/sync commands,
product PR dry-run routing, mode-scope classification, and single-repository
regression behavior. It never needs private product repositories or live GitHub
App credentials by default.

Optional live GitHub App validation is separate and must be requested with
`--live-github-app` plus operator-supplied safe-test repository environment
variables. Do not wire the live path into default CI.

### `select-sync-manifest-entries.py`

Selects `sync-manifest.yaml` entries for a repository role before sync-template
compares or applies files.

Usage:

```bash
python3 scripts/development-workflow/select-sync-manifest-entries.py \
  --manifest sync-manifest.yaml \
  --role workflow_hub
```

What it does:

- Validates declared `mode_scope` values.
- Selects all entries for `single_repo` compatibility.
- Selects `shared` plus `hub_only` for `workflow_hub`.
- Selects `shared` plus `product_repo_injection` for `product_repo`.
- Prints selected and skipped entries with stable `KEY=value` output for tests
  and sync-template summaries.
- Fails closed on unknown roles, missing entry scopes, and unknown scope values
  before any file mutation path can proceed.

Run focused coverage with:

```bash
bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh
```

#### `hub-sync-product-repos.sh`

Safely prepares clean product repository checkouts.

Usage:

```bash
./scripts/development-workflow/hub-sync-product-repos.sh --repo mobile-app
./scripts/development-workflow/hub-sync-product-repos.sh --all
./scripts/development-workflow/hub-sync-product-repos.sh --repo mobile-app --bootstrap-local-path --yes
```

What it does:

- Refuses dirty checkouts before fetch or fast-forward work
- Fetches the configured default branch and fast-forwards only when local state
  is not ahead of origin
- Blocks ahead-only or diverged checkouts instead of rebasing, stashing,
  resetting, force-updating, or pushing
- Reports partial success and blocked or failed repositories in the final
  summary
- Writes a missing local path to `.ai-dev-workflow.local.yaml` only when
  `--bootstrap-local-path` is set and the operator confirms the prompt, or when
  `--yes` is also supplied

#### `hub-list-prs.sh`

Lists open pull requests for selected product repositories without modifying
remote state.

Usage:

```bash
./scripts/development-workflow/hub-list-prs.sh --repo mobile-app
./scripts/development-workflow/hub-list-prs.sh --all
```

The command resolves `github_repo` directly, or derives `owner/repo` from
GitHub-form `git_url` values such as `git@github.com:owner/repo.git` and
`https://github.com/owner/repo.git`. If no GitHub repository slug can be
resolved, it fails for that product repository instead of falling back to the
workflow hub repository.

### `post-merge-cleanup.sh`

After a development PR is merged and the remote branch deleted, sync with
origin, switch to the merged PR's base branch, pull, and delete the local
branch.

Usage:

```bash
./scripts/development-workflow/post-merge-cleanup.sh [--base develop-workflow-hub-mode] [BRANCH]
```

- No argument: use the current branch (run while still on the merged branch).
- With `BRANCH`: branch name to delete (e.g. `feature/my-feature`).
- With `--base`: explicitly choose the cleanup base branch. When omitted for
  hub-owned branches, the script queries the merged PR base and falls back to
  `develop` only if that lookup is unavailable.

Use this when:

- You have merged a feature/plan/spec PR and deleted the remote branch, and want
  to clean up the local branch and update the correct base branch.

### `prepare-release-post-merge-cleanup.sh`

After both release PRs (`release/*` -> `main` and `release/*` -> `develop`) are merged, verify merge state, remove the release branch remotely and locally, and optionally transition scoped tracker items from `Merged` to `Released`.

Usage:

```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh <version|release-branch> [--issue N]... [--issues N,N,...]
```

Examples:

```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --issues 232,240
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issue 232
```

Use this when:

- Both release PRs are already merged and you need deterministic release-branch cleanup.
- You want explicit, scoped tracker transitions to the terminal shipped status.

### `batch-merge.sh`

Deterministic merge pipeline for parallel batch PRs. Handles PR discovery (auto or explicit), metadata collection, merge ordering (non-CHANGELOG PRs first by ascending PR number, then CHANGELOG PRs by ascending PR number), and single-PR merge execution with structured key-value output.

Usage:

```bash
# Discovery mode — auto-discover all ready-for-human-review PRs targeting develop
./scripts/development-workflow/batch-merge.sh discover

# Discovery mode — explicit PR list
./scripts/development-workflow/batch-merge.sh discover --prs 101,102,103

# Per-PR merge — attempt to merge one PR into develop (called in a loop by the agent)
./scripts/development-workflow/batch-merge.sh merge --pr 101
```

Outputs structured `KEY=VALUE` lines. See the script header for the full output format.

Use this when:

- The agent protocol `94-batch-merge-protocol.md` is running a batch merge.
- You want to inspect the merge ordering for a set of PRs before invoking the agent command.
- Called by the `/batch-merge` Claude Code command, `/batch-merge` Cursor command, or the `/batch-merge` / `batch-merge` Codex skill alias.
