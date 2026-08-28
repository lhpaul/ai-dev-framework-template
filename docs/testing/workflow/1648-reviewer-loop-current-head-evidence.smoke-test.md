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

2. Call `reviewer_loop_head_evidence_classify` once per row of the plan's
   parser-risk edge-case table, in table order.

**Expected result**: each call returns the state — and, where the table names
one, the reason — in that row's "Required result" column. In particular a
7-character abbreviation that prefixes the current head returns
`not-current|unverifiable_reviewed_head` rather than `current`; a 39- or
41-character value and a 40-character value with a non-hex character do the
same; an empty reviewed head returns `not-reported`; and an empty current head
or the synthetic `unknown-…` placeholder returns
`not-current|unverifiable_current_head`. Nothing but exact case-insensitive
equality of two full OIDs returns `current`.

3. Call `reviewer_loop_head_evidence_full_sha` with a 40-char hex value, a
   39-char hex value, a 41-char hex value, a 7-char abbreviation, a 40-char
   value containing one non-hex character, and the empty string.

**Expected result**: success only for the 40-char hex value; failure for all
five others. Full-OID equality is enforced, not merely documented, and no
abbreviation or prefix path exists to fall back to.

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

### Step 2b: One head snapshot, shared with the aggregate evidence

**Maps to**: the reuse-`loop_head_sha` rule in the plan's Layer-by-Layer
changes.

1. In the harness, mock `gh pr view --json headRefOid` so it returns a
   *different* SHA on every call.
2. Run one loop iteration and read the rendered summary block, the ledger entry,
   and the emitted `LOCAL_AI_HEAD_CURRENT`.
3. Compare the ledger entry's `classification_head` with the run's
   `POST_CLEAN_HEAD_SHA`.

**Expected result**: all three surfaces report the same current head and the
same per-platform classification, and `classification_head` equals
`POST_CLEAN_HEAD_SHA`. A differing value anywhere means a renderer issued its
own lookup instead of reading the pre-dispatch `loop_head_sha`, which the plan
places out of bounds. Confirm no `gh` call was added: the mock should be
consulted the same number of times as on the unmodified script.

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

3. Read the section emitted for a **pre-field ledger** fixture — an entry with
   no `reviewed_heads` field — with `local-ai-reviewer` configured and
   `--require-review-summary true`.
4. Read it again with `local-ai-reviewer` absent from the resolved platform
   list.

**Expected result**: `unavailable_required` in step 3 and
`unavailable_optional` in step 4. A pre-field ledger for a configured reviewer
must not pass as optional — that is the stale-verdict hole this item closes, and
`unavailable_required` keeps the item non-terminal until Step 7 is re-run on the
live head.

### Step 6: Protocol conditions are stated, not just implemented

**Maps to**: brief scope bullet 3.

1. Read the *Conditions for `ready-for-human-review`* section of Protocol 92.
2. Read the readiness checklist in Protocol 91 where `POST_CLEAN_HEAD_SHA` is
   already enforced.

**Expected result**: Both documents state the same fail-closed rule as the
implementation plan and as Step 7 below — when `local-ai-reviewer` is in the
resolved platform list and Step 7 returned `clean`, `LOCAL_AI_HEAD_CURRENT`
must be exactly `1`; both `0` and a present-but-empty value block
`ready-for-human-review`, the latter because the reviewer ran and reported no
head, which is missing evidence. Neither document may describe an empty value as
non-blocking: the non-applicable case is the **absent** key, emitted only when
the platform is not in the resolved list, and that distinction must be explicit
in both. Reading the two documents against the Step 7 table below must surface
no contradiction.

### Step 7: The three readiness states are distinguishable

**Maps to**: brief scope bullet 3 and the "downstream consumers" risk in the
plan.

1. Run the loop against a resolved platform list that omits
   `local-ai-reviewer`, using the harness mocks.
2. Run it again with `local-ai-reviewer` in the list but mocked to report no
   reviewed head.
3. Run it a third time with `local-ai-reviewer` reporting the current head.

**Expected result**:

| Run | `LOCAL_AI_HEAD_CURRENT` | Readiness |
| --- | --- | --- |
| Platform not in the resolved list | key absent from the output | condition does not apply; not blocked |
| Platform ran, reported no head | present and empty | **blocked** — missing evidence is not a pass |
| Platform ran, head matches | `1` | not blocked |

An absent key and an empty value must be distinguishable in the output; if the
loop emits an empty key in the not-configured run, the fail-closed rule would
stall every repository that does not configure the platform.

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
