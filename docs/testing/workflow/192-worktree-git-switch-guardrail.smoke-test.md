# Smoke Test Runbook: Worktree Git Switch Guardrail

**Feature**: Worktree Git Switch Guardrail (issue #192)
**Spec**: [`docs/specs/developments/20260417203405_192-worktree-git-switch-guardrail/1_192-worktree-git-switch-guardrail_specs.md`](../../specs/developments/20260417203405_192-worktree-git-switch-guardrail/1_192-worktree-git-switch-guardrail_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR has been merged into `develop`
- [ ] You have a local clone of the repository on the `develop` branch
- [ ] `git` and `gh` CLI are available

---

## Test Data

| Item | Value |
|---|---|
| Protocol 91 path | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Protocol 90 path | `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` |
| Claude agent path | `.claude/agents/item-orchestrator.md` |
| Cursor agent path | `.cursor/agents/item-orchestrator.md` |

---

## Smoke Test Steps

### Step 1: Verify Protocol 91 "Critical: Worktree Git Discipline" block (AC 1)

**Maps to**: Acceptance Criterion 1

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
2. Navigate to Step 3 "Worktree isolation for parallel batches"
3. Locate the clearly marked "Critical: Worktree Git Discipline" section

**Expected result**:
- The section exists and is clearly labelled (e.g., `**Critical: Worktree Git Discipline**`)
- It lists these prohibited commands: `git switch`, `git checkout`, `git checkout -b`, `git reset`, `git restore`
- It provides `git -C <worktree-path>` and `cd <worktree-path> &&` as required alternatives
- It states the rule applies when `BATCH_CONTEXT=true`

### Step 2: Verify Protocol 91 optional pre-tool-use hook guidance (AC 5)

**Maps to**: Acceptance Criterion 5 (optional)

1. Continuing in `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` Step 3
2. Locate the optional pre-tool-use hook guidance note near the Critical block

**Expected result**:
- A clearly marked "Optional" note exists describing the hook warning text
- The note states the hook is non-blocking (warns rather than blocks)
- The note states implementation is only required when the platform supports pre-tool-use hooks

### Step 3: Verify Protocol 90 Step 5.2 auto-correction for wrong-branch + clean (AC 2)

**Maps to**: Acceptance Criterion 2

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
2. Navigate to Step 5.2 "Post-Agent Main Working Tree Verification"
3. Review the wrong-branch + clean case

**Expected result**:
- The step explicitly handles the case where the main tree is on the wrong branch AND is clean
- It specifies auto-correcting by switching back to the integration branch (e.g., `git switch develop`)
- It requires logging the correction as a guardrail violation in the batch retrospective notes
- It does not require human intervention in this case (proceeds automatically)

### Step 4: Verify Protocol 90 Step 5.2 halt for wrong-branch + dirty (AC 3)

**Maps to**: Acceptance Criterion 3

1. Continuing in Protocol 90 Step 5.2
2. Review the wrong-branch + dirty case

**Expected result**:
- The step explicitly handles the case where the main tree is on the wrong branch AND has uncommitted modifications
- It does NOT auto-correct in this case
- It requires logging the full `git status --porcelain` output and the item ID of the preceding agent
- It halts and requires human intervention before dispatching additional agents

### Step 5: Verify Protocol 90 Step 5.2 halt for correct-branch + dirty

**Maps to**: Spec Use Case 2 postcondition (fourth case)

1. Continuing in Protocol 90 Step 5.2
2. Review the correct-branch + dirty case

**Expected result**:
- The step explicitly handles the case where the main tree is on the correct branch BUT has uncommitted modifications
- It halts and escalates to the human (same escalation path as wrong-branch + dirty)
- It logs the `git status --porcelain` output and the item ID

### Step 6: Verify Protocol 90 Step 5.2 clean pass for correct-branch + clean

**Maps to**: Spec Use Case 2 postcondition (third case)

1. Continuing in Protocol 90 Step 5.2
2. Review the correct-branch + clean case

**Expected result**:
- The step explicitly handles the case where the main tree is on the correct branch AND is clean
- It proceeds normally without any intervention

### Step 7: Verify item-orchestrator agent files contain git discipline reminder (AC 4)

**Maps to**: Acceptance Criterion 4

1. Open `.claude/agents/item-orchestrator.md`
2. Look for the worktree git discipline reminder

**Expected result**:
- A brief reminder is present that states all git state-changing commands must target the worktree path, not the main repo root
- The reminder mentions that violations leave the main repo in a broken state for concurrent agents

### Step 8: Verify both agent files are in sync (Dual-agent file rule)

**Maps to**: Implementation plan dual-agent file rule

1. Compare `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md`

**Expected result**:
- The worktree git discipline reminder in `.cursor/agents/item-orchestrator.md` is identical to `.claude/agents/item-orchestrator.md`
- No divergence in the reminder text between the two files

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: Protocol 91 Step 3 contains "Critical: Worktree Git Discipline" section listing `git switch`, `git checkout`, `git checkout -b`, `git reset`, `git restore` as prohibited commands, with correct alternatives, scoped to `BATCH_CONTEXT=true`
- [ ] AC 2: Protocol 90 Step 5.2 auto-corrects and logs when main tree is on wrong branch and is clean
- [ ] AC 3: Protocol 90 Step 5.2 halts and escalates with full `git status --porcelain` output when main tree has uncommitted modifications (regardless of branch)
- [ ] AC 4: `.claude/agents/item-orchestrator.md` contains a brief git discipline reminder
- [ ] AC 4 (sync): `.cursor/agents/item-orchestrator.md` contains the identical reminder
- [ ] AC 5 (optional): Protocol 91 contains an optional pre-tool-use hook guidance note describing warning text and non-blocking nature

---

## Seed Data Reference

None — this feature involves only protocol and agent-prompt document edits.

| Entity | Scenario | How to load |
|---|---|---|
| (none) | (none) | (none) |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| "Critical: Worktree Git Discipline" block not found in Protocol 91 | Implementation was not applied or was applied to the wrong section | Re-read the implementation plan and check Step 3 "Worktree isolation for parallel batches" |
| Protocol 90 Step 5.2 only shows the old single-case check | Implementation was not applied or was only partially applied | Check git diff against `develop` to confirm the four-case block is present |
| `.cursor/agents/item-orchestrator.md` reminder differs from `.claude` version | Sync was missed during implementation | Copy the reminder text from `.claude/agents/item-orchestrator.md` to `.cursor/agents/item-orchestrator.md` |

---

## Known Limitations

- The pre-tool-use hook (AC 5) is optional and platform-specific. This runbook only verifies the guidance note exists in the protocol — it does not test an actual hook at runtime.
- The four-case Step 5.2 logic is documented as protocol prose; runtime behavior depends on the orchestrator correctly following the protocol text.
