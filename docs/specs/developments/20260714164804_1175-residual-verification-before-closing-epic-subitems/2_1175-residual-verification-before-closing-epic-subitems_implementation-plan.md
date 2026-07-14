# Residual Verification Before Closing Epic Sub-items - Implementation Plan

**Spec**: [1_1175-residual-verification-before-closing-epic-subitems_specs.md](1_1175-residual-verification-before-closing-epic-subitems_specs.md)
**Smoke test runbook**: [1175-residual-verification-before-closing-epic-subitems.smoke-test.md](../../../testing/workflow/1175-residual-verification-before-closing-epic-subitems.smoke-test.md)

---

## Summary

**Approach**: Add a template-generic residual verification gate to the workflow readiness path. The implementation will introduce a small deterministic helper that classifies broad-scope issue briefs, requires visible residual evidence before readiness, and blocks `ready-for-human-review` when residual groups lack a completed, out-of-scope, or linked-follow-up disposition.

**Estimated complexity**: M

**Rationale**: The change is mostly workflow shell and documentation, but it touches cross-cutting orchestration paths, reviewer expectations, and parser-risk classification over issue text and evidence summaries.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `d26edf45de5fbc7a95313ba087ad95130b88cb65` |
| Existing artifact state | `find docs/specs/developments/20260714164804_1175-residual-verification-before-closing-epic-subitems -maxdepth 1 -type f -print \| sort` | Spec exists; plan file did not exist before this branch. |
| Cross-cutting agent and skill references | `grep -rl "02-generate-implementation-plan-protocol\\|03-implement-development-protocol\\|91-orchestrate-work-protocol\\|95-run-epic-protocol\\|ready-for-human-review" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ 2>/dev/null \| sort` | Found 22 agent/skill files that reference affected stages or readiness labels; applicable files are enumerated below. |
| Readiness and completion surface | `rg -l "ready-for-human-review\|reviewThreads\|Automated Reviewer Loop Summary\|Label Readiness Checklist\|Plan in Review\|Development in Review\|completion gate\|epic ledger\|sub-item\|sub-issue\|batch" docs/workflow/development-workflow/protocols scripts/development-workflow .claude/agents .cursor/agents .codex/skills .agents/skills REVIEW.md \| sort` | Confirmed the affected surface spans Protocols 90, 91, 92, 95, reviewer-loop/CI readiness docs, agent guidance, skills, and run-epic audit helpers. |
| Existing workflow script tests | `find scripts/development-workflow/tests -maxdepth 2 -type f -print \| sort` | Existing test harness directory contains workflow shell tests including `test-pr-review-loop.sh`, `test-run-epic-audit-trail.sh`, `test-run-epic-scope-resolver.sh`, and `test-run-item-scope-resolver.sh`; add the residual gate tests there. |
| Template-fit check | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; the spec is template-generic because it changes shipped workflow protocols and scripts, not a downstream app stack. |

---

## Layer-by-Layer Changes

### Workflow Script Layer

- [ ] Add `scripts/development-workflow/scope-residual-gate.sh` to perform the residual gate as a deterministic, template-generic helper.
- [ ] Support a read-only classification mode that identifies broad-scope work from issue title/body text using anchored, documented patterns for sweep, batch, helper extraction, numeric counts, "all", "across", and multiple named targets. Maps to BO-1, BR-2, AC-1, AC-7, and AC-8.
- [ ] Support an evidence validation mode that consumes explicit residual evidence supplied by the runner or implementer. The evidence should be structured JSON where practical, with text summary fallback only for human-readable output. Maps to BO-2 through BO-6 and BR-1 through BR-6.
- [ ] Require each residual group to have one disposition: `completed`, `out_of_scope`, or `follow_up`. For `follow_up`, require a linked issue reference such as `#123` or a provider-native tracker URL. Maps to BR-5, BR-6, BR-8, AC-3, and AC-4.
- [ ] Add helper-extraction checks that flag newly created helper outputs with no apparent caller evidence in the supplied summary. The helper must not attempt perfect semantic dead-code detection; it should block only when the evidence reports no apparent callers or omits caller evidence for helper-extraction work. Maps to BO-4, BR-7, and AC-5.
- [ ] Emit stable key/value output for orchestrators, including `RESULT=pass|block|escalate|not_applicable`, `SCOPE_CLASSIFICATION=...`, `RESIDUAL_GROUPS=...`, `FOLLOW_UPS=...`, and a human-readable summary block. Maps to BO-6, BR-4, AC-2, AC-3, AC-4, AC-6, and AC-8.
- [ ] Keep the helper read-only: no label changes, tracker updates, issue creation, branch changes, PR comments, or file edits.

