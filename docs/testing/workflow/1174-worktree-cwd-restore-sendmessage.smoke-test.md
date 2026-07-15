# Smoke Test Runbook: Worktree CWD Restore on Checkpoint Resume

**Feature**: Worktree CWD restore on checkpoint resume (#1174)
**Spec**:
[1_1174-worktree-cwd-restore-sendmessage_specs.md](../../specs/developments/20260714164811_1174-worktree-cwd-restore-sendmessage/1_1174-worktree-cwd-restore-sendmessage_specs.md)
**Implementation plan**:
[2_1174-worktree-cwd-restore-sendmessage_implementation-plan.md](../../specs/developments/20260714164811_1174-worktree-cwd-restore-sendmessage/2_1174-worktree-cwd-restore-sendmessage_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for #1174 is checked out.
- [ ] `bash`, `git`, `jq`, `python3`, and `npx` are available.
- [ ] `node_modules` is installed so `markdownlint-cli2` can run.
- [ ] The runner can create temporary git repositories and worktrees under
      `/tmp`.
- [ ] No real tracker, PR, label, or comment mutation is performed during the
      helper tests.

---

## Test Data

| Item | Value |
| --- | --- |
| Resume preflight helper | `scripts/development-workflow/worktree-resume-preflight.sh` |
| Existing CWD guard | `scripts/development-workflow/worktree-cwd-guard.sh` |
| Main shell test | `scripts/development-workflow/tests/test-worktree-resume-preflight.sh` |
| Run-item protocol | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Run-epic protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |
| Run-item surfaces | `.agents/skills/run-item/SKILL.md`, `.claude/commands/run-item.md`, `.cursor/commands/run-item.md` |
| Run-epic surfaces | `.agents/skills/run-epic/SKILL.md`, `.claude/commands/run-epic.md`, `.cursor/commands/run-epic.md` |
| Main clone expected branch | `develop` |

---

## Smoke Test Steps

### Step 1: Run resume preflight unit tests

**Maps to**: AC1, AC2, AC3, AC4, AC5, AC6, AC9, AC10

Run:

```bash
bash scripts/development-workflow/tests/test-worktree-resume-preflight.sh
```

**Expected result**: The test exits successfully. Output includes passing
coverage for:

- already in expected worktree;
- main clone with one matching worktree;
- missing worktree;
- ambiguous worktree;
- mismatched branch;
- detached or incomplete entry;
- path-boundary handling;
- branch lookalikes;
- worktree paths with spaces;
- failing `git worktree list`.

### Step 2: Verify the existing CWD guard still works

**Maps to**: AC6, AC7

Run the existing guard from inside a temporary fixture or the implementation
test fixture:

```bash
bash scripts/development-workflow/worktree-cwd-guard.sh \
  --check-cwd "<expected-worktree-path>" "<main-repo-root>"
```

**Expected result**: When the command runs from the expected worktree, it exits
successfully. When the command runs from the main clone, it exits non-zero with
a `GUARDRAIL WARNING` and does not perform any git state-changing action.

### Step 3: Simulate a checkpoint resume from the main clone

**Maps to**: AC1, AC3, AC6, AC9, AC10

Using a temporary fixture repository:

1. Create a main clone on `develop`.
2. Create one registered worktree on
   `implementation-plan/1174-worktree-cwd-restore-sendmessage`.
3. Start from the main clone CWD.
4. Run the resume preflight helper with the expected branch and item.
5. Follow the helper's re-entry directive.
6. Run `pwd` and `git rev-parse --abbrev-ref HEAD` after re-entry.
7. From the main clone path, run:

   ```bash
   git -C "<main-repo-root>" rev-parse --abbrev-ref HEAD
   git -C "<main-repo-root>" status --porcelain
   ```

**Expected result**: The helper identifies exactly one matching worktree, logs
safe re-entry, and the resumed commands run from the worktree branch. The main
clone remains on `develop` and has no tracked modifications.

### Step 4: Simulate a missing or untrusted worktree

**Maps to**: AC4, AC6, AC9

Using a temporary fixture repository:

1. Start from the main clone CWD.
2. Run the resume preflight helper for an expected branch that has no trusted
   registered worktree.
3. Repeat with a fixture where the expected path exists but is on a different
   branch.
4. Repeat with ambiguous matching worktree data.

**Expected result**: Each run exits non-zero or emits a structured stop result
before mutation. The output names the item, expected branch, observed directory,
observed branch when available, failure reason, and human recovery action.

### Step 5: Verify checkpoint state is not changed by re-entry

**Maps to**: AC5

Run:

```bash
bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh
```

**Expected result**: The test exits successfully. Existing checkpoint
satisfaction and waiver behavior still depends on explicit satisfaction or
waiver evidence, not on worktree re-entry.

### Step 6: Verify run-item and run-epic surface parity

**Maps to**: AC1, AC2, AC8

Inspect the updated surfaces:

```bash
rg -n "checkpoint-resume|worktree preflight|expected worktree|main clone" \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/95-run-epic-protocol.md \
  .agents/skills/run-item/SKILL.md \
  .agents/skills/run-item-work/SKILL.md \
  .agents/skills/run-epic/SKILL.md \
  .codex/skills/workflow-item-orchestrator/SKILL.md \
  .claude/commands/run-item.md \
  .claude/commands/run-item-work.md \
  .claude/commands/run-epic.md \
  .cursor/commands/run-item.md \
  .cursor/commands/run-item-work.md \
  .cursor/commands/run-epic.md
```

**Expected result**: Each primary run-item and run-epic surface describes the
same resume-side worktree requirement or explicitly inherits it from the
canonical command/protocol.

### Step 7: Run adjacent workflow regressions

**Maps to**: AC5, AC7, AC8

Run:

```bash
bash scripts/development-workflow/tests/test-run-item-scope-resolver.sh
bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
bash scripts/development-workflow/tests/test-run-bounded-prelude.sh
```

**Expected result**: All tests exit successfully. Scope resolution and bounded
prelude behavior remain unchanged except for the new resume-side worktree
requirement.

### Step 8: Run markdown and shell guards

**Maps to**: AC8, AC9

Run:

```bash
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
npx markdownlint-cli2 \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  ".agents/skills/run-item/SKILL.md" \
  ".agents/skills/run-item-work/SKILL.md" \
  ".agents/skills/run-epic/SKILL.md" \
  ".codex/skills/workflow-item-orchestrator/SKILL.md" \
  ".claude/commands/run-item.md" \
  ".claude/commands/run-item-work.md" \
  ".claude/commands/run-epic.md" \
  ".cursor/commands/run-item.md" \
  ".cursor/commands/run-item-work.md" \
  ".cursor/commands/run-epic.md" \
  "docs/specs/developments/20260714164811_1174-worktree-cwd-restore-sendmessage/1_1174-worktree-cwd-restore-sendmessage_specs.md" \
  "docs/specs/developments/20260714164811_1174-worktree-cwd-restore-sendmessage/2_1174-worktree-cwd-restore-sendmessage_implementation-plan.md" \
  "docs/testing/workflow/1174-worktree-cwd-restore-sendmessage.smoke-test.md" \
  "CHANGELOG.md"
```

**Expected result**: Both commands exit successfully.

### Last Step: Assertions Checklist

- [ ] A checkpointed worktree-isolated `/run-item` resume runs a CWD preflight
      before file, git, PR, tracker, label, or comment mutation.
- [ ] A checkpointed worktree-isolated `/run-epic` resume runs the same CWD
      preflight before mutation.
- [ ] A resume that begins in the main clone with exactly one matching
      registered worktree re-enters that worktree and logs the correction.
- [ ] Missing, ambiguous, detached, or mismatched worktree state stops before
      mutation with a clear recovery action.
- [ ] Worktree re-entry does not satisfy or waive human checkpoints.
- [ ] A resumed checkpointed run cannot silently switch, dirty, or use the main
      clone for item-branch execution.
- [ ] The existing initial-entry branch/worktree guard still applies before the
      first edit of newly dispatched worktree-isolated items.
- [ ] Run-item and run-epic command and skill surfaces describe the same
      resume-side requirement.
- [ ] Tests simulate a checkpoint resume that starts from the main clone.
- [ ] Main-clone branch evidence shows the shared checkout remains on
      `develop` after the resume attempt.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Main clone fixture | Main checkout starts on `develop` | Created by `test-worktree-resume-preflight.sh` |
| Worktree fixture | Expected item branch registered as a worktree | Created by `test-worktree-resume-preflight.sh` |
| Untrusted worktree fixtures | Missing, ambiguous, detached, and mismatched worktree states | Created by `test-worktree-resume-preflight.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `git worktree add` fails because a branch is checked out elsewhere | Fixture cleanup did not remove a previous test worktree | Remove the temporary fixture directory and rerun the shell test |
| Resume helper reports ambiguous worktrees | More than one registered worktree matches the expected branch or path | Inspect `git worktree list --porcelain`, remove stale fixture worktrees, and rerun |
| Main clone branch check is not `develop` | The test ran commands from the main clone instead of the fixture worktree | Stop before mutation and fix the re-entry step or helper matching logic |
| Markdownlint relative-link failure | A command or plan link uses the wrong number of `../` segments | Recalculate the link from the file location and rerun markdownlint |

---

## Known Limitations

- The smoke test uses temporary git fixtures rather than a real paused Codex
  SendMessage session.
- The feature protects repository working-directory context only. It does not
  isolate ports, databases, caches, or other runtime resources.
