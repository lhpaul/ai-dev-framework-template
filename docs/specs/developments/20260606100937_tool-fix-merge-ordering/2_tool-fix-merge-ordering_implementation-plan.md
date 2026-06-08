# Tool-Fix Merge Ordering — Implementation Plan

**Spec**: [1_tool-fix-merge-ordering_specs.md](1_tool-fix-merge-ordering_specs.md)
**Smoke test runbook**: [tool-fix-merge-ordering.smoke-test.md](../../../testing/workflow/tool-fix-merge-ordering.smoke-test.md)

---

## Summary

**Approach**: Extend the batch orchestration protocol's existing tool-fix ordering hazard section with merge-ordering guidance for foundational reviewer-tool fixes. The implementation is documentation-only: define detection signals, hold behavior, resume behavior after foundational merge, and required batch-summary output.

**Estimated complexity**: S

**Rationale**: The approved spec scopes the change to protocol guidance and smoke documentation. No script behavior, tracker schema, or reviewer platform integration changes are required.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `0b52d0d` |
| Existing tool-fix ordering text | `rg -n "tool-fix|Serialize-first|foundational|dependent|reviewer tooling|rebase" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md docs/testing/workflow` | The batch orchestration protocol already owns the same-batch tool-fix serialize-first rule; no existing foundational-merge guidance is present. |
| Script change scope check | `rg -n "TOOL_FIX|TOOL_FIX_FILES|detect_file_conflicts|workflow-batch-plan" scripts/development-workflow docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | `workflow-batch-plan.sh` already emits tool-fix classification; the requested behavior can be expressed as orchestrator protocol guidance without changing helper output. |

---

## Layer-by-Layer Changes

### Workflow Protocols

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — update the "Same-batch tool-fix ordering hazard" section with a new "Foundational reviewer-tool merge ordering" subsection.
- [ ] Define a foundational reviewer-tool fix as a tool-fix that repairs reviewer-loop or reviewer-action behavior another same-batch tool-fix needs to trust its own reviewer loop.
- [ ] Require dependent tool-fix items to be held until the foundational PR is merged.
- [ ] Require dependent branches or PRs to be updated from the target base after the foundational merge, then rerun reviewer loop and CI before readiness is trusted.
- [ ] State that a dependent pre-foundational-merge escalation is stale until a post-update reviewer loop runs.
- [ ] Require the batch summary to list foundational item, held dependent items, merge-ordering reason, and resume condition.

### Scripts / Helpers

- [ ] No script changes. `workflow-batch-plan.sh` already emits `TOOL_FIX` and `TOOL_FIX_FILES`; this feature only adds orchestration guidance for a case discovered after classification.

### Tests and Smoke Runbooks

- [ ] `docs/testing/workflow/tool-fix-merge-ordering.smoke-test.md` — add a manual smoke runbook that verifies the batch orchestration protocol includes detection, hold, merge-first, update/reloop, stale-escalation, summary, and human-merge-approval guidance.

---

## Testing Strategy

**Test types**: Markdown lint and manual smoke verification.

**Key scenarios to test**:

1. The batch orchestration protocol explains why dispatch serialization alone is insufficient for dependent reviewer-tool fixes — maps to AC1.
2. The batch orchestration protocol instructs the orchestrator to identify foundational reviewer-tool fixes — maps to AC2.
3. Dependent tool-fix items are held until the foundational PR is merged — maps to AC3.
4. Dependent branches are updated from target base and rerun through reviewer loop/CI after foundational merge — maps to AC4.
5. Pre-foundational-merge escalations are treated as stale until post-update review runs — maps to AC5.
6. Batch summaries list held dependents and merge-ordering reason — maps to AC6.
7. Human approval remains required before every merge — maps to AC7.

**Smoke test runbook**: `docs/testing/workflow/tool-fix-merge-ordering.smoke-test.md`

**Regression suite**: No automated shell regression is required because this plan does not change scripts.

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — add foundational reviewer-tool merge-ordering guidance.
- [ ] `docs/testing/workflow/tool-fix-merge-ordering.smoke-test.md` — add manual smoke coverage.
- [ ] `CHANGELOG.md` — add under `[Unreleased]` → `### Fixed`: `- **Tool-fix merge ordering** (#825): documents that foundational reviewer-tool fixes must merge before dependent tool-fixes are trusted, and that dependents must update from the fixed base before rerunning reviewer loops.`

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Orchestrators over-serialize unrelated tool-fixes. | Medium | Medium | Limit the rule to reviewer-tool fixes that a dependent item's own reviewer loop needs to trust. |
| Agents infer auto-merge authority. | Low | High | State explicitly that human approval remains required for every PR merge. |
| Dependent PRs are marked ready using stale pre-merge reviewer outcomes. | Medium | High | Require update-from-base and a fresh reviewer loop/CI run after the foundational merge. |

---

## Code Samples

No production code samples are required.

---

## Implementation Order

1. Update the batch orchestration protocol's same-batch tool-fix ordering section with the foundational reviewer-tool merge-ordering subsection.
2. Add summary-output requirements for foundational item, held dependents, merge-ordering reason, stale escalation treatment, and resume condition.
3. Add `docs/testing/workflow/tool-fix-merge-ordering.smoke-test.md` with the seven Testing Strategy scenarios.
4. Update `CHANGELOG.md` with the entry listed in **Documentation Updates**.
5. Run markdown lint:

   ```bash
   npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" "docs/testing/workflow/tool-fix-merge-ordering.smoke-test.md" "CHANGELOG.md"
   ```
