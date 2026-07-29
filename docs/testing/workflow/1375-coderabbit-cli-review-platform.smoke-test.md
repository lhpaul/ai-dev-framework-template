# Smoke Test Runbook: CodeRabbit CLI Review Platform

**Feature**: Add CodeRabbit CLI as optional Step 7 review platform
**Spec**: [1_1375-coderabbit-cli-review-platform_specs.md](../../specs/developments/20260728171704_1375-coderabbit-cli-review-platform/1_1375-coderabbit-cli-review-platform_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out.
- [ ] Test harnesses pass locally.
- [ ] `gh` is authenticated for repository metadata lookups.
- [ ] If testing a live successful review, CodeRabbit CLI is installed and
  authenticated. If it is not available, run the unavailable-path checks.

---

## Test Data

| Item | Value |
| --- | --- |
| Test PR | A draft or disposable PR from the implementation branch |
| Base branch | `develop` |
| Configured platform | `coderabbit-cli` |
| Existing App platform | `coderabbit` |

---

## Smoke Test Steps

### Step 1: Confirm CLI platform is independently configurable

**Maps to**: Acceptance Criteria 1 and 2

1. In a temporary copy or local override, configure `review.on_draft.github`
   with `coderabbit-cli`.
2. Run the reviewer loop against the test PR with
   `./scripts/development-workflow/pr-review-loop.sh <pr> --branch <branch> --platform coderabbit-cli`.
3. Confirm the output contains `PLATFORM_LIST=coderabbit-cli` and
   `PLATFORM_1_NAME=coderabbit-cli`.

**Expected result**: The loop accepts `coderabbit-cli` without using the
existing `coderabbit` GitHub App path.

### Step 2: Confirm existing CodeRabbit App behavior remains distinct

**Maps to**: Acceptance Criteria 1 and 2

1. Run the reviewer loop with `--platform coderabbit`.
2. Confirm the output identifies `PLATFORM_1_NAME=coderabbit`.
3. Confirm the CodeRabbit App path still uses GitHub bot review evidence and
   not the local CLI companion script.

**Expected result**: `coderabbit` and `coderabbit-cli` remain separate
platforms.

### Step 3: Confirm unavailable CLI is skipped, not clean

**Maps to**: Acceptance Criteria 3 and 7

1. Run the new CodeRabbit CLI companion script with `cr` and `coderabbit`
   unavailable on `PATH`.
2. Confirm the script exits with the skipped contract.
3. Confirm companion-script output includes `RESULT=skipped` and an
   unavailable reason.
4. Run the reviewer loop with `--platform coderabbit-cli` and confirm the
   loop-mapped output includes `PLATFORM=coderabbit-cli`.

**Expected result**: Missing CLI or auth is explicit unavailable/skipped
evidence and is never reported as a successful fresh review.

### Step 4: Confirm clean and blocking output mapping

**Maps to**: Acceptance Criteria 2 and 4

1. Run the new unit harness fixtures for clean CLI JSON.
2. Run the harness fixtures for blocking CLI JSON.
3. Confirm clean fixtures emit `RESULT=clean` and blocking fixtures emit
   `RESULT=needs_fixes` with `BLOCKING_COUNT` greater than zero.

**Expected result**: CLI findings are normalized into the same Step 7
contract as other platforms.

### Step 5: Confirm rate-limit policy behavior

**Maps to**: Acceptance Criteria 4, 5, and 6

1. Run the rate-limited fixture with default policy.
2. Confirm it emits `RESULT=skipped` and `REASON=rate_limited`.
3. Run the same fixture with `CODERABBIT_CLI_RATE_LIMIT_POLICY=strict`.
4. Confirm it emits `RESULT=escalate` and `REASON=rate_limited`.

**Expected result**: Default warn policy allows the workflow to continue with
explicit skipped evidence; strict policy blocks/escalates.

### Step 6: Confirm documentation evidence

**Maps to**: Acceptance Criteria 7 and 8

1. Open the implementation PR.
2. Confirm the automated reviewer summary or handoff notes state whether a
   fresh CodeRabbit CLI review ran.
3. If the CLI was unavailable, confirm the notes do not claim CodeRabbit CLI
   found no issues.

**Expected result**: PR evidence distinguishes clean review evidence from a
skipped or unavailable platform.

### Last Step: Validate & Shut Down

- Verify all assertions below are met.
- Restore any temporary local configuration changes.

---

## Assertions Checklist

- [ ] `coderabbit-cli` is configurable independently from `coderabbit`.
- [ ] `pr-review-loop.sh` dispatches `coderabbit-cli` and preserves
  `coderabbit` App behavior.
- [ ] Missing CLI or auth maps to skipped/unavailable, not clean.
- [ ] Clean CLI output maps to `RESULT=clean`.
- [ ] Blocking CLI output maps to `RESULT=needs_fixes`.
- [ ] Rate limit with warn policy maps to skipped.
- [ ] Rate limit with strict policy maps to escalation.
- [ ] PR evidence states whether a fresh CodeRabbit CLI review actually ran.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Mock CLI output | Clean, blocking, unavailable, and rate-limited responses | Run `scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `coderabbit-cli` is reported as unsupported | `pr-review-loop.sh` dispatch or platform list was not updated | Re-check dispatch and supported-platform enumeration |
| CLI returns skipped during live smoke | CodeRabbit CLI is missing, unauthenticated, or rate-limited | Verify `cr --agent --base develop` locally or record skipped evidence |
| App review starts instead of CLI | Platform name `coderabbit` was used instead of `coderabbit-cli` | Re-run with the explicit CLI platform |

---

## Known Limitations

- Live successful CodeRabbit CLI review depends on local CLI installation,
  authentication, and current CodeRabbit service limits.
- Rate-limit reset waiting is intentionally out of scope.
