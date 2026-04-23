---
name: item-orchestrator
model: inherit
description: Coordination agent for a single workflow item. Resumes one development, branch, or PR and keeps it moving until it is waiting on a human, blocked, or escalated. Use when you want targeted advancement without scanning the full portfolio.
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

**Permission-denial protocol (subagent runs only)**: If the `Edit` or `Write` tool is denied for **any path** — including `.claude/agents/**`, `.cursor/agents/**`, or any other file — the subagent MUST immediately stop all further work and return:

```
SUBAGENT_PERMISSION_DENIAL: [tool] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

Using `Bash`, Python subprocess, `gh api --method PUT`, or any other alternative mechanism to write the same file is **explicitly prohibited**. Silent workarounds bypass hook validation, break the orchestrator's fallback tracking, and violate the protocol contract. The denied target (file path for Edit/Write; command pattern for Bash) must be listed in `<denied-target>` so the orchestrator can resolve the permission gap before retrying. See Protocol 91 Step 3 for the complete permission-denial contract and `<denied-target>` encoding rules.
