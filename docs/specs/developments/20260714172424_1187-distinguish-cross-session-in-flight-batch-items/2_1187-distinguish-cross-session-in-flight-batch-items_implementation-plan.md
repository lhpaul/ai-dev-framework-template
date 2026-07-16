# Distinguish Cross-Session In-Flight Items in Run-Work Batch Proposals - Implementation Plan

**Spec**: [1_1187-distinguish-cross-session-in-flight-batch-items_specs.md](1_1187-distinguish-cross-session-in-flight-batch-items_specs.md)
**Smoke test runbook**: [../../../testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md](../../../testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md)

---

## Summary

**Approach**: Add an explicit report-category contract to the portfolio scan and
batch proposal flow, then have the batch-planning helpers emit category fields
that Protocol 90 and `/run-work` surfaces can render consistently. Keep
`/run-work` scan mode read-only; this change only clarifies which records are
informational context, actionable resume work, proposed Backlog starts, or held
Backlog candidates.

**Estimated complexity**: M

**Rationale**: The change touches shell helper output, workflow protocol text,
command/skill guidance, and regression tests, but it does not require new
tracker statuses, persistence, external services, or product runtime code.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `38829f7` |
| Template-fit check | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; scope is generic workflow tooling/reporting, not a framework-specific downstream feature. |
| Tracker status | `gh issue view 1187 --json number,title,state,projectItems,url` | Issue #1187 is open and the project item status is `Writing Plan`. |
| Run-work/report surface search | `rg -n "run-work|batch proposal|proposal|in-flight|resume|Protocol 90|workflow-batch" docs/workflow scripts .agents .codex .claude .cursor AGENTS.md README.md` | Relevant surfaces include Protocol 90, Protocol 96, `.agents/skills/run-work`, `.claude/commands/run-work.md`, `.cursor/commands/run-work.md`, `README.md`, `AGENTS.md`, and `workflow-batch-plan.sh` / `workflow-batch-lanes.sh`. |
| Existing helper output fields | `rg -n "^print_kv|NEXT_ACTION|BATCH_HINT|PARALLEL_SAFE|DISPATCH|HOLD_REASON" scripts/development-workflow/workflow-batch-plan.sh scripts/development-workflow/workflow-batch-lanes.sh scripts/development-workflow/tests` | `workflow-batch-plan.sh` emits candidate metadata; `workflow-batch-lanes.sh` already emits `DISPATCH=proposed|held|skip` and `HOLD_REASON`, making it the right place to add report-category metadata. |
| Existing smoke-test location | `find docs/testing -maxdepth 3 -type f | sort | sed -n '1,120p'` | Workflow runbooks live under `docs/testing/workflow/`; use `1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md`. |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Update `scripts/development-workflow/workflow-batch-plan.sh` so each item
      block exposes enough metadata for category rendering without forcing the
      operator to infer meaning from `NEXT_ACTION`, tracker status, or batch
      order alone. Preserve existing keys for compatibility.
- [ ] Update `scripts/development-workflow/workflow-batch-lanes.sh` to derive and
      emit a stable category field for every item:
      `REPORT_CATEGORY=informational|actionable_resume|proposed_batch|held`.
- [ ] Emit `REPORT_LABEL` values matching the spec's display markers:
      `INFORMATIONAL - not actionable in this proposal`,
      `ACTIONABLE RESUME - can advance now`,
      `PROPOSED BATCH - your decision`, and
      `HELD - not included in proposed batch`.
- [ ] Emit `REPORT_REASON` for every non-proposed item. For informational items,
      name the reason they are outside the current `/run-work` decision, such as
      waiting on human review, waiting on merge, already handled elsewhere, or
      not dispatch-eligible. For held items, reuse or refine `HOLD_REASON`.
- [ ] Keep the existing `DISPATCH` semantics intact:
      `DISPATCH=proposed` may map to `actionable_resume` or `proposed_batch`
      depending on whether the item is resume work or a Backlog start candidate;
      `DISPATCH=held` maps to `held`; `DISPATCH=skip` maps to informational.
- [ ] If the implementation needs Backlog-specific classification that is not
      present in the helper block, use the already available tracker status or
      next-action evidence. Do not introduce new tracker fields.

### Workflow Protocols And Guidance

- [ ] Update
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      Step 2 / largest safe start-batch reporting guidance so scan output
      renders four separate sections when present:
      informational context, actionable resume work, proposed batch, and held
      candidates.
