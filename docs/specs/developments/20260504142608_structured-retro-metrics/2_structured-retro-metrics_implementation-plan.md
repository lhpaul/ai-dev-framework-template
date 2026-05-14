# Structured Retro Metrics and Meta-Retrospective Protocol — Implementation Plan

**Spec**: [1_structured-retro-metrics_specs.md](./1_structured-retro-metrics_specs.md)
**Smoke test runbook**: [../../../testing/workflow/458-structured-retro-metrics.smoke-test.md](../../../testing/workflow/458-structured-retro-metrics.smoke-test.md)

---

## Summary

**Approach**: Add a required metrics block step to the existing `06-retrospective-protocol.md` and create a new `06b-meta-retrospective-protocol.md` file. Create the initial `docs/workflow/retro-metrics.md` tracking file. Update all agent, skill, and documentation files that reference the retrospective protocol so they are aware of the new metrics step and the meta-retrospective protocol.

**Estimated complexity**: M

**Rationale**: The work is entirely documentation and protocol changes — no code, no database, no infrastructure. All changes are additions or extensions to existing Markdown files. The moderate complexity comes from touching multiple files (protocol, agents, skills, workflow README, model-config doc) and from carefully integrating the metrics block into the existing six-step protocol without breaking its structure.

**Dependencies**: None

---

## Verification Log

| Check                                    | Command / query                                                                                                                                    | Result                                                                                                                           |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Repo revision                            | `git rev-parse --short HEAD`                                                                                                                       | `ff2a19c`                                                                                                                        |
| Files referencing retrospective protocol | `grep -rl "06-retrospective-protocol\|retrospective" .claude/agents/ .cursor/agents/ .codex/skills/ docs/workflow/development-workflow/ CLAUDE.md` | 11 files (see Layer-by-Layer Changes)                                                                                            |
| Existing meta-retrospective file         | `ls docs/workflow/development-workflow/protocols/ \| grep -E "06b\|meta"`                                                                          | none — file does not yet exist                                                                                                   |
| Existing retro-metrics log               | `ls docs/workflow/ \| grep retro`                                                                                                                  | none — file does not yet exist                                                                                                   |
| Smoke test location                      | `ls docs/testing/workflow/`                                                                                                                        | 19 existing `.smoke-test.md` files; new file will be added at `docs/testing/workflow/458-structured-retro-metrics.smoke-test.md` |

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

Not applicable — this is a protocol and documentation feature.

### Infrastructure / Configuration

Not applicable.

### Documentation / Protocol Layer

All changes are Markdown file additions or modifications.

#### New files

- [ ] `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` — full meta-retrospective procedure (scope resolution, trend analysis, classification table, escalation, human-approval gate). See Implementation Order Step 2 for required content.
- [ ] `docs/workflow/retro-metrics.md` — initial metrics tracking file with column headers matching the required metrics block fields. Seeded with column headers only (no data rows); will be populated by real retrospective runs after this feature ships.
- [ ] `docs/testing/workflow/458-structured-retro-metrics.smoke-test.md` — smoke test runbook (created in Step 4 of this protocol).

#### Modified files

- [ ] `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` — insert new Step 3d (Metrics Block) between existing Step 3 and Step 4; update Step 6 (Close) to include the append instruction to `docs/workflow/retro-metrics.md`; add a closing reference to `06b-meta-retrospective-protocol.md`.
- [ ] `docs/workflow/development-workflow/README.md` — add row for meta-retrospective in the Workflow Commands table and note about the periodic verification protocol.
- [ ] `.claude/agents/retrospective.md` — extend the Key responsibilities bullet list to mention the metrics block step and meta-retrospective protocol.
- [ ] `.cursor/agents/retrospective.md` — same update as `.claude/agents/retrospective.md`.
- [ ] `.codex/skills/workflow-retrospective/SKILL.md` — add step referencing the metrics block and the meta-retrospective skill.
- [ ] `CLAUDE.md` (symlink to `AGENTS.md`) — update the Retrospective row in the Workflow Commands table to note `06b-meta-retrospective-protocol.md` for the on-demand meta-retrospective command.

