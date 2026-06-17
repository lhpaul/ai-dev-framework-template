# Smoke Test Runbook: Bugbot Automated PR Reviewer Platform Support

**Feature**: Bugbot Automated PR Reviewer Platform Support (#990)
**Spec**: [docs/specs/developments/20260617122727_bugbot-reviewer-platform/1_bugbot-reviewer-platform_specs.md](../../specs/developments/20260617122727_bugbot-reviewer-platform/1_bugbot-reviewer-platform_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI authenticated with write access to a test repository
- [ ] `scripts/development-workflow/pr-review-loop.sh` is present and executable
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` is present
- [ ] The test repository has an open, non-draft PR available for testing
- [ ] (For the live paths only) The Cursor GitHub App providing Bugbot is
  installed on the test repository

---

## Test Data

| Item | Value |
| --- | --- |
| Test repository | A GitHub repository with the Cursor Bugbot app installed (for live paths) |
| Test PR number | An open non-draft PR in the test repository |
| Bot login | `cursor[bot]` (or overridden via `BUGBOT_BOT_LOGIN`) |
| Check-run name | `Cursor Bugbot` (or overridden via `BUGBOT_CHECK_NAME`) |
| Trigger comment | `bugbot run` (or overridden via `BUGBOT_TRIGGER_COMMENT`) |
| Poll interval | `30` seconds (default) |
| Max wait | `300` seconds (abbreviated for smoke test) |

---

## Smoke Test Steps

### Step 1: Verify script syntax (AC-1, AC-8)

**Maps to**: AC-1 — `bugbot` recognized by `pr-review-loop.sh`; AC-8 — no
behavior change when `bugbot` is absent.

1. Run:

   ```bash
   bash -n scripts/development-workflow/pr-review-loop.sh
   ```

**Expected result**: Command exits 0 with no output (no syntax errors).

### Step 2: Verify `bugbot` is a recognized platform (AC-1, AC-7)

**Maps to**: AC-1 — the platform is dispatched without falling through to the
`unsupported-platform` fallback; AC-7 — the bot login is mapped for thread
auditing.

1. Source the script in HARNESS_MODE and call `bot_login_for_platform`:

   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   bot_login_for_platform bugbot
   ```

**Expected result**: Output is `cursor[bot]` (or the value of `BUGBOT_BOT_LOGIN`
if set). No empty output.

### Step 3: Run HARNESS_MODE unit tests (AC-9)

**Maps to**: AC-9 — exit-code and key-value output contract verified for
no-findings, blocking, and timeout/unavailable scenarios.

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

**Expected result**: All tests pass (exit 0). The output includes PASS lines for
the Bugbot no-findings, blocking, and timeout/unavailable scenarios.

### Step 4: Verify no behavior change when `bugbot` absent (AC-8)

**Maps to**: AC-8 — repositories not listing `bugbot` are unaffected.

1. Ensure `.ai-dev-workflow.yaml` does **not** list `bugbot` under
   `review.on_draft.github` or `review.on_ready.github`.
2. Run the review loop against a test PR (or dry-run with HARNESS_MODE).

**Expected result**: The loop runs exactly as before — no Bugbot review is
triggered, no output lines mention `bugbot`.

### Step 5: Verify `.ai-dev-workflow.yaml` comment updated (AC-1)

**Maps to**: AC-1 — `bugbot` is a documented, selectable reviewer platform.

1. Run:

   ```bash
   grep "bugbot" .ai-dev-workflow.yaml
   ```

**Expected result**: At least one match in the `Supported today` reviewer
comment listing supported platforms (and, if added, the `bugbot` override-options
comment block).

### Step 6: Live end-to-end — no-findings path (AC-2, AC-4) (optional)

**Maps to**: AC-2 — standard telemetry emitted; AC-4 — clean run lets the PR
progress.

> Requires a live repository with the Cursor Bugbot app installed and a PR with
> no issues Bugbot considers blocking. Skip if unavailable.

1. Add `bugbot` to `review.on_ready.github` in `.ai-dev-workflow.yaml` in the
   test repository.
2. Run:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> \
     --platform bugbot \
     --max-wait 300
   ```

**Expected result**: Output contains `PLATFORM_1_NAME=bugbot`,
`PLATFORM_1_RESULT=clean`, `BLOCKING_COUNT=0`, and the standard
`COMMENT_COUNT` / `SUGGESTION_COUNT` lines. Script exits 0.

### Step 7: Live end-to-end — blocking-findings path (AC-3, AC-6) (optional)

**Maps to**: AC-3 — blocking findings keep the PR out of ready; AC-6 — blocking
findings summarized with severity and location context.

> Requires a PR where Bugbot reports at least one blocking finding.

1. Run the same command as Step 6 against a PR with a known Bugbot finding.

**Expected result**: Output contains `RESULT=needs_fixes`, `BLOCKING_COUNT>=1`,
and at least one `BLOCKING_1_PATH` / `BLOCKING_1_LINE` / `BLOCKING_1_BODY`
summary line whose body carries severity and location context (the Bugbot
`BUGBOT_REVIEW` / `BUGBOT_BUG_ID` / `LOCATIONS` / severity markers). Script
exits 1. The PR is not advanced to `ready-for-human-review`.

### Step 8: Live end-to-end — timeout / unavailable path (AC-5) (optional)

**Maps to**: AC-5 — timeout / unavailable surfaced explicitly, never treated as
clean.

> Run against a repository where the Cursor Bugbot app is NOT installed, or use a
> very short max-wait so no completed check run appears in time.

1. Run with a short max-wait:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> \
     --platform bugbot \
     --max-wait 60
   ```

**Expected result**: Output contains `RESULT=escalate` and `REASON=timeout` (no
completed check run in time) or `REASON=unavailable` (no Cursor Bugbot check run
ever published). Script exits 2. The result is **never** `clean`. No crash or
unhandled error.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: `bugbot` is recognized by `pr-review-loop.sh`; `bot_login_for_platform bugbot` returns a non-empty login; `.ai-dev-workflow.yaml` lists `bugbot`
- [ ] AC-2: Bugbot run emits standard telemetry — `RESULT`, `PLATFORM_n`, `COMMENT_COUNT`, `BLOCKING_COUNT`, `SUGGESTION_COUNT`
- [ ] AC-3: Blocking Bugbot findings → exit 1, `RESULT=needs_fixes`, `BLOCKING_COUNT>=1`; PR kept out of `ready-for-human-review`
- [ ] AC-4: No-findings run → exit 0, `RESULT=clean`, `BLOCKING_COUNT=0`; PR may progress
- [ ] AC-5: Timeout / unavailable / absent verdict → exit 2, `RESULT=escalate`, `REASON=timeout` or `REASON=unavailable`; never `clean`
- [ ] AC-6: Blocking findings summarized with severity and location context in `BLOCKING_*_BODY`
- [ ] AC-7: `bot_login_for_platform bugbot` returns `cursor[bot]`, including Bugbot in platform thread auditing
- [ ] AC-8: Review-loop behavior unchanged for repositories that do not list `bugbot`
- [ ] AC-9: HARNESS_MODE unit tests cover no-findings, blocking, and timeout/unavailable scenarios; all pass

---

## Seed Data Reference

None — this is a shell-script, configuration-comment, and test change. No
application data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| N/A | N/A | N/A |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `bot_login_for_platform bugbot` returns empty | `bugbot)` case missing from `bot_login_for_platform()` | Add the case per Implementation Order step 4 |
| `RESULT=skipped REASON=unsupported-platform` for `bugbot` | `bugbot)` case missing from `run_platform_review()` | Add the case per Implementation Order step 3 |
| HARNESS_MODE tests fail for the Bugbot area | `run_bugbot_review` function absent or misnamed | Verify the function is named exactly `run_bugbot_review` and is present in `pr-review-loop.sh` |
| Live test: no check run ever found, but a real Bugbot review exists | Check-run name or app slug mismatch | Set `BUGBOT_CHECK_NAME` / verify the `.app.slug` filter; the function should also fall back to the `cursor[bot]` review/comment signal |
| Live test: absent verdict reported as clean | Classification bug — missing verdict treated as success | Confirm the timeout/unavailable path returns `escalate`, never `clean` (AC-5) |

---

## Known Limitations

- Live end-to-end testing requires a repository with the Cursor GitHub App
  (Bugbot) installed. Most CI environments will not have this configured; the
  HARNESS_MODE unit tests provide deterministic coverage in those environments.
- The exact "Cursor Bugbot" check-run name, `cursor[bot]` login, and trigger
  phrase may vary across Cursor app versions; use the `BUGBOT_CHECK_NAME`,
  `BUGBOT_BOT_LOGIN`, and `BUGBOT_TRIGGER_COMMENT` env-var overrides if the
  defaults do not match your repository.
- Downstream Bugbot setup documentation (`.cursor/BUGBOT.md`, rollout defaults,
  check-conclusion reference) is out of scope for this item and is delivered by a
  separate epic #988 child.
