# Smoke Test Runbook: Human Checkpoint Lifecycle

**Feature**: Human Checkpoint Lifecycle
**Spec**:
[1_1020-human-checkpoint-policy-model_specs.md](../../specs/developments/20260622164905_1020-human-checkpoint-policy-model/1_1020-human-checkpoint-policy-model_specs.md)
**Created in**: In Development stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #1024.
- [ ] The PR targets `develop-run-epic-human-checkpoints`.
- [ ] The implementation branch includes the merged work for #1021, #1022, and
      #1023.
- [ ] Fixture tests are available and do not require live GitHub mutation.

---

## Test Data

| Item | Value |
| --- | --- |
| Policy recommender | `scripts/development-workflow/run-epic-policy-recommender.sh` |
| Checkpoint lifecycle helper | `scripts/development-workflow/run-epic-checkpoint-lifecycle.sh` |
| Delegated gate | `scripts/development-workflow/run-epic-delegated-gate.sh` |
| Batch merge helper | `scripts/development-workflow/batch-merge.sh` |
| Audit helper | `scripts/development-workflow/run-epic-audit-trail.sh` |
| Run-epic protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |
| Readiness signal protocol | `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` |
| Batch merge protocol | `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` |

---

## Smoke Test Steps

### Step 1: Verify Policy Recommendation and Initial Summary

**Maps to**: issue requirements 1, 2, and 3.

1. Run the policy recommender fixture tests.
2. Confirm eligible items with schema, migration, data-model, product ambiguity,
   product/technical tradeoff, auth, permission, security, or sensitive-change
   wording produce `effectivePolicy.checkpoints`.
3. Confirm the run-epic protocol and command wrappers tell agents to present
   checkpoint policy in the initial preflight summary alongside autonomy policy,
   base branch, risk rationale, scoped items, and copy-paste command.

**Expected result**: A `/run-epic` preflight makes checkpoint policy visible
before any branch, tracker, PR, label, comment, or merge mutation.

### Step 2: Verify Plan-Stage Database or Schema Checkpoint

**Maps to**: issue requirement 2.

1. Inspect the run-epic protocol examples.
2. Confirm database schema, migration, or persistent data-model wording maps to
   a `plan` / `technical` checkpoint.
3. Confirm the required human action names plan approval, such as approving the
   migration and rollback plan.
4. Confirm an implementation-stage PR for the same item remains blocked while
   the earlier plan-stage checkpoint is still `pending`.

**Expected result**: Schema and migration work asks for human plan review before
implementation can be delegated through merge.

### Step 3: Verify Implementation-Stage Sensitive-Change Checkpoint

**Maps to**: issue requirements 2 and 4.

1. Inspect the run-epic protocol examples and policy recommender fixtures.
2. Confirm auth, permission, security-sensitive automation, or merge behavior
   wording maps to an `implementation` / `technical` checkpoint.
3. Confirm the required human action names approval of the sensitive
   implementation before delegated merge.

**Expected result**: Sensitive implementation work cannot pass delegated review
or merge solely because CI and automated reviewers are clean.

### Step 4: Verify PR Readiness Label Lifecycle

**Maps to**: issue requirements 1 and 4.

1. Run the checkpoint lifecycle helper fixture tests.
2. Confirm an applicable pending checkpoint applies `human-checkpoint-required`
   and records a stable `<!-- run-epic:checkpoint-status -->` PR comment.
3. Confirm `ready-for-human-review` may coexist with
   `human-checkpoint-required` when automation is clean but a checkpoint remains
   open.
4. Confirm satisfaction via human approval/comment, or waiver with rationale,
   removes `human-checkpoint-required` only after checkpoint state becomes
   `satisfied` or `waived`.

**Expected result**: Readiness labels distinguish automation-clean from
checkpoint-satisfied state.

### Step 5: Verify Delegated Gate Blocking

**Maps to**: issue requirements 1 and 4.

1. Run the delegated gate fixture tests.
2. Confirm a pending checkpoint for the PR's item and current or earlier stage
   returns `human_required`.
3. Confirm the stop reason includes `human_checkpoint_required`, the affected
   issue number, stage, domain, and required human action.
4. Confirm satisfied checkpoints, future-stage checkpoints, and checkpoints for
   other items do not block an otherwise clean PR.

**Expected result**: Delegated merge cannot bypass an unsatisfied declared
checkpoint.

