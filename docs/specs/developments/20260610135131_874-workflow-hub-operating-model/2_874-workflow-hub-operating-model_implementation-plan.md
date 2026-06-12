# Workflow Hub Operating Model and Artifact Ownership - Implementation Plan

**Spec**: [1_874-workflow-hub-operating-model_specs.md](1_874-workflow-hub-operating-model_specs.md)
**Smoke test runbook**: [874-workflow-hub-operating-model.smoke-test.md](../../../testing/workflow/874-workflow-hub-operating-model.smoke-test.md)

---

## Summary

**Approach**: Add a documentation-only architecture note at
`docs/workflow/development-workflow/repository-modes.md` that defines the three
supported repository modes, artifact ownership, PR routing, target repository
selection, and a generic multi-product hub example. Link the note from the root
`README.md` and `docs/workflow/development-workflow/README.md`.

**Estimated complexity**: S

**Rationale**: The implementation changes documentation only and does not alter
scripts, config parsing, CI workflows, reviewer integrations, or runtime
behavior. The main risk is incomplete or ambiguous ownership language, not code
complexity.

**Dependencies**: None. This is the first workflow-hub sub-item and establishes
terminology for later implementation work under #873.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `3144f30` |
| Existing workflow-hub references | `rg -n "workflow hub\|workflow_hub\|product_repo\|single_repo\|target product\|target repository" README.md docs/README.md docs/workflow/development-workflow/README.md docs/workflow/development-workflow docs/project AGENTS.md .ai-dev-workflow.yaml` | No existing repository-mode architecture note or mode definitions found. |
| Documentation location options | `find docs/workflow/development-workflow -maxdepth 2 -type d -print \| sort` | Existing workflow docs are organized under `integrations/`, `protocols/`, and `templates/`; a top-level workflow architecture note is appropriate. |
| README link targets | `rg -n "Repository Structure\|AI Development Workflow" README.md docs/workflow/development-workflow/README.md docs/README.md` | Root README has workflow overview sections; workflow README is the canonical workflow index. |
| Tracker brief and comments | `gh issue view 874 --json title,body,comments,labels,url` | Issue #874 is part of #873, has no scope-changing comments, and carries `integration-branch:workflow-hub-mode`. |

---

## Layer-by-Layer Changes

### Documentation Architecture

- [ ] Add `docs/workflow/development-workflow/repository-modes.md` as the
      canonical architecture note for repository modes.
- [ ] Define exactly these code values with display labels and user-facing
      descriptions: `single_repo`, `workflow_hub`, and `product_repo`.
- [ ] State that a missing mode declaration is interpreted as `single_repo`.
- [ ] Add an artifact ownership table covering:
      backlog/tracker items, specs, plans, hub-owned smoke runbooks,
      product-owned smoke runbooks, implementation branches, spec PRs, plan PRs,
      code PRs, CI checks, and reviewer-loop checks.
- [ ] State where spec, plan, and code PRs are opened in each mode.
- [ ] Define target product repository selection for hub-managed work items,
      including the rule that missing or ambiguous targets are flagged before
      product implementation routing.
- [ ] Distinguish content that lives in the workflow hub from framework-owned
      content that may be injected into product repositories.
- [ ] Include a generic multi-product hub example without private project,
      repository, or team names.
- [ ] Explicitly state that this item introduces no runtime behavior changes or
      migration requirement for existing adopters.

### Root Documentation Links

- [ ] Update `README.md` to link to the repository modes architecture note from
      the development workflow section or nearby workflow overview.
- [ ] Update `docs/workflow/development-workflow/README.md` to link to the
      repository modes architecture note from the workflow documentation index
      or architecture/configuration section.

### Database / Data Layer

- [ ] None. No schema, migration, seed, or data model changes.

### Backend / API

- [ ] None. No scripts, services, APIs, or workflow automation behavior changes.

### Shared Packages / Libraries

- [ ] None.

### Frontend / UI

