# Repository-level scripts

Scripts intended to be run from the monorepo root or from CI/CD.

## AI development workflow (Codex / orchestrator)

Scripts used by the staged AI development workflow. Referenced by `docs/ai/development-workflow/` and by the Codex skills in `.codex/skills/`.

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

Use this when:
- You want a quick view of what work is already in progress
- The orchestrator needs a deterministic summary before choosing the next stage

### `check-workflow-branch.sh`

Checks whether a specific workflow branch already exists locally, remotely, or in an active worktree.

Usage:

```bash
./scripts/check-workflow-branch.sh <branch-name>
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