### Step 6: Verify Batch Merge Handling

**Maps to**: issue requirements 1 and 4.

1. Run the batch merge checkpoint fixture tests.
2. Confirm discovery warns and skips PRs labeled `human-checkpoint-required` by
   default, even when `ready-for-human-review` is present.
3. Confirm explicit discovery can surface checkpointed PRs for protocol handling
   with `--include-checkpointed`.
4. Confirm merge mode refuses a stale `human-checkpoint-required` label.

**Expected result**: Batch merge does not silently merge checkpointed PRs.

### Step 7: Verify Audit Evidence

**Maps to**: issue requirements 1 and 4.

1. Run the audit trail fixture tests.
2. Confirm PR disposition output includes invocation policy, checkpoint policy,
   satisfaction states, pending applicable checkpoint count, reviewer outcome,
   CI outcome, risk classification, and final decision.
3. Confirm epic ledger output scopes checkpoints by item and updates marker
   comments in place.

**Expected result**: Delegated checkpoint decisions leave reproducible audit
evidence without duplicate comments.

### Step 8: Run Automated Validation

**Maps to**: all issue requirements and acceptance criteria.

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
   bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh
   bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
   bash scripts/development-workflow/tests/test-batch-merge-checkpoints.sh
   bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop-run-epic-human-checkpoints
   npx markdownlint-cli2 "docs/testing/workflow/1024-human-checkpoint-lifecycle.smoke-test.md" "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" "docs/testing/README.md" ".agents/skills/run-epic/SKILL.md" ".claude/commands/run-epic.md" ".cursor/commands/run-epic.md" "CHANGELOG.md"
   find docs/testing/workflow -name "1024-human-checkpoint-lifecycle.smoke-test.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
   ```

2. Confirm all commands pass.

**Expected result**: Policy recommendation, readiness labels, satisfaction
detection, delegated gate blocking, batch merge handling, audit output, shell
quality, and documentation formatting are validated together.

---

## Assertions Checklist

- [ ] Policy recommendation exposes checkpoints before mutation.
- [ ] Plan-stage database/schema checkpoints are documented with a technical
      approval action.
- [ ] Implementation-stage sensitive-change checkpoints are documented with a
      technical approval action.
- [ ] Pending checkpoints apply `human-checkpoint-required` without replacing
      `ready-for-human-review`.
- [ ] Satisfied or waived checkpoints remove `human-checkpoint-required` only
      with audit evidence.
- [ ] Delegated gate returns `human_required` for applicable pending
      checkpoints.
- [ ] Batch merge discovery warns and skips checkpointed PRs by default.
- [ ] Batch merge refuses stale checkpoint labels at merge time.
- [ ] PR disposition and epic ledger audit output include checkpoint policy and
      satisfaction state.
- [ ] Command wrappers mention checkpoint policy in the initial run summary.

---

## Seed Data Reference

No persistent seed data is required. Fixture tests create temporary checkpoint
policy, PR label, reviewer, CI, delegated gate, batch merge, and audit inputs.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| No checkpoints appear in preflight output | Item metadata lacks a high-leverage signal or the checkpoint policy was not carried from recommender output | Add explicit checkpoint policy with `--checkpoints-file` or update metadata signals when appropriate. |
| `human-checkpoint-required` disappears after a fix cycle | Label sync treated `needs-fixes` removal as satisfaction | Rerun lifecycle tests and require `satisfied` or `waived` checkpoint state before removing the label. |
| Delegated gate blocks with no concrete action | Stop reason omitted checkpoint metadata | Include `human_checkpoint_required`, item number, stage, domain, and `required_human_action`. |
| Batch merge includes checkpointed PRs silently | Discovery skipped the checkpoint-label filter | Verify `PR_HAS_HUMAN_CHECKPOINT` output and default skip behavior. |
| Audit comments duplicate | Stable marker lookup failed | Reuse `<!-- run-epic:pr-disposition -->`, `<!-- run-epic:epic-ledger -->`, and `<!-- run-epic:checkpoint-status -->`. |

---

## Known Limitations

- The smoke test uses fixture-backed shell tests for mutation-sensitive paths.
  Live GitHub runs should use disposable PRs and should not bypass checkpoint
  satisfaction by manually deleting labels.
- Checkpoints are scoped to delegated epic policy. Non-epic single-item runs do
  not receive checkpoint policy unless an orchestrator supplies it explicitly.
