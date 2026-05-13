# Smoke Test Runbook: Script Quality Gates for pr-review-loop.sh

**Feature**: Script Quality Gates to Prevent Downstream Drift (#585)
**Spec**: [docs/specs/developments/20260512122855_585-script-quality-gates/1_585-script-quality-gates_specs.md](../../specs/developments/20260512122855_585-script-quality-gates/1_585-script-quality-gates_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out locally
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` exists and is executable
- [ ] `pr-review-loop.sh` has the `HARNESS_MODE` guard added
- [ ] `.github/workflows/shellcheck.yml` (or a new workflow file) has the test-harness job/step
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` has the two new checklist items in Step 7.3
- [ ] `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` has the downstream script-bug prompt in Step 3a
- [ ] `bash` is available (any version supporting `set -euo pipefail` and arrays)
- [ ] `git` is available (needed for `REPO_ROOT` resolution inside the harness)

---

## Test Data

| Item | Value |
|---|---|
| Test harness script | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Script under test | `scripts/development-workflow/pr-review-loop.sh` |
| CI workflow file | `.github/workflows/shellcheck.yml` or `.github/workflows/test-pr-review-loop.yml` |
| Prepare-release protocol | `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` |
| Retrospective protocol | `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` |

---

## Smoke Test Steps

### Step 1: Run the test harness locally (AC 1, 4)

**Maps to**: AC: harness runs without external tooling beyond `bash`; AC: harness is executable

1. From the repository root, run:
   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```
2. Observe the output.

**Expected result**: All test cases print `PASS: <name>`. The final summary line reads
`Tests: N passed, 0 failed` (where N > 0). Exit code is 0.

---

### Step 2: Verify harness file is executable and ShellCheck-clean (AC 1, 4)

**Maps to**: AC: harness runs without external tooling beyond `bash`

1. Check the file mode:
   ```bash
   ls -l scripts/development-workflow/tests/test-pr-review-loop.sh
   ```
2. Run ShellCheck (if available locally):
   ```bash
   shellcheck --severity=warning scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

**Expected result**: File has execute permission. ShellCheck reports zero warnings at
`--severity=warning`.

---

### Step 3: Verify coverage of all three target logic areas (AC 2)

**Maps to**: AC: harness covers `normalize_platform_verdict`, `check_unreplied_rest_comments`, and compare-mode analytics

1. Inspect the harness output from Step 1.
2. Confirm that test case names covering each area are present:
   - `normalize_platform_verdict`: look for `PASS: verdict_*` lines
   - `check_unreplied_rest_comments`: look for `PASS: rest_*` lines
   - Compare-mode analytics (`append_compare_metrics_row`): look for `PASS: compare_*` lines

**Expected result**: At least one PASS line exists for each of the three areas.

---

### Step 4: Verify that a test failure causes harness exit 1 (AC 2)

**Maps to**: AC: CI fails when any test case fails

1. Temporarily introduce a regression by changing one expected value in the harness
   (e.g., change `run_test "verdict_clean" "clean"` to `run_test "verdict_clean" "WRONG"`).
2. Run the harness:
   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh; echo "Exit: $?"
   ```
3. Revert the temporary change.

**Expected result**: The harness prints `FAIL: verdict_clean — expected 'WRONG', got 'clean'`,
the summary shows `Tests: N passed, 1 failed`, and the exit code is 1.

---

### Step 5: Verify CI workflow file path filters (AC 3)

**Maps to**: AC: CI runs harness only when `pr-review-loop.sh` or `workflow-lib.sh` is modified

1. Open the CI workflow file (`.github/workflows/shellcheck.yml` or
   `.github/workflows/test-pr-review-loop.yml`) in an editor.
2. Locate the path filter for the test-harness job or step.

**Expected result**: The path filter includes both
`scripts/development-workflow/pr-review-loop.sh` and
`scripts/development-workflow/workflow-lib.sh`. No broader pattern that would trigger
on every PR is present for the test-harness step.

---

### Step 6: Verify prepare-release protocol has script-coverage checklist item (AC 5)

**Maps to**: AC: prepare-release protocol requires the reviewer loop to cover modified workflow scripts

1. Open `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`.
2. Navigate to Step 7.3 (Automated reviewer loop).

**Expected result**: Step 7.3 contains an explicit requirement that the automated
reviewer loop (including CodeRabbit when available) must cover all modified
`scripts/development-workflow/` files before labeling the production PR
`ready-for-human-review`. The requirement is visible as a distinct paragraph or
callout, not buried in existing prose.

---

### Step 7: Verify prepare-release protocol has downstream bug-review checklist item (AC 6)

**Maps to**: AC: prepare-release protocol requires reviewing open script-bug issues before release

1. Still in `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`,
   Step 7.3.

**Expected result**: Step 7.3 contains an explicit instruction to check for open GitHub
issues from downstream sync retrospectives (labeled `workflow`) before labeling the
production PR `ready-for-human-review`. The instruction includes or references a `gh
issue list` command or equivalent guidance.

---

### Step 8: Verify retrospective protocol has downstream script-bug prompt (AC 7)

**Maps to**: AC: retrospective or prepare-release protocol contains the downstream script-bug tracking prompt

1. Open `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`.
2. Navigate to Step 3a (backlog query / issue scan section).

**Expected result**: Step 3a contains the downstream script-bug tracking prompt: an
explicit question asking whether any template script bugs were fixed in a downstream
sync PR during the current cycle, and instructions to file a template issue if so.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Harness exists at `scripts/development-workflow/tests/test-pr-review-loop.sh` and runs without external tooling beyond `bash` (AC 1, 4)
- [ ] Harness covers `normalize_platform_verdict` (AC 2)
- [ ] Harness covers `check_unreplied_rest_comments` bot-account exclusion (AC 2)
- [ ] Harness covers compare-mode analytics platform-config detection (AC 2)
- [ ] CI workflow triggers on `pr-review-loop.sh` or `workflow-lib.sh` changes and fails when any test case fails (AC 3)
- [ ] `05-prepare-release-protocol.md` Step 7.3 requires reviewer loop to cover modified workflow scripts (AC 5)
- [ ] `05-prepare-release-protocol.md` Step 7.3 requires reviewing open downstream script-bug issues before release (AC 6)
- [ ] `06-retrospective-protocol.md` Step 3a contains downstream script-bug tracking prompt (AC 7)

---

## Seed Data Reference

None — the test harness uses in-process mock data; no external seed data is needed.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Harness exits with "return: can only return from a function" | `return 0` used inside `HARNESS_MODE` guard when not sourced (run directly) | Ensure the guard uses `return 0 2>/dev/null \|\| true` |
| All test cases fail immediately after sourcing | `workflow-lib.sh` function mocks missing or incomplete | Add the missing mock function definitions to the harness before the `source` line |
| `check_unreplied_rest_comments` test always returns 0 | Mock `gh` output is not in paginated format (`[[...]]`) | Wrap the mock payload in an outer array to match `jq -s` behavior |
| CI test-harness step does not appear in PR checks | Path filter does not match the changed file | Verify the path filter in the CI workflow includes both target files |
| ShellCheck warns on harness file | Array or process substitution syntax not compatible with `sh` | Ensure shebang is `#!/usr/bin/env bash` and all bash-specific syntax is correct |

---

## Known Limitations

- The harness does not test network behavior or real GitHub API responses — only the jq
  pipeline logic is verified with mock payloads.
- The harness does not achieve complete coverage of `pr-review-loop.sh`. Coverage of
  the three highest-risk sections is the intended scope.
- CI triggers only when `pr-review-loop.sh` or `workflow-lib.sh` changes. PRs that
  modify only other scripts in `scripts/development-workflow/` do not run the harness.
