# Smoke Test Runbook: Sync-Template Workflow-Hub Scopes

**Feature**: Sync-template workflow-hub scopes
**Spec**: [1_881-sync-template-workflow-hub-scopes_specs.md](../../specs/developments/20260611200820_881-sync-template-workflow-hub-scopes/1_881-sync-template-workflow-hub-scopes_specs.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #881.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.
- [ ] No private product repositories or live GitHub App credentials are needed
      for the default smoke path.

---

## Test Data

| Item | Value |
| --- | --- |
| Sync manifest | `sync-manifest.yaml` |
| Expected focused test | `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` |
| Workflow-hub fixture harness | `scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh` |
| Repository mode docs | `docs/workflow/development-workflow/repository-modes.md` |

---

## Smoke Test Steps

### Step 1: Verify Single-Repository Compatibility

**Maps to**: AC4

1. Run the focused sync-template scope test.
2. Inspect the single-repository section.
3. Confirm missing mode or explicit `single_repo` keeps the compatibility file
   selection and does not drop entries solely because of `mode_scope`.

**Expected result**: Single-repository output remains the compatibility baseline.

### Step 2: Verify Workflow-Hub Selection

**Maps to**: AC1, AC5

1. Inspect the workflow-hub section of the test output.
2. Confirm the selected set includes shared and hub-only entries.
3. Confirm product-repo-injection entries appear in skipped output.
4. Confirm selected and skipped counts are visible.

**Expected result**: Workflow hubs receive hub-owned framework files and explain
why product-only entries were skipped.

### Step 3: Verify Product-Repository Selection

**Maps to**: AC2, AC3, AC5, AC9

1. Inspect the product-repository section of the test output.
2. Confirm the selected set includes shared and product-repo-injection entries.
3. Confirm hub-only tracker, spec, plan, protocol, and orchestration entries are
   skipped.
4. Confirm the test uses local fixture data only.

**Expected result**: Product repositories receive only injection-safe files and
do not need private hub access for dry-run verification.

### Step 4: Verify Divergent Local Change Reporting

**Maps to**: AC6

1. Run the implementation's dry-run or fixture scenario with a selected file
   that differs locally.
2. Confirm the output reports the divergent file before any apply step.
3. Confirm skipped role-inapplicable files are not reported as overwrite
   candidates.

**Expected result**: Maintainers see selected-file divergence before mutation.

### Step 5: Verify Fail-Closed Manifest Handling

**Maps to**: AC7

1. Run the focused test cases for unknown role and unknown `mode_scope`.
2. Confirm both fail before file changes are applied.
3. Confirm the error names the invalid role or scope.

**Expected result**: Unsupported manifest role metadata cannot silently produce a
partial sync.

### Step 6: Run Automated Validation

**Maps to**: AC1 through AC9

Run:

```bash
bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh
bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
```

Then run shell, Python, markdown, and changelog validation from the
implementation plan.

**Expected result**: All default non-secret tests pass.

---

## Assertions Checklist

- [ ] AC1: Workflow-hub mode selects hub-owned and shared files.
- [ ] AC2: Product-repository mode selects product-repo-injection and shared
      files.
- [ ] AC3: Product-repository mode excludes hub-owned workflow state.
- [ ] AC4: Single-repository mode keeps compatibility behavior.
- [ ] AC5: Skipped files are visible by mode scope.
- [ ] AC6: Divergent selected-file changes are reported before overwrite.
- [ ] AC7: Unknown mode scopes fail closed.
- [ ] AC8: Hub and product repository modes produce different file sets.
- [ ] AC9: Default product-repository validation is non-secret.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Product repo output includes hub protocols | Mode-scope filter is not applied before file comparison | Reuse the shared role-selection helper for dry-run and apply. |
| Single-repo output is unexpectedly small | Compatibility mode is filtering by scope | Restore single-repo compatibility selection and rerun tests. |
| Unknown scope is skipped silently | Manifest validation is fail-open | Fail closed before file mutation and add a regression assertion. |
| Dry-run and apply summaries differ | Selection logic is duplicated | Centralize selection or add parity tests. |