#### Files inspected and confirmed not requiring changes

- `docs/workflow/development-workflow/agent-model-config.md` — no new agent role introduced; the same `retrospective` agent runs both protocols.
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — references retrospective suggestion timing; no change needed (timing rules are not affected by adding a metrics block).
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — references retrospective suggestion; no change needed.
- `.codex/skills/post-merge-cleanup/SKILL.md` — references retrospective suggestion; no change needed (suggestion wording is not affected).
- `.codex/skills/workflow-retrospective/agents/openai.yaml` — metadata file; no change needed (skill name and description are unchanged).

---

## Testing Strategy

**Test types**: Manual (smoke test). No automated tests apply — this feature adds protocol documentation only.

**Key scenarios to test**:

1. Metrics block required in every retrospective — maps to Acceptance Criterion 1, 2, 3 (BR-1, BR-6, BR-7)
2. Append metrics block to `docs/workflow/retro-metrics.md` after Step 5 — maps to Acceptance Criterion 3 (BR-2)
3. Meta-retrospective reads log entries and produces trend table and classification — maps to Acceptance Criterion 4, 5, 6
4. Meta-retrospective handles fewer-than-window entries gracefully — maps to Acceptance Criterion 6 (partial data note) and Acceptance Criterion 9
5. Escalated "Still recurring" items create backlog entries — maps to Acceptance Criterion 4 (BR-4)
6. `06-retrospective-protocol.md` references `06b-meta-retrospective-protocol.md` in closing section — maps to Acceptance Criterion 8

**Smoke test runbook**: `docs/testing/workflow/458-structured-retro-metrics.smoke-test.md`

**Regression suite**: No automated regression suite exists in this repository. Smoke test only.

---

## Seed Data

Not applicable — this feature introduces no data model or application state. The metrics log file (`docs/workflow/retro-metrics.md`) is created with headers only.

