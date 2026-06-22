# Smoke Test Runbook: Codex Reviewer Runtime Fallback

**Feature**: Codex Reviewer Runtime Fallback (Issue #185)
**Spec**: [`docs/specs/developments/20260417203329_codex-reviewer-runtime-fallback/1_codex-reviewer-runtime-fallback_specs.md`](../../specs/developments/20260417203329_codex-reviewer-runtime-fallback/1_codex-reviewer-runtime-fallback_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Protocol 91 Step 7a has been updated with the runtime-availability check sub-section
- [ ] `.ai-dev-workflow.yaml` has the `internal_reviewers_unavailable_policy` comment annotation
- [ ] You have access to a draft PR (or can open one) to observe Step 7a behavior
- [ ] You understand the runner context you are in (Claude Code subagent, direct human, Codex)

---

## Test Data

| Item                                | Value                                                                          |
| ----------------------------------- | ------------------------------------------------------------------------------ |
| Protocol file                       | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Config file                         | `.ai-dev-workflow.yaml`                                                        |
| Local override file                 | `.ai-dev-workflow.local.yaml` (gitignored)                                     |
| Internal reviewers (default config) | `[claude, codex]`                                                              |
| Default policy                      | `warn`                                                                         |

---

## Smoke Test Steps

### Step 1: Verify Protocol 91 Step 7a contains the runtime-availability check sub-section

- Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- Locate Step 7a
- Verify the sub-section "Runtime-availability check" appears before the "Reviewer dispatch map" table

**Expected result**: The sub-section is present and contains:

- A reachability classification table listing runner contexts and which reviewers they can invoke
- Policy resolution logic for `warn`, `fail-if-any-unavailable`, and zero-reachable cases
- Warning comment format for skipped reviewers
- Hard-fail comment format (BR-3 / Use Case 2)
- Local override log message format

### Step 2: Verify the Step 7a summary comment requirement is documented

**Maps to**: Acceptance Criterion 5 (summary comment always posted)

- In the same Step 7a block, locate the multi-reviewer execution rules
- Verify a rule states that a Step 7a summary comment must always be posted when the gate exits

**Expected result**: The rule lists the required comment fields: effective reviewer set, skipped reviewers (with reason), and final verdict.

### Step 3: Simulate Use Case 1 — `codex` unreachable (warn policy, Claude Code subagent context)

**Maps to**: Acceptance Criteria 1, 2, 3, 4, 5

This step is a protocol-reading exercise (not a live execution). Read the updated Step 7a and trace the decision path for the following scenario:

- Runner: Claude Code subagent
- `internal_reviewers`: `[claude, codex]`
- Policy: `warn` (default, not set in config)
- Availability check result: `claude` = reachable, `codex` = unreachable

Verify the protocol instructs the runner to:

1. Emit a warning before dispatching any reviewer — naming `codex` as unreachable and the runner context

**Expected result**: Warning step appears before reviewer dispatch in the protocol text.

2. Record `codex` as `skipped (unreachable)` — not `APPROVED` and not `NEEDS REVISION`

**Expected result**: The protocol explicitly states that a skipped reviewer does not count as an approval.

3. Dispatch `claude` and await its verdict

**Expected result**: Protocol continues to the existing reviewer dispatch path for `claude`.

4. If `claude` returns `APPROVED`, post a Step 7a summary comment listing effective reviewers, skipped reviewers, and verdict, then call `gh pr ready`

**Expected result**: Protocol mandates the summary comment before `gh pr ready` is called.

5. If `claude` returns `NEEDS REVISION`, apply fixes and re-run only the reachable subset (`claude`)

**Expected result**: Protocol re-runs only the reachable reviewer list, not the full declared list.

### Step 4: Simulate Use Case 2 — all reviewers unreachable (hard-fail)

**Maps to**: Acceptance Criterion 6

Trace the decision path for:

- Runner: hypothetical runner that can invoke neither `claude` nor `codex`
- `internal_reviewers`: `[claude, codex]`
- Availability check result: both unreachable

Verify the protocol instructs the runner to:

1. Hard-fail immediately — regardless of configured policy
2. Post a blocking comment to the PR that doubles as the BR-7 summary comment, listing all reviewers as `unreachable` and verdict as `hard-fail` with remediation guidance
3. NOT call `gh pr ready`
4. Report the item as "blocked — no reviewer available"

**Expected result**: All four conditions are explicit in the protocol text.

### Step 5: Simulate Use Case 3 — all reviewers reachable (no change)

**Maps to**: Acceptance Criterion 3 (indirect — skipped reviewer not counted as approved)

Trace the path for:

- Runner: direct human or Codex runner
- All listed reviewers reachable

Verify the protocol instructs the runner to proceed with the existing Step 7a loop with no extra comments or warning steps.

**Expected result**: No deviation from the pre-existing flow; no warning or skip comment is posted.

### Step 6: Simulate Use Case 4 — local override present

**Maps to**: Acceptance Criterion 8

Trace the path for:

- `.ai-dev-workflow.local.yaml` present with `review.on_draft.runner: [claude]`
- Original `.ai-dev-workflow.yaml` list: `[claude, codex]`

Verify the protocol instructs the runner to:

1. Use the override list `[claude]` for Step 7a
2. Log: `INFO: Using review.on_draft.runner override from .ai-dev-workflow.local.yaml: [claude]. Original list: [claude, codex].`
3. Not post a warning comment to the PR (the developer knowingly excluded `codex`)
4. Run availability check only against the override list

**Expected result**: All four instructions are present in the protocol.

### Step 7: Verify `fail-if-any-unavailable` policy wording

**Maps to**: Business Rule 5 (BR-5) and Acceptance Criterion 7 (partial)

In the protocol text, locate the policy resolution section. Verify the `fail-if-any-unavailable` policy is documented and the protocol states:

- When the policy is set to `fail-if-any-unavailable` and any reviewer is unreachable, the gate hard-fails
- This hard-fail applies even when only one reviewer out of multiple is unreachable

**Expected result**: The distinction between `warn` and `fail-if-any-unavailable` is explicit in the protocol table or decision description.

### Step 8: Verify Step 8c clarification

Locate Step 8c in the protocol. Verify it contains a parenthetical or note clarifying that:

- The "Automated reviewer loop summary" check (Step 7) is distinct from the Step 7a summary comment
- The Step 7a summary comment does not satisfy the Step 8c check

**Expected result**: A clarifying note is present that prevents confusion between the two summary comment requirements.

### Step 9: Verify `.ai-dev-workflow.yaml` annotation

- Open `.ai-dev-workflow.yaml`
- Locate the `internal_reviewers` key
- Verify a commented-out `internal_reviewers_unavailable_policy` key is present beneath it with:
  - Default value: `warn`
  - Valid values documented: `warn`, `fail-if-any-unavailable`

**Expected result**: The comment annotation is present and accurate.

### Step 10: Verify smoke test runbook relative link from the plan

- Open `docs/specs/developments/20260417203329_codex-reviewer-runtime-fallback/2_codex-reviewer-runtime-fallback_implementation-plan.md`
- Locate the smoke test runbook link
- Verify the path uses three `../` hops: `../../../testing/workflow/codex-reviewer-runtime-fallback.smoke-test.md`

**Expected result**: The link resolves correctly from the plan file's location.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: When Step 7a is entered with `internal_reviewers: [claude, codex]` and `codex` is unreachable, the protocol instructs the runner to emit a warning log and post a warning comment to the draft PR identifying `codex` as unreachable and skipped.
- [ ] AC-2: The warning comment appears before any reviewer is dispatched, per the protocol ordering.
- [ ] AC-3: `codex` being unreachable does not cause the gate to treat it as `APPROVED`. The skipped reviewer is listed as `skipped (unreachable)` in the Step 7a summary.
- [ ] AC-4: When `claude` (the only reachable reviewer) returns `APPROVED`, the protocol instructs the gate to succeed and call `gh pr ready`.
- [ ] AC-5: The Step 7a summary comment is mandated to list effective reviewer set, skipped reviewers (with reason), and final verdict.
- [ ] AC-6: When ALL listed reviewers are unreachable, the protocol instructs the gate to hard-fail, post a blocking/summary comment, keep the PR in draft, and escalate the item to human.
- [ ] AC-7: The `warn` policy (default) allows the gate to proceed with a reduced reviewer set as long as at least one reviewer is reachable and returns `APPROVED`.
- [ ] AC-8: A local `.ai-dev-workflow.local.yaml` override suppresses the unavailability warning for excluded reviewers and triggers an INFO log that the override was applied.
- [ ] AC-9: Protocol 91 Step 7a wording includes the runtime-availability check, skip/warn/fail logic, and summary comment requirement.

---

## Seed Data Reference

Not applicable — this feature is a protocol documentation change. No runtime seed data is required.

---

## Troubleshooting

| Symptom                                                     | Likely cause                             | Fix                                                                                                                                          |
| ----------------------------------------------------------- | ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Step 7a summary comment requirement is missing from Step 7a | Implementation skipped BR-7 wording      | Re-read BR-7 and add the mandatory summary comment rule to Step 7a                                                                           |
| Hard-fail comment format is undocumented                    | Use Case 2 wording was not included      | Add the exact comment format from Use Case 2 step 3 to the protocol                                                                          |
| Override log message format is wrong                        | Use Case 4 exact wording was paraphrased | Match the exact wording from the spec Use Case 4 step 5                                                                                      |
| Smoke test link uses four `../` hops instead of three       | Plan file depth miscounted               | Plan file is at depth 4 (`docs/specs/developments/<folder>/`), so three `../` hops reach `docs/`; correct to `../../../testing/workflow/...` |

---

## Known Limitations

- These smoke tests are manual protocol-reading exercises, not automated integration tests. The runtime-availability check behavior can only be observed by actually running Step 7a from a Claude Code subagent context with `codex` listed as a reviewer.
- The `fail-if-any-unavailable` policy is documented but not end-to-end testable in this runbook without a live PR in a runner that supports setting that policy.