### Orchestration Protocol Layer

- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` so Step 8a runs the residual gate before applying `ready-for-human-review` for applicable sweep, batch, and helper-extraction items. Maps to BR-1, BR-3, BR-4, AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, and AC-7.
- [ ] Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` so epic runs include residual gate status in per-item and epic ledger summaries, and do not treat an epic sub-item as ready when the gate blocks or escalates. Maps to BO-7, Operational Visibility, and AC-8.
- [ ] Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` so explicit-list batches inherit the same residual gate before each in-scope PR is reported terminal at `ready-for-human-review`. Maps to BO-1, BO-2, and AC-8.
- [ ] Update `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` so readiness signaling treats a blocking residual gate as a `needs-fixes` or human-decision condition, not as a clean handoff. Maps to BR-5, BR-6, and AC-3.
- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` so implementation agents for sweep, batch, or helper-extraction items must produce residual evidence before their PR can pass readiness. Maps to BR-1 through BR-9.
- [ ] Update `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` with a brief planning note that sweep, batch, and helper-extraction implementation plans should name the residual verification strategy and evidence source. This prevents future plans from omitting the evidence mechanism. Maps to BO-2, BR-4, and AC-1.

### Review and Agent Guidance Layer

- [ ] Update `REVIEW.md` so reviewers flag applicable workflow PRs that can reach `ready-for-human-review` without residual gate evidence or with residuals silently deferred in prose. Maps to BR-3, BR-4, BR-8, and AC-3.
- [ ] Update `.claude/agents/developer.md` and `.cursor/agents/developer.md` to instruct implementation agents to produce residual evidence for sweep, batch, and helper-extraction items.
- [ ] Update `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` to require the residual gate before readiness handoff.
- [ ] Update `.claude/agents/orchestrator.md` and `.cursor/agents/orchestrator.md` so batch supervision recognizes residual-gate block/escalation outcomes.
- [ ] Update `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, and `.codex/skills/workflow-orchestrator/SKILL.md` for Codex parity.
- [ ] Update `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-items/SKILL.md`, `.agents/skills/run-epic/SKILL.md`, and `.agents/skills/run-items/agents/openai.yaml` / `.agents/skills/run-epic/agents/openai.yaml` where they summarize terminal readiness behavior.
- [ ] Update `.codex/skills/batch-merge/SKILL.md` only if the implementation adds a pre-merge safety reminder for stale `ready-for-human-review` labels. Do not make batch merge rerun the residual gate unless Protocol 94 explicitly adopts that behavior.

### Documentation Layer

- [ ] Update `scripts/development-workflow/README.md` to list the new helper, its read-only contract, and example invocations.
- [ ] Update `docs/testing/workflow/1175-residual-verification-before-closing-epic-subitems.smoke-test.md` during implementation if final helper names or outputs differ from this plan.
- [ ] Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR, not in this plan PR.

### Database / Data Layer

- [ ] None. This workflow feature does not add persistent storage or migrations.

### Backend / API

- [ ] None. No HTTP or service API changes are required.

### Frontend / UI

- [ ] None. No user interface changes are required.

### Infrastructure / Configuration

- [ ] None. The gate should work with the existing GitHub/CLI workflow configuration and should not require new environment variables.

---

## Cross-Cutting Checklist Impact

This plan introduces a cross-cutting completion-quality gate that can apply to many independent workflow items. The implementation must update every affected guidance surface rather than only the shell helper.

**Files to modify**:

- `scripts/development-workflow/scope-residual-gate.sh` - new read-only residual gate helper.
- `scripts/development-workflow/tests/test-scope-residual-gate.sh` - new shell test coverage.
- `scripts/development-workflow/README.md` - helper documentation.
- `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` - planning guidance for residual evidence strategy.
- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` - implementation evidence requirement.
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` - explicit-list batch terminal-state handling.
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` - single-item readiness gate.
- `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` - readiness signal interpretation.
- `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` - epic audit and ledger behavior.
- `REVIEW.md` - reviewer expectations.
- `.claude/agents/developer.md` - Claude implementation guidance.
- `.cursor/agents/developer.md` - Cursor implementation guidance.
- `.claude/agents/item-orchestrator.md` - Claude item-runner guidance.
- `.cursor/agents/item-orchestrator.md` - Cursor item-runner guidance.
- `.claude/agents/orchestrator.md` - Claude batch-runner guidance.
- `.cursor/agents/orchestrator.md` - Cursor batch-runner guidance.
- `.codex/skills/workflow-implementer/SKILL.md` - Codex implementation guidance.
- `.codex/skills/workflow-item-orchestrator/SKILL.md` - Codex item-runner guidance.
- `.codex/skills/workflow-orchestrator/SKILL.md` - Codex batch-runner guidance.
- `.agents/skills/run-item/SKILL.md` - command-style item runner guidance.
- `.agents/skills/run-items/SKILL.md` - command-style explicit batch guidance.
- `.agents/skills/run-items/agents/openai.yaml` - command-style explicit batch default prompt.
- `.agents/skills/run-epic/SKILL.md` - command-style epic runner guidance.
- `.agents/skills/run-epic/agents/openai.yaml` - command-style epic default prompt.
- `CHANGELOG.md` - implementation PR entry under `[Unreleased]`.

