# fix(item-orchestrator): Write/Edit path guardrail for isolated worktrees — Spec

**Depends on**: none

---

## Overview

When item-orchestrator agents run inside isolated git worktrees during parallel batch execution, they repeatedly issue `Write` and `Edit` tool calls with main-repo-absolute paths instead of worktree-relative paths. The files land in the main repo root instead of the worktree, require manual relocation, and risk polluting the `develop` branch if undetected. This spec defines the guardrails — both protocol-level instructions and an optional pre-tool-use hook — that prevent this path mismatch from occurring.

---

## Use Cases

### Use Case 1: Item-orchestrator receives explicit path reminder after worktree creation

**Actor**: Item-orchestrator agent (automated, running as part of a parallel batch with `BATCH_CONTEXT=true`)
**Preconditions**: A worktree has been created at `<repo-root>/.claude/worktrees/<item-id>/<branch-slug>` and the stage agent (e.g., `product-manager`) is about to be dispatched.

**Steps**:
1. Item-orchestrator creates the worktree and records the worktree path as `<worktree-path>`.
2. The worktree isolation section of Protocol 91 Step 3 includes an explicit reminder that the orchestrator passes to every stage agent it dispatches: "All `Write` and `Edit` tool calls from this point forward must target paths under `<worktree-path>/...`. Any path that does not begin with `<worktree-path>/` is a main-repo path — correct it before calling the tool."
3. The dispatched stage agent reads this reminder and issues `Write`/`Edit` calls with paths under `<worktree-path>/`.
4. Files are created in the correct worktree location.

**Postconditions**: No files are written to the main repo root by mistake; the spec, plan, or implementation files land inside the worktree.

**Information shown**: N/A (automated)

**Actions available**: N/A (automated)

**Considerations**:
- The reminder must include the literal `<worktree-path>` value resolved at runtime, not a placeholder, so the stage agent can compare its intended path against the worktree root without ambiguity.
- The reminder must appear in every sub-task handoff the item-orchestrator issues, not only the first one, because a multi-step agent may lose track of the boundary mid-run.

---

### Use Case 2: Pre-tool-use hook warns when a Write call targets a path outside the worktree

**Actor**: Pre-tool-use hook script running inside an agent session that was launched with a designated worktree root.
**Preconditions**: The agent session has a `WORKTREE_ROOT` environment variable set to the worktree path. A stage agent issues a `Write` or `Edit` tool call.

**Steps**:
1. The pre-tool-use hook intercepts the `Write` (or `Edit`) call.
2. The hook checks whether the target path starts with the value of `WORKTREE_ROOT`.
3. If the target path does NOT start with `WORKTREE_ROOT`, the hook emits a blocking warning:
   `"GUARDRAIL: Write/Edit target '<path>' is outside the designated worktree '<WORKTREE_ROOT>'. Correct the path before proceeding."`
4. The agent reads the warning, corrects the path to the worktree-relative equivalent, and retries the tool call.
5. The corrected call targets a path under `WORKTREE_ROOT` and succeeds without triggering the hook.

**Postconditions**: No file is written to the main repo root; the agent self-corrects before the write lands.

**Information shown**:
- Warning message including the offending path and the expected worktree root.

**Actions available**:
- Agent corrects the path and retries.

**Considerations**:
- The hook should not block reads (`Read`, `Glob`, `Grep`) — reads from main-repo paths are legitimate (e.g., reading a protocol doc).
- The hook applies only to `Write` and `Edit` tool calls.
- Paths that begin with `<worktree-path>/.tmp/` are also within the worktree boundary and must not trigger the warning.
- When `WORKTREE_ROOT` is not set (agent is not running inside a worktree), the hook must skip the check entirely — it should not interfere with non-worktree sessions.
- This use case is marked Optional in this spec; the protocol-level reminder (Use Case 1) is the mandatory fix.

---

### Use Case 3: Stage agent issues a sub-task handoff and the worktree reminder is present in every handoff

**Actor**: Item-orchestrator agent dispatching multiple sequential stage agents (e.g., `product-manager` then `spec-reviewer`).
**Preconditions**: Worktree is active; multiple stage agents will be dispatched in sequence.