- [ ] Update the Protocol 90 `/run-work` scan-only wording to state that
      approval applies only to `PROPOSED BATCH - your decision` items and that
      informational records are excluded unless the operator invokes a separate
      bounded command.
- [ ] Update `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
      only if its no-target scan handoff text needs the same category labels or
      approval-scope wording.
- [ ] Update `/run-work` command and skill guidance so Claude, Cursor, Codex,
      and repo-scoped aliases use the same category names and meanings:
      `.agents/skills/run-work/SKILL.md`,
      `.agents/skills/run-work/agents/openai.yaml`,
      `.claude/commands/run-work.md`,
      `.cursor/commands/run-work.md`,
      `README.md`,
      `AGENTS.md`, and
      `docs/workflow/development-workflow/README.md`.
- [ ] Do not update implementation-stage command behavior for `/run-items`,
      `/run-item`, or `/run-epic` except to reference the read-only scan
      categories if needed for clarity.

### Tests And Smoke Coverage

- [ ] Extend `scripts/development-workflow/tests/test-workflow-batch-lanes.sh`
      with mixed input covering proposed Backlog starts, current-session resume
      work, held candidates, and skipped or waiting items. Assert
      `REPORT_CATEGORY`, `REPORT_LABEL`, and `REPORT_REASON` values.
- [ ] Add or extend a shell-level fixture that proves a proposed batch with
      informational items cannot render as one undifferentiated approval list.
      Prefer extending `test-workflow-batch-lanes.sh` unless implementation
      adds a dedicated report-rendering helper.
- [ ] Keep `scripts/development-workflow/tests/test-run-work-router.sh` focused
      on routing unless Protocol 96 output changes; do not overload router tests
      with Protocol 90 rendering assertions.
- [ ] Use the smoke runbook at
      `docs/testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md`
      to validate a mixed scan report against all acceptance criteria.

### Data, Infrastructure, And Configuration

- [ ] No database, seed-data, infrastructure, environment-variable, or project
      board schema changes.
- [ ] No new dependencies. Use the existing Bash, `awk`, `grep`, `jq`, and
      Python patterns already present in the workflow helper tests when needed.

---

## Files To Modify

```text
scripts/development-workflow/workflow-batch-plan.sh
scripts/development-workflow/workflow-batch-lanes.sh
scripts/development-workflow/tests/test-workflow-batch-lanes.sh
docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md
.agents/skills/run-work/SKILL.md
.agents/skills/run-work/agents/openai.yaml
.claude/commands/run-work.md
.cursor/commands/run-work.md
README.md
AGENTS.md
docs/workflow/development-workflow/README.md
docs/testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md
CHANGELOG.md
```

`docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
is conditional: edit it only if the implementation needs to clarify the
no-target scan handoff. `CHANGELOG.md` is implementation-stage only; this plan
branch intentionally does not modify it.

---

## Testing Strategy

**Test types**: Unit-style shell tests, documentation lint, smoke runbook.

**Key scenarios to test**:

1. Mixed `/run-work` scan output separates cross-session or waiting context from
   proposal-eligible Backlog starts. Maps to AC1, AC2, AC3, AC4, and AC7.
2. Informational-only scan says no Backlog start batch is proposed. Maps to AC5.
3. Held Backlog candidates are separate from informational, actionable-resume,
   and proposed-batch items, with hold reasons. Maps to AC6.
4. Current-session resume work is labeled as actionable resume work rather than
   informational context or a Backlog start proposal. Maps to AC10.
5. Protocol, command, skill, and README guidance use the same labels and
   meanings. Maps to AC8.
6. Workflow smoke coverage demonstrates the mixed scan distinction. Maps to AC9.

**Smoke test runbook**:
`docs/testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-batch-lanes.sh`
- `bash scripts/development-workflow/tests/test-run-work-router.sh` if Protocol
  96 or router-adjacent wording changes
- `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
- `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`

### Parser-Risk Classification

Not parser-risk. The plan changes shell helper classification and reporting
metadata, but it does not add a parser/scanner module, change regex-heavy
structured-text extraction semantics, or introduce inline suppression behavior.

### Concurrent-Event-Source Classification

Not concurrent-event-source. The implementation is synchronous shell reporting
and markdown guidance with no event listeners, timers, sockets, async queues, or
shared mutable state across execution contexts.

### Cross-Cutting Checklist Classification

Not a cross-cutting checklist plan. The implementation clarifies a workflow
reporting category contract; it does not add or rename a safety, quality, or
compliance checklist category in planning, implementation, or review gates.

---

## Seed Data

No persisted seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Shell fixture item | In-flight or review-waiting item that should be informational | `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` |
| Shell fixture item | Current-session resume item that can advance now | `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` |
| Shell fixture item | Proposal-eligible Backlog item | `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` |
| Shell fixture item | Held Backlog candidate with a hold reason | `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - document report categories, section ordering, no-proposal wording, and
      approval scope.
