# Delegated Review and Merge Loop for Run Epic - Implementation Plan

**Spec**:
[1_918-delegated-review-merge-loop_specs.md](1_918-delegated-review-merge-loop_specs.md)
**Smoke test runbook**:
[918-delegated-review-merge-loop.smoke-test.md](../../../testing/workflow/918-delegated-review-merge-loop.smoke-test.md)

---

## Summary

**Approach**: Extend `/run-epic` from resolver plus sibling gates into an
explicit delegated execution contract. Keep actual stage execution, reviewer
loop, CI loop, merge, post-merge cleanup, and tracker updates owned by the
existing workflow protocols and scripts; add policy capture to the scope
resolver and a read-only delegated readiness gate that determines whether a
candidate PR may proceed to the repository merge protocol.

**Estimated complexity**: M

**Rationale**: The change is contained to workflow shell helpers, tests, and
workflow guidance, but it coordinates multiple safety gates. The implementation
must avoid silently widening authority, must not mutate out-of-scope items, and
must remain testable without live merges.

**Dependencies**: #917, #919, and #920 are merged. #917 provides scope
resolution, #919 provides risk classification, and #920 provides audit trail
comments.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `608abdd` |
| Template-fit check | `cat .ai-dev-workflow.yaml` | `template.is_template: true`; this feature is generic workflow tooling for all downstream projects. |
| Existing run-epic protocol | `sed -n '1,320p' docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Current protocol covers resolver, risk gate, and audit trail but not the delegated review/merge control loop. |
| Existing helper surfaces | `rg -n "run-epic-scope-resolver|run-epic-risk-classifier|run-epic-audit-trail" scripts/development-workflow .agents .claude .cursor docs/workflow/development-workflow AGENTS.md` | Resolver, risk classifier, and audit helper already exist and are referenced by command wrappers. |
| Readiness labels | `sed -n '1,120p' docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | `ready-for-regression` applies to implementation PRs; `ready-for-human-review` requires CI and reviewer gates. |
| Existing tests | `ls scripts/development-workflow/tests/test-run-epic-*.sh` | Existing fixture tests cover scope resolver, risk classifier, and audit trail; #918 should add delegated policy/readiness coverage. |
| Existing smoke runbooks | `ls docs/testing/workflow/*run-epic*.smoke-test.md docs/testing/workflow/91*.smoke-test.md docs/testing/workflow/92*.smoke-test.md 2>/dev/null` | #917, #919, and #920 runbooks establish the workflow test style for this epic. |

---

## Layer-by-Layer Changes

### Run Epic Scope Resolver

- [ ] Extend `scripts/development-workflow/run-epic-scope-resolver.sh` to accept
      delegation policy flags while remaining read-only:
      `--delegate-review`, `--may-merge`,
      `--may-start-backlog <true|false>`, and `--max-risk <low|medium|high>`.
- [ ] Keep existing `--epic`, `--items`, `--base`, and `--json` behavior
      backward-compatible.
- [ ] Validate delegation flags before tracker or GitHub reads.
- [ ] Emit a policy block in JSON output with review authority, merge
      authority, backlog-start policy, maximum risk, and base source.
- [ ] Emit the same policy values in human-readable output.
- [ ] Ensure resolver output still states the read-only guarantee.

### Delegated Readiness Gate

- [ ] Add `scripts/development-workflow/run-epic-delegated-gate.sh`.
- [ ] Support `--input <file>` for fixture/offline validation and `--pr
      <number>` for live read-only PR validation.
- [ ] Support `--policy <file>` or inline policy flags matching the resolver
      output, so tests can verify authority boundaries without live mutation.
- [ ] Validate the candidate PR against final delegated merge requirements:
      non-draft state, in-scope item, `ready-for-human-review`,
      `ready-for-regression` when branch prefix requires it, green CI, clean
      merge state, no `needs-setup`, no unresolved blocking bot threads,
      acceptable reviewer disposition, and risk permitted by the invocation.
- [ ] Treat missing or ambiguous required state as blocked.
- [ ] Emit a machine-readable JSON decision and a human-readable summary:
      `merge_allowed`, `fix_required`, `human_required`, or `blocked`.
- [ ] Include reasons and recommended next action for every non-merge decision.
- [ ] Keep the gate read-only. It must not run reviewer loops, poll CI, edit
      labels, create comments, update tracker status, merge PRs, close issues,
      or delete branches.

### Delegated Loop Protocol

