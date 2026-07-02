# Smoke Test Runbook: Actions Cost-Audit Guidance

**Feature**: Actions cost-audit guidance
**Spec**: [1_1099-actions-cost-audit-guidance_specs.md](../../specs/developments/20260701091532_1099-actions-cost-audit-guidance/1_1099-actions-cost-audit-guidance_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in the repository root.
- [ ] The implementation branch for #1099 is checked out.
- [ ] `gh` is authenticated when running the optional live smoke step.
- [ ] `jq`, `shellcheck`, and the repository markdown lint tooling are available.

---

## Test Data

No application seed data is required.

| Item | Value |
| --- | --- |
| Audit helper | `scripts/development-workflow/actions-cost-audit.sh` |
| Focused test | `scripts/development-workflow/tests/test-actions-cost-audit.sh` |
| Integration guide | `docs/workflow/development-workflow/integrations/actions-cost-audit.md` |
| Recommendation outcomes | `keep`, `narrow`, `make opt-in`, `replace`, `disable`, `investigate` |

---

## Smoke Test Steps

### Step 1: Run Focused Static Tests

**Maps to**: AC1, AC2, AC3, AC4, AC6, AC7, AC8

1. Run `bash scripts/development-workflow/tests/test-actions-cost-audit.sh`.
2. Confirm the test output reports success.

**Expected result**: Mocked `gh` fixtures validate aggregation by workflow,
duration handling, incomplete data visibility, empty data handling,
permission-failure handling, recommendation outcomes, and public/private
cost-risk framing.

### Step 2: Run Shell Quality Checks

**Maps to**: AC3, AC8

1. Run:
   `shellcheck --severity=warning scripts/development-workflow/actions-cost-audit.sh scripts/development-workflow/tests/test-actions-cost-audit.sh`.
2. Run:
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.

**Expected result**: ShellCheck and the workflow shell guard pass without new
warnings.

### Step 3: Validate Documentation and Output Contract

**Maps to**: AC4, AC5, AC6, AC7, AC8

1. Open `docs/workflow/development-workflow/integrations/actions-cost-audit.md`.
2. Confirm it explains public-template zero-billable standard-runner assumptions
   separately from private downstream runner-minute risk.
3. Confirm it states that the helper reports wall time, not exact dollars.
4. Confirm it describes when to keep high-signal workflows despite cost.
5. Confirm it documents all recommendation outcomes:
   `keep`, `narrow`, `make opt-in`, `replace`, `disable`, and `investigate`.
6. Confirm the example output is compact enough to paste into a retrospective or
   template-sync review.

**Expected result**: Maintainers can use the guide without billing-admin access
and can copy the recommendation format into review notes.

### Step 4: Run Markdown Validation

**Maps to**: AC7, AC8

1. Run markdown lint on the changed docs and this runbook.
2. Run the repository heuristic markdown lint command against workflow docs,
   testing docs, and `CHANGELOG.md`.

**Expected result**: Markdown lint and heuristic lint pass.

### Step 5: Run Optional Live Audit

**Maps to**: AC1, AC2, AC3, AC7

1. Run `./scripts/development-workflow/actions-cost-audit.sh --limit 10`.
2. Confirm the command exits successfully.
3. Confirm the output groups recent runs by workflow.
4. Confirm total or average wall-time signals are present when timestamp data is
   available.
5. Confirm any unavailable or incomplete data is called out explicitly.

**Expected result**: A maintainer with normal repository workflow-run
visibility can generate a useful audit summary without billing-admin access.

---

## Assertions Checklist

- [ ] AC1: Maintainers can inspect recent workflow run counts by workflow using
      normal repository workflow-run visibility.
- [ ] AC2: Maintainers can inspect recent workflow wall time or an equivalent
      duration signal by workflow.
- [ ] AC3: The audit output identifies unavailable, incomplete, or
      permission-limited workflow run data.
- [ ] AC4: Guidance distinguishes public-repository zero-billable template runs
      from private downstream runner-minute cost risk.
- [ ] AC5: Guidance explains when to keep workflows despite cost, including
      high-signal checks, release gates, and real regression or deployment jobs.
- [ ] AC6: Guidance supports `keep`, `narrow`, `make opt-in`, `replace`,
      `disable`, and `investigate`.
- [ ] AC7: Output is suitable for retrospectives or template-sync reviews,
      including compact summary and decision rationale.
- [ ] AC8: Tests or static validation cover the output structure and
      public-vs-private cost-risk framing.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `gh` reports authentication or permission failure | The current account cannot read workflow runs for the repository | Authenticate with `gh auth login` or rerun against a repository where the account has Actions read visibility. |
| Live audit shows no workflow runs | The repository has no recent runs in the inspected limit or date range | Increase `--limit`, remove `--since`, or confirm Actions are enabled for the repository. |
| Duration totals are lower than expected | Some runs are missing start or end timestamps | Check the data-limitation notes and inspect recent run IDs directly with `gh run view`. |
| Shell tests fail while live audit works | Mock fixture or output contract drifted during implementation | Update the focused test to match the intended stable output headings and rerun it. |

---

## Known Limitations

- The audit reports workflow-run wall time, not exact billable minutes or dollar
  cost.
- The live smoke step depends on current GitHub CLI authentication and
  repository Actions visibility.
