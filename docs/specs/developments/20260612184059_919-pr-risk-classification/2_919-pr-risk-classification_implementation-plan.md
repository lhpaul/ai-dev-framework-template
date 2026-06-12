# PR Risk Classification for Delegated Merge Decisions - Implementation Plan

**Spec**:
[1_919-pr-risk-classification_specs.md](1_919-pr-risk-classification_specs.md)
**Smoke test runbook**:
[919-pr-risk-classification.smoke-test.md](../../../testing/workflow/919-pr-risk-classification.smoke-test.md)

---

## Summary

**Approach**: Add a standalone workflow helper that classifies a candidate PR's
delegated merge risk from explicit, fixture-testable inputs. The helper will
emit stable JSON plus a concise text summary containing the risk level, max-risk
decision, reasons, blockers, and the required medium-risk "why safe to merge"
evidence. `/run-epic` documentation and command guidance will call this
classifier before any delegated merge decision, without making the classifier
perform merges itself.

**Estimated complexity**: M

**Rationale**: The change is contained to workflow scripts, tests, runbooks, and
workflow documentation, but it defines a safety gate used by future delegated
merge automation. The implementation must be conservative, deterministic, and
easy to test without live PR mutation.

**Dependencies**: #917 must be merged because this feature extends the
`/run-epic` surface and consumes the resolved execution-set/base-branch context
that #917 introduced.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `f74c8aa` |
| Existing `/run-epic` surface | `sed -n '1,220p' docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Current protocol is resolver-only and explicitly says risk, review, merge, and audit behavior are sibling epic work. |
| Resolver helper precedent | `sed -n '1,260p' scripts/development-workflow/run-epic-scope-resolver.sh` | Existing helper is Bash, uses `workflow-lib.sh`, validates inputs before lookup, supports text/JSON modes, and is fixture-testable. |
| Existing #917 plan precedent | `sed -n '1,340p' docs/specs/developments/20260612124828_917-run-epic-scope-resolver/2_917-run-epic-scope-resolver_implementation-plan.md` | Workflow-tooling plans in this epic list helper scripts, protocol surfaces, tests, parser-risk cases, and smoke runbooks explicitly. |
| Changelog placement | `rg -n "## \\[Unreleased\\]|Add run-epic" CHANGELOG.md \| head -20` | `[Unreleased]` exists and #917 already uses the bold-title issue format expected for implementation PR entries. |

---

## Layer-by-Layer Changes

### Workflow Helper Script

- [ ] Add `scripts/development-workflow/run-epic-risk-classifier.sh`.
- [ ] Support `--pr <number>` for live PR classification and `--input <file>`
      for fixture/offline classification.
- [ ] Support `--max-risk <low|medium|high>` with a default of `low`.
- [ ] Support `--json` for machine-readable output and always print a concise
      text summary for human review when JSON is not requested.
- [ ] Validate PR numbers and enum values before reading GitHub state.
- [ ] Normalize risk levels as ordered values: `low`, `medium`, `high`, and
      `blocked`.
- [ ] Evaluate hard blockers before ordinary risk rules. Hard blockers include
      failing, pending, unavailable, or ambiguous required CI; configured
      reviewer failure; unresolved blocking review threads; `needs-setup`;
      missing credentials; ambiguous tracker state; unclear target/base branch;
      dirty or ambiguous merge state; required force-push; and required
      destructive action.
- [ ] Classify Low for docs, tests, narrow workflow text, or isolated helper
      changes with clean readiness evidence and no blockers.
- [ ] Classify Medium for workflow scripts, orchestration behavior, merge or
      cleanup automation, or shared workflow tooling with contained blast
      radius and clean readiness evidence.
- [ ] Classify High for auth, secrets, GitHub permissions, release automation,
      branch deletion behavior, cross-repo PR credentials, broad shared
      libraries, or unclear behavior changes.
- [ ] Compare the assigned risk with `--max-risk` and emit a boolean merge-gate
      decision plus a mismatch reason when the assigned risk exceeds the limit.
- [ ] Require a complete `why_safe_to_merge` object for Medium risk when
      `--max-risk medium` or higher permits the risk. Required fields are
      scope, tests, reviewer outcome, CI outcome, and rollback or cleanup risk.
- [ ] Keep the helper read-only: no tracker updates, label changes, reviewer
      loop execution, CI polling, merge commands, branch deletion, or comments.

### Rule Fixtures and Tests

- [ ] Add `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
      with stubbed live `gh` responses and offline JSON fixtures.