**Files verified but not expected to change**:

- `.codex/skills/batch-merge/SKILL.md` - batch merge should continue to require `ready-for-human-review`; residual gate enforcement belongs before that label is applied.
- `.codex/skills/post-merge-cleanup/SKILL.md` - cleanup runs after merge and should not own readiness validation.
- `.codex/skills/workflow-plan-writer/SKILL.md` - existing parser and cross-cutting planning rules are sufficient for this plan.
- `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md` - existing plan-writer guidance already points to Protocol 02; update only if Protocol 02 adds a new checklist that must be mirrored explicitly.

---

## Testing Strategy

**Test types**: Shell unit tests, markdown/documentation lint, workflow smoke test.

**Key scenarios to test**:

1. Scope classifier marks numeric sweeps, `all` sweeps, `across` sweeps, batch extraction, multiple named targets, and helper extraction as applicable. Maps to BR-2, AC-1, and AC-8.
2. Scope classifier leaves ordinary single-file fixes and non-sweep documentation edits as `not_applicable`. Maps to BR-2 and AC-7.
3. Gate passes when applicable residual evidence reports no residuals. Maps to AC-2 and AC-6.
4. Gate blocks when residuals remain without `out_of_scope` or linked `follow_up` disposition. Maps to BR-5, BR-6, AC-3, and AC-6.
5. Gate passes with explicit linked follow-up disposition and includes the follow-up in the summary. Maps to AC-4.
6. Gate blocks helper-extraction evidence where produced helper outputs have no apparent callers or no caller evidence. Maps to BR-7 and AC-5.
7. Gate escalates when broad scope is detected but the stated target cannot be converted into a checkable residual evidence request. Maps to BR-9 and AC-7.
8. Protocol smoke test confirms the single-item, explicit batch, and epic guidance all require the gate before readiness. Maps to AC-8.

**Smoke test runbook**: `docs/testing/workflow/1175-residual-verification-before-closing-epic-subitems.smoke-test.md`

**Regression suite**: Add `scripts/development-workflow/tests/test-scope-residual-gate.sh` and run it directly. Also run existing nearby workflow tests that cover readiness and epic audit paths:

