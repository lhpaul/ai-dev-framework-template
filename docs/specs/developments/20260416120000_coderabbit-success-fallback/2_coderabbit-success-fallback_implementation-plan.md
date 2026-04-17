# CodeRabbit SUCCESS Commit-Status Fallback — Implementation Plan

**Spec**: [1_coderabbit-success-fallback_specs.md](./1_coderabbit-success-fallback_specs.md)
**Smoke test runbook**: [docs/testing/workflow/coderabbit-success-fallback.smoke-test.md](../../../testing/workflow/coderabbit-success-fallback.smoke-test.md)

---

## Summary

**Approach**: Modify `run_coderabbit_review()` in `scripts/development-workflow/pr-review-loop.sh` to check the GitHub commit-status contexts for the current HEAD SHA after the retry budget is exhausted but before the stale-findings recovery path runs. If a CodeRabbit commit-status context with `state: SUCCESS` is found and no blocking inline comments exist for the current HEAD, the function returns `clean` with `REASON=coderabbit_status_success_fallback` instead of falling through to stale-findings or escalation. Also update `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 3.7 to document this fallback.

**Estimated complexity**: S

**Rationale**: The change is limited to a single insertion point in `run_coderabbit_review()` — a new code block inserted between the rate-limit retry exhaustion check and the existing stale-findings recovery. It requires one new GitHub API call (`/commits/{sha}/statuses`) and two output key-value pairs. No new files are created; no other platform handlers are touched.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Scripts / Shell

- [ ] In `scripts/development-workflow/pr-review-loop.sh`, within `run_coderabbit_review()`:
  - Add a new local variable `coderabbit_success_status_found=0` in the local declarations block at the top of the function.
  - After the rate-limit retry block (the `if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_rate_limit_retries" -lt "$coderabbit_rate_limit_max_retries" ]` guard) and once `elapsed >= max_wait`, insert a new fallback check block immediately before the existing `stale_count` / stale-findings block:
    1. Query `GET /repos/{repo}/commits/{head_sha}/statuses` (paginated) via `gh api`.
    2. Filter for entries where `.context` contains `coderabbit` (case-insensitive) and `.state == "success"`.
    3. If at least one such entry is found, set `coderabbit_success_status_found=1`.
  - If `coderabbit_success_status_found=1`, skip the stale-findings block entirely and emit:
    ```
    RESULT=clean
    REASON=coderabbit_status_success_fallback
    PLATFORM=coderabbit
    PR_NUMBER=<pr_number>
    BRANCH=<branch_name>
    REVIEW_COMMENT_ID=
    FIX_AGENT=<reviewer_for_branch>
    COMMENT_COUNT=0
    BLOCKING_COUNT=0
    SUGGESTION_COUNT=0
    ```
    Then `return 0`.
  - The stale-findings block and the existing `skipped (no_review)` / `escalate (timeout)` paths are only reached when `coderabbit_success_status_found=0`.
  - The `coderabbit_success_status_found` check must only apply when `coderabbit_any_activity -eq 0`. When `coderabbit_any_activity -eq 1` (a real review was posted), the existing Phase 3 result collection path runs as-is.

### Documentation

- [ ] In `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`, update Step 3.7 to document the new fallback:
  - Describe the new behavior: when all retry budget is exhausted and no CodeRabbit review comment was posted, the script checks for a CodeRabbit commit-status context with `state: SUCCESS`. If found, the result is `clean` with `REASON=coderabbit_status_success_fallback`.
  - Remove the statement "The PR can still advance to `ready-for-human-review`" that currently applies only to the stale/skipped path — that statement remains valid but the new fallback path should be described first.
  - Keep the note about manually posting `@coderabbitai review` as an optional step for human reviewers.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. SUCCESS commit-status present, retry budget exhausted, no blocking inline comments → `RESULT=clean, REASON=coderabbit_status_success_fallback` (maps to Acceptance Criterion 1)
