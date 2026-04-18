# fix(post-merge-cleanup): handle locked Claude worktrees — Implementation Plan

**Spec**: [`1_177-locked-worktree-cleanup_specs.md`](./1_177-locked-worktree-cleanup_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/177-locked-worktree-cleanup.smoke-test.md`](../../../testing/workflow/177-locked-worktree-cleanup.smoke-test.md)

---

## Summary

**Approach**: Wrap the existing `git worktree remove "$WORKTREE_PATH" --force` call in `post-merge-cleanup.sh` with a lock-detection block. If the removal fails with the `fatal: cannot remove a locked working tree` message, the script emits a force-override warning, attempts `git worktree unlock` + `git worktree remove --force`, and falls back to `git worktree remove --force --force` (double-force) if unlock is unavailable or fails. If both remediation paths fail, the script exits non-zero.

**Estimated complexity**: S

**Rationale**: The change is contained entirely within a single shell script, involves no new dependencies, and the logic is a straightforward error-capture-and-retry pattern. No schema, API, UI, or configuration changes are required.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Scripts / Shell

- [ ] `scripts/development-workflow/post-merge-cleanup.sh` — replace the single `git worktree remove "$WORKTREE_PATH" --force` call with a lock-aware removal block (see Implementation Order for exact steps).

No other files require changes. `batch-merge.sh`, `pr-review-loop.sh`, protocol docs, and all other scripts are out of scope per the spec.

---

## Testing Strategy

**Test types**: Smoke (manual shell-level execution against a real git repo with a locked worktree)

**Key scenarios to test**:

1. Locked worktree — script unlocks, removes, and continues (maps to AC 1, AC 2, AC 6)
2. Unlock unavailable — script falls back to double-force and continues (maps to AC 1, AC 2, AC 6)
3. Non-locked worktree — standard single removal succeeds, no warning emitted (maps to AC 3)
4. No worktree for branch — script skips worktree block entirely (maps to AC 4)
5. Both remediation paths fail — script exits non-zero with clear error (maps to AC 5)

**Smoke test runbook**: [`docs/testing/workflow/177-locked-worktree-cleanup.smoke-test.md`](../../../testing/workflow/177-locked-worktree-cleanup.smoke-test.md)

**Regression suite**: None — this repository does not have an automated regression test suite for shell scripts.

---

## Seed Data

None — the smoke test provisions its own temporary git worktree with a manufactured lock.

---

## Documentation Updates

None — this fix is a self-contained script change with no effect on documented architecture, domain model, stack conventions, or project setup. `AGENTS.md`, `docs/project/`, and `docs/best-practices/` do not need updates.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `git worktree remove --force --force` (double-force) not supported on older git | Low | Low | Double-force was introduced in git 2.17; any environment running Claude Code parallel batches will have a recent enough git. If it fails, the script exits non-zero (AC 5), surfacing the error. |
| Legitimate active worktrees accidentally force-removed | Very low | High | The force-override warning (including lock reason) is emitted before any removal attempt, giving the operator a visible audit trail. The script does not distinguish agent vs. human locks; the warning covers both. |
| Issue #184 merge conflict on `post-merge-cleanup.sh` | Medium | Low | The scope here is limited to the worktree-removal block (lines 73–78 in the current file). Issue #184 touches different lines. The batch-merge auto-resolution (protocol 94 Step 4.3) handles any overlap. |

---

## Code Samples

> All samples below are illustrative — adapt during implementation.

### Lock-aware worktree removal block (replaces lines 73–78 in `post-merge-cleanup.sh`)

```bash
# Illustrative — adapt during implementation
WORKTREE_PATH=$(git worktree list --porcelain | grep -B2 "branch refs/heads/$TO_DELETE$" | grep "^worktree " | sed 's/^worktree //' || true)
if [ -n "$WORKTREE_PATH" ]; then
  echo "Worktree '$WORKTREE_PATH' is still using branch '$TO_DELETE'. Removing worktree first..."
  # Capture stderr so we can detect the locked-worktree condition.
  REMOVE_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1) && REMOVE_RC=0 || REMOVE_RC=$?
  if [ $REMOVE_RC -ne 0 ] && echo "$REMOVE_ERR" | grep -q "locked working tree"; then
    # Detect lock reason from git worktree list --porcelain (the "locked" field).
    LOCK_REASON=$(git worktree list --porcelain | grep -A5 "^worktree $WORKTREE_PATH$" | grep "^locked" | sed 's/^locked //' || echo "unknown")
    echo "WARNING: Worktree '$WORKTREE_PATH' is locked (reason: $LOCK_REASON). Force-overriding — if this worktree belongs to an active agent, data may be lost."
    # Primary remediation: unlock then remove.
    if git worktree unlock "$WORKTREE_PATH" 2>/dev/null; then
      git worktree remove "$WORKTREE_PATH" --force
    else
      # Fallback: double-force (bypasses lock without requiring unlock subcommand).
      echo "WARNING: 'git worktree unlock' unavailable or failed; using double-force fallback."
      git worktree remove "$WORKTREE_PATH" --force --force
    fi
  elif [ $REMOVE_RC -ne 0 ]; then
    echo "Error removing worktree '$WORKTREE_PATH': $REMOVE_ERR" >&2
    exit 1
  fi
  echo "Worktree removed."
fi
```

---

## Implementation Order

1. **Read the current worktree-removal block** in `scripts/development-workflow/post-merge-cleanup.sh` (lines 69–78) to confirm exact line numbers and surrounding context before editing.
2. **Replace the `git worktree remove` call** with the lock-aware block shown in Code Samples above. Key mechanics:
   - Capture both stdout and stderr from the first removal attempt using `2>&1` into a variable; check the exit code separately.
   - Match the locked-worktree condition by grepping for `"locked working tree"` in the captured error output.
   - Emit the force-override warning (exact format from the spec's Operational Visibility section) **before** the remediation attempt, so it appears even if remediation fails.
   - Attempt `git worktree unlock` first; if it exits non-zero or is not available, fall back to `git worktree remove --force --force`.
   - If the fallback also fails, print the error to stderr and `exit 1` (non-zero).
   - The WORKTREE_PATH detection line (the `git worktree list --porcelain | grep …` pipeline) is unchanged.
3. **Verify the lock reason extraction** works by reading `git worktree list --porcelain` output format; the `locked` field appears after the worktree's `worktree`, `HEAD`, and `branch` lines. Use `grep -A5` with a suitable pattern, or inspect the raw output format in your git version to confirm field ordering.
4. **Run the smoke test runbook** against a local test git repository, covering all scenarios: locked-worktree unlock path, double-force fallback, non-locked standard path, no-worktree skip, and both-paths-fail exit.
5. **Update CHANGELOG** — add an entry under `[Unreleased]` for this fix.
6. **Open the implementation PR** targeting `develop`.
