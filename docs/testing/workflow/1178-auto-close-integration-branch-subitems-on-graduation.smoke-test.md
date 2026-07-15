# Smoke Test Runbook: Auto-Close Integration-Branch Sub-Items on Graduation

**Feature**: Auto-close integration-branch sub-items on graduation (issue #1178)
**Spec**: [docs/specs/developments/20260714164810_1178-auto-close-integration-branch-subitems-on-graduation/1_1178-auto-close-integration-branch-subitems-on-graduation_specs.md](../../specs/developments/20260714164810_1178-auto-close-integration-branch-subitems-on-graduation/1_1178-auto-close-integration-branch-subitems-on-graduation_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch has the graduation closeout helper and Protocol
      05b updates.
- [ ] `gh` CLI is authenticated if running against a live repository, or the
      committed unit-test fixture mocks are available.
- [ ] You have an integration branch slug such as `test-graduation-closeout`.
- [ ] The configured GitHub Projects terminal status exists. For the template
      default this is `Merged`; downstream repositories can set
      `GITHUB_PROJECT_STATUS_GRADUATED` to `Done` or `Released` when that is
      their terminal delivery status.

---

## Test Data

| Item | Value |
| ---- | ----- |
| Integration branch slug | `test-graduation-closeout` |
| Integration branch name | `develop-test-graduation-closeout` |
| Graduation PR | A merged PR from `develop-test-graduation-closeout` to `develop` |
| Parent epic | A GitHub issue with native sub-issues or child issues labeled `integration-branch:test-graduation-closeout` |
| Delivered sub-item A | Open issue with a merged implementation PR targeting `develop-test-graduation-closeout` |
| Delivered sub-item B | Closed issue whose project status is not terminal |
| Delivered sub-item C | Closed issue whose project status is already terminal |
| Optional sub-item | Open issue labeled or explicitly passed as optional/deferred/excluded |
| Parser fixture PR | Merged sub-item PR whose title/body includes closing keyword refs such as `Closes #<issue>` |

---

## Smoke Test Steps

### Step 1: Verify Protocol 05b Closeout Sweep

**Maps to**: AC1, AC2, AC4, AC6, AC10

1. Open `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
2. Locate Step 5 (Post-Merge Cleanup).
3. Confirm Step 5 instructs the operator to run the graduation closeout helper
   after the graduation PR merges.
4. Confirm the documented command includes `--slug`, `--graduation-pr`, and
   `--epic`, with optional `--exclude-issue` and `--defer-epic-close` handling.
5. Confirm the step says the helper identifies the parent epic and planned
   sub-items from native sub-issues or the `integration-branch:<slug>` label,
   and includes issues referenced by merged sub-item PR closing keywords when
   available.
6. Confirm the step says delivered open sub-items are closed and moved to the
   configured terminal status before the parent epic is closed.

**Expected result**: Protocol 05b documents an explicit closeout mechanism and no
longer relies on GitHub default-branch auto-close behavior.

### Step 2: Verify Terminal Status Resolution

**Maps to**: AC2, AC3, AC3a, AC8

1. Inspect the implementation helper or its tests.
2. Confirm terminal status is configurable, with the template default resolving
   to `Merged` unless `GITHUB_PROJECT_STATUS_GRADUATED` or
   `GITHUB_PROJECT_STATUS_MERGED` overrides it.
3. Confirm an open delivered sub-item is closed and has terminal project status
   reasserted after issue closure.
4. Confirm a closed but non-terminal sub-item receives only the project status
   update.
5. Confirm a closed and terminal sub-item is reported as already terminal and is
   not moved backward.

**Expected result**: Delivered sub-items end in terminal issue state and terminal
project status, while already-terminal items remain stable.

### Step 3: Verify Optional and Deferred Item Handling

**Maps to**: AC5, AC6

1. Prepare or inspect a fixture with an open optional/deferred/excluded sub-item.
2. Run the helper in fixture mode or inspect the unit-test output.
3. Confirm the optional item remains open.
4. Confirm the closeout summary lists it under `skipped_optional` or equivalent
   wording with a human follow-up action.

**Expected result**: Optional, deferred, cancelled, or explicitly excluded
sub-items are never silently closed.

### Step 4: Verify Partial Failure and Rerun Behavior

**Maps to**: AC6, AC7, AC8

1. Run the helper test fixture where one issue closure or project status update
   fails.
2. Confirm other delivered sub-items are still processed successfully.
3. Confirm the failed item is listed separately with enough context for manual
   repair or retry.
4. Rerun the helper or inspect the rerun fixture.
5. Confirm previously reconciled items are reported as already terminal and only
   still-non-terminal items are retried.

**Expected result**: The closeout is repeatable and partial failures are visible
without undoing successful work.

### Step 5: Verify Closing Keyword Reference Coverage

**Maps to**: AC1, AC10

1. Run `bash scripts/development-workflow/tests/test-graduation-closeout.sh`.
2. Confirm the parser-risk tests cover closing keyword variants, negative
   lookalikes, multiple refs on one line, duplicate refs, optional `issue`
   wording, cross-repo refs ignored, and markdown punctuation boundaries.
3. Confirm only current-repository plain `#<number>` closing refs are included
   in the closeout candidate set.
4. Confirm the mocked closeout test reports `53 passed, 0 failed`.

**Expected result**: Issues referenced by merged sub-item PR closing keywords are
included when available, and non-closing references do not trigger mutation.

### Step 6: Verify Portfolio Scan Visibility Outcome

**Maps to**: AC9

1. After a successful closeout in a live or fixture-backed run, inspect delivered
   planned sub-items.
2. Confirm each delivered sub-item is closed and has terminal project status.
3. Run the relevant portfolio scan or inspect the scan fixture output.
4. Confirm delivered planned sub-items no longer appear as open actionable work.
5. Confirm intentionally open optional or deferred follow-up items remain visible
   with their skip/disposition context.

**Expected result**: Future planning queries do not show phantom open delivered
work after graduation.

### Last Step: Validate and Close

- Verify all assertions in the checklist below are met.
- Shut down any temporary fixture repository, mocks, or local test processes.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: Graduation closeout identifies the parent epic and all planned
      delivered sub-items, including available closing-keyword references from
      sub-item PRs merged into the integration branch.
- [ ] AC2: Open planned delivered sub-items are closed and moved to the
      configured terminal delivery status.
- [ ] AC3: Already closed and terminal delivered sub-items are reported as
      already terminal and not moved backward.
- [ ] AC3a: Closed but non-terminal delivered sub-items receive the terminal
      project status update.
- [ ] AC4: The parent epic closes and receives terminal project status only after
      delivered planned sub-items reconcile, unless the operator defers closure.
- [ ] AC5: Optional, deferred, cancelled, or explicitly excluded sub-items remain
      open unless the operator chooses a terminal disposition.
- [ ] AC6: The closeout summary separates closed, already terminal, skipped, and
      failed items.
- [ ] AC7: One item failure does not prevent successful reconciliation of other
      items.
- [ ] AC8: Rerunning closeout reconciles only still-non-terminal items and treats
      fully reconciled items as already terminal.
- [ ] AC9: A portfolio scan after successful closeout does not return delivered
      planned sub-items as open actionable work.
- [ ] AC10: The accepted implementation documents the explicit post-merge sweep
      mechanism and does not rely solely on GitHub default-branch auto-close.

---

## Seed Data Reference

No application seed data is required. Use mocked `gh`/GraphQL fixtures in the
committed shell tests, or a disposable GitHub repository with the issue/PR
states listed in Test Data.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Closeout cannot resolve terminal status | The configured status option does not exist on the Project board | Set `GITHUB_PROJECT_STATUS_GRADUATED` to an existing terminal option or add the option to the board |
| Optional item was included in delivered set | Missing optional/deferred/excluded label or missing explicit exclusion flag | Add the skip signal and rerun closeout before closing the item |
| Parser test closes a non-closing reference | Closing keyword regex overmatched a lookalike | Tighten keyword boundaries and rerun `test-graduation-closeout.sh` |
| Epic closure is skipped | One or more delivered sub-items failed closeout, or `--defer-epic-close` was set | Repair failed items or rerun without the deferral once children are reconciled |

---

## Known Limitations

- The smoke test can run fully in mocked fixtures. A live end-to-end run requires
  a disposable or real integration-branch epic with merged sub-item PRs.
- Cross-repository closing references are out of scope for the MVP and should be
  reported for human follow-up rather than mutated automatically.
