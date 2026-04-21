# Smoke Test Runbook: Subagent Permission Denial Mitigation

**Feature**: Subagent permission denial detection and inline fallback (Issue #172)
**Spec**: [docs/specs/developments/20260416200000_172-subagent-permission-denial/1_172-subagent-permission-denial_specs.md](../../specs/developments/20260416200000_172-subagent-permission-denial/1_172-subagent-permission-denial_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] A batch orchestration session (Protocol 90) is available to run or simulate
- [ ] The repository has at least one item eligible for advancement (Spec Ready or Plan Ready)
- [ ] The updated protocol documents (90 and 91) are in place on the active branch
- [ ] A test can simulate a subagent returning a `SUBAGENT_PERMISSION_DENIAL:` response (e.g., by crafting a mock subagent output or using a test stub)

---

## Test Data

| Item | Value |
|---|---|
| Simulated denied tools | `Edit`, `Write`, `Bash` |
| Structured exit string | `SUBAGENT_PERMISSION_DENIAL: Edit tool denied on path <denied-path>. No partial work committed. Falling back to orchestrator inline execution.` |
| Test item | Any single Spec Ready or Plan Ready item in the tracker |

---

## Smoke Test Steps

### Scenario 1: Happy Path — Subagent Completes Normally (AC1 True-Negative)

**Maps to**: AC1 (no false-positive detection)

1. Run a batch orchestration session with a single eligible item.
2. Allow the subagent to complete normally (no permission denial injected).
3. In the final batch summary, verify the item is listed with execution path `subagent`.

**Expected result**: Batch summary shows `subagent` execution path. No inline fallback section is present. No `SUBAGENT_PERMISSION_DENIAL` signal appears in the output.

---

### Scenario 2: Subagent Permission Denial — Successful Inline Fallback (AC1, AC2, AC3, AC4)

**Maps to**: AC1, AC2, AC3, AC4

1. Configure a test subagent to return the following output and exit:
   ```
   SUBAGENT_PERMISSION_DENIAL: Edit tool denied on path <denied-path>. No partial work committed. Falling back to orchestrator inline execution.
   ```
2. Run a batch orchestration session with one eligible item and the mock subagent.
3. Observe the Portfolio Orchestrator's response after the subagent returns.

**Expected results**:
- The orchestrator logs: `[PERMISSION_DENIAL] Item #N: subagent denied access to Edit. Switching to inline execution.` (AC1)
- The orchestrator does NOT redispatch the same subagent for this item (AC1)
- The orchestrator calls `workflow-next-action.sh --branch <branch-name>` and resumes inline execution from scratch (AC2)
- The item eventually reaches `ready-for-human-review` or another valid terminal condition via inline execution (AC4)
- The final batch summary lists the item with execution path `inline fallback (permission denial: Edit)` (AC3)

---

### Scenario 3: Double Failure — Both Subagent and Inline Fallback Denied (AC6)

**Maps to**: AC6

1. Configure a test subagent to return `SUBAGENT_PERMISSION_DENIAL: Edit tool denied on path <denied-path>. No partial work committed. Falling back to orchestrator inline execution.`.
2. Configure the main-session inline execution to also encounter an `Edit` permission denial.
3. Run the batch.

**Expected results**:
- The orchestrator logs `[BLOCKED] Item #N: both subagent and inline fallback were denied Edit access. Human intervention required.`
- The item is marked `blocked` in the batch summary.
- No `needs-fixes` label is applied on any PR (permission denial is an infrastructure failure, not a content failure).
- The orchestrator does not retry further (no loop). (AC6)

---

### Scenario 4: Pre-Flight Self-Check Detects Denial Before Creator Work (AC5)

**Maps to**: AC5

1. Configure the subagent environment so that `Edit` to `.tmp/` is denied.
2. Start a Work Item Runner subagent for any creator-stage item (Writing Spec, Writing Plan, or In Development).
3. Allow the pre-flight self-check to run.

**Expected results**:
- The subagent exits immediately with: `SUBAGENT_PERMISSION_DENIAL: Edit tool denied on path <denied-path>. No partial work committed. Falling back to orchestrator inline execution.`
- No creator-stage file (spec, plan, feature code) has been written or committed.
- No tracked files are modified (verify with `git status --porcelain` — clean).
- The `.tmp/` self-check file (if created) is cleaned up.

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Remove any test stubs or mock subagent configurations.
- Confirm no unintended tracked files were modified during testing.

---

## Assertions Checklist

- [ ] AC1: `SUBAGENT_PERMISSION_DENIAL:` in subagent output is detected; orchestrator does not redispatch the subagent for the same item in the same batch.
- [ ] AC2: After a subagent permission failure, the orchestrator re-evaluates state via `workflow-next-action.sh` from the existing worktree and executes inline.
- [ ] AC3: Final batch summary distinguishes `subagent` vs. `inline fallback (permission denial: [tools])` execution paths.
- [ ] AC4: Item reaches a valid terminal condition (e.g., `ready-for-human-review`) via inline fallback.
- [ ] AC5: Pre-flight self-check exits with `SUBAGENT_PERMISSION_DENIAL:` before any creator-stage write; no tracked files modified; temp file cleaned up.
- [ ] AC6: Double-failure path marks item as `blocked` and notifies human; no further retries; no `needs-fixes` label applied (permission denial is an infrastructure failure).

---

## Seed Data Reference

Not applicable — this feature modifies protocol documents only and does not require application seed data.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Orchestrator does not detect `SUBAGENT_PERMISSION_DENIAL:` signal | The substring match is case-sensitive or the message format changed | Verify the exact message format produced by the subagent matches the protocol's detection pattern; adjust to case-insensitive match if needed |
| Inline fallback picks up stale state from partial subagent work | Inline fallback is not calling `workflow-next-action.sh` from scratch | Confirm the protocol instructs a fresh `workflow-next-action.sh` invocation; do not assume prior progress |
| `needs-fixes` label applied to PR during permission denial (non-double-failure path) | Business rule not enforced | Verify the protocol explicitly states no `needs-fixes` label for single-failure subagent denials |
| Self-check writes to a tracked file | Self-check target path is wrong | Ensure `.tmp/` is used; verify `.gitignore` includes `.tmp/` |

---

## Known Limitations

- Scenario 2–4 above require manual simulation of subagent permission denial; there is no automated harness-level test that can force the Claude Code harness to deny tool access at will. Testing must rely on mock subagent output or controlled test environments where permission restrictions can be applied.
- The smoke test cannot simulate the exact harness condition that produced the Batch 5 failure (#160) without access to the underlying harness configuration. The runbook tests the protocol's response to the signal, not the harness's production of the signal.
