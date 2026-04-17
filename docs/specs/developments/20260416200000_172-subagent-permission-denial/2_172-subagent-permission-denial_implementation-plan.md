# Subagent Permission Denial Mitigation — Implementation Plan

**Spec**: [1_172-subagent-permission-denial_specs.md](./1_172-subagent-permission-denial_specs.md)
**Smoke test runbook**: [docs/testing/workflow/subagent-permission-denial.smoke-test.md](../../../testing/workflow/subagent-permission-denial.smoke-test.md)

---

## Summary

**Approach**: Add a structured early-exit convention to `91-orchestrate-work-protocol.md` so that a subagent that encounters a tool-permission denial returns a recognisable error signal before doing any partial work. Add a corresponding detection and inline-fallback section to `90-batch-orchestrate-work-protocol.md` so the Portfolio Orchestrator reads that signal, switches to inline execution for the affected item from the correct worktree, and records the fallback in the batch summary.

**Estimated complexity**: S

**Rationale**: All changes are to Markdown protocol documents and one smoke-test runbook — no shell scripts, no runtime code, and no CI workflow changes. The detection heuristic (substring match on the harness error message) and the recovery path (re-evaluate state with `workflow-next-action.sh`) are both straightforward. No architectural tradeoffs are involved.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Protocol Documents

#### `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`

- [ ] **AC5** — Add a new named section "Pre-flight permission self-check (subagent runs only)" immediately after the existing Step 3 dispatch strategy section. The section must specify:
  - When the subagent starts (after receiving handoff context), before any creator-stage file edit or tool call, attempt a lightweight sanity check (e.g., write a single-line comment to a `.tmp/` file) to verify `Edit` and `Bash` are accessible.
  - If the check fails with a "Permission to use [tool] has been denied" error, exit immediately with a structured message: `"SUBAGENT_PERMISSION_DENIAL: [tool] denied. No partial work committed. Falling back to orchestrator inline execution."` — do not continue into creator-stage work.
  - If the check succeeds, proceed normally.
  - The temp file used for the self-check must not be a tracked file (write to `.tmp/` which is gitignored) and must be cleaned up after the check regardless of outcome.
  - Classify this as "optional but recommended" per AC5 / spec Use Case 3: even without the self-check, Use Case 1 recovery handles permission denials that happen mid-run.

- [ ] **AC5 / AC6** — In Step 3 (Dispatch Strategy), under "Worktree isolation for parallel batches", add a paragraph instructing the *subagent itself* to:
  - Detect any `"Permission to use Edit has been denied"` or `"Permission to use Bash has been denied"` harness response at any point during the run (not just during the pre-flight check).
  - Immediately stop all further work and return a structured error string starting with `SUBAGENT_PERMISSION_DENIAL:`.
  - Not apply any PR labels, not commit any partial work, and not update tracker status before exiting.

#### `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

- [ ] **AC1, AC2, AC3, AC4, AC6** — Add a new subsection "Step 4.1: Subagent Permission-Denial Detection and Inline Fallback" immediately after the existing Step 4 (Dispatch Work Item Runners). The subsection must specify:

  1. **Detection** (AC1): After each Work Item Runner subagent returns, check whether its output contains the substring `SUBAGENT_PERMISSION_DENIAL:`. If it does, extract the denied tool name(s) from the message and log: `[PERMISSION_DENIAL] Item #N: subagent denied access to [tools]. Switching to inline execution.`

  2. **No-redispatch rule** (AC1): Do NOT redispatch the same subagent for the same item in the same batch run. The inline fallback is the only recovery path.

  3. **Inline fallback** (AC2): Execute the item from the main session using the worktree path that was already created for the item (use the same path from the dispatch handoff). Re-evaluate item state from scratch:
     ```bash
     ./scripts/development-workflow/workflow-next-action.sh --branch <branch-name>
     ```
     Do not assume any progress from the failed subagent — treat the item as if newly dispatched.

  4. **Batch summary entry** (AC3): In the final batch summary, mark the item with execution path `inline fallback (permission denial: [tools])` rather than `subagent`. The summary must distinguish items completed via subagent dispatch from items completed via inline fallback.

  5. **Double-failure path** (AC6): If the inline fallback itself encounters a permission denial on `Edit` or `Bash`, mark the item as `blocked` in the batch summary, apply a `needs-fixes` label on any open PR for the item (if one exists), and notify the human. Do not retry further. Example notification: `[BLOCKED] Item #N: both subagent and inline fallback were denied [tool] access. Human intervention required.`

  6. **No `needs-fixes` label on permission failures** (business rule from spec): A permission denial is an infrastructure failure, not a content failure. Do not apply `needs-fixes` unless the item is in the double-failure path.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. Happy path — subagent completes normally (no permission denial): batch summary shows `subagent` execution path and no inline fallback section. Maps to AC1 (true-negative: no false-positive detection).
