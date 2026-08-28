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
| Tier-1 normative-document predicate | `reviewer_loop_path_is_normative_document` |
| Tier-2 contract-surface predicate | `reviewer_loop_finding_touches_contract_surface` |
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

### Step 1: Two tiers — path decides first, body escalates second

**Maps to**: brief scope bullet 1.

Only **blocking** findings reach this rule at all: `small_findings_paths` is
built from `reviewer_loop_blocking_paths_from_output`. Advisory findings are out
of scope, so every case below is a finding the reviewer already said must be
fixed.

1. Source the loop in harness mode:

   <!-- workflow-shell-contract: bash -->

   ```bash
   HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
   ```

2. Call `reviewer_loop_path_is_normative_document` on the ten first-tier
   patterns and on five controls: `docs/project/1-business-domain.md`,
   `tests/fixtures/x.json`, `__snapshots__/x.snap`, `CHANGELOG.md` and
   `scripts/development-workflow/pr-review-loop.sh`.
3. Run the loop three times with a blocking finding on
   `docs/specs/developments/x/1_x_specs.md`: a body naming a decision matrix; a
   body reading only "trailing whitespace"; and a body reading "required error
   handling is missing", which contains **no** listed contract term.
4. Run it twice with a blocking finding on `docs/project/1-business-domain.md`:
   once cosmetic, once naming a decision matrix.

**Expected result**: step 2 matches all ten patterns and none of the five
controls. All three of step 3's findings are **non-small** — including the third,
which no vocabulary list would have caught. Step 4's cosmetic finding is
**small** and its contract finding is not.

Step 3's third case is the point of the two-tier design. A vocabulary-only rule
catches only findings that happen to use its words; *"required error handling is
missing"* and *"this permits an invalid value"* are contract findings containing
none of them, and would fall through and be cleared. The path tier is what makes
the guard fail-closed, and the vocabulary tier only escalates where a cosmetic
tail is still wanted.

Step 4 is the counterweight: the normative list is deliberately narrow, so
`docs/project/**`, fixtures, snapshots and `CHANGELOG.md` keep the cosmetic-tail
escape.

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
| `the decision gate is inconsistent`, run under **BSD grep** | match — the boundary uses `(^\|[^[:alnum:]_])…([^[:alnum:]_]\|$)`, not `\b`, which BSD grep does not recognise |
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
| a body containing a URL whose path contains `coverage-matrix` | match — a listed phrase still matches inside a URL |
| a body containing a URL whose path contains only `scope` | no match — bare `scope` is not a listed phrase, wherever it appears |
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

1. Seed a ledger with two prior small-findings rounds whose
   `classification_head` is an **older** commit and one whose
   `classification_head` is the **current** head. Run the counter.
1a. Seed a prior entry whose `classification_head` equals the current head but
   whose `reviewed_heads[]` contains one platform on an older commit; then one
   where both contributors name the `classification_head`. Run the counter for
   each.
1b. Seed a prior entry whose `head_sha` equals the current head while its
   `classification_head` is an older commit; then the two swapped. Run the
   counter for each.
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

**Expected result**: step 1 returns **1**, not 3 — a round classified against an
older commit ends the consecutive run rather than extending it.

Step 1a's first seed ends the run and its second counts: a round *classified*
against the current head is not evidence that every *contributor* reviewed it,
and accepting it would count evidence nobody produced for this commit. This is
the same per-contributor rule the deciding round is held to in step 5, applied
to the prior entries so both halves of `prior + 1` are checked identically.

Step 1b's first seed ends the run with `stale_head` and its second counts. The
counter must read `classification_head` and never `head_sha`: #1648's ledger
uses `head_sha` as the identity key the #1502 cap counters bucket on, and it can
legitimately differ from the commit the round actually described. All three cases in step 2 also end
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

4. Run it three more times. Two carry genuinely co-occurring causes: a round
   with both a shipped-path and a contract-surface finding, and a round whose
   findings are all small but which has one stale contributor and one reporting
   no head. The third is a **mutual-exclusivity** case rather than a
   co-occurrence: a round carrying a contract-surface finding **together with** a
   contributor on a stale head, where the two inputs are present but only one
   becomes a recorded cause.

**Expected result**: the four situations report `shipped_path`,
`contract_surface`, `stale_head` and `head_unknown` respectively; the firing run
reports an **empty** value, as does a run whose consecutive count was simply
short — `exhausted` and `not_small` describe an ordinary short run and are not
blocking reasons.

