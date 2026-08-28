# Smoke Test Runbook: Small-Finding Terminal Policy

**Feature**: Tightened small-finding terminal policy for the reviewer loop
**Spec**: None — Refactor item. Source brief:
[issue #1652](https://github.com/lhpaul/ai-dev-framework-template/issues/1652)
**Implementation plan**:
[2_1652-small-finding-terminal-policy_implementation-plan.md](../../specs/developments/20260828063000_1652-small-finding-terminal-policy/2_1652-small-finding-terminal-policy_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #1652.
- [ ] The PR targets `develop-internal-reviewer-effectiveness`.
- [ ] #1648 is merged into that branch, so per-reviewer head evidence exists.
- [ ] `bash`, `jq` and `git` are available. No network access and no live GitHub
      mutation are required — every step runs against harness fixtures with
      mocked `gh` commands and inline ledger payloads.

---

## Test Data

| Item | Value |
| --- | --- |
| Reviewer loop | `scripts/development-workflow/pr-review-loop.sh` |
| Normative-document predicate | `reviewer_loop_path_is_normative_document` |
| Contract-surface predicate | `reviewer_loop_finding_touches_contract_surface` |
| Smallness aggregate | `reviewer_loop_all_findings_are_small` |
| Consecutive counter | `reviewer_loop_small_findings_prior_consecutive_count` |
| Loop harness suite | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Replay suite (new) | `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` |
| Round-count variable | `PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS` (default `2`, unchanged) |
| Blocked-reason key | `SMALL_FINDINGS_BLOCKED_BY` |
| Reviewer-loop protocol | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |

---

## Smoke Test Steps

### Step 1: Normative documents are shipped artifacts

**Maps to**: brief scope bullet 1.

1. Source the loop in harness mode:

   <!-- workflow-shell-contract: bash -->

   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   ```

2. Call `reviewer_loop_path_is_non_shipped_artifact` on the five paths the plan's
   Verification Log records as non-shipped today:
   `docs/specs/developments/x/1_x_specs.md`, `REVIEW.md`,
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`,
   `docs/best-practices/3-testing.md`, `docs/testing/workflow/x.smoke-test.md`.
3. Call it on four control paths: `docs/project/1-business-domain.md`,
   `tests/fixtures/x.json`, `__snapshots__/x.snap`, `CHANGELOG.md`.

**Expected result**: all five return **shipped**; all four controls still return
**non-shipped**. The controls matter as much as the five: a change that made
every documentation path shipped would pass step 2 and disable the terminal
mechanism entirely, which is a different defect rather than a fix.

### Step 2: A contract-surface finding is never small, wherever it lives

**Maps to**: brief scope bullet 1, the path-independent half.

1. Call `reviewer_loop_finding_touches_contract_surface` with one body per row of
   the plan's contract-surface table.
2. Call it with three cosmetic bodies: a typo report, a trailing-whitespace
   report, and a heading-capitalisation report.
3. Call `reviewer_loop_all_findings_are_small` with a finding whose **path is
   non-shipped** and whose **body names a decision matrix**.

**Expected result**: every contract-surface row matches; all three cosmetic
bodies do not; and step 3 reports the finding as **not** small. Step 3 is the
core of this item — the original rule would have called that finding small
because of its path alone.

### Step 3: The parser does not over-match or under-match

**Maps to**: the parser-risk addendum.

Call the contract-surface predicate with each case and read match / no-match:

| Body | Required result |
| --- | --- |
| `the delegates list is wrong` | no match — `delegates` must not match `gate` |
| `use a microscope analogy` | no match — `microscope` must not match `scope` |
| `the heading state is inconsistent` | no match — bare `state` is not a matched term |
| `a typo in the scope section` | no match — bare `scope` is not a matched term |
| `the status column is misaligned` | no match — bare `status` is not a matched term |
| `the gate heading needs a capital` | no match — bare `gate` is not a matched term |
| `fix the proof reading typo` | no match — bare `proof` is not a matched term |
| `parse is misspelled here` | no match — bare `parse` is not a matched term |
| `the contract section has a trailing space` | no match — bare `contract` is not a matched term |
| `the decision gate is inconsistent` | match — the qualified phrase |
| `failXclosed is wrong` | no match — each spelling is listed literally, never via a wildcard `.` separator |
| `the allow list is incomplete` | no match — only the hyphenated `allow-list` is a listed spelling |
| `this row is out of scope` | match — the qualified phrase |
| `the evidence state table is wrong` | match — the qualified phrase |
| `Acceptance Criteria are inconsistent` | match — case-insensitive |
| `FAIL-CLOSED contract is violated` | match — case-insensitive |
| a body quoting `decision gate` inside a fenced code block | match |
| a body containing a URL with `scope` in the path | match |
| `""` (empty) | no match |
| a whitespace-only body | no match |
| `this is not a decision gate` | match — the classifier does not read intent |
| a multi-line body whose only term is on the last line | match |

**Expected result**: exactly as tabulated. Two groups carry the weight, and both
guard the **restrictive** direction:

- The two **substring** rows. Without word-boundary matching, `delegates`
  matches `gate` and nearly every finding becomes non-small.
- The seven **bare common word** rows. Every matched term is a phrase or a
  qualified form precisely so that ordinary prose — "the heading state is
  inconsistent", "a typo in the scope section" — does not read as
  contract-bearing. An earlier draft listed these words bare; they were removed
  for this reason, and the three qualified rows at the end confirm the phrases
  still match.

Over-matching here disables the terminal rule while looking like a tightening,
which is the more likely of the two mistakes because it appears to succeed.

### Step 4: Counted rounds must be on the current head

**Maps to**: brief scope bullet 2.

1. Seed a ledger with two prior small-findings rounds recorded on an **older**
   head and one on the **current** head. Run the counter.
2. Seed a ledger whose prior round has an **absent** head; then an **empty**
   head; then a synthetic `unknown-<epoch>-<pid>-<rand>` placeholder. Run the
   counter for each.
3. Read the counter's **stop reason** in each run above, plus one run where the
   walk reaches the end of the ledger and one where it stops at a non-small
   round.
4. With `PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS` at its default `2`, seed two
   prior small rounds on a stale head and run the terminal decision.
5. Seed two prior small rounds **on the current head**, so the prior count is
   sufficient, and give the deciding round counted findings from **two**
   platforms. Run the terminal decision for four combinations: both platforms
   reporting `loop_head_sha`; one reporting a different head; one reporting no
   head; both stale.

**Expected result**: step 1 returns **1**, not 3 — a round on an older head ends
the consecutive run rather than extending it. All three cases in step 2 also end
the run. Step 3 returns `stale_head`, `head_unknown` (three times), `exhausted`
and `not_small` respectively; a bare count could not distinguish the first two,
which `SMALL_FINDINGS_BLOCKED_BY` must. Step 4 does **not** fire the terminal
rule and reports `SMALL_FINDINGS_BLOCKED_BY=stale_head`.

**Step 5**: only the first combination may fire. The other three must not —
`stale_head` for the differing head, `head_unknown` for the missing one, and
`stale_head` for both stale — and the summary line must name the platform
responsible.

Two things are being guarded. The consecutive run is `prior entries + 1`, and
the `+ 1` is the round being decided, so verifying only the prior entries would
let the rule terminate on findings describing a commit that is no longer the
head. And a round can aggregate blockers from several platforms, so the check is
per contributor: one platform's current-head evidence says nothing about what
another was looking at, which is why **every** contributor must report
`loop_head_sha` rather than any one of them.

An unprovable head must end the run rather than be skipped over: the terminal
rule exists to be demonstrated, and a round whose head cannot be established
cannot demonstrate anything.

### Step 5: The blocked reason is visible

**Maps to**: the "cannot tell a refusing loop from a failing one" risk.

1. Run the loop for each of four situations: a shipped-path finding, a
   contract-surface finding on a non-shipped path, a stale counted head, and a
   counted head that is a placeholder.
2. Run it once where the terminal rule fires.
3. Read `SMALL_FINDINGS_BLOCKED_BY` and the summary's small-findings line.

4. Run it three more times: a round carrying both a shipped-path and a
   contract-surface finding; a round whose findings are all small but which has
   one stale contributor and one reporting no head; and a round carrying a
   contract-surface finding **together with** a contributor on a stale head.

**Expected result**: the four situations report `shipped_path`,
`contract_surface`, `stale_head` and `head_unknown` respectively; the firing run
reports an **empty** value, as does a run whose consecutive count was simply
short — `exhausted` and `not_small` describe an ordinary short run and are not
blocking reasons.

The three co-occurring runs report `shipped_path`, `stale_head` and
`contract_surface` respectively.

The first two test the two **within-group** precedences: `shipped_path` outranks
`contract_surface` because a shipped path is a property of the artifact and
needs no reading of the finding text to act on, and `stale_head` outranks
`head_unknown` because a known-different head is the more specific statement.
Both are the cases proof P9 inverts.

The third run tests something else: it carries a contract-surface finding *and*
a contributor on a stale head, and must report `contract_surface` with **no
currency cause recorded at all**. Content and currency causes are mutually
exclusive by construction — the head of a counted round is only asked about once
the round qualifies as a small-findings round, so a non-small finding means the
head check is never reached. There is no content-versus-currency ordering to
test, and this run is the guard against re-introducing one.

In the first two runs the **summary line still names every cause present** —
precedence reduces only the single-valued key, and nothing is hidden by it.

The summary line names the matched contract-surface identity, not just that some
surface matched: `reviewer_loop_finding_touches_contract_surface` prints the
identity (`acceptance_criteria`, `fail_closed_semantics`, and so on) rather than
returning a bare boolean, so the renderer has a defined input. A body matching
two surfaces prints the first in table order. The summary line names the specific contract surface
or shipped path that kept the round non-small, so the reason is legible on the
PR without reading loop output.

### Step 6: The #1661 regression does not fire

**Maps to**: brief scope bullet 3, and the incidence recorded in the plan's
Verification Log.

1. Run the replay suite:

   <!-- workflow-shell-contract: bash -->

   ```bash
   bash scripts/development-workflow/tests/test-small-finding-terminal-policy.sh
   ```

2. Inspect the case built from PR #1661's actual history — consecutive rounds
   whose only findings were on `docs/specs/developments/**` with bodies naming
   fail-closed semantics, decision-matrix rows and acceptance criteria.

**Expected result**: the terminal rule does **not** fire, where on the
unmodified loop it fires on round two. This is the exact sequence that produced
24 `RESULT=clean` outcomes carrying live blocking findings across PRs #1660,
#1661 and #1662; the findings involved were contract defects — a deny-list where
the contract claimed fail-closed, an empty set treated as passing, an
unvalidated bound that defeated its own cap — not typographical ones.

### Step 7: The mechanism still terminates on a cosmetic tail

**Maps to**: the "tightening removes the mechanism" risk.

1. In the same suite, inspect the case replaying the identical ledger shape with
   bodies naming only a trailing space and a heading capitalisation.

**Expected result**: the terminal rule **does** fire. If Step 6 passes and this
fails, the change did not tighten the rule — it deleted it.

### Step 8: Planted-violation proofs are present and two-directional

**Maps to**: `REVIEW.md` § Planted-violation proof.

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P9 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: nine proofs in three groups. **Six** plant the
**permissive** direction —
P1 through P5 and P8, reproducing the original bug; P8 skips the current round's
head check and requires Step 4's fifth run to fail. **Two** plant the
**restrictive** direction, and neither is optional: **P6** makes every `docs/`
path shipped and requires Steps 1, 2 and 7 to fail; **P7** restores the bare
common words to the contract-surface list and requires Step 3's seven bare-word
rows and Step 7 to fail. A tightening that disables the mechanism would pass
every permissive proof while introducing a different defect, and it is the more
likely mistake because it looks like success.

**One** — **P9** — is neither, and forms the third group: it inverts the
`SMALL_FINDINGS_BLOCKED_BY` precedence so currency reasons outrank content
reasons. It requires Step 5's **first two** co-occurring runs to fail — the
content-group pair reporting `contract_surface` where a shipped path is present,
and the currency-group pair reporting `head_unknown` where a known-different
head is present. Both are genuine co-occurrences within a group, so both can
detect the inversion. P9 changes no
firing decision at all — the rule still terminates or refuses exactly as before
— and only changes which cause a maintainer is shown first. It is its own group
because a precedence defect is an **observability** defect, invisible to any
test that asserts only whether the rule fired.

### Step 9: Documentation agrees across all three surfaces

1. Read the small-findings section of
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
2. Read the added line in `REVIEW.md`.
3. Run `pr-review-loop.sh --help`.

**Expected result**: all three describe the same rule — normative documents are
shipped artifacts, a contract-surface finding is never small wherever it lives,
**both** the prior counted rounds and the round being decided must be on the
current head, and an unknown head ends the run — and all three name the same four
`SMALL_FINDINGS_BLOCKED_BY` values. Reading
them against Steps 1 through 5 must surface no contradiction.

### Step 10: Static checks

1. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh`.
2. Run `markdownlint-cli2` on the two changed documentation files, this runbook
   and the implementation plan.

**Expected result**: both tools exit 0.

---

## Rollback

Revert the implementation PR. The change is additive in behavior terms — two new
predicates, one renamed aggregate, one extra argument to the consecutive
counter, one new stdout key, and two documentation edits — and reverting
restores the previous, more permissive classification. No configuration
migration is involved: `PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS` keeps its
name, default and validation throughout, since this item changes what counts as
a qualifying round rather than how many are required. Ledger entries written
while the change was live remain readable by the reverted loop, which ignores
the fields it does not know.
