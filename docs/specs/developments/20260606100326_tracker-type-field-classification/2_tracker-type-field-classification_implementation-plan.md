# Tracker Type Field Classification — Implementation Plan

**Spec**: Refactor work item #828 brief
**Smoke test runbook**: [tracker-type-field-classification.smoke-test.md](../../../testing/workflow/tracker-type-field-classification.smoke-test.md)

---

## Summary

**Approach**: Make the GitHub Projects `Type` field the classification source of
truth for workflow items, add a `Workflow` Type option, and stop relying on
repository labels for Bug/Feature/Workflow classification. Keep operational labels
unchanged because they trigger automation and review gates. Replace cheap
`workflow` label filters with targeted project-field queries or open-issue plus
project cross-reference flows so the implementation does not reintroduce the
GraphQL budget drain addressed by #824.

**Estimated complexity**: L

**Rationale**: The change spans tracker integration guidance, release and
retrospective protocols, backlog creation/classification conventions, smoke tests,
and helper behavior. It also includes a migration and project-board configuration
step that cannot be represented by repository file edits alone.

**Dependencies**: #824 must remain merged because this refactor depends on
targeted GitHub Projects lookups rather than repeated full-board scans.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `a8eb835e4fcab978f0aae16f974333b70590d648` |
| Workflow-label filters | `rg -n "gh issue list --label workflow|--label \"workflow\"|--label workflow" docs scripts .claude .cursor .codex AGENTS.md --glob '!docs/specs/developments/**'` | In-scope current references: `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`, `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`, and `docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md`. |
| Type-label setup guidance | `rg -n "type:feature|type:bug|type:refactor|Type labels" docs/workflow/development-workflow/integrations docs/workflow/development-workflow/protocols --glob '!docs/specs/developments/**'` | Current type-label guidance is concentrated in `docs/workflow/development-workflow/integrations/github-projects.md`; `linear.md` separately documents Linear type labels. |
| Type-field guidance | `rg -n "Type.*Single select|project.*Type|Type field|Workflow" docs/workflow/development-workflow scripts AGENTS.md --glob '!docs/specs/developments/**'` | GitHub Projects docs define `Type` as `Feature`, `Bug`, `Refactor`; Protocol 90 already references tracker Type for Backlog routing; no reusable helper exists yet for querying Workflow-typed open issues. |

## Layer-by-Layer Changes

### Tracker / GitHub Projects Integration

- [ ] Update `docs/workflow/development-workflow/integrations/github-projects.md`
      to define the project `Type` field as the classification source of truth.
- [ ] Add `Workflow` as a required `Type` option for framework workflow items.
- [ ] State that repository labels `bug`, `enhancement`, `type:feature`,
      `type:bug`, `type:refactor`, and `workflow` are legacy classification
      labels and should not be applied by new workflow automation.
- [ ] Preserve operational labels such as `ready-for-human-review`,
      `needs-fixes`, `ready-for-regression`, `reviewer-failed`,
      `feedback-staging`, and `integration-branch:<slug>`.
- [ ] Document the board migration: backfill Type values from current labels and
      issue context, then remove retired classification labels from open workflow
      issues after the Type field is populated.

### Workflow Scripts / Helpers

- [ ] Add or extend GitHub Projects helpers in
      `scripts/development-workflow/workflow-lib.sh` for targeted Type-field
      access:
      - read an issue's Type value through the targeted project item query;
      - set an issue's Type value best-effort;
      - list open issues whose project Type is `Workflow` without per-item
        full-board scans.
- [ ] Ensure the list helper uses the #824-safe discovery shape: fetch open
      issues first, then cross-reference a single project item-list result, or
      use a targeted GraphQL query that does not paginate all closed items.
- [ ] Add tests in
      `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
      for Type field metadata lookup, Type update mutation construction, and
      open Workflow issue filtering.

### Protocols

- [ ] Update
      `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`
      so GitHub Projects backlog creation sets the project Type field when the
      type/path is known, rather than instructing agents to use classification
      labels.
- [ ] Update
      `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      to replace `gh issue list --label workflow` with the new Workflow Type
      discovery helper or equivalent Type-field query.
- [ ] Update
      `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`
      so retrospective backlog checks and issue creation use project Type
      `Workflow` instead of the `workflow` label.
- [ ] Update
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      to clarify that tracker Type, not labels, determines Backlog route for
      GitHub Projects items.
- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      where single-item routing discusses Backlog Feature/Bug/Refactor
      classification, making tracker Type authoritative for GitHub Projects.

### Agent / Skill Guidance

- [ ] Update `AGENTS.md` GitHub/tracker conventions to mention the `Workflow`
      Type option and retired classification labels.