The three runs report `shipped_path`, `stale_head` and `contract_surface`
respectively.

The first two are the co-occurrence cases, and they test the two **within-group**
precedences: `shipped_path` outranks
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

### Step 6: The #1661 regression does not fire (tier 1)

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
unmodified loop it fires on round two.

This is **tier-1 coverage**. Those findings are on `docs/specs/developments/**`,
so their bodies are irrelevant to the outcome and this case would pass even if
the contract-surface test were completely broken. It proves the epic's actual
regression is closed; Step 6b is what proves tier 2 works.

### Step 6b: Tier 2 in isolation

**Maps to**: brief scope bullet 1, the content half.

1. In the same suite, inspect the case replaying the #1661 ledger shape and
   bodies on `docs/project/1-business-domain.md` — a non-normative, non-shipped
   path.

**Expected result**: the terminal rule does **not** fire. Here the path alone
would make the findings small, so only the contract-surface test can produce
that result. This is the only replay that exercises tier 2 end to end, and it
fails if the vocabulary matching is broken — which Step 6's case would not. This is the exact sequence that produced
24 `RESULT=clean` outcomes carrying live blocking findings across PRs #1660,
#1661 and #1662; the findings involved were contract defects — a deny-list where
the contract claimed fail-closed, an empty set treated as passing, an
unvalidated bound that defeated its own cap — not typographical ones.

### Step 7: The mechanism still terminates on a cosmetic tail

**Maps to**: the "tightening removes the mechanism" risk.

1. In the same suite, inspect the case replaying **Step 6b's** ledger exactly —
   same round count, adjacency, head and the same
   `docs/project/1-business-domain.md` path — with only the bodies changed to
   cosmetic ones.

**Expected result**: the terminal rule **does** fire. If Step 6b passes and this
fails, the change did not tighten tier 2 — it made it match everything.

Pairing with Step 6b rather than Step 6 is what makes this the strong form: the
two differ in **body alone** on a tier-2 path, so opposite outcomes isolate the
contract-surface test exactly. Pairing it with Step 6 would prove nothing, since
tier 1 makes those findings non-small whatever the body says.

### Step 8: Planted-violation proofs are present and two-directional

**Maps to**: `REVIEW.md` § Planted-violation proof.

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P14 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: fourteen proofs in three groups. **Ten** plant the
**permissive** direction — P1 through P5, P8, P10, P11, P12 and P14, reproducing the
original bug; P8 skips the current round's head check and requires Step 4's
fifth run to fail; P10 reads `head_sha` instead of `classification_head` and
requires Step 4's step 1b to fail; P14 breaks the contract-surface
matching entirely and requires Step 6b to fail while Step 6 still passes, which
is precisely why Step 6b exists; P11 checks only a prior entry's
`classification_head` and skips its `reviewed_heads[]`, requiring step 1a to
fail; **P12** drops tier 1 and leaves the vocabulary test as the only guard, requiring Step 1's third case — a contract finding containing no listed term — to fail. **Three** plant the
**restrictive** direction, and none is optional: **P13** replaces the portable
boundary with `\b` and requires Step 3's BSD row to fail; **P6** widens the
normative list and requires Steps 1, 2 and 7 to fail; **P7** restores the bare
common words to the contract-surface list and requires Step 3's seven bare-word
rows and Step 7 to fail. A tightening that disables the mechanism would pass
every permissive proof while introducing a different defect, and it is the more
likely mistake because it looks like success.

**One** — **P9** — is neither, and forms the third group: it inverts both
**within-group** `SMALL_FINDINGS_BLOCKED_BY` precedences, reporting
`contract_surface` over `shipped_path` and `head_unknown` over `stale_head`.
There is no cross-group ordering to invert, because content and currency causes
are mutually exclusive. It requires Step 5's **first two** co-occurring runs to fail — the
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
a **blocking** finding on a normative document is never small whatever it says,
a contract-surface finding is escalated on other documentation paths while a
cosmetic one there is not, **both** the prior counted rounds and the round being decided must be on
the current head, and an unknown head ends the run — and all three name the same
four `SMALL_FINDINGS_BLOCKED_BY` values. **None may describe the classification
as vocabulary-only**, and none may claim that *every* finding on a normative
document is non-small — only blocking findings reach this rule at all. Reading
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