- [ ] Update
      `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      to add delegated execution steps after scope resolution:
      authority capture, backlog-start handling, item advancement through
      `/run-item-work`, delegated review decision, fix-and-rerun behavior,
      final readiness gate, risk classification, PR disposition audit, merge,
      post-merge cleanup, rediscovery, and parent epic closeout.
- [ ] Document that the resolver remains read-only even when delegation flags
      are supplied.
- [ ] Document that actual merge operations still use repository merge
      protocol, `gh pr merge`, batch-merge, or post-merge cleanup as
      appropriate.
- [ ] Document the label removal/restoration rule before and after fix pushes.
- [ ] Document the no amend/force-push rule for published PR fixes.
- [ ] Document stop conditions and final reporting requirements.

### Command and Skill Surfaces

- [ ] Update `.agents/skills/run-epic/SKILL.md` and
      `.agents/skills/run-epic/agents/openai.yaml` so Codex users see the new
      delegation flags and the delegated gate.
- [ ] Update `.claude/commands/run-epic.md` and
      `.cursor/commands/run-epic.md` with the same delegation flag summary and
      safety boundaries.
- [ ] Update `docs/workflow/development-workflow/README.md` and `AGENTS.md`
      where they summarize `/run-epic`, so the command is no longer described
      only as scope resolution plus risk/audit gates.

### Tests

- [ ] Extend `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
      for delegation flag parsing, invalid flag values, JSON policy output, and
      text policy output.
- [ ] Add `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
      with fixture coverage for merge allowed, missing delegated authority,
      Backlog policy boundary, missing labels, implementation PR missing
      `ready-for-regression`, failing/pending CI, dirty merge state,
      `needs-setup`, unresolved blocking thread, reviewer blocker, risk above
      max risk, and successful merge cleanup preconditions.
- [ ] Include no-mutation guards that fail if the delegated gate invokes
      mutating `gh`, `git`, or GraphQL operations.
- [ ] Update related run-epic test runbooks.

### Documentation

- [ ] Add
      `docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md`.
- [ ] Add a `CHANGELOG.md` entry under `[Unreleased]` during implementation.

### Database / Data Layer

- [ ] No database, migration, generated type, or seed data changes.

### Frontend / UI

- [ ] No frontend or UI changes.

### Infrastructure / Configuration

- [ ] No new secrets, GitHub App permissions, workflow files, or repository
      configuration keys.

---

## Files to Modify

```text
scripts/development-workflow/run-epic-scope-resolver.sh
scripts/development-workflow/run-epic-delegated-gate.sh
scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
.agents/skills/run-epic/SKILL.md
.agents/skills/run-epic/agents/openai.yaml
.claude/commands/run-epic.md
.cursor/commands/run-epic.md
docs/workflow/development-workflow/README.md
AGENTS.md
docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md
CHANGELOG.md
```

---

## Testing Strategy

**Test types**: Shell fixture tests, JSON-output assertions, no-mutation guard,
markdown lint, manual smoke review.

**Key scenarios to test**:

1. Resolver records delegated review, merge, backlog-start, max-risk, and base
   policy before mutation. Maps to AC1.
2. Explicit item-list policy remains bounded and does not authorize
   out-of-scope mutation. Maps to AC2.
3. Backlog start denied blocks starting Backlog items even when dependencies
   are satisfied. Maps to AC3 and AC11.
4. Blocking reviewer finding produces `fix_required`, requires readiness-label
   removal, and requires rerun before readiness restoration. Maps to AC4.
5. Advisory findings produce a fix-or-accept decision with rationale. Maps to
   AC5.
6. Published PR fix flow is represented as normal follow-up commits, not
   amend/force-push. Maps to AC6.
7. Final delegated gate permits merge only when labels, CI, merge state,
   unresolved threads, setup labels, reviewer state, and risk policy are all
   clean. Maps to AC7.
8. Audit disposition is required before a merge decision is considered
   complete. Maps to AC8.
9. Post-merge cleanup and rediscovery are listed as required follow-up actions.
   Maps to AC9.
10. Parent epic closeout checks require live native sub-issue and Project state.
    Maps to AC10.
11. Blocked dependencies, services, credentials, destructive actions, risk
    limits, ambiguity, and backlog boundaries stop with clear reasons. Maps to
    AC11.
12. Fixture tests cover the delegated review and merge loop decisions. Maps to
    AC12.

**Smoke test runbook**:
`docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
- `bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`
- `bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
- `bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
- `shellcheck -x scripts/development-workflow/run-epic-scope-resolver.sh scripts/development-workflow/run-epic-risk-classifier.sh scripts/development-workflow/run-epic-audit-trail.sh scripts/development-workflow/run-epic-delegated-gate.sh scripts/development-workflow/tests/test-run-epic-scope-resolver.sh scripts/development-workflow/tests/test-run-epic-risk-classifier.sh scripts/development-workflow/tests/test-run-epic-audit-trail.sh scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md" "AGENTS.md" "CHANGELOG.md" ".agents/skills/run-epic/SKILL.md" ".claude/commands/run-epic.md" ".cursor/commands/run-epic.md"`

