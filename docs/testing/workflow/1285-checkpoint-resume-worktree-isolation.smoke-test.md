# Smoke Test Runbook: Checkpoint Resume Worktree Isolation

**Feature**: Checkpoint Resume Worktree Isolation
**Spec**:
[1_1285-checkpoint-resume-worktree-isolation_specs.md](../../specs/developments/20260723110117_1285-checkpoint-resume-worktree-isolation/1_1285-checkpoint-resume-worktree-isolation_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for issue #1285 is checked out.
- [ ] `bash`, `git`, `jq`, `python3`, and `npx` are available.
- [ ] `node_modules` is installed so Markdown lint can run.
- [ ] Temporary repositories and worktrees can be created under the system
      temporary directory.
- [ ] No real tracker, PR, label, comment, review, or merge mutation is
      performed by the resume gate tests.

---

## Test Data

| Item | Value |
| --- | --- |
| Executable resume gate | `scripts/development-workflow/checkpoint-resume-gate.sh` |
| Worktree isolation helper | `scripts/development-workflow/worktree-resume-preflight.sh` |
| Gate integration test | `scripts/development-workflow/tests/test-checkpoint-resume-gate.sh` |
| Worktree helper unit test | `scripts/development-workflow/tests/test-worktree-resume-preflight.sh` |
| Canonical protocols | Protocols 90, 91, and 95 under `docs/workflow/development-workflow/protocols/` |
| Valid checkpoint states | `pending`, `satisfied`, `waived` |
| Isolation stop condition | `unclear_requirements` |
| Main clone branch | `develop` |

---

## Smoke Test Steps

### Step 1: Run the worktree preflight unit tests

**Maps to**: AC2, AC3, AC4, AC5, AC6, AC10

Run:

```bash
bash scripts/development-workflow/tests/test-worktree-resume-preflight.sh
```

**Expected result**: The test exits successfully and covers exact and
descendant worktree paths, main-clone and main-descendant stops, sibling and
same-prefix path rejection, exact branch matching, missing/detached/ambiguous
registrations, paths with spaces, failed worktree discovery, and complete
structured stop evidence.

### Step 2: Run the actual checkpoint-resume gate integration tests

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC7, AC9, AC10

Run:

```bash
bash scripts/development-workflow/tests/test-checkpoint-resume-gate.sh
```

**Expected result**: The test invokes the same executable gate required by the
resume protocols. Complete valid context with checkpoint state `satisfied` or
`waived` returns `continue`; `pending` returns `checkpoint_pending`; missing or
contradictory context returns `stop` with `unclear_requirements`.

### Step 3: Prove main-clone resume stops before mutation

**Maps to**: AC2, AC4, AC6, AC9

Use the integration-test fixture or reproduce its guarded-callback scenario:

1. Snapshot the main clone's current branch, `HEAD`, porcelain status, and a
   marker file.
2. Register the expected item branch in a separate worktree.
3. Start the gate process from the main clone with all required context and a
   satisfied checkpoint.
4. Arrange a simulated mutation command to run only when the gate exits
   successfully.
5. Compare the snapshots after the gate returns.

**Expected result**: The gate returns non-zero with `RESULT=stop`,
`ISOLATION_RESULT=stop`, and `STOP_CONDITION=unclear_requirements`. The
simulated mutation does not run; branch, `HEAD`, status, and marker evidence are
unchanged. No `cd`, branch switch, worktree creation, reset, restore, stash,
clean, commit, push, or repair occurs.

### Step 4: Verify checkpoint lifecycle remains separate

**Maps to**: AC3, AC7

Run:

```bash
bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh
```

Then inspect the gate integration output for `CHECKPOINT_STATE`.

**Expected result**: Existing lifecycle tests pass. Valid isolation with
`pending` still stops, while `satisfied` and `waived` permit continuation only
from the assigned worktree. The isolation gate does not write or alter
checkpoint evidence.

### Step 5: Verify fail-closed invalid-context outcomes

**Maps to**: AC4, AC5, AC6, AC10, AC11

From deterministic temporary fixtures, invoke the executable gate with:

1. each required field missing in turn;
2. a current directory outside the expected worktree;
3. an active branch different from the expected branch;
4. a missing or detached registration;
5. duplicate or ambiguous worktree registrations.

**Expected result**: Every case stops before the guarded mutation callback.
Output names the affected item, failed expected-versus-observed comparison,
`unclear_requirements`, and a human action that prefers a fresh runner with
complete context and any approved checkpoint decision front-loaded. No output
directs the stopped process to repair or re-enter repository state.

### Step 6: Verify item, epic, and batch surface parity

**Maps to**: AC1, AC2, AC8

Run the surface-contract assertions in:

```bash
bash scripts/development-workflow/tests/test-checkpoint-resume-gate.sh
```

Inspect the canonical protocols:

```bash
rg -n "checkpoint-resume-gate|expected-worktree|expected-branch|main-repo-root|checkpoint-state" \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
```

**Expected result**: All three protocols use the executable gate and require
item, expected worktree, expected branch, main root, and checkpoint state before
mutation. Their results and recovery actions match the implementation-plan
decision matrix.

### Step 7: Verify concurrent sibling isolation and batch guidance

**Maps to**: AC11, AC12, AC13

Run the concurrent fixture in:

```bash
bash scripts/development-workflow/tests/test-checkpoint-resume-gate.sh
```

Then inspect bounded-batch guidance:

```bash
rg -n "front-load|fresh.*runner|sibling|checkpoint-resume-gate" \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
  .agents/skills/run-items/SKILL.md \
  .agents/skills/run-items/agents/openai.yaml \
  .codex/skills/workflow-orchestrator/SKILL.md \
  .codex/skills/workflow-orchestrator/agents/openai.yaml \
  .claude/commands/run-items.md \
  .cursor/commands/run-items.md
```

**Expected result**: A stopped resumed item does not switch, dirty, or commit
from the shared main clone, and the sibling worktree remains unchanged. Every
batch surface advises front-loading approvals and fresh isolated dispatch after
concurrent risk clears instead of resuming a paused runner.

### Step 8: Confirm automatic re-entry has no live residual

**Maps to**: AC4, AC6, AC8, AC11

Run:

```bash
rg -n "RESULT=reenter|result=\"reenter\"|re-enter expected worktree|cd .*TARGET_WORKTREE" \
  scripts/development-workflow \
  docs/workflow/development-workflow \
  .agents/skills \
  .codex/skills \
  .claude/agents \
  .claude/commands \
  .cursor/agents \
  .cursor/commands
```

**Expected result**: No live checkpoint-resume instruction or executable path
permits automatic re-entry. Any historical documentation match is explicitly
reviewed and recorded as out of scope; it does not act as current operator
guidance.

### Step 9: Run adjacent workflow regressions

**Maps to**: AC7, AC8, AC9, AC12

Run:

```bash
bash scripts/development-workflow/tests/test-run-bounded-prelude.sh
bash scripts/development-workflow/tests/test-run-item-scope-resolver.sh
bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
```

**Expected result**: All tests exit successfully. Existing scope, policy,
checkpoint recommendation, and initial-dispatch isolation behavior remain
unchanged except for the fail-closed checkpoint-resume boundary.

### Step 10: Run shell and documentation quality gates

**Maps to**: AC2, AC8, AC9, AC10

Run:

```bash
shellcheck \
  scripts/development-workflow/checkpoint-resume-gate.sh \
  scripts/development-workflow/worktree-resume-preflight.sh \
  scripts/development-workflow/tests/test-checkpoint-resume-gate.sh \
  scripts/development-workflow/tests/test-worktree-resume-preflight.sh
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
npx markdownlint-cli2 \
  "docs/workflow/development-workflow/**/*.md" \
  ".agents/skills/**/*.md" \
  ".codex/skills/**/*.md" \
  ".claude/agents/*.md" \
  ".claude/commands/*.md" \
  ".cursor/agents/*.md" \
  ".cursor/commands/*.md" \
  "docs/specs/developments/20260723110117_1285-checkpoint-resume-worktree-isolation/*.md" \
  "docs/testing/workflow/1285-checkpoint-resume-worktree-isolation.smoke-test.md" \
  "CHANGELOG.md"
```

**Expected result**: ShellCheck, the workflow shell guard, and Markdown lint
exit successfully.

### Last Step: Validate assertions

- [ ] Every real checkpoint-resume handoff supplies item, expected worktree,
      expected branch, main root, and checkpoint state automatically.
- [ ] The executable resume gate runs before file, git, tracker, PR, label,
      comment, review, or merge mutation.
- [ ] Continuation succeeds only inside the unique assigned worktree on the
      expected branch with a satisfied or waived checkpoint.
- [ ] Main-clone, unexpected-directory, wrong-branch, missing, detached, and
      ambiguous contexts stop with `unclear_requirements`.
- [ ] A stopped session does not re-enter, switch, recreate, reset, restore,
      stash, clean, commit, push, or repair repository state.
- [ ] Isolation state and checkpoint state remain separate.
- [ ] Item, epic, and bounded-batch resume surfaces expose the same inputs,
      outcomes, next actions, and evidence.
- [ ] The integration test exercises the actual resume gate and blocks a
      guarded mutation callback from the main clone.
- [ ] Recovery guidance prefers a fresh, pre-approved, fully isolated runner.
- [ ] Concurrent test evidence proves the main clone and sibling worktree stay
      unchanged.
- [ ] Batch operator guidance front-loads approvals and avoids resuming a
      paused runner while a sibling is active.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Main clone fixture | Clean `develop` checkout with pre-gate snapshots | Created by `test-checkpoint-resume-gate.sh` |
| Expected worktree | Unique expected issue branch | Created by the shell test fixtures |
| Invalid registrations | Missing, wrong, detached, duplicated, and ambiguous states | Created by `test-worktree-resume-preflight.sh` |
| Sibling worktree | Concurrent isolated runner marker and branch | Created by `test-checkpoint-resume-gate.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Fixture worktree creation reports a branch already checked out | A prior interrupted test left temporary worktree metadata | Remove only the reported temporary fixture and rerun |
| Main-clone case unexpectedly returns `continue` | The gate or helper still allows automatic re-entry or omitted path proof | Stop; inspect gate output and restore fail-closed current-CWD comparison |
| Valid worktree case reports ambiguous registration | More than one fixture claims the expected path or branch | Inspect fixture `git worktree list --porcelain` and fix deterministic setup |
| Surface-contract assertion fails | One protocol, command, skill, agent, or metadata mirror omitted the canonical gate contract | Update the named surface to match Protocols 90/91/95 and rerun |
| Workflow shell guard flags the new script | Added shell uses an unsafe workflow pattern | Apply the reported safe pattern and rerun ShellCheck plus the guard |

---

## Known Limitations

- The regression creates new shell processes and deterministic temporary git
  fixtures to model a session continuation; it cannot force the hosted runner
  product itself to reset its process CWD.
- This feature protects repository worktree context only. It does not isolate
  ports, services, databases, caches, credentials, or other shared resources.
