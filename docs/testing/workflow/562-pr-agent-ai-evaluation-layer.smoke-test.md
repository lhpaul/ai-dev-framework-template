# Smoke Test Runbook: AI Evaluation Layer for PR-Agent "Possible Issue" Findings

**Feature**: Add AI evaluation layer for PR-Agent "Possible Issue" findings in
reviewer loop
**Spec**: [../../specs/developments/20260510120000\_562-pr-agent-ai-evaluation-layer/1\_562-pr-agent-ai-evaluation-layer\_specs.md](../../specs/developments/20260510120000_562-pr-agent-ai-evaluation-layer/1_562-pr-agent-ai-evaluation-layer_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You have a local checkout of the repository on a branch with the
  implemented changes merged
- [ ] `gh` CLI is authenticated against the repository
- [ ] `scripts/development-workflow/pr-review-loop.sh` is executable
- [ ] You have an open PR in the repository to use as a test target (or create
  a draft PR on a scratch branch)

---

## Test Data

| Item | Value |
|---|---|
| Script under test | `scripts/development-workflow/pr-review-loop.sh` |
| Env var to simulate verdict | `POSSIBLE_ISSUE_EVAL_OUTCOME` |
| Possible Issue label string | `Possible Issue` |
| Other advisory label strings | `Edge Case`, `Logic Gap`, `Documentation Inconsistency` |
| Test PR number | Any open PR (replace `<PR>` in commands below) |

---

## Smoke Test Steps

### Step 1: Confirm new functions exist in the script

- Open `scripts/development-workflow/pr-review-loop.sh`
- Confirm `_extract_possible_issue_labels` function is present
- Confirm `run_pr_agent_possible_issue_evaluation` function is present

**Expected result**: Both function definitions are visible in the file.

---

### Step 2: Unit-level — `_extract_possible_issue_labels` isolates correctly

**Maps to**: Acceptance Criterion 4 (other labels must NOT trigger evaluation)

Run in a shell that has sourced the script's library functions (or extract the
function inline for testing):

1. Call `_extract_possible_issue_labels "Edge Case|Possible Issue|Logic Gap"`
2. Confirm the output is `Possible Issue` (only the matching label)

3. Call `_extract_possible_issue_labels "Edge Case|Logic Gap"`
4. Confirm the output is empty

5. Call `_extract_possible_issue_labels "possible issue"` (all lowercase)
6. Confirm the output is `possible issue` (case-insensitive match returns the
   label as found)

**Expected result**: Steps 2, 4, and 6 confirm the filter works correctly.

---

### Step 3: Fallback path — agent unavailable

**Maps to**: Acceptance Criterion 6

1. Run `pr-review-loop.sh` against a PR where PR-Agent has posted a comment
   containing a "Possible Issue" advisory label and the overall classification
   is `clean`.
2. Do NOT set `POSSIBLE_ISSUE_EVAL_OUTCOME` (leave unset or set to empty).

```bash
POSSIBLE_ISSUE_EVAL_OUTCOME="" \
  ./scripts/development-workflow/pr-review-loop.sh \
  --pr <PR> --platform pr-agent
```

**Expected result**:
- Script exits 0 (clean)
- Output contains `RESULT=clean`
- Output contains `POSSIBLE_ISSUE_EVAL_OUTCOME=unavailable`
- A `WARN` line about "code-reviewer agent unavailable" appears on stderr
- `ADVISORY_LABELS` still includes the "Possible Issue" label (label is not
  silently dropped)

---

### Step 4: Acknowledged path — finding is acceptable

**Maps to**: Acceptance Criteria 1 and 3

1. Run `pr-review-loop.sh` against the same PR as Step 3.
2. Set `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged`.

```bash
POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged \
  ./scripts/development-workflow/pr-review-loop.sh \
  --pr <PR> --platform pr-agent
```

**Expected result**:
- Script exits 0 (clean)
- Output contains `RESULT=clean`
- Output contains `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged`
- The reviewer loop summary comment posted to the PR includes the evaluation
  outcome ("acknowledged")
- No new fix commit is pushed to the PR branch

---

### Step 5: Fix pushed path — real bug found

**Maps to**: Acceptance Criterion 2

1. Run `pr-review-loop.sh` against the same PR.
2. Set `POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed`.

```bash
POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed \
  ./scripts/development-workflow/pr-review-loop.sh \
  --pr <PR> --platform pr-agent
```

**Expected result**:
- Script exits 3 (re-run sentinel)
- Output contains `RESULT=needs_rerun`
- Output contains `POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed`
- The orchestrator caller would re-invoke the loop on the new HEAD (verify
  this by checking protocol docs or by inspecting the orchestrator logic in
  Protocol 91/93)

---

### Step 6: Other advisory labels only — no evaluation triggered

**Maps to**: Acceptance Criterion 4

