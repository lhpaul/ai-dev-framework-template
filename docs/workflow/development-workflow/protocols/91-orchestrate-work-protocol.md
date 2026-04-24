# Protocol: Run One Workflow Item

**Agent role**: Work Item Runner (`item-orchestrator`)
**Purpose**: Advance one workflow item, execute the next deterministic action, and keep that item moving until it reaches a real terminal condition

This is a **supporting protocol**. The Work Item Runner does not own a workflow stage, but it coordinates the stage-specific protocols for one development item at a time.

The portfolio-wide launcher is defined separately in `90-batch-orchestrate-work-protocol.md` as the **Portfolio Orchestrator** (`orchestrator`).

This protocol may be entered in either of two ways:

- A human invokes the Work Item Runner directly for one specific work item, branch, development folder, or PR
- The Portfolio Orchestrator dispatches the Work Item Runner after scanning the broader portfolio

---

## Overview

The Work Item Runner:
1. Resolves the request to exactly one workflow item
2. Determines the next deterministic action for that item
3. Executes creator, review-gate, PR, CI, and automated-review work as one continuous control loop
4. Stops only when the item is truly waiting on a human, blocked, or escalated

### Persistent orchestration contract

A single Work Item Runner run should keep advancing the selected item until it reaches one of these **terminal conditions**:

- A PR is clean and waiting for human review / merge
- A human product or architecture decision is required
- The automated review loop or CI loop escalated after retry / timeout limits
- The item is blocked by an unmet dependency
- The request cannot be resolved to exactly one workflow item

These are **not** terminal conditions and must not stop the run:

- A creator stage finished drafting its output
- A reviewer found fixable PR feedback
- A branch was pushed and still needs a PR opened
- A PR is open but still waiting for CI or automated review to finish
- Automated review found blocking PR feedback that the matching fixer agent can address

---

## Step 1: Resolve the Target Item

When an issue tracker is configured in `.ai-dev-workflow.yaml`, **always query the tracker first** to get the item's current status before relying on VCS state. If the tracker is unavailable (API unreachable, no MCP server), **you MUST immediately warn the human** that status is being inferred from VCS and may be stale — do not silently proceed.

Prefer the helper scripts in `scripts/development-workflow/` for deterministic state inspection before falling back to ad hoc shell commands.

### Parallel batch indicator

**Check for a parallel batch context**: If this Work Item Runner was dispatched as part of a parallel batch by the Portfolio Orchestrator (`90-batch-orchestrate-work-protocol.md`), the handoff metadata will indicate `BATCH_CONTEXT=true`. Note this indicator; you will use it in Step 3 (Dispatch Strategy) to decide whether worktree isolation is required.

**CHANGELOG in parallel batches**: Each item in a parallel batch adds its own CHANGELOG entry as normal. CHANGELOG merge conflicts are resolved at merge time by the batch-merge auto-resolution (protocol 94 Step 4.3). Do not skip or consolidate CHANGELOG entries — see protocol 90 Step 3.6 for rationale.

Resolve the request to exactly one of the following:

1. **Backlog / tracker work item** — use when a human explicitly requests a not-yet-started item
2. **Development folder** — `docs/specs/developments/<timestamp>_<slug>`
3. **Workflow branch** — `spec/*`, `implementation-plan/*`, `feature/*`, `refactor/*`, `fix/*`, `hotfix/*`
4. **Open PR**

Use these helpers while resolving and resuming work:

```bash
./scripts/development-workflow/workflow-next-action.sh --development <path>
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
```

If the request is portfolio-wide or refers to multiple items, stop using this protocol and switch to `90-batch-orchestrate-work-protocol.md`.

Important for `development folder` targets:

- `workflow-next-action.sh --development` is only reliable once the item is already `Spec Ready`, `Plan Ready`, or `In Development`.
- The script uses a VCS-level merged-PR check to distinguish `Plan Ready` (not yet started) from `Done` (branch merged and cleaned up). This is tracker-agnostic and requires only `gh`.
- The script **cannot** distinguish `Spec in Review` / `Plan in Review` from the corresponding merged state. If the target may still be waiting on a spec or plan PR merge, confirm the state via the issue tracker or by inspecting the workflow branch / PR directly before advancing.
- If `NEXT_ACTION=skip` is returned, the item is already done — do not redispatch.

When dispatching a subagent for this item, include a short "Tracker Work Item Summary" in the handoff:

- What the work item is asking for
- Any scope changes / decisions in recent comments
- Any ambiguity or conflict that still requires human confirmation

---

## Step 2: Determine the Next Deterministic Action

### What can advance now?

