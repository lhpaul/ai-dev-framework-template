# Complex Workflow Decision Gate Consistency Matrix - Implementation Plan

**Spec**: [1_1242-consistency-matrix-complex-workflow-decision-gates_specs.md](1_1242-consistency-matrix-complex-workflow-decision-gates_specs.md)
**Smoke test runbook**: [1242-consistency-matrix-complex-workflow-decision-gates.smoke-test.md](../../../testing/workflow/1242-consistency-matrix-complex-workflow-decision-gates.smoke-test.md)

---

## Summary

**Approach**: Add a human-readable consistency matrix requirement to the workflow documentation gates that already control spec, plan, and implementation PR readiness. Keep the matrix as PR evidence and review guidance, not as a new script, status label, CI job, or merge authority path.

**Estimated complexity**: M

**Rationale**: The change is documentation-only, but it touches multiple mirrored workflow surfaces: generation protocols, implementation self-review, PR readiness guidance, review contract, and agent/skill summaries. The main work is keeping the cross-stage wording consistent and ensuring simple non-gate documentation updates have a clear not-applicable path.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `060e056` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and the #1242 spec | `template.is_template: true`; the spec improves generic workflow documentation and is framework-agnostic |
| Cross-cutting protocol mirror search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/` | 6 required planning/implementation mirrors: `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md` |
| Stage and readiness surface search | `grep -rl "Document Quality Gate\|ready-for-human-review\|implementation-plan\|03-implement-development-protocol\|02-generate-implementation-plan-protocol\|01-generate-spec-protocol" .agents/skills .codex/skills .claude/agents .cursor/agents docs/workflow/development-workflow/protocols REVIEW.md` | Found spec, plan, implementation, readiness, review, orchestrator, and skill surfaces; plan lists the surfaces that need direct edits and the delegating surfaces that should remain unchanged |
| Existing documentation PR gate pattern | Read `docs/testing/workflow/doc-pr-quality-gate.smoke-test.md` and `REVIEW.md` | Existing pattern uses PR description evidence plus review-contract checks, then preserves internal review, automated reviewer loop, CI, labels, and tracker transitions |
| Parser/concurrency classification | Read the #1242 spec and searched for parser, scanner, regex, listeners, timers, queues, and shared mutable state signals | Parser-risk: not applicable, no parser/scanner implementation planned. Concurrent-event-source: not applicable, no runtime event sources or shared mutable state |

---

## Layer-by-Layer Changes

### Workflow Protocols and Documentation

- [ ] Update `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` so spec authors include a consistency matrix, or a short not-applicable rationale, when a spec PR changes complex workflow decision-gate behavior.
- [ ] Update `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` so plan authors classify complex workflow decision-gate changes and include matrix coverage in the Document Quality Gate evidence before plan PR handoff.
- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` so implementation authors include matrix evidence in the pre-submission self-review log for complex gate documentation PRs before opening or marking the PR ready.
- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` so the readiness chain treats missing or contradictory matrix evidence as a blocker before `ready-for-human-review` when the PR changes a complex workflow decision gate.
- [ ] Update `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` so the `ready-for-human-review` label definition names stage-required evidence, including the complex gate matrix when applicable, without changing CI, reviewer, or merge policy.
- [ ] Update `REVIEW.md` so spec, plan, and code reviewers can flag missing inputs, outcomes, next actions, mirror surfaces, examples, or not-applicable rationales as findings for complex gate PRs.
- [ ] Update `docs/workflow/development-workflow/README.md` only if needed to define the consistency matrix at the workflow overview level. Keep it concise and defer detailed checklist mechanics to the protocols and review contract.

### Agent and Skill Guidance

- [ ] Update `.claude/agents/product-manager.md` and `.cursor/agents/product-manager.md` so spec-generation guidance points to Protocol 01's matrix applicability check.
- [ ] Update `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and `.codex/skills/workflow-plan-writer/SKILL.md` so plan-generation guidance points to Protocol 02's matrix classification and Document Quality Gate entry.
- [ ] Update `.claude/agents/developer.md`, `.cursor/agents/developer.md`, and `.codex/skills/workflow-implementer/SKILL.md` so implementation guidance points to Protocol 03's pre-submission matrix evidence requirement.
- [ ] Update `.codex/skills/workflow-spec-writer/SKILL.md` so Codex spec-generation guidance mirrors the Protocol 01 requirement.

