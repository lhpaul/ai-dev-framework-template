# Smoke Test Runbook: CodeRabbit SUCCESS Commit-Status Fallback

**Feature**: fix(pr-review-loop): treat existing CodeRabbit SUCCESS status as clean during rate-limit wait
**Spec**: [docs/specs/developments/20260416120000_coderabbit-success-fallback/1_coderabbit-success-fallback_specs.md](../../specs/developments/20260416120000_coderabbit-success-fallback/1_coderabbit-success-fallback_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI is authenticated with a token that has `repo` scope
- [ ] `jq` is installed and on `$PATH`
- [ ] The repository has CodeRabbit configured (the `coderabbitai[bot]` has previously posted reviews on PRs)
- [ ] You have access to a test PR or can create one on a feature branch

---

## Test Data

| Item | Value |
|---|---|
| Script under test | `scripts/development-workflow/pr-review-loop.sh` |
| Function under test | `run_coderabbit_review()` |
| Environment variable (poll interval) | `POLL_INTERVAL` (default 120s) |
| Environment variable (max wait) | `MAX_WAIT` (default 1200s) |
| Environment variable (rate-limit retries) | `CODERABBIT_RATE_LIMIT_MAX_RETRIES` (default 2) |

> **Note**: These smoke tests require shell-level inspection of the script logic and controlled API conditions. Full end-to-end testing requires an actual PR with a CodeRabbit SUCCESS commit-status. Steps below describe both a live test path (preferred) and a code-inspection verification path (fallback).

---

## Smoke Test Steps

### Step 1: Verify the fallback code path exists in the script

**Maps to**: All acceptance criteria (structural prerequisite)

1. Open `scripts/development-workflow/pr-review-loop.sh`.
2. Locate the `run_coderabbit_review()` function.
3. Inside the `if [ "$elapsed" -ge "$max_wait" ]` block, within the `if [ "$coderabbit_any_activity" -eq 0 ]` guard, verify a block that:
   - Calls `gh api "repos/$repo/commits/$head_sha/statuses"` (paginated).
   - Filters with `jq` for entries where `.context` matches `coderabbit` (case-insensitive) and `.state == "success"`.
   - On a positive match: emits `RESULT=clean` and `REASON=coderabbit_status_success_fallback`, then returns 0.
4. Verify this block appears **before** the stale-findings query (`stale_comments`).

**Expected result**: The fallback block is present at the correct location, before stale-findings recovery.

---

### Step 2: Verify REASON output key-value format

**Maps to**: Acceptance Criterion 4 — `REASON=coderabbit_status_success_fallback` key-value is in script output.

1. Search the fallback block for the `print_kv REASON coderabbit_status_success_fallback` call.
2. Confirm `print_kv` is called with both `RESULT clean` and `REASON coderabbit_status_success_fallback` in the same early-return path.

**Expected result**: Both key-value calls are present and use the exact values `clean` and `coderabbit_status_success_fallback`.

---

### Step 3: Verify Greptile and Devin handlers are untouched

**Maps to**: Acceptance Criterion 5 — Greptile and Devin platform handlers are unaffected.

1. Search `run_greptile_review()` for any reference to `commit-status`, `statuses`, or `coderabbit_status_success_fallback`.
2. Search `run_devin_review()` for the same.

**Expected result**: Neither `run_greptile_review()` nor `run_devin_review()` contain any reference to the new fallback logic.

---

### Step 4: Live test — SUCCESS commit-status present, retry budget exhausted, no blocking comments (Use Case 1)

**Maps to**: Acceptance Criterion 1

> This step requires a real PR where CodeRabbit has posted a `SUCCESS` commit-status but no inline review comment for the current HEAD. This scenario naturally occurs when CodeRabbit completes review via a status check rather than an inline comment (e.g., after a rate-limit window resets and re-review is triggered via API rather than comment).

1. Identify or create a PR where:
   - The current HEAD SHA has a CodeRabbit commit-status with `state: success`. Verify with:
     ```bash
     HEAD_SHA=$(gh pr view <PR_NUMBER> --json headRefOid --jq '.headRefOid')
     gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/statuses" \
       | jq '[.[] | select((.context | ascii_downcase | test("coderabbit")) and .state == "success")] | length'
     ```
     The output should be `> 0`.
   - No blocking CodeRabbit inline comments exist on the current HEAD.
2. Run the script with a very short `max_wait` to simulate budget exhaustion and no polling activity (set `CODERABBIT_RATE_LIMIT_MAX_RETRIES=0` to skip rate-limit retries):
   ```bash
   CODERABBIT_RATE_LIMIT_MAX_RETRIES=0 \
     ./scripts/development-workflow/pr-review-loop.sh <PR_NUMBER> \
       --branch <branch-name> \
       --platform coderabbit \
       --poll-interval 1 \
       --max-wait 2
   ```
3. Capture the output.

**Expected result**:
- `RESULT=clean`
- `REASON=coderabbit_status_success_fallback`
- Script exits with code `0`

---

### Step 5: Live test — No SUCCESS commit-status, retry budget exhausted (Use Case 2)

**Maps to**: Acceptance Criterion 2

1. Identify or create a PR where the current HEAD SHA has NO CodeRabbit commit-status with `state: success`. Verify with:
   ```bash
   HEAD_SHA=$(gh pr view <PR_NUMBER> --json headRefOid --jq '.headRefOid')
   gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/statuses" \
     | jq '[.[] | select((.context | ascii_downcase | test("coderabbit")) and .state == "success")] | length'
   ```
   The output should be `0`.
2. Run the script with a very short `max_wait`:
   ```bash
   CODERABBIT_RATE_LIMIT_MAX_RETRIES=0 \
     ./scripts/development-workflow/pr-review-loop.sh <PR_NUMBER> \
       --branch <branch-name> \
       --platform coderabbit \
       --poll-interval 1 \
       --max-wait 2
   ```
3. Capture the output.

**Expected result**:
- Script does NOT output `REASON=coderabbit_status_success_fallback`
- Behavior falls through to existing stale-findings recovery: `RESULT=skipped` with `REASON=no_review` (if no stale blocking comments) or `RESULT=needs_fixes` with `REASON=stale_findings` (if stale blocking comments exist)
- Script exits with code `0` (skipped) or `1` (needs_fixes)

---

### Step 6: Live test — Blocking inline comments present on current HEAD even with SUCCESS commit-status (Acceptance Criterion 3)

**Maps to**: Acceptance Criterion 3

> The most practical way to test this scenario is with blocking inline comments posted **after** the HEAD commit timestamp (i.e., truly "on the current HEAD" from the script's perspective). In this case, Phase 1 of `run_coderabbit_review()` (`pr-review-loop.sh` lines 831–895) intercepts them before the polling loop starts, and the fallback is never reached.

1. On the same PR from Step 4 (SUCCESS commit-status present), verify that there IS at least one unresolved blocking CodeRabbit inline comment (severity 🔴 Critical or 🟠 Major) whose `created_at` timestamp is **after** the HEAD commit's committer timestamp (`since_iso`).
2. Run the script with a very short `max_wait`:
   ```bash
   CODERABBIT_RATE_LIMIT_MAX_RETRIES=0 \
     ./scripts/development-workflow/pr-review-loop.sh <PR_NUMBER> \
       --branch <branch-name> \
       --platform coderabbit \
       --poll-interval 1 \
       --max-wait 2
   ```
3. Capture the output.

**Expected result**:
- `RESULT=needs_fixes`
- `REASON=existing_findings` (Phase 1 intercepts the blocking comment before the polling loop starts)
- `BLOCKING_COUNT` is greater than 0
- Script does NOT output `REASON=coderabbit_status_success_fallback` (the fallback is never reached when Phase 1 finds blocking comments)
- Script exits with code `1`

> Note: Phase 1 (`existing-blocking-findings` check) runs before the polling loop and before the SUCCESS-status fallback. When blocking inline comments are present on the current HEAD, Phase 1 returns `REASON=existing_findings` immediately. The SUCCESS commit-status fallback is only reachable when `coderabbit_any_activity -eq 0` after the full polling loop completes — a condition that cannot occur when Phase 1 already found blocking findings and returned early.

---

### Step 7: Verify protocol 90 Step 3.7 is updated

**Maps to**: Acceptance Criterion 6

1. Open `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Locate Step 3.7.
3. Verify the section now describes the SUCCESS commit-status fallback behavior: when retry budget is exhausted and no inline review was posted, the script checks for a CodeRabbit `SUCCESS` commit-status. If found (and no blocking inline comments), it returns `clean` with `REASON=coderabbit_status_success_fallback`.

**Expected result**: Step 3.7 accurately describes both the existing rate-limit retry behavior and the new SUCCESS status fallback path. The note about manually posting `@coderabbitai review` is retained as an optional human action.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: When retry budget exhausted and HEAD SHA has CodeRabbit `SUCCESS` commit-status and no blocking inline comments → `RESULT=clean`, `REASON=coderabbit_status_success_fallback`, exit 0
- [ ] AC2: When retry budget exhausted and NO CodeRabbit `SUCCESS` commit-status → behavior unchanged; falls through to stale-findings/skipped/escalate paths
- [ ] AC3: When blocking CodeRabbit inline comments (Critical or Major) are present → fallback does not apply; `RESULT=needs_fixes` regardless of commit-status
- [ ] AC4: `REASON=coderabbit_status_success_fallback` key-value is present in script output when fallback triggers
- [ ] AC5: Greptile and Devin platform handlers contain no references to the new fallback logic
- [ ] AC6: `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 3.7 documents the new fallback behavior

---

## Seed Data Reference

| Entity | Scenario | How to load |
|---|---|---|
| N/A | Shell script test — no application seed data required | — |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Script still returns `skipped (no_review)` even with SUCCESS commit-status | Fallback not inserted before stale-findings block | Verify insertion point is before the stale-findings `stale_comments` query |
| `jq` filter returns 0 even when status exists | Context name mismatch | Check the actual `.context` value in the API response and update the `test("coderabbit")` filter if needed |
| `gh api` returns paginated results that miss the status | Missing `--paginate` flag | Confirm `--paginate` is included in the API call |
| Phase 1 returns `needs_fixes` before fallback runs | Blocking comments exist from a prior commit and are being picked up | Verify `since_iso` is correctly set to the HEAD commit timestamp |

---

## Known Limitations

- Live testing of the full fallback path requires a PR in a CodeRabbit rate-limited state, which is difficult to reproduce on demand. Code-inspection verification (Steps 1-3 and 7) provides deterministic coverage for the structural requirements.
- The `--max-wait 2` / `--poll-interval 1` workaround in Steps 4-6 approximates retry budget exhaustion but skips the actual polling loop. In production, the fallback is only reached after the full `max_wait` (default 20 minutes).
