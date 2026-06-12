# Autonomous Epic Audit Trail - Implementation Plan

**Spec**:
[1_920-autonomous-epic-audit-trail_specs.md](1_920-autonomous-epic-audit-trail_specs.md)
**Smoke test runbook**:
[920-autonomous-epic-audit-trail.smoke-test.md](../../../testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md)

---

## Summary

**Approach**: Add a read-only-by-default audit helper that renders stable PR
disposition and epic ledger comment bodies, with an explicit apply mode for
creating or updating GitHub comments by marker. The helper will accept fixture
JSON for deterministic tests and live identifiers for later `/run-epic`
integration, then update the `/run-epic` protocol to require disposition and
ledger updates at delegated decision points.

**Estimated complexity**: M

**Rationale**: The feature is contained to workflow scripts, fixture tests, and
workflow documentation, but it writes GitHub comments and must avoid duplicate
comments, secret leaks, stale SHA evidence, and table drift across reruns.

**Dependencies**: #917 must be merged for resolved execution-set data. #919 is
also expected to be merged before implementation so risk classification evidence
can be recorded in the audit output.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `078a31a` |
| Existing run-epic protocol | `rg -n "risk classifier|bounded scope|merge_permitted|run-epic" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | `/run-epic` already owns resolver handoff and risk-gated delegated merge guidance. |
| Existing comment-update patterns | `rg -n "marker|comment|gh pr comment|gh issue comment|comments" scripts/development-workflow docs/workflow/development-workflow/protocols` | Reviewer-loop and workflow scripts already use stable summary comments; implementation should follow marker-based update semantics. |
| Existing risk helper | `rg -n "why_safe_to_merge|merge_permitted|read_only_guarantee" scripts/development-workflow/run-epic-risk-classifier.sh` | Risk classifier emits structured fields that can be copied into the audit trail. |

---

## Layer-by-Layer Changes

### Workflow Helper Script

- [ ] Add `scripts/development-workflow/run-epic-audit-trail.sh`.
- [ ] Support `render-pr-disposition`, `apply-pr-disposition`,
      `render-epic-ledger`, and `apply-epic-ledger` subcommands.
- [ ] Support `--input <file>` for fixture/offline data and live identifiers
      such as `--pr <number>` and `--epic <number>` only when needed for apply
      mode.
- [ ] Use stable HTML markers for comments:
      `<!-- run-epic:pr-disposition -->` and
      `<!-- run-epic:epic-ledger -->`.
- [ ] In apply mode, update an existing matching comment; create one only when
      no marker exists.
- [ ] Render PR disposition fields from the spec: scope source, item, PR,
      reviewed head SHA, reviewer result, blocking/advisory counts, advisory
      decisions/rationales, risk classification/reasons, merge authority, final
      decision, verification evidence, and protocol deviations.
- [ ] Render epic ledger rows with issue number/title, PR number, tracker
      status, risk level, review result, decision, merge/cleanup verification,
      and notes.
- [ ] Redact secrets, tokens, credentials, home-directory paths, and temporary
      local paths from rendered content.
- [ ] Fail closed when required disposition fields are missing for a merge
      approved decision.

### Tests

- [ ] Add `scripts/development-workflow/tests/test-run-epic-audit-trail.sh`.
- [ ] Cover PR disposition render and apply create/update behavior.
- [ ] Cover epic ledger render and apply create/update behavior.
- [ ] Cover explicit item-list runs where epic ledger is not applicable.
- [ ] Cover advisory dispositions `fixed`, `accepted`, `deferred`, and
      `false_or_stale`, including required rationale for non-fixed advisories.
- [ ] Cover reviewed SHA presence, merge authority, risk evidence, verification
      evidence, protocol deviation fields, and redaction.
- [ ] Include no-duplicate-comment assertions through stubbed `gh` comments.

### Protocol and Command Surfaces

- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      to require audit updates after delegated review/fix/merge/escalation
      decisions.
- [ ] Update `.agents/skills/run-epic/SKILL.md`,
      `.agents/skills/run-epic/agents/openai.yaml`,
      `.claude/commands/run-epic.md`, and `.cursor/commands/run-epic.md` only
      if their command guidance needs to mention the audit helper.

### Documentation

- [ ] Update `docs/workflow/development-workflow/README.md` and `AGENTS.md` only
      if the command summary needs to describe audit-trail behavior.
- [ ] Add `docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md`.
- [ ] Add a `CHANGELOG.md` entry under `[Unreleased]` during implementation.

### Database / Data Layer

- [ ] No database or seed data changes.

### Frontend / UI

- [ ] No frontend or UI changes.

### Infrastructure / Configuration

- [ ] No new secrets, GitHub App permissions, workflow files, or repository
      configuration keys.

---

## Files to Modify

```text
scripts/development-workflow/run-epic-audit-trail.sh
scripts/development-workflow/tests/test-run-epic-audit-trail.sh
docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
.agents/skills/run-epic/SKILL.md
.agents/skills/run-epic/agents/openai.yaml
.claude/commands/run-epic.md
.cursor/commands/run-epic.md
docs/workflow/development-workflow/README.md
AGENTS.md
docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md
CHANGELOG.md
```

---

## Testing Strategy

**Test types**: Shell fixture tests, markdown lint, manual smoke review.

**Key scenarios to test**:

1. PR disposition comment is rendered with all required fields and marker.
   Maps to AC1 and AC3.
2. Repeated PR disposition apply updates an existing marker comment instead of
   creating a duplicate. Maps to AC2.
3. Advisory decisions and rationales render correctly. Maps to AC4.
4. Epic ledger comment is rendered with all child rows and marker. Maps to AC5
   and AC6.
5. Repeated epic ledger apply updates the existing marker comment. Maps to AC5.
6. Explicit item-list run renders PR disposition and reports epic ledger as not
   applicable. Maps to AC7.
7. Redaction removes secrets, tokens, credentials, home paths, and temporary
   local paths. Maps to AC8.
8. Protocol deviations include command/action, impact, and mitigation. Maps to
   AC9.
9. Fixture tests cover creation/update behavior and ledger table updates. Maps
   to AC10.

**Smoke test runbook**:
`docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md" "AGENTS.md" "CHANGELOG.md"`