- [ ] Cover representative Low, Medium, High, Blocked, and risk-threshold
      mismatch cases.
- [ ] Include no-mutation guards that fail if the helper calls mutating `gh`,
      `git`, or GraphQL operations.
- [ ] Include invalid-input tests for PR number, `--max-risk`, missing fixture
      file, malformed fixture JSON, and incomplete Medium `why_safe_to_merge`
      evidence.

### Protocol and Command Surfaces

- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      to add the risk-classification gate after a candidate PR reaches clean
      reviewer/CI/readiness state and before any delegated merge decision.
- [ ] Document that the classifier is a gate only and does not replace
      reviewer-loop, CI-loop, merge-state checks, unresolved-thread checks, or
      repository merge protocol.
- [ ] Document default `--max-risk low` behavior and the required explicit
      higher tolerance for Medium or High delegated merges.
- [ ] Update `.agents/skills/run-epic/SKILL.md`, `.claude/commands/run-epic.md`,
      and `.cursor/commands/run-epic.md` only where needed to route delegated
      merge decisions through the risk-classification step.

### Documentation

- [ ] Update `docs/workflow/development-workflow/README.md` if its `/run-epic`
      command summary needs to mention the risk gate.
- [ ] Update `AGENTS.md` if the command table or Codex skill prose needs to
      mention risk-gated delegated merge behavior.
- [ ] Add `docs/testing/workflow/919-pr-risk-classification.smoke-test.md`.
- [ ] Add a `CHANGELOG.md` entry under `[Unreleased]` during implementation.

### Database / Data Layer

- [ ] No database or seed data changes.

### Frontend / UI

- [ ] No frontend or UI changes.

### Infrastructure / Configuration

- [ ] No new secrets, environment variables, GitHub App permissions, workflow
      files, or shared repository configuration keys.

---

## Files to Modify

```text
scripts/development-workflow/run-epic-risk-classifier.sh
scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
docs/workflow/development-workflow/README.md
AGENTS.md
.agents/skills/run-epic/SKILL.md
.claude/commands/run-epic.md
.cursor/commands/run-epic.md
docs/testing/workflow/919-pr-risk-classification.smoke-test.md
CHANGELOG.md
```

---

## Testing Strategy

**Test types**: Shell fixture tests, JSON-output assertions, no-mutation guard,
markdown lint, manual smoke review.

**Key scenarios to test**:

1. Low-risk docs/tests/helper-text PR with clean review, clean CI, clear base,
   and no blockers is classified as `low`. Maps to AC1, AC2, AC5, and AC9.
2. Medium-risk workflow-script PR with complete evidence is classified as
   `medium` and includes `why_safe_to_merge`. Maps to AC6 and AC8.
3. Medium-risk workflow-script PR with incomplete `why_safe_to_merge` evidence
   is classified as `blocked`. Maps to AC4 and AC8.
4. High-risk PR touching auth, secrets, permissions, release automation, branch
   deletion behavior, cross-repo credentials, broad shared libraries, or unclear
   behavior is classified as `high`. Maps to AC7.
5. Failing/pending CI, reviewer failure, unresolved blocking thread,
   `needs-setup`, missing credentials, ambiguous tracker/base state, dirty
   merge state, required force-push, or required destructive action produces
   `blocked`. Maps to AC4.
6. Risk above `--max-risk` blocks autonomous merge and reports both assigned
   risk and allowed risk. Maps to AC3.
7. `--json` emits valid JSON with stable keys for risk, max risk, merge
   permitted, reasons, blockers, and why-safe evidence. Maps to AC1 and AC2.

**Smoke test runbook**:
`docs/testing/workflow/919-pr-risk-classification.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/919-pr-risk-classification.smoke-test.md" "AGENTS.md" "CHANGELOG.md"`

