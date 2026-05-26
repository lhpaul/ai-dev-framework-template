# Smoke Test Runbook: GitHub Copilot Code Review Backstop

**Feature**: GitHub Copilot Code Review Backstop (#709)
**Spec**: [docs/specs/developments/20260524150328_copilot-review-backstop/1_copilot-review-backstop_specs.md](../../specs/developments/20260524150328_copilot-review-backstop/1_copilot-review-backstop_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI authenticated with write access to a test repository
- [ ] `scripts/development-workflow/pr-review-loop.sh` is present and executable
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` is present
- [ ] The test repository has an open, non-draft PR available for testing
- [ ] (For AC-1/AC-2/AC-3 live tests) The repository has an active GitHub Copilot
  seat or the Copilot for Pull Requests feature enabled

---

## Test Data

| Item | Value |
| --- | --- |
| Test repository | A GitHub repository with Copilot review active (for live paths) |
| Test PR number | An open non-draft PR in the test repository |
| Bot login | `copilot-pull-request-reviewer[bot]` (or overridden via `COPILOT_BOT_LOGIN`) |
| Poll interval | `30` seconds (default) |
| Max wait | `300` seconds (abbreviated for smoke test) |

---

## Smoke Test Steps

### Step 1: Verify script syntax (AC-1, AC-5)

**Maps to**: AC-1 — `copilot` recognized by `pr-review-loop.sh`; AC-5 — no
behavior change when `copilot` is absent from `review.platforms`

1. Run:

   ```bash
   bash -n scripts/development-workflow/pr-review-loop.sh
   ```

**Expected result**: Command exits 0 with no output (no syntax errors).

### Step 2: Verify `copilot` is a recognized platform (AC-1)

**Maps to**: AC-1 — the platform is dispatched without falling through to the
`unsupported-platform` fallback

1. Source the script in HARNESS_MODE and call `bot_login_for_platform`:

   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   bot_login_for_platform copilot
   ```

**Expected result**: Output is `copilot-pull-request-reviewer[bot]` (or the
value of `COPILOT_BOT_LOGIN` if set). No empty output.

### Step 3: Run HARNESS_MODE unit tests (AC-8)

**Maps to**: AC-8 — exit-code and key-value output contract verified for clean,
needs\_fixes, and escalate scenarios

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

**Expected result**: All tests pass (exit 0). The output includes PASS lines for
the Copilot clean, needs-fixes, and escalate (timeout) scenarios.

### Step 4: Verify no behavior change when `copilot` absent (AC-5)

**Maps to**: AC-5 — repositories not listing `copilot` are unaffected

1. Ensure `.ai-dev-workflow.yaml` does **not** list `copilot` in
   `review.platforms`.
2. Run the review loop against a test PR (or dry-run with HARNESS_MODE).

**Expected result**: The loop runs exactly as before — no Copilot review is
triggered, no output lines mention `copilot`.

### Step 5: Verify integration guide is present and marked optional (AC-6)

**Maps to**: AC-6 — integration guide added under `integrations/`

1. Check:

   ```bash
   ls docs/workflow/development-workflow/integrations/copilot.md
   ```

2. Open the file and confirm the first paragraph contains the word "optional".
3. Confirm the guide documents the `COPILOT_BOT_LOGIN` override variable.
4. Confirm prerequisites (Copilot seat / feature) are described.

**Expected result**: File exists, marked optional, prerequisites documented,
env var override documented.

### Step 6: Verify `.ai-dev-workflow.yaml` comment updated (AC-7)

**Maps to**: AC-7 — template comment lists `copilot` as an optional backstop

1. Run:

   ```bash
   grep "copilot" .ai-dev-workflow.yaml
   ```

**Expected result**: At least two matches — one in the `Supported today` comment
listing supported platforms and one in the `copilot`-specific configurable
options comment block.

### Step 7: Live end-to-end test — clean path (AC-1, AC-3) (optional)

**Maps to**: AC-1 and AC-3 — Copilot approves PR, loop emits `RESULT=clean`

> This step requires a live repository with Copilot code review active. Skip if
> that prerequisite is not available.

1. Add `copilot` to `review.platforms` in `.ai-dev-workflow.yaml` in the test
   repository.
2. Run:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> \
     --platform copilot \
     --max-wait 300
   ```

**Expected result**: Output contains `PLATFORM_1_NAME=copilot` and
`PLATFORM_1_RESULT=clean` (or `needs_fixes` if Copilot found issues). Script
exits 0 for clean, 1 for needs\_fixes.

### Step 8: Live end-to-end test — unavailable path (AC-4) (optional)

**Maps to**: AC-4 — Copilot not active on repository → `RESULT=escalate`

> This step requires a repository where the Copilot review feature is NOT active.

1. Add `copilot` to `review.platforms` in `.ai-dev-workflow.yaml` for a
   repository without an active Copilot seat.
2. Run with a short max-wait to confirm timeout behaviour:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> \
     --platform copilot \
     --max-wait 60
   ```

**Expected result**: Output contains `RESULT=escalate` and
`REASON=unavailable` or `REASON=timeout`. Script exits 2. No crash or
unhandled error.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: `copilot` is recognized by `pr-review-loop.sh`; `bot_login_for_platform copilot` returns a non-empty login
- [ ] AC-2: HARNESS_MODE test for CHANGES\_REQUESTED path passes — exit 1, `RESULT=needs_fixes`, `BLOCKING_COUNT>=1`
- [ ] AC-3: HARNESS_MODE test for APPROVED path passes — exit 0, `RESULT=clean`, `BLOCKING_COUNT=0`
- [ ] AC-4: HARNESS_MODE test for timeout/unavailable path passes — exit 2, `RESULT=escalate`
- [ ] AC-5: Review loop behavior is unchanged for repositories that do not list `copilot` in `review.platforms`
- [ ] AC-6: `docs/workflow/development-workflow/integrations/copilot.md` exists, marked optional, prerequisites documented
- [ ] AC-7: `.ai-dev-workflow.yaml` `Supported today` comment lists `copilot`
- [ ] AC-8: HARNESS_MODE unit tests cover clean, needs\_fixes, and escalate scenarios; all pass

---

## Seed Data Reference

None — this is a shell script, documentation, and test change. No application
data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| N/A | N/A | N/A |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `bot_login_for_platform copilot` returns empty | `copilot)` case missing from `bot_login_for_platform()` | Add the case per Implementation Order step 4 |
| `RESULT=skipped REASON=unsupported-platform` for `copilot` | `copilot)` case missing from `run_platform_review()` | Add the case per Implementation Order step 3 |
| HARNESS_MODE tests fail for Copilot area | `run_copilot_review` function absent or misnamed | Verify function is named exactly `run_copilot_review` and is present in `pr-review-loop.sh` |
| Live test: reviewer request API call fails with 404 or 422 | Copilot review feature not enabled on the repository | Confirm Copilot seat active; verify the reviewer login value matches GitHub's expected value for the Copilot reviewer |

---

## Known Limitations

- Live end-to-end testing of the clean and needs-fixes paths requires a repository
  with an active GitHub Copilot seat or the Copilot for Pull Requests feature
  enabled. Most CI environments will not have this configured.
- The exact bot login for Copilot pull-request reviews may vary across GitHub
  plans; use the `COPILOT_BOT_LOGIN` env var override if the default
  `copilot-pull-request-reviewer[bot]` does not match what GitHub uses on your
  repository.
- GitHub Enterprise Server (GHES) with a self-hosted Copilot deployment is out of
  scope for this feature; live tests against GHES are not covered.
