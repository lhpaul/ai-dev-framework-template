# Native GitHub Issue Type Classification — Implementation Plan

**Spec**: [Native GitHub Issue Type Classification](1_1280-native-github-projects-issue-type_specs.md)
**Smoke test runbook**: [Native GitHub Issue Type Classification](../../../testing/workflow/native-github-projects-issue-type.smoke-test.md)

---

## Summary

**Approach**: Extend the existing targeted GitHub Projects GraphQL lookup so
each project item also returns its issue content's native `issueType`. Insert
that value into the helper's single precedence-ordered candidate list between
the configured project field and the conventional custom fields, then expand
the existing shell regression harness to prove every precedence and warning
branch.

**Estimated complexity**: S

**Rationale**: The production change is localized to one GraphQL selection and
one JSON parsing block, with no new helper or consumer contract. Most of the
work is deterministic fixture coverage for the complete classification matrix.

**Dependencies**: None. The merged spec defines the precedence contract, and
GitHub's live GraphQL schema exposes `ProjectV2Item.content` as
`ProjectV2ItemContent` and `Issue.issueType` as `IssueType`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Existing classification aliases | `rg -n "configuredType\|customType\|compactCustomType\|fieldValueByName\\(name: \\"Type\\"\\)\|type_candidates" scripts/development-workflow/workflow-lib.sh` | One targeted query and parser block in `workflow_github_project_item_for_issue`; current order is configured field, `Custom Type`, `CustomType`, then `Type`. |
| Shared production consumer | `rg -n "get_tracker_type_for_issue" scripts/development-workflow --glob "*.sh" --glob "!workflow-lib.sh"` | `scripts/development-workflow/run-epic-scope-resolver.sh` consumes the shared result; no second production parser was found. |
| Regression harness | `rg -n "MOCK_PROJECT_ITEM_MODE\|targeted_type_read\|missing_named_fields" scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` | The existing shell harness already mocks project-item GraphQL responses and asserts classification plus missing-field warnings. |
| GitHub GraphQL schema | `gh api graphql` introspection for `Issue.issueType` and `ProjectV2Item.content` | `Issue.issueType` is an `IssueType` object; `ProjectV2Item.content` is the `ProjectV2ItemContent` union, so an inline `... on Issue` fragment is the compatible query shape. |
| Documentation surface | `rg -n "get_tracker_type_for_issue\|custom_fields.type_field\|Custom Type" docs/workflow/development-workflow/integrations/github-projects.md` | The GitHub Projects integration guide documents the current custom-field-only precedence and needs the native source added. |
| Design assets | Issue #1280 body, tracker attachments, linked files, and `find docs/specs/developments/20260723110048_1280-native-github-projects-issue-type -maxdepth 2 -type d -name assets` | No UI scope or design assets; no fidelity step is required. |

---

## Layer-by-Layer Changes

### Workflow Helper / GitHub API Boundary

- [ ] In
  `scripts/development-workflow/workflow-lib.sh`,
  extend `workflow_github_project_item_for_issue`'s existing
  `projectItems.nodes` selection with
  `content { ... on Issue { issueType { name } } }` (AC-1, AC-8).
- [ ] In the same helper's Python parser, read `content` defensively, accepting
  absent, null, or non-object content as an empty native candidate rather than
  raising an exception (AC-6, BR-4).
- [ ] Keep one ordered `type_candidates` list with the exact order:
  configured project field, native Issue Type, `Custom Type`, `CustomType`,
  `Type`. Preserve the existing first-non-empty loop as the enforcement
  mechanism for deterministic precedence (AC-3, AC-4, AC-5, BR-2, BR-3).
- [ ] Continue deriving both returned `type` and `MISSING_FIELDS=Type` from the
  selected candidate. This existing shared `type_value`/missing-list mechanism
  ensures native-only classification returns `Feature` without the
  missing-classification warning, while fully empty inputs retain the warning
  (AC-1, AC-2, AC-7).
- [ ] Do not change `get_tracker_type_for_issue`,
  `run-epic-scope-resolver.sh`, update helpers, routing rules, or value
  normalization. They already consume the shared compact JSON `type` value
  and therefore inherit the new source without a second implementation
  (AC-8, BR-7).

### Automated Regression Harness

- [ ] In
  `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`,
  add focused mock project-item responses for native-only, all-sources
  precedence, null/absent native fallback, and fully empty classification
  (AC-1 through AC-8).
- [ ] Assert the recorded GraphQL call requests `issueType`, so a parser-only
  change cannot pass while the real query still omits the native value (AC-1,
  AC-8).