### Parser-risk addendum

This plan is parser-risk because the helper parses CLI subcommands, fixture
JSON, GitHub comment lists, comment marker text, markdown table rows, and
redaction candidates.

**Edge-case enumeration**:

- Missing or unknown subcommand.
- Missing `--input` for render mode.
- Missing `--pr` or `--epic` for apply mode.
- Invalid JSON, empty JSON, or missing required fields.
- Existing comments with no marker, one marker, multiple markers, and marker in
  quoted text.
- Advisory disposition without required rationale.
- Markdown table content containing pipes, newlines, backticks, links, and issue
  references.
- Secret-like values: tokens, credentials, `Authorization` headers, home
  directories, `/tmp` paths, and repository-external absolute paths.
- Explicit item-list input with no parent epic.

**Unit test mapping**:

Use `scripts/development-workflow/tests/test-run-epic-audit-trail.sh`.

- `requires_known_subcommand` covers missing and unknown subcommands.
- `renders_pr_disposition_with_marker` covers required PR fields.
- `updates_existing_pr_disposition_comment` covers update semantics.
- `creates_pr_disposition_when_missing` covers create semantics.
- `renders_epic_ledger_with_rows` covers ledger table output.
- `updates_existing_epic_ledger_comment` covers ledger update semantics.
- `explicit_items_skip_epic_ledger` covers no-parent behavior.
- `requires_advisory_rationale` covers non-fixed advisory rationale.
- `redacts_sensitive_values` covers secret and local-path redaction.
- `renders_protocol_deviations` covers deviation fields.
- `no_duplicate_comments` covers stable marker behavior.

**Suppression semantics**: Not applicable. The helper does not introduce inline
suppression directives.

