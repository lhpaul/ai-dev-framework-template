# Smoke Test Runbook: Codex GitHub Integration Reviewer Path

**Feature**: Codex GitHub Integration Reviewer Path (issue #309)
**Spec**: [`docs/specs/developments/20260427222115_309-codex-github-integration-reviewer/1_309-codex-github-integration-reviewer_specs.md`](../../specs/developments/20260427222115_309-codex-github-integration-reviewer/1_309-codex-github-integration-reviewer_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR has been merged to `develop`
- [ ] `gh` CLI is authenticated with access to the test repository
- [ ] The Codex GitHub App is installed on the test repository (required for Steps 2 and 3; not required for timeout and skip scenarios in Steps 4 and 5)
- [ ] A test draft PR is open on a workflow branch (e.g., a `spec/*` or `implementation-plan/*` branch targeting `develop`)
- [ ] `.ai-dev-workflow.yaml` in the test repo lists `codex-github` in `review.internal_reviewers`

---

## Test Data

| Item | Value |
|---|---|
| Test PR | A draft PR on a `spec/*` or `implementation-plan/*` branch |
| Test repo owner | `<owner>` — the GitHub org or user owning the test repo |
| Test repo name | `<repo>` — the name of the test repo |
| Default trigger phrase | `@codex review` |
| Default bot login | `codex-ai[bot]` (verify actual login via GitHub App settings) |
| Script path | `scripts/development-workflow/codex-github-reviewer.sh` |

---

## Smoke Test Steps

### Step 1: Verify script exists and is executable

- Run: `ls -l scripts/development-workflow/codex-github-reviewer.sh`
- Verify: file exists and has execute permission (`-rwxr-xr-x` or similar)
- Run: `bash -n scripts/development-workflow/codex-github-reviewer.sh`
- Verify: exits with code 0 (no syntax errors)

---

### Step 2: Verify reachability classification — `codex-github` marked reachable from all contexts

**Maps to**: Acceptance Criterion 1 (AC-1)

- Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- Locate the Step 7a "Reachability classification table"
- Verify: the table includes a `codex-github reachable?` column (or equivalent block)
- Verify: `codex-github` is marked `Yes` for all runner contexts: Claude Code (direct), Claude Code subagent, Codex runner, and direct human shell

**Expected result**: Every row in the classification table shows `Yes` for `codex-github`.

---

### Step 3: Happy path — Codex GitHub App responds with approval

**Maps to**: AC-2, AC-3, AC-7 (Use Case 1)

> Prerequisites: The Codex GitHub App must be installed and responsive on the test repository.

1. Open a draft PR on a `spec/*` or `implementation-plan/*` branch in the test repository
2. Note the current HEAD commit SHA: `gh pr view <pr_number> --json headRefOid --jq '.headRefOid'`
3. Run the script directly: `scripts/development-workflow/codex-github-reviewer.sh <pr_number> <owner> <repo>`
4. Verify: a trigger comment appears in the PR comment thread containing `@codex review` and the commit SHA
5. Wait for the Codex GitHub App to respond (may take up to 5 minutes)
6. Verify: the script exits with code 0 and prints `VERDICT: APPROVED`
7. Verify: the PR now has both the trigger comment and the Codex bot response comment visible in the comment thread

**Expected result**: Script exits 0, APPROVED verdict printed, trigger comment and bot response visible in PR.

---

### Step 4: Timeout path — Codex bot does not respond

**Maps to**: AC-5, Use Case 3

> This step uses a reduced `--max-wait` to simulate a timeout without waiting 5 minutes.

1. Open or reuse a draft PR in a test repository where the Codex GitHub App will NOT respond (either App not installed, or use a private test repo that the App cannot access)
2. Run: `scripts/development-workflow/codex-github-reviewer.sh <pr_number> <owner> <repo> --max-wait 60 --poll-interval 15`
3. Wait up to 60 seconds for the script to time out
4. Verify: script exits with code 2 and prints `VERDICT: TIMED_OUT`

**Expected result**: Script exits 2 with TIMED_OUT message within the configured `--max-wait` window.

---

### Step 5: Idempotency guard — no duplicate trigger comments posted

**Maps to**: AC-6, BR-10

1. Use the same PR and commit SHA from Step 3 (or Step 4) — a trigger comment for that SHA already exists in the PR
2. Run the script again: `scripts/development-workflow/codex-github-reviewer.sh <pr_number> <owner> <repo>`
3. Verify: the script prints an `INFO: trigger comment already posted for commit <sha> — skipping duplicate post` message
4. Verify: no second trigger comment appears in the PR (check the comment count before and after running the script)

**Expected result**: Script detects the existing trigger comment and skips posting, with no duplicate comment created.

---

### Step 6: Verify Step 7a summary comment includes `codex-github`

**Maps to**: AC-7

1. Run a full Step 7a cycle with `codex-github` in `internal_reviewers` (either simulate or use the protocol manually on a draft PR)
2. After all reviewers return `APPROVED`, locate the Step 7a summary comment posted to the PR
3. Verify: the summary comment lists `codex-github` in the effective reviewer set (when it produced a verdict) or in the skipped/timed-out list (when it timed out)

**Expected result**: Step 7a summary comment accurately reflects `codex-github` verdict.

---

### Step 7: Verify documentation updates

**Maps to**: AC-8 (workflow documentation), AC-9 (configuration manifest), AC-10 (agent guidance)

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and confirm `codex-github` appears in:
   - The Step 7a reachability classification table (reachable from all runner contexts)
   - The Step 7a reviewer dispatch map (pointing to `codex-github-reviewer.sh`)
   - The local override example JSON
2. Open `.ai-dev-workflow.yaml` and confirm the `internal_reviewers` comment block documents `codex-github` as a supported value with its configuration keys
3. Open `.claude/agents/item-orchestrator.md` and confirm it describes the `codex-github` dispatch path
4. Open `.cursor/agents/item-orchestrator.md` and confirm the same update is present

**Expected result**: All four files updated with `codex-github` documentation.

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met
- Clean up any test draft PRs opened solely for this smoke test

---

## Assertions Checklist

- [ ] `scripts/development-workflow/codex-github-reviewer.sh` exists, is executable, and has no syntax errors
- [ ] `codex-github` is listed as reachable from all runner contexts in Protocol 91 Step 7a reachability classification table
- [ ] Running the script against an active PR with the Codex GitHub App installed posts a trigger comment containing the trigger phrase and commit SHA
- [ ] When the Codex bot responds with no blocking findings, the script exits 0 (`APPROVED`)
- [ ] When the Codex bot does not respond within `--max-wait`, the script exits 2 (`TIMED_OUT`)
- [ ] Re-running the script on a PR where a trigger comment for the current SHA already exists does not post a second trigger comment
- [ ] The Step 7a summary comment includes `codex-github` in the effective reviewer set or skipped list
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` documents `codex-github` in the reachability table and reviewer dispatch map
- [ ] `.ai-dev-workflow.yaml` documents `codex-github` as a supported `internal_reviewers` value
- [ ] `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` document the `codex-github` dispatch path

---

## Seed Data Reference

Not applicable — this feature has no runtime data requirements. Test data is a live draft PR in a repository with the Codex GitHub App installed.

| Entity | Scenario | How to load |
|---|---|---|
| Draft PR | A PR in draft state on a `spec/*` or `implementation-plan/*` branch | Open manually via `gh pr create --draft` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Script exits with "gh CLI not authenticated" | `gh` CLI is not logged in | Run `gh auth login` and retry |
| Script exits 2 (TIMED_OUT) when App should respond | Bot login name mismatch — default `codex-ai[bot]` does not match actual app login | Check the actual bot account login via the GitHub App settings; pass `--bot-login <actual-login>` |
| Trigger comment posted but bot never responds | Codex GitHub App not installed or not configured for the repo | Verify App installation in GitHub Settings → Apps; confirm the app has permissions to read/write PR comments |
| Duplicate trigger comments appear on re-run | Idempotency guard broken — SHA matching regex not working | Inspect the trigger comment body format and ensure the SHA is embedded as documented |
| Script syntax error on `bash -n` | Shell compatibility issue | Ensure the shebang is `#!/usr/bin/env bash` and the script uses only POSIX-compatible constructs |

---

## Known Limitations

- The smoke test for the "changes requested" path (Use Case 2 / AC-4) requires a PR with actual issues that the Codex bot would flag. This is difficult to arrange in a controlled test environment. Verify the `NEEDS_REVISION` path via code inspection of the verdict-parsing logic in `codex-github-reviewer.sh`.
- The exact bot login name (`codex-ai[bot]` default) must be verified against the actual Codex GitHub App installation before production use. The default is a best-guess; operators must confirm via GitHub App settings.