- [ ] Reuse the harness's stderr capture to prove native-only classification
  omits the existing missing-Type warning and the all-empty fixture still
  emits it (AC-2, AC-7).
- [ ] Preserve the existing no-full-board-scan assertion. The change remains
  inside the targeted `repository.issue(...).projectItems` query and must not
  introduce `gh project item-list` calls (BR-8).

### Documentation

- [ ] Update
  `docs/workflow/development-workflow/integrations/github-projects.md`
  so the Type-read documentation states the full configured → native →
  `Custom Type` → `CustomType` → `Type` precedence. Keep write-helper
  documentation scoped to project single-select fields because this feature
  does not change native Issue Type mutation (BR-2 and Out of Scope).

### Release Documentation

- [ ] Add the following entry under `CHANGELOG.md` → `[Unreleased]` →
  `### Fixed`:
  `- **Recognize native GitHub Issue Types** (#1280): classify GitHub Projects items from native Issue Type while preserving configured and custom field precedence.`

No database, frontend, infrastructure, generated artifact, or persistent seed
data changes are required.

---

## Classification Decision Matrix

This plan modifies a workflow classification decision gate, so implementation
and review must keep these inputs, outcomes, and next actions aligned with the
spec.

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Regression example |
| --- | --- | --- | --- | --- |
| Configured value non-empty; native/custom values may also exist | Return configured value | Stop at the first candidate and continue typed routing | Helper parser, integration guide, tests | `Workflow` beats native `Feature` and custom `Bug` |
| Configured empty; native name non-empty | Return native name | Continue typed routing with no missing-Type warning | GraphQL query, helper parser, tests, smoke runbook | Native `Feature` returns `Feature` |
| Configured/native empty; `Custom Type` non-empty | Return `Custom Type` | Continue the established custom fallback | Helper parser, integration guide, tests | `Refactor` beats lower custom aliases |
| Higher candidates empty; `CustomType` non-empty | Return `CustomType` | Continue the established custom fallback | Helper parser, integration guide, tests | `Bug` beats `Type=Workflow` |
| Higher candidates empty; `Type` non-empty | Return `Type` | Continue the established custom fallback | Helper parser, integration guide, tests | `Workflow` remains supported |
| `content` or native `issueType` absent, null, empty, or non-object; custom value exists | Return first non-empty custom value | Ignore unusable native data and continue normally | Defensive parser and tests | Null native value falls back to `Custom Type` |
| All candidates empty | Return empty type | Preserve the existing missing-Type warning and untyped workflow result | Helper warning, tests, smoke runbook | Empty fixture warns |
| Project item is not the configured project | Ignore that item | Continue pagination/search for the matching project item | Existing project-ID guard and tests | A native type on another project cannot classify the target |

The first-non-empty `type_candidates` loop is the single mechanism enforcing
the "stop at first candidate" guarantee. The existing project-ID equality
guard ensures unrelated project items cannot participate.

---

## Testing Strategy

**Test types**: Shell unit/regression tests, ShellCheck, workflow shell guard,
and workflow smoke runbook.

**Primary regression file**:
`scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`

**Key scenarios to test**:

1. Native-only `Feature` resolves to `Feature`, the query includes
   `issueType`, and no missing-Type warning appears (AC-1, AC-2).
2. Configured `Workflow` beats native `Feature` and every custom alias (AC-3).
3. Native `Feature` beats `Custom Type`, `CustomType`, and `Type` values when
   the configured value is empty (AC-4).
4. With configured/native empty, custom precedence remains `Custom Type`,
   `CustomType`, then `Type` (AC-5).
5. Absent, null, empty-name, and non-object native content fall through without
   parser failure; an existing custom value is returned (AC-6).
6. All sources empty returns an empty type and emits the existing warning
   (AC-7).
7. The focused harness remains green and the targeted lookup still avoids a
   full-board scan (AC-8, BR-8).

**Smoke test runbook**:
`docs/testing/workflow/native-github-projects-issue-type.smoke-test.md`

### Parser-Risk Edge Cases and Unit-Test Mapping

The plan is parser-risk because it changes structured GraphQL JSON parsing in
an embedded Python block.

