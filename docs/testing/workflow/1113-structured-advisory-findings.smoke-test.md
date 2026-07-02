# Smoke Test Runbook: Structured Haystack Advisory Findings

**Feature**: Structured Haystack Advisory Findings
**Spec**: [Structured Haystack Advisory Findings](../../specs/developments/20260702083004_1113-structured-advisory-findings/1_1113-structured-advisory-findings_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for issue #1113 is checked out.
- [ ] `jq` is available on `PATH`.
- [ ] No real Haystack credentials are required; the committed unit harness uses
      mocked Haystack responses.

---

## Test Data

| Item | Value |
| ---- | ----- |
| Test harness | `scripts/development-workflow/tests/test-haystack-reviewer.sh` |
| Reviewer wrapper | `scripts/development-workflow/haystack-reviewer.sh` |
| Documentation | `docs/workflow/development-workflow/integrations/haystack-triage.md` |
| Mock PR number | `123` in the test harness |

---

## Smoke Test Steps

### Step 1: Run Haystack Reviewer Unit Harness

**Maps to**: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-haystack-reviewer.sh
   ```

2. Verify the harness reports passing structured-finding cases for:
   - multiple advisory findings,
   - mixed blocking and advisory findings,
   - optional source fields,
   - escaped text values,
   - missing or unknown categories,
   - `Major` category policy behavior.

**Expected result**: The harness exits `0`, and no structured-finding case
fails.

### Step 2: Verify Structured Output Remains Machine-Readable

**Maps to**: AC-1, AC-2, AC-3, AC-4

1. Inspect the test output or the harness assertions for
   `ADVISORY_FINDINGS_JSON=` and `BLOCKING_FINDINGS_JSON=`.
2. Confirm each emitted value is parsed with `jq` by the test harness.
3. Confirm the existing count assertions still pass.

**Expected result**: Structured arrays are valid JSON, and the existing result
and count fields still match the same payload.

### Step 3: Verify Documentation Contract

**Maps to**: AC-7

1. Open `docs/workflow/development-workflow/integrations/haystack-triage.md`.
2. Confirm it includes a structured finding output section with:
   - required fields,
   - optional fields,
   - example key-value output,
   - compatibility notes for existing count fields,
   - a note that PR summary consumption is handled by follow-up issue #1114.

**Expected result**: A workflow maintainer can implement a downstream consumer
from the documented contract without reading `haystack-reviewer.sh`.

### Step 4: Run Markdown Lint

**Maps to**: AC-7

1. Run:

   ```bash
   npx markdownlint-cli2 \
     "docs/workflow/development-workflow/integrations/haystack-triage.md" \
     "docs/testing/workflow/1113-structured-advisory-findings.smoke-test.md"
   ```

**Expected result**: Markdown lint exits `0`.

---

## Assertions Checklist

- [ ] AC-1: Multiple advisory findings produce one structured advisory entry per
      finding.
- [ ] AC-2: Each advisory entry includes required fields and preserves optional
      location or fix guidance when present.
- [ ] AC-3: Blocking findings use the same structured finding shape.
- [ ] AC-4: Existing result and count fields remain available and accurate.
- [ ] AC-5: Advisory-only results remain non-blocking.
- [ ] AC-6: Focused unit tests cover multi-advisory structured output.
- [ ] AC-7: The Haystack triage guide documents the structured finding
      contract.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| ------ | -------- | ----------- |
| Mock Haystack payload | Advisory, blocking, mixed, and malformed finding data | Built into `test-haystack-reviewer.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `jq` parse assertion fails | Structured output is not compact valid JSON | Build arrays with `jq -c` and parse the value after the first `=`. |
| Advisory-only result becomes blocking | Classification and structured-array logic diverged | Reuse the same category classification for counts and arrays. |
| Optional source test fails | The normalizer assumes a source shape Haystack did not guarantee | Omit unknown optional fields instead of failing. |

---

## Known Limitations

- This runbook verifies the Haystack reviewer contract only. Rendering the
  structured advisories in `pr-review-loop.sh` summaries is covered by follow-up
  issue #1114.
