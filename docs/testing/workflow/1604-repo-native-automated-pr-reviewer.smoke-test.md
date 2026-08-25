# Smoke Test Runbook: Repo-Native Automated PR Reviewer Spike/MVP

**Feature**: Add an opt-in local-only Step 7 review platform
**Spec**: [1_1604-repo-native-automated-pr-reviewer_specs.md](../../specs/developments/20260825164644_1604-repo-native-automated-pr-reviewer/1_1604-repo-native-automated-pr-reviewer_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out.
- [ ] The local unit and dispatch tests pass.
- [ ] `gh` is authenticated for repository metadata lookups.
- [ ] A disposable PR exists, or the implementation PR is safe to review with mock commands.
- [ ] Bugbot remains configured as this repository's ready-phase reviewer unless a later human decision
  changes the ready-phase platform.

---

## Test Data

| Item | Value |
| --- | --- |
| Test PR | A disposable draft PR or the implementation PR |
| Base branch | `develop` |
| Draft-phase platform | `local-ai-reviewer` |
| Current ready-phase platform | `bugbot` |
| Mock command | A local script that emits clean, blocking, malformed, timeout, and advisory fixtures |
| Focused automated tests | `test-local-ai-reviewer.sh`, `test-local-ai-reviewer-findings.py`, `test-local-ai-reviewer-pr-review-loop-dispatch.sh` |

---

## Smoke Test Steps

### Step 1: Confirm platform dispatch

**Maps to**: Result Wire Contract and local reviewer lifecycle rules

1. Configure a local override or explicit flag for `local-ai-reviewer`.
2. Run:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr> --branch <branch> --platform local-ai-reviewer
   ```

3. Confirm output contains `PLATFORM_LIST=local-ai-reviewer` and `PLATFORM_1_NAME=local-ai-reviewer`.

**Expected result**: The reviewer loop accepts the new platform without invoking Bugbot or another platform.

**Automated fixture**:

```bash
bash scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh
```

### Step 2: Confirm missing command escalates

**Maps to**: Failure-state classification

1. Unset `LOCAL_AI_REVIEWER_COMMAND`.
2. Run the companion script or reviewer loop.
3. Confirm output includes `RESULT=escalate` and `REASON=missing_command`.

**Expected result**: Missing local reviewer setup is unavailable evidence, not clean review evidence.

**Automated fixture**: `missing_command_result` in
`scripts/development-workflow/tests/test-local-ai-reviewer.sh`.

### Step 3: Confirm clean and advisory-only mapping

**Maps to**: Advisory-only result contract

1. Set `LOCAL_AI_REVIEWER_COMMAND` to a mock command that emits a clean result.
2. Confirm `RESULT=clean`, `BLOCKING_COUNT=0`, `COMMENT_COUNT=0`, and `SUGGESTION_COUNT=0`.
3. Set the mock command to emit advisory-only suggestions.
4. Confirm `RESULT=clean`, `BLOCKING_COUNT=0`, `SUGGESTION_COUNT>0`, and `COMMENT_COUNT` equals the
   advisory count.

**Expected result**: Advisory-only feedback never emits raw `RESULT=advisory`.

**Automated fixtures**: `clean_result`, `advisory_result`,
`clear_in_scope_suggestion_result`, and `important_result` in
`scripts/development-workflow/tests/test-local-ai-reviewer.sh`.

### Step 4: Confirm blocking mapping

**Maps to**: Result Wire Contract

1. Set the mock command to emit one blocking finding with a path and line.
2. Run the reviewer loop.
3. Confirm output includes `RESULT=needs_fixes`, `BLOCKING_COUNT=1`, and a blocking summary field.

**Expected result**: Blocking local findings stop the loop for fixes.

**Automated fixture**: `clear_in_scope_suggestion_blocking` in
`scripts/development-workflow/tests/test-local-ai-reviewer.sh`.

### Step 5: Confirm head mismatch escalates

**Maps to**: Current-head binding

1. Configure the mock PR metadata or fixture so the checkout head differs from the PR head.
2. Run the companion script.
3. Confirm output includes `RESULT=escalate` and `REASON=head_mismatch`.

**Expected result**: The local reviewer never reports clean evidence for a stale or wrong head.

**Automated fixture**: `head_mismatch_result` in
`scripts/development-workflow/tests/test-local-ai-reviewer.sh`.

### Step 6: Confirm malformed and timeout behavior

**Maps to**: Failure-state classification

1. Set the mock command to emit malformed output.
2. Confirm `RESULT=escalate` and `REASON=malformed_output`.
3. Set the mock command to exceed the timeout.
4. Confirm `RESULT=escalate` and `REASON=timeout`.

**Expected result**: Unsafe output and timeout fail closed.

**Automated fixtures**: `malformed_result` and `timeout_result` in
`scripts/development-workflow/tests/test-local-ai-reviewer.sh`.

### Step 7: Confirm optional graph context behavior

**Maps to**: Graph Context Adoption Criteria

1. Leave graph tools unconfigured.
2. Run a clean mock review.
3. Confirm the review can complete and output records `GRAPH_CONTEXT=skipped`.
4. If `code-review-graph` or `graphify` is available, run the graph-enabled path and record setup effort,
   extra context, noise, and runtime.

**Expected result**: Missing optional graph tooling does not block local review.

**Automated fixture**: `graph_skipped_result` in
`scripts/development-workflow/tests/test-local-ai-reviewer.sh`.

### Step 8: Confirm ready-phase Bugbot remains separate

**Maps to**: Preserve ready-phase validation

1. Run the local reviewer in draft phase and get a clean result.
2. Let the normal reviewer loop continue to ready phase, or run with the configured ready-phase platform.
3. Confirm Bugbot evidence is recorded separately from local reviewer evidence.

**Expected result**: Local clean evidence does not replace Bugbot ready-phase evidence.

### Step 9: Confirm net-new finding comparison fixtures

**Maps to**: Net-new ready-phase finding metric

1. Run the finding matcher fixtures.
2. Confirm same-path/different-key findings do not collapse incorrectly.
3. Confirm ambiguous matches are counted as net-new with candidate IDs.
4. Confirm one local finding cannot consume multiple ready-phase findings.

**Expected result**: The matcher is conservative and does not hide ready-phase findings.

**Automated fixture**:

```bash
python3 scripts/development-workflow/tests/test-local-ai-reviewer-findings.py
```

### Last Step: Validate & Shut Down

- Verify all assertions below are met.
- Restore temporary local reviewer config and mock commands.
- Record whether graph evaluation was completed, deferred, or skipped.

---

## Assertions Checklist

- [ ] `local-ai-reviewer` is accepted as a Step 7 platform.
- [ ] Missing local command escalates with `REASON=missing_command`.
- [ ] Clean output maps to `RESULT=clean`.
- [ ] Advisory-only output maps to `RESULT=clean` with positive `SUGGESTION_COUNT`.
- [ ] Blocking output maps to `RESULT=needs_fixes`.
- [ ] Head mismatch escalates.
- [ ] Malformed output escalates.
- [ ] Timeout escalates.
- [ ] Optional graph absence records `GRAPH_CONTEXT=skipped`.
- [ ] Bugbot ready-phase evidence remains separate.
- [ ] Net-new ready-phase comparison fixtures pass.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Mock local reviewer command | Clean, advisory-only, blocking, malformed, timeout | Run `scripts/development-workflow/tests/test-local-ai-reviewer.sh` |
| Finding matcher fixtures | Duplicate, ambiguous, rephrased, severity-promoted, and unclassified findings | Run `scripts/development-workflow/tests/test-local-ai-reviewer-findings.py` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `local-ai-reviewer` is reported as unsupported | `pr-review-loop.sh` dispatch or usage list was not updated | Re-check platform dispatch and supported-platform enumeration |
| Missing command returns clean | Companion-script failure mapping is unsafe | Fix missing-command handling to emit `RESULT=escalate` |
| Bugbot runs during platform dispatch test | The test used configured platforms instead of explicit `--platform local-ai-reviewer` | Re-run with the explicit platform flag |
| Graph absence blocks the review | Optional graph status was incorrectly treated as terminal | Emit `GRAPH_CONTEXT=skipped` while preserving the platform result |
| Ready-phase findings disappear from measurement | Matcher over-collapsed ambiguous findings | Treat ambiguous matches as net-new and list candidate IDs |

---

## Known Limitations

- Native GitHub inline comments are out of scope for the MVP.
- Live successful local review depends on the configured local command and model credentials.
- Graph adoption cannot be promoted beyond optional/deferred without evidence from representative inputs.
