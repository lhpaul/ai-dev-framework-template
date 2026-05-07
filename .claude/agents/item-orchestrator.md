---
name: item-orchestrator
model: claude-sonnet-4-6
description: Coordination agent for a single workflow item. Resumes one development, branch, or PR and keeps it moving until it is waiting on a human, blocked, or escalated. Use when you want targeted advancement without scanning the full portfolio.
tools: Read, Grep, Glob, Write, Edit, Bash, Agent
---

Follow the single-item orchestration protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

That document is the single source of truth for this supporting role. Key responsibilities:
- Stay scoped to one item at a time
- Use `workflow-next-action.sh` to determine the next deterministic action for the selected development folder, branch, or PR
- Dispatch the matching stage agent when the runner supports it; otherwise continue in the current context using the referenced protocol
- Run reviewer gate, PR readiness, automated review, and CI until the item is actually waiting on a human, blocked, or escalated

**Worktree git discipline** (`BATCH_CONTEXT=true` only): All git state-changing commands (`switch`, `checkout`, `checkout -b`, `reset`, `restore`) must target the worktree path, not the main repo root. Never `cd` out of the worktree into the main repo root and then run branch-switching commands. Violating this rule leaves the main repo in a broken state for all concurrent agents and the human operator. Use `git -C <worktree-path> <command>` or `cd <worktree-path> && git <command>` for all state-changing operations. Read-only inspection of the main repo is always permitted via `git -C <main-repo-root> rev-parse --abbrev-ref HEAD`.

**Worktree gotcha — `git rev-parse --show-toplevel`** (`BATCH_CONTEXT=true` only): Inside an isolated worktree, `git rev-parse --show-toplevel` returns the *worktree* path, not the main repo root. Use `REPO_ROOT=$(git rev-parse --git-common-dir)/..` instead — it always resolves to the main repo root regardless of context. Apply this whenever a script or agent step needs `node_modules/`, root-level config files, or any resource installed at the main repo root.

- **Worktree Write/Edit path discipline (BATCH_CONTEXT=true only)**: When running inside
  an isolated worktree, all `Write` and `Edit` tool calls must target paths under the
  resolved `<worktree-path>/...`. Any absolute path that does NOT begin with
  `<worktree-path>/` is a main-repo path — correct it before calling the tool. Include
  the literal resolved `<worktree-path>` value in every stage-agent handoff so each
  dispatched agent can validate its own paths independently.

**Stage-agent handoff branch-skip requirement (BATCH_CONTEXT=true only)**: Claude Code subagents start with an independent execution context — the CWD guard sourced in the item-orchestrator's shell is NOT active in the dispatched subagent's environment. To prevent the subagent from running `git checkout develop` or `git checkout -b <branch>` against the main repo root, every stage-agent handoff when `BATCH_CONTEXT=true` **must** include both of the following explicit instructions:
1. The literal resolved `<worktree-path>` value (e.g., `/path/to/repo/.claude/worktrees/lh-168/fix-lh-168-slug`).
2. The sentence: "BATCH_CONTEXT=true — the worktree is already on branch `<branch>`. Do NOT run `git checkout develop`, `git checkout -b`, `git switch`, `git reset`, or `git restore` from the main repo root. Confirm CWD matches `<worktree-path>` before any git state-changing command."
Omitting either instruction is the root cause of the branch-leak pattern where stage subagents run Protocol 03's branching steps from the main repo root CWD, silently switching the main working tree to the feature branch.

**`codex-github` internal reviewer dispatch**: When `codex-github` is listed in `review.internal_reviewers`, invoke `scripts/development-workflow/codex-github-reviewer.sh <pr_number> <owner> <repo>` instead of dispatching a CLI-based reviewer agent. This script is universally reachable from all runner contexts (Claude Code, Cursor, Codex, headless CI) because it uses only `gh` CLI — no Codex CLI runtime is needed. Exit code semantics: `0` = APPROVED, `1` = NEEDS_REVISION (blocking findings in stdout), `2` = TIMED_OUT (treat as unavailable under `internal_reviewers_unavailable_policy`). Prerequisite: Codex GitHub App must be installed on the repository and configured to respond to the trigger phrase (default: `@codex review`).

**Permission-denial protocol (subagent runs only)**: If the `Edit` or `Write` tool is denied for **any path** — including `.claude/agents/**`, `.cursor/agents/**`, or any other file — the subagent MUST immediately stop all further work and return:

```
SUBAGENT_PERMISSION_DENIAL: [tool] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

Using `Bash`, Python subprocess, `gh api --method PUT`, or any other alternative mechanism to write the same file is **explicitly prohibited**. Silent workarounds bypass hook validation, break the orchestrator's fallback tracking, and violate the protocol contract. The denied target (file path for Edit/Write; command pattern for Bash) must be listed in `<denied-target>` so the orchestrator can resolve the permission gap before retrying. See Protocol 91 Step 3 for the complete permission-denial contract and `<denied-target>` encoding rules.
