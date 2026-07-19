# Smoke Test Runbook: May-Merge Policy Terminal Behavior

**Feature**: May-merge policy terminal behavior
**Spec**: [1_1177-may-merge-policy-terminal-behavior_specs.md](../../specs/developments/20260714170251_1177-may-merge-policy-terminal-behavior/1_1177-may-merge-policy-terminal-behavior_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for issue `#1177`.
- [ ] Local shell tests can run with `bash`.
- [ ] `gh`, `jq`, and repository shell helpers are available.
- [ ] The implementation PR includes the planned protocol, command, skill,
      agent, test, and changelog changes.

---

## Test Data

| Item | Value |
| --- | --- |
| Issue | `#1177` |
| Merge-granted policy | Effective stage policy has `may_merge_pr: true` for the PR stage or the invocation selected `--may-merge` within allowed guardrails. |
| Merge-denied policy | Effective stage policy has `may_merge_pr: false` or invocation selected `--no-may-merge`. |
| In-scope PR | A PR whose issue or branch belongs to the bounded item, batch, or epic scope. |
| Out-of-scope PR | Any discovered PR outside the bounded item, batch, or epic scope. |

---

## Smoke Test Steps

### Step 1: Verify Merge-Granted Contract

**Maps to**: AC1, AC3, AC4, AC10

1. Inspect the implementation diff for `guardrails-enforcement.md`,
   Protocol 91, and the `/run-item` surfaces.
2. Confirm the merge-granted path says readiness labels are intermediate.
3. Confirm the path requires delegated merge gate evidence before merge.
4. Confirm the path continues through merge verification, branch cleanup,
   `post-merge-cleanup.sh`, and tracker verification when gates pass.
5. Confirm a post-readiness merge gate failure reports `merge_blocked`, the
   failed gate, and the human action needed to unblock.

**Expected result**: Merge-granted runs cannot stop as done merely because
`ready-for-human-review` was applied.

### Step 2: Verify Merge-Denied Contract

**Maps to**: AC2, AC5, AC10

1. Inspect Protocol 91 and the `/run-item` surfaces.
2. Confirm the merge-denied path applies readiness labels when eligible.
3. Confirm the terminal outcome is `ready_human_merge`.
4. Confirm the summary must name the policy value denying merge.
5. Confirm the wording explicitly forbids calling the merge path.

**Expected result**: Merge-denied runs stop cleanly for human review or merge and
do not execute merge commands.

### Step 3: Verify Batch And Epic Consistency

**Maps to**: AC6, AC7, AC8, AC10

1. Inspect Protocol 90, Protocol 95, `/run-items`, and `/run-epic` surfaces.
2. Confirm batch and epic summaries use the same terminal outcome names:
   `merged`, `ready_human_merge`, `merge_blocked`, `policy_inconsistent`, and
   `out_of_scope`.
3. Confirm a merge-granted in-scope PR that stops at readiness without a named
   blocker is reported as `policy_inconsistent`.
4. Confirm discovered out-of-scope PRs are reported as `out_of_scope` and are
   not included in delegated merge or batch-merge commands.

**Expected result**: Batch and epic runs apply the same selected merge policy to
all in-scope PRs and never merge out-of-scope PRs.

### Step 4: Verify Cross-Surface Wording

**Maps to**: AC1, AC2, AC6, AC9

1. Run the implementation's cross-surface static contract test, if added:

   ```bash
   bash scripts/development-workflow/tests/test-may-merge-terminal-contract.sh
   ```

2. If no new static test was added, manually run:

   ```bash
   rg -n "merge_granted|merge_denied|ready_human_merge|merge_blocked|policy_inconsistent|out_of_scope|may_merge_pr" \
     docs/workflow/development-workflow/protocols/9*.md \
     docs/workflow/development-workflow/guardrails-enforcement.md \
     .claude/commands/run-{item,items,epic}.md \
     .cursor/commands/run-{item,items,epic}.md \
     .agents/skills/run-{item,items,epic}/SKILL.md \
     .codex/skills/workflow-{item-orchestrator,orchestrator}/SKILL.md \
     .claude/agents/{item-orchestrator,orchestrator}.md \
     .cursor/agents/{item-orchestrator,orchestrator}.md
   ```

3. Confirm every supported `/run-item`, `/run-items`, and `/run-epic` surface
   has the granted and denied terminal behavior.

**Expected result**: Supported command, skill, and agent surfaces teach the same
terminal-state contract.

### Step 5: Run Targeted Tests And Document Checks

**Maps to**: AC3, AC4, AC9, AC10

1. Run any new or changed shell tests:

   ```bash
   bash scripts/development-workflow/tests/test-may-merge-terminal-contract.sh
   bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
   bash scripts/development-workflow/tests/test-run-bounded-prelude.sh
   ```

2. Skip a command only when its corresponding file was not added or changed,
   and record that rationale in the PR validation notes.
3. Run markdown/documentation checks required by the repository.

**Expected result**: Targeted shell tests and document checks pass, or the PR
clearly names the blocker.

---

## Assertions Checklist

- [ ] AC1: Merge-granted handoffs state readiness is intermediate and the runner
      must continue through delegated merge and the approved merge path.
- [ ] AC2: Merge-denied handoffs state the runner stops after readiness and must
      not execute a merge.
- [ ] AC3: Merge-granted, gate-clean PRs proceed through merge, merge
      verification, branch cleanup, and tracker verification.
- [ ] AC4: Merge-granted PRs blocked after readiness report `merge_blocked`
      with the failed gate and human action.
- [ ] AC5: Merge-denied ready PRs report `ready_human_merge`, name the denying
      policy value, and do not call merge commands.
- [ ] AC6: Batch and epic item runners use the same terminal-state contract.
- [ ] AC7: Unexplained stalled-at-ready in-scope PRs during merge-granted runs
      report `policy_inconsistent`.
- [ ] AC8: Out-of-scope PRs report `out_of_scope` and are not merged.
- [ ] AC9: `/run-item`, `/run-items`, and `/run-epic` command and skill
      surfaces use consistent wording.
- [ ] AC10: Final output states selected merge authority, expected terminal
      state, actual terminal state, and blocker or cleanup/tracker result.

---

## Seed Data Reference

No seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| None | Workflow contract validation uses shell fixtures and static docs. | Not applicable |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Static test fails on one mirror only. | Command, skill, or agent wording drifted from the canonical protocol. | Update the mirror to match the protocol wording, then rerun the test. |
| Delegated-gate tests fail after wording-only edits. | The test is matching prose instead of stable outcome tokens. | Narrow the assertion to outcome tokens or helper behavior. |
| Merge-denied wording still says ready PRs are complete. | Old two-step lifecycle wording was left in a command or README surface. | Replace it with `ready_human_merge` and explicit no-merge language. |

---

## Known Limitations

- This smoke test validates workflow contract and helper behavior. It does not
  perform a live merge against production branches.
