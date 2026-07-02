# Smoke Test Runbook: Unified Advisory Contract

**Feature**: Unified advisory contract
**Spec**: [1_1118-unify-advisory-contract_specs.md](../../specs/developments/20260702123855_1118-unify-advisory-contract/1_1118-unify-advisory-contract_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for issue #1118.
- [ ] `jq`, `gh`, and shell test dependencies used by the existing workflow
      test scripts are available.
- [ ] The implementation PR has been pushed so the reviewer-loop command can
      run against a real pull request if manual end-to-end validation is needed.

---

## Test Data

| Item | Value |
| ---- | ----- |
| PR-Agent advisory fixture | Mock output with at least two advisory labels and one comment URL. |
| Haystack advisory fixture | Mock completed review with advisory findings containing category, summary, detail, location, fix hint, and known false-positive disposition metadata. |
| Mixed-platform fixture | One PR-Agent advisory plus one Haystack advisory in the same aggregate loop run. |

---

## Smoke Test Steps

### Step 1: Verify PR-Agent Unified Advisory Output

**Maps to**: AC-2, AC-4, AC-7

1. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh`.
2. Locate the PR-Agent advisory normalization tests in the output.
3. Confirm advisory labels are still available through `ADVISORY_LABELS`.
4. Confirm the same advisories are represented in `ADVISORY_FINDINGS`.

**Expected result**: The shell test passes and shows that PR-Agent advisory-only
findings remain non-blocking while emitting the unified advisory list.

### Step 2: Verify Haystack Unified Advisory Output

**Maps to**: AC-3, AC-7

1. Run `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`.
2. Confirm completed Haystack advisory reviews emit `ADVISORY_FINDINGS`.
3. Confirm the transition alias `ADVISORY_FINDINGS_JSON` is still emitted.
4. Confirm both JSON arrays preserve category, summary, detail, location, fix
   hint, and known false-positive disposition metadata when present.

**Expected result**: The shell test passes and both fields contain equivalent
compact JSON arrays for completed Haystack review paths.

### Step 3: Verify Mixed-platform Aggregation

**Maps to**: AC-4, AC-5

1. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh`.
2. Confirm the mixed-platform aggregation test reports a single aggregate
   `ADVISORY_FINDINGS` array.
3. Confirm the aggregate array includes entries from `pr-agent` and `haystack`.
4. Confirm the reviewer summary renders one advisory section without duplicating
   legacy alias rows.
5. Confirm `ADVISORY_DISPOSITION_REQUIRED=1` when the aggregate list is
   non-empty and the aggregate result is clean.

**Expected result**: Advisory disposition can be derived from the unified list
without reading provider-specific aliases.

### Step 4: Verify Documentation Contract

**Maps to**: AC-1, AC-6

1. Read `docs/workflow/development-workflow/integrations/pr-review-platform.md`.
2. Confirm it defines the canonical `ADVISORY_FINDINGS` JSON array contract,
   required fields, optional fields, and transition aliases.
3. Read `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
4. Confirm Protocol 93 references the unified contract for advisory discovery,
   summary rendering, and disposition handling.

**Expected result**: Maintainers can implement a new review platform by emitting
one documented advisory field instead of provider-specific advisory signals.

### Last Step: Validate & Shut Down

1. Run the full verification command list from the implementation plan.
2. Confirm all commands pass.
3. Record any skipped manual end-to-end validation with a reason in the PR.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Generic review-platform docs define `ADVISORY_FINDINGS` with
      required and optional fields.
- [ ] AC-2: PR-Agent emits the unified contract and keeps `ADVISORY_LABELS` as
      a deprecated transition alias.
- [ ] AC-3: Haystack emits the unified contract without losing structured
      advisory or known false-positive metadata.
- [ ] AC-4: `pr-review-loop.sh` aggregates advisories from all configured
      platforms into the summary comment using the unified contract.
- [ ] AC-5: Advisory disposition input is derivable from the unified list
      without provider-specific parsing.
- [ ] AC-6: Protocol 93 references the unified contract.
- [ ] AC-7: Existing blocking behavior and advisory-only clean exits still work.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| ------ | -------- | ----------- |
| Shell fixtures | Mock PR-Agent and Haystack advisory outputs | Built into `scripts/development-workflow/tests/test-pr-review-loop.sh` and `scripts/development-workflow/tests/test-haystack-reviewer.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `ADVISORY_FINDINGS` is empty but aliases contain data. | Aggregation still reads only legacy alias fields. | Recheck platform output parsing in `pr-review-loop.sh`. |
| JSON parse test fails on pipes or equals signs. | The implementation split the value beyond the first `=`. | Parse key-value lines by key prefix and keep the entire suffix as JSON. |
| Summary shows duplicate advisory rows. | Both canonical and alias values were rendered. | Prefer `ADVISORY_FINDINGS` and render aliases only as fallback. |

---

## Known Limitations

- This smoke test validates the workflow contract through shell fixtures. A live
  PR reviewer run is useful but not required when shell tests cover the same
  output paths deterministically.