- `bash scripts/development-workflow/tests/test-scope-residual-gate.sh`
- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
- `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`

### Parser-Risk Addendum

This plan is parser-risk because the helper will classify issue title/body text and validate structured residual evidence.

**Edge-case enumeration**:

- Boundary-character variants: `all console.log`, `all-console-log`, `(all) console.log`, `127 console.log`, `127-console.log`, and `127x console.log`.
- Negative lookalikes: `not all items`, `all set`, `across from the login page`, `batch size config`, and `helper text copy` must not classify as sweep/helper-extraction work by themselves.
- Multiple occurrences on one line: `clean console.log and debug() across apps/admin, apps/api` must identify one applicable sweep with multiple target tokens, not duplicate gate records.
- Nested or overlapping constructs: `extract 7 helpers across services and remove all old callers` should classify both helper-extraction and sweep dimensions while producing one gate outcome for the item.
- Numeric target flexibility: numeric counts with words around them, such as `127 console.log cleanup`, `clean up 127 occurrences`, and `extract 7 shared helpers`, should preserve the target count in the summary.
- Follow-up references: `#123`, `owner/repo#123`, and a full issue URL count as linked follow-up references; plain prose such as `defer later` does not.
- Evidence schema tolerance: JSON evidence may contain zero residual groups, one residual group, multiple residual groups, or helper output records; missing required disposition fields must block or escalate rather than default to pass.

**Unit test mapping**: Add these cases to `scripts/development-workflow/tests/test-scope-residual-gate.sh`.

- `test_classifies_boundary_variants` covers boundary-character variants.
- `test_ignores_negative_lookalikes` covers negative lookalikes.
- `test_collapses_multi_target_line_to_single_gate` covers multiple occurrences on one line.
- `test_combines_overlapping_helper_and_sweep_signals` covers nested/overlapping constructs.
- `test_preserves_numeric_target_in_summary` covers numeric target flexibility.
- `test_requires_linked_follow_up_for_deferred_residuals` covers follow-up references.
- `test_blocks_malformed_or_incomplete_evidence` covers evidence schema tolerance.

**Suppression semantics**: Not applicable. The feature should not introduce inline suppression directives. Residuals can pass only when completed, explicitly out of scope, or linked to a follow-up issue.

### Concurrent-Event-Source Addendum

Not applicable. The feature runs synchronously in shell workflow scripts and does not add listeners, socket callbacks, timers, async queues, or shared mutable state across execution contexts.

---

## Seed Data

No application seed data is required. Test fixtures should be shell-local JSON/text files created under temporary directories by `test-scope-residual-gate.sh`.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Issue brief fixture | Sweep, batch, helper-extraction, ambiguous, and negative-lookalike titles/bodies | Temporary files created by `scripts/development-workflow/tests/test-scope-residual-gate.sh` |
| Residual evidence fixture | Passing, blocking, linked-follow-up, out-of-scope, malformed, and unused-helper evidence | Temporary JSON files created by `scripts/development-workflow/tests/test-scope-residual-gate.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` - add residual-evidence planning guidance for sweep, batch, and helper-extraction items.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` - require implementation agents to produce residual evidence for applicable items.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` - add explicit-list batch residual-gate behavior.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` - add the readiness gate before `ready-for-human-review`.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` - document how blocking/escalated residual results affect readiness.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` - add epic summary and ledger behavior.
- [ ] `scripts/development-workflow/README.md` - document the new helper.
- [ ] `REVIEW.md` - add review checks for residual evidence.
- [ ] Agent and skill guidance listed in **Cross-Cutting Checklist Impact** - mirror the new completion gate.
- [ ] `CHANGELOG.md` - add the implementation PR entry under `[Unreleased]` using the literal in **Implementation Order**.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Over-broad classifier blocks ordinary work | Medium | Medium | Keep classification conservative, add negative-lookalike tests, and allow `not_applicable` outcomes for ordinary scoped fixes. |
| Agents produce prose summaries that cannot be validated | Medium | High | Prefer structured JSON evidence and block ambiguous residual dispositions instead of parsing vague prose as pass. |
| Gate duplicates reviewer-loop or CI responsibilities | Low | Medium | Document that CI/review remain separate; the residual gate only validates stated completion scope. |
| Documentation surfaces drift | Medium | Medium | Update all enumerated protocol, agent, skill, and reviewer files in one implementation PR. |
| Helper caller detection appears stronger than it is | Medium | Medium | Treat helper checks as evidence validation and apparent caller-risk surfacing, not semantic dead-code proof. |

---

## Code Samples

The exact CLI shape may be adjusted during implementation, but it should preserve a small read-only interface like this:

```bash
# Illustrative - adapt during implementation.
./scripts/development-workflow/scope-residual-gate.sh classify \
  --issue-title "$ISSUE_TITLE" \
  --issue-body-file "$ISSUE_BODY_FILE"