1. Run `pr-review-loop.sh` against a PR where PR-Agent has returned clean with
   only non-"Possible Issue" advisory labels (e.g., "Edge Case", "Logic Gap").
2. Leave `POSSIBLE_ISSUE_EVAL_OUTCOME` unset.

```bash
./scripts/development-workflow/pr-review-loop.sh \
  --pr <PR> --platform pr-agent
```

**Expected result**:
- Script exits 0 (clean)
- Output contains `RESULT=clean`
- Output does NOT contain `PR_AGENT_POSSIBLE_ISSUE_EVAL`
- Output does NOT contain `POSSIBLE_ISSUE_EVAL_OUTCOME`
- No code-reviewer agent dispatch is triggered

---

### Step 7: Spec / chore PR — evaluation is not exempted

**Maps to**: Acceptance Criterion 5

1. Identify or create a PR on an `implementation-plan/*` or `spec/*` branch.
2. Run the loop against it with a simulated "Possible Issue" advisory and
   `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged`.

```bash
POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged \
  ./scripts/development-workflow/pr-review-loop.sh \
  --pr <SPEC_PR> --platform pr-agent
```

**Expected result**:
- Script exits 0 (clean)
- Output contains `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged`
- The evaluation ran (no PR-type exemption was applied)

---

### Step 8: No advisory labels — baseline unchanged

**Maps to**: Acceptance Criterion 1 (negative / baseline path)

1. Run `pr-review-loop.sh` against a PR where PR-Agent returned
   "No major issues detected" (no advisory labels at all).

```bash
./scripts/development-workflow/pr-review-loop.sh \
  --pr <PR> --platform pr-agent
```

**Expected result**:
- Script exits 0 (clean)
- Output contains `RESULT=clean`
- Output does NOT contain `POSSIBLE_ISSUE_EVAL_OUTCOME`
- No evaluation step is triggered

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met
- Clean up any scratch PRs or test branches created during this runbook

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: When PR-Agent posts a `Possible Issue` finding and the overall
  classification is `clean`, the reviewer loop emits `PR_AGENT_POSSIBLE_ISSUE_EVAL`
  for the orchestrator caller to dispatch a code-reviewer agent before declaring the
  result `clean`
- [ ] AC-2: If `POSSIBLE_ISSUE_EVAL_OUTCOME=fix_pushed`, the script exits 3 and
  emits `RESULT=needs_rerun` so the orchestrator re-runs the loop on the new HEAD
- [ ] AC-3: If `POSSIBLE_ISSUE_EVAL_OUTCOME=acknowledged`, the script exits 0 and
  emits `RESULT=clean`; the loop summary comment includes the acknowledgment outcome
- [ ] AC-4: Advisory labels other than "Possible Issue" do NOT trigger evaluation;
  the script exits 0 cleanly without emitting `PR_AGENT_POSSIBLE_ISSUE_EVAL`
- [ ] AC-5: A "Possible Issue" label on a spec or chore PR is evaluated correctly
  (no PR-type exemption); the loop exits clean after acknowledgment
- [ ] AC-6: When `POSSIBLE_ISSUE_EVAL_OUTCOME` is unset or empty, the script logs a
  `WARN`, emits `POSSIBLE_ISSUE_EVAL_OUTCOME=unavailable`, exits 0, and the advisory
  label remains visible in the loop summary output

---

## Seed Data Reference

| Entity | Scenario | How to load |
|---|---|---|
| Open PR with PR-Agent "Possible Issue" comment | Any PR where PR-Agent has posted a reviewer guide comment containing the "Possible Issue" advisory label | Use an existing PR or push a commit to trigger PR-Agent on a scratch branch |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `RESULT=clean` but `POSSIBLE_ISSUE_EVAL_OUTCOME` is absent | Advisory labels contain "Possible Issue" but the detection function did not match | Verify `_extract_possible_issue_labels` with the exact label string from the PR-Agent comment |
| Script exits 1 (needs\_fixes) instead of 3 (needs\_rerun) | `needs_rerun` RESULT value not handled in the outer loop's `case` block | Check Step 5 of the Implementation Order — `needs_rerun` must be added to `run_platform_review` and the main `case` |
| `WARN` not appearing on stderr for unavailable fallback | `run_pr_agent_possible_issue_evaluation` not reached (short-circuit too early) | Confirm the advisory label string passed to the function contains "Possible Issue" |
| Advisory label disappears from summary when `POSSIBLE_ISSUE_EVAL_OUTCOME=unavailable` | `_post_review_summary` not preserving advisory labels on fallback path | Verify `aggregate_advisory_labels` is still populated and passed to `_post_review_summary` in the unavailable branch |

---

## Known Limitations

- This smoke test uses the `POSSIBLE_ISSUE_EVAL_OUTCOME` environment variable
  to simulate agent verdicts without actually dispatching the code-reviewer
  agent. End-to-end testing against a live agent dispatch requires a real PR
  with a real PR-Agent comment and a running orchestrator session.
