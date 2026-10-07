# Smoke Test Runbook: Pipefail-safe test assertions

**Feature**: #1877
**Spec**: [Approved spec](../../specs/developments/20261006223254_1877-pipefail-safe-tests/1_1877-pipefail-safe-tests_specs.md)
**Created in**: Plan Ready stage

## Prerequisites and Test Data

Use the implementation branch, Bash 3.2 or newer, Python 3, jq and ShellCheck.
The committed shell harnesses create temporary fixtures. No application login,
database, external account or product seed is needed.

## Step 1: Stable text matching

**Maps to**: AC1, AC4; spec Use Case 1.

Run the help regression suite and inspect its matching/absent-text large-output
assertions and pass/fail totals:

<!-- workflow-shell-contract: bash -->
```bash
bash scripts/development-workflow/tests/test-pr-review-loop-pr-agent-coderabbit.sh
```

Expected: the early match succeeds with at least 1 MiB of trailing data, and the
absent token is rejected; existing help assertions still pass.

## Step 2: Recurrence validation

**Maps to**: AC3, AC5; spec Use Case 2.

<!-- workflow-shell-contract: bash -->
```bash
bash scripts/lint/tests/test-workflow-shell-guard-lint.sh
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
```

Expected: the unit suite explicitly demonstrates unsafe/safe pairs, options,
continuations, fixtures and diagnostic locations; the implementation diff passes.
The PR proof record must identify an actual planted file and line, the failing
exit 1 diagnostic and the corrected passing exit 0.

## Step 3: Pattern completeness and regression

**Maps to**: AC2, AC4.

Rerun the implementation plan's candidate query across the shell-test tree.
Inspect any remaining candidates, including multiline and long-option variants.
Confirm every executable affected assertion has been corrected, and record
intentional data or out-of-scope groups explicitly. Run the affected suite list
and inspect its assertion totals. Run scope-residual-gate.sh with that evidence.

Expected: no untreated executable test assertion; residual gate passes; affected
suites, Bash syntax, ShellCheck and git diff --check pass.

## Completion Checklist

- [ ] Large-output match and absent-token tests pass.
- [ ] Lint has demonstrated failing/passing planted-violation proof.
- [ ] Test-tree residuals are audited and the scope gate passes.
- [ ] Changed suites and supported shell checks pass.

No server or persistent test data was started; no shutdown step is needed.
