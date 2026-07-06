# Smoke Test Runbook: Run Item Autonomy Confirmation Preflight

**Feature**: Run item autonomy confirmation preflight (#1152)
**Spec**: [1_1152-run-item-autonomy-confirmation-preflight_specs.md](../../specs/developments/20260706121853_1152-run-item-autonomy-confirmation-preflight/1_1152-run-item-autonomy-confirmation-preflight_specs.md)
**Implementation plan**: [2_1152-run-item-autonomy-confirmation-preflight_implementation-plan.md](../../specs/developments/20260706121853_1152-run-item-autonomy-confirmation-preflight/2_1152-run-item-autonomy-confirmation-preflight_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for #1152 is checked out.
- [ ] `jq`, `bash`, `python3`, `npx`, and `gh` are available.
- [ ] `node_modules` is installed so `markdownlint-cli2` can run.
- [ ] No real tracker mutation is performed during the prelude checks.

---

## Test Data

| Item | Value |
| --- | --- |
| Bounded prelude helper | `scripts/development-workflow/run-bounded-prelude.sh` |
| Policy recommender helper | `scripts/development-workflow/run-epic-policy-recommender.sh` |
| Main shell test | `scripts/development-workflow/tests/test-run-bounded-prelude.sh` |
| Policy shell test | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Run-item protocol | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Run-item Codex skill | `.agents/skills/run-item/SKILL.md` |
| Legacy Codex orchestrator skill | `.codex/skills/workflow-item-orchestrator/SKILL.md` |
| Claude command | `.claude/commands/run-item.md` |
| Cursor command | `.cursor/commands/run-item.md` |

---

## Smoke Test Steps

### Step 1: Verify bounded prelude shell tests

**Maps to**: AC1, AC2, AC3, AC4, AC7, AC8, AC11

Run:

```bash
bash scripts/development-workflow/tests/test-run-bounded-prelude.sh
```

**Expected result**: The test exits successfully. The output includes passing
cases for inferred policy, explicit policy, checkpoint summary, text output, and
additive JSON summary fields.

### Step 2: Verify policy recommender shell tests

**Maps to**: AC3, AC6, AC7, AC8, AC11

Run:

```bash
bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
```

**Expected result**: The test exits successfully. Existing checkpoint waiver
validation still rejects waived checkpoints that lack `waiver_rationale`.

### Step 3: Inspect a run-item prelude summary

**Maps to**: AC1, AC2, AC3

Run a read-only prelude command against a safe test issue or a fixture-backed
environment chosen by the implementer:

```bash
./scripts/development-workflow/run-bounded-prelude.sh \
  --original-command '/run-item 1152' \
  --issue 1152
```

**Expected result**: The output is operator-facing and includes:

- Resolved item or scope information.
- Effective policy values.
- Field sources for policy values.
- Pending checkpoint guidance when checkpoints are present.
- Copy-paste equivalent.
- Read-only guarantee.

### Step 4: Verify explicit flags still print the summary

**Maps to**: AC2, AC4

Run:

```bash
./scripts/development-workflow/run-bounded-prelude.sh \
  --original-command '/run-item 1152 --delegate-review --may-merge --may-start-backlog true --max-risk medium --base develop' \
  --issue 1152 \
  --delegate-review \
  --may-merge \
  --may-start-backlog true \
  --max-risk medium \
  --base develop
```

**Expected result**: The summary prints before any mutation. Explicit policy
values are identified as explicit, unless repository guardrails narrow them.

### Step 5: Verify Protocol 91 no-redundant-prompt rule

**Maps to**: AC5, AC6

Inspect `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.

**Expected result**:

- The protocol names the invocation-scoped confirmation state.
- The backlog-start gate says a confirmed bounded prelude for the same resolved
  item satisfies the initial backlog-start confirmation.
- The protocol still names exceptions for unresolved checkpoints, CI/review
  failures, risk violations, destructive actions, missing permissions, and other
  named stop conditions.

### Step 6: Verify command-surface parity

**Maps to**: AC9, AC10

Inspect:

```bash
rg -n "confirmation summary|invocation-scoped|no redundant|pending checkpoint|explicit autonomy" \
  .agents/skills/run-item/SKILL.md \
  .codex/skills/workflow-item-orchestrator/SKILL.md \
  .claude/commands/run-item.md \
  .cursor/commands/run-item.md \
  .claude/agents/item-orchestrator.md \
  .cursor/agents/item-orchestrator.md
```

**Expected result**: Each primary run-item surface describes the same preflight
summary, explicit flag behavior, and no-redundant-prompt continuation rule.

### Step 7: Run markdown and shell guards

**Maps to**: AC11

Run:

```bash
python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
npx markdownlint-cli2 \
  "docs/workflow/development-workflow/**/*.md" \
  ".agents/skills/run-item/SKILL.md" \
  ".codex/skills/workflow-item-orchestrator/SKILL.md" \
  ".claude/commands/run-item.md" \
  ".cursor/commands/run-item.md" \
  "docs/testing/workflow/run-item-autonomy-confirmation-preflight.smoke-test.md" \
  "CHANGELOG.md"
```

**Expected result**: Both commands exit successfully.

### Last Step: Assertions Checklist

- [ ] `/run-item` prelude output includes an operator-facing confirmation
      summary before mutation.
- [ ] The summary includes effective policy, field sources, checkpoints, base
      branch, copy-paste equivalent, and read-only guarantee.
- [ ] Inferred policy and pending checkpoints remain confirmation-gated.
- [ ] Explicit autonomy flags still print a summary before proceeding.
- [ ] Protocol 91 prevents redundant prompts for the same confirmed policy.
- [ ] Protocol 91 still stops for new guardrail stops, unresolved checkpoints,
      blocking review findings, failing CI, missing permissions, destructive
      actions, and risk violations.
- [ ] Pending checkpoints require satisfaction or waiver rationale before their
      protected stage proceeds.
- [ ] The implementation reuses the shared bounded prelude and policy helpers.
- [ ] Docs explain explicit single-item autonomy flags.
- [ ] Codex, Claude, and Cursor run-item surfaces describe the same behavior.
- [ ] Shell tests and markdown/shell guards pass.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Run-item scope fixture | Inferred, explicit, ambiguous, and checkpoint policy tests | Created inside shell test temp directories |
| Checkpoint policy fixture | Valid and invalid checkpoint waiver tests | Created inside shell test temp directories |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Summary lacks field sources | `confirmationSummary` was built from effective values only | Include `fieldSources` data from the policy recommendation. |
| Explicit flags still ask for a second identical confirmation | Protocol 91 does not record invocation-scoped confirmation | Add and consume the confirmed-policy state for the same resolved item. |
| Pending checkpoint disappears after confirmation | Confirmation was treated as a waiver | Preserve checkpoint `satisfaction_state` and require waiver rationale. |
| Markdown lint fails on relative links | Link depth from `docs/testing/workflow/` is wrong | Use `../../specs/developments/...` for spec and plan links. |

---

## Known Limitations

- The smoke test validates workflow behavior through helper output, protocol
  text, and command-surface parity. A full end-to-end agent transcript still
  depends on the active runner following Protocol 91.