./scripts/development-workflow/scope-residual-gate.sh verify \
  --issue-title "$ISSUE_TITLE" \
  --issue-body-file "$ISSUE_BODY_FILE" \
  --evidence "$RESIDUAL_EVIDENCE_JSON"
```

Example evidence shape:

```json
{
  "checked_scope": "console.log cleanup across apps/admin",
  "target": {"kind": "occurrence", "expected": 127},
  "residual_groups": [
    {
      "summary": "apps/admin legacy debug logs",
      "remaining_count": 3,
      "disposition": "follow_up",
      "follow_up": "#1234"
    }
  ],
  "helper_outputs": []
}
```

---

## Implementation Order

1. Add `scripts/development-workflow/scope-residual-gate.sh` with argument validation, read-only behavior, and stable result output. Verify by running the helper manually against one passing evidence fixture and one blocking evidence fixture.
2. Add `scripts/development-workflow/tests/test-scope-residual-gate.sh` with the parser-risk cases listed above. Verify with `bash scripts/development-workflow/tests/test-scope-residual-gate.sh`.
3. Update Protocol 91 Step 8a to run the helper before applying `ready-for-human-review`, map `pass`, `block`, `escalate`, and `not_applicable` outcomes to the existing readiness loop, and require the human-readable summary in the PR or terminal handoff. Verify by reading the Step 8a flow and confirming the residual gate runs after reviewer/CI cleanliness but before the readiness label.
4. Update Protocols 90, 92, and 95 so explicit batches, readiness signaling, and epic ledgers preserve the same gate outcome and do not report blocked residual work as terminal human-ready work. Verify by searching for `scope-residual-gate.sh` and confirming all three protocols mention the pass/block/escalate outcomes.
5. Update Protocols 02 and 03 so plans and implementation work for sweep, batch, and helper-extraction items name the residual evidence strategy and produce evidence before readiness. Verify by confirming both files mention residual evidence and broad-scope item signals.
6. Update `REVIEW.md` plus the agent and skill guidance files enumerated in **Cross-Cutting Checklist Impact**. Verify with a live search for `scope-residual` or the chosen helper name and confirm every listed guidance file is either updated or intentionally documented as not applicable.
7. Update `scripts/development-workflow/README.md` with helper usage and read-only guarantees. Verify the examples use simple commands and do not imply tracker, label, or issue mutation.
8. Update this runbook if final helper names or output fields differ from the plan. Verify every acceptance criterion still has at least one smoke step.
9. Run markdown and workflow shell quality checks:
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/**/*.md" "docs/testing/workflow/1175-residual-verification-before-closing-epic-subitems.smoke-test.md" "REVIEW.md"`
   - `shellcheck scripts/development-workflow/scope-residual-gate.sh scripts/development-workflow/tests/test-scope-residual-gate.sh`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
10. Run the focused workflow regression tests:
    - `bash scripts/development-workflow/tests/test-scope-residual-gate.sh`
    - `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
    - `bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
    - `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
11. Update `CHANGELOG.md` under `[Unreleased]` with:
    - `- **Add residual verification gate for sweep sub-items** (#1175): Require broad-scope workflow items to record residual evidence before readiness.`
