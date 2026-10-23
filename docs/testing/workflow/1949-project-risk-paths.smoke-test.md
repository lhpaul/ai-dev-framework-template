# Smoke Test Runbook: Project Risk Paths

**Feature**: Optional project path-risk categories with immutable sensitive floors.
**Spec**: [Project Risk Paths](../../specs/developments/20261015110303_1949-project-risk-paths/1_1949-project-risk-paths_specs.md)
**Created in**: Plan Ready stage.

## Prerequisites

- Bash, Python 3, jq and ShellCheck are available; framework configuration parsing
  uses the dependency-free strict reader, without PyYAML.
- Use the implementation checkout with a clean tracked tree. Tests create their
  own temporary config/evidence fixtures; no credentials or API writes needed.
- No UI, database seed, user session or design assets apply.

## Test Data

Use the deterministic fixtures in the helper and classifier suites named below.
They include the incident docs path, real release tooling, nested sensitive
paths, conflicting rules, invalid maps and hub/product identity cases.

## Smoke Test Steps

### Step 1: Exercise the configuration and matching contract

**Maps to**: AC4–AC7, AC10.

Run `bash scripts/development-workflow/tests/test-workflow-risk-paths.sh`.
Expect valid absent/empty maps, order-independent matching and project isolation
to pass; malformed maps and ambiguous targets must be rejected with diagnostics.
Check that invalid-config diagnostics do not echo secret-shaped fixture values.

### Step 2: Reproduce the incident and enforce floors

**Maps to**: AC1–AC9, AC12.

Run `bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh`.
Confirm the incident path is Low without another signal, ordinary overrides
apply, sensitive/tooling floors stay High, and mixed paths aggregate by highest
risk in either order. Empty changed-file evidence must retain High and preserve
the existing Low/High ceiling behavior.

Record the planted-violation pair from the plan: the Low-ceiling permission
assertion fails for the sensitive fixture and passes after the path is changed
to the ordinary fixture. Include concrete fixture file/line locators in the log.

### Step 3: Verify composed gates and shipped guidance

**Maps to**: AC10–AC12.

Run `bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
and `bash scripts/development-workflow/tests/test-status-check-rollup-dedupe.sh`.
Confirm existing reviewer/CI/checkpoint/budget blockers still deny merge.
Inspect the helper's covers header and selected-suite output; ensure the new
suite is selected when the helper changes. Run the repository sync-coverage
check for the added helper and verify the commented configuration example is
not an active Low-risk override for this template.

## Assertions Checklist

- [ ] Docs release-word incident is corrected and actual tooling stays protected.
- [ ] Project matching, overlap and all sensitive floors match the spec.
- [ ] Invalid configuration fails; missing changed-file evidence preserves compatibility.
- [ ] Composed authorization gates and max-risk ceilings remain enforced.
- [ ] Guidance, test selection, sync ownership and slugged fragment are present.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Missing Python 3 | Use the repository's workflow tooling setup, then retry; framework parsing needs no PyYAML |
| Invalid configuration | Repair the indicated rule/field using shipped grammar |
| Scope, reviewer or CI gate fails | Stop readiness and follow that gate; do not change risk ceilings |

## Known Limitations

This is path-based classification. It does not inspect store-submission state
inside file contents or grant permission to merge the implementation PR.
