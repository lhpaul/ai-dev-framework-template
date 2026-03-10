# Development workflow scripts

Scripts used by the staged AI development workflow. Referenced by `docs/ai/development-workflow/` and by the Codex skills in `.codex/skills/`. Run from the repository root.

## `install-codex-skills.sh`

Installs the repository's bundled Codex skills into the local Codex skill directory by creating symlinks.

What it does:
- Reads skills from `.codex/skills/`
- Uses `CODEX_HOME/skills` if `CODEX_HOME` is set
- Otherwise uses `~/.codex/skills`
- Skips an existing destination if it is not a symlink

Use this when:
- You want to make the template's bundled Codex skills available in your local Codex environment
- You are testing the workflow skills in a downstream repository created from this template

### `discover-workflow-state.sh`

Prints a compact snapshot of the repository's workflow-related state.

What it does:
- Shows `git status --short --branch`
- Lists workflow branches (`spec/`, `implementation-plan/`, `feature/`, `fix/`, `hotfix/`, `release/`)
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

Triggers and polls the automated PR review tool, then classifies findings into blocking vs suggestion.

Usage:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch feature/my-branch]
```

What it does:
- Posts the Greptile trigger comment
- Polls for the completion signal
- Fetches new inline comments after the trigger
- Reports a stable `RESULT=clean|needs_fixes|escalate|skipped`
- Emits the matching fixer agent (`spec-reviewer`, `implementation-plan-reviewer`, or `code-reviewer`)

Use this when:
- A stage has pushed to a PR branch and must resolve automated review before requesting human review
- The orchestrator is resuming a PR after a prior push or interruption

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
- For `--development`: derives workflow status from repo state (presence of implementation plan file, feature branch) so the **issue tracker remains the source of truth**; no `**Status**` line in the spec is required. Outputs `LINEAR_ISSUE` when the spec has `**Linear Issue**: <id>` (note the space after the colon) for orchestrator use.

Use this when:
- The orchestrator needs to resume work after an interrupted run
- A stage-specific agent needs to determine whether work is still in-progress or already waiting on a human

For resume behavior, run `workflow-next-action.sh` with `--branch`, `--pr`, or `--development`; it reports the next deterministic action for a partially completed run.

### `post-merge-cleanup.sh`

After a development PR is merged and the remote branch deleted, sync with origin, switch to develop, pull, and delete the local branch.

Usage:

```bash
./scripts/development-workflow/post-merge-cleanup.sh [BRANCH]
```

- No argument: use the current branch (run while still on the merged branch).
- With `BRANCH`: branch name to delete (e.g. `feature/my-feature`).

Use this when:
- You have merged a feature/plan/spec PR and deleted the remote branch, and want to clean up the local branch and update develop.
