# Smoke Test Runbook: Advisory Disposition Triggers

**Feature**: Advisory disposition triggers
**Spec**: [Advisory Disposition Triggers](../../specs/developments/20260702095847_1114-advisory-disposition-triggers/1_1114-advisory-disposition-triggers_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on a branch that includes the #1114 implementation.
- [ ] `jq`, `gh`, and the repository shell test prerequisites are available.
- [ ] The repository has a test or fixture path that can run the reviewer loop
      without requiring a live Haystack service response.

## Test Data

| Item | Value |
| ---- | ----- |
| Haystack advisory summary | `Summary with "quotes", pipe | equals =, and newline text` |
| Haystack advisory category | `Minor` |
| Policy-required signal | Reviewer output indicates policy review is required with no blocking findings |
| PR-Agent advisory label | `Possible Issue` |

## Smoke Test Steps

### Step 1: Haystack advisory count triggers disposition

**Maps to**: AC-1, AC-4, AC-6, AC-7

1. Run the reviewer-loop harness or smoke fixture that simulates a Haystack-only
   clean review with one structured advisory finding.
2. Verify the reviewer-loop output remains clean and reports zero blocking
   findings.
3. Verify the output includes `ADVISORY_DISPOSITION_REQUIRED=1`.
4. Verify the Automated Reviewer Loop Summary lists the Haystack advisory
   category and summary.

**Expected result**: The pull request remains non-blocked, but readiness evidence
requires advisory disposition.

### Step 2: Haystack advisory details are visible

**Maps to**: AC-4, AC-5

1. Use a fixture advisory with category, summary, detail, optional path, line,
   and fix hint.
2. Run the reviewer-loop summary rendering path.
3. Verify the summary includes the advisory category and summary.
4. Verify available detail, source location, and fix hint are visible or
   omitted only when the fixture omits them.

**Expected result**: A human can decide whether to fix, accept, defer, or
escalate the advisory without manually rerunning Haystack for basic context.

### Step 3: Policy-review-required clean result triggers disposition

**Maps to**: AC-2, AC-6

1. Run a fixture where the review result is clean, blocking count is zero, and
   policy review is required.
2. Verify the reviewer-loop output reports `ADVISORY_DISPOSITION_REQUIRED=1`.
3. Verify the summary includes a policy acknowledgement or policy advisory entry.

**Expected result**: Policy-required evidence cannot disappear into a generic
clean result.

### Step 4: PR-Agent advisory labels still trigger disposition

**Maps to**: AC-3, AC-5

1. Run or inspect the fixture that simulates a clean PR-Agent result with an
   advisory label.
2. Verify the existing advisory-label summary entry is still present.
3. Verify `ADVISORY_DISPOSITION_REQUIRED=1` applies to the label.

**Expected result**: Existing PR-Agent advisory behavior is preserved.

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary fixture PRs, comments, or local test files created during
  manual smoke testing.

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Clean output with advisory count greater than zero emits
      `ADVISORY_DISPOSITION_REQUIRED=1` before readiness is complete.
- [ ] AC-2: Clean output with policy review required emits
      `ADVISORY_DISPOSITION_REQUIRED=1` before readiness is complete.
- [ ] AC-3: Existing advisory-label disposition behavior still runs.
- [ ] AC-4: Haystack structured advisory details are listed in the reviewer-loop
      summary.
- [ ] AC-5: Every summary advisory can receive a fixed, accepted, deferred, or
      escalated disposition.
- [ ] AC-6: Advisory-only Haystack results remain non-blocking after
      dispositions are recorded.
- [ ] AC-7: The Haystack-only clean-with-advisories path is covered by a smoke
      or harness scenario.

## Seed Data Reference

No persistent seed data is required. Use mocked reviewer-loop platform output or
temporary smoke fixtures.

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Summary shows only an advisory count | Structured Haystack advisory output was not forwarded or parsed | Inspect reviewer-loop platform output for `ADVISORY_FINDINGS_JSON`. |
| Disposition-required signal is missing | Aggregation did not account for advisory count, policy review, or advisory labels | Check the platform output fields used by the aggregation step. |
| Summary Markdown is malformed | Advisory text contains special characters that were not escaped or rendered safely | Re-run special-character fixture and inspect the generated summary body. |

## Known Limitations

- This smoke runbook verifies workflow behavior with mocked or fixture reviewer
  output; it does not require a live Haystack service response.
