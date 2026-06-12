# Run Epic Scope Resolver - Implementation Plan

**Spec**: [1_917-run-epic-scope-resolver_specs.md](1_917-run-epic-scope-resolver_specs.md)
**Smoke test runbook**: [917-run-epic-scope-resolver.smoke-test.md](../../../testing/workflow/917-run-epic-scope-resolver.smoke-test.md)

---

## Summary

**Approach**: Add a read-only `/run-epic` resolver surface backed by a new
workflow helper script. The helper resolves either native GitHub sub-issues for
an epic or an explicit item list, enriches each item with tracker and PR state,
infers a single target base branch, and prints both human-readable grouped
output and machine-readable JSON without mutating tracker, branch, PR, or issue
state.

**Estimated complexity**: M

**Rationale**: The implementation is contained to workflow scripts, docs,
command aliases, and tests, but it touches GitHub GraphQL, Project field reads,
CLI parsing, base-branch inference, and explicit no-mutation guarantees.

**Dependencies**: None. This is the foundational resolver item for the delegated
epic orchestration package.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d68f083` |
| Existing `/run-epic` surface | `rg -n "run-epic" .agents .codex .claude .cursor scripts docs/workflow/development-workflow -g '!docs/specs/**'` | No existing command, skill, script, or protocol owns `/run-epic`; implementation must add the first resolver surface. |
| Existing command alias patterns | `find .agents/skills .codex/skills .claude/commands .cursor/commands -maxdepth 3 -type f \| sort` | Command-style aliases already exist for `/run-work`, `/run-item-work`, `/graduate-development`, and related workflow commands across Claude, Cursor, and Codex surfaces. |
| Native sub-issue query precedent | `rg -n "subIssues|addSubIssue|parent" docs/workflow/development-workflow/protocols scripts` | Native GitHub sub-issue GraphQL examples exist in `00-add-backlog-item-protocol.md` and `05b-graduate-development-protocol.md`; reuse their pagination and parent-verification patterns. |
| Workflow helper patterns | `sed -n '1,220p' scripts/development-workflow/workflow-next-action.sh` and `sed -n '1938,2025p' scripts/development-workflow/workflow-lib.sh` | Existing helpers use Bash, `workflow-lib.sh`, stable key-value output, GitHub Projects status/type helpers, and stub-friendly shell tests. |
| Installer alias coverage | `sed -n '1,220p' scripts/development-workflow/install-codex-skills.sh` | The installer symlinks every `.agents/skills/*` directory, but `test-install-codex-skills.sh` has explicit real-repo alias expectations that must include `run-epic`. |

---

## Layer-by-Layer Changes

### Workflow Helper Script

- [ ] Add `scripts/development-workflow/run-epic-scope-resolver.sh`.
- [ ] Support `--epic <issue-number>` and
      `--items <issue-number>[,<issue-number>...]`; require exactly one of
      these inputs.
- [ ] Support optional `--base <branch>` and `--json`.
- [ ] Validate all issue numbers as positive integers before using them in
      `gh`, GraphQL variables, regexes, or output grouping.
- [ ] Resolve repository slug through `workflow-lib.sh` so environment overrides
      and repo-mode behavior stay consistent with existing helpers.
- [ ] For `--epic`, query native GitHub sub-issues first using GraphQL and page
      through every page before deciding the child set is complete.
- [ ] For `--epic`, verify each child issue's parent relationship when GraphQL
      exposes it. If the native relationship cannot be read, fall back to the
      existing `integration-branch:<slug>` label grouping only when a single
      integration branch can be inferred from the epic or its known children.
- [ ] For `--items`, use exactly the listed items and do not add parent,
      sibling, label-matched, or milestone-matched issues.
- [ ] Enrich each resolved item with issue title, issue state, labels, Project
      Status, Project Type, Project Priority when available, dependency signal,
      and linked/open/merged PR state.
- [ ] Infer the target base branch using this precedence:
      supplied `--base`; one shared `integration-branch:<slug>` label mapped to
      `develop-<slug>`; otherwise `develop`.
- [ ] Mark the execution set ambiguous when items imply conflicting integration
      branch labels and no `--base` override is present.
- [ ] Group items as `eligible`, `blocked`, `already_merged`, `in_review`,
      `ambiguous`, or `out_of_scope`.
- [ ] Print a read-only guarantee stating that the resolver did not start
      Backlog items, update tracker status, create branches, open PRs, merge
      PRs, close issues, or delete branches.

### Protocol and Command Surfaces

- [ ] Add
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      for the resolver-only `/run-epic` stage.
- [ ] Add `.claude/commands/run-epic.md` pointing to the new protocol.
- [ ] Add `.cursor/commands/run-epic.md` pointing to the new protocol.
- [ ] Add `.agents/skills/run-epic/SKILL.md` as the command-style Codex alias.
- [ ] Add `.agents/skills/run-epic/agents/openai.yaml` with a concise default
      prompt.
- [ ] Do not add delegated review, merge, risk, or audit behavior in this item;
      those remain sibling epic items.

### Documentation

- [ ] Update `AGENTS.md` command tables and Codex skill list to include
      `/run-epic` as a resolver-only delegated epic command.
- [ ] Update `docs/workflow/development-workflow/README.md` command tables and
      command-alias prose to include `/run-epic`.
- [ ] In the new protocol, document the read-only scope boundary, accepted
      inputs, base-branch inference, grouping labels, ambiguity outcomes, and
      the fact that Backlog starts still require separate approval.

### Tests

- [ ] Add `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
      with stubbed `gh` responses for GraphQL, issues, PRs, and Project fields.
- [ ] Update `scripts/development-workflow/tests/test-install-codex-skills.sh`
      real-repo alias expectations to include `run-epic`.
- [ ] Add the new test harness to any relevant workflow validation docs or
      runbook steps so implementers know it must run with the feature.

### Database / Data Layer

- [ ] No database or seed data changes.

### Frontend / UI

- [ ] No frontend or UI changes.

### Infrastructure / Configuration

- [ ] No new secrets, environment variables, GitHub App permissions, or shared
      configuration keys.

---

## Files to Modify

```text
scripts/development-workflow/run-epic-scope-resolver.sh
scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
scripts/development-workflow/tests/test-install-codex-skills.sh
docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
docs/workflow/development-workflow/README.md
AGENTS.md
.claude/commands/run-epic.md
.cursor/commands/run-epic.md
.agents/skills/run-epic/SKILL.md
.agents/skills/run-epic/agents/openai.yaml
CHANGELOG.md
```

---

## Testing Strategy

**Test types**: Shell unit/fixture tests, markdown lint, manual smoke review.

**Key scenarios to test**:

1. Epic with native sub-issues resolves all pages and reports child items with
   tracker/PR state. Maps to AC1 and AC10.
2. Explicit item list includes only listed items. Maps to AC2.
3. Supplied base override wins over inferred labels. Maps to AC3.
4. Shared integration-branch label infers `develop-<slug>`. Maps to AC4.
5. No integration-branch label infers `develop`. Maps to AC5.
6. Conflicting integration-branch labels without override produce an ambiguous
   execution set. Maps to AC6.
7. Every resolved item appears in exactly one execution group. Maps to AC7.
8. Resolver-only path performs no mutating `gh`, `git`, tracker, branch, PR, or
   issue-close operation. Maps to AC8 and AC9.
9. Epic with no native sub-issues reports the condition instead of treating the
   parent as a child. Maps to AC10.

**Smoke test runbook**:
`docs/testing/workflow/917-run-epic-scope-resolver.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
- `bash scripts/development-workflow/tests/test-install-codex-skills.sh`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/917-run-epic-scope-resolver.smoke-test.md" "AGENTS.md"`

### Parser-risk addendum

This plan is parser-risk because it adds CLI parsing, comma-separated item-list
parsing, GraphQL JSON extraction, Project field extraction, and
integration-branch label interpretation.

**Edge-case enumeration**:

- Missing input: no `--epic` and no `--items`.
- Conflicting input: both `--epic` and `--items`.
- Invalid issue number: zero, negative, non-numeric, empty list element, or
  whitespace around a comma.
- Explicit item-list duplicates.
- Native sub-issue pagination with more than one page.
- Epic with no native sub-issues.
- Native sub-issue query failure with no safe label fallback.
- Child-side parent mismatch.
- Missing Project item fields.
- Terminal Project Status values such as `Merged`, `Released`, `Done`, and
  `Cancelled`.
- Item labels with no integration branch, exactly one shared integration
  branch, and conflicting integration branches.
- Open PR with `ready-for-human-review`, draft PR, merged PR, and no linked PR.
- Supplied `--base` overriding otherwise conflicting labels.
- `--json` output remains valid JSON when item titles contain quotes,
  backticks, or punctuation.

**Unit test mapping**:

Use `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`.

- `requires_one_scope_input` covers missing input and conflicting input.
- `validates_issue_numbers` covers invalid issue numbers, empty list elements,
  and whitespace handling.
- `dedupes_explicit_items_without_expanding_scope` covers explicit duplicates
  and no sibling/label expansion.
- `resolves_native_subissues_all_pages` covers multi-page native sub-issue
  pagination.
- `reports_empty_epic_scope` covers epic with no native sub-issues.
- `fails_closed_on_unreadable_native_scope` covers GraphQL failure without a
  safe fallback.
- `rejects_parent_mismatch` covers child-side parent mismatch.
- `enriches_project_and_pr_state` covers Project field extraction, terminal
  statuses, open review PRs, draft PRs, merged PRs, and no linked PR.
- `infers_default_base` covers no integration label -> `develop`.
- `infers_shared_integration_base` covers shared label ->
  `develop-<slug>`.
- `reports_conflicting_integration_bases` covers conflicting labels.
- `base_override_wins` covers supplied `--base`.
- `json_output_is_valid` covers JSON escaping for item titles.
- `no_mutating_commands_are_called` covers the resolver-only guarantee by
  failing the test if stubbed `gh` receives mutating verbs such as
  `issue edit`, `pr create`, `pr merge`, `project item-edit`, or GraphQL
  mutations.

**Suppression semantics**: Not applicable. The resolver does not introduce
inline suppressions or ignore directives.

---

## Seed Data

No persistent seed data is required. The implementation test harness should
build temporary fixture data through stubbed `gh` responses for issues, Project
fields, PRs, labels, and GraphQL sub-issue pages.

---

## Documentation Updates

- [ ] `AGENTS.md` — add `/run-epic` to workflow command tables and Codex skill
      alias prose.
- [ ] `docs/workflow/development-workflow/README.md` — add `/run-epic` to
      command tables and command alias prose.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      new resolver protocol.
- [ ] `.claude/commands/run-epic.md` — new Claude command wrapper.
- [ ] `.cursor/commands/run-epic.md` — new Cursor command wrapper.
- [ ] `.agents/skills/run-epic/SKILL.md` and
      `.agents/skills/run-epic/agents/openai.yaml` — new Codex command alias.
- [ ] `CHANGELOG.md` — add an `[Unreleased]` entry during implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Native sub-issue GraphQL shape changes or is unavailable. | Medium | Medium | Use explicit error reporting and a label fallback only when it is unambiguous; cover both paths with fixture tests. |
| Resolver accidentally mutates tracker or repository state. | Low | High | Keep the helper read-only, centralize all `gh` calls, and make tests fail on mutating commands. |
| Base branch inference hides mixed-scope ambiguity. | Medium | High | Treat conflicting integration labels as `ambiguous` unless `--base` is supplied; list every conflicting item. |
| Project fields are missing on some issues. | Medium | Medium | Report missing fields as item detail and classify only from available data; do not infer Type or Status from legacy labels when Project fields are available. |
| Later delegated merge features consume unstable output. | Medium | Medium | Provide stable JSON output and documented grouping names from the first resolver implementation. |

---

## Implementation Order

1. Add `scripts/development-workflow/run-epic-scope-resolver.sh` with read-only
   CLI parsing for `--epic`, `--items`, `--base`, `--json`, and help output.
2. Implement issue-number validation and explicit item-list normalization before
   any GitHub or Project lookup occurs.
3. Implement native sub-issue resolution for `--epic` using paginated GraphQL
   based on the existing graduation-protocol query pattern.
4. Implement explicit item-list resolution that preserves the exact requested
   scope and does not expand through labels, parents, siblings, or milestones.
5. Implement item enrichment for issue state, labels, Project Status, Project
   Type, Project Priority when available, dependency signal, and linked/open or
   merged PR state.
6. Implement base-branch inference and ambiguity reporting with `--base` taking
   precedence over inferred labels.
7. Implement execution grouping and the read-only guarantee in both text and
   JSON output.
8. Add `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
   using stubbed `gh` output for all parser-risk edge cases listed above.
9. Add `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
10. Add `/run-epic` wrappers for Claude, Cursor, and Codex in `.claude/commands`,
    `.cursor/commands`, and `.agents/skills`.
11. Update `scripts/development-workflow/tests/test-install-codex-skills.sh` to
    include `run-epic` in real-repo alias coverage.
12. Update `AGENTS.md` and `docs/workflow/development-workflow/README.md` to
    list `/run-epic`.
13. Add this CHANGELOG entry under `[Unreleased]`:

    ```markdown
    - **Add run-epic scope resolver** (#917): add a read-only resolver for epic
      and explicit item-list execution sets before delegated review or merge
      behavior begins.
    ```

14. Run validation:

    ```bash
    bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
    bash scripts/development-workflow/tests/test-install-codex-skills.sh
    npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/917-run-epic-scope-resolver.smoke-test.md" "AGENTS.md"
    ```

15. Confirm `git status --short` shows only intended implementation files
    before committing.

---

## Cross-Section Consistency Self-Check

- The resolver script name is consistently
  `scripts/development-workflow/run-epic-scope-resolver.sh`.
- The protocol file is consistently
  `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
- The command name is consistently `/run-epic`.
- The target base branch precedence is consistently `--base`, shared
  integration-branch label, then `develop`.
- The execution group values are consistently `eligible`, `blocked`,
  `already_merged`, `in_review`, `ambiguous`, and `out_of_scope`.
- The test harness is consistently
  `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`.

---

## Document Quality Gate

- Spec/brief coverage: Checked - all ACs map to implementation steps and tests.
- Implementation-order consistency: Checked - file list, helper names, command
  names, grouping values, and branch inference rules agree across sections.
- Verification support: Checked - file-surface claims cite the Verification Log.
- Behavioral guarantees: Checked - read-only behavior is enforced by a
  resolver-only helper design plus no-mutation fixture tests.
- Parser/API/concurrency checklist: Checked - parser-risk applies and has an
  edge-case enumeration plus unit-test mapping; no API-surface or concurrent
  event-source checklist applies.
- CHANGELOG literal format: Checked - implementation order uses the
  `**Bold Title** (#N):` format.
- Not-applicable rationale: Checked - database, UI, seed data, suppressions, and
  concurrency are not applicable because this is a shell workflow resolver.