2. Subagent permission denial, successful inline fallback: item reaches `ready-for-human-review` via inline execution; batch summary lists execution path as `inline fallback (permission denial: [tool])`. Maps to AC1, AC2, AC3, AC4.
3. Double failure — both subagent and inline fallback denied: item is marked `blocked` in batch summary; human is notified; no `needs-fixes` label applied (unless an open PR already exists, in which case `needs-fixes` is applied). Maps to AC6.
4. Pre-flight self-check fails before any creator-stage work: subagent exits immediately with `SUBAGENT_PERMISSION_DENIAL:` message and no partial commit. Maps to AC5.

**Smoke test runbook**: [`docs/testing/workflow/subagent-permission-denial.smoke-test.md`](../../../testing/workflow/subagent-permission-denial.smoke-test.md)

---

## Seed Data

Not applicable. This feature modifies protocol documents only; no application data or database seeding is required.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — updated as part of implementation (primary deliverable; not a separate doc update)
- [ ] `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — updated as part of implementation (primary deliverable; not a separate doc update)

No other project docs in `docs/project/`, `docs/best-practices/`, or `AGENTS.md` are affected by this change. The change is internal to the AI workflow protocol layer.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Harness changes its exact error wording, breaking the `SUBAGENT_PERMISSION_DENIAL` detection | Low | Med | Use case-insensitive substring match on `"permission"` and `"denied"` (or `"has been denied"`) rather than exact match; document the matching strategy in the protocol so future maintainers can update it if the wording changes |
| Pre-flight self-check accidentally writes to a tracked file and creates noise in git status | Low | Low | Explicitly target `.tmp/` (gitignored); include a `git status --porcelain` gate in the self-check to catch any accidental tracked-file writes; clean up regardless of outcome |
| Inline fallback re-evaluates stale VCS state after partial subagent work | Low | Med | Protocol mandates a fresh `workflow-next-action.sh` call; do not assume any VCS state from the failed subagent; the script will detect what is actually committed vs. not |

---

## Code Samples

> All samples below are **illustrative — adapt during implementation**.

### SUBAGENT_PERMISSION_DENIAL exit message (illustrative)

```text
SUBAGENT_PERMISSION_DENIAL: Edit tool denied by harness. No partial work committed. 
Falling back to orchestrator inline execution.
```

### Inline fallback detection logic (illustrative pseudocode)

```text
if subagent_output contains "SUBAGENT_PERMISSION_DENIAL:":
    denied_tools = extract tool names from message
    log "[PERMISSION_DENIAL] Item #N: subagent denied access to {denied_tools}. Switching to inline execution."
    run workflow-next-action.sh --branch <branch-name>  # fresh state evaluation
    execute inline from main session
    record execution_path = "inline fallback (permission denial: {denied_tools})"
```

---

## Implementation Order

1. Update `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`:
   - Add "Pre-flight permission self-check" section after Step 3.
   - Add permission-denial early-exit paragraph to Step 3 worktree isolation section.
2. Update `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`:
   - Add "Step 4.1: Subagent Permission-Denial Detection and Inline Fallback" after Step 4.
3. Write smoke test runbook at `docs/testing/workflow/subagent-permission-denial.smoke-test.md`.
4. Commit, push, and open draft PR targeting `develop`.
5. Run internal review gate (Step 7a).
6. Run automated reviewer loop (Step 7) and CI loop (Step 8).
7. Apply `ready-for-human-review` label after all readiness checks pass (Step 8a).
8. Update tracker status to `Plan in Review` (Step 8b).