### Not Modified

- `scripts/development-workflow/*` - no new script or automated detector is planned for MVP.
- `CHANGELOG.md` - plan-only PRs are exempt. The later implementation PR should add the documented entry under `[Unreleased]`.
- `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-items/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, and reviewer-loop skills - no direct edits needed because they delegate to Protocol 91, Protocol 92, or `REVIEW.md` rather than duplicating the readiness evidence checklist.

---

## Cross-Cutting Workflow Guidance

**Classification**: Applies. This plan introduces a cross-cutting quality checklist for complex workflow decision-gate changes across independent spec, plan, and implementation PRs.

**Full enumeration decision**:

| Surface | Action |
| --- | --- |
| `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` | Add spec-stage matrix applicability evidence |
| `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Add plan-stage matrix classification and Document Quality Gate evidence |
| `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Add implementation pre-submission matrix evidence |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Add readiness-chain reminder that applicable matrix evidence must be present before `ready-for-human-review` |
| `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | Clarify the label definition includes stage-required evidence such as the matrix when applicable |
| `REVIEW.md` | Add reviewer checks and finding guidance for missing or contradictory matrix evidence |
| `docs/workflow/development-workflow/README.md` | Optional concise overview only if protocol wording needs a central glossary pointer |
| `.claude/agents/product-manager.md` | Add spec author reminder |
| `.cursor/agents/product-manager.md` | Mirror Claude spec author reminder |
| `.codex/skills/workflow-spec-writer/SKILL.md` | Add Codex spec writer reminder |
| `.claude/agents/tech-lead.md` | Add plan author reminder |
| `.cursor/agents/tech-lead.md` | Mirror Claude plan author reminder |
| `.codex/skills/workflow-plan-writer/SKILL.md` | Add Codex plan writer reminder |
| `.claude/agents/developer.md` | Add implementation author reminder |
| `.cursor/agents/developer.md` | Mirror Claude implementation author reminder |
| `.codex/skills/workflow-implementer/SKILL.md` | Add Codex implementer reminder |

The implementation should not add direct matrix wording to delegating orchestrator or reviewer-loop wrappers unless live review finds they duplicate stage evidence requirements. If such duplicates are discovered, update the mirror or explicitly document why it remains delegated.

---

## Matrix Semantics

The implementation should define a complex workflow decision-gate change as a documentation or protocol change whose behavior depends on multiple inputs, allowed outcomes, next-action branches, labels, exit states, examples, or mirrored workflow surfaces.

For applicable PRs, the matrix evidence must identify:

- Gate name or decision point.
- Inputs that influence the gate.
- Allowed outcomes for those inputs.
- Required next action for each outcome.
- Mirror surfaces that must use matching wording.
- Examples that make the gate behavior testable, when examples are part of the changed surface.
- Short rationale for any expected input, outcome, example, or mirror surface marked not applicable.

For non-applicable PRs, a short rationale is enough when the evidence format asks for the check, for example: "Not applicable - this documentation change does not add or modify workflow decision-gate behavior."

---

## Parser, API, and Concurrency Classification

**Parser-risk**: Not applicable. The feature should add human-readable protocol and review guidance only. It must not add a custom parser, scanner, regex rule engine, or structured-text detector.

**API-surface changes**: Not applicable. No CLI flags, machine-readable config keys, public functions, status labels, or GitHub API behavior are planned.

**Concurrent-event-source**: Not applicable. The change has no listeners, timers, queues, async callbacks, or shared mutable runtime state.

---

## Testing Strategy

**Test types**: Documentation review, markdown lint, targeted consistency searches, and smoke test runbook execution.

**Key scenarios to test**:

1. Complex workflow decision-gate PR evidence includes matrix coverage before `ready-for-human-review` - maps to AC1 and AC7.
2. Matrix entries list gate inputs, allowed outcomes, required next actions, and mirror surfaces - maps to AC2 and AC6.
3. Not-applicable matrix rows include short rationale - maps to AC3.
4. Reviewers can flag missing or contradictory matrix evidence as findings - maps to AC4.
5. Simple documentation PRs can use a not-applicable rationale instead of a full matrix - maps to AC5.
6. Existing internal review, automated reviewer loop, CI, labels, tracker, and human merge gates remain required - maps to AC7.