- [ ] `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
      - update no-target handoff wording if needed so routing and Protocol 90
      category labels do not conflict.
- [ ] `.agents/skills/run-work/SKILL.md` and
      `.agents/skills/run-work/agents/openai.yaml` - describe the four
      report categories and the recommended `/run-items` approval scope.
- [ ] `.claude/commands/run-work.md` and `.cursor/commands/run-work.md` -
      mirror the category labels and approval-scope wording.
- [ ] `README.md`, `AGENTS.md`, and
      `docs/workflow/development-workflow/README.md` - keep user-facing
      `/run-work` guidance consistent with the Protocol 90 report contract.
- [ ] `docs/testing/workflow/1187-distinguish-cross-session-in-flight-batch-items.smoke-test.md`
      - add the workflow smoke runbook for mixed scan verification.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| `DISPATCH=proposed` is currently too broad to distinguish resume work from Backlog start proposals. | Medium | High | Derive `REPORT_CATEGORY` from `NEXT_ACTION` plus tracker/status evidence, and add tests for both resume and Backlog-like candidates. |
| Guidance surfaces drift and use different labels. | Medium | Medium | Treat Protocol 90 labels as canonical and update command/skill/README surfaces in the same implementation PR. |
| Operators still see informational items near the approval prompt and assume they are included. | Medium | High | Place the proposed-batch section adjacent to the approval command and explicitly state informational items are excluded. |
| Tests assert brittle exact prose instead of stable category fields. | Medium | Medium | Assert the stable key/value fields and essential labels/reasons; keep full prose checks limited to smoke/manual review. |

---

## Code Samples

Illustrative key/value output shape only; adapt exact placement during
implementation:

```text
SLUG=1187-example
NEXT_ACTION=write-plan
DISPATCH=proposed
REPORT_CATEGORY=proposed_batch
REPORT_LABEL=PROPOSED BATCH - your decision
REPORT_REASON=Backlog start candidate included in the current proposal
```

---

## Implementation Order

1. Update `workflow-batch-lanes.sh` to derive `REPORT_CATEGORY`,
   `REPORT_LABEL`, and `REPORT_REASON` from the existing item block fields and
   lane/dispatch decision. Verify with a small local fixture that the output
   includes category fields for proposed, held, and skipped blocks.
2. If the lane helper cannot reliably distinguish Backlog proposed starts from
   actionable resume work, add the minimum metadata needed in
   `workflow-batch-plan.sh` while preserving all existing output keys. Verify
   that existing helper output still includes `TARGET`, `DEVELOPMENT_PATH`,
   `SLUG`, `STATUS`, `NEXT_ACTION`, `BATCH_HINT`, and `PARALLEL_SAFE`.
3. Extend `test-workflow-batch-lanes.sh` with mixed scan fixtures and assertions
   for informational, actionable-resume, proposed-batch, and held categories.
   Confirm the output makes informational items visibly separate from the
   proposed batch.
4. Update Protocol 90 to define the report-category contract, section ordering,
   no-proposal wording, and approval scope. Include the exact display labels
   from the spec.
5. Update `/run-work` command/skill/README guidance so all user-facing surfaces
   refer to the same labels and state that `/run-work` approval applies only to
   proposed-batch items.
6. Update Protocol 96 only if needed to keep no-target scan handoff wording
   consistent with Protocol 90. Do not change routing modes or mutation rules.
7. Update the smoke runbook and verify each acceptance criterion maps to a
   runnable check or manual assertion.
8. Add a `CHANGELOG.md` entry under `[Unreleased]` using this literal format:
   `- **Clarify run-work batch proposal categories** (#1187): Label informational, actionable-resume, proposed-batch, and held items separately in run-work scan proposals.`
9. Run validation:
   `bash scripts/development-workflow/tests/test-workflow-batch-lanes.sh`,
   `bash scripts/development-workflow/tests/test-run-work-router.sh` if Protocol
   96/router-adjacent behavior changed, `npx markdownlint-cli2
   "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md"
   "CHANGELOG.md"`, and the markdown heuristic lint command from the testing
   strategy.
