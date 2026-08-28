# Smoke Test Runbook: Reviewer Loop Current-Head Evidence

**Feature**: Reviewer-loop current-head evidence
**Spec**: None — Refactor item. Source brief:
[issue #1648](https://github.com/lhpaul/ai-dev-framework-template/issues/1648)
**Implementation plan**:
[2_1648-reviewer-loop-current-head-evidence_implementation-plan.md](../../specs/developments/20260827210500_1648-reviewer-loop-current-head-evidence/2_1648-reviewer-loop-current-head-evidence_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #1648.
- [ ] The PR targets `develop-internal-reviewer-effectiveness`.
- [ ] `bash`, `jq`, and `git` are available. No network access or live GitHub
      mutation is required — every step runs against the repository checkout and
      the mocked harnesses.

---

## Test Data

| Item | Value |
| --- | --- |
| Reviewer loop | `scripts/development-workflow/pr-review-loop.sh` |
| Local reviewer | `scripts/development-workflow/local-ai-reviewer.sh` |
| Ground-truth self-check | `scripts/development-workflow/item-completion-self-check.sh` |
| Loop harness suite | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Dispatch suite | `scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh` |
| Self-check suite | `scripts/development-workflow/tests/test-item-completion-self-check.sh` |
| Readiness protocol | `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` |
| Work item runner protocol | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |

---

## Smoke Test Steps

### Step 1: Classification of reviewed head vs current head

**Maps to**: brief scope bullet 1 and bullet 2.

1. Source the loop in harness mode:

   <!-- workflow-shell-contract: bash -->

   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   ```

2. Call `reviewer_loop_head_evidence_classify` with: two identical 40-char
   SHAs; a 7-char abbreviation and the matching 40-char SHA; a 7-char value that
   does not prefix the 40-char SHA; an empty reviewed head; and a synthetic
   `unknown-…` placeholder against a real SHA.

**Expected result**: `current`, `current`, `not-current`, `not-reported`,
`not-current`, in that order. The synthetic placeholder must never classify as
`current`.

### Step 2: Head evidence in the reviewer-loop summary comment

**Maps to**: brief scope bullet 1.

1. Run the loop harness suite:

   <!-- workflow-shell-contract: bash -->

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Read the rendered summary body produced by the head-evidence cases.

**Expected result**: The body contains a single `**Head evidence:**` block that
names the current PR head once and lists one row per configured platform, each
row ending in `current`, `not-current`, or `not-reported`. The suite exits 0.

### Step 3: Reviewed heads recorded in the reviewer-loop ledger

**Maps to**: brief scope bullet 1, and the downstream needs of #1651 and #1657.

1. In the same harness, build a history entry and pipe it through `jq`.
2. Build a second entry from an existing payload that has no `reviewed_heads`
   field.

**Expected result**: The new entry carries a `reviewed_heads` array whose
elements have `platform`, `reviewed_head`, and `state`. The legacy payload still
parses and appends without error, confirming the `reviewer_loop_history.v1`
schema stayed backward compatible.

### Step 4: Stale local clean result is marked not-current

**Maps to**: brief scope bullet 2 and bullet 3.

1. Run the dispatch suite:

   <!-- workflow-shell-contract: bash -->

   ```bash
   bash scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh
   ```

2. Inspect the case where the mocked local reviewer reports a reviewed head that
   is an ancestor of the mocked live PR head.

**Expected result**: The loop emits `LOCAL_AI_REVIEWED_HEAD` with the ancestor
SHA and `LOCAL_AI_HEAD_CURRENT=0`. The suite exits 0.

### Step 5: Readiness claim is blocked on stale local evidence

**Maps to**: brief scope bullet 3.

1. Run the self-check suite:

   <!-- workflow-shell-contract: bash -->

   ```bash
   bash scripts/development-workflow/tests/test-item-completion-self-check.sh
   ```

2. Read the `## Ground-Truth Completion Verification` section emitted for the
   stale-ledger fixture and for the matching-ledger fixture.

**Expected result**: The stale fixture produces a
`pull_request.local_reviewer_head` row with status `discrepancy`; the matching
fixture produces `verified`. The suite exits 0.

### Step 6: Protocol conditions are stated, not just implemented

**Maps to**: brief scope bullet 3.

1. Read the *Conditions for `ready-for-human-review`* section of Protocol 92.
2. Read the readiness checklist in Protocol 91 where `POST_CLEAN_HEAD_SHA` is
   already enforced.

**Expected result**: Both documents state that a `clean` Step 7 result with
`LOCAL_AI_HEAD_CURRENT=0` blocks `ready-for-human-review`, and that an empty
value (platform not configured, or no head reported) does not block but must be
named in the runner summary.

### Step 7: Not-configured repositories are unaffected

**Maps to**: the "downstream consumers" risk in the plan.

1. Run the loop against a resolved platform list that omits
   `local-ai-reviewer`, using the harness mocks.

**Expected result**: `LOCAL_AI_HEAD_CURRENT` is empty, the head-evidence block
either is absent or lists only the configured platforms, and readiness is not
blocked.

### Step 8: Static checks

1. Run `shellcheck` on the two changed scripts.
2. Run `markdownlint-cli2` on the changed protocol documents, this runbook, and
   the implementation plan.

**Expected result**: Both tools exit 0.

---

## Rollback

Revert the implementation PR. The change is additive — a new optional ledger
field, two new stdout keys, one new self-check row, and two protocol bullets —
so reverting restores the previous behavior without migration. Ledger entries
already written with `reviewed_heads` remain parseable by the reverted reader,
which dereferences unknown fields with defaults.