| Current state / detection | Can advance if... | Next action |
|---|---|---|
| Backlog (Feature) | Human has requested this specific item | Set tracker status to **Writing Spec**, then run `01-generate-spec-protocol.md` |
| Backlog (Refactor) | Human has requested this specific item as a Refactor | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md` (skip spec) |
| Writing Spec | Tracker **Writing Spec** — spec PR not yet human-ready | Continue spec branch/PR work (generate, internal review, reviewer tools, CI) until tracker moves to **Spec in Review** |
| Spec in Review | Tracker **Spec in Review** — spec PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Spec branch pushed, no PR yet | Branch exists on local / remote / worktree | Run the spec review gate via `REVIEW.md` / `01-review-spec-protocol.md`, open the PR, then finish PR readiness |
| Spec Ready | Spec PR is merged | Set tracker status to **Writing Plan**, then run `02-generate-implementation-plan-protocol.md` |
| Writing Plan | Tracker **Writing Plan** — plan PR not yet human-ready | Continue plan branch/PR work until tracker moves to **Plan in Review** |
| Plan in Review | Tracker **Plan in Review** — plan PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Plan branch pushed, no PR yet | Branch exists on local / remote / worktree | Run the plan review gate via `REVIEW.md` / `02-review-implementation-plan-protocol.md`, open the PR, then finish PR readiness |
| Plan Ready | Plan PR is merged | Set tracker status to **In Development**, then run `03-implement-development-protocol.md` |
| In Development | Tracker **In Development** — feature/fix PR not yet human-ready | Continue implementation branch/PR work (Step 7a, 7, 8) until tracker moves to **Development in Review** |
| Development in Review | Tracker **Development in Review** — feature/fix PR ready for humans | Wait — human review / merge (unless addressing `needs-fixes`) |
| Dev branch pushed, no PR yet | Branch exists on local / remote / worktree | Open draft PR, run the internal review gate (Step 7a), run `gh pr ready` to convert to non-draft, then run automated reviewer loop (Step 7) and CI loop (Step 8) |
| Draft PR open, internal review pending | PR is draft and the relevant internal review gate has not run yet or has open findings | Run the stage-specific internal review gate (Step 7a); apply fixes, push, repeat until clean. Once APPROVED, run `gh pr ready` to convert to non-draft |
| Non-draft PR open, no readiness label, external review not yet run | PR is non-draft (converted after Step 7a APPROVED), external review not yet run | Run Step 7 (external automated reviewers) and Step 8 (CI) |
| PR open (non-draft), no readiness label | PR exists and latest push has not fully cleared | Run Step 7 and Step 8 until clean or escalated |
| PR labeled `needs-fixes` | Human or automated systems requested changes | Address feedback, push, then run Step 7a, Step 7, and Step 8 |
| PR labeled `ready-for-human-review` | — | Wait — human review / merge required |

### Pre-dispatch tracker status update (single-item path)

When the Work Item Runner is invoked **directly** (not via Protocol 90) and the item's tracker status is stale — for example, a Refactor item is still `Backlog` even though the plan is merged and implementation is about to start — the runner must update the tracker status **before** dispatching the creator agent. Use the same transition table as Protocol 90 Step 2.5:

| Next action to dispatch | Tracker status to set |
|---|---|
| Write Spec | `Writing Spec` |
| Write Plan | `Writing Plan` |
| Implement (feature/fix/refactor/hotfix branch) | `In Development` |
| Resume in-progress stage (status already `Writing Spec`, `Writing Plan`, or `In Development`) | No change — skip |

This mirrors what Protocol 90 does at the portfolio level in Step 2.5 and ensures the tracker reflects the correct in-flight state regardless of whether the item was dispatched by the Portfolio Orchestrator or invoked directly by a human.

If the tracker is unavailable, log a warning and proceed — do not block advancement.

### Pre-dispatch branch check

Before dispatching any creator-stage agent, run all three checks below. An existing branch or active worktree means work already exists and should be resumed rather than restarted.

```bash
git branch -r | grep "<branch-prefix>/<slug>"
git branch | grep "<branch-prefix>/<slug>"
git worktree list | grep "<branch-prefix>/<slug>"
```

| Stage about to dispatch | Branch / worktree to check for |
|---|---|
| Write spec | `spec/[slug]` |
| Write plan | `implementation-plan/[slug]` |
| Implement (Feature) | `feature/[slug]` |
| Implement (Refactor) | `refactor/[slug]` |

If any check returns a match: **do not re-dispatch**. Resume from the existing branch or PR with `workflow-next-action.sh`.

### Dependency check

Before advancing the item, check its spec's `Depends on` field. If any dependency is not yet `Merged` or `Released`, stop and report the blocked state to the human.

---

## Step 3: Dispatch Strategy

Use the matching workflow agent / skill for the next stage when your runner supports handoff. Otherwise continue in the current session by following the referenced stage protocol directly.

**Subagent assignment by stage:**

| Stage action | Preferred execution path |
|---|---|
| Write spec | `product-manager` |
| Review spec | Native review against `REVIEW.md` or the compatibility wrapper `01-review-spec-protocol.md` |
| Write plan | `tech-lead` |
| Review plan | Native review against `REVIEW.md` or the compatibility wrapper `02-review-implementation-plan-protocol.md` |
| Implement feature | `developer` |
| Review code (post-draft-PR) | `code-reviewer` agent (Claude Code: `/code-review`); for other runners use compatibility wrapper `03-review-implementation-protocol.md` |

### Worktree isolation for parallel batches

**When dispatched as part of a parallel batch** (`BATCH_CONTEXT=true` in the handoff metadata):

1. **Create a dedicated worktree** for this item before executing any stage work. This ensures complete isolation from other concurrent Work Item Runners in the batch.

2. Determine the appropriate base branch for the worktree:

| Item type | Base branch |
|-----------|------------|
| Feature (`feature/`) | `origin/develop` |
| Refactor (`refactor/`) | `origin/develop` |
| Fast Track fix (`fix/`) | `origin/develop` |
| Hotfix (`hotfix/`) | `origin/main` |
| Spec (`spec/`) | `origin/develop` |
| Plan (`implementation-plan/`) | `origin/develop` |

**Note:** Use `origin/<base>` (remote tracking) rather than local `<base>` to avoid git worktree conflicts if the local base branch is already checked out elsewhere.

3. Create the worktree. The command depends on whether the item's branch already exists:

```bash
# Fetch latest remote refs first
git fetch origin

# Case A: New item — branch does not exist yet
git worktree add <worktree-path> -b <branch-prefix>/<slug> origin/<base-branch>

# Case B: Resuming item — branch exists locally
git worktree add <worktree-path> <branch-prefix>/<slug>

# Case C: Resuming item — branch exists only on remote
git worktree add <worktree-path> -b <branch-prefix>/<slug> origin/<branch-prefix>/<slug>

cd <worktree-path>
```

Use the pre-dispatch branch check from Step 2 (`git branch --list`, `git branch -r --list`) to determine which case applies. Case B and C are common when resuming "In Development" items, PRs with `needs-fixes`, or any item with prior work.

**Critical: Worktree Git Discipline** (`BATCH_CONTEXT=true` only)

When operating inside a worktree, **never** run the following commands against the main repo root:

- `git switch <branch>`
- `git checkout <branch>`
- `git checkout -b <branch>`
- `git reset [--hard|--soft|--mixed] ...`
- `git restore ...`

These commands change the branch or modify files in the main working tree, breaking isolation for all concurrent agents and the human operator. Violating this rule leaves the main repo in a broken state (e.g., pointing at a feature branch) that blocks all subsequent agents and the human operator until manually corrected.

**Required alternatives:**

- Run all git operations scoped to the worktree: `cd <worktree-path> && git <command>`
- Or use the `-C` flag: `git -C <worktree-path> <command>`

Read-only inspection of the main repo is always permitted and must use `-C` without switching branches:

```bash
git -C <main-repo-root> rev-parse --abbrev-ref HEAD
```

**Optional — platform-specific: pre-tool-use hook guidance**

For runners that support pre-tool-use hooks (e.g., Claude Code), a non-blocking hook can be configured to warn when a prohibited git command is issued from the main repo root while a worktree is active. The hook should:

1. Intercept tool calls for `Bash` commands.
2. Check whether the command includes any of `switch`, `checkout`, `checkout -b`, `reset`, or `restore` as git subcommands.
3. Compare the working directory of the command against the main repo root path.
4. If the working directory matches the main repo root and the command is state-changing, emit a warning: `"GUARDRAIL WARNING: git state-changing command targeting main repo root detected while worktree is active. Use git -C <worktree-path> or cd <worktree-path> && git instead."`
5. The hook is **non-blocking** — it warns but does not abort the command. Blocking hooks can cause cascading failures when legitimate read-only commands are incorrectly matched.

This hook is advisory and not required for the guardrail to function. The Critical block above is the normative rule; this hook provides an additional safety signal for supported runners.

**Common worktree gotcha — `git rev-parse --show-toplevel` returns the worktree path, not the main repo root**

When an agent runs inside an isolated worktree (`.claude/worktrees/<branch>/`), `git rev-parse --show-toplevel` returns the *worktree* path rather than the main repo root. Any script or agent instruction that relies on this command to locate `node_modules/`, project-level config files, or other resources installed at the main repo root will construct wrong paths.

Use `git rev-parse --git-common-dir` instead — it always points to the `.git` directory of the *main* repo regardless of which worktree is active. Append `/..` to get the main repo root:

```bash
# Wrong — returns the worktree path when run inside an isolated worktree:
REPO_ROOT=$(git rev-parse --show-toplevel)

