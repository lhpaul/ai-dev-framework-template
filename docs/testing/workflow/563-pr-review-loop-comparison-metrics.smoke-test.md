# Smoke Test Runbook: PR Review Loop Comparison Mode and Platform Metrics Tracking

**Feature**: PR Review Loop Comparison Mode and Platform Metrics Tracking (#563)
**Spec**: [docs/specs/developments/20260510235554_563-pr-review-loop-comparison-metrics/1_563-pr-review-loop-comparison-metrics_specs.md](../../specs/developments/20260510235554_563-pr-review-loop-comparison-metrics/1_563-pr-review-loop-comparison-metrics_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out locally
- [ ] `scripts/development-workflow/pr-review-loop.sh` has been updated with `--compare` support
- [ ] `docs/workflow/retro-metrics-platforms.md` exists with the header and graduation criteria
- [ ] `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` has been updated with Step 2b
- [ ] Agent and skill files (`.claude/agents/retrospective.md`, `.cursor/agents/retrospective.md`, `.codex/skills/workflow-retrospective/SKILL.md`) have been updated

---

## Test Data

| Item                        | Value                                                                             |
| --------------------------- | --------------------------------------------------------------------------------- |
| Script under test           | `scripts/development-workflow/pr-review-loop.sh`                                  |
| Metrics log file            | `docs/workflow/retro-metrics-platforms.md`                                        |
| Meta-retrospective protocol | `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` |
| Agent file (Claude Code)    | `.claude/agents/retrospective.md`                                                 |
| Agent file (Cursor)         | `.cursor/agents/retrospective.md`                                                 |
| Skill file (Codex)          | `.codex/skills/workflow-retrospective/SKILL.md`                                   |

---

## Smoke Test Steps

### Step 1: Verify `--compare` flag is accepted

**Maps to**: Acceptance Criterion 1, 6

1. Run `./scripts/development-workflow/pr-review-loop.sh --help`.
2. Confirm `--compare` appears in the usage output.
3. Run `./scripts/development-workflow/pr-review-loop.sh` without `--compare` against a real or recent PR (use a PR number from the repository's history that is already merged and clean).
4. Confirm the output and exit code are identical to previous behavior (no `COMPARE_MODE` key in output, no metrics row appended).

**Expected result**: `--compare` appears in help; normal invocation behavior is unchanged.

---

### Step 2: Verify compare mode runs all platforms

**Maps to**: Acceptance Criterion 1, 2

1. Invoke the script in compare mode against a real open or recently-merged PR:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr-number> --compare
   ```

2. Observe the output. Confirm `COMPARE_MODE=1` appears in the key=value output.
3. Confirm `COMPARE_VERDICT_1_PLATFORM`, `COMPARE_VERDICT_1_RESULT`, `COMPARE_VERDICT_2_PLATFORM`, `COMPARE_VERDICT_2_RESULT` (and so on for each configured platform) appear in the output.
4. Confirm the script did not exit after the first platform's result — all platforms ran to completion.

**Expected result**: Output contains `COMPARE_MODE=1` and per-platform verdict lines for every configured platform.

---

### Step 3: Verify overall exit code matches normal mode

**Maps to**: Acceptance Criterion 2

1. Run the same PR in normal mode and note the `RESULT` value and exit code.
2. Run the same PR in compare mode and note the `RESULT` value and exit code.
3. Confirm the `RESULT` value and exit code are identical between the two runs.

**Expected result**: `RESULT` and exit code are the same in both modes for the same PR and platform verdicts.

---

### Step 4: Verify a metrics row is appended

**Maps to**: Acceptance Criterion 3

1. Note the number of data rows currently in `docs/workflow/retro-metrics-platforms.md` (count table rows after the header).
2. Run `./scripts/development-workflow/pr-review-loop.sh <pr-number> --compare`.
3. Open `docs/workflow/retro-metrics-platforms.md` and confirm exactly one new row was appended.
4. Confirm the row contains the correct PR number, the correct branch type (e.g., `fix` for a `fix/*` branch), a verdict for each configured platform, and an overall result.
5. Confirm the "Block Was Real Bug?" column is blank.

**Expected result**: One new row is appended; all columns are populated; "Block Was Real Bug?" is blank.

---

### Step 5: Verify the metrics log header contains graduation criteria

**Maps to**: Acceptance Criterion 4

1. Open `docs/workflow/retro-metrics-platforms.md`.
2. Confirm a "Graduation Criteria" or equivalent section exists in the file header.
3. Confirm the criteria state: zero platform-exclusive blocking findings across 30 or more consecutive compare-mode runs, covering at least one run each of `fix`, `feature`, and `refactor` branch types.
4. Confirm the criteria explicitly state that fewer than 30 runs is insufficient for a graduation decision.

**Expected result**: Header section with graduation criteria matching the spec is present.

---

### Step 6: Verify platform-exclusive block detection

**Maps to**: Acceptance Criterion 5

This step requires a scenario where one platform blocks and another is clean. If no such PR is immediately available, verify the logic by reading the code:

1. Open `scripts/development-workflow/pr-review-loop.sh`.
2. Locate `normalize_platform_verdict` (or equivalent) and confirm it maps `needs_fixes` to `blocking` and `clean` to `clean`.
3. Confirm that when `compare_mode=1` and a `blocking` verdict is recorded for platform A but `clean` for platform B, the appended metrics row contains `blocking` for platform A and `clean` for platform B.
4. Confirm the overall result reflects the first-blocking-platform rule (e.g., if platform A is listed first in config and returned `needs_fixes`, `RESULT=needs_fixes`).

**Expected result**: Per-platform verdicts are recorded accurately; overall result matches first-blocking rule.

---

### Step 7: Verify the meta-retrospective protocol includes Step 2b

**Maps to**: Acceptance Criterion 7

1. Open `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`.
2. Locate Step 2b (Platform Evaluation) — it should appear between Step 2 and Step 3.
3. Confirm Step 2b describes:
   - Reading `docs/workflow/retro-metrics-platforms.md`.
   - Reporting "no data" when the file is absent or empty.
   - Computing per-platform exclusive-block rate.
   - Comparing against the graduation criteria.
   - Reporting one of: "safe to evaluate removal", "data insufficient", or "not yet ready".

**Expected result**: Step 2b is present and covers all required sub-steps.

---

### Step 8: Verify fewer-than-30-runs data-insufficient message

**Maps to**: Acceptance Criterion 8

1. Ensure `docs/workflow/retro-metrics-platforms.md` has fewer than 30 data rows (it will initially have 0 or very few).
2. Simulate or read through the meta-retrospective Step 2b logic.
3. Confirm the protocol explicitly states "data insufficient" or equivalent when fewer than 30 runs are logged.

**Expected result**: The protocol output explicitly flags insufficient data when the row count is below 30.

---

### Step 9: Verify agent and skill files are updated

**Maps to**: AC 7 (supporting)

1. Open `.claude/agents/retrospective.md`.
2. Confirm a bullet or note references the platform evaluation step in the meta-retrospective and `docs/workflow/retro-metrics-platforms.md`.
3. Repeat for `.cursor/agents/retrospective.md` and `.codex/skills/workflow-retrospective/SKILL.md`.

**Expected result**: All three files mention the platform evaluation step.

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- No cleanup needed (metrics rows written to `docs/workflow/retro-metrics-platforms.md` during testing may be left in place — they represent real test data).

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: `--compare` runs all configured platforms to completion; per-platform verdicts in output.
- [ ] AC 2: Overall exit code and `RESULT` in compare mode are identical to normal mode for the same PR.
- [ ] AC 3: One row appended to `docs/workflow/retro-metrics-platforms.md` after each compare run.
- [ ] AC 4: Metrics log header documents graduation criteria (zero exclusive blocks, ≥ 30 runs, ≥ 1 each of fix/feature/refactor).
- [ ] AC 5: Platform-exclusive block correctly recorded when one platform blocks and another is clean.
- [ ] AC 6: Normal (non-compare) invocation is unaffected: behavior, output, and exit codes unchanged.
- [ ] AC 7: `06b-meta-retrospective-protocol.md` includes Step 2b that reads the metrics file and reports rates.
- [ ] AC 8: Meta-retrospective Step 2b explicitly states "data insufficient" when fewer than 30 runs logged.

---

## Seed Data Reference

No seed data is required for this feature.

| Entity                 | Scenario                 | How to load                            |
| ---------------------- | ------------------------ | -------------------------------------- |
| Real or recent open PR | Compare-mode test target | Use an existing PR from the repository |

---

## Troubleshooting

| Symptom                                          | Likely cause                                          | Fix                                                              |
| ------------------------------------------------ | ----------------------------------------------------- | ---------------------------------------------------------------- |
| `Unknown option: --compare` error                | `--compare` not added to argument parser              | Verify implementation Step 1                                     |
| Metrics row not appended                         | `append_compare_metrics_row` not called after loop    | Verify implementation Step 5d                                    |
| Only one platform runs in compare mode           | `break` still present unconditionally in loop         | Verify implementation Step 2                                     |
| `RESULT` differs between compare and normal mode | Overall result not recomputed from collected verdicts | Verify implementation Step 4                                     |
| File not created on first compare run            | Path resolution in `append_compare_metrics_row` wrong | Check `cd_workflow_repo_root_path` or equivalent path derivation |

---

## Known Limitations

- The "Block Was Real Bug?" column in the metrics log is filled manually by an analyst — it cannot be automated at run time.
- Compare mode always runs all configured platforms; running a subset is out of scope (MVP).
