# Retrospective Protocol — Implementation Plan

**Spec**: [1_retrospective-protocol_specs.md](1_retrospective-protocol_specs.md)
**Smoke test runbook**: [retrospective-protocol.smoke-test.md](../../testing/workflow/retrospective-protocol.smoke-test.md)

---

## Summary

**Approach**: Add a new protocol document (`06-retrospective-protocol.md`) that defines the retrospective analysis flow, then integrate suggestion hooks into Protocols 90 and 91 at their Step 6 summary points. Create the `/retrospective` command/skill across all three supported platforms (Claude Code, Cursor, Codex) following the existing patterns for each. Finally, update the workflow README and AGENTS.md to reference the new protocol and command.

**Estimated complexity**: S
<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->
**Rationale**: All deliverables are Markdown documentation and platform configuration files. No code, database, or infrastructure changes. All platform patterns (Claude Code commands, Cursor agents, Codex skills) are well-established and can be copied from existing examples.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Protocol Document

- [ ] Create `docs/ai/development-workflow/protocols/06-retrospective-protocol.md` — the core retrospective protocol document covering:
  - Protocol metadata (agent role, purpose)
  - Step 1: Resolve scope — determine which PRs to analyze (from scope hint, current session, or recent repo PRs)
  - Step 2: Gather data — query GitHub PR metadata (review cycles, finding types, labels, merge conflicts) and git history (commit patterns, fix-commit ratio); when conversation context is available, also analyze manual interventions, human corrections, agent deviations
  - Step 3: Synthesize findings — categorize improvement opportunities using the fixed taxonomy (`workflow-process`, `agent-behavior`, `configuration`, `documentation`, `code-quality`, `tooling`), assign severity signals (`high`, `medium`, `low`), and recommend an action for each
  - Step 4: Present and act — show categorized findings to the human; for each, accept the human's choice of "Address now", "Add to backlog", or "Skip"; execute the chosen action
  - Step 5: Execute actions — "Address now": apply simple fix, commit, push (no new PR or review loop); "Add to backlog": create GitHub issue directly via `gh issue create` (not through `00-add-backlog-item-protocol.md`); "Skip": move on
  - Step 6: Close — confirm what was done and end the retrospective
  - Graceful exit when no actionable findings are surfaced
  - Constraint: the agent never applies fixes or creates issues without the human's explicit choice
  - Maps to: AC 1, 2, 3, 4, 5, 6, 7, 8, 12

### Integration into Existing Protocols

- [ ] Update `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — add a retrospective suggestion at the end of Step 6 (after the batch summary), with text like: *"Would you like to run a retrospective on this session's work?"* If the human agrees, follow `06-retrospective-protocol.md`. Maps to: AC 9
- [ ] Update `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — add a retrospective suggestion at the end of Step 6 (after the item summary), conditioned on the item being run standalone (not dispatched by a batch orchestrator via `BATCH_CONTEXT=true`). When `BATCH_CONTEXT=true`, suppress the suggestion to avoid double-triggering. Maps to: AC 10

### Platform Commands / Skills

- [ ] Create `.claude/commands/retrospective.md` — Claude Code command following the pattern of existing commands (e.g., `run-reviewer-loop.md`). Points to `06-retrospective-protocol.md` as the canonical source. Maps to: AC 11
- [ ] Create `.cursor/agents/retrospective.md` — Cursor agent following the pattern of existing agents (e.g., `orchestrator.md`). Points to `06-retrospective-protocol.md`. Maps to: AC 11
- [ ] Create `.codex/skills/workflow-retrospective/SKILL.md` — Codex skill following the pattern of existing skills (e.g., `workflow-reviewer-loop/SKILL.md`). Points to `06-retrospective-protocol.md`. Maps to: AC 11
- [ ] Create `.codex/skills/workflow-retrospective/agents/openai.yaml` — Codex agent metadata following the pattern of existing agents. Maps to: AC 11

---

## Testing Strategy

**Test types**: Smoke / Manual

**Key scenarios to test**:
1. Invoke `/retrospective` in a fresh session with no scope hint — verify the agent queries recent PRs, presents categorized findings (or closes gracefully if none), and respects the human's choice for each (AC 1, 2, 3, 4, 12)
2. Invoke `/retrospective` with a specific PR number as scope hint — verify findings are scoped to that PR (AC 1)
3. Choose "Address now" for a simple finding — verify fix is applied, committed, and pushed without a new PR (AC 5)
4. Choose "Address now" for a complex finding — verify agent recommends "Add to backlog" instead and explains why (AC 6)
5. Choose "Add to backlog" for a finding — verify a GitHub issue is created with descriptive title/body and the URL is returned (AC 7)
6. Complete a batch run via Protocol 90 and verify retrospective is suggested after the batch summary (AC 9)
7. Complete a standalone item run via Protocol 91 and verify retrospective is suggested after the item summary (AC 10)
8. Complete a dispatched (non-standalone) item run via Protocol 91 and verify retrospective is NOT suggested (AC 10)
9. Run retrospective in the same session as a completed batch/item and verify conversation-context findings are surfaced alongside GitHub findings (AC 8)

**Smoke test runbook**: [`docs/testing/workflow/retrospective-protocol.smoke-test.md`](../../testing/workflow/retrospective-protocol.smoke-test.md)

---

## Seed Data

No seed data is required. The retrospective protocol operates on existing GitHub PR data and git history already present in the repository.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/README.md` — add `06-retrospective-protocol.md` to the Core Protocols list and add a `/retrospective` row to the Commands By Stage table
- [ ] `AGENTS.md` — add a `/retrospective` row to the Workflow Commands table and the Maintenance Commands or a new "Analysis" section

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Protocol 90/91 integration text conflicts with other in-flight changes | Low | Low | Changes are additive (appended to existing Step 6 sections); merge conflicts are easy to resolve |
| "Address now" action could make unintended changes | Low | Medium | Protocol explicitly constrains "Address now" to simple, self-assessed-safe changes; complex items redirect to backlog |

---

## Implementation Order

1. Create `docs/ai/development-workflow/protocols/06-retrospective-protocol.md` — the core protocol document
2. Update `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — add retrospective suggestion to Step 6
3. Update `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — add retrospective suggestion to Step 6 (with `BATCH_CONTEXT` guard)
4. Create `.claude/commands/retrospective.md` — Claude Code command
5. Create `.cursor/agents/retrospective.md` — Cursor agent
6. Create `.codex/skills/workflow-retrospective/SKILL.md` and `.codex/skills/workflow-retrospective/agents/openai.yaml` — Codex skill
7. Update `docs/ai/development-workflow/README.md` — add protocol and command references
8. Update `AGENTS.md` — add `/retrospective` to workflow commands table
9. Verify smoke test runbook
10. Update CHANGELOG