### Parser-risk addendum

This plan is parser-risk because the classifier parses CLI options, risk enum
values, PR JSON, labels, check status collections, review/thread summaries,
changed file paths, and optional offline fixture JSON.

**Edge-case enumeration**:

- Missing `--pr` and missing `--input`.
- Both `--pr` and `--input` supplied.
- Invalid PR number: zero, negative, non-numeric, empty, or whitespace-only.
- Invalid `--max-risk`, including `blocked` as an allowed threshold.
- Missing fixture file.
- Malformed fixture JSON.
- Fixture JSON with missing optional fields versus missing required fields.
- Risk enum ordering: `low < medium < high`; `blocked` is never mergeable.
- Required CI states: success, failure, pending, skipped, missing, and
  ambiguous.
- Reviewer states: clean, configured failure, advisory-only, unavailable, and
  unresolved blocking thread.
- Labels: `needs-setup`, readiness labels, unrelated labels, and duplicate
  labels.
- Merge states: clean, dirty, blocked, unknown, and missing.
- Changed-file categories: docs, tests, narrow workflow text, isolated helper,
  workflow scripts, merge/cleanup automation, auth, secrets, permissions,
  release automation, branch deletion, cross-repo credentials, broad shared
  libraries, and unclear changes.
- Medium-risk `why_safe_to_merge` evidence present, missing one required field,
  empty strings, and whitespace-only strings.
- JSON output remains valid when reasons contain quotes, punctuation, issue
  references, and shell metacharacters.

**Unit test mapping**:

Use `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`.

- `requires_one_pr_source` covers missing and conflicting `--pr` / `--input`.
- `validates_pr_number_and_max_risk` covers invalid PR numbers and thresholds.
- `rejects_missing_or_malformed_fixture` covers fixture file and JSON failures.
- `classifies_low_docs_and_tests` covers Low risk.
- `classifies_medium_workflow_script_with_evidence` covers Medium risk and
  complete why-safe evidence.
- `blocks_medium_without_evidence` covers incomplete why-safe evidence.
- `classifies_high_sensitive_scope` covers High risk categories.
- `hard_blockers_take_precedence` covers CI, reviewer, thread, setup,
  credential, tracker/base, merge-state, force-push, and destructive-action
  blockers.
- `max_risk_gate_blocks_excess_risk` covers threshold mismatch.
- `json_output_is_valid_and_stable` covers JSON escaping and required keys.
- `no_mutating_commands_are_called` covers the read-only guarantee.

**Suppression semantics**: Not applicable. The classifier does not introduce
inline suppressions or ignore directives.

### Concurrent-event-source addendum

- **Shared mutable state guards**: Not applicable. The helper is a short-lived
  process with local variables and temporary fixture data only.
- **Re-entrancy / in-flight tracking**: Not applicable. Each invocation
  classifies one PR or fixture independently.
- **Event deduplication**: Not applicable. The helper does not subscribe to
  events.
- **Listener and resource cleanup**: Use a temporary directory only if needed
  for fixture normalization, and clean it with `trap`.
- **Race conditions at initialization**: Live PR data can change while being
  read; the helper must report ambiguous or blocked state when required state
  is unavailable or internally inconsistent.
- **Race conditions at teardown**: Not applicable beyond temporary-directory
  cleanup.
- **Error propagation across async boundaries**: Not applicable. Bash command
  failures should surface through `set -euo pipefail` plus explicit error
  messages for expected validation failures.

---

## Seed Data

No persistent seed data is required. Fixture tests should define temporary PR
state JSON for Low, Medium, High, Blocked, max-risk mismatch, and invalid-input
cases.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` -
      add the delegated PR risk-classification gate.
- [ ] `docs/workflow/development-workflow/README.md` - mention the risk gate if
      the `/run-epic` command summary now describes delegated merge behavior.
- [ ] `AGENTS.md` - mention the risk gate if the command table or Codex skill
      prose now describes delegated merge behavior.
- [ ] `.agents/skills/run-epic/SKILL.md`, `.claude/commands/run-epic.md`, and
      `.cursor/commands/run-epic.md` - route delegated merge decisions through
      the classifier without redefining the protocol.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` entry during implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Classifier permits a merge when required readiness state is stale or ambiguous. | Medium | High | Treat unavailable, pending, missing, or internally inconsistent required evidence as `blocked`. |