| Entity              | Values / Scenario                 | File                             |
| ------------------- | --------------------------------- | -------------------------------- |
| Initial metrics log | Column headers only, no data rows | `docs/workflow/retro-metrics.md` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/README.md` — add Workflow Commands row for meta-retrospective trigger; this is done as part of implementation (see Layer-by-Layer Changes).
- [ ] `AGENTS.md` (via `CLAUDE.md` symlink) — update Retrospective row; this is done as part of implementation (see Layer-by-Layer Changes).

All other documentation updates are the implementation itself (the protocol files are the feature). No additional project or architecture docs (`docs/project/`) need updating — this feature adds no new runtime components, no new dependencies, and no architecture changes.

---

## Risks & Mitigations

| Risk                                                                             | Likelihood | Impact | Mitigation                                                                                                                               |
| -------------------------------------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Metrics block step disrupts existing retro protocol structure                    | Low        | Medium | Insert as Step 3d (a sub-step of existing Step 3), keeping Steps 4–6 numbering unchanged; re-read the protocol before committing         |
| `docs/workflow/retro-metrics.md` path conflicts with a planned sister item       | Low        | Low    | Verify path is not claimed by any other in-flight branch before pushing                                                                  |
| Agent files reference the old six-step protocol numbering explicitly             | Low        | Medium | Inspect each agent/skill file for hard-coded step references before updating                                                             |
| Missing fields in metrics block definition lead to ambiguous entries             | Low        | High   | Define all required fields with precise, unambiguous names and units in the protocol text; replicate from the spec's Acceptance Criteria |
| Meta-retrospective classified "Still recurring" triggers unnecessary escalations | Low        | Low    | Protocol explicitly states directional analysis only; analyst must not overstate confidence (BR-8 cadence is advisory)                   |

---

## Implementation Order

1. **Create `docs/workflow/retro-metrics.md`** with the initial column headers matching the required metrics block fields (batch identifier, human interventions count, Step 5.2 violations count, automated-reviewer retry loops count, escalations count, prior action item recurrence assessment). Add a brief preamble explaining the file's purpose (append-only log, one entry per completed retrospective).

   Verify: file exists at `docs/workflow/retro-metrics.md`, opens without lint errors, headers match the field list from spec Acceptance Criterion 1.

2. **Create `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`** with the following required sections:
   - **Header**: role = Retrospective Analyst, purpose = periodic verification of prior improvement effectiveness
   - **Prerequisites**: metrics log exists at `docs/workflow/retro-metrics.md`; at least one prior retrospective entry present (if fewer than default window size, note limited data and proceed)
   - **Step 1: Resolve Scope** — read N most recent entries from `docs/workflow/retro-metrics.md`; default window = 5; document how to override (human passes a number at invocation)
   - **Step 2: Trend Analysis** — build trend table with batch identifiers across columns, tracked metrics as rows, values filled from the log
   - **Step 3: Classify Prior Action Items** — for each action item recorded in the window, assign one outcome: "Verified fixed" (failure mode absent in all subsequent batches), "Partially fixed" (reduced frequency), "Still recurring" (same or higher frequency)
   - **Step 4: Escalation** — for each "Still recurring" item, draft an escalated finding at severity "high" to include in the next regular retrospective; explicitly note that one clean batch is not sufficient to classify as "Verified fixed"
   - **Step 5: Human Review Gate** — present the classification table and escalated findings to the human; wait for approval before writing to the backlog
   - **Step 6: Backlog Update** — for each human-approved escalated finding, create a backlog item using the same `gh issue create` flow as `06-retrospective-protocol.md` Step 5 (Add to backlog)
   - **Constraints**: protocol must not edit historical entries in `docs/workflow/retro-metrics.md` (BR-5); trend data is directional, not statistically rigorous (must be stated in Step 4 guidance)
   - **Analysis window override**: document that the human passes an explicit number (e.g., "run meta-retro on the last 10 entries") and the analyst uses that count

   Verify: file exists at the correct path, Steps 1 through 6 are all present, analysis window default of 5 is documented, "Still recurring" escalation severity is stated as "high".

3. **Update `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`**:

   a. After existing Step 3c (Categorization taxonomy), insert **Step 3d: Populate Metrics Block**. Content must include:
   - Instruction: after completing Steps 3a–3c, fill in the required metrics block
   - Required fields with unambiguous definitions:
     - **Batch identifier**: the PR numbers or batch date used as the scope in Step 1
     - **Human interventions count**: number of moments where the human had to correct the agent's direction mid-run (source: Step 2c or PR events)
     - **Step 5.2 violations count**: number of instances where the automated reviewer found a Step 5.2 (PR-readiness) violation (source: PR comments)
     - **Automated-reviewer retry loops count**: number of additional pr-review-loop iterations beyond the first pass (source: PR comment timestamps)
     - **Escalations count**: number of items that escalated past the automated retry limit (source: PR labels or conversation notes)
     - **Prior action item recurrence assessment**: for each open action item from prior retrospectives whose targeted failure mode was observable in this batch, record "recurred" or "did not recur" (source: comparison with prior retrospective output)
   - "Unavailable" rule: if a field cannot be reliably determined from available data, record "unavailable" (not blank, not a guess) — BR-7
   - Zero is a valid value — BR-1
   - The metrics block is part of the retrospective output presented in Step 4

   b. Update **Step 4** to include the metrics block in the structured output format (alongside improvement opportunities). The block may be presented as a separate section after improvement opportunities.

   c. Update **Step 6 (Close)** to add: after confirming all opportunities have been acted on, append the finalized metrics block to `docs/workflow/retro-metrics.md` (create the file if it does not exist). Instruction should specify the Markdown table row format matching the column headers in that file.

   d. At the end of the file (after the Step 6 close section), add a **"See also"** reference:

   > For periodic verification of whether prior improvement action items are working, run the meta-retrospective protocol: `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`. Recommended cadence: every 5 batches. Can be triggered at any time.

   Verify: Step 3d exists between Steps 3c and Step 4; Step 6 includes append instruction; "See also" section references `06b-meta-retrospective-protocol.md`; no existing step numbering is broken.

4. **Update `.claude/agents/retrospective.md`** — add to the Key responsibilities bullets:
   - "After synthesizing findings (Step 3), populate the required metrics block (Step 3d): batch identifier, human interventions, Step 5.2 violations, retry loops, escalations, and prior action item recurrence. Record 'unavailable' for any field that cannot be reliably determined."
   - "After executing Step 5 actions, append the finalized metrics block to `docs/workflow/retro-metrics.md`."
   - "For periodic effectiveness verification, use `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`."

   Verify: agent file describes metrics block as part of retrospective flow; meta-retrospective protocol path is referenced.

5. **Update `.cursor/agents/retrospective.md`** — mirror the same additions made in Step 4.

   Verify: cursor agent matches claude agent description for metrics block and meta-retrospective reference.

6. **Update `.codex/skills/workflow-retrospective/SKILL.md`** — add two items to the numbered step list:
   - After the "Synthesize findings" step: "After synthesizing findings, populate the required metrics block (see Step 3d in the protocol): batch identifier, human interventions count, Step 5.2 violations count, automated-reviewer retry loops count, escalations count, prior action item recurrence. Record 'unavailable' for any field that cannot be reliably determined."
   - After the confirmation summary step: "After all opportunities are acted on, append the finalized metrics block to `docs/workflow/retro-metrics.md` as a new table row."

   Verify: SKILL.md references metrics block and append step.

7. **Update `docs/workflow/development-workflow/README.md`** — in the Workflow Commands table, add a new row for the meta-retrospective:

   | Meta-Retrospective | — (use `/retrospective` with meta flag or invoke directly) | — | `workflow-retrospective` skill | Follow `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` |

   Verify: README table has the meta-retrospective row; relative link to `06b-meta-retrospective-protocol.md` is correct from the README file location.

8. **Update `CLAUDE.md`** (via symlink `AGENTS.md`) — in the Workflow Commands table, update the Retrospective row to add a note that `06b-meta-retrospective-protocol.md` handles the periodic meta-retrospective, or add a separate row. Match the README style from Step 7.

   Verify: AGENTS.md/CLAUDE.md references `06b-meta-retrospective-protocol.md`.

9. **Cross-section consistency self-check** — before committing, verify that the field names defined in Step 3d of `06-retrospective-protocol.md`, the column headers in `docs/workflow/retro-metrics.md`, and the field descriptions in `06b-meta-retrospective-protocol.md` all use identical names and definitions. Any discrepancy will cause ambiguous entries in the metrics log.

10. **Run pre-commit lint check**:

    ```bash
    REPO_ROOT=$(git rev-parse --git-common-dir)/..
    "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
      "docs/specs/developments/20260504142608_structured-retro-metrics/2_structured-retro-metrics_implementation-plan.md" \
      "docs/testing/workflow/458-structured-retro-metrics.smoke-test.md" \
      "docs/workflow/development-workflow/protocols/06-retrospective-protocol.md" \
      "docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md" \
      "docs/workflow/retro-metrics.md"
    ```

    Fix any reported violations before committing.

11. **Verify smoke test runbook** — confirm all acceptance criteria have at least one testable step in the runbook.

12. **Update CHANGELOG.md** under `[Unreleased]`:

    ```
    - **Add structured retro metrics and meta-retrospective protocol** (#458): Adds a required metrics block step to the retrospective protocol and a new `06b-meta-retrospective-protocol.md` for periodic verification of improvement effectiveness, along with the initial `docs/workflow/retro-metrics.md` tracking log.
    ```
