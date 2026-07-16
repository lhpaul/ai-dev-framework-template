# Smoke Test Runbook: Incremental Commit Requirement for Dispatch

**Feature**: Incremental commit requirement for dispatch
**Spec**: [1_1176-incremental-commit-requirement-for-dispatch_specs.md](../../specs/developments/20260714170150_1176-incremental-commit-requirement-for-dispatch/1_1176-incremental-commit-requirement-for-dispatch_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on a branch containing the implementation for issue #1176.
- [ ] The repository has no unrelated uncommitted changes.
- [ ] Markdown lint dependencies are installed or available through `npx`.

---

## Test Data

| Item | Value |
| --- | --- |
| Long-running item example | A mutating workflow item with multiple coherent sub-parts |
| Single-step item example | A workflow item with no meaningful intermediate checkpoint |
| Recovery boundary | Latest committed checkpoint on the item branch or assigned worktree |
| Preserved gates | Internal review, automated reviewer loop, CI, readiness labels, tracker transitions, human merge policy |

---

## Smoke Test Steps

### Step 1: Verify Batch Dispatch Visibility

**Maps to**: AC1, AC2, AC3, AC7, AC8

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Find the Work Item Runner handoff section.
3. Confirm mutating item handoffs require committing immediately after each completed logical sub-part.
4. Confirm the text says agents must not intentionally batch all completed sub-parts into one end-of-run commit.
5. Confirm the text exempts truly single-step work with no meaningful completed intermediate checkpoint.
6. Confirm the text scopes commits to the assigned item, branch, and worktree.

**Expected result**: A receiving Work Item Runner sees the incremental commit requirement before mutating work starts.

### Step 2: Verify Stage-Agent And Fixer Handoffs

**Maps to**: AC1, AC2, AC3, AC6, AC7, AC8

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Confirm the stage-agent handoff requirement includes the same incremental commit instruction.
3. Confirm fixer-agent guidance reconciles local checkpoint commits with the existing rule to push once per review cycle.
4. Confirm no text permits committing incomplete, failing, or incoherent partial edits.
5. Confirm no text weakens reviewer-loop, CI, readiness-label, tracker, or merge gates.

**Expected result**: Creator and fixer agents receive consistent commit guidance without changing PR readiness requirements.

### Step 3: Verify Epic-Scoped Dispatch

**Maps to**: AC1, AC2, AC4, AC5, AC7, AC8

1. Open `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
2. Confirm epic-scoped child item execution passes the incremental commit requirement into item handoffs.
3. Confirm recovery guidance points operators to committed checkpoints on the item branch or assigned worktree.
4. Confirm absence of a newer checkpoint is acceptable evidence when no completed sub-part existed after the last checkpoint.

**Expected result**: Epic-scoped runs get the same recoverability behavior as explicit-list and single-item runs.

### Step 4: Verify Mirrored Agent And Skill Surfaces

**Maps to**: AC1, AC2, AC7, AC8

1. Run a repository search for the core phrase:

   ```bash
   rg -n "completed logical sub-part|incremental commit requirement|checkpoint commit" \
     docs/workflow/development-workflow/protocols \
     .claude/agents .cursor/agents .agents/skills .codex/skills REVIEW.md
   ```

2. Confirm results include the updated orchestrator, item-orchestrator, and developer-facing surfaces named in the implementation plan.
3. Confirm the mirrored text uses the same core terms: completed logical sub-part, coherent checkpoint, assigned item/branch/worktree, and no end-of-run batching.

**Expected result**: The requirement is not stranded in a single protocol; receiving agents and reviewers can find it.

### Step 5: Verify Recovery And Readiness Gates

**Maps to**: AC4, AC5, AC6

1. Search the changed docs for `reviewer loop`, `CI`, `ready-for-human-review`, and `tracker`.
2. Confirm incremental commits are described as crash-safety checkpoints only.
3. Confirm final PR readiness still depends on the normal internal review, automated reviewer loop, CI, readiness labels, tracker transitions, and human merge policy.
4. Confirm recovery still inspects live branch, PR, and worktree state.

**Expected result**: Incremental commits improve recovery but do not bypass any existing validation or merge gate.

### Step 6: Run Documentation Checks

**Maps to**: AC8

1. Run markdown lint on the changed documentation files.
2. Run the workflow heuristic Markdown linter.
3. If the implementation updates `CHANGELOG.md`, run the duplicate-header check.

**Expected result**: Documentation checks pass.

---

## Assertions Checklist

- [ ] Long-running mutating item dispatches require commits after each completed logical sub-part.
- [ ] Dispatch guidance prohibits batching all completed sub-parts into one end-of-run commit.
- [ ] Single-step work with no meaningful intermediate checkpoint may still use one final commit.
- [ ] Recovery operators can inspect item branch or worktree commit history for completed checkpoints.
- [ ] Absence of a newer checkpoint is acceptable recovery evidence when no completed sub-part existed.
- [ ] Incremental commits do not change internal review, automated reviewer loop, CI, readiness-label, tracker-transition, or human merge gates.
- [ ] Concurrent batch and epic-scoped guidance keeps commits and recovery scoped to the assigned item, branch, and worktree.
- [ ] The requirement is visible in both dispatcher and receiving-agent guidance.

---

## Seed Data Reference

No application seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Only Protocol 90 mentions the requirement | Mirrored stage-agent or skill guidance was missed | Update Protocol 91 and the agent/skill surfaces listed in the implementation plan. |
| Fixer guidance says both "commit per sub-part" and "one commit, then push" without distinction | Local checkpoint commits were not distinguished from reviewer-loop pushes | Clarify that substantial fixer work may create local checkpoint commits but pushes once after all addressable fixes are complete. |
| Agents could interpret the rule as timer-based commits | The coherent-checkpoint boundary was omitted | Add text that incomplete, failing, or incoherent edits must not be committed just to satisfy a timer. |
| Recovery guidance ignores unpushed local commits | The worktree recovery surface was missed | Add explicit inspection of local worktree commits and uncommitted edits before resuming. |

---

## Known Limitations

- This runbook validates documentation and prompt surfaces. It does not simulate
  a killed runner process.
