# Smoke Test Runbook: PR Risk Classification

**Feature**: PR Risk Classification for Delegated Merge Decisions
**Spec**:
[1_919-pr-risk-classification_specs.md](../../specs/developments/20260612184059_919-pr-risk-classification/1_919-pr-risk-classification_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #919.
- [ ] The PR targets `develop-delegated-epic-orchestration`.
- [ ] The implementation diff is available locally.
- [ ] Fixture tests are available and do not require live GitHub mutation.
- [ ] Any live PR classification is read-only.

---

## Test Data

| Item | Value |
| --- | --- |
| Classifier helper | `scripts/development-workflow/run-epic-risk-classifier.sh` |
| Classifier tests | `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh` |
| Run-epic protocol | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` |
| Codex alias | `.agents/skills/run-epic/SKILL.md` |
| Claude command | `.claude/commands/run-epic.md` |
| Cursor command | `.cursor/commands/run-epic.md` |

---

## Smoke Test Steps

### Step 1: Verify Low, Medium, High, and Blocked Classifications

**Maps to**: AC1, AC2, AC4, AC5, AC6, AC7, AC9

1. Run the classifier fixture test harness.
2. Inspect fixture cases for Low, Medium, High, and Blocked risk.
3. Confirm each classification includes specific reasons.

**Expected result**: Representative PR states classify deterministically and
include machine-readable and human-readable reasons.

### Step 2: Verify Hard-Blocker Precedence

**Maps to**: AC4

1. Inspect fixture cases for failing CI, pending CI, reviewer failure,
   unresolved blocking thread, `needs-setup`, missing credentials, ambiguous
   tracker/base state, dirty merge state, required force-push, and required
   destructive action.
2. Confirm each case produces `blocked` even when changed files would otherwise
   look Low or Medium risk.

**Expected result**: Blocked conditions take precedence over ordinary risk
levels.

### Step 3: Verify Max-Risk Gate

**Maps to**: AC3

1. Inspect fixture cases where assigned risk is above `--max-risk`.
2. Confirm output includes assigned risk, max allowed risk, and a merge-blocked
   decision.
3. Confirm `blocked` is never accepted as an allowed max-risk threshold.

**Expected result**: Autonomous merge is blocked whenever assigned risk exceeds
the invocation's maximum allowed risk.

### Step 4: Verify Medium-Risk Why-Safe Evidence

**Maps to**: AC8

1. Inspect a Medium-risk fixture with complete evidence.
2. Confirm output includes scope, tests, reviewer outcome, CI outcome, and
   rollback or cleanup risk.
3. Inspect a Medium-risk fixture with one missing or blank field.
4. Confirm incomplete evidence blocks autonomous merge.

**Expected result**: Medium-risk delegated merges are auditable and incomplete
evidence is not accepted.

### Step 5: Verify Read-Only Behavior

**Maps to**: AC1 through AC10

1. Inspect the classifier helper for `gh` and `git` command usage.
2. Confirm the fixture test fails if the helper invokes mutating commands such
   as label edits, tracker updates, comments, PR merge, branch deletion, issue
   close, or GraphQL mutation.
3. Confirm the helper does not run reviewer-loop or CI-loop itself.

**Expected result**: The classifier observes PR state and makes a gate decision
without mutating repository, PR, branch, issue, or tracker state.

### Step 6: Verify Run-Epic Integration Guidance

**Maps to**: AC1 through AC10

1. Open the run-epic protocol and command wrappers.
2. Confirm delegated merge guidance runs risk classification after normal
   reviewer/CI/readiness checks and before merge.
3. Confirm the docs say risk classification does not replace reviewer-loop,
   CI-loop, unresolved-thread, merge-state, or repository merge-protocol checks.

**Expected result**: `/run-epic` guidance uses risk classification as an
additional conservative gate, not as a substitute for existing quality gates.

### Step 7: Run Automated Validation

**Maps to**: AC1 through AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-risk-classifier.sh
   npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/919-pr-risk-classification.smoke-test.md" "AGENTS.md" "CHANGELOG.md"
   ```

2. Confirm all commands pass.

**Expected result**: Classifier behavior and documentation formatting are
validated.

---

## Assertions Checklist

- [ ] AC1: The classifier produces machine-readable and human-readable risk
      classification.
- [ ] AC2: Every classification includes specific reasons.
- [ ] AC3: Risk above `--max-risk` blocks autonomous merge.
- [ ] AC4: Hard blockers produce `blocked`.
- [ ] AC5: Clean docs, tests, narrow workflow text, or isolated helpers can
      classify as `low`.
- [ ] AC6: Clean contained workflow tooling changes can classify as `medium`.
- [ ] AC7: Sensitive or broad changes can classify as `high`.
- [ ] AC8: Medium-risk permitted merges include complete why-safe evidence.
- [ ] AC9: Low, Medium, High, and Blocked cases are covered by tests.
- [ ] AC10: Risk rules are visible in docs, fixtures, or helper structure.

---

## Seed Data Reference

No persistent seed data is required. Fixture tests provide temporary PR state
JSON for Low, Medium, High, Blocked, threshold mismatch, and invalid-input
cases.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| A sensitive PR classifies as Low or Medium | Changed-file category rules are too permissive | Prefer the higher risk when categories overlap and add a fixture for the path pattern. |
| Medium risk is permitted without why-safe evidence | Evidence validation is incomplete | Require non-empty scope, tests, reviewer outcome, CI outcome, and rollback or cleanup risk fields. |
| Fixture tests mutate live GitHub state | Test harness did not stub a mutating command | Add the command to the no-mutation guard and rerun with fixture-only data. |
| JSON output fails downstream parsing | Reasons or titles were not escaped through `jq` | Build JSON with `jq` or equivalent structured output, not string concatenation. |
| Markdown links fail lint | Relative link depth is wrong | Run `markdownlint-cli2` and fix links from the runbook directory. |

---

## Known Limitations

- The classifier is read-only. It does not run reviewer-loop, poll CI, resolve
  review threads, merge PRs, update tracker status, or write audit comments.
- File-category rules are conservative heuristics. Ambiguous or overlapping
  categories should classify to the higher risk until a maintainer narrows the
  rule.
