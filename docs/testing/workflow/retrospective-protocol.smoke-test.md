# Smoke Test Runbook: Retrospective Protocol

**Feature**: Retrospective Protocol
**Spec**: [1_retrospective-protocol_specs.md](../../specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository has at least one merged or open PR with review history (comments, review cycles, labels)
- [ ] `gh` CLI is authenticated and functional (`gh auth status`)
- [ ] The retrospective protocol document exists at `docs/ai/development-workflow/protocols/06-retrospective-protocol.md`
- [ ] The `/retrospective` command/skill is available in the platform being tested

---

## Test Data

| Item | Value |
|---|---|
| Repository | The current repository (or any repo with recent PR activity) |
| Target PR (for scoped test) | Any recently merged PR with review comments |

---

## Smoke Test Steps

### Step 1: Fresh Session — No Scope Hint

**Maps to**: Acceptance Criteria 1, 2, 3, 4, 12

1. Open a new session in the target platform (Claude Code, Cursor, or Codex)
2. Invoke `/retrospective` (or the platform equivalent) with no arguments
3. Observe: the agent queries GitHub for recent PR data
4. If findings are surfaced:
   - Verify each finding has a category label (from: Workflow & Process, Agent Behavior, Configuration, Documentation, Code Quality, Tooling)
   - Verify each finding has a severity signal (High, Medium, or Low)
   - Verify each finding has a recommended action (Address now or Add to backlog)
   - For one finding, choose "Skip" — verify the agent moves on without taking action
5. If no findings are surfaced:
   - Verify the agent communicates that no actionable opportunities were found
   - Verify the agent closes the retrospective gracefully

**Expected result**: Categorized findings are presented (or a graceful "no findings" message), and the agent does not take any action without the human's explicit choice.

### Step 2: Fresh Session — With Scope Hint

**Maps to**: Acceptance Criterion 1

1. Open a new session
2. Invoke `/retrospective` with a specific PR number (e.g., `/retrospective PR #42`)
3. Verify findings are scoped to that PR (not unrelated recent PRs)

**Expected result**: Findings relate to the specified PR.

### Step 3: Address Now — Simple Fix

**Maps to**: Acceptance Criteria 5, 12

1. From the findings in Step 1 or Step 2, choose "Address now" for a finding the agent assesses as simple
2. Verify the agent applies the fix directly
3. Verify the agent commits and pushes the change
4. Verify the agent reports what was changed (diff or summary)
5. Verify no new PR or review loop was opened

**Expected result**: Simple fix is committed and pushed; no new PR created.

### Step 4: Address Now — Complex Finding

**Maps to**: Acceptance Criterion 6

1. If any finding is assessed as too complex for direct fix, choose "Address now" for it
2. Verify the agent recommends "Add to backlog" instead
3. Verify the agent explains why the fix is too complex for direct application

**Expected result**: Agent redirects to "Add to backlog" with explanation. (Note: this scenario depends on the findings surfaced; if no complex findings exist, note this step as N/A.)

### Step 5: Add to Backlog

**Maps to**: Acceptance Criteria 7, 12

1. From the findings, choose "Add to backlog" for one finding
2. Verify a GitHub issue is created (via `gh issue create`)
3. Verify the issue has a descriptive title and body
4. Verify the agent returns the issue URL
5. Inspect the created issue: confirm the body includes enough context to understand the problem without the original conversation

**Expected result**: GitHub issue created with descriptive content; URL returned.

### Step 6: Protocol 90 Integration — Batch Summary Suggestion

**Maps to**: Acceptance Criterion 9

1. Run a batch orchestration session (via `/run-work` or equivalent) that processes at least one item to completion
2. After the batch summary is displayed, verify the agent suggests: "Would you like to run a retrospective on this session's work?" (or similar wording)
3. Accept the suggestion
4. Verify the retrospective runs and presents findings (including conversation-context findings if available)

**Expected result**: Retrospective is suggested after batch summary; runs when accepted.

### Step 7: Protocol 91 Integration — Standalone Item Suggestion

**Maps to**: Acceptance Criterion 10

1. Run a single item via `/run-item-work` or equivalent (standalone, not dispatched by a batch orchestrator)
2. After the item summary is displayed, verify the agent suggests running a retrospective
3. Decline the suggestion
4. Verify the agent closes without running the retrospective

**Expected result**: Retrospective is suggested for standalone item runs; skipped when declined.

### Step 8: Protocol 91 Integration — Batched Item Suppression

**Maps to**: Acceptance Criterion 10

1. Run a batch orchestration session that dispatches at least one item via the Work Item Runner with `BATCH_CONTEXT=true`
2. After the dispatched item completes, verify the Work Item Runner does NOT suggest a retrospective
3. Verify the batch orchestrator (Protocol 90) suggests the retrospective instead (per Step 6)

**Expected result**: Retrospective suggestion is suppressed for batched items; only the batch orchestrator suggests it.

### Step 9: Same-Session Conversation Context

**Maps to**: Acceptance Criterion 8

1. During the retrospective in Step 6 or Step 7, verify findings include items sourced from conversation history (manual interventions, human corrections, agent deviations) in addition to GitHub data
2. Verify findings indicate their source (GitHub data only, or both GitHub and conversation context)

**Expected result**: Conversation-context findings are present when the retrospective runs in the same session as completed work.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: A developer can invoke `/retrospective` in a fresh session and receive categorized improvement opportunities from GitHub PR data
- [ ] AC 2: When GitHub data is insufficient, the agent communicates "no findings" and closes gracefully
- [ ] AC 3: Each opportunity is labeled with category, severity signal, and recommended action
- [ ] AC 4: The developer can choose "Address now", "Add to backlog", or skip for each opportunity
- [ ] AC 5: "Address now" for a simple fix: agent applies, commits, pushes without new PR
- [ ] AC 6: "Address now" for a complex fix: agent recommends "Add to backlog" instead with explanation
- [ ] AC 7: "Add to backlog": agent creates GitHub issue directly and returns URL
- [ ] AC 8: Same-session retrospective surfaces conversation-context findings alongside GitHub findings
- [ ] AC 9: Protocol 90 suggests retrospective after Step 6 batch summary
- [ ] AC 10: Protocol 91 suggests retrospective after item summary only for standalone runs (not batched)
- [ ] AC 11: `/retrospective` command/skill is available in Claude Code, Cursor, and Codex
- [ ] AC 12: Agent never applies fixes or creates issues without human's explicit choice

---

## Known Limitations

- Step 4 (complex finding) depends on the retrospective surfacing a finding that is too complex; if all findings are simple, this step cannot be validated and should be marked N/A
- Steps 6-8 require running full orchestration sessions, which may take significant time; these can be tested opportunistically during normal workflow usage rather than in a dedicated smoke test session
- Conversation-context analysis quality depends on the richness of the conversation history in the current session
