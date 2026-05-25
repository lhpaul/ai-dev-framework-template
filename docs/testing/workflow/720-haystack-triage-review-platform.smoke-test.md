# Smoke Test Runbook: Haystack Triage CLI — Native PR Review Platform

**Feature**: Haystack Triage CLI as native PR review platform (#720)
**Spec**: [docs/specs/developments/20260524150346_720-haystack-triage-review-platform/1_720-haystack-triage-review-platform_specs.md](../../specs/developments/20260524150346_720-haystack-triage-review-platform/1_720-haystack-triage-review-platform_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The repository is checked out locally with the feature branch applied
- [ ] `gh` CLI is authenticated (`gh auth status`)
- [ ] `jq` is installed (`jq --version`)
- [ ] A test PR number is available in the repo (can be any open, non-draft PR)
- [ ] The `haystack` CLI is installed for AC-2, AC-3, AC-5 tests (`haystack --version`)
  - Note: AC-4 tests explicitly require the CLI to be **absent** — use a temporary `$PATH` override
- [ ] `scripts/development-workflow/haystack-reviewer.sh` is executable (`chmod +x`)

---

## Test Data

| Item | Value |
| ---- | ----- |
| Repo owner | `<owner>` (from `gh repo view --json owner -q .owner.login`) |
| Repo name | `<repo>` (from `gh repo view --json name -q .name`) |
| Test PR number | `<pr_number>` (any open non-draft PR in the repo) |
| Script path | `scripts/development-workflow/haystack-reviewer.sh` |
| pr-review-loop path | `scripts/development-workflow/pr-review-loop.sh` |

---

## Smoke Test Steps

### Step 1: AC-4 — Graceful degradation when `haystack` CLI is absent

**Maps to**: Acceptance Criterion AC-4

1. Temporarily remove `haystack` from `$PATH`:
   ```bash
   PATH_BACKUP="$PATH"
   export PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'haystack' | tr '\n' ':')"
   ```
2. Run the script:
   ```bash
   scripts/development-workflow/haystack-reviewer.sh 1 owner repo
   ```
3. Observe the exit code:
   ```bash
   echo "Exit code: $?"
   ```
4. Restore `$PATH`:
   ```bash
   export PATH="$PATH_BACKUP"
   ```

**Expected result**:
- Exit code is `3`
- stdout contains `RESULT=skipped`
- stdout contains `REASON=unavailable`
- No error message about "review findings" or triage output

---

### Step 2: AC-2 — Blocking findings produce exit 1 and `RESULT=needs_fixes`

**Maps to**: Acceptance Criterion AC-2

Prerequisites: `haystack` CLI installed and authenticated. A test PR with known blocking findings, or mock the CLI output by setting `HAYSTACK_TRIAGE_CMD` to a test double that emits a JSON payload with a blocking severity finding (if the script supports a test-double override).

1. Run the script against a PR that has blocking Haystack findings:
   ```bash
   scripts/development-workflow/haystack-reviewer.sh <pr_number> <owner> <repo>
   echo "Exit code: $?"
   ```

**Expected result**:
- Exit code is `1`
- stdout contains `RESULT=needs_fixes`
- stdout contains `BLOCKING_COUNT=<n>` where `n > 0`
- stderr contains the raw `haystack triage --json` output (for debugging)

---

### Step 3: AC-3 — Advisory/no findings produce exit 0 and `RESULT=clean`

**Maps to**: Acceptance Criterion AC-3

Prerequisites: `haystack` CLI installed and authenticated. A test PR with no blocking findings, or mock the CLI output to return only advisory findings.

1. Run the script against a PR with no blocking findings:
   ```bash
   scripts/development-workflow/haystack-reviewer.sh <pr_number> <owner> <repo>
   echo "Exit code: $?"
   ```

**Expected result**:
- Exit code is `0`
- stdout contains `RESULT=clean`
- stdout contains `BLOCKING_COUNT=0`

---

### Step 4: AC-5 — `bot_login_for_platform("haystack")` returns empty string

**Maps to**: Acceptance Criterion AC-5

1. Source the pr-review-loop.sh in harness mode and call `bot_login_for_platform`:
   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh 2>/dev/null || true
   result="$(bot_login_for_platform haystack)"
   echo "Bot login: '${result}'"
   ```

**Expected result**:
- Output is `Bot login: ''` (empty string)
- No error

---

### Step 5: AC-1 / AC-8 — `run_platform_review` dispatches to haystack reviewer

**Maps to**: Acceptance Criteria AC-1, AC-8

1. Verify `haystack` appears in `run_platform_review` case statement:
   ```bash
   grep -A3 "haystack)" scripts/development-workflow/pr-review-loop.sh | head -6
   ```

**Expected result**:
- Output contains `run_haystack_review` or similar dispatch call
- The case block is present in the function

---

### Step 6: AC-6 — Integration guide exists with required sections

**Maps to**: Acceptance Criterion AC-6

1. Confirm the guide exists:
   ```bash
   test -f docs/workflow/development-workflow/integrations/haystack-triage.md && echo "exists"
   ```
2. Confirm required sections are present:
   ```bash
   grep -l "bot login\|severity\|install\|CLI" docs/workflow/development-workflow/integrations/haystack-triage.md
   ```

**Expected result**:
- File exists
- Contains content covering CLI install steps, bot login identifier, and severity mapping table

---

### Step 7: AC-7 — `haystack.md` references new triage guide

**Maps to**: Acceptance Criterion AC-7

1. Check for cross-reference:
   ```bash
   grep "haystack-triage" docs/workflow/development-workflow/integrations/haystack.md
   ```

**Expected result**:
- At least one reference to `haystack-triage.md` appears in `haystack.md`

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met
- No temporary files left in `/tmp/haystack_*`

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: `run_platform_review("haystack", ...)` dispatches to `haystack-reviewer.sh`
- [ ] AC-2: Blocking severity findings → exit 1, `RESULT=needs_fixes`, `BLOCKING_COUNT > 0`
- [ ] AC-3: Advisory/no findings → exit 0, `RESULT=clean`, `BLOCKING_COUNT=0`
- [ ] AC-4: Missing `haystack` binary → exit 3, `RESULT=skipped`, `REASON=unavailable`; other platforms unaffected
- [ ] AC-5: `bot_login_for_platform("haystack")` returns empty string
- [ ] AC-6: `haystack-triage.md` exists with CLI install steps, bot login identifier, and severity mapping table
- [ ] AC-7: `haystack.md` references `haystack-triage.md` and notes triage as a supported review platform
- [ ] AC-8: `haystack-reviewer.sh` accepts `<pr_number> <owner> <repo>` and emits the standard key-value output contract

---

## Seed Data Reference

None — this feature adds tooling scripts and documentation with no application data dependencies.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `RESULT=skipped` when CLI is installed | `haystack` not in `$PATH` at script invocation time | Confirm `which haystack` works in the shell running the script |
| `haystack triage --json` fails with auth error | CLI not authenticated | Run `haystack setup` or `haystack auth login` |
| Exit code 2 (TIMED_OUT) | Slow network or large PR | Increase `HAYSTACK_REVIEWER_TIMEOUT` env var (default: 120 s) |
| JSON parse error | Unexpected `haystack triage --json` output schema | Check actual schema vs. the `jq` expression in `haystack-reviewer.sh`; consult `haystack triage --help` |

---

## Known Limitations

- AC-2 and AC-3 tests require a real or mocked `haystack triage --json` response. Without a CLI test-double mechanism, these tests must be run with the actual Haystack CLI authenticated against a real PR.
- Haystack triage findings are parsed locally; they are not posted back to GitHub as inline review comments (Out of Scope for MVP). The `check_unresolved_threads` gate is therefore not triggered for the `haystack` platform.
