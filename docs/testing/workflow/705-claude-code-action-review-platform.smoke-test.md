# Smoke Test Runbook: Claude Code Action Review Platform

**Feature**: Claude Code Action Review Platform (#705)
**Spec**: [docs/specs/developments/20260523130152_claude-code-action-review-platform/1_claude-code-action-review-platform_specs.md](../../specs/developments/20260523130152_claude-code-action-review-platform/1_claude-code-action-review-platform_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] A test repository with the Claude Code Action GitHub Actions workflow file present (e.g., `.github/workflows/claude-code-review.yml` accepting `workflow_dispatch` with a `pr_number` input)
- [ ] `gh` CLI authenticated with write access to the test repository
- [ ] `scripts/development-workflow/claude-code-action-reviewer.sh` is executable
- [ ] `scripts/development-workflow/pr-review-loop.sh` is present
- [ ] The test repository has an open, non-draft PR available for testing

---

## Test Data

| Item | Value |
| --- | --- |
| Test repository | A GitHub repository with `claude-code-review.yml` workflow |
| Test PR number | An open non-draft PR in the test repository |
| Bot login | `claude[bot]` (or overridden via `CLAUDE_CODE_ACTION_BOT_LOGIN`) |
| Workflow file | `claude-code-review.yml` (or overridden via `CLAUDE_CODE_ACTION_WORKFLOW_FILE`) |
| Poll interval | `30` seconds (default) |
| Max wait | `300` seconds (abbreviated for smoke test) |

---

## Smoke Test Steps

### Step 1: Verify the reviewer script is valid (AC-1)

**Maps to**: AC-1 — platform recognized by the reviewer loop

1. Run:
   ```bash
   bash -n scripts/development-workflow/claude-code-action-reviewer.sh
   ```
2. Run:
   ```bash
   bash -n scripts/development-workflow/pr-review-loop.sh
   ```

**Expected result**: Both commands exit 0 with no output (no syntax errors).

### Step 2: Verify `claude-code-action` is a recognized platform (AC-1)

**Maps to**: AC-1 — `PLATFORM=claude-code-action` emitted in output

1. In a test repository, add `claude-code-action` to `review.platforms` in `.ai-dev-workflow.yaml`
2. Run:
   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   bot_login_for_platform claude-code-action
   ```
3. Confirm the command prints the configured bot login (default `claude[bot]`)

**Expected result**: The bot login is printed without errors, confirming the platform is registered in `bot_login_for_platform()`.

### Step 3: Dispatch workflow and observe clean result (AC-1, AC-2)

**Maps to**: AC-1 (platform invoked) and AC-2 (RESULT=clean when no blocking threads)

1. Ensure the Claude Code Action bot has no unresolved review threads on the test PR
2. Run:
   ```bash
   scripts/development-workflow/claude-code-action-reviewer.sh \
     <pr_number> <owner> <repo> \
     --max-wait 300 \
     --poll-interval 30
   ```
3. Observe the INFO lines showing the workflow dispatch and polling
4. After the Actions run completes successfully with no blocking threads, confirm exit code is 0

**Expected result**: Script exits 0. `VERDICT: APPROVED` is printed to stdout.

### Step 4: Verify RESULT=clean in reviewer loop output (AC-1, AC-2)

**Maps to**: AC-1 and AC-2

1. With `claude-code-action` in `.ai-dev-workflow.yaml` `platforms`
2. Run against the test PR:
   ```bash
   scripts/development-workflow/pr-review-loop.sh <pr_number>
   ```
3. Confirm the output contains:
   ```
   RESULT=clean
   PLATFORM=claude-code-action
   PR_NUMBER=<pr_number>
   BRANCH=<branch>
   FIX_AGENT=<agent>
   COMMENT_COUNT=0
   BLOCKING_COUNT=0
   SUGGESTION_COUNT=0
   ```

**Expected result**: All nine key-value pairs are present and correct.

### Step 5: Verify pre-existing thread detection skips dispatch (AC-3)

**Maps to**: AC-3 — `RESULT=needs_fixes` without new dispatch when bot already has unresolved threads

1. Using the GitHub API or test fixture, ensure the Claude Code Action bot has at least one unresolved review thread on the test PR
2. Run:
   ```bash
   scripts/development-workflow/pr-review-loop.sh <pr_number> --platform claude-code-action
   ```
3. Confirm no new Actions workflow run is triggered (verify by checking:
   ```bash
   gh api repos/<owner>/<repo>/actions/runs
   ```
   No new run should appear after the loop call)
4. Confirm the output contains `RESULT=needs_fixes`, `REASON=existing_findings`, and `BLOCKING_COUNT` equal to the count of pre-existing unresolved threads

**Expected result**: Loop exits with `RESULT=needs_fixes` without dispatching a new workflow run.

### Step 6: Verify timeout result (AC-5)

**Maps to**: AC-5 — `RESULT=escalate`, `REASON=timeout` when run does not complete in time

1. Run against a test PR with intentionally too short timeout:
   ```bash
   scripts/development-workflow/claude-code-action-reviewer.sh <pr_number> <owner> <repo> \
     --max-wait 1 --poll-interval 1
   ```
2. Confirm exit code is 2 and `VERDICT: TIMED_OUT` appears in output
3. When called via `pr-review-loop.sh`, confirm `RESULT=escalate` and `REASON=timeout` are emitted

**Expected result**: Exit code 2; loop emits `RESULT=escalate`, `REASON=timeout`.

### Step 7: Verify escalate result when workflow file is absent (AC-6)

**Maps to**: AC-6 — `RESULT=escalate`, `REASON=timeout` when workflow file cannot be dispatched

Both unavailable (workflow file absent, dispatch error) and actual run timeout map to exit code 2 from the reviewer script. `run_claude_code_action_review()` maps exit 2 to `RESULT=escalate, REASON=timeout` canonically.

1. Run against a repository that does NOT have the configured workflow file (or use a deliberate typo for `--workflow-file`):
   ```bash
   scripts/development-workflow/claude-code-action-reviewer.sh <pr_number> <owner> <repo> \
     --workflow-file nonexistent-workflow.yml
   ```
2. Confirm exit code is 2 and `VERDICT: TIMED_OUT` appears in output
3. When called via `pr-review-loop.sh`, confirm `RESULT=escalate` and `REASON=timeout` are emitted

**Expected result**: Exit code 2; loop emits `RESULT=escalate`, `REASON=timeout`.

### Step 8: Verify configurable bot login (AC-7)

**Maps to**: AC-7 — `CLAUDE_CODE_ACTION_BOT_LOGIN` overrides default bot login

1. Run with a custom bot login:
   ```bash
   CLAUDE_CODE_ACTION_BOT_LOGIN="my-custom-claude-bot[bot]" \
     scripts/development-workflow/pr-review-loop.sh <pr_number> --platform claude-code-action
   ```
2. Confirm the thread check uses `my-custom-claude-bot` (without `[bot]` suffix) for GraphQL matching
3. Confirm in a shell:
   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   bot_login_for_platform claude-code-action
   ```
   Returns `my-custom-claude-bot[bot]`

**Expected result**: The custom bot login is used throughout, not the default `claude[bot]`.

### Step 9: Verify phase-after-clean behavior (AC-8)

**Maps to**: AC-8 — platform is skipped until pre-clean platforms report clean

1. Configure `.ai-dev-workflow.yaml` with:
   ```yaml
   platforms:
     - pr-agent
   phase_after_clean:
     - claude-code-action
   ```
2. Run against a PR where `pr-agent` is still reporting `needs_fixes`:
   ```bash
   scripts/development-workflow/pr-review-loop.sh <pr_number>
   ```
3. Confirm `PHASE_AFTER_CLEAN_STARTED=0` appears in output and `claude-code-action` is not invoked

**Expected result**: `claude-code-action` is not triggered until `pr-agent` clears.

### Step 10: Verify kv output format matches codex-github (AC-9)

**Maps to**: AC-9 — key-value output format is identical to `codex-github`

1. Run with `--platform claude-code-action` against a clean PR and capture output:
   ```bash
   scripts/development-workflow/pr-review-loop.sh <pr_number> --platform claude-code-action
   ```
2. Run with `--platform codex-github` against the same clean PR and capture output (or a clean codex-github run from a prior test):
   ```bash
   scripts/development-workflow/pr-review-loop.sh <pr_number> --platform codex-github
   ```
3. Compare the key names in both outputs

**Expected result**: Both platform outputs contain exactly: `RESULT`, `PLATFORM`, `PR_NUMBER`, `BRANCH`, `FIX_AGENT`, `COMMENT_COUNT`, `BLOCKING_COUNT`, `SUGGESTION_COUNT`. No extra or missing keys in the `claude-code-action` clean output.

---

## Assertions Checklist

- [ ] AC-1: `claude-code-action` in `review.platforms` causes `pr-review-loop.sh` to invoke the Claude Code Action review and emit `PLATFORM=claude-code-action` in output
- [ ] AC-2: When no blocking threads exist and the Actions run succeeds with no new blocking threads, `RESULT=clean` is emitted
- [ ] AC-3: When the bot has existing unresolved threads, `RESULT=needs_fixes` is emitted with correct `BLOCKING_COUNT` and no new dispatch is triggered
- [ ] AC-4: When the Actions run completes and the bot posts new blocking threads, `RESULT=needs_fixes` and correct `BLOCKING_COUNT` are emitted
- [ ] AC-5: When the Actions run times out, `RESULT=escalate` and `REASON=timeout` are emitted
- [ ] AC-6: When the workflow cannot be dispatched (file absent), `RESULT=escalate` and `REASON=timeout` are emitted
- [ ] AC-7: `CLAUDE_CODE_ACTION_BOT_LOGIN` env var overrides the bot login used for thread identification
- [ ] AC-8: When `claude-code-action` is in `phase_after_clean`, it is skipped until pre-clean platforms are clean
- [ ] AC-9: Key-value output keys match those of the `codex-github` platform exactly

---

## Seed Data Reference

Not applicable. No database or seed data changes. Requires a GitHub repository with a configured Claude Code Action GHA workflow for live testing.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Dispatch returns 404 | Workflow file not found at the expected path | Check `--workflow-file` value matches the actual `.github/workflows/` filename |
| Dispatch returns 422 | `pr_number` input not defined in the workflow's `on.workflow_dispatch.inputs` | Add `pr_number` input to the workflow file |
| Script exits 2 immediately | `gh` CLI not authenticated or lacks `actions:write` scope | Run `gh auth login` with correct scopes |
| Polling loop never exits | Actions run stuck in `queued` or `in_progress` | Increase `--max-wait` or investigate the GHA runner |
| Wrong bot threads counted | Bot login mismatch | Set `CLAUDE_CODE_ACTION_BOT_LOGIN` to the exact GitHub login of the bot account (including `[bot]` suffix if applicable) |

---

## Known Limitations

- Live end-to-end testing requires a functioning Claude Code Action GitHub Actions workflow in the test repository. Partial testing is possible by using `HARNESS_MODE=1` to source `pr-review-loop.sh` and unit-test individual functions.
- The smoke test for AC-4 (bot posts new blocking threads after a successful run) requires a specially configured test workflow that posts a blocking review; this may need to be simulated via a manual test fixture.
