# Smoke Test Runbook: Delegated Review and Merge Loop for Run Epic

**Feature**: Delegated Review and Merge Loop for Run Epic
**Spec**:
[1_918-delegated-review-merge-loop_specs.md](../../specs/developments/20260615073146_918-delegated-review-merge-loop/1_918-delegated-review-merge-loop_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #918.
- [ ] The PR targets `develop-delegated-epic-orchestration`.
- [ ] Fixture tests are available and do not require live GitHub mutation.
- [ ] #917, #919, and #920 are merged on the target branch.

---

## Test Data

| Item | Value |
| --- | --- |
| Scope resolver | `scripts/development-workflow/run-epic-scope-resolver.sh` |
| Delegated gate | `scripts/development-workflow/run-epic-delegated-gate.sh` |
| Risk classifier | `scripts/development-workflow/run-epic-risk-classifier.sh` |
| Audit helper | `scripts/development-workflow/run-epic-audit-trail.sh` |
| Run-epic protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |

---

## Smoke Test Steps

### Step 1: Verify Delegation Policy Capture

**Maps to**: AC1, AC3, AC11

1. Run the scope resolver fixture tests.
2. Confirm `--delegate-review`, `--may-merge`,
   `--may-start-backlog <true|false>`, and `--max-risk <low|medium|high>` are
   validated before live lookups.
3. Confirm JSON output contains the policy block.
4. Confirm text output reports the same policy values.

**Expected result**: The run records authority boundaries before item mutation.

### Step 2: Verify Scope Boundaries

**Maps to**: AC2, AC3, AC11

1. Inspect explicit item-list fixtures.
2. Confirm duplicate items are collapsed without expanding scope.
3. Confirm out-of-scope PR or issue fixtures produce a blocked decision.
4. Confirm Backlog items are blocked when the policy denies Backlog starts.

**Expected result**: Delegated runs cannot mutate outside their resolved scope
or start Backlog items without explicit authority.

### Step 3: Verify Reviewer and Advisory Decisions

**Maps to**: AC4, AC5, AC6

1. Run the delegated gate fixture tests.
2. Inspect the reviewer-blocker fixture.
3. Confirm it returns `fix_required` and requires readiness-label removal plus
   rerun before labels are restored.
4. Inspect the advisory-only fixture.
5. Confirm accepted advisories require rationale.
6. Confirm published PR fix guidance uses follow-up commits, not force-push.

**Expected result**: Blocking findings route to fix-and-rerun; advisories have
documented decisions.

### Step 4: Verify Final Merge Gate

**Maps to**: AC7, AC8

1. Inspect merge-candidate fixtures for non-draft state, labels, CI, merge
   state, setup labels, unresolved threads, reviewer state, risk output, and
   audit disposition state.
2. Confirm the fully clean implementation PR fixture returns `merge_allowed`.
3. Confirm each missing or failing gate returns `blocked`, `fix_required`, or
   `human_required` with a reason.

**Expected result**: Merge is allowed only when every readiness, risk, and audit
gate is satisfied.

### Step 5: Verify Merge Cleanup and Epic Closeout Guidance

**Maps to**: AC9, AC10

1. Open the run-epic protocol.
2. Confirm delegated merge guidance requires PR merged verification, branch
   cleanup, tracker update, and rediscovery after every merge.
3. Confirm final child-item closeout requires native sub-issue and Project
   status verification before closing the parent epic.

**Expected result**: The epic cannot be declared complete from stale state.

### Step 6: Run Automated Validation

**Maps to**: AC1 through AC12

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
   bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
   bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
   shellcheck -x scripts/development-workflow/run-epic-scope-resolver.sh scripts/development-workflow/run-epic-risk-classifier.sh scripts/development-workflow/run-epic-audit-trail.sh scripts/development-workflow/run-epic-delegated-gate.sh scripts/development-workflow/tests/test-run-epic-scope-resolver.sh scripts/development-workflow/tests/test-run-epic-risk-classifier.sh scripts/development-workflow/tests/test-run-epic-audit-trail.sh scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
   npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/918-delegated-review-merge-loop.smoke-test.md" "AGENTS.md" "CHANGELOG.md" ".agents/skills/run-epic/SKILL.md" ".claude/commands/run-epic.md" ".cursor/commands/run-epic.md"
   ```

2. Confirm all commands pass.

**Expected result**: Delegated policy, readiness decisions, existing risk and
audit helpers, shell quality, and documentation formatting are validated.

---

## Assertions Checklist

- [ ] AC1: Delegated invocation records authority, Backlog policy, max risk,
      and base branch.
- [ ] AC2: Explicit item-list scope blocks out-of-scope mutation.
- [ ] AC3: Backlog starts require explicit authority.
- [ ] AC4: Blocking reviewer findings remove labels, fix, rerun, and verify
      before readiness is restored.
- [ ] AC5: Advisory findings have fix-or-accept decisions with rationale when
      accepted.
- [ ] AC6: Published PR fixes use follow-up commits instead of amend plus
      force-push.
- [ ] AC7: Final gate checks non-draft, labels, CI, merge state, unresolved
      threads, setup labels, reviewer state, and risk policy.
- [ ] AC8: PR disposition audit is required before merge.
- [ ] AC9: Merge verification, branch cleanup, tracker update, ledger update,
      and rediscovery happen after merge.
- [ ] AC10: Parent epic closeout checks native sub-issues and Project statuses.
- [ ] AC11: Blocked dependencies, unavailable services, missing credentials,
      destructive actions, ambiguity, risk limits, and Backlog boundaries stop
      clearly.
- [ ] AC12: Fixture tests cover delegated review and merge loop decisions.

---

## Seed Data Reference

No persistent seed data is required. Fixture tests provide temporary policy,
scope, PR, reviewer, CI, risk, audit, and epic closeout state.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Resolver appears to authorize mutation | Delegation policy output is being confused with execution | Confirm resolver output still states the read-only guarantee and no mutating command is invoked. |
| Merge is allowed without `ready-for-regression` | Branch-prefix label rule is missing | Add implementation-branch fixture coverage and block feature/fix/refactor/hotfix PRs missing the label. |
| Advisory appears in reviewer output but not audit | Advisory disposition mapping is missing | Require a rationale fixture before `merge_allowed`. |
| Parent epic closes with an open child | Closeout check used stale state | Re-read native sub-issues and Project statuses immediately before closeout. |
| JSON output fails downstream parsing | Reasons were assembled by string concatenation | Build JSON with `jq` and add punctuation-heavy fixture values. |

---

## Known Limitations

- The delegated readiness gate is read-only. Actual item advancement, reviewer
  loops, CI polling, merges, cleanup, tracker updates, and issue closeout remain
  owned by the existing workflow protocols and scripts.
- The feature does not introduce an always-on autonomy profile; authority is
  invocation-scoped.