### Concurrent-event-source addendum

- **Shared mutable state guards**: Comment updates must identify comments by
  marker and target PR/epic number; no local shared state should persist across
  runs.
- **Re-entrancy / in-flight tracking**: Concurrent runs can race to update the
  same marker comment. The helper should fetch comments immediately before
  update and prefer update over create whenever a marker exists.
- **Event deduplication**: Stable markers deduplicate audit comments.
- **Listener and resource cleanup**: Temporary fixture files should be cleaned
  by test harness traps.
- **Race conditions at initialization**: Missing or unreadable comments should
  fail closed in apply mode rather than silently creating duplicates when the
  read fails.
- **Race conditions at teardown**: Not applicable beyond temp cleanup.
- **Error propagation across async boundaries**: Not applicable; Bash command
  failures should surface through `set -euo pipefail` and explicit `gh`/`jq`
  checks.

---

## Seed Data

No persistent seed data is required. Fixture tests should create temporary PR
state, epic ledger state, comment lists, advisory decisions, risk evidence, and
redaction examples.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` -
      add audit trail steps after delegated decisions.
- [ ] `.agents/skills/run-epic/SKILL.md`,
      `.agents/skills/run-epic/agents/openai.yaml`,
      `.claude/commands/run-epic.md`, and `.cursor/commands/run-epic.md` -
      mention audit helper only if command guidance needs it.
- [ ] `docs/workflow/development-workflow/README.md` and `AGENTS.md` - update
      command summaries only if needed.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` entry during implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Reruns duplicate comments. | Medium | Medium | Use stable markers and fixture tests for create/update paths. |
| Audit comments leak sensitive data. | Medium | High | Apply redaction before rendering and cover representative secrets/paths. |
| Ledger rows become stale or misleading. | Medium | Medium | Include reviewed SHA, status, decision, and merge/cleanup evidence in every row. |
| Comment updates race between runs. | Low | Medium | Fetch comments immediately before apply and prefer update over create. |
| Audit helper is mistaken for merge authority. | Low | High | Document comments as audit artifacts and preserve separate risk/reviewer/CI gates. |

---

## Implementation Order

1. Add `scripts/development-workflow/run-epic-audit-trail.sh` with subcommand
   parsing, help text, input validation, and read-only render modes.
2. Implement fixture JSON validation and required-field checks.
3. Implement PR disposition markdown rendering with stable marker.
4. Implement epic ledger markdown table rendering with stable marker.
5. Implement redaction helpers before any render output.
6. Implement GitHub comment lookup/update/create apply modes with guarded `gh`
   and `jq` calls.
7. Add `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` with
   stubbed `gh` comment create/update behavior.
8. Update `/run-epic` protocol and command surfaces as needed.
9. Add `docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md`.
10. Add this CHANGELOG entry under `[Unreleased]`:

    ```markdown
    - **Add autonomous epic audit trail** (#920): add stable PR disposition and
      epic ledger comments for delegated `/run-epic` decisions.
    ```

11. Run validation:

    ```bash
    bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
    npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md" "AGENTS.md" "CHANGELOG.md"
    ```

---

## Cross-Section Consistency Self-Check

- The helper script name is consistently
  `scripts/development-workflow/run-epic-audit-trail.sh`.
- The PR disposition marker is consistently
  `<!-- run-epic:pr-disposition -->`.
- The epic ledger marker is consistently `<!-- run-epic:epic-ledger -->`.
- PR disposition comments are required for delegated decisions in all scopes.
- Epic ledger comments are required only for native epic runs.

---

## Document Quality Gate

- Spec coverage: Checked - every AC maps to implementation and test steps.
- Behavioral guarantees: Checked - marker update, redaction, and no-duplicate
  behavior are explicit.
- Parser/API/concurrency checklist: Checked - parser-risk and comment update
  concurrency cases are listed.
- CHANGELOG literal format: Checked - implementation order uses the project's
  bold-title issue format.
