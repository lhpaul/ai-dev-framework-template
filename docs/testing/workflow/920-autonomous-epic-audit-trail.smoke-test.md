# Smoke Test Runbook: Autonomous Epic Audit Trail

**Feature**: Autonomous Epic Audit Trail
**Spec**:
[1_920-autonomous-epic-audit-trail_specs.md](../../specs/developments/20260612193017_920-autonomous-epic-audit-trail/1_920-autonomous-epic-audit-trail_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #920.
- [ ] The PR targets `develop-delegated-epic-orchestration`.
- [ ] Fixture tests are available and do not require live GitHub comment writes.

---

## Test Data

| Item | Value |
| --- | --- |
| Audit helper | `scripts/development-workflow/run-epic-audit-trail.sh` |
| Audit tests | `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` |
| Run-epic protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |
| PR marker | `<!-- run-epic:pr-disposition -->` |
| Epic marker | `<!-- run-epic:epic-ledger -->` |

---

## Smoke Test Steps

### Step 1: Verify PR Disposition Rendering

**Maps to**: AC1, AC3, AC4, AC8, AC9

1. Run the audit fixture test harness.
2. Inspect the PR disposition render fixture.
3. Confirm the output includes the stable marker, reviewed SHA, reviewer
   result, advisory dispositions/rationales, risk evidence, merge authority,
   final decision, verification evidence, and protocol deviations.
4. Confirm redaction removes secrets and local-only paths.

**Expected result**: PR disposition output is complete, marked, and redacted.

### Step 2: Verify PR Comment Update Semantics

**Maps to**: AC1, AC2

1. Inspect the stubbed comment list with an existing PR marker.
2. Confirm apply mode updates the existing comment.
3. Inspect the stubbed comment list without a marker.
4. Confirm apply mode creates exactly one comment.

**Expected result**: Reruns update comments instead of duplicating them.

### Step 3: Verify Epic Ledger Rendering

**Maps to**: AC5, AC6

1. Inspect the epic ledger render fixture.
2. Confirm each child row includes issue, PR, tracker status, risk, review
   result, decision, merge/cleanup verification, and notes.
3. Confirm the output includes the stable epic ledger marker.

**Expected result**: Epic ledger output summarizes all child items.

### Step 4: Verify Explicit Item-List Behavior

**Maps to**: AC7

1. Inspect an explicit item-list fixture without a parent epic.
2. Confirm PR disposition output still renders.
3. Confirm epic ledger output reports not applicable instead of failing or
   writing to an unrelated issue.

**Expected result**: Item-list runs keep PR audit comments without requiring an
epic ledger.

### Step 5: Run Automated Validation

**Maps to**: AC1 through AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/920-autonomous-epic-audit-trail.smoke-test.md" "AGENTS.md" "CHANGELOG.md"
   ```

2. Confirm all commands pass.

**Expected result**: Audit rendering, comment update semantics, and docs
formatting are validated.

---

## Assertions Checklist

- [ ] AC1: PR disposition comment uses a stable marker.
- [ ] AC2: Reruns update the PR disposition comment.
- [ ] AC3: PR disposition includes required decision evidence.
- [ ] AC4: Advisory decisions and rationales are recorded.
- [ ] AC5: Epic ledger comment uses a stable marker.
- [ ] AC6: Epic ledger includes required child-item columns.
- [ ] AC7: Explicit item-list runs handle missing epic ledger as not applicable.
- [ ] AC8: Audit comments omit secrets and local-only paths.
- [ ] AC9: Protocol deviations include action, impact, and mitigation.
- [ ] AC10: Fixture tests cover creation/update behavior and ledger updates.

---

## Known Limitations

- The audit trail stores comments in GitHub only; dashboards and external log
  sinks are out of scope.
- The audit helper records decisions; it does not grant merge authority.