| File-category heuristics under-classify a sensitive change. | Medium | High | Prefer higher risk when categories overlap and cover sensitive paths with fixture tests. |
| Medium-risk evidence becomes boilerplate instead of useful audit signal. | Medium | Medium | Require non-empty structured fields for scope, tests, reviewer outcome, CI, and rollback or cleanup risk. |
| Helper accidentally mutates PR, branch, or tracker state. | Low | High | Keep it read-only and enforce with stubbed no-mutation tests. |
| `/run-epic` docs imply the classifier replaces reviewer or CI gates. | Low | High | Document it as an additional pre-merge gate that runs after normal readiness checks and before merge. |

---

## Implementation Order

1. Add `scripts/development-workflow/run-epic-risk-classifier.sh` with
   read-only CLI parsing for `--pr`, `--input`, `--max-risk`, `--json`, and
   help output.
2. Implement enum validation, risk ordering, fixture loading, and text/JSON
   output scaffolding.
3. Implement live PR-state collection through read-only `gh` calls for labels,
   base/head, merge state, changed files, checks, and review/thread summary
   fields that the repository can read deterministically.
4. Implement hard-blocker precedence.
5. Implement changed-file and state-based Low, Medium, and High risk rules.
6. Implement `--max-risk` gating and mismatch reasons.
7. Implement Medium-risk `why_safe_to_merge` validation and output.
8. Add `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
   with fixtures for all parser-risk and acceptance-criteria cases.
9. Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
   to call the classifier before delegated merge decisions.
10. Update `.agents/skills/run-epic/SKILL.md`, `.claude/commands/run-epic.md`,
    and `.cursor/commands/run-epic.md` as needed so command guidance points to
    the risk gate.
11. Update `docs/workflow/development-workflow/README.md` and `AGENTS.md` only
    if the command summary needs to reflect delegated merge behavior.
12. Add `docs/testing/workflow/919-pr-risk-classification.smoke-test.md`.
13. Add this CHANGELOG entry under `[Unreleased]`:

    ```markdown
    - **Add PR risk classification** (#919): add a conservative risk gate for
      delegated `/run-epic` merge decisions.
    ```

14. Run validation:

    ```bash
    bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
    npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/919-pr-risk-classification.smoke-test.md" "AGENTS.md" "CHANGELOG.md"
    ```

15. Confirm `git status --short` shows only intended implementation files
    before committing.

---

## Cross-Section Consistency Self-Check

- The classifier script name is consistently
  `scripts/development-workflow/run-epic-risk-classifier.sh`.
- The test harness is consistently
  `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`.
- The runbook is consistently
  `docs/testing/workflow/919-pr-risk-classification.smoke-test.md`.
- The risk levels are consistently `low`, `medium`, `high`, and `blocked`.
- `blocked` is consistently a hard-blocking state, not an allowed `--max-risk`.
- Medium-risk delegated merge consistently requires `why_safe_to_merge` fields
  for scope, tests, reviewer outcome, CI outcome, and rollback or cleanup risk.
- The classifier is consistently read-only and does not replace reviewer-loop,
  CI-loop, thread, merge-state, or repository merge protocol checks.

---

## Document Quality Gate

- Spec/brief coverage: Checked - all ACs map to implementation steps and tests.
- Implementation-order consistency: Checked - file names, helper names, risk
  levels, and documentation targets agree across sections.
- Verification support: Checked - scope and file-surface claims cite the
  Verification Log.
- Behavioral guarantees: Checked - hard blockers, max-risk gating, medium-risk
  evidence, and read-only behavior are explicit.
- Parser/API/concurrency checklist: Checked - parser-risk applies and has an
  edge-case enumeration plus test mapping; concurrent event-source risks are
  mostly not applicable but live-state race behavior is documented.
- CHANGELOG literal format: Checked - implementation order uses the project's
  bold-title issue format.