2. No SUCCESS commit-status, retry budget exhausted → fallthrough to existing stale/skipped/escalate paths, behavior unchanged (maps to Acceptance Criterion 2)
3. Blocking CodeRabbit inline comments present even when SUCCESS status exists → `RESULT=needs_fixes` (maps to Acceptance Criterion 3)
4. `REASON=coderabbit_status_success_fallback` appears in script output when fallback is triggered (maps to Acceptance Criterion 4)
5. Greptile and Devin handlers are unaffected (maps to Acceptance Criterion 5)

**Smoke test runbook**: [`docs/testing/workflow/coderabbit-success-fallback.smoke-test.md`](../../../testing/workflow/coderabbit-success-fallback.smoke-test.md)

---

## Seed Data

| Entity | Values / Scenario | File |
|---|---|---|
| N/A — shell script change; no application seed data required | — | — |

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — Update Step 3.7 as described in the Layer-by-Layer Changes section above. This is included in-scope per Acceptance Criterion 6.

No other project docs (`docs/project/`, `AGENTS.md`, `docs/best-practices/`) are affected by this fix — it is entirely internal to the `pr-review-loop.sh` script and its corresponding orchestration protocol note.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GitHub commit-statuses API returns paginated results and the CodeRabbit entry is on a later page | Low | Medium | Use `--paginate` flag on `gh api` to fetch all pages before filtering |
| Context name for CodeRabbit commit-status changes over time | Low | Medium | Filter with case-insensitive substring match (`coderabbit`) rather than exact context name; document the assumption in an inline comment |
| `state: success` is returned for a stale status from a prior HEAD (not the current HEAD) | Low | High | The API call is scoped to `head_sha` — GitHub statuses endpoint is keyed by commit SHA, so only statuses for that exact SHA are returned; no additional time filter is needed |
| New fallback bypasses stale-findings detection | Low | High | The fallback only activates when `coderabbit_any_activity -eq 0`; when activity was detected (Phase 2 loop exited normally), Phase 3 runs as-is. The stale-findings block is only skipped when the SUCCESS status fallback fires. |

---

## Code Samples

> Illustrative — adapt during implementation.

```bash
# Inside run_coderabbit_review(), after the rate-limit retry block,
# at the start of the `if [ "$elapsed" -ge "$max_wait" ]` block,
# before the stale-findings check:

if [ "$coderabbit_any_activity" -eq 0 ]; then
  # Check for a CodeRabbit SUCCESS commit-status on the current HEAD SHA
  # before falling through to stale-findings recovery or escalation.
  local coderabbit_success_status_count
  coderabbit_success_status_count="$(
    gh api "repos/$repo/commits/$head_sha/statuses" --paginate \
      | jq '[.[] | select(
            (.context // "" | ascii_downcase | test("coderabbit")) and
            .state == "success"
          )] | length'
  )"
  if [ "${coderabbit_success_status_count:-0}" -gt 0 ]; then
    # SUCCESS commit-status found — treat as clean (Illustrative — adapt during implementation)
    print_kv RESULT clean
    print_kv REASON coderabbit_status_success_fallback
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 0
  fi
  # ... existing stale-findings block follows here ...
fi
```

---

## Implementation Order

1. Read the full `run_coderabbit_review()` function in `scripts/development-workflow/pr-review-loop.sh` and identify the exact insertion point: the `if [ "$elapsed" -ge "$max_wait" ]` block, inside the `if [ "$coderabbit_any_activity" -eq 0 ]` guard, before the stale-findings query.
2. Add `local coderabbit_success_status_found=0` to the local declarations block at the top of `run_coderabbit_review()`.
3. Insert the SUCCESS commit-status fallback block (API query + conditional `return 0`) at the identified location.
4. Update `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 3.7 to document the new fallback.
5. Verify the smoke test runbook scenarios manually or with a dry-run review of the script diff.
6. Update CHANGELOG.md under `[Unreleased]` with the fix entry.