# Correct — always returns the main repo root, even from a worktree:
REPO_ROOT=$(git rev-parse --git-common-dir)/..
```

Apply this pattern whenever a stage agent, script, or implementation step needs to reference `node_modules/`, root-level config files, or any path that lives at the main repo root rather than in the worktree.

**Important — stage protocol compatibility**: When working inside a worktree created with this method, the stage protocol's initial branching steps (`git fetch origin`, `git checkout develop`, `git pull origin develop`, `git checkout -b ...`) are **already satisfied** by the worktree creation above. The stage agent should skip those steps and proceed directly to the implementation work. If the stage agent runs `git checkout develop` inside the worktree, it will fail because `develop` is already checked out in the main working tree and git prevents the same branch from being checked out in multiple worktrees simultaneously.

**Critical safety rule — never modify the main working tree's branch**: An agent running inside a worktree **must never** run `git checkout`, `git switch`, `git reset`, or any command that changes the checked-out branch of the **main working tree**. Violating this rule leaves the main repo in a broken state (e.g., pointing at a `worktree-agent-*` branch) that breaks subsequent operations for all other agents and for the human operator.

- All git operations must target **the current worktree only**. Never `cd` out of the worktree into the main repo root and then run branch-switching commands.
- If you need to read information from the main repo (e.g., inspect its current branch), use `git -C <main-repo-root> <command>` without switching branches, for example:

  ```bash
  git -C /path/to/main-repo rev-parse --abbrev-ref HEAD
  ```

- After the item reaches a terminal condition and **before** removing the worktree, verify the main working tree is still on the expected integration branch **and has no uncommitted modifications**. This check mirrors Protocol 90 Step 5.2 — use the same four-case handling described there. Resolve the expected branch from your workflow context (typically `develop` for this template, but use whatever `integration_branch` is configured for the repo):

  ```bash
  INTEGRATION_BRANCH="<integration-branch>"  # e.g., develop (or main in repos configured that way)
  MAIN_BRANCH=$(git -C <main-repo-root> rev-parse --abbrev-ref HEAD)
  MAIN_STATUS=$(git -C <main-repo-root> status --porcelain)

  if [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
    # Case 1: Wrong branch + clean — auto-correct and log guardrail violation
    echo "GUARDRAIL: main working tree was on '$MAIN_BRANCH' after this agent completed. Expected '$INTEGRATION_BRANCH'. Auto-correcting."
    echo "IMPORTANT: Record this as a guardrail violation in retrospective notes — the agent likely ran in the main tree instead of the worktree, or leaked a branch switch."
    git -C <main-repo-root> switch "$INTEGRATION_BRANCH"
    # Proceed normally after correction

  elif [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
    # Case 2: Wrong branch + dirty — halt and escalate
    echo "ERROR: main working tree is on '$MAIN_BRANCH' (expected '$INTEGRATION_BRANCH') AND has uncommitted modifications."
    echo "$MAIN_STATUS"
    echo "Do not proceed. The human must inspect, discard or commit these changes, and restore the main tree to '$INTEGRATION_BRANCH' before the next dispatch."
    exit 1

  elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
    # Case 3: Correct branch + clean — proceed normally
    :

  elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
    # Case 4: Correct branch + dirty — halt and escalate
    echo "WARNING: main working tree is on '$INTEGRATION_BRANCH' but has uncommitted modifications:"
    echo "$MAIN_STATUS"
    echo "Possible cause: a stage agent leaked file writes outside the worktree boundary."
    echo "Do NOT commit or discard these changes without human review. Do not dispatch additional agents."
    exit 1
  fi
  ```

  For Case 1, auto-correct is safe because the tree is clean — no uncommitted work is at risk. The guardrail violation must still be logged in retrospective notes because it indicates the isolation boundary was breached (the agent likely ran in the main tree rather than the worktree, or a stage protocol issued a branch-switching command that leaked into the main tree). For Cases 2 and 4, **stop and report to the human** — the human must inspect and resolve before the next batch dispatch.

**Critical safety rule — Write and Edit paths inside a worktree**: Every `Write` and
`Edit` tool call issued within an active worktree session **must** target a path under
`<worktree-path>/...`. Any path that does NOT begin with the resolved `<worktree-path>`
value is a main-repo path — treat it as a red flag and correct it before calling the tool.

- Before calling `Write` or `Edit`, mentally verify: "Does this absolute path start with
  `<worktree-path>/`?" If not, prepend `<worktree-path>/` to the relative portion of the
  path.
- The item-orchestrator must include the resolved literal value of `<worktree-path>` in
  every stage-agent handoff (not just the first), so each agent can validate paths against
  it independently.
- Paths under `<worktree-path>/.tmp/` are within the worktree boundary and are permitted.
- This rule applies only when `BATCH_CONTEXT=true` and a dedicated worktree exists; for
  non-batch runs, no reminder is injected.

**Optional: pre-tool-use hook for WORKTREE_ROOT validation**

A pre-tool-use hook can enforce the Write/Edit path rule automatically:

1. Set the `WORKTREE_ROOT` environment variable to the resolved worktree path when
   launching the agent session.
2. In the hook, intercept `Write` and `Edit` tool calls only.
3. If `WORKTREE_ROOT` is unset, skip the check (non-worktree session — no-op).
4. If the target path does not start with `$WORKTREE_ROOT`, emit:
   `"GUARDRAIL: Write/Edit target '<path>' is outside the designated worktree
   '<WORKTREE_ROOT>'. Correct the path before proceeding."`
5. The hook is **non-blocking** — it warns but does not prevent the tool call. This
   allows the agent to correct the path in subsequent calls and prevents cascading
   failures from false positives.
6. The hook must NOT intercept read-only tools (`Read`, `Glob`, `Grep`).

4. **Suggested worktree path**: `<repo-root>/.claude/worktrees/<item-id>/<branch-prefix>-<slug>` where `<item-id>` is the issue number, tracker ID, or slug.

5. After the item reaches a terminal condition, the cleanup script will remove the worktree:

```bash
# IMPORTANT: Change directory to the main repo root BEFORE deleting the worktree
cd <repo-root>
git worktree remove <worktree-path>
```

**Critical safety rule:** You **must** `cd` to the repository root or any other valid directory **before** executing `git worktree remove`. If the shell's current working directory (CWD) is inside the worktree being deleted, the directory will cease to exist immediately after `git worktree remove` completes. All subsequent bash commands will fail with "directory not found" errors, causing the orchestration to break and requiring manual intervention or agent re-delegation.

After removing the worktree, verify that the CWD is still valid by running a simple command like `pwd` before executing any further shell operations.

**When not in a parallel batch**: Worktree creation is optional but recommended for large development folders or long-running work. If not using a dedicated worktree, ensure the working directory is clean before proceeding.

**Permission-denial early exit (subagent runs only)**: If at any point during the run the harness responds with the known harness failure pattern — a message containing the phrase `"Permission to use"` AND a denied tool name (`Edit`, `Write`, or `Bash`) — the subagent must **immediately stop all further work** and return the following structured string to the Portfolio Orchestrator:

```
SUBAGENT_PERMISSION_DENIAL: [tool] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

The `<denied-target>` field identifies what was denied and must be populated as follows:

- **`Edit` or `Write` denial**: list every denied file path as a comma-separated list of repo-relative, normalized paths, sorted lexicographically, with no duplicates and no surrounding spaces (e.g., `.claude/agents/developer.md,.cursor/agents/developer.md`). When only one path was denied, write it without a trailing comma.
- **`Bash` denial**: use the denied command pattern as reported by the harness (e.g., `Bash(gh api:*)`). There is no file path to report for a Bash denial.

This field is mandatory in all cases so the orchestrator can identify and resolve the permission gap before retrying.

**No silent workarounds — this is an absolute rule**: When `Edit` or `Write` is denied for any path (including `.claude/agents/**`, `.cursor/agents/**`, or any other file), the subagent MUST NOT use any alternative mechanism to write the same content. The following substitutions are all explicitly prohibited:

- `Bash` with `echo`, `cat`, `tee`, `printf`, `>`, or any shell redirection
- Python subprocess (`python3 -c "open(...).write(...)"` or equivalent)
- `gh api --method PUT /repos/.../contents/...` (GitHub Contents API)
- Any other indirect write path

**Rationale**: These side-channel writes bypass the canonical `Edit`/`Write` tool pipeline, which means any pre-tool-use hooks (e.g., path validation, write tracking) do not fire. They also make it impossible for the Portfolio Orchestrator to detect that a permission gap exists and perform the correct inline fallback. Silent degradation to a workaround tool is a protocol violation that erodes the orchestrator's ability to track item state reliably.

Before exiting:
- Do **not** apply any PR labels.
- Do **not** commit any partial work.
- Do **not** update the tracker status.

The Portfolio Orchestrator will handle recovery via the inline fallback described in `90-batch-orchestrate-work-protocol.md` Step 4.1.

This protocol stays scoped to one item. It may call different stage agents over time, but it must not start scanning or dispatching unrelated items.

### CHANGELOG in parallel batches

See Protocol 90 Step 3.6 for the canonical CHANGELOG strategy in parallel batches. CHANGELOG merge conflicts are resolved at merge time by the batch-merge auto-resolution (Protocol 94 Step 4.3).

### Scope Boundary Rule for Dispatched Agents

When dispatching a stage agent (creator, reviewer, or fixer), include the following explicit instruction:

> **Critical scope rule**: This item is assigned only to [ISSUE_ID]. Modify **only** files directly related to this issue. If a finding or review comment requires changes outside this issue's scope (e.g., fixing issues in unrelated modules, applying a new pattern to the broader codebase, or addressing tech debt elsewhere), do **not** implement it. Instead:
> 1. Note it as a separate finding
> 2. Suggest opening a new issue if appropriate
> 3. Continue with in-scope work only
>
> This is critical in parallel batch orchestration where multiple agents work concurrently. Out-of-scope changes cause merge conflicts and waste review cycles.

This rule prevents agents from making changes that affect unrelated issues and causing downstream conflicts in batch runs.

---

## Step 3.5: Pre-flight Permission Self-Check (Subagent Runs Only)

**Applies to**: Work Item Runner subagents dispatched as part of a parallel batch (`BATCH_CONTEXT=true`). This step is **optional but recommended** — the permission-denial early-exit in Step 3 (above) covers mid-run failures even without the self-check.

Before calling any creator-stage agent or making any file edits, perform a lightweight sanity check to verify that both `Edit` and `Bash` are accessible:

1. **Test `Edit`**: Use the `Edit` tool to create `.tmp/permission-preflight.tmp` with a single comment line (`# preflight-check`). This is the primary check — the Batch 5 incident (#160) was specifically about `Edit` being denied while `Bash` remained available.
2. **Test `Bash`**: Use `Bash` to delete the temp file:

   ```bash
   rm -f .tmp/permission-preflight.tmp
   ```

If either tool call is denied (harness responds with a permission-denied message), exit immediately before any creator-stage work:

```
SUBAGENT_PERMISSION_DENIAL: [DENIED_TOOL] tool denied on <denied-target>. No partial work committed. Falling back to orchestrator inline execution.
```

**Self-check rules**:
- Always target `.tmp/` for the self-check write (this path is gitignored).
- Clean up the temp file after the check regardless of outcome.
- Never touch tracked files during the self-check.
- After the write, run a quick sanity check to ensure no tracked file was accidentally modified:

  ```bash
  git status --porcelain
  ```

  If the output is non-empty, clean up the `.tmp/permission-preflight.tmp` artifact, emit a distinct error (`SELF_CHECK_DIRTY_WORKTREE: unexpected tracked file modifications detected — see git status output above`), and abort for human inspection. Do **not** emit `SUBAGENT_PERMISSION_DENIAL:` for this case.

If the self-check succeeds, proceed normally to the creator-stage work.

---

## Step 4: Execute and Re-evaluate

Run the next deterministic action for the selected item, then immediately re-evaluate the item state.

Expected chain:

`creator -> draft PR opened -> internal review gate with all internal reviewers (Step 7a) -> gh pr ready -> automated reviewer loop (Step 7) -> regression label (Step 7b, implementation PRs only) -> CI loop (Step 8) -> label readiness checklist (Step 8a) -> tracker status update (Step 8b) -> independent PR verification (Step 8c) -> wait or escalation`

After any subagent finishes, determine whether the item still has a deterministic next action:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch <branch>
./scripts/development-workflow/workflow-next-action.sh --pr <number>
./scripts/development-workflow/workflow-next-action.sh --development <path>
```

Do not stop after a single creator or reviewer stage if the next action is deterministic.

---

## Step 5: Resume Rules

When work already exists, resume rather than restart.

- If a development folder already maps to `Spec Ready`, `Plan Ready`, or `In Development`, continue from that state
- If a workflow branch already exists, use `workflow-next-action.sh --branch <branch>`
- If a PR already exists, use `workflow-next-action.sh --pr <number>`
- If labels indicate `needs-fixes`, enter the fix loop instead of reopening the stage from scratch

The Work Item Runner owns the full control loop for this item until it reaches a terminal condition.

---

## Step 6: Notify Humans

After the selected item reaches a terminal condition, provide a concise summary:

```markdown
## Work Item Runner Summary

- Item: [identifier]
- Final state: ready for human review / waiting on human decision / blocked / escalated
- Path taken: plan written -> reviewed -> PR opened -> automated review clean -> CI green
- Next human action: merge PR / answer architecture question / unblock dependency
```

**Retrospective suggestion (standalone runs only)**:

If this Work Item Runner was invoked **directly by a human** (i.e., `BATCH_CONTEXT` is not set or is `false`), do **not** suggest a retrospective immediately after the terminal condition summary. The work is not complete yet — the human still needs to review and merge the PR.

Instead, suggest the retrospective **after the human confirms the PR has been merged** (e.g., via `/post-merge-cleanup` or an explicit "it's merged" message). At that point, offer:

> Would you like to run a retrospective on this session's work?

If the human agrees, follow `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`. The retrospective will analyze the PRs from this item run using both GitHub data and the conversation context from this session.

**When `BATCH_CONTEXT=true`** (dispatched by the Portfolio Orchestrator): suppress the retrospective suggestion entirely. The Portfolio Orchestrator will suggest the retrospective after the full batch has been merged, not when PRs reach `ready-for-human-review`.

---

## Step 7a: Internal Review Gate (Draft PR)

Run this step immediately after opening a draft PR, and again after any push that addresses internal-review findings.

### Determining which reviewers to run

Read the `review.internal_reviewers` list from `.ai-dev-workflow.yaml`. If a `.tmp/template-config.json` file exists in the repository root (this path is gitignored and used for local developer overrides), read its `overrides.review.internal_reviewers` list — that value takes precedence over `.ai-dev-workflow.yaml` for the local environment. This allows developers without access to all configured review tools to run a subset (e.g., only `claude`) without changing the shared config.

Example `.tmp/template-config.json` override format:

```json
{
  "overrides": {
    "review": {
      "internal_reviewers": ["claude"]
    }
  }
}
```

If neither file defines `internal_reviewers`, fall back to running the stage-appropriate reviewer once (default behavior: `claude`).

When `.tmp/template-config.json` supplies an override, log the following before running the availability check:

> `INFO: Using internal_reviewers override from .tmp/template-config.json: [<override-list>]. Original list: [<yaml-list>].`

No warning comment is posted for reviewers intentionally removed by the override list (`override-excluded`). If any reviewer still present in the override list is unreachable at runtime, post the standard warning comment for those unreachable reviewers (the runtime-availability check still applies to the override list).

### Runtime-availability check

Before dispatching any reviewer, classify each entry in the resolved list as `reachable` or `unreachable` based on the runner's execution context. The check is deterministic and requires no external network call — runner identity is a sufficient proxy for reviewer reachability (see [codex-reviewer-runtime-fallback spec](../../../specs/developments/20260417203329_codex-reviewer-runtime-fallback/1_codex-reviewer-runtime-fallback_specs.md) — BR-1 and BR-8).

#### Reachability classification table

| Runner context | `claude` reachable? | `codex` reachable? |
|---|---|---|
| Claude Code (direct human session) | Yes | No |
| Claude Code subagent (dispatched by orchestrator) | Yes | No |
| Codex runner / Codex skill | Yes | Yes |
| Direct human (shell / CI with both CLIs available) | Yes | Yes |

#### Policy resolution

After classifying each reviewer, apply the configured policy. Read `internal_reviewers_unavailable_policy` from `.ai-dev-workflow.yaml` (or its local override in `.tmp/template-config.json`). If the key is absent, the default is `warn`.

To override the policy locally without changing shared config, use `.tmp/template-config.json`:

```json
{
  "overrides": {
    "review": {
      "internal_reviewers": ["claude"],
      "internal_reviewers_unavailable_policy": "warn"
    }
  }
}
```

Allowed values: `warn` (default), `fail-if-any-unavailable`.

| Condition | Policy | Action |
|---|---|---|
| Zero reviewers reachable | Any | **Hard-fail** — post the Step 7a summary comment (as error/blocked comment per Use Case 2) and stop. Do NOT call `gh pr ready`. Escalate to human. |
| One or more reviewers unreachable, at least one reachable | `warn` (default) | Post a warning comment to the PR naming each unreachable reviewer and the runner context, record each as `skipped (unreachable)`, then proceed with the reachable subset. |
| Any reviewer unreachable | `fail-if-any-unavailable` | **Hard-fail** — same outcome as zero-reachable (no reviewers dispatched, PR stays draft, escalate to human) even when some reviewers are reachable. Post the Step 7a summary comment using the hard-fail comment format **Case B** below and stop. Do NOT call `gh pr ready`. Escalate to human. |
| All reviewers reachable | Any | Proceed normally — no warning comment, no deviation from the existing flow. |

#### Warning comment format (one or more unreachable, `warn` policy)

Post via `gh pr comment` before dispatching any reviewer. Use the following wording for each unreachable reviewer:

> `WARNING: internal_reviewer '<reviewer>' unreachable from current runner (<runner-context>) — skipping. Only '<reachable-list>' will run in this Step 7a cycle. Reviewer coverage is reduced from <total> to <reachable-count>.`

Example for `codex` unreachable from a Claude Code subagent with `internal_reviewers: [claude, codex]`:

> `WARNING: internal_reviewer 'codex' unreachable from current runner (Claude Code subagent) — skipping. Only 'claude' will run in this Step 7a cycle. Reviewer coverage is reduced from 2 to 1.`

#### Hard-fail comment format

Post via `gh pr comment`. This comment doubles as the BR-7 mandatory Step 7a summary comment in the hard-fail case. Use the appropriate template based on the hard-fail condition:

**Case A — Zero reviewers reachable (any policy):**

> `Step 7a BLOCKED: no internal reviewer is reachable from the current runner. Effective reviewer set: none. Reachable: []. Unreachable: [<reviewer> (unreachable), ...]. Verdict: hard-fail. To unblock: run Step 7a from a runner that supports all configured reviewers, or temporarily override 'review.internal_reviewers' via .tmp/template-config.json.`

**Case B — `fail-if-any-unavailable` policy triggered (one or more reviewers unreachable, but at least one was reachable):**

> `Step 7a BLOCKED: policy 'fail-if-any-unavailable' triggered — one or more internal reviewers are unreachable. No reviewers were dispatched. Effective reviewer set: none (policy block). Reachable: [<reachable-list>]. Unreachable: [<reviewer> (unreachable), ...]. Verdict: hard-fail. To unblock: run Step 7a from a runner where all configured reviewers are reachable, or set internal_reviewers_unavailable_policy to 'warn' temporarily, or override 'review.internal_reviewers' via .tmp/template-config.json.`

### Reviewer dispatch map

For each reviewer in the resolved list, dispatch the stage-appropriate agent:

| Reviewer | PR branch prefix | Agent / protocol to dispatch |
|---|---|---|
| `claude` | `spec/*` | `spec-reviewer` or `01-review-spec-protocol.md` |
| `claude` | `implementation-plan/*` | `implementation-plan-reviewer` or `02-review-implementation-plan-protocol.md` |
| `claude` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `code-reviewer` or `03-review-implementation-protocol.md` |
| `codex` | `spec/*` | `workflow-spec-reviewer` Codex skill against `REVIEW.md` |
| `codex` | `implementation-plan/*` | `workflow-plan-reviewer` Codex skill against `REVIEW.md` |
| `codex` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `workflow-code-reviewer` Codex skill against `REVIEW.md` |

### Multi-reviewer execution rules

Run all configured internal reviewers **sequentially** in the order listed. Each reviewer runs against `REVIEW.md`, applies deterministic fixes directly, and commits + pushes if needed.

Initialize `internal_review_cycle = 0` at the start of Step 7a. Increment each time the full reviewer list is restarted. Escalate to human when `internal_review_cycle` reaches `max_internal_review_cycles` (default: 5).

| Outcome | Action |
|---|---|
| All reviewers `APPROVED` | Post the Step 7a summary comment (see below), then run `gh pr ready <pr_number>` to convert the draft PR to non-draft, then continue to Step 7 (external automated reviewers) |
| Any reviewer returns `NEEDS REVISION` (fixable) and `internal_review_cycle < max_internal_review_cycles` | Fixes already applied by the agent; increment `internal_review_cycle`; re-run **all** internal reviewers from the beginning of the list |
| Any reviewer returns `NEEDS REVISION` (fixable) and `internal_review_cycle >= max_internal_review_cycles` | Post the Step 7a summary comment with verdict `escalated — max cycles reached`, then escalate to human |
| Any reviewer returns `NEEDS REVISION` (product/design decision) | Post the Step 7a summary comment with verdict `escalated — human decision required`, then stop and escalate to human before proceeding |

All internal reviewers must APPROVE before `gh pr ready` is called. If any reviewer finds issues, fix them and re-run ALL internal reviewers.

#### Step 7a summary comment (mandatory)

A Step 7a summary comment **must always be posted to the PR** when the gate exits — whether all reviewers ran, some were skipped, or the gate hard-failed (BR-7). Post via `gh pr comment` immediately before `gh pr ready` (in the success path) or immediately before stopping (in the hard-fail or escalation paths).

Required fields:

- **Effective reviewer set**: which reviewers actually ran (excluding skipped/unreachable ones)
- **Skipped reviewers**: each reviewer skipped, with reason (e.g., `unreachable`, `override-excluded`)
- **Final verdict**: `APPROVED`, `hard-fail`, or `escalated — <reason>`

Example format:

```markdown
### Step 7a Internal Review Gate Summary

**Effective reviewer set**: claude
**Skipped reviewers**: codex (unreachable from Claude Code subagent)
**Verdict**: APPROVED

All reachable internal reviewers approved. Note: codex was unreachable from the current runner — reviewer coverage was reduced from 2 to 1. Human reviewers may re-run Step 7a from a Codex-capable runner if full coverage is required.
```

In the hard-fail case (zero reachable reviewers or `fail-if-any-unavailable` policy triggered), the hard-fail comment posted in the Runtime-availability check section above **already satisfies BR-7** — do not post a second summary comment.

**Note**: The Step 7a summary comment is a distinct requirement from the Step 7 "Automated Reviewer Loop Summary" comment checked in Step 8c. The Step 7a summary covers the internal gate only; Step 8c's check targets the external automated reviewer loop (Step 7). These are separate comments and neither substitutes for the other.

### Step 7a loop parameters

| Parameter | Default | Description |
|---|---|---|
| `max_internal_review_cycles` | 5 | Max times the full internal reviewer list is restarted before escalating |

Step 7a runs **before** Step 7 (external reviewers). Only proceed to Step 7 once all internal reviewers in Step 7a produce `APPROVED`. After any fixer push triggered by Step 7 (external reviewers), re-run Step 7a (all internal reviewers) to ensure the stage-specific internal review gate is still clean.

---

## Step 7: Automated Reviewer Loop

If one or more automated code review platforms are configured (see [`integrations/pr-review-platform.md`](../integrations/pr-review-platform.md)), run this loop after **any push to a PR branch**. If no review platform is configured, skip this step and report `⏭️ skipped` in the Step 6 summary.

**Standalone use:** This step (and Step 8) can be run for a single PR without full orchestration — see [`93-automated-reviewer-loop-protocol.md`](93-automated-reviewer-loop-protocol.md) and the `/run-reviewer-loop` command (Cursor) or `automated-reviewer-loop` agent (Claude Code) or `workflow-reviewer-loop` skill (Codex).

**Important:** Run Step 7 **to completion** and use its result before running Step 8. Do not run Step 7 in the background while proceeding to Step 8. The review loop can take several minutes (poll interval × wait for bot). Only when the script exits with `clean` or `skipped` may you continue to Step 8.

The helper script evaluates configured platforms sequentially. For each platform it checks for **existing** blocking findings from the bot (e.g. from a review that already ran on PR open) before posting a new trigger. If it finds any, it exits with `needs_fixes` without moving on to later platforms — so the fixer addresses them first; after a push, the next run starts again from the first configured platform.

Initialize `cycle = 0` once per orchestration run for the PR. Increment `cycle` each time a fixer agent is dispatched. Do not reset `cycle` after a fixer push; escalate when the run reaches `max_cycles`.

### PR feedback tracking and comments

Maintain a **PR feedback ledger** alongside the cycle counter. Each entry tracks:

| Field | Description |
|---|---|
| `id` | Sequential integer assigned in discovery order |
| `platform` | Review platform name (e.g. `greptile`, `devin`) |
| `path` | File path |
| `line` | Line number (display-only — can shift between commits) |
| `body_snippet` | First 120 chars of the finding body (used as matching key — line-shift-safe) |
| `discovered_cycle` | Cycle when first seen |
| `status` | `open` · `resolved` · `unresolved` |
| `resolved_commit` | Short SHA (set when resolved) |

**Matching key**: `(platform, path, body_snippet)` — not line number, since lines shift after fixes. If a finding looks like a restatement of existing open PR feedback (same platform, same file, similar description), match it rather than creating a duplicate.

**Ledger updates:**

- After each review run with `needs_fixes`: parse `BLOCKING_N_*` output, add new entries or leave existing open ones unchanged.
- After each fixer push + re-review: any open entry whose key no longer appears in the new output is marked `resolved` with the fixer's commit SHA.
- When the loop terminates: any still-open entry is marked `unresolved`.

#### Fix commit comment

Post via `gh pr comment` immediately after updating the ledger following a fixer push:

````markdown
### Automated Fix: commit `<short_sha>`

Addressed **N** finding(s) from cycle M:

| # | Platform | File | Description |
|---|----------|------|-------------|
| 1 | greptile | `src/foo.ts:42` | First 80 chars of body... |

<details><summary>Remaining open findings: K</summary>

| # | Platform | File | Description |
|---|----------|------|-------------|
| 3 | greptile | `src/baz.ts:5` | First 80 chars of body... |

</details>
````

If 0 findings were resolved: post a shorter note — "Pushed fixes for cycle M. 0 findings resolved so far — re-running review to check."

#### Resolve inline review comments

After each fixer push, reply to each addressed inline review comment on the PR to mark it as resolved. Use `gh api` to post a reply to each comment whose ledger entry transitioned to `resolved`:

```bash
gh api "repos/{owner}/{repo}/pulls/<pr_number>/comments/<comment_id>/replies" \
  -f body="Fixed in commit \`<short_sha>\`."
```

This is **mandatory** — do not skip this step. Unresolved inline comments cause confusion when humans review the PR on GitHub, even if the underlying issue was already fixed. When delegating to a fixer subagent, include explicit instructions to reply to each addressed comment.

#### Final summary comment

Post via `gh pr comment` when the loop reaches a terminal condition (`clean`, `escalate`, or `max_cycles`):

````markdown
### Automated Reviewer Loop Summary

**Result:** clean | escalated (reason) | max cycles reached
**Cycles:** N / `max_cycles`
**Platforms:** greptile, devin

| # | Platform | File | Line | Description | Status | Resolved In |
|---|----------|------|------|-------------|--------|-------------|
| 1 | greptile | `src/foo.ts` | 42 | First 80 chars... | Resolved | `abc1234` |
| 2 | greptile | `src/baz.ts` | 5 | First 80 chars... | Unresolved | -- |

**Resolved:** 1 / 2 findings

**Reply-only resolutions (no code fix):** M thread(s) resolved via reply + resolveReviewThread mutation.

| Thread | Author | Concern summary | Rationale |
|--------|--------|-----------------|-----------|
| #1 | coderabbitai[bot] | First 60 chars of concern... | First 80 chars of reply rationale... |
````

When M=0 (all resolutions were code fixes), omit the "Reply-only resolutions" subsection entirely.

- If no findings were ever raised (clean on first run): post a simpler comment — "No blocking PR feedback was raised by any configured reviewer tool."
- If result is `skipped` (no platforms configured): do **not** post a summary comment.

Prefer the helper script (it reads `.ai-dev-workflow.yaml` for the platform list automatically):

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
```

Interpret the result as follows:

| Result | Action |
|---|---|
| `clean` | Continue to Step 7b (implementation PRs) then Step 8 |
| `skipped` | Continue to Step 7b (implementation PRs) then Step 8 |
| `needs_fixes` and `cycle < max_cycles` | Increment `cycle`, dispatch the matching fixer agent, wait for a push, then run Step 7 again |
| `needs_fixes` and `cycle >= max_cycles` | Escalate to human |
| `escalate` | Escalate to human |

### Blocking vs. suggestion classification

When an automated review platform returns inline comments, classify them before deciding whether the PR needs fixes.

- Treat a comment as a **soft suggestion** only when every non-empty, non-code line starts with an advisory prefix such as `Consider`, `You might`, `An alternative`, `Optionally`, `It could be cleaner to`, `Perhaps`, `Maybe`, `You could`, `One option is`, or `Alternatively`.
- Treat any other inline comment as **blocking**.
- Treat `CHANGES_REQUESTED` reviews from any automated reviewer as **blocking**. Treat `COMMENTED` reviews from Devin as **blocking** when the body starts with `**Devin Review**` OR when the review is accompanied by unresolved inline PR review comments from `devin-ai-integration[bot]`; a `COMMENTED` Devin review is non-blocking only when neither condition holds. For other platforms, `COMMENTED` reviews are not automatically blocking. See `93-automated-reviewer-loop-protocol.md` for full Devin blocking classification rules.

Soft suggestions may be reported in summaries, but they do not change the loop result to `needs_fixes`. Any blocking finding does.

**Fixing agent by PR branch type:**

| PR branch prefix | Compatibility fixer to dispatch when direct fixes are needed |
|---|---|
| `spec/*` | `spec-reviewer` |
| `implementation-plan/*` | `implementation-plan-reviewer` |
| `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `code-reviewer` |

### Loop parameters

| Parameter | Value | Description |
|---|---|---|
| `poll_interval` | 2 min | Time to wait between review status checks |
| `max_wait` | 20 min | Max wait **per fix cycle** for the reviewer to respond |
| `max_cycles` | 10 | Max number of times a fixing agent is dispatched before escalating |

---

## Step 7b: Regression Label (Implementation PRs Only)

After Step 7 completes with result `clean` or `skipped`, and **before** entering Step 8, apply the `ready-for-regression` label on implementation PRs to trigger label-gated e2e/regression CI checks.

**Applies to**: PRs on branches `feature/*`, `fix/*`, `hotfix/*`, `refactor/*`
**Does not apply to**: PRs on branches `spec/*`, `implementation-plan/*`

```bash
# Only for implementation PRs:
gh pr edit <pr_number> --add-label "ready-for-regression"
```

This label triggers the `e2e-regression.yml` workflow (or project-specific equivalents). Step 8's CI loop (`pr-ci-loop.sh`) will then naturally pick up the e2e check as part of its green/red polling via `statusCheckRollup`.

The `gh pr edit --add-label` command is idempotent — applying a label that already exists is a no-op. When the label is already present from a previous cycle, the `synchronize` event from the latest push will have already re-triggered the workflow.

Skip this step entirely for spec and plan PRs.

See [`integrations/e2e-regression.md`](../integrations/e2e-regression.md) for the full integration guide, including downstream customization.

---

## Step 8: CI Loop

**Only after Step 7 (and Step 7b for implementation PRs) has completed**, wait for required checks to settle.

Prefer the helper script:

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

Interpret the result as follows:

| Result | Action |
|---|---|
| `green` | Proceed to Step 8a (label readiness checklist) → Step 8b (tracker status) → Step 8c (independent verification) |
| `red` | Apply `needs-fixes`, dispatch the matching fixer agent, wait for a push, then return to Step 7 |
| `timeout` | Escalate to human; do not apply `ready-for-human-review` |

---

## Step 8a: Label Readiness Checklist (Hard Gate)

**Before applying `ready-for-human-review`**, verify all required readiness conditions are met. This is a hard gate — do not skip or defer.

### Label derivation rule

Required labels are determined by the **branch prefix**, not by the content of the PR (e.g., whether it changes code vs. documentation). An agent must never infer labels from what was changed inside the PR.

| Branch prefix | Requires `ready-for-regression` |
|---|---|
| `feature/*` | Yes |
| `fix/*` | Yes |
| `refactor/*` | Yes |
| `hotfix/*` | Yes |
| `spec/*` | No |
| `implementation-plan/*` | No |

Any branch that does not match a recognized prefix is treated as non-implementation (i.e., `ready-for-regression` is NOT required), but this should be treated as a configuration anomaly and reported to the human.

Run this checklist for **every PR**:

```bash
PR_NUMBER=<pr_number>
BRANCH=<branch_name>  # e.g., feature/foo, spec/bar, fix/baz

# Determine PR type (implementation vs. spec/plan)
case "$BRANCH" in
  feature/*|fix/*|hotfix/*|refactor/*)
    IS_IMPLEMENTATION_PR=true
    ;;
  spec/*|implementation-plan/*)
    IS_IMPLEMENTATION_PR=false
    ;;
  *)
    IS_IMPLEMENTATION_PR=false
    echo "WARNING: Branch '$BRANCH' does not match a recognized prefix (feature/*, fix/*, refactor/*, hotfix/*, spec/*, implementation-plan/*). Treating as non-implementation PR. Report this anomaly to the human."
    ;;
esac

# Check 1: PR is non-draft
DRAFT=$(gh pr view "$PR_NUMBER" --json isDraft --jq '.isDraft')
if [ "$DRAFT" = "true" ]; then
  echo "ERROR: PR is still a draft. Run 'gh pr ready $PR_NUMBER' first."
  exit 1
fi

# Check 2: ready-for-regression label applied (implementation PRs only)
if [ "$IS_IMPLEMENTATION_PR" = "true" ]; then
  HAS_REGRESSION_LABEL=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-regression$" || true)
  if [ "$HAS_REGRESSION_LABEL" -eq 0 ]; then
    echo "ERROR: Implementation PR is missing 'ready-for-regression' label. Run Step 7b first."
    exit 1
  fi
fi

# Check 3: needs-fixes label — remove if present (stale at this point: CI is green and reviews are clean)
HAS_NEEDS_FIXES=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^needs-fixes$" || true)
if [ "$HAS_NEEDS_FIXES" -gt 0 ]; then
  echo "INFO: Removing stale 'needs-fixes' label (CI is green and reviews are clean)."
  gh pr edit "$PR_NUMBER" --remove-label "needs-fixes"
fi

# Check 4: ready-for-human-review label NOT yet applied (we are about to apply it)
HAS_HUMAN_REVIEW_LABEL=$(gh pr view "$PR_NUMBER" --json labels --jq '.labels[].name' | grep -c "^ready-for-human-review$" || true)
if [ "$HAS_HUMAN_REVIEW_LABEL" -gt 0 ]; then
  echo "INFO: PR already has 'ready-for-human-review' label. Skipping re-application."
else
  echo "Applying 'ready-for-human-review' label..."
  gh pr edit "$PR_NUMBER" --add-label "ready-for-human-review"
fi

echo "✅ Label readiness checklist passed. PR is ready for human review."
```

**Interpretation**:

- **All checks pass**: Continue to Step 8b (update tracker status) and then Step 8c (independent PR verification); only report the PR as ready after Step 8c also passes
- **Any check fails**: Stop and fix the condition. Do not apply `ready-for-human-review` until all checks pass
  - If `PR is still a draft`: Human error; run `gh pr ready <pr_number>` manually
  - If `missing ready-for-regression` on implementation PR: Re-run Step 7b, then re-check
  - If `needs-fixes` is present (Check 3): The label is stale at this point (CI is green and reviews are clean), so it is automatically removed before proceeding to apply `ready-for-human-review`

This checklist ensures the label sequence is always complete before the PR is declared ready for human review.

---

## Step 8b: Update Tracker Status

After the label readiness checklist passes, update the tracker status to reflect the PR is waiting for human review:

- For **spec PRs** (`spec/*`): set tracker status to `Spec in Review`
- For **plan PRs** (`implementation-plan/*`): set tracker status to `Plan in Review`
- For **implementation PRs** (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`): set tracker status to `Development in Review`

### Routing: CLI vs. MCP

How to perform the update depends on the configured `issue_tracker.provider` in `.ai-dev-workflow.yaml` and the execution context:

#### GitHub Projects (provider: `github_projects`) — use `gh` CLI

GitHub Projects status updates are fully supported via `gh` CLI and require no MCP server. Subagents in any execution context (including parallel batch runs) **must** use the CLI update pattern rather than MCP. Follow the "One-shot status update (recommended pattern)" section in [`docs/workflow/development-workflow/integrations/github-projects.md`](../integrations/github-projects.md) for the full commands and ID-resolution steps.

#### Other providers (Linear, Jira, etc.) — report and defer

For issue tracker providers that have no supported `gh`-equivalent CLI, MCP server access is required. Because MCP servers are not available in subagent execution contexts:

- **Subagents** must **not** attempt the tracker update directly. Instead, include the required transition in the summary returned to the orchestrator:

  ```
  TRACKER_UPDATE_REQUIRED: set issue #<N> status to "<target_status>"
  ```

- **The orchestrator** (or the human invoking the Work Item Runner directly) is responsible for performing the MCP-based status update after the subagent returns.

If neither the CLI path nor MCP is available, log a warning and continue — do not block labeling or PR readiness on a tracker update failure.

---

## Step 8c: Post-Label Independent Verification (Hard Gate)

After Steps 8a and 8b complete, perform one final independent verification of the actual PR state via `gh pr view` before reporting the PR as ready for human review. **Do not rely on prior step outputs or agent self-reports** — query GitHub directly.

```bash
gh pr view <pr_number> --json baseRefName,isDraft,labels,statusCheckRollup,comments
```

Verify all of the following. If any check fails, **do not report ready** — treat it the same as `needs-fixes` and re-enter the fix loop from Step 7a:

| Check | Pass condition |
|---|---|
| Base branch | `develop` for `feature/*`, `fix/*`, `refactor/*`; `main` for `hotfix/*`; `develop` for `spec/*`, `implementation-plan/*` |
| PR is non-draft | `isDraft: false` |
| `ready-for-human-review` label | Present in `labels[].name` |
| `ready-for-regression` label | Present in `labels[].name` for `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`; absent/ignored for `spec/*`, `implementation-plan/*` |
| No `needs-fixes` label | `needs-fixes` absent from `labels[].name` |
| All automated-reviewer `reviewThreads` resolved | GraphQL `reviewThreads.nodes[].isResolved=true` (or `✅ Addressed` in the first comment body) for every thread authored by a configured bot login. Evaluate via: `gh api graphql -f query='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{author{login}body}}}}}}}' -f owner=OWNER -f repo=REPO -F pr=NUMBER \| jq '.data.repository.pullRequest.reviewThreads.nodes[] \| select(.isResolved==false)'` — output must be empty for all bot-authored threads. Use cursor-based pagination for PRs with more than 100 threads. |
| Automated reviewer loop summary | At least one comment whose body contains `"Automated Reviewer Loop Summary"` or `"No blocking PR feedback"` (skip this check only when Step 7 was `skipped` because no review platforms are configured). **This is a hard requirement. Agents applying fixes MUST NOT remove or skip this check — the presence of the comment is the only reliable signal that Step 7 ran to completion. A PR that has `ready-for-human-review` but lacks this comment is in an incomplete state and must re-run Step 7.** (Note: the Step 7a summary comment posted by the internal review gate is a distinct comment from a distinct step — it does not satisfy this check. This check targets the external automated reviewer loop summary from Step 7 only.) |
| CI checks | All required status checks have `state: SUCCESS` or `conclusion: success` in `statusCheckRollup` (no check in `PENDING`, `FAILURE`, or `ERROR` state) |

If any check fails:

1. Log the specific failure(s) — include the PR number, failed check name, and observed value.
2. Apply `needs-fixes` if not already present: `gh pr edit <pr_number> --add-label "needs-fixes"`.
3. Remove `ready-for-human-review` if it was already applied: `gh pr edit <pr_number> --remove-label "ready-for-human-review"`.
4. Fix the root cause (wrong base branch, missing label, missing review comment, failing CI) and return to Step 7a.

Only after all checks pass should the Work Item Runner report the PR as terminal ("ready for human review").

---

## Step 9: Feedback Loop

When a human requests changes on a PR:

1. Remove `ready-for-human-review`
2. Add `needs-fixes`
3. Address the feedback
4. Push fixes
5. Run Step 7a (internal review gate) — all internal reviewers must approve before proceeding
6. Run Step 7 (external automated reviewers)
7. Run Step 7b (implementation PRs only)
8. Run Step 8 (CI loop)
9. Run Step 8a (label readiness checklist) — this is **mandatory** to verify the PR is non-draft, `ready-for-regression` is applied on implementation PRs, and `ready-for-human-review` is applied
10. Run Step 8b (update tracker status)
11. Run Step 8c (post-label independent verification) — query GitHub directly to confirm base branch, labels, review comment, and CI before reporting ready
12. Notify human that feedback has been addressed and the PR is ready again

See `92-pr-readiness-signal-protocol.md` for label definitions.

---

## Step 10: Post-Merge Status Transitions

When a human confirms that a PR has been merged, update the issue tracker and clean up local state according to this table:

| Merged PR branch type | Set tracker status to |
|---|---|
| `spec/*` | Spec Ready |
| `implementation-plan/*` | Plan Ready |
| `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` | Merged |

**Key rules:**

- When a spec or plan PR is merged, set the tracker status to the corresponding **Ready** status (`Spec Ready` or `Plan Ready`) — **not** `Merged`. Only implementation PRs (feature, fix, refactor, hotfix) go to `Merged`.
- The `/post-merge-cleanup` skill and `post-merge-cleanup` command follow this same table when updating tracker status.
- After updating the tracker, clean up local branches and worktrees associated with the merged PR:

```bash
git fetch origin
cd <repo-root>                          # CRITICAL: change to repo root before removing worktree (see Step 3)
git worktree remove <worktree-path>     # remove worktree first (branch is checked out there)
git branch -D <merged-branch>           # force-delete local branch (squash merges need -D)
```

If the item's tracker status is already in a further-advanced state (e.g., already `In Development` when a spec PR merges), do not roll it back — leave it as-is and only clean up local branches/worktrees.
