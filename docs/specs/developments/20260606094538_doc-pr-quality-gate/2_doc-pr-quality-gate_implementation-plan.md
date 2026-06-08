# Doc PR Quality Gate — Implementation Plan

**Spec**: [1_doc-pr-quality-gate_specs.md](1_doc-pr-quality-gate_specs.md)
**Smoke test runbook**: [doc-pr-quality-gate.smoke-test.md](../../../testing/workflow/doc-pr-quality-gate.smoke-test.md)

---

## Summary

**Approach**: Add a compact pre-submission document quality gate to the spec and implementation-plan authoring protocols. The gate reuses existing review concerns from `REVIEW.md`, requires a visible PR-description log, and adds operator guidance for long document-review cycles without changing reviewer-loop authority.

**Estimated complexity**: M

**Rationale**: The change is documentation/protocol only, but it affects several workflow surfaces that must stay consistent: spec authoring, plan authoring, work item orchestration handoff, reviewer-loop operator guidance, review contract expectations, and smoke-test coverage.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `0b52d0d` |
| Existing self-review/gate language | `rg -n "pre-submission|self-review|quality gate|PR description|document" docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md REVIEW.md .claude .cursor .codex/skills .agents/skills` | Existing anchors are Protocol 01's spec self-check, Protocol 02's plan consistency check, Protocol 03's implementation self-review, Protocol 91's reviewer lifecycle, Protocol 93's advisory-disposition guidance, and Claude/Cursor developer-agent self-review text. |
| Spec and plan PR creation surfaces | `rg -n "Open a \\*\\*draft\\*\\* PR|draft PR|PR description|review gate" docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Protocol 01 and 02 own draft PR creation text; Protocol 91 owns the post-PR review lifecycle. |
| Agent/skill delegation check | `rg -n "01-generate-spec-protocol|02-generate-implementation-plan-protocol|document quality|self-review" .claude/agents .cursor/agents .codex/skills .agents/skills` | Product-manager and tech-lead agents delegate directly to Protocol 01/02; no Codex skill contains independent document-quality-gate logic today. |

---

## Layer-by-Layer Changes

### Workflow Protocols

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` — replace the current narrow "Before opening the draft PR" skim with a named **Document Quality Gate** for spec PRs. The gate must include brief coverage, internal consistency, naming/casing consistency, behavioral guarantees, known high-signal reviewer categories, template-placeholder cleanup, and not-applicable rationale.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — add the same **Document Quality Gate** for plan PRs before draft PR creation. For plans, include implementation-order consistency, verification-log support for broad claims, behavioral guarantee mechanisms, parser/concurrency checklist completeness when applicable, and CHANGELOG literal format.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — clarify that spec/plan PR readiness includes a PR-description quality-gate log before the normal internal review gate, automated reviewer loop, CI, and human review.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — add operator guidance for long spec/plan review cycles: inspect the quality-gate log, reviewer-loop summary, advisory dispositions, and remaining reviewer findings before deciding whether to continue or escalate.

### Review Contract

- [ ] `REVIEW.md` — add review expectations for spec and plan PRs: a missing or obviously incomplete document-quality-gate log is an important finding by default, and a stale or contradictory log that claims unchecked coverage is blocking.

### Agent / Skill Guidance