**Steps**:
1. Item-orchestrator dispatches `product-manager` with handoff including the worktree-path reminder.
2. `product-manager` completes and returns.
3. Item-orchestrator dispatches `spec-reviewer` (or any subsequent stage agent) with a new handoff that also includes the worktree-path reminder.
4. Each successive stage agent receives the reminder independently.

**Postconditions**: Every agent dispatched within the run has seen the worktree-path reminder at least once in its own context.

**Information shown**: N/A (automated)

**Actions available**: N/A (automated)

**Considerations**:
- Because each stage agent starts a fresh context, reminder inheritance from a prior agent's context cannot be assumed. The reminder must be re-stated in each handoff.
- The reminder text should be identical across handoffs so it is recognizable as a standard guard, not a contextual one-off comment.

---

### Use Case 4: Non-batch run (BATCH_CONTEXT=false) — no worktree reminder or hook

**Actor**: Item-orchestrator agent running in a non-batch (single-item, direct invocation) context.
**Preconditions**: `BATCH_CONTEXT=false` or absent; no dedicated worktree was created.

**Steps**:
1. Item-orchestrator proceeds without creating a worktree.
2. No worktree-path reminder is injected into stage-agent handoffs.
3. The pre-tool-use hook (if installed) does not trigger because `WORKTREE_ROOT` is not set.
4. Normal workflow proceeds.

**Postconditions**: Non-batch behavior is unchanged; no spurious warnings or reminders in single-item runs.

**Considerations**:
- The guardrail is additive and must not degrade or change the non-batch execution path.

---

## Business Rules

- When `BATCH_CONTEXT=true`, the worktree isolation section of Protocol 91 Step 3 MUST include an explicit reminder stating that all `Write` and `Edit` tool calls must target paths under `<worktree-path>`, not under the main repo root.
- The reminder MUST include the resolved runtime value of `<worktree-path>`, not a generic placeholder.
- The reminder MUST be repeated in every stage-agent handoff issued by the item-orchestrator for the duration of the parallel batch run.
- When `BATCH_CONTEXT=false` or absent, no reminder is injected and no hook fires.
- The pre-tool-use hook (Use Case 2) is optional. If implemented, it MUST only fire on `Write` and `Edit` calls, not on read-only tools.
- When `WORKTREE_ROOT` is unset, the hook MUST be a no-op.
- The guardrail changes are scoped to the worktree isolation section of Protocol 91 Step 3 and optionally the `.claude/agents/item-orchestrator.md` handoff template. No other scripts or protocols are modified.

---

## Acceptance Criteria

- [ ] The worktree isolation section of Protocol 91 Step 3 contains an explicit, human-readable reminder that all `Write` and `Edit` tool calls must target paths under `<worktree-path>/...` and that any main-repo-absolute path is a red flag to correct before calling the tool.
- [ ] The reminder specifies that `<worktree-path>` must be resolved to its runtime value before being included in stage-agent handoffs.
- [ ] The reminder specifies that it must appear in every stage-agent handoff (not just the first) issued for the item.
- [ ] The protocol language makes clear the guardrail applies only when `BATCH_CONTEXT=true` (a dedicated worktree exists).
- [ ] (Optional) A pre-tool-use hook design is described that intercepts `Write`/`Edit` calls, checks the target path against `WORKTREE_ROOT`, and emits a blocking warning if the path is outside the worktree.
- [ ] (Optional) The hook spec states that when `WORKTREE_ROOT` is unset the hook is a no-op.
- [ ] The changes do not alter Protocol 91 behavior for non-batch runs, Protocol 90, `post-merge-cleanup.sh`, `pr-review-loop.sh`, or any scope covered by issue #192 (git switch/checkout guardrail).

---

## Out of Scope (MVP)

- The `git switch`/`git checkout` guardrail (tracked in issue #192).
- Changes to `post-merge-cleanup.sh`, `batch-merge.sh`, `pr-review-loop.sh`, or any implementation script.
- Protocol 90 Step 3 batch-dispatch logic (covered by issue #199, recently merged).
- Step 7a internal review gate changes (issue #185's scope).
- Implementing the pre-tool-use hook as runnable code (the spec defines the behavior; implementation is deferred to the plan stage).
- Enforcement at the git level (e.g., pre-commit hooks that reject stray files in the main repo).
- Retroactive cleanup tooling for already-leaked files.

---

## Open Questions

None.
