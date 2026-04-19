# Smoke Test Runbook: Write/Edit Path Guardrail for Isolated Worktrees

**Feature**: fix(item-orchestrator): Write/Edit path guardrail for isolated worktrees (#193)
**Spec**: [`docs/specs/developments/20260418003426_193-worktree-write-paths-guardrail/1_193-worktree-write-paths-guardrail_specs.md`](../../specs/developments/20260418003426_193-worktree-write-paths-guardrail/1_193-worktree-write-paths-guardrail_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Working copy is on `develop` (or the feature branch after merge)
- [ ] No worktrees with leaked files are present in the main repo root
- [ ] You have `gh` CLI configured and authenticated

---

## Test Data

| Item | Value |
|---|---|
| Protocol file | `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Claude agent file | `.claude/agents/item-orchestrator.md` |
| Cursor agent file | `.cursor/agents/item-orchestrator.md` |

---

## Smoke Test Steps

### Step 1: Verify Protocol 91 Step 3 contains the Write/Edit guardrail

**Maps to**: Acceptance Criterion 1 and 2

1. Open `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Navigate to Step 3 (Dispatch Strategy) → worktree isolation subsection.
3. Locate the critical safety rule block for `Write` and `Edit` paths.
4. Confirm the block explicitly states that all `Write` and `Edit` tool calls must target paths under `<worktree-path>/...`.
5. Confirm the block states that `<worktree-path>` must be resolved to its **runtime value** (not left as a static placeholder) before injection into stage-agent handoffs.

**Expected result**: The guardrail prose is present in Step 3 and references the runtime-resolved `<worktree-path>`.

---

### Step 2: Verify the reminder covers every stage-agent handoff

**Maps to**: Acceptance Criterion 3

1. In the same guardrail block, look for the instruction that the item-orchestrator must include the reminder in **every** stage-agent handoff, not only the first.
2. Confirm the block explicitly says "every stage-agent handoff" or equivalent language.

**Expected result**: The text clearly mandates repeated inclusion across all handoffs in a batch run.

---

### Step 3: Verify the guardrail is scoped to BATCH_CONTEXT=true

**Maps to**: Acceptance Criterion 4

1. Confirm the guardrail prose states the rule applies only when `BATCH_CONTEXT=true` (a dedicated worktree exists).
2. Confirm non-batch runs (no worktree) are explicitly excluded or the block notes this is a no-op when `BATCH_CONTEXT=false`.

**Expected result**: The scoping condition is unambiguous.

---

### Step 4: Verify optional pre-tool-use hook design (if implemented)

**Maps to**: Acceptance Criterion 5 and 6

1. Look for an "Optional: pre-tool-use hook" or similarly titled subsection in Protocol 91 Step 3.
2. Confirm it describes: intercept `Write`/`Edit` calls only, check path against `WORKTREE_ROOT`, emit a blocking warning on mismatch, skip read-only tools.
3. Confirm the hook spec states that when `WORKTREE_ROOT` is unset the hook is a no-op.

**Expected result**: Hook design is documented (or step is skipped if the optional section was not implemented).

---

### Step 5: Verify non-batch behavior is unchanged

**Maps to**: Acceptance Criterion 7

1. Search `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` for any change outside the Step 3 worktree isolation block (e.g., Step 7a, Step 8, Protocol 90 references, `post-merge-cleanup.sh`, `pr-review-loop.sh`).
2. Confirm no lines outside the targeted subsection were modified.
3. Verify Protocol 90 (`90-batch-orchestrate-work-protocol.md`) was not changed by this PR.
4. Verify `scripts/development-workflow/post-merge-cleanup.sh` and `scripts/development-workflow/pr-review-loop.sh` were not changed by this PR.

**Expected result**: Zero diffs outside the three targeted files (Protocol 91 Step 3, `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`).

---

### Step 6: Verify dual-agent sync

**Maps to**: Acceptance Criterion for dual-agent consistency

1. Open `.claude/agents/item-orchestrator.md`.
2. Locate the worktree Write/Edit path discipline reminder in the Notes block.
3. Open `.cursor/agents/item-orchestrator.md`.
4. Confirm the identical reminder language is present in the same relative position.
5. Confirm no other content differs between the two files beyond the `model:` and `tools:` frontmatter fields (which legitimately differ).

**Expected result**: Worktree path reminder is identical in both agent files.

---

### Last Step: Assertions checklist

- [ ] All assertions below are confirmed.
- [ ] No unexpected file changes are present in the PR diff.

---

## Assertions Checklist

- [ ] AC1: Protocol 91 Step 3 worktree section contains an explicit, human-readable reminder that all `Write` and `Edit` tool calls must target paths under `<worktree-path>/...` and that any main-repo-absolute path is a red flag to correct before calling the tool.
- [ ] AC2: The reminder specifies that `<worktree-path>` must be resolved to its runtime value before being included in stage-agent handoffs (not left as a placeholder).
- [ ] AC3: The reminder specifies that it must appear in every stage-agent handoff (not just the first) issued for the item.
- [ ] AC4: The protocol language makes clear the guardrail applies only when `BATCH_CONTEXT=true`.
- [ ] AC5 (Optional): A pre-tool-use hook design is described that intercepts `Write`/`Edit` calls, checks the target path against `WORKTREE_ROOT`, and emits a blocking warning if the path is outside the worktree.
- [ ] AC6 (Optional): The hook spec states that when `WORKTREE_ROOT` is unset the hook is a no-op.
- [ ] AC7: The changes do not alter Protocol 91 behavior for non-batch runs, Protocol 90, `post-merge-cleanup.sh`, `pr-review-loop.sh`, or any scope covered by issue #192.
- [ ] Dual-agent sync: `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` contain identical worktree path reminder language.

---

## Seed Data Reference

No seed data required. All changes are documentation-only.

| Entity | Scenario | How to load |
|---|---|---|
| N/A | — | — |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Reminder not found in Protocol 91 Step 3 | Implementation PR not yet merged, or wrong section searched | Confirm you are in the Step 3 worktree isolation block, after the `git switch`/`git reset` safety rule |
| `.claude` and `.cursor` agent files differ | Developer forgot to update one file | Re-open the implementation PR and apply the missing change to the out-of-sync file |
| Non-targeted files modified in PR diff | Scope leak during implementation | Revert unexpected changes and reopen the PR |

---

## Known Limitations

- This smoke test is entirely manual (document review). There is no automated way to verify that an agent honors the reminder at runtime without running a live parallel batch.
- The optional pre-tool-use hook (Use Case 2) is not implemented as runnable code in this PR; its design is documented only.
