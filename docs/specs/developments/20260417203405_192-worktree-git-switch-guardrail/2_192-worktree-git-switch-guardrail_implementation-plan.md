# Worktree Git Switch Guardrail — Implementation Plan

**Spec**: [`1_192-worktree-git-switch-guardrail_specs.md`](1_192-worktree-git-switch-guardrail_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/192-worktree-git-switch-guardrail.smoke-test.md`](../../../testing/workflow/192-worktree-git-switch-guardrail.smoke-test.md)

---

## Summary

**Approach**: Three targeted documentation edits across four files: (1) strengthen Protocol 91 Step 3 worktree isolation section with an explicit "Critical: Worktree Git Discipline" block listing prohibited commands and correct alternatives; (2) upgrade Protocol 90 Step 5.2 post-agent verification to auto-correct a clean wrong-branch main tree (all four postcondition states from the spec — wrong+clean, wrong+dirty, correct+clean, correct+dirty — are handled explicitly); (3) add a brief git-discipline reminder to both item-orchestrator agent files (`.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md`, which must stay in sync). An optional pre-tool-use hook guidance note is added to Protocol 91 as a clearly marked optional section.

**Estimated complexity**: S

**Rationale**: All changes are documentation and agent-prompt edits only. No code, scripts, or infrastructure changes are required. The existing Protocol 91 Step 3 already has the conceptual worktree isolation section; this plan adds a specifically labelled guardrail block to it. Protocol 90 Step 5.2 already has the post-agent check but only handles dirty modifications — the plan adds branch-drift detection and auto-correction logic for the clean case, plus the two correct-branch cases from the spec.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

> This project's "shared libraries" are the workflow protocol documents and agent system prompt files. Changes are doc-only with no code.

- [ ] **`docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`** — Step 3 "Worktree Isolation" section: add an explicit, clearly marked "Critical: Worktree Git Discipline" block immediately inside the existing Step 3 worktree content (after the `cd <worktree-path>` instruction, before the "Important — stage protocol compatibility" note). The block must enumerate `git switch`, `git checkout`, `git checkout -b`, `git reset`, and `git restore` as prohibited commands when issued against the main repo root; provide `git -C <worktree-path>` and `cd <worktree-path> &&` as the required alternatives; and state the rule applies when `BATCH_CONTEXT=true`. (AC 1)

- [ ] **`docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`** — Step 3 "Worktree Isolation" section: add an optional pre-tool-use hook guidance note (clearly marked "Optional — platform-specific") describing the warning text, check logic (command's working directory vs. main repo root), and non-blocking nature of the hook. Place this note after the Critical block above. (AC 5 — optional, does not block the PR)

- [ ] **`docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`** — Step 5.2 "Post-Agent Main Working Tree Verification": replace the current check (which only detects uncommitted modifications) with an expanded check that handles all four postcondition states from the spec:
  - **Wrong branch + clean**: auto-correct by running `git -C <main-repo-root> switch <integration-branch>` (or `git checkout`), log the correction as a guardrail violation in the batch retrospective notes, and proceed normally. (AC 2, BR-2, BR-3, BR-6)
  - **Wrong branch + dirty**: halt and escalate — do not auto-correct. Log the full `git status --porcelain` output and the item ID of the preceding agent. (AC 3, BR-3)
  - **Correct branch + clean**: proceed normally. (AC 2 implicit — already handled today but must be explicitly documented as a case)
  - **Correct branch + dirty**: halt and escalate — same escalation as wrong-branch dirty; log `git status --porcelain` output and item ID. (spec UC2 postcondition — fourth case)

- [ ] **`.claude/agents/item-orchestrator.md`** — add a brief "Worktree git discipline" reminder after the existing bullet list. The reminder must state that all git state-changing commands (`switch`, `checkout`, `reset`, `restore`) must target the worktree path, not the main repo root, and that violations leave the main repo in a broken state for all concurrent agents. (AC 4)

- [ ] **`.cursor/agents/item-orchestrator.md`** — apply the identical worktree git discipline reminder as `.claude/agents/item-orchestrator.md`. These two files must stay in sync. (AC 4 — dual-agent file rule)

---

## Testing Strategy

**Test types**: Manual / Smoke (workflow protocol review)

**Key scenarios to test**:

1. Protocol 91 Step 3 contains the new "Critical: Worktree Git Discipline" section with all required fields — maps to AC 1
2. Protocol 91 Step 3 contains the optional pre-tool-use hook guidance note, clearly marked "Optional" — maps to AC 5
3. Protocol 90 Step 5.2 handles wrong-branch + clean (auto-corrects and logs) — maps to AC 2
4. Protocol 90 Step 5.2 handles wrong-branch + dirty (halts and escalates with full `git status --porcelain`) — maps to AC 3
5. Protocol 90 Step 5.2 handles correct-branch + dirty (halts and escalates, same path as wrong+dirty) — maps to spec UC2 postcondition
6. Both item-orchestrator agent files contain the git discipline reminder — maps to AC 4
7. Both item-orchestrator files are identical in the new section — maps to the dual-agent file rule

**Smoke test runbook**: [`../../../testing/workflow/192-worktree-git-switch-guardrail.smoke-test.md`](../../../testing/workflow/192-worktree-git-switch-guardrail.smoke-test.md)

---

## Seed Data

None — this feature involves only protocol and agent-prompt document edits. No seed data is required.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — updated as part of implementation (this is the primary deliverable)
- [ ] `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — updated as part of implementation (this is the primary deliverable)
- [ ] `.claude/agents/item-orchestrator.md` — updated as part of implementation
- [ ] `.cursor/agents/item-orchestrator.md` — updated as part of implementation
- [ ] `CHANGELOG.md` — add entry under `[Unreleased]` for the guardrail additions

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Conflict with #193 at impl stage | Med | Low | #193 touches Protocol 91 Step 3/4 Write/Edit path guardrail; #192 touches git state-changing commands in the same section. If both PRs are merged to `develop` before the other's impl starts, the section will differ from the plan's base. Resolve the merge conflict by keeping both guardrail sub-blocks. |
| Auto-correction logic misidentifies integration branch | Low | Med | The plan specifies using the `integration_branch` from workflow context (typically `develop`). The implementation must read this value from `.ai-dev-workflow.yaml` or hardcode `develop` as the default — do not infer from runtime state. |
| The four-case Step 5.2 becomes hard to scan | Low | Low | Use a code-block or a clear 4-case numbered list with explicit branch labels so the cases are unambiguous and diff-friendly. |

---

## Code Samples

> All samples below are **Illustrative — adapt during implementation**.

### Protocol 90 Step 5.2 Replacement (Illustrative)

```bash
# Illustrative — adapt during implementation
INTEGRATION_BRANCH="develop"
MAIN_BRANCH=$(git -C <main-repo-root> rev-parse --abbrev-ref HEAD)
MAIN_STATUS=$(git -C <main-repo-root> status --porcelain)

if [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
  # Case: wrong branch, clean — auto-correct
  echo "GUARDRAIL: main working tree was on '$MAIN_BRANCH' after agent for item <item-id> returned. Auto-correcting to '$INTEGRATION_BRANCH'. Record as guardrail violation in retrospective notes."
  git -C <main-repo-root> switch "$INTEGRATION_BRANCH"
  # Proceed normally

elif [ "$MAIN_BRANCH" != "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
  # Case: wrong branch, dirty — halt and escalate
  echo "ERROR: main working tree is on '$MAIN_BRANCH' and has uncommitted modifications after agent for item <item-id> returned."
  echo "$MAIN_STATUS"
  echo "Do not dispatch additional agents. Report to the human and ask them to inspect and discard (or commit to a separate branch) the leaked modifications before resuming."
  exit 1

elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -z "$MAIN_STATUS" ]; then
  # Case: correct branch, clean — proceed normally (no action needed)
  :

elif [ "$MAIN_BRANCH" = "$INTEGRATION_BRANCH" ] && [ -n "$MAIN_STATUS" ]; then
  # Case: correct branch, dirty — halt and escalate
  echo "WARNING: main working tree is on '$INTEGRATION_BRANCH' but has uncommitted modifications after agent for item <item-id> returned:"
  echo "$MAIN_STATUS"
  echo "Possible cause: a stage agent leaked file writes outside the worktree boundary. Do not discard these changes without human review. Do not dispatch additional agents."
  exit 1
fi
```

### Protocol 91 Step 3 Guardrail Block (Illustrative)

```markdown
<!-- Illustrative — adapt during implementation -->
**Critical: Worktree Git Discipline** (`BATCH_CONTEXT=true` only)

When operating inside a worktree, **never** run the following commands against the main repo root:

- `git switch <branch>`
- `git checkout <branch>`
- `git checkout -b <branch>`
- `git reset [--hard|--soft|--mixed] ...`
- `git restore ...`

These commands change the branch or modify files in the main working tree, breaking isolation for all concurrent agents and the human operator.

**Required alternatives**:
- Run the command inside the worktree: `cd <worktree-path> && git <command>`
- Or use the `-C` flag: `git -C <worktree-path> <command>`

Read-only inspection of the main repo branch is always permitted:
`git -C <main-repo-root> rev-parse --abbrev-ref HEAD`
```

---

## Implementation Order

1. Read the current text of Protocol 91 Step 3 (Worktree Isolation section) and Protocol 90 Step 5.2 in full — understand exact insertion points before editing.
2. Edit `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — add the "Critical: Worktree Git Discipline" block in Step 3 at the insertion point identified in step 1 (after the `cd <worktree-path>` instruction, before the "Important — stage protocol compatibility" note).
3. Edit `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — add the optional pre-tool-use hook guidance note immediately after the Critical block (clearly marked "Optional — platform-specific").
4. Edit `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — replace the current Step 5.2 bash block and its "If any modifications are detected" prose with the expanded four-case logic from the Code Samples section above.
5. Edit `.claude/agents/item-orchestrator.md` — add the "Worktree git discipline" reminder after the existing bullet list.
6. Edit `.cursor/agents/item-orchestrator.md` — apply the identical reminder text (keep both files in sync).
7. Update `CHANGELOG.md` — add entry under `[Unreleased]` describing the guardrail additions.
8. Run markdownlint on the changed files and fix any trailing-whitespace or link issues.
9. Verify smoke test runbook steps manually against the updated documents.