| Edge case category | Concrete input | Expected behavior | Automated mapping |
| --- | --- | --- | --- |
| Boundary variants | `content` absent, `null`, `{}`, or `{"issueType": null}` | Treat native candidate as empty and continue to custom fields | Add a null/absent native fallback fixture and assertions in the primary regression file |
| Boundary variants | `{"content":{"issueType":{"name":""}}}` | Empty name does not resolve classification | Cover in the all-empty or fallback fixture |
| Negative lookalike | `content` is a string or list rather than an object | Defensive `isinstance(content, dict)` path avoids an exception and continues fallback | Add a non-object content fixture with a valid custom value |
| Multiple occurrences | One response contains project items for another project and the configured project, both with native types | Only the item whose `project.id` equals the configured project ID is eligible | Extend the paginated/multi-item fixture or add a focused target-project assertion |
| Nested precedence | Configured, native, `Custom Type`, `CustomType`, and `Type` all have different non-empty names | Return the configured value; variants with each higher source empty select the next exact candidate | Add all-sources and fallback-order fixtures with assertions for each precedence boundary |
| Normative-spec flexibility | Not applicable: JSON object shape and GraphQL fields are schema-defined; there is no flexible text grammar | No special normalization or permissive parsing is introduced | No test beyond schema-shaped and defensive malformed-content fixtures |

Suppression semantics are not applicable; the helper does not recognize inline
or directive suppressions.

### Additional Quality Checks

- Run
  `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`.
- Run
  `shellcheck scripts/development-workflow/workflow-lib.sh scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`.
- Run
  `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
- Run the repository's Markdown lint and heuristic lint over the implementation
  plan, smoke runbook, integration guide, and CHANGELOG after implementation.

No API filter-schema canary is required: this change reads an additional
GraphQL response field and does not add a filter parameter. No concurrency
checklist is required because the synchronous helper introduces no listener,
timer, queue, or shared mutable state. No single-snapshot or
consistency-semantics change is introduced because all candidate values come
from the same existing project-item GraphQL response.

---

## Seed Data

No persistent seed data is required. The shell regression harness supplies
deterministic JSON fixtures for every classification source and warning case.
The smoke runbook uses those fixtures and does not modify a live project.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` —
  document native Issue Type as the second read-precedence source and clarify
  that the project-field write helper remains unchanged.
- [ ] `CHANGELOG.md` — add the exact `[Unreleased]` fixed entry specified in
  **Release Documentation**.

`AGENTS.md`, project architecture docs, and best-practice docs do not need
updates: this feature does not change repository commands, architecture,
coding standards, or tracker mutation conventions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Native type is parsed but omitted from the GraphQL query | Low | High | Assert the recorded query contains `issueType` and keep query/parser changes in the same implementation step. |
| Candidate insertion changes legacy custom precedence | Medium | High | Use one explicit ordered list and regression fixtures where every source has a distinct value. |
| `content` is null or a non-Issue union member | Low | Medium | Use the inline `... on Issue` fragment and defensively accept missing/non-object `content`. |
| Warning suppression becomes too broad | Low | Medium | Derive warning presence from the same selected candidate and retain the all-empty warning regression. |
| Documentation implies native Issue Type can be mutated by existing helpers | Medium | Low | Describe native support only for reads and explicitly retain custom-field write semantics. |

---

## Implementation Order

1. Extend
   `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
   with the schema-shaped native Issue Type fixtures and assertions listed in
   **Testing Strategy**. Run the focused harness and confirm the new assertions
   fail against the pre-change helper for the expected missing-query/missing-
   classification reasons (AC-1 through AC-8).
2. Update `workflow_github_project_item_for_issue` in
   `scripts/development-workflow/workflow-lib.sh` to request
   `content.issueType.name`, defensively extract it, and insert it at the exact
   configured → native → `Custom Type` → `CustomType` → `Type` precedence
   boundary (AC-1 through AC-7).
3. Run the focused harness again and confirm all native, precedence, fallback,
   warning, pagination, and no-full-board-scan assertions pass. Run ShellCheck
   and the workflow shell guard, and inspect their output for no new findings
   (AC-8).
4. Update
   `docs/workflow/development-workflow/integrations/github-projects.md`
   with the read precedence and unchanged write scope, then execute
   `docs/testing/workflow/native-github-projects-issue-type.smoke-test.md`
   and record the result.
5. Add the exact `CHANGELOG.md` `[Unreleased]` → `### Fixed` entry from
   **Release Documentation**.
6. Run Markdown lint and heuristic lint on the changed documentation, inspect
   `git diff --check`, and confirm the final diff contains only the helper,
   focused regression harness, integration guide, smoke runbook update, and
   CHANGELOG entry authorized by this plan.

---

## Residual Verification Strategy

This is a bounded classification-matrix change. Before the implementation PR
can reach `ready-for-human-review`, the focused shell harness output is the
residual evidence source: every matrix row above must have a named passing
assertion, or the PR must link an explicitly out-of-scope follow-up approved by
the human. The implementation PR should include the harness summary and the
workflow shell guard result; silent deferral of a precedence or warning branch
is not acceptable.
