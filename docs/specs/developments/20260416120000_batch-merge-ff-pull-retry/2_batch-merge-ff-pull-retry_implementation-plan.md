# batch-merge ff-pull transient failure retry — Implementation Plan

**Spec**: [`1_batch-merge-ff-pull-retry_specs.md`](./1_batch-merge-ff-pull-retry_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/batch-merge-ff-pull-retry.smoke-test.md`](../../../testing/workflow/batch-merge-ff-pull-retry.smoke-test.md)

---

## Summary

**Approach**: Wrap the existing `git pull --ff-only origin "$TARGET_BASE"` call in `batch-merge.sh`'s `cmd_merge` with a one-shot retry: if the first attempt fails, sleep 2 seconds, run `git fetch origin "$TARGET_BASE"`, then retry `git pull --ff-only`. Only if the retry also fails is `merge_die` called. No changes to discovery, conflict handling, or any other section.

**Estimated complexity**: S

**Rationale**: The change is confined to exactly three lines in one function of a single shell script. The logic is straightforward conditional branching with no new state, flags, or interfaces introduced.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] `scripts/development-workflow/batch-merge.sh` — in `cmd_merge`, replace the single-attempt `git pull --ff-only` + `merge_die` call (lines 308–309) with a two-attempt sequence:
  1. Attempt `git pull --ff-only origin "$TARGET_BASE"` (suppress stdout/stderr as today).
  2. If it succeeds, continue as before.
  3. If it fails, print a diagnostic message to stderr (e.g., `"ff-pull failed; retrying after 2s..."`), sleep 2, run `git fetch origin "$TARGET_BASE"`, then retry `git pull --ff-only origin "$TARGET_BASE"`.
  4. If the retry succeeds, continue.
  5. If the retry fails, call `merge_die "Could not fast-forward local '${TARGET_BASE}' from origin — resolve divergence manually"` (same message as today).

  The fetch before the retry must use `"$TARGET_BASE"` (the same variable already in scope), not a hard-coded `develop`, so the logic is correct if `TARGET_BASE` is ever changed at the top of the file.

---

## Testing Strategy

**Test types**: Manual smoke test (bash script; no automated test suite in the repository)

**Key scenarios to test**:

1. Transient failure recovery — first `git pull --ff-only` fails, retry succeeds → `MERGE_RESULT=clean` emitted, no human intervention. *(Maps to Acceptance Criterion 1)*
2. Genuine divergence — both attempts fail → `MERGE_RESULT=failed` + `ERROR_MESSAGE` emitted, same structured output as before. *(Maps to Acceptance Criterion 2)*
3. Diagnostic message present — when a retry is attempted, stderr contains a "retrying" message. *(Maps to Acceptance Criterion 3)*
4. No regression — existing call paths (clean first attempt, conflict, non-conflict non-ff failure) behave identically to before the change. *(Maps to Acceptance Criterion 4)*
5. Change isolation — discovery mode, conflict classification, and post-merge logic are unmodified. *(Maps to Acceptance Criterion 5)*

**Smoke test runbook**: [`docs/testing/workflow/batch-merge-ff-pull-retry.smoke-test.md`](../../../testing/workflow/batch-merge-ff-pull-retry.smoke-test.md)

---

## Seed Data

N/A — `batch-merge.sh` is a standalone bash script that interacts with git and the GitHub API. No database or application seed data is required.

---

## Documentation Updates

None — this change is a self-contained bug fix in a single script. It does not alter any user-facing workflow step, introduce a new option, change the output contract, or affect any pattern described in `docs/`. The script's own header comment does not describe the ff-pull internals and does not need updating.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Retry masks a genuine but intermittent divergence | Low | Med | The retry only changes the result if `git pull --ff-only` succeeds on the second attempt — a genuine divergence will fail both times and still emit `MERGE_RESULT=failed` exactly as before. |
| 2-second sleep adds noticeable latency | Low | Low | The sleep only fires on the failure path. A clean first attempt (the common case) has zero added latency. Even in the worst case the delay is a fixed 2 seconds. |
| Variable `TARGET_BASE` referenced incorrectly | Low | Med | Use `"$TARGET_BASE"` consistently in both the fetch and the pull; this is already the pattern in the surrounding code. |

---

## Code Samples

```bash
# Illustrative — adapt during implementation

# Current code (lines 308–309):
git pull --ff-only origin "$TARGET_BASE" >/dev/null 2>&1 || \
  merge_die "Could not fast-forward local '${TARGET_BASE}' from origin — resolve divergence manually"

# Replacement:
if ! git pull --ff-only origin "$TARGET_BASE" >/dev/null 2>&1; then
  echo "ff-pull failed on first attempt; retrying after 2s (transient stale-ref recovery)..." >&2
  sleep 2
  git fetch origin "$TARGET_BASE" >/dev/null 2>&1 || true
  git pull --ff-only origin "$TARGET_BASE" >/dev/null 2>&1 || \
    merge_die "Could not fast-forward local '${TARGET_BASE}' from origin — resolve divergence manually"
fi
```

---

## Implementation Order

1. Read `scripts/development-workflow/batch-merge.sh` (specifically `cmd_merge`) to confirm the exact line numbers and surrounding context before editing.
2. Replace the single-attempt ff-pull block with the two-attempt sequence from the Code Samples section above.
3. Verify the script still passes `shellcheck` (run `shellcheck scripts/development-workflow/batch-merge.sh`).
4. Run the smoke test runbook manually to validate both the retry-success and retry-failure scenarios.
5. Update CHANGELOG.md — add an entry under `[Unreleased]` for this fix.
