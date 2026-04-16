# Agent Timeout Handling — Implementation Plan

**Spec**: [`1_agent-timeout-handling_specs.md`](./1_agent-timeout-handling_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/agent-timeout-handling.smoke-test.md`](../../../../testing/workflow/agent-timeout-handling.smoke-test.md)

---

## Summary

**Approach**: This is a documentation-only change across three protocol/config files. The work adds explicit timeout-handling guidance to `agent-model-config.md` (expected run durations + resume runbook), adds a stale-PR detection heuristic to `90-batch-orchestrate-work-protocol.md`, and confirms/strengthens the reviewer loop summary comment check already in Step 8c of `91-orchestrate-work-protocol.md`.

**Estimated complexity**: S
<!-- S: < 1 day -->
**Rationale**: All five acceptance criteria map to targeted additions inside existing protocol documents. No code, scripts, or CI changes are required. The largest single addition is the resume runbook section in `agent-model-config.md` (~30–40 lines).

**Dependencies**: None

---

## Layer-by-Layer Changes

### Documentation / Protocol Layer

- [ ] **`docs/ai/development-workflow/agent-model-config.md`** — Add an "Expected Run Durations" subsection under the Agent Assignments table that documents typical and maximum run durations for `item-orchestrator` and `automated-reviewer-loop` agents. (Acceptance Criterion 2)
- [ ] **`docs/ai/development-workflow/agent-model-config.md`** — Add a "Resume a Timed-Out Agent Run" section that covers: (a) how to detect an incomplete run (checklist of signals: labels, review summary comment, CI state), (b) the command to resume (`workflow-next-action.sh --pr <N>` or re-invoking the item-orchestrator), and (c) an explicit warning not to manually apply `ready-for-human-review` without completing the review loop. (Acceptance Criterion 3)
- [ ] **`docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`** — Confirm that Step 8c's reviewer loop summary comment check is clearly stated and explicitly marked as non-removable by an agent. Add a brief explanatory note to the existing check row in the Step 8c table. (Acceptance Criterion 1)
- [ ] **`docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`** — Add a "Stale / Incomplete PR Detection" subsection to Step 5.1 (Post-Dispatch PR Verification) that documents the detection heuristic (non-draft, readiness labels present, review summary comment absent → incomplete), the manual detection command, and the action to take (re-dispatch item-orchestrator to resume from Step 7). (Acceptance Criterion 4)

---

## Testing Strategy

**Test types**: Manual (document review only — no runnable code)

**Key scenarios to test**:
1. Reviewer reads `agent-model-config.md` and can find the resume guide within 30 seconds — maps to Acceptance Criterion 3 (UX rule: scannable in under 30 seconds)
2. All four acceptance criteria are verified by inspecting the changed files — maps to Acceptance Criteria 1–4
3. Acceptance Criterion 5 (documentation-only) is satisfied by confirming no code/script/CI files were changed — maps to Acceptance Criterion 5

**Smoke test runbook**: [`docs/testing/workflow/agent-timeout-handling.smoke-test.md`](../../../../testing/workflow/agent-timeout-handling.smoke-test.md)

**Regression suite**: No regression suite exists in this repository.

---

## Seed Data

None — this feature is documentation-only and requires no seed data.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/agent-model-config.md` — Updated as part of this implementation (Acceptance Criteria 2 and 3). This is the primary output of the feature; no separate post-implementation update is needed.
- [ ] `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — Updated as part of this implementation (Acceptance Criterion 1).
- [ ] `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — Updated as part of this implementation (Acceptance Criterion 4).

No other `docs/project/` files, `AGENTS.md`, or `docs/best-practices/` files require changes — this feature is scoped to AI workflow protocol documents.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Open question: resume section location (`agent-model-config.md` vs. dedicated runbook) | Low | Low | Spec Open Question 1 defers to this plan. Place the section in `agent-model-config.md` for discoverability — it is the document operators already consult for agent behavior. Link it from the "Expected Run Durations" subsection so operators encounter it naturally. A dedicated runbook adds a navigation hop with no benefit for an initial MVP section. |
| Reviewer loop summary check in Step 8c could be ambiguously worded | Low | Med | The implementation step explicitly reviews and, if needed, strengthens the wording of the existing check — not just confirms it exists. |
| Changes to protocol documents could introduce cross-reference inconsistencies | Low | Low | The implementation order requires a final cross-read of all three files after edits to verify references and wording are consistent. |

---

## Implementation Order

1. Read `docs/ai/development-workflow/agent-model-config.md` in full to understand the current structure and identify the correct insertion point for the new sections.
2. Add the "Expected Run Durations" subsection to `agent-model-config.md` immediately after the Agent Assignments table. Include a two-column table: `item-orchestrator` (typical 5–15 min; consider timeout at ~25 min) and `automated-reviewer-loop` (typical 2–10 min; consider timeout at ~20 min).
3. Add the "Resume a Timed-Out Agent Run" section to `agent-model-config.md`, immediately after the "Expected Run Durations" subsection. Include: (a) detection checklist (non-draft PR, some labels applied, reviewer loop summary comment absent, CI incomplete), (b) resume command (`./scripts/development-workflow/workflow-next-action.sh --pr <N>` or re-invoking the item-orchestrator), and (c) bold warning not to manually apply `ready-for-human-review` without completing Step 7.
4. Read Step 8c of `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`. Verify the reviewer loop summary comment check row in the table is explicitly stated and clear. Add a note below the table row — or update the wording — to explicitly state that this check is a hard requirement that must not be removed by agents applying fixes.
5. Read Step 5.1 of `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`. Add a "Stale / Incomplete PR Detection" subsection after the main verification table. The subsection must include: the detection heuristic, a one-line detection shell command (using `gh pr view --json` to check for label+comment state), and the required action (re-dispatch item-orchestrator to resume from Step 7).
6. Cross-read all three updated files for consistency: confirm references between them are accurate, no wording contradicts the spec's business rules, and each section satisfies its mapped acceptance criterion.
7. Verify smoke test runbook is complete and maps to all acceptance criteria. (Note: CHANGELOG update is not required — plan-only PRs are exempt per `docs/best-practices/2-version-control.md`.)

---

## Code Samples

No code samples — this plan is documentation-only.
