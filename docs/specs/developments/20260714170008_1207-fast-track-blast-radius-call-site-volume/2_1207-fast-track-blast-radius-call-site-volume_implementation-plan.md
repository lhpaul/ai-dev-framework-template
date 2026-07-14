# Fast Track Blast Radius Call-Site Volume — Implementation Plan

**Spec**: [1_1207-fast-track-blast-radius-call-site-volume_specs.md](1_1207-fast-track-blast-radius-call-site-volume_specs.md)
**Smoke test runbook**: [1207-fast-track-blast-radius-call-site-volume.smoke-test.md](../../../testing/workflow/1207-fast-track-blast-radius-call-site-volume.smoke-test.md)

---

## Summary

**Approach**: Extend the Work Item Runner Fast Track routing gate so it evaluates call-site volume and external-system impact before dispatching bug/simple-change work directly to implementation. Keep Protocol 91 as the authoritative routing definition, then mirror the criteria in the workflow overview, implementation protocol Fast Track criteria, and direct-entry developer guidance.

**Estimated complexity**: S

**Rationale**: This is a documentation/protocol change with no runtime code, database schema, or migration work. The main risk is cross-reference drift across workflow surfaces that mention Fast Track eligibility.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and issue #1207 brief | `template.is_template: true`; issue improves template workflow routing and is framework-generic |
| Existing Fast Track routing surfaces | `rg -l "Cross-layer scope check|No multi-layer scope signals|Fast track is the shortened path|Fast Track \\(Bug / Simple Change\\)" docs/workflow/development-workflow/README.md docs/workflow/development-workflow/protocols/03-implement-development-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | 3 core files: README, Protocol 03, Protocol 91 |
| Direct Fast Track implementer guidance | `grep -rl "03-implement-development-protocol\\|Fast Track\\|fast-track" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ 2>/dev/null` | 3 direct-entry files: `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `.codex/skills/workflow-implementer/SKILL.md` |
| Protocol 91 reference fan-out | `grep -rl "91-orchestrate-work-protocol" .claude/agents/ .claude/commands/ .cursor/agents/ .cursor/commands/ .codex/skills/ .agents/skills/ docs/workflow 2>/dev/null` | 30 files reference Protocol 91; most should continue to rely on the canonical protocol without duplicated criteria |
| Parser/concurrency classification | `rg -n "parser|scanner|regex|structured-text|concurrent|listener|timer|queue|shared mutable|call-site|ripgrep|grep" docs/specs/developments/20260714170008_1207-fast-track-blast-radius-call-site-volume/1_1207-fast-track-blast-radius-call-site-volume_specs.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Parser-risk: no custom parser or scanner implementation planned; ordinary `rg`/`grep` examples only. Concurrent-event-source: not applicable |

---

## Layer-by-Layer Changes

### Workflow Protocols and Documentation

- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — rename the Fast Track routing subsection from cross-layer-only wording to a broader blast-radius check that includes cross-layer signals, call-site volume, and external-system impact.
- [ ] In Protocol 91, define the call-site check sequence:
  1. Identify the primary entity being renamed or modified when the issue brief or linked artifact makes one identifiable.
  2. Run a bounded repository search over non-test source references when an entity is identifiable.
  3. Treat high volume as a planning-risk signal, not proof that every reference requires code edits.
  4. Record the routing evidence in the Work Item Runner summary.
- [ ] In Protocol 91, document the MVP threshold as high volume when either more than 15 non-test source files or more than 30 non-test source occurrences reference the primary entity.
- [ ] In Protocol 91, define non-test source references as source/config/workflow files that are not test/spec/fixture files, docs, generated artifacts, lockfiles, or changelog entries.
- [ ] In Protocol 91, define the routing outcomes:
  - Cross-layer signal present: route to Full Pipeline.
  - High call-site volume present: route to Full Pipeline unless the human explicitly overrides.
  - Primary entity ambiguous: record why the check is not applicable, or ask for clarification when the ambiguity prevents a defensible Fast Track decision.
  - Known or likely external-system impact: route to Full Pipeline or require a tracked pre-flight follow-up before any later Fast Track dispatch.
- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — mirror the Fast Track criteria so direct Path 3 entry checks call-site volume and external-system impact before implementation.
- [ ] Update `docs/workflow/development-workflow/README.md` — describe call-site volume as the blast-radius complement to layer presence in the Fast Track overview.

### Agent and Skill Guidance

- [ ] Update `.claude/agents/developer.md` — replace the generic "stop if scope expands" Fast Track reminder with a pointer to the Protocol 91 blast-radius routing gate and Protocol 03 criteria.
- [ ] Update `.cursor/agents/developer.md` — mirror the Claude developer reminder.
- [ ] Update `.codex/skills/workflow-implementer/SKILL.md` — add a concise instruction that Fast Track work must have passed the Protocol 91 blast-radius gate and must stop if call-site volume or external-system impact is discovered after dispatch.

### Not Modified

- `CHANGELOG.md` — plan-only PRs are exempt. The later implementation PR should add a `Changed` entry under `[Unreleased]`.
- `REVIEW.md` — no new review checklist category is required. Existing plan/code review checks already cover cross-section consistency, policy text changes, and documentation PR quality.
- `scripts/development-workflow/*` — no script behavior is planned for MVP. The gate stays human-readable and runner-executable through protocol instructions.
- `.agents/skills/run-item/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`, and slash-command wrappers — no edits needed because they delegate to Protocol 91 rather than duplicating Fast Track criteria.

---

## Cross-Cutting Workflow Guidance

**Classification**: Applies. This plan modifies a routing safety gate that affects future Fast Track decisions across independent work items.

**Full enumeration decision**:

| Surface | Action |
| --- | --- |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Primary authoritative change |
| `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Mirror direct Fast Track implementation criteria |
| `docs/workflow/development-workflow/README.md` | Mirror workflow overview |
| `.claude/agents/developer.md` | Add direct-entry reminder |
| `.cursor/agents/developer.md` | Add direct-entry reminder |
| `.codex/skills/workflow-implementer/SKILL.md` | Add direct-entry reminder |
| `REVIEW.md` | No edit; existing checks cover policy consistency and documentation PRs |
| Tech-lead agent/skill files | No edit; this affects Fast Track routing and implementation entry, not plan writing behavior |
| Item-orchestrator skills/commands | No edit; they already load Protocol 91 as authoritative |

---

## Parser, API, and Concurrency Classification

**Parser-risk**: Not applicable. The implementation should document ordinary literal-search examples using existing shell tools; it must not add a custom parser, scanner, tokenizer, regex engine, or structured-text rule engine.

**API-surface changes**: Not applicable. No CLI flags, schema fields, public functions, or machine-readable config keys are added in MVP.

**Concurrent-event-source**: Not applicable. The change does not introduce listeners, timers, queues, async callbacks, or shared mutable runtime state.

---

## Testing Strategy

**Test types**: Documentation verification, markdown lint, targeted grep checks, and human-readable smoke test runbook.

**Key scenarios to test**:

1. Fast Track routing guidance requires call-site volume before direct implementation dispatch — maps to AC-1, AC-3, AC-4.
2. High call-site volume and cross-layer signals independently block Fast Track — maps to AC-2, AC-5.
3. Ambiguous primary entity has an explicit routing outcome — maps to AC-6.
4. Workflow overview documents call-site volume as distinct from layer presence — maps to AC-7.
5. External-system impact is checked and blocks immediate Fast Track when known or likely — maps to AC-8, AC-9.
6. Thresholds and search mechanics are documented in Protocol 91 without introducing a script/config dependency — maps to AC-10.

**Smoke test runbook**: `docs/testing/workflow/1207-fast-track-blast-radius-call-site-volume.smoke-test.md`

**Regression suite**: No automated regression suite is configured for workflow documentation. Use markdown lint plus the smoke runbook checks.

---

## Seed Data

None. This workflow documentation change has no database, fixture, or seed-data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — authoritative Work Item Runner routing gate.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — direct Fast Track criteria mirror.
- [ ] `docs/workflow/development-workflow/README.md` — Fast Track overview.
- [ ] `.claude/agents/developer.md` — developer role reminder.
- [ ] `.cursor/agents/developer.md` — developer role reminder.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` — Codex implementer skill reminder.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Criteria drift between Protocol 91, Protocol 03, and README | Medium | Medium | Keep Protocol 91 authoritative; mirror only concise eligibility language elsewhere |
| Call-site threshold feels overly precise for all repos | Medium | Low | Document threshold as an MVP default and planning-risk signal that humans can override explicitly |
| Search examples accidentally count tests/docs and over-promote work | Medium | Medium | Define non-test source exclusions and require the routing summary to state the search scope |
| External-system prompt becomes vague and non-actionable | Low | Medium | Require one of three recorded outcomes: no signal, signal found, or clarification required |

---

## Code Samples

No production code samples are included. The implementation may include short illustrative shell snippets in protocol text, but they must be marked as examples and kept human-readable.

---

## Implementation Order

1. Update Protocol 91's Fast Track routing subsection to the new blast-radius gate, preserving the existing deterministic cross-layer rule and adding call-site volume plus external-system impact.
2. Add the Protocol 91 threshold and search-scope mechanics: identifiable primary entity, non-test source references, more than 15 files or more than 30 occurrences, explicit override requirement, and summary evidence.
3. Update Protocol 03 Path 3 criteria so direct Fast Track implementation requires the same blast-radius gate before coding.
4. Update the README Fast Track overview to state that call-site volume is a propagation-breadth check distinct from architectural layer presence.
5. Add concise direct-entry reminders to `.claude/agents/developer.md`, `.cursor/agents/developer.md`, and `.codex/skills/workflow-implementer/SKILL.md`.
6. Run a cross-reference consistency check:
   - Search for `Fast Track`, `cross-layer scope check`, `call-site volume`, and `external-system impact`.
   - Confirm Protocol 91 remains authoritative and mirrored surfaces do not contradict the threshold, routing outcome, or external-system wording.
7. Run markdown/document checks:
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/README.md" "docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" ".claude/agents/developer.md" ".cursor/agents/developer.md" ".codex/skills/workflow-implementer/SKILL.md"`
   - Run the smoke test runbook and confirm every assertion passes.
8. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR using:
   - `### Changed`
   - `- **Fast Track blast-radius routing** (#1207): Added call-site volume and external-system impact checks before Fast Track dispatch.`
