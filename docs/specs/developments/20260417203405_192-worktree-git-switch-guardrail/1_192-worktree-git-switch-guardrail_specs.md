# Worktree Git Switch Guardrail — Spec

**Depends on**: <!-- None -->

---

## Overview

When the Portfolio Orchestrator dispatches parallel Work Item Runners, each runner operates inside an isolated git worktree. A critical invariant is that the **main working tree must stay on the integration branch (`develop`) for the entire batch duration**. In batch 8 (plan PRs #187–#191), one Work Item Runner ran `git switch` against the main repo root instead of inside its worktree, silently leaving the main tree on `implementation-plan/173-markdown-lint-plan-spec-docs`. This spec defines guardrails that prevent such violations: explicit protocol wording in the item-orchestrator handoff prompt, a strengthened post-agent main-tree verification step that auto-corrects drift, and optional pre-tool-use hook guidance that warns when a state-changing git command is issued from the main repo root.

---

## Use Cases

### Use Case 1: Item-orchestrator agent runs git state-changing command from main repo root

**Actor**: Work Item Runner (item-orchestrator) agent executing inside an isolated worktree

**Preconditions**:

- The Work Item Runner was dispatched by the Portfolio Orchestrator with `BATCH_CONTEXT=true`
- A dedicated worktree has been created at `.claude/worktrees/<item-id>/<branch-name>`
- The agent's handoff prompt should instruct it to perform all git operations inside the worktree

**Steps**:

1. The item-orchestrator agent invokes a stage protocol (e.g., write-spec, write-plan, implement)
2. The stage protocol's initial branching steps include `git switch develop`, `git checkout -b <branch>`, or similar
3. Without an explicit guardrail, the agent runs these commands against the main repo root instead of with `git -C <worktree-path>` or from inside `cd <worktree-path>`
4. The main working tree silently changes its checked-out branch

**Postconditions (desired — after the guardrail is in place)**:

- The agent receives an explicit warning in the handoff prompt listing prohibited commands on the main repo root
- If a pre-tool-use hook is configured, the agent receives a tool-call-level warning before the command executes
- The main working tree remains on the integration branch

**Information shown**:

- Handoff prompt includes a clearly marked "Critical: Worktree Git Discipline" section listing the exact commands (`switch`, `checkout`, `checkout -b`, `reset`, `restore`) that must not target the main repo root
- The pre-tool-use hook (when active) prints a warning to stderr identifying the command, its working directory, and the expected worktree path

**Actions available**:

- Agent corrects the command to use `git -C <worktree-path>` or `cd <worktree-path> &&` prefix
- Agent aborts the command and escalates if the correct worktree path is not determinable

**Considerations**:

- The guardrail must not block legitimate read-only git commands against the main repo root (e.g., `git -C <main-repo-root> rev-parse --abbrev-ref HEAD` to inspect the main branch without switching)
- The guardrail applies only when `BATCH_CONTEXT=true`; single-item runs without a worktree are unaffected

---

### Use Case 2: Post-agent main-tree verification detects branch drift and auto-corrects

**Actor**: Portfolio Orchestrator running Step 5.2 verification after a Work Item Runner returns

**Preconditions**:

- A Work Item Runner has returned after completing its item
- The main working tree may or may not have been modified by the agent

**Steps**:

1. Portfolio Orchestrator runs the post-agent verification check (Protocol 90 Step 5.2)
2. The check finds that the main working tree is on a branch other than the integration branch (e.g., `implementation-plan/173-markdown-lint-plan-spec-docs` instead of `develop`)
3. The check also verifies whether the main working tree is clean (no uncommitted modifications)

**Postconditions**:

- If the main tree is on the wrong branch **and is clean**: the orchestrator automatically switches it back to the integration branch (`git switch develop`) and logs the correction
- If the main tree is on the wrong branch **and has uncommitted modifications**: the orchestrator stops, reports all modified files to the human, and does not dispatch additional agents until resolved
- If the main tree is on the correct branch and clean: orchestrator proceeds normally

**Information shown**:

- Orchestrator logs: `"Main working tree was on '<wrong-branch>' — auto-corrected to 'develop'. This indicates a guardrail violation by the preceding agent. See retrospective notes."`
- If dirty: orchestrator logs the full `git status --porcelain` output and the item ID of the preceding agent

**Actions available**:

- Orchestrator dispatches the next Work Item Runner after successful auto-correction
- Orchestrator stops and awaits human input when dirty modifications are found

**Considerations**:

- Auto-correction is only safe when the working tree is clean — no risk of losing uncommitted work
- The auto-correction should be logged as a guardrail violation in the batch retrospective notes
- The original incident (batch 8) was on a clean tree, making auto-correction the correct recovery path

---

### Use Case 3: Pre-tool-use hook warns before a prohibited git command executes

**Actor**: Pre-tool-use hook or agent harness checking tool calls at execution time

**Preconditions**:

- An agent session has a configured pre-tool-use hook (Claude Code hooks or equivalent)
- The agent is executing inside an isolated worktree session
- The agent is about to issue a `Bash` tool call containing `git switch`, `git checkout`, `git reset`, or `git restore`

**Steps**:

1. The hook intercepts the tool call before execution
2. The hook checks whether the command's working directory is the main repo root (not a worktree path)
3. If the command is state-changing and targets the main repo root, the hook emits a warning

**Postconditions**:

- The agent sees the warning text before the command executes (non-blocking: the hook warns rather than blocks, to avoid disrupting legitimate use)
- The warning includes the command text and the expected worktree path derived from the agent's session context

**Information shown**:

- Warning: `"[GUARDRAIL] git state-changing command detected at main repo root. Use 'git -C <worktree-path>' or 'cd <worktree-path> &&' prefix. Command: <command>"`

**Actions available**:

- Agent revises the command to target the worktree
- Agent proceeds if it has confirmed the command is intentionally targeting the main repo root for a read-only reason (hook does not block)

**Considerations**:

- This use case is optional; the core guardrail is the protocol wording (Use Case 1) and the post-agent verification (Use Case 2)
- The hook guidance should be documented as optional in the spec and plan; implementation is only required if the platform supports pre-tool-use hooks

---

## Business Rules

- **BR-1**: All git state-changing commands (`switch`, `checkout`, `checkout -b`, `reset`, `restore`) issued by a Work Item Runner operating in a worktree must target the worktree path, not the main repo root. This rule is mandatory when `BATCH_CONTEXT=true`.
- **BR-2**: The Portfolio Orchestrator must verify the main working tree branch after each Work Item Runner returns in a parallel batch (Protocol 90 Step 5.2). This check already exists but currently only warns — it must also auto-correct when the tree is clean.
- **BR-3**: Auto-correction (switching back to the integration branch) is permitted only when `git status --porcelain` returns empty output. When uncommitted modifications exist, the orchestrator must stop and escalate to the human.
- **BR-4**: The handoff prompt template in Protocol 91 Step 4 must include an explicit "Critical: Worktree Git Discipline" section. This section must enumerate the prohibited commands and provide the correct alternatives (`git -C <worktree-path>` or `cd <worktree-path> &&`).
- **BR-5**: Read-only git commands against the main repo root are always permitted (e.g., `git -C <main-repo-root> rev-parse --abbrev-ref HEAD`). The guardrail applies only to state-changing commands.
- **BR-6**: Auto-correction events must be recorded in the batch retrospective notes as a guardrail violation.
- **BR-7**: The scope of this guardrail is git branch-switching commands only. File write paths outside the worktree are out of scope (tracked separately in issue #193).

---

## Acceptance Criteria

- [ ] Protocol 91 Step 3 (Worktree Isolation) and/or Step 4 (Execute and Re-evaluate) contain an explicit, clearly marked guardrail section that: (a) lists `git switch`, `git checkout`, `git checkout -b`, `git reset`, and `git restore` as prohibited commands when run against the main repo root; (b) provides the correct alternative patterns (`git -C <worktree-path>` or `cd <worktree-path> &&`); (c) states the rule applies when `BATCH_CONTEXT=true`.
- [ ] Protocol 90 Step 5.2 is updated so that when the main working tree is found on the wrong branch and has no uncommitted modifications, the orchestrator automatically runs `git switch <integration-branch>` (or equivalent) to restore the correct branch, logs the correction, and proceeds — rather than only printing a warning.
- [ ] Protocol 90 Step 5.2 still halts and escalates to the human (does not auto-correct) when the main working tree has uncommitted modifications, and the escalation message includes the full `git status --porcelain` output.
- [ ] The `.claude/agents/item-orchestrator.md` system prompt (or an equivalent handoff note referenced by it) includes a brief reminder that all git state-changing commands must target the worktree path, not the main repo root.
- [ ] (Optional — this criterion does not block the PR) A guidance note is added in either Protocol 91 or a new integration doc describing how a pre-tool-use hook can warn when a state-changing git command is issued from the main repo root; implementation is declared optional and hook-platform-specific.
- [ ] No changes are made to `post-merge-cleanup.sh`, `pr-review-loop.sh`, Protocol 90 Step 3 (in scope for #199), or the `Write` path rule (in scope for #193).

---

## Out of Scope (MVP)

<!-- markdown-heuristic-disable COUNT001 -->
- File write paths outside the worktree (tracked in issue #193)
- Protocol 90 Step 3 changes (already addressed by issue #199, recently merged)
- Changes to `post-merge-cleanup.sh` or `pr-review-loop.sh`
- Changes to the Step 7a internal review gate (#185's scope)
- Enforcing the hook at the harness level (blocking tool-call denial) — the hook is advisory/warning only
- Auto-correcting dirty main working trees (always escalate to human in that case)
- Retroactive replay or correction of any past batch runs

---

## Open Questions

<!-- All questions resolved at handoff; no open questions remain. -->
