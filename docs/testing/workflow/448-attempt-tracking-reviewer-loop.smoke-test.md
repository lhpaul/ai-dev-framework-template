# Smoke Test Runbook: Attempt Tracking for Reviewer Loop Prompts

**Feature**: Add attempt tracking to reviewer loop prompts
**Spec**: [`docs/specs/developments/20260504142615_448-attempt-tracking-reviewer-loop/1_448-attempt-tracking-reviewer-loop_specs.md`](../../specs/developments/20260504142615_448-attempt-tracking-reviewer-loop/1_448-attempt-tracking-reviewer-loop_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Protocol 91 Step 7 has been updated to include the `### Attempt-context injection rule` subsection
- [ ] Protocol 93 has been updated with the matching `### Attempt-context injection rule` subsection
- [ ] You have access to the updated protocol files and can read them

---

## Test Data

| Item | Value |
|---|---|
| Protocol 91 | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Protocol 93 | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Target section in 91 | Between `### Fixer agent batching rule (mandatory)` and `### Loop parameters` |
| Target section in 93 | After `### Fixer agent batching rule (mandatory)` |

---

## Smoke Test Steps

### Step 1: Verify Protocol 91 — First dispatch has no attempt-context prefix

**Maps to**: Acceptance Criterion 1

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
2. Locate the `### Attempt-context injection rule` subsection in Step 7
3. Confirm there is an explicit rule stating that when `cycle = 1` (first fixer dispatch), no attempt-context prefix is added to the fixer prompt

**Expected result**: A clear statement that cycle = 1 dispatches use the standard prompt with no attempt-context prefix

---

### Step 2: Verify Protocol 91 — Retry dispatch prompt format

**Maps to**: Acceptance Criteria 2, 3, 4

1. In the same `### Attempt-context injection rule` subsection, locate the retry dispatch rules (cycle ≥ 2)
2. Confirm the documented prompt format begins with `"Attempt N/M:"` where N is the current cycle value
3. Confirm the format specifies that N matches the loop's `cycle` counter
4. Confirm the format specifies that M is the `max_cycles` parameter

**Expected result**: The subsection explicitly states N = current `cycle` value and M = `max_cycles` (default: 10)

---

### Step 3: Verify Protocol 91 — Per-attempt summary content and accumulation

**Maps to**: Acceptance Criteria 5, Use Case 3

1. In the `### Attempt-context injection rule` subsection, locate the per-attempt summary rules
2. Confirm the rule specifies one-to-two plain-language sentences per prior attempt
3. Confirm the rule requires summaries for ALL prior attempts (not only the most recent) when cycle ≥ 3
4. Confirm the rule states that summaries are derived from the PR feedback ledger and fixer response/commit

**Expected result**: Accumulation rule is explicit — cycle N includes summaries for attempts 1 through N-1

---

### Step 4: Verify Protocol 91 — Reappearance notation

**Maps to**: Acceptance Criterion 6

1. In the `### Attempt-context injection rule` subsection, locate the reappearance handling rule
2. Confirm the rule states that when a finding reappears (was marked resolved, then opened again), the per-attempt summary for the cycle where it was "resolved" must note the reappearance explicitly

**Expected result**: A specific rule about reappearance notation with example wording similar to "fix did not hold — finding reappeared in cycle N"

---

### Step 5: Verify Protocol 91 — Attempt-context prefix is additive

**Maps to**: Acceptance Criterion 7

1. In the `### Attempt-context injection rule` subsection, confirm the rule states that the attempt-context prefix is prepended in addition to the standard blocking-findings list
2. Confirm there is no statement that the prefix replaces the findings list

**Expected result**: An explicit statement that the prefix does not replace the standard blocking-findings list

---

### Step 6: Verify Protocol 91 — Fallback when no prior-attempt summary is available

**Maps to**: Use Case 1 Considerations, Acceptance Criterion 5

1. In the `### Attempt-context injection rule` subsection, locate the fallback rule
2. Confirm the fallback phrase is similar to: "Attempt N/M: prior attempt did not fully resolve all findings. Try a different approach."

**Expected result**: A clearly documented fallback message for cases where no per-attempt summary was recorded

---

### Step 7: Verify Protocol 93 — Same rule is documented

**Maps to**: Acceptance Criterion 9

1. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
2. Locate the `### Attempt-context injection rule` subsection after the `### Fixer agent batching rule (mandatory)` block
3. Confirm it contains the same rule as Protocol 91 (first dispatch unchanged, retry format, accumulation, reappearance, additive prefix, fallback)

**Expected result**: Protocol 93 contains an equivalent `### Attempt-context injection rule` subsection covering all the same rules as Protocol 91 Step 7

---

### Step 8: Verify Protocol 91 — Step 7 cycle counter documentation

**Maps to**: Acceptance Criterion 3

1. In Protocol 91 Step 7, find where `cycle` is initialized (`Initialize cycle = 0`)
2. Confirm the `### Attempt-context injection rule` subsection references the same `cycle` variable
3. Confirm the subsection states that N shown in the prompt matches the `cycle` counter exactly

**Expected result**: N in the prompt is explicitly defined as the current `cycle` counter value, with no offset or separate counter

---

### Last Step: Validate & Shut Down

- Confirm all assertions in the checklist below are met
- No application to shut down (documentation-only change)

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: First dispatch (cycle = 1) prompt has no attempt-context prefix
- [ ] AC-2: Retry dispatch (cycle ≥ 2) prompt begins with "Attempt N/M:" followed by prior-attempt summary and remaining findings
- [ ] AC-3: N in the prompt matches the loop's `cycle` counter value
- [ ] AC-4: M in the prompt matches the `max_cycles` parameter
- [ ] AC-5: Per-attempt summary is one-to-two plain-language sentences; all prior attempts are included for cycle ≥ 3
- [ ] AC-6: When a finding reappeared after a prior fix, the summary notes the reappearance explicitly
- [ ] AC-7: Attempt-context prefix is prepended to (not a replacement of) the standard blocking-findings list
- [ ] AC-8: Protocol 91 Step 7 documents the attempt-context injection rule and required prompt format
- [ ] AC-9: Protocol 93 documents the same rule for the standalone reviewer loop path

---

## Seed Data Reference

None — this is a documentation-only feature with no application data requirements.

| Entity | Scenario | How to load |
|---|---|---|
| N/A | N/A | N/A |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `### Attempt-context injection rule` subsection missing from Protocol 91 | Implementation step 2 was not completed | Re-run the implementation and add the subsection after `### Fixer agent batching rule (mandatory)` |
| `### Attempt-context injection rule` subsection missing from Protocol 93 | Implementation step 3 was not completed | Add the subsection in the matching position in Protocol 93 |
| N or M in the prompt format definition does not match cycle / max_cycles | Cross-section inconsistency during authoring | Re-read both subsections and align variable names with the existing loop parameters table |

---

## Known Limitations

- This smoke test verifies protocol documentation correctness only. It does not test runtime orchestrator behaviour — live validation requires observing an actual multi-cycle reviewer loop dispatch with a PR that has persistent findings.
