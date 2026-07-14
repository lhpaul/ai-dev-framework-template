# Smoke Test Runbook: Orchestrator Worktree Isolation for Concurrent Items

**Feature**: Orchestrator worktree isolation for concurrent items
**Spec**: [1_1205-orchestrator-worktree-isolation-for-concurrent-items_specs.md](../../specs/developments/20260714165415_1205-orchestrator-worktree-isolation-for-concurrent-items/1_1205-orchestrator-worktree-isolation-for-concurrent-items_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on a branch containing the implementation for issue #1205.
- [ ] The repository has no uncommitted changes unrelated to the test.
- [ ] `gh` is authenticated for read-only repository and PR inspection.
- [ ] Markdown lint dependencies are installed or available through `npx`.

---

## Test Data

| Item | Value |
| --- | --- |
| Mutating batch example | Two or more workflow items whose next action writes files |
| Read-only batch example | A portfolio scan or read-only inspection-only task |
| Expected isolation mode | `isolation: "worktree"` |
| Related distinction | Issue #1200 covers unsanctioned nested-agent PRs, not initial dispatch isolation |

---

## Smoke Test Steps

### Step 1: Verify Protocol 90 Dispatch Contract

**Maps to**: AC-1, AC-2, AC-3, AC-4, AC-9, AC-12

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Find the concurrent mutating dispatch section.
3. Confirm it requires `isolation: "worktree"` for two or more concurrent file-mutating runners.
4. Confirm it requires a distinct worktree path for every mutating item.
5. Confirm it stops before dispatch when an assignment is missing or duplicated.
6. Confirm it preserves an explicit read-only carve-out.

**Expected result**: Protocol 90 has an actionable pre-dispatch contract and
clear stop conditions before any concurrent mutating runner starts.

### Step 2: Verify Work Item Runner Self-Check

**Maps to**: AC-5, AC-6, AC-7, AC-8

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Find the `BATCH_CONTEXT=true` worktree self-check language.
3. Confirm the runner must compare expected and observed worktree path before mutation.
4. Confirm the runner must compare expected and observed branch before mutation.
5. Confirm wrong CWD and wrong branch stop before mutation.
6. Confirm possible prior out-of-worktree mutation escalates for human inspection instead of auto-resetting, restoring, or committing.

**Expected result**: Protocol 91 prevents a concurrent runner from silently
editing in the main checkout or on a sibling branch.

### Step 3: Verify Mirrored Command And Agent Surfaces

**Maps to**: AC-1, AC-2, AC-5, AC-10, AC-12

1. Run:

   ```bash
   grep -rl "isolation: \"worktree\"" \
     docs/workflow/development-workflow/protocols \
     .agents/skills .codex/skills .claude .cursor REVIEW.md
   ```

2. Confirm the output includes the updated run-items, orchestrator, and item-orchestrator surfaces named in the implementation plan.
3. Open each updated surface and confirm it uses the same core terms: isolation mode, distinct worktree path, pre-mutation self-check, and `BATCH_CONTEXT=true`.

**Expected result**: The workflow does not rely on Protocol 90 alone; every
runner-facing surface carries the isolation contract.

### Step 4: Verify #1200 Distinction

**Maps to**: AC-11

1. Search for `#1200` or `nested-agent` in the updated workflow docs.
2. Confirm the text says issue #1205 covers dispatch-time shared-tree contamination.
3. Confirm the text says issue #1200 covers separate unsanctioned nested-agent PR behavior.

**Expected result**: Operators and reviewers can distinguish the two failure
modes without guessing.

### Step 5: Run Documentation Checks

**Maps to**: AC-10, AC-12

1. Run markdown lint against the changed Markdown files.
2. Run the workflow heuristic Markdown linter.
3. Inspect the final implementation PR summary and confirm it reports whether isolation passed, failed before mutation, or escalated after possible mutation.

**Expected result**: Documentation checks pass, and the implementation PR
contains auditable isolation evidence.

---

## Assertions Checklist

- [ ] Protocol 90 requires `isolation: "worktree"` for concurrent mutating runners.
- [ ] Protocol 90 lists each mutating item with a distinct worktree path before dispatch.
- [ ] Missing isolation assignment stops before dispatch.
- [ ] Duplicate worktree path stops before dispatch.
- [ ] Protocol 91 requires a pre-mutation CWD self-check for `BATCH_CONTEXT=true`.
- [ ] Protocol 91 requires a pre-mutation branch self-check for `BATCH_CONTEXT=true`.
- [ ] Possible prior mutation outside the assigned worktree escalates for human inspection.
- [ ] Read-only concurrent work has an explicit non-isolated carve-out.
- [ ] Final summaries include isolation pass, pre-mutation failure, or escalation status.
- [ ] Documentation distinguishes dispatch-time shared-tree contamination from #1200 nested-agent PR behavior.
- [ ] `/run-items` and mirrored command surfaces mention the concurrent worktree isolation requirement.

---

## Seed Data Reference

No application seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Only Protocol 90 mentions isolation | Mirror update missed command, skill, or agent surfaces | Re-run the mirror search and update every listed surface. |
| Runner self-check language exists but no expected path is named | Handoff contract is too vague to verify | Add explicit expected worktree path and branch fields to the handoff and summary. |
| Docs treat #1200 and #1205 as the same risk | Failure-mode distinction was omitted | Add text that #1205 is initial dispatch isolation; #1200 is unsanctioned nested-agent PR creation. |

---

## Known Limitations

- This runbook validates the workflow contract and documentation surfaces. If
  the implementation adds executable shell enforcement, add script-level tests
  for missing and duplicate isolation assignments.
