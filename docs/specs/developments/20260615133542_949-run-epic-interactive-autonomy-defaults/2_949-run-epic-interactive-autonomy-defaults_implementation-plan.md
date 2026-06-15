# Run Epic Interactive Autonomy Defaults - Implementation Plan

**Spec**: Refactor brief in
[GitHub issue #949](https://github.com/lhpaul/ai-dev-framework-template/issues/949)
**Smoke test runbook**:
[949-run-epic-interactive-autonomy-defaults.smoke-test.md](../../../testing/workflow/949-run-epic-interactive-autonomy-defaults.smoke-test.md)

---

## Summary

**Approach**: Add a read-only policy recommendation layer after `/run-epic`
scope resolution and before any mutating workflow stage begins. Keep
`run-epic-scope-resolver.sh` as the bounded scope contract, add a
fixture-testable helper that derives recommended autonomy settings from the
resolved scope and original invocation, and update protocol/command guidance so
agents ask in-place only when effective policy values are missing or ambiguous.

**Estimated complexity**: M

**Rationale**: The change is contained to workflow scripts, tests, protocol
docs, command wrappers, and audit evidence, but it alters delegated workflow
control flow. The implementation must preserve resolver read-only behavior,
avoid silently widening merge authority, and keep recommendations deterministic
enough for fixture tests.

**Dependencies**: None. The merged `/run-epic` resolver, risk classifier, audit
trail, and delegated gate are already present on `develop`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `3b6f303` |
| Template-fit check | `cat .ai-dev-workflow.yaml` | `template.is_template: true`; #949 is generic workflow tooling for all downstream projects. |
| Current issue route | `./scripts/development-workflow/run-epic-scope-resolver.sh --items 949 --delegate-review --may-merge --may-start-backlog true --max-risk medium --json` | `#949` is `eligible`, Project status `Backlog`, Type `Refactor`, base `develop`, no dependencies or PRs. |
| Existing strict parameter behavior | `rg -n "ERROR: pass exactly one|Unknown option|--delegate-review|--may-merge|--may-start-backlog|--max-risk|readOnlyGuarantee|policy" scripts/development-workflow/run-epic-scope-resolver.sh` | Resolver requires a scope source, validates policy flags, emits policy values, and states its read-only guarantee. |
| Missing interactive recommendation behavior | `rg -n "request_user_input|confirmation|accept recommended|selected policy|effective policy|originally requested|rerun" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md scripts/development-workflow .agents/skills/run-epic .claude/commands/run-epic.md .cursor/commands/run-epic.md` | No current `/run-epic` surface derives recommendations, asks in-place, or records original/recommended/selected policy. |
| Audit trail extension point | `rg -n "render-pr-disposition|original|policy|mergeAuthority|finalDecision|protocolDeviation|reviewedHeadSha" scripts/development-workflow/run-epic-audit-trail.sh scripts/development-workflow/tests/test-run-epic-audit-trail.sh docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | PR disposition has reviewed SHA, reviewer, risk, merge authority, decision, verification, and deviations; policy-selection fields must be added. |
| Existing run-epic tests | `ls scripts/development-workflow/tests/test-run-epic-*.sh` | Existing tests cover audit trail, delegated gate, risk classifier, and scope resolver; #949 should add policy recommender coverage and update audit tests. |

---

## Layer-by-Layer Changes

### Policy Recommendation Helper

- [ ] Add `scripts/development-workflow/run-epic-policy-recommender.sh`.
- [ ] Accept `--scope <resolver-json>`, `--original-command <string>`, and
      optional explicit policy overrides matching resolver flags:
      `--delegate-review`, `--may-merge`, `--may-start-backlog <true|false>`,
      `--max-risk <low|medium|high>`, and `--base <branch>`.
- [ ] Support `--json` for machine-readable handoff and a concise text summary
      when JSON is not requested.
- [ ] Validate input before deriving recommendations: missing scope file,
      malformed JSON, missing groups/items, invalid booleans, invalid risk
      values, and ambiguous base data must produce clear non-zero failures.
- [ ] Preserve explicit human choices. If a flag was supplied, mark its source
      as `explicit` and do not override it with a recommendation.
- [ ] Derive missing `--may-start-backlog` from scope: recommend `true` only
      when the requested scope includes Backlog items and no dependency blocker
      is detected; recommend `false` when dependencies or ambiguity block
      starting work.
- [ ] Derive missing `--delegate-review` from configured review availability:
      recommend `true` when at least one configured review path can be used by
      the current runner; otherwise recommend `false` with a setup reason.
- [ ] Derive missing `--may-merge` as `true` for explicit scoped runs when
      review can be delegated and no authority/risk ambiguity is present;
      otherwise recommend `false` with a plain-language reason.
- [ ] Derive missing `--max-risk` from scope classification: `low` for docs,
      spec, plan, and narrow text-only runs; `medium` for workflow scripts,
      orchestration, merge/cleanup automation, or shared workflow tooling when
      `why_safe_to_merge` evidence can be produced; never recommend `high`.
- [ ] Derive missing `--base` from resolver output when unambiguous; require
      human selection when the resolver reports a conflicting or missing base.
- [ ] Emit `originalCommand`, `recommendedPolicy`, `selectedPolicy`,
      `effectivePolicy`, `requiresConfirmation`, `confirmationReason`,
      `copyPasteCommand`, and per-field rationale.
- [ ] Keep the helper read-only. It must not update trackers, create branches,
      open PRs, edit labels, post comments, merge, close issues, or delete
      branches.

### Run Epic Protocol and Command Surfaces

- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      so resolver execution is followed by a policy recommendation preflight
      before any mutating `/run-item-work` dispatch.
- [ ] Document the in-place confirmation flow:
      present scoped issues, grouped states, base branch, recommended policy,
      risk rationale, and copy-paste equivalent command; continue in the same
      run when the human accepts.
- [ ] Document that exact invocations with all effective policy values supplied
      may skip the prompt but must still record original, recommended, selected,
      and effective policy in audit evidence.
- [ ] Document stop behavior for ambiguous base, recommended risk above
      allowed tolerance, unavailable reviewers, missing merge authority,
      unresolved reviewer findings, CI/check state, tracker ambiguity, and
      delegated gate blocks.
- [ ] Update `.agents/skills/run-epic/SKILL.md`,
      `.agents/skills/run-epic/agents/openai.yaml`,
      `.claude/commands/run-epic.md`, and `.cursor/commands/run-epic.md` with
      the recommendation helper and confirmation requirements.
- [ ] Update `docs/workflow/development-workflow/README.md` and `AGENTS.md`
      where they summarize `/run-epic` behavior.

### Audit Trail

- [ ] Extend `scripts/development-workflow/run-epic-audit-trail.sh`
      `render-pr-disposition` output with an `Invocation Policy` section that
      records the originally requested command, recommended policy, selected
      policy, effective policy, copy-paste equivalent command, and any human
      confirmation or customization.
- [ ] Extend epic ledger input/output when a native epic exists to include the
      effective policy and final stop gate in the ledger notes.
- [ ] Keep audit rendering backward-compatible for older fixtures that do not
      include policy-selection fields.
- [ ] Update audit trail tests for redaction, markdown table escaping, missing
      optional policy fields, and populated policy fields.

### Tests

- [ ] Add
      `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
      with offline fixtures for explicit item lists, native epics, Backlog
      items, blocked dependencies, already-merged items, in-review PRs,
      ambiguous bases, unavailable reviewers, docs-only low risk, workflow
      tooling medium risk, and high-risk signals.
- [ ] Include no-mutation guards in policy recommender tests that fail if the
      helper invokes mutating `gh`, `git`, or GraphQL operations.
- [ ] Extend `scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
      for policy-selection audit fields.
- [ ] Extend existing resolver/delegated gate tests only where their fixture
      contracts need to accept the new policy evidence; do not move
      recommendation logic into those helpers.

### Database / Data Layer

- [ ] No database, migration, generated type, or seed data changes.

### Backend / API

- [ ] No backend/API service changes.

### Frontend / UI

- [ ] No frontend or UI changes.

### Infrastructure / Configuration

- [ ] No new secrets, GitHub App permissions, workflow files, or repository
      configuration keys.

---

## Files to Modify

```text
scripts/development-workflow/run-epic-policy-recommender.sh
scripts/development-workflow/run-epic-audit-trail.sh
scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
scripts/development-workflow/tests/test-run-epic-audit-trail.sh
docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
.agents/skills/run-epic/SKILL.md
.agents/skills/run-epic/agents/openai.yaml
.claude/commands/run-epic.md
.cursor/commands/run-epic.md
docs/workflow/development-workflow/README.md
AGENTS.md
docs/testing/workflow/949-run-epic-interactive-autonomy-defaults.smoke-test.md
CHANGELOG.md
```

---

## Testing Strategy

**Test types**: Shell fixture tests, JSON-output assertions, no-mutation guard,
audit-rendering tests, markdown lint, manual smoke review.

**Key scenarios to test**:

1. Underspecified explicit item-list invocation recommends an automatic safe
   policy and requires in-place confirmation. Maps to issue requirements 1, 2,
   5, and 6.
2. Backlog scope with no dependency blocker recommends
   `--may-start-backlog true`; blocked or ambiguous scope recommends `false`
   and stops before mutation. Maps to requirements 3, 4, and 5.
3. Workflow/tooling scope recommends `--max-risk medium` with plain-language
   rationale and never recommends `high`. Maps to requirements 4 and 6.
4. Explicitly supplied policy flags are preserved as selected/effective values
   and skip repeated prompting within the same invocation. Maps to requirements
   6 and 7.
5. Ambiguous base or conflicting integration branches require human selection
   before any mutating stage. Maps to requirements 5 and 9.
6. Audit rendering records original command, recommended policy, selected
   policy, effective policy, and copy-paste equivalent command. Maps to
   requirements 8 and 10.
7. Final stop output identifies the blocking gate as authority, risk, CI/check
   state, reviewer findings, tracker ambiguity, or delegated gate state. Maps
   to requirement 9.

**Smoke test runbook**:
`docs/testing/workflow/949-run-epic-interactive-autonomy-defaults.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
- `bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
- `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
- `bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
- `bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
- `shellcheck -x scripts/development-workflow/run-epic-policy-recommender.sh scripts/development-workflow/run-epic-audit-trail.sh scripts/development-workflow/tests/test-run-epic-policy-recommender.sh scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/949-run-epic-interactive-autonomy-defaults.smoke-test.md" "AGENTS.md" "CHANGELOG.md" ".agents/skills/run-epic/SKILL.md" ".claude/commands/run-epic.md" ".cursor/commands/run-epic.md"`
- `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
- `git diff --check`

### Parser-risk addendum

This plan is parser-risk because it adds CLI option parsing, consumes resolver
JSON, emits structured JSON for downstream agents, and adds markdown rendering
for policy evidence.

**Edge-case enumeration**:

1. Missing, empty, and malformed scope JSON files.
2. Scope JSON with no groups, no items, duplicate items, or empty Backlog
   groups.
3. Boolean policy values supplied as invalid strings, omitted values, or
   explicit `false`.
4. Invalid `--max-risk` values, including `blocked`, uppercase values, and
   empty strings.
5. Ambiguous base values: null base, conflicting integration labels, and
   explicit base overriding an inferred base.
6. Scope mixes eligible, blocked, already-merged, and in-review groups.
7. Risk signals overlap, such as docs-only plan artifacts plus workflow script
   paths; the higher applicable recommendation should win up to `medium`.
8. Original command contains quotes, shell metacharacters, or local paths that
   must be escaped or redacted in audit output.
9. Policy rationale strings contain pipes, backticks, or newlines that must not
   break markdown tables.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
  covers edge cases 1 through 7 and validates JSON keys plus text output.
- `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` covers edge
  cases 8 and 9 for rendering, escaping, and redaction.

**Suppression semantics**: Not applicable; this feature does not introduce
inline suppression directives.

---

## Seed Data

No persistent seed data is required. Fixture tests provide temporary resolver
scope JSON, reviewer availability, selected policy, risk signals, and audit
input state.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` -
      describe policy recommendation, in-place confirmation, selected policy
      audit evidence, and final stop gate reporting.
- [ ] `.agents/skills/run-epic/SKILL.md` and
      `.agents/skills/run-epic/agents/openai.yaml` - route Codex command users
      through the recommendation preflight before mutation.
- [ ] `.claude/commands/run-epic.md` and `.cursor/commands/run-epic.md` -
      mirror the same command-surface behavior for Claude and Cursor.
- [ ] `docs/workflow/development-workflow/README.md` - update the workflow
      command summary for `/run-epic`.
- [ ] `AGENTS.md` - update repository-wide command guidance for `/run-epic`.
- [ ] `CHANGELOG.md` - add the implementation PR entry under `[Unreleased]`.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Recommendation silently widens authority beyond what the human intended | Med | High | Preserve explicit flags, require confirmation for inferred values, and record selected/effective policy in audit evidence. |
| The resolver starts mutating state while trying to recommend policy | Low | High | Keep resolver read-only and place recommendation in a separate read-only helper with no-mutation tests. |
| Risk recommendation is too permissive for shared workflow scripts | Med | Med | Cap default recommendations at `medium`, never recommend `high`, and require existing risk classifier plus why-safe evidence before merge. |
| Audit output becomes incompatible with older PR disposition fixtures | Low | Med | Treat policy-selection fields as optional and add backward-compatibility tests. |
| Interactive prompt behavior differs across agent surfaces | Med | Med | Put canonical behavior in protocol 95 and mirror it in all command/skill wrappers. |

---

## Code Samples

No production code samples are required in this plan. The implementation should
prefer fixture-driven tests over prose-only examples.

---

## Implementation Order

1. Add `scripts/development-workflow/run-epic-policy-recommender.sh` with
   read-only input validation, recommendation derivation, text output, and JSON
   output.
2. Add `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
   with the parser-risk fixtures and no-mutation guard.
3. Extend `scripts/development-workflow/run-epic-audit-trail.sh` to render
   optional invocation policy evidence in PR disposition and epic ledger
   comments.
4. Extend `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` for
   populated and omitted policy evidence.
5. Update protocol 95 and all `/run-epic` command/skill wrappers to describe
   resolver, recommendation, in-place confirmation, effective-policy handoff,
   audit requirements, and final stop gate reporting.
6. Add
   `docs/testing/workflow/949-run-epic-interactive-autonomy-defaults.smoke-test.md`.
7. Update `AGENTS.md` and
   `docs/workflow/development-workflow/README.md` command summaries.
8. Add this implementation CHANGELOG entry under `[Unreleased]`:
   `- **Improve run-epic autonomy defaults** (#949): add policy recommendations and audit evidence for underspecified /run-epic invocations.`
9. Run the regression suite listed in **Testing Strategy** and fix any failures
   before opening the implementation PR.

