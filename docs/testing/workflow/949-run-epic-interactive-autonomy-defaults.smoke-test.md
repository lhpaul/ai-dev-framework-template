# Smoke Test Runbook: Run Epic Interactive Autonomy Defaults

**Feature**: Run Epic Interactive Autonomy Defaults
**Spec**:
[GitHub issue #949](https://github.com/lhpaul/ai-dev-framework-template/issues/949)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #949.
- [ ] The PR targets `develop`.
- [ ] Fixture tests are available and do not require live GitHub mutation.
- [ ] Existing `/run-epic` resolver, risk, audit, and delegated gate tests pass
      before new behavior is assessed.

---

## Test Data

| Item | Value |
| --- | --- |
| Policy recommender | `scripts/development-workflow/run-epic-policy-recommender.sh` |
| Scope resolver | `scripts/development-workflow/run-epic-scope-resolver.sh` |
| Audit helper | `scripts/development-workflow/run-epic-audit-trail.sh` |
| Run-epic protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |
| Codex alias | `.agents/skills/run-epic/SKILL.md` |
| Claude command | `.claude/commands/run-epic.md` |
| Cursor command | `.cursor/commands/run-epic.md` |

---

## Smoke Test Steps

### Step 1: Verify Policy Recommendation

**Maps to**: issue requirements 1, 2, 3, 4, 5, and 6.

1. Run the policy recommender fixture tests.
2. Confirm underspecified explicit item and epic scopes produce a recommended
   policy with `mayStartBacklog`, `delegateReview`, `mayMerge`, `maxRisk`, and
   `base`.
3. Confirm Backlog scope with no dependency blocker recommends
   `mayStartBacklog: true`.
4. Confirm blocked dependencies, ambiguous bases, or unavailable reviewers
   recommend a safer value and require confirmation.
5. Confirm workflow/tooling scope recommends `maxRisk: medium` with a rationale
   and does not recommend `high`.

**Expected result**: The helper provides deterministic, safe recommendations
without mutating tracker, branch, PR, label, issue, or merge state.

### Step 2: Verify In-Place Confirmation Guidance

**Maps to**: issue requirements 1, 5, 6, and 7.

1. Open the run-epic protocol and command wrappers.
2. Confirm the resolver remains read-only.
3. Confirm underspecified policy values route to an in-place confirmation prompt
   instead of a rerun instruction.
4. Confirm accepting the recommendation continues the same run using the
   selected policy.
5. Confirm fully specified invocations do not repeatedly ask for the same
   policy choice within the same invocation.

**Expected result**: The command can continue without requiring the human to
paste a replacement command.

### Step 3: Verify Audit Evidence

**Maps to**: issue requirements 8 and 10.

1. Run the audit trail tests.
2. Inspect rendered PR disposition output.
3. Confirm it records the originally requested command, recommended policy,
   selected policy, effective policy, human confirmation/customization, and
   copy-paste equivalent command.
4. Confirm older audit fixtures without policy evidence still render
   successfully.
5. Confirm local paths, tokens, shell metacharacters, pipes, and newlines are
   redacted or escaped safely.

**Expected result**: Delegated decisions include reproducible policy evidence
without breaking prior audit inputs.

### Step 4: Verify Stop Gate Reporting

**Maps to**: issue requirement 9.

1. Inspect policy recommender, delegated gate, and protocol fixtures for stop
   cases.
2. Confirm final output distinguishes missing authority, risk classification,
   CI/check state, unresolved reviewer findings, tracker ambiguity, and
   delegated gate blocks.
3. Confirm ambiguous base or risk above allowed tolerance stops before mutation.

**Expected result**: Autonomous progress stops with a specific gate reason, not
a generic failure.

### Step 5: Run Automated Validation

**Maps to**: all issue requirements.

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
   bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
   bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
   bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
   shellcheck -x scripts/development-workflow/run-epic-policy-recommender.sh scripts/development-workflow/run-epic-audit-trail.sh scripts/development-workflow/tests/test-run-epic-policy-recommender.sh scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
   npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/949-run-epic-interactive-autonomy-defaults.smoke-test.md" "AGENTS.md" "CHANGELOG.md" ".agents/skills/run-epic/SKILL.md" ".claude/commands/run-epic.md" ".cursor/commands/run-epic.md"
   ```

2. Confirm all commands pass.

**Expected result**: Policy recommendation, audit evidence, existing run-epic
gates, shell quality, and documentation formatting are validated.

---

## Assertions Checklist

- [ ] Requirement 1: Missing or ambiguous parameters trigger an in-place prompt
      instead of a rerun instruction.
- [ ] Requirement 2: The prompt recommends the most automatic safe
      configuration by default.
- [ ] Requirement 3: Recommendations are derived from resolved scope state.
- [ ] Requirement 4: Recommendations include Backlog, review, merge, risk, and
      base values.
- [ ] Requirement 5: Risk tradeoffs are explained in plain language.
- [ ] Requirement 6: Accepting the recommendation continues the current run.
- [ ] Requirement 7: The same policy choice is not repeatedly requested within
      one invocation.
- [ ] Requirement 8: Audit evidence records original, recommended, selected,
      and effective policy.
- [ ] Requirement 9: Stops identify the exact blocking gate.
- [ ] Requirement 10: A copy-paste equivalent command is recorded.

---

## Seed Data Reference

No persistent seed data is required. Fixture tests provide temporary scope,
policy, reviewer availability, risk, audit, and stop-gate state.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Helper recommends `high` risk | Recommendation cap is missing | Cap recommendations at `medium` and require a human for high risk. |
| Prompt asks again after acceptance | Selected policy was not carried in invocation state | Preserve selected/effective policy in the handoff and audit input. |
| Resolver mutates state | Recommendation logic was added to the wrong helper | Keep resolver read-only and place recommendation in the separate policy helper. |
| Audit table renders incorrectly | Policy rationale was not escaped | Reuse existing audit table escaping and add punctuation-heavy fixtures. |
| Stop output is generic | Gate reason mapping is incomplete | Emit the specific authority, risk, CI, reviewer, tracker, or delegated-gate reason. |

---

## Known Limitations

- The feature does not introduce a repo-wide autonomy profile. Policy remains
  invocation-scoped.
- The policy recommender is read-only. Actual review, fix, CI, merge, cleanup,
  and tracker updates remain owned by the existing workflow protocols and
  helpers.

