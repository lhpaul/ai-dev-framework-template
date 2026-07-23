# Smoke Test Runbook: Portable Documentation-Stage Alignment Hardening

**Feature**: Traversal-safe and portable documentation-stage alignment
**Spec**: [1_1312-documentation-stage-alignment-hardening_specs.md](../../specs/developments/20260723113808_1312-documentation-stage-alignment-hardening/1_1312-documentation-stage-alignment-hardening_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] The implementation branch is checked out.
- [ ] Bash, `jq`, and the implementation's supported base64 command are
      available.
- [ ] The checker and existing shell harness are executable.
- [ ] The test harness can prepend temporary command shims to `PATH`.

---

## Test Data

| Item | Value |
| --- | --- |
| Canonical path | `docs/testing/workflow/example.smoke-test.md` |
| Traversal path | `docs/testing/../specs/example.smoke-test.md` |
| Deep traversal path | `docs/testing/workflow/../../src/example.smoke-test.md` |
| Lookalike path | `docs/testing/.../example.smoke-test.md` |
| Valid payload | `ZG9jcy90ZXN0aW5nL3dvcmtmbG93L2V4YW1wbGUuc21va2UtdGVzdC5tZA==` |
| Invalid payload | `%%%not-base64%%%` |
| Decoder families | GNU `--decode`/`-d`, BusyBox `-d`, macOS `-D` |
| Mismatch exit | `8` |
| Evaluation-failure exit | `10` |

---

## Smoke Test Steps

### Step 1: Run the Complete Automated Harness

**Maps to**: Acceptance Criteria 1-8

1. Run
   `bash scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`.
2. Confirm the output names all canonical, traversal, decoder-family,
   invalid-payload, unsupported-capability, and existing regression cases.

**Expected result**: The harness exits successfully with zero failed cases.

### Step 2: Preserve the Canonical Smoke-Test Allowlist

**Maps to**: Acceptance Criteria 2, 7

1. Run the checker in fixture mode on an `implementation-plan/*` head whose only
   files are its plan and
   `docs/testing/workflow/example.smoke-test.md`.
2. Inspect JSON output.

**Expected result**: The checker reports `result: aligned`; the existing
plan-stage policy remains unchanged.

### Step 3: Reject Parent Traversal Before Regex Matching

**Maps to**: Acceptance Criteria 1, 6, 8

1. Run fixture mode with
   `docs/testing/../specs/example.smoke-test.md`.
2. Repeat with
   `docs/testing/workflow/../../src/example.smoke-test.md`.
3. Inspect exit status and `unexpected_files`.

**Expected result**: Each case exits `8`, reports `mismatch`, and preserves the
original traversal path in evidence.

### Step 4: Verify Segment Boundaries

**Maps to**: Acceptance Criteria 1, 2, 7

1. Run fixtures containing `...`, `..hidden`, and `parent..` path segments.
2. Compare their outcomes with the pre-hardening stage regex behavior.

**Expected result**: Only an exact `..` segment triggers traversal rejection.
Lookalikes proceed to the unchanged stage allowlist.

### Step 5: Compare GNU, BusyBox, and macOS Decoders

**Maps to**: Acceptance Criteria 3, 6, 7

1. Prepend the GNU decoder shim to `PATH` and classify the valid payload.
2. Repeat with the BusyBox and macOS decoder shims.
3. Compare decoded bytes and checker JSON.

**Expected result**: Every supported family decodes the same canonical path and
returns the same `aligned` result.

### Step 6: Fail Visibly on Invalid Encoded Content

**Maps to**: Acceptance Criteria 4, 6, 8

1. Use the fixture-only encoded-path input with `%%%not-base64%%%`.
2. Capture stdout, stderr, and exit status.

**Expected result**: The checker exits `10`, identifies changed-path decoding as
the failure, and emits no clean, empty-content, or ordinary mismatch verdict.

### Step 7: Fail Visibly When Decoder Capability Is Missing

**Maps to**: Acceptance Criteria 5, 6, 8

1. Prepend a base64 shim that rejects `--decode`, `-d`, and `-D`.
2. Run a normal plan fixture.
3. Repeat with a shim that passes the probe but fails on the real payload.

**Expected result**: Both cases exit `10`. The first names unsupported decoder
capability; the second names payload decoding. Neither reaches the allowlist.

### Step 8: Verify Protocol 91 Recovery Routing

**Maps to**: Acceptance Criteria 4, 5, 8

1. Inspect Protocol 91 (the Work Item Runner orchestration protocol).
2. Confirm exit `8` remains artifact mismatch/correction.
3. Confirm exit `10` includes GitHub/diff, decoder capability, and
   changed-content decoding failures with repair-and-retry guidance.

**Expected result**: Operator-facing guidance clearly distinguishes invalid PR
artifacts from an environment that could not evaluate them.

### Last Step: Validate and Shut Down

- Run ShellCheck and workflow shell guard lint.
- Verify every assertion below.
- Confirm the test trap removes all temporary decoder shims and fixtures.

---

## Assertions Checklist

- [ ] Exact parent traversal after an allowed prefix is rejected. AC1.
- [ ] Canonical smoke-test documentation remains accepted. AC2.
- [ ] GNU, BusyBox, and macOS variants produce equivalent decoded content and
      alignment decisions. AC3.
- [ ] Invalid encoded content exits with visible evaluation failure. AC4.
- [ ] Unsupported decoder capability exits with actionable infrastructure
      failure. AC5.
- [ ] Automated tests cover path, payload, and environment-family cases. AC6.
- [ ] Existing valid non-traversal classifications remain unchanged. AC7.
- [ ] Human-readable errors and machine-observable exits distinguish mismatch
      from evaluation failure. AC8.

---

## Seed Data Reference

No database seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Alignment fixture | Canonical, traversal, lookalike, and encoded path variants | Generated by the checker shell harness |
| Decoder shim | GNU, BusyBox, macOS, unsupported, and post-probe failure | Generated under the harness temporary directory |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Canonical path is a mismatch | Traversal predicate is running as a broad substring check | Compare exact `/`-delimited segments only |
| `...` is rejected as traversal | Boundary matching is too broad | Require the complete segment to equal `..` |
| One decoder family returns different bytes | Probe selected the wrong flag or failed to validate output | Inspect the known-payload probe and selected flag |
| Invalid payload appears as mismatch | Decode status was not checked before allowlist matching | Route decoder failure directly to exit `10` |
| Temporary base64 shim affects later tests | Harness did not restore `PATH` or clean the temp directory | Restore the original path and verify the exit trap |

---

## Known Limitations

- The traversal check protects repository paths evaluated by this gate; it is
  not a general filesystem sandbox.
- Environment-family coverage uses deterministic CLI shims rather than separate
  operating-system CI workers.