**Smoke test runbook**: `docs/testing/workflow/1242-consistency-matrix-complex-workflow-decision-gates.smoke-test.md`

**Regression suite**: No automated regression suite is configured for workflow documentation. Use markdown lint plus the smoke runbook checks.

---

## Seed Data

None. This workflow documentation change has no database, fixture, or seed-data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` - spec-stage matrix evidence.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` - plan-stage matrix evidence.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` - implementation pre-submission matrix evidence.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` - readiness-chain applicability reminder.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` - readiness label definition clarification.
- [ ] `REVIEW.md` - reviewer checks for matrix evidence and not-applicable rationale.
- [ ] `docs/workflow/development-workflow/README.md` - optional concise overview if needed.
- [ ] `.claude/agents/product-manager.md` - spec author reminder.
- [ ] `.cursor/agents/product-manager.md` - spec author reminder.
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md` - spec writer reminder.
- [ ] `.claude/agents/tech-lead.md` - plan author reminder.
- [ ] `.cursor/agents/tech-lead.md` - plan author reminder.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` - plan writer reminder.
- [ ] `.claude/agents/developer.md` - implementation author reminder.
- [ ] `.cursor/agents/developer.md` - implementation author reminder.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` - implementer reminder.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Requirement becomes generic documentation bureaucracy | Medium | Medium | Define applicability narrowly around complex workflow decision gates and preserve the short not-applicable rationale path |
| Wording drifts across spec, plan, implementation, review, and readiness surfaces | Medium | High | Keep matrix field names identical across all edited files and run a targeted consistency search before staging |
| Reviewers treat the matrix as replacing review or CI | Low | High | State in every primary surface that matrix evidence is additive and does not bypass internal review, automated reviewer loop, CI, readiness labels, tracker transitions, or human merge gates |
| Implementation overbuilds automatic detection | Medium | Medium | Keep MVP documentation-only and explicitly exclude scripts, labels, and machine-readable config |

---

## Code Samples

No production code samples are included. The implementation may include a small illustrative markdown table for the matrix shape, but it must be labeled as an example and not treated as a mandatory file format.

---

## Implementation Order

1. Update Protocol 01, Protocol 02, and Protocol 03 with the same matrix applicability definition, field names, and not-applicable rationale rule.
2. Update Protocol 91 and Protocol 92 so PR readiness requires applicable matrix evidence before `ready-for-human-review` without changing reviewer-loop, CI-loop, label, tracker, or merge authority behavior.
3. Update `REVIEW.md` so spec, plan, and code reviewers flag missing or contradictory matrix evidence for complex gate PRs and accept concise not-applicable rationales for non-gate documentation changes.
4. Update agent and skill guidance for product-manager/spec-writer, tech-lead/plan-writer, and developer/implementer roles so each role routes to the canonical protocol requirement instead of defining separate local semantics.
5. If the edited protocol text needs a central overview pointer, add a concise entry to `docs/workflow/development-workflow/README.md`; otherwise leave README unchanged and document the no-edit decision in the implementation PR body.
6. Run a consistency search for `consistency matrix`, `complex workflow decision gate`, `gate inputs`, `allowed outcomes`, `required next actions`, `mirror surfaces`, and `not applicable`; confirm every edited surface uses the same field names and applicability rule.
7. Run documentation validation:
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md" "docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md" "docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md" "REVIEW.md" ".claude/agents/product-manager.md" ".cursor/agents/product-manager.md" ".codex/skills/workflow-spec-writer/SKILL.md" ".claude/agents/tech-lead.md" ".cursor/agents/tech-lead.md" ".codex/skills/workflow-plan-writer/SKILL.md" ".claude/agents/developer.md" ".cursor/agents/developer.md" ".codex/skills/workflow-implementer/SKILL.md"`
   - `npx markdownlint-cli2 "docs/testing/workflow/1242-consistency-matrix-complex-workflow-decision-gates.smoke-test.md"` after updating the runbook if needed.
   - Run the smoke test runbook and confirm every assertion passes.
8. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR using:
   - `### Changed`
   - `- **Decision gate consistency matrix** (#1242): Added consistency-matrix evidence for complex workflow decision-gate documentation changes before PR readiness.`