- [ ] None.

### Infrastructure / Configuration

- [ ] None. Do not add mode declarations to `.ai-dev-workflow.yaml` in this
      item; later implementation items can introduce config keys once behavior
      exists.

---

## Testing Strategy

**Test types**: Markdown lint, documentation smoke/manual verification.

**Key scenarios to test**:

1. Repository modes are defined with display labels and descriptions (AC1).
2. The architecture note is linked from both required entry points (AC2).
3. Missing mode defaults to `single_repo` and preserves current behavior (AC3,
   AC9).
4. Artifact ownership and PR routing tables cover every artifact named in the
   spec (AC4, AC5).
5. Target repository selection is visible and missing or ambiguous targets are
   flagged before implementation routing (AC6).
6. Hub-owned content and product-injected content are distinct (AC7).
7. The example is generic and contains no private project details (AC8).
8. The diff is documentation-only (AC10).

**Smoke test runbook**:
`docs/testing/workflow/874-workflow-hub-operating-model.smoke-test.md`

**Regression suite**: No automated product regression suite applies because the
implementation is documentation-only. Use markdown lint and the smoke runbook.

### Parser-risk Addendum

Not applicable. The implementation does not add parser, scanner, regex, lint, or
structured-text processing behavior.

### Concurrent-Event-Source Addendum

Not applicable. The implementation does not introduce event listeners, timers,
async queues, or shared mutable runtime state.

---

## Seed Data

None.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/repository-modes.md` - new canonical
      architecture note for repository modes and artifact ownership.
- [ ] `README.md` - link to the repository modes note.
- [ ] `docs/workflow/development-workflow/README.md` - link to the repository
      modes note.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` / `### Added` entry:
      `- **Workflow hub operating model** (#874): documents repository modes, artifact ownership, target repository selection, and PR ownership for workflow hub deployments.`

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The ownership table omits an artifact type from the spec. | Medium | Medium | Use the smoke runbook to check every named artifact: backlog/tracker items, specs, plans, smoke runbooks, implementation branches, PRs, CI checks, and reviewer-loop checks. |
| The note appears to introduce behavior that later scripts must already support. | Medium | Medium | Include explicit "documentation-only, no runtime behavior change" language and avoid adding config keys in this item. |
| The target repository rule over-specifies the future storage format. | Medium | Medium | Define required properties of the value, not the concrete storage mechanism; leave storage details to later implementation items. |
| The example leaks private project details. | Low | Medium | Use generic names such as `workflow-hub`, `mobile-app`, and `admin-portal`. |

---

## Code Samples

No code samples. The only structured examples should be documentation tables and
generic repository-mode examples.

---

## Implementation Order

1. Create `docs/workflow/development-workflow/repository-modes.md`.
2. In the note, add sections for:
   - Supported repository modes.
   - Missing-mode default.
   - Artifact ownership by mode.
   - PR ownership by mode.
   - Target product repository selection.
   - Hub-owned versus product-injected framework content.
   - Generic multi-product hub example.
   - Non-goals and current behavior preservation.
3. Update `README.md` to link to the note from the development workflow
   overview.
4. Update `docs/workflow/development-workflow/README.md` to link to the note
   from the workflow documentation/configuration area.
5. Add the CHANGELOG entry under `[Unreleased]` / `### Added` using the literal
   from **Documentation Updates**.
6. Run the smoke test runbook and confirm all assertions pass.
7. Run markdown validation:
   - `npx markdownlint-cli2 "README.md" "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/874-workflow-hub-operating-model.smoke-test.md" "CHANGELOG.md"`
   - `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/874-workflow-hub-operating-model.smoke-test.md CHANGELOG.md`
   - `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
8. Run `git diff --name-only` and confirm the implementation diff is
   documentation-only.
9. Open a draft implementation PR targeting `develop-workflow-hub-mode` and run
   the standard plan review, automated reviewer, and CI loops before marking it
   ready for human review.