- [ ] `.claude/agents/product-manager.md` and `.cursor/agents/product-manager.md` — mention that Protocol 01 includes a document quality gate before spec PR creation.
- [ ] `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md` — mention that Protocol 02 includes a document quality gate before plan PR creation.
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md` and `.codex/skills/workflow-plan-writer/SKILL.md` — no independent gate text is required because both skills delegate to Protocol 01/02, but the implementer must verify that they still instruct agents to continue through PR creation/readiness.
- [ ] `.agents/skills` aliases — no change expected unless a command-style alias contains independent spec/plan PR guidance.

### Tests and Smoke Runbooks

- [ ] `docs/testing/workflow/doc-pr-quality-gate.smoke-test.md` — add manual verification for the new gate across spec, plan, PR description, reviewer-loop operator guidance, and review contract expectations.
- [ ] Update any existing smoke runbook that directly asserts Protocol 01/02 PR-creation steps if the new gate changes the expected text.

---

## Testing Strategy

**Test types**: Markdown lint and manual smoke verification.

**Key scenarios to test**:

1. Spec authoring protocol requires a quality-gate pass before opening a spec PR — maps to AC1, AC3, AC4, AC5.
2. Plan authoring protocol requires a quality-gate pass before opening a plan PR — maps to AC2, AC3, AC4, AC5.
3. PR description guidance requires visible evidence of the gate and not-applicable rationale — maps to AC4.
4. Operator guidance explains how to inspect long spec/plan review cycles after the gate has run — maps to AC6.
5. Reviewer-loop authority remains unchanged: the gate does not replace internal review, automated review, CI, or human review — maps to AC5 and AC7.

**Smoke test runbook**: `docs/testing/workflow/doc-pr-quality-gate.smoke-test.md`

**Regression suite**: No automated shell/script regression is required because this is documentation/protocol behavior only. Run markdown lint over all changed docs.

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` — add spec document quality gate.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — add plan document quality gate.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — include the gate in spec/plan PR readiness expectations.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — add operator guidance for long document-review cycles.
- [ ] `REVIEW.md` — add review expectations for quality-gate logs on spec and plan PRs.
- [ ] `.claude/agents/product-manager.md`, `.cursor/agents/product-manager.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md` — align agent summaries with the new Protocol 01/02 gate.
- [ ] `docs/testing/workflow/doc-pr-quality-gate.smoke-test.md` — add the smoke runbook.
- [ ] `CHANGELOG.md` — add under `[Unreleased]` → `### Added`: `- **Document PR quality gate** (#816): adds a pre-submission quality gate for spec and implementation-plan PRs so document authors check brief coverage, consistency, behavioral guarantees, and recurring reviewer categories before opening draft PRs.`

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The gate becomes too long and agents skip it. | Medium | Medium | Keep the required log compact and focus on the recurring high-value categories named in the spec. |
| Agents treat the gate as replacing reviewers. | Low | High | State in Protocol 01, Protocol 02, and REVIEW.md that internal review, automated review, CI, and human review remain authoritative. |
| Spec and plan gate wording drifts. | Medium | Medium | Use the same section name, shared checklist categories, and smoke-test assertions for both protocols. |
| Operator guidance normalizes slow review cycles instead of reducing them. | Low | Medium | Frame the guidance as diagnostic context after the gate has run, not as permission to submit weak first drafts. |

---

## Code Samples

No production code samples are required.

---

## Implementation Order

1. Update Protocol 01 with a named spec document quality gate before draft PR creation. Include the required PR-description log format and not-applicable rationale rule.
2. Update Protocol 02 with a parallel plan document quality gate before draft PR creation. Include implementation-order consistency, verification-log support, behavioral guarantees, and conditional parser/concurrency checklist completeness.
3. Update Protocol 91 to include the document quality-gate log in spec/plan PR readiness expectations while preserving the existing internal review, automated reviewer loop, CI, and human review gates.
4. Update Protocol 93 with operator guidance for long spec/plan review cycles after the gate has run.
5. Update `REVIEW.md` so reviewers can flag missing, incomplete, stale, or contradictory quality-gate logs.
6. Update Claude/Cursor product-manager and tech-lead agent summaries to mention the new Protocol 01/02 gate. Verify Codex skills and `.agents/skills` aliases do not duplicate the protocol text.
7. Add `docs/testing/workflow/doc-pr-quality-gate.smoke-test.md` covering the five Testing Strategy scenarios.
8. Update `CHANGELOG.md` with the entry listed in **Documentation Updates**.
9. Run markdown lint on all changed docs:

   ```bash
   npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md" "docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md" "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md" "REVIEW.md" ".claude/agents/product-manager.md" ".cursor/agents/product-manager.md" ".claude/agents/tech-lead.md" ".cursor/agents/tech-lead.md" "docs/testing/workflow/doc-pr-quality-gate.smoke-test.md" "CHANGELOG.md"
   ```
