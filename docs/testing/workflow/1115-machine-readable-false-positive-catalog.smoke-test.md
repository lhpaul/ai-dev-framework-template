# Smoke Test Runbook: Machine-readable False-positive Catalog

**Feature**: Machine-readable false-positive catalog
**Spec**: [Machine-readable False-positive Catalog Spec](../../specs/developments/20260702105007_1115-machine-readable-false-positive-catalog/1_1115-machine-readable-false-positive-catalog_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for #1115.
- [ ] `jq`, `bash`, `shellcheck`, `python3`, and Node dependencies for
      `markdownlint-cli2` are available.
- [ ] The branch includes the catalog file and implementation changes from the
      #1115 plan.

## Test Data

| Item | Value |
| --- | --- |
| Catalog file | `scripts/development-workflow/haystack-false-positives.json` |
| Haystack reviewer harness | `scripts/development-workflow/tests/test-haystack-reviewer.sh` |
| Reviewer-loop harness | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Known false-positive disposition | `known-false-positive` |

## Smoke Test Steps

### Step 1: Validate catalog shape

**Maps to**: AC-1

1. Run:

   ```bash
   jq -e 'type == "array" and all(.[]; has("id") and has("category") and has("rationale"))' scripts/development-workflow/haystack-false-positives.json
   ```

2. Confirm the command exits successfully.
3. Confirm the catalog includes rules for CHANGELOG, hotfix backport, and
   mirror-guidance known false positives.

**Expected result**: The catalog is valid JSON and exposes the maintained
machine-readable rule set.

### Step 2: Run Haystack reviewer unit coverage

**Maps to**: AC-2, AC-3, AC-4, AC-5, AC-7

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-haystack-reviewer.sh
   ```

2. Confirm the output reports zero failures.
3. Confirm the named tests cover:
   - CHANGELOG known false-positive classification.
   - Hotfix-backport known false-positive classification.
   - Mirror-guidance known false-positive classification.
   - Negative lookalike findings.
   - Unknown-category safe-fail.
   - Multiple independent findings.
   - Malformed catalog override behavior.

**Expected result**: Matching findings are marked
`known-false-positive`, non-matching findings keep their normal classification,
and unknown categories remain blocking unless explicitly cataloged.

### Step 3: Verify reviewer-loop summary rendering

**Maps to**: AC-2, AC-6

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Confirm the output reports zero failures.
3. Confirm the summary-rendering tests include a structured advisory with
   `disposition=known-false-positive`.

**Expected result**: Reviewer-loop summaries show the known false-positive
disposition without hiding the original finding context.

### Step 4: Run shell and workflow lint

**Maps to**: AC-2, AC-4

1. Run:

   ```bash
   shellcheck --severity=warning -x scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-haystack-reviewer.sh scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Run:

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
   ```

**Expected result**: Both lint commands pass.

### Step 5: Verify documentation and changelog quality

**Maps to**: AC-6

1. Run:

   ```bash
   npx markdownlint-cli2 "docs/workflow/development-workflow/integrations/haystack-triage.md" "docs/testing/workflow/1115-machine-readable-false-positive-catalog.smoke-test.md" "CHANGELOG.md"
   ```

2. Run:

   ```bash
   python3 scripts/lint/markdown-heuristic-lint.py docs/workflow/development-workflow/integrations/haystack-triage.md docs/testing/workflow/1115-machine-readable-false-positive-catalog.smoke-test.md CHANGELOG.md
   ```

3. Run:

   ```bash
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

**Expected result**: Documentation and CHANGELOG checks pass.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Run `git diff --check`.

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: The catalog exists and validates as machine-readable JSON with
      stable rule metadata.
- [ ] AC-2: Matching Haystack findings include a `known-false-positive`
      disposition while preserving original finding context.
- [ ] AC-3: Matched known false positives remain non-blocking unless another
      gate requires escalation.
- [ ] AC-4: Non-matching findings keep their normal reviewer classification.
- [ ] AC-5: Multiple findings are evaluated independently.
- [ ] AC-6: Documentation explains the catalog format and Helm relationship.
- [ ] AC-7: Tests cover CHANGELOG and hotfix-backport known false-positive
      patterns.

## Seed Data Reference

The following seed data is embedded in shell test fixtures:

| Entity | Scenario | How to load |
| --- | --- | --- |
| Mock Haystack output | CHANGELOG, hotfix-backport, mirror guidance, unrelated advisory, unknown category | Run `test-haystack-reviewer.sh` |
| Catalog override file | Malformed catalog behavior | Created by `test-haystack-reviewer.sh` in a temporary directory |
| Structured advisory summary | Known false-positive rendering | Run `test-pr-review-loop.sh` |

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Catalog validation fails | JSON syntax error or missing required rule fields | Fix `haystack-false-positives.json` and rerun Step 1. |
| Known false-positive tests fail | Rule regex is too narrow or field mapping changed | Inspect the failing fixture and adjust the rule or matching helper. |
| Unknown category no longer blocks | Catalog matching is overriding safe-fail too broadly | Restrict rules by category and rerun parser-risk tests. |
| Summary test fails | `pr-review-loop.sh` renderer is not displaying disposition fields | Update `render_structured_advisory_entries` and rerun Step 3. |

## Known Limitations

- The smoke test uses deterministic shell fixtures rather than the live Haystack
  service. This is intentional so known false-positive behavior is reproducible
  without external service timing or authentication.