### Parser-risk addendum

This plan is parser-risk because it changes CLI option parsing, JSON fixture
loading, status/label/risk normalization, branch-prefix interpretation, and
structured decision output.

**Edge-case enumeration**:

- Missing scope source while delegation flags are present.
- Unknown delegation flag.
- Missing values for `--may-start-backlog` and `--max-risk`.
- Invalid boolean values for `--may-start-backlog`.
- Invalid max-risk values, including `blocked`.
- Delegation flags in text output and JSON output.
- Explicit item-list with duplicate items and delegation policy.
- Backlog item with policy denied versus allowed.
- Candidate PR not in resolved scope.
- Draft PR.
- Missing `ready-for-human-review`.
- Feature/refactor/fix/hotfix PR missing `ready-for-regression`.
- Spec or plan PR without `ready-for-regression`.
- Failing, pending, missing, or duplicated CI statuses.
- Dirty, blocked, unknown, or missing merge state.
- `needs-setup` present.
- Reviewer blocker present.
- Advisory-only reviewer state with accepted rationale.
- Unresolved blocking bot thread present.
- Risk classifier blocked.
- Risk above max risk.
- Complete medium-risk why-safe evidence.
- Audit disposition missing before merge.
- Parent epic has one open child after final item merge.
- Parent epic has all child issues closed and terminal Project statuses.
- Fixture JSON is missing, empty, malformed, or missing required fields.
- JSON output contains reasons with quotes, pipes, issue references, and shell
  metacharacters.

**Unit test mapping**:

Use `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` for
resolver policy parsing and
`scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` for final
gate decisions.

- `delegation_flags_parse_to_policy` covers valid policy output.
- `rejects_invalid_delegation_flags` covers unknown and invalid values.
- `explicit_items_policy_bounded` covers item-list scope plus policy.
- `backlog_policy_denied_blocks_start` covers Backlog boundary.
- `candidate_not_in_scope_blocks` covers out-of-scope PRs.
- `requires_non_draft_and_labels` covers draft and label cases.
- `feature_pr_requires_regression_label` covers branch-prefix label rules.
- `spec_plan_skip_regression_label` covers non-implementation PRs.
- `ci_and_merge_state_blockers` covers CI and merge-state variants.
- `needs_setup_blocks_merge` covers setup labels.
- `reviewer_blocker_requires_fix` covers blocking reviewer findings.
- `advisory_requires_rationale` covers accepted advisory decisions.
- `unresolved_thread_blocks` covers bot-thread state.
- `risk_gate_blocks_or_allows` covers risk decisions and max-risk mismatch.
- `audit_required_before_merge` covers PR disposition requirement.
- `parent_epic_closeout_requires_terminal_children` covers closeout checks.
- `no_mutating_commands_are_called` covers read-only guarantee.

**Suppression semantics**: Not applicable. The delegated gate does not
introduce inline suppression directives.

### Concurrent-event-source addendum

- **Shared mutable state guards**: Not applicable. Helpers are short-lived
  shell processes using local fixture or live PR snapshots.
- **Re-entrancy / in-flight tracking**: Not applicable inside one helper
  invocation. The protocol handles reruns by re-reading live state before every
  decision.
- **Event deduplication**: Not applicable. No event subscription is introduced.
- **Listener and resource cleanup**: Temporary fixture files must use
  `mktemp -d` plus a single `trap ... EXIT`.
- **Race conditions at initialization**: Live PR state can change while being
  read; missing or internally inconsistent required state must block rather
  than permit merge.
- **Race conditions at teardown**: Not applicable beyond temporary directory
  cleanup.
- **Error propagation across async boundaries**: Not applicable. Bash command
  failures must surface through `set -euo pipefail` plus explicit `gh` and
  `jq` guards.

---

## Seed Data

