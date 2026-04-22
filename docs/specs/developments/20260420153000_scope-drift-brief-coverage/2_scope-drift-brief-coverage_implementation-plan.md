# Scope Drift Brief Coverage — Implementation Plan

**Spec**: [`1_scope-drift-brief-coverage_specs.md`](./1_scope-drift-brief-coverage_specs.md)  
**Smoke test runbook**: [`docs/testing/workflow/186-scope-drift-brief-coverage.smoke-test.md`](../../../testing/workflow/186-scope-drift-brief-coverage.smoke-test.md)

---

## Summary

**Approach**: Update workflow documentation and review rubrics so spec-writers and plan-writers cannot silently drop brief objectives or copy stale enumerations when pattern-based completeness is intended. Changes are confined to Markdown: `01-generate-spec-protocol.md` (Brief Objective List, Coverage Matrix, PR-body requirements, deferral notes), `02-generate-implementation-plan-protocol.md` (mandatory live search vs spec-frozen enumeration, **Verification Log** block in every plan), `REVIEW.md` (blocking checklist bullets for spec and plan per AC6–AC7), and optional one-line cross-links in `product-manager` / `tech-lead` agent entrypoints so dispatched agents open the right protocol sections. Add a small **committed fixture** under `docs/testing/workflow/fixtures/` for AC5 manual verification: the fixture text claims pattern-wide coverage while listing too few concrete paths. The developer proves the updated plan-writer rules by recording a live `rg` in the Verification Log and aligning Summary counts with that output, not with the stale list.

**Estimated complexity**: M  
**Rationale**: Several files must stay mutually consistent (protocols ↔ `REVIEW.md` ↔ smoke runbook ↔ optional agent stubs). AC5 needs a reproducible grep command and a stable fixture path so reviewers are not asked to invent repo state.

**Dependencies**: None (`Depends on: none` in spec).

---

## Verification Log (plan-write time)

| Check | Command / note | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` (run at authoring time in worktree) | `f74c5cd` |
| Spec file presence | `test -f docs/specs/developments/20260420153000_scope-drift-brief-coverage/1_scope-drift-brief-coverage_specs.md` | present |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] None

### Backend / API

- [ ] None

### Shared Packages / Libraries

- [ ] None

### Frontend / UI

- [ ] None

### Infrastructure / Configuration

- [ ] None

### Documentation / Workflow (primary surface)

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` — insert a dedicated subsection after alignment (or within Step 3 quality guardrails) documenting Brief Objective List, Coverage Matrix, PR description summary, and Deferral Notes per UC1–UC3, BR-1–BR-3; wire Step 5 PR body bullet to require the matrix summary — **AC3**
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — add plan-writer rules for pattern vs frozen enumeration, mandatory Verification Log (command, repo SHA, outputs affecting counts/paths), and cross-links to UC4–UC5 — **AC4**
- [ ] `REVIEW.md` — extend **Spec Review Checklist** with a blocking bullet: when a tracker issue is linked, verify brief-to-spec coverage (matrix or equivalent trace) — **AC6**; extend **Plan Review Checklist** with a blocking bullet: when pattern-based completeness applies, verify counts/paths against the plan’s Verification Log — **AC7**
- [ ] `.claude/agents/product-manager.md` and `.cursor/agents/product-manager.md` — add a single sentence pointing to the new brief-coverage subsection in protocol 01 (optional but recommended for discoverability) — supports **AC3**
- [ ] `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md` — add a single sentence pointing to enumeration vs live-search rules in protocol 02 — supports **AC4**
- [ ] `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md` — new synthetic excerpt: states “all files matching pattern P” while listing fewer concrete paths than a live search returns in today’s repo — **AC5** input
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md` and `.codex/skills/workflow-plan-writer/SKILL.md` — if either duplicates protocol steps inline, add one line each referencing the new mandatory checks (skills remain thin wrappers) — **AC3**, **AC4**

---

## Testing Strategy

**Test types**: Manual / documentation smoke (no automated unit tests).

**Key scenarios to test**:

1. Protocol 01 documents matrix + deferral PR requirements — maps to **AC3**, **AC2**, **AC1** (synthetic brief scenario described in smoke runbook)
2. Protocol 02 documents Verification Log + pattern-vs-freeze — maps to **AC4**
3. Fixture + live `rg` proves plan text cannot copy stale counts — maps to **AC5**
4. `REVIEW.md` lists new blocking bullets — maps to **AC6**, **AC7**

**Smoke test runbook**: [`docs/testing/workflow/186-scope-drift-brief-coverage.smoke-test.md`](../../../testing/workflow/186-scope-drift-brief-coverage.smoke-test.md)

**Regression suite**: None beyond existing markdownlint / CI on touched paths.

---

## Seed Data

| Entity | Values / Scenario | File |
|---|---|---|
| Synthetic stale enumeration | Fixture markdown for AC5 | `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md` (new) |

---

## Documentation Updates

Files the developer edits during implementation (this plan already targets them; no separate `docs/project/*` churn unless review finds a glossary gap):

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
- [ ] `REVIEW.md`
- [ ] `docs/testing/workflow/186-scope-drift-brief-coverage.smoke-test.md` (created in Plan Ready stage alongside this file)
- [ ] `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md` (new in Development)
- [ ] `.claude/agents/product-manager.md`, `.cursor/agents/product-manager.md` (optional cross-link)
- [ ] `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md` (optional cross-link)
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md` (optional one-liners)

**None** for `AGENTS.md` / `docs/project/*` unless the implementation PR discovers a broken link after renames.

- [ ] `docs/workflow/development-workflow/integrations/issue-tracker.md` — only if protocol edits assume GitHub-only fields; add a short tracker-agnostic note per spec **Out of Scope (MVP)** (non-GitHub trackers)

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Protocol text becomes too long; agents skip it | Med | Med | Use scannable headings + a short checklist table at the top of each new subsection |
| AC5 fixture drifts as repo grows | Low | Med | Fixture uses a **stable path subset** (e.g. only `docs/workflow/development-workflow/protocols/*.md`) and documents the exact `rg` pattern so counts remain meaningful |
| Parallel wording between 01/02 protocols and `REVIEW.md` diverges | Med | Med | Single source of truth in protocols; `REVIEW.md` bullets only point to behaviors already spelled out there |

---

## Code Samples

None (documentation-only work).

---

## Implementation Order

1. Add fixture `docs/testing/workflow/fixtures/186-scope-drift-pattern-enumeration-mismatch.md` so AC5 verification is reproducible — **AC5**
2. Update `01-generate-spec-protocol.md` with Brief Objective List, Coverage Matrix, PR description requirements, deferral visibility — **AC1**, **AC2**, **AC3**
3. Update `02-generate-implementation-plan-protocol.md` with live-search vs freeze rules and Verification Log template — **AC4**
4. Update `REVIEW.md` spec and plan checklists — **AC6**, **AC7**
5. Optional: agent entrypoint files and Codex skill one-liners — supports discoverability for **AC3**, **AC4**
6. Run markdownlint on touched Markdown paths per `AGENTS.md`; fix violations
7. Update `CHANGELOG.md` under `[Unreleased]` with an entry for the **feature implementation** PR (protocol / `REVIEW.md` / fixture changes), following `AGENTS.md` conventions
8. Execute smoke runbook steps on the implementation PR branch before marking development done

Each step should leave the repo internally consistent (no dangling references to headings that do not exist).