- [ ] Do not update `.codex/skills/workflow-orchestrator/SKILL.md`; it delegates
      to Protocol 90 and contains no direct classification-label instruction.
- [ ] Do not update `.codex/skills/workflow-item-orchestrator/SKILL.md`; it
      delegates to Protocol 91 and contains no direct classification-label
      instruction.
- [ ] Update Claude/Cursor orchestrator and run-work entry points to mirror the
      tracker classification rule from `AGENTS.md`, because those entry points
      read and route Backlog work directly.

### Tests and Smoke Runbooks

- [ ] Update `docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md`
      so its temporary issue setup no longer applies the `workflow` label.
- [ ] Add or update a smoke runbook for this refactor:
      `docs/testing/workflow/tracker-type-field-classification.smoke-test.md`.
- [ ] Run the workflow-lib GitHub Projects test harness after helper changes.
- [ ] Run markdown lint over the changed protocol, integration, and smoke-test
      docs.

## Testing Strategy

**Test types**: shell unit tests, markdown lint, smoke/manual tracker verification.

**Key scenarios to test**:

1. A GitHub Projects item with Type `Workflow` is discovered as workflow backlog
   without relying on a `workflow` label.
2. A GitHub Projects item with Type `Bug` routes to the fast-track/fix path even
   when it has no `bug` label.
3. A GitHub Projects item with Type `Refactor` routes to the plan-only refactor
   path even when it has no `type:refactor` label.
4. Operational labels still drive PR readiness and CI behavior.
5. Release and retrospective protocols can find workflow items through Type-based
   discovery.

**Smoke test runbook**: `docs/testing/workflow/tracker-type-field-classification.smoke-test.md`

**Regression suite**: Add workflow-lib shell tests for Type-field helper behavior.

## Seed Data

No permanent seed data is required. Smoke testing uses temporary GitHub issues on
the configured project board and deletes or closes them at the end of the run.

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` —
      document the Type taxonomy, `Workflow` option, retired classification
      labels, and migration steps.
- [ ] `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`
      — route backlog creation/classification through project Type.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      — replace `workflow` label discovery with Workflow Type discovery.
- [ ] `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`
      — replace `workflow` label issue creation/filtering with Workflow Type.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — clarify Type-based Backlog routing and proposal eligibility.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — clarify Type-based single-item Backlog routing.
- [ ] `AGENTS.md` — document the project Type convention and retired labels.
- [ ] `docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md` —
      remove the `workflow` label from temporary issue setup.
- [ ] `docs/testing/workflow/tracker-type-field-classification.smoke-test.md` —
      add the manual smoke runbook for this refactor.
- [ ] `CHANGELOG.md` — add a `### Changed` entry for #828 using the format below.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Type-field discovery reintroduces GraphQL budget drain. | Medium | High | Reuse the #824 targeted-query pattern and add tests that fail if helpers call per-item full-board scans. |
| Removing label-based filters misses workflow items whose Type is unset. | Medium | High | Include an explicit migration step and fail-soft warnings for open workflow-labeled items with missing Type. |
| Operational labels are accidentally retired with classification labels. | Low | High | Document the allow-list of operational labels and keep PR readiness protocols unchanged. |
| Downstream projects have not created a `Workflow` Type option yet. | Medium | Medium | Document setup/migration steps and make helpers warn clearly when the option is absent. |

## Code Samples

No production code samples are required in the plan. The implementation should
prefer small Bash helper functions in `workflow-lib.sh` that mirror the existing
targeted Status helpers.

## Implementation Order

1. Add `Workflow` Type setup and retired-label guidance to the GitHub Projects
   integration document.
2. Add Type field read/update/discovery helpers to `workflow-lib.sh`, reusing the
   existing targeted project item lookup and Status field metadata patterns.
3. Add workflow-lib tests for Type helper success, missing-option warnings, and
   Workflow Type discovery.
4. Update Protocol 00 so backlog creation sets Type instead of classification
   labels when GitHub Projects is configured.
5. Update Protocol 05 and Protocol 06 to replace `workflow` label filters with
   Workflow Type discovery.
6. Update Protocol 90 and Protocol 91 to make tracker Type authoritative for
   Backlog route classification under GitHub Projects.
7. Update `AGENTS.md` and the affected smoke-test docs listed above.
8. Run markdown lint for changed docs and the workflow-lib test harness.
9. Add this CHANGELOG entry under `[Unreleased]` → `### Changed`:
   `- **Tracker Type field classification** (#828): makes GitHub Projects Type the source of truth for workflow item classification, adds the Workflow Type convention, and retires repository labels for bug/enhancement/workflow classification while preserving operational PR labels.`