No persistent seed data is required. Fixture tests should create temporary
policy JSON, scope JSON, PR state JSON, reviewer state, CI state, risk output,
audit disposition state, and parent epic closeout state.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` -
      add delegated review and merge loop behavior.
- [ ] `.agents/skills/run-epic/SKILL.md` and
      `.agents/skills/run-epic/agents/openai.yaml` - document delegation flags
      and gate ordering.
- [ ] `.claude/commands/run-epic.md` and `.cursor/commands/run-epic.md` -
      mirror delegation flag and gate guidance.
- [ ] `docs/workflow/development-workflow/README.md` and `AGENTS.md` - update
      `/run-epic` summaries.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` entry during implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Delegation flags are mistaken as permission to mutate during scope resolution. | Medium | High | Keep resolver read-only and state the read-only guarantee in output and tests. |
| Final gate permits merge with stale or incomplete readiness state. | Medium | High | Treat missing, pending, ambiguous, or inconsistent evidence as blocked. |
| `/run-epic` duplicates `/run-work` or `/run-item-work` logic. | Medium | Medium | Protocol must call existing item, reviewer, CI, merge, and cleanup protocols rather than reimplementing them. |
| Accepted advisories become invisible. | Medium | Medium | Require audit disposition rationale before merge. |
| Parent epic closes prematurely. | Low | High | Require native sub-issue and Project status verification before closeout. |
| Test harness misses mutating commands. | Low | High | Stub and fail on `gh pr merge`, label edits, issue close, tracker updates, branch deletion, and GraphQL mutations. |

---

## Code Samples

No production code samples are required in the plan. Implementation should
follow existing Bash helper patterns in the resolver, classifier, and audit
trail scripts.

---

## Implementation Order

1. Extend `scripts/development-workflow/run-epic-scope-resolver.sh` to parse
   delegation policy flags and emit policy output in text and JSON.
2. Update `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
   for the new policy parsing and read-only guarantees.
3. Add `scripts/development-workflow/run-epic-delegated-gate.sh` as a
   read-only final decision helper with fixture and live PR input support.
4. Add `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
   with parser-risk and acceptance-criteria fixture coverage.
5. Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
   with the delegated review and merge loop.
6. Update `.agents/skills/run-epic/SKILL.md`,
   `.agents/skills/run-epic/agents/openai.yaml`,
   `.claude/commands/run-epic.md`, and `.cursor/commands/run-epic.md`.
7. Update `docs/workflow/development-workflow/README.md` and `AGENTS.md`
   command summaries.
8. Add `docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md`.
9. Add this CHANGELOG entry under `[Unreleased]`:

   ```markdown
   - **Add delegated run-epic review and merge loop** (#918): add explicit
     delegation policy and final readiness gating for bounded `/run-epic`
     executions.
   ```

10. Run validation:

    ```bash
    bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
    bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
    bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
    bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
    shellcheck -x scripts/development-workflow/run-epic-scope-resolver.sh scripts/development-workflow/run-epic-risk-classifier.sh scripts/development-workflow/run-epic-audit-trail.sh scripts/development-workflow/run-epic-delegated-gate.sh scripts/development-workflow/tests/test-run-epic-scope-resolver.sh scripts/development-workflow/tests/test-run-epic-risk-classifier.sh scripts/development-workflow/tests/test-run-epic-audit-trail.sh scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
    npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md" "AGENTS.md" "CHANGELOG.md" ".agents/skills/run-epic/SKILL.md" ".claude/commands/run-epic.md" ".cursor/commands/run-epic.md"
    ```

---

## Cross-Section Consistency Self-Check

- Delegation policy flags are consistently named `--delegate-review`,
  `--may-merge`, `--may-start-backlog`, and `--max-risk`.
- The new final gate helper is consistently named
  `scripts/development-workflow/run-epic-delegated-gate.sh`.
- Resolver and delegated gate helpers are consistently described as read-only.
- Actual item advancement, reviewer-loop, CI-loop, merge, cleanup, and tracker
  updates remain owned by existing workflow protocols and scripts.
- Implementation PRs consistently require `ready-for-regression`; spec and plan
  PRs do not.

---

## Document Quality Gate

- Spec/brief coverage: Checked - every acceptance criterion maps to
  implementation steps and tests.
- Implementation-order consistency: Checked - file list and ordered steps use
  the same helper names and delegation flag names.
- Verification support: Checked - existing protocol, helper, and label behavior
  claims cite live repository reads.
- Behavioral guarantees: Checked - read-only resolver/gate behavior, label
  removal/restoration, risk gating, audit requirements, and closeout checks are
  explicit.
- Parser/API/concurrency checklist: Checked - parser-risk edge cases and unit
  test mapping are included; concurrency is not introduced.
- CHANGELOG literal format: Checked - implementation order uses the project's
  bold-title issue format.
