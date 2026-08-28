# Smoke Test: Missed-Finding Telemetry (#1651)

**Item**: [#1651](https://github.com/lhpaul/ai-dev-framework-template/issues/1651)
**Spec**: [1_1651-missed-findings-telemetry_specs.md](../../specs/developments/20260828014500_1651-missed-findings-telemetry/1_1651-missed-findings-telemetry_specs.md)
**Plan**: [2_1651-missed-findings-telemetry_implementation-plan.md](../../specs/developments/20260828014500_1651-missed-findings-telemetry/2_1651-missed-findings-telemetry_implementation-plan.md)

Steps 1 through 5 source the loop with `HARNESS_MODE=1` and call the derivation
directly; Steps 6 onward exercise the assembled behavior.

<!-- workflow-shell-contract: bash -->

```bash
HARNESS_MODE=1 source scripts/development-workflow/pr-review-loop.sh
```

Sourcing enables `set -euo pipefail` in this shell. Two of the functions below
return non-zero as a normal answer; call them inside an `if` or suffix with
`|| true`.

---

## Step 0: The current round is part of the evidence

**Maps to**: AC-1.

1. Run a round in which the **local reviewer reports clean** and an external
   reviewer reports blocking findings, on a pull request with a prior round
   whose local verdict was `needs_fixes`.
2. Run the same shape on a pull request with **no** prior round at all.

**Expected result**: both produce `clean_same_commit` and a **confirmed miss**.
Neither is classified from the prior round's verdict, and neither reports
`not_yet_run`.

Pin **both** arrays in each fixture: the composed synthetic entry must carry the
round's `reviewed_heads[]` as well as its `platform_results`. The selector takes
the outcome from one and the commit from the other, so composing only the
results yields an empty head, an undecidable ancestry and `unknown` — while
every assertion about the *outcome* still passes. Proof P21.

This is the case the feature exists for, and it is the one a natural
implementation cannot see. At the moment the records are built, the round's own
verdicts live only in the freshly collected `platform_result_records` — the
ledger entry that will carry them has not been written. A selector reading
persisted entries alone classifies the round from the *previous* one, or from
nothing, and every other step in this runbook still passes, because they all
supply the local verdict as prior history. Proof P14.

## Step 1: The most recent verdict wins, not the most recent clean one

**Maps to**: AC-4a.

1. Build a history payload with the local reviewer clean at iteration 2 and
   reporting findings at iteration 5.
2. Call `reviewer_loop_local_latest_verdict` with it.

**Expected result**: the iteration-5 verdict, outcome `needs_fixes`. The final
state is `not_clean`, and the round is neither a confirmed nor a possible miss.

This is the item's most likely implementation error and the reason the function
is named for recency. "The most recent clean verdict" is the same sentence with
the search order and the filter swapped, and it reads as the more helpful one —
it finds evidence where recency finds none. What it actually does is count a
round as missed on a verdict the reviewer itself had already superseded. Proof
P1.

## Step 2: "Has not run yet" and "will never run" stay apart

**Maps to**: AC-6.

1. Call the selector with a history that has **no entries at all** and a
   configured list that contains `local-ai-reviewer`.
2. Call it with the **same** empty history and a configured list that does not.

3. Call it with a history whose local-reviewer record is `skipped` with reason
   `not_configured`, and a configured list that **contains** the reviewer.

**Expected result**: `not_yet_run` and `not_configured` for 1 and 2, asserted as
those two values — not merely as two non-clean results. Call 3 returns
**`unavailable`**, never `not_configured`.

Call 3 is the disagreement between the two sources of `not_configured`. The list
says the reviewer is configured and will run; the round says it did not run. The
spec's `not_configured` means *will never run*, which the list contradicts, so
the honest state is a configured reviewer that did not run — `unavailable`. The
reverse disagreement cannot arise: the list is consulted first.

4. Call it with a configured list of **three** platforms, `local-ai-reviewer`
   among them; then with a list containing only `local-ai-reviewer-v2`.

**Expected result for call 4**: the three-platform list is recognised — not
`not_configured` — and the `-v2` list is not.

5. Call it with a list of **500** platforms whose **first** entry is
   `local-ai-reviewer`.

**Expected result for call 5**: recognised — not `not_configured`.

Call 5 is the SIGPIPE case. `grep -q` closes its input on the first match, so
under `set -o pipefail` a `printf | grep -Fxq` spelling lets the producer take
SIGPIPE on the remaining 499 lines and the failed pipeline reports a configured
reviewer as `not_configured`, removing every round on that repository from the
denominator. Both properties of the fixture are load-bearing: the **early**
match makes `grep` close early, and the **length** makes the producer still be
writing when it does. A here-string has no pipeline for `pipefail` to act on.
Proof P22, and the same hazard as the changed-files decode in #1653.

The configured list is newline-delimited, one platform per line
(`pr-review-loop.sh:8336-8339`), so membership must be a whole-line literal
comparison. A comma-split `case` matches only when the reviewer is the sole
entry, and reports a configured repository as `not_configured` — the state that
means *will never run* — excluding every round on it from the denominator. A
substring test accepts `local-ai-reviewer-v2`. Call 4 excludes both wrong
implementations, and it matters that the first case has three platforms: every
single-platform fixture passes under the comma-split. Proof P19.

The two calls differ only in the configured-platform argument, which is the
point: an empty history looks identical for a repository that has not run the
reviewer yet and one that never will, so no amount of history can separate them.
That is why the selector takes two inputs.

A pull request early in its life and a repository that will never produce local
evidence are different facts about different repositories. Summed, they make a
report unable to tell a young pull request from an unconfigured project. Proof
P4.

## Step 3: A healthy but silent history is `unknown`

**Maps to**: AC-7.

1. Call the selector with entries that **exist** but name no local-reviewer
   result.
2. Call it with an entry written **before** this change — `platforms` present,
   `platform_results` absent — whose aggregate `result` is `clean`.
3. Call it with an entry whose aggregate `result` is `needs_fixes` because an
   external reviewer failed, while the local reviewer's own entry in
   `platform_results` reads `clean`.

4. Call it with an entry whose local-reviewer record is
   `{"result": "unavailable", "raw_result": "skipped", "raw_reason": "unavailable"}`,
   and again with `{"result": "skipped", "raw_result": "skipped", "raw_reason": ""}`.

**Expected result**: `unknown` for 1 and 2; `clean` for 3; `unavailable` and
`skipped` for 4's two calls. A record is written in every case, and 1 and 2 are
neither confirmed nor possible misses.

Case 4's fixtures are **already normalized**, which is the point: normalization
happens once, at collection time, and `result` is what the selector reads. The
raw pair travels beside it for audit — `raw_result: "skipped"` with
`raw_reason: "unavailable"` versus an empty reason is what distinguishes a
reviewer that timed out from one deliberately skipped, and both arrive from the
companion script as `RESULT=skipped`. Assert all three fields, not just
`result`: a normalizer that dropped the raw pair would pass a check on `result`
alone while destroying the only evidence that the normalization was right.

The summary's display array cannot carry this distinction — it folds both into
the single word `unavailable` and renders escalations as `escalated (<reason>)`
— which is why `platform_results` is built from the raw pair at collection.
Proof P11 plants the display array as the source.

`unknown` here is not a failure — the history is readable and simply does not
say. That is why it belongs in the denominator rather than being dropped.

Case 2 is the fail-closed one. A pre-change entry carries only the **aggregate**
round result, and reading that as the local reviewer's verdict would record
rounds the local reviewer never ran as confirmed misses — in the historical half
of the data, where nobody checks. Proof P8.

Case 3 is the same confusion in the present tense: the aggregate says
`needs_fixes` because *someone* failed, and the local reviewer was clean. Only
`platform_results` distinguishes them.

Case 1 is separated from Step 2's `not_yet_run` by the presence of entries, not
by whether the search found anything — both searches come back empty-handed. A
pull request with forty rounds of history that says nothing about the local
reviewer is `unknown`, not "has not run yet". Proof P10.

## Step 3a: Normalization, one case per row

**Maps to**: AC-6, and the collection-time normalization table.

Run the collection step once per row of the plan's seven-row table and read the
stored record:

| Companion output | Stored `result` | `raw_result` / `raw_reason` |
| --- | --- | --- |
| `RESULT=clean` | `clean` | `clean` / `` |
| `RESULT=needs_fixes` | `needs_fixes` | `needs_fixes` / `` |
| `RESULT=skipped`, `REASON=unavailable` | `unavailable` | `skipped` / `unavailable` |
| `RESULT=skipped`, `REASON=not_configured` | `not_configured` | `skipped` / `not_configured` |
| `RESULT=skipped`, `REASON=by_policy` | `skipped` | `skipped` / `by_policy` |
| `RESULT=escalate`, `REASON=timeout` | `unavailable` | `escalate` / `timeout` |
| `RESULT=weird` | `unknown` | `weird` / `` |

**Expected result**: exactly as tabulated, with the raw pair asserted on every
row and not only the normalized value.

This runs against **collection**, not the selector: normalization happens once,
at collection time, and the selector only reads `result`. Four of these rows are
what a display-derived source cannot produce — `escalate` arrives as
`escalated (<reason>)`, a `DISPLAY_RESULT` override arrives as whatever the
platform chose, and both `skipped` reasons collapse into one word — so this step
is what makes P11's plant fail.

## Step 4: Ancestry answers four ways on a healthy repository

**Maps to**: AC-1 through AC-4.

1. Build a temporary repository: a root commit, branch A of two commits, and
   branch B of two commits from the same root.
2. Call `reviewer_loop_commit_ancestry` for a commit against itself, against a
   descendant, against an ancestor, and across the two branches.

**Expected result**: `same`, `ancestor`, `descendant`, `unrelated`.

Run this step in a shell that has sourced the loop, so `set -euo pipefail` is
active — which is how the script itself runs. Three of these four results pass
through a `git merge-base --is-ancestor` exit status of **1**, and a bare call
would terminate the shell there rather than return an answer. Every status must
be captured with `|| status=$?`, which is exempt from errexit. Proof P9.

## Step 5: Ancestry that cannot be computed is `undecidable`, never `unrelated`

**Maps to**: the `unknown` mapping, and the guard the whole feature's honesty
rests on.

1. Call the function with a commit SHA that does not exist in the repository.
2. Call it in a repository state where `git merge-base --is-ancestor` exits with
   something other than 0 or 1.
3. Call it with an empty commit argument.

**Expected result**: `undecidable` in all three, mapping to local evidence state
`unknown`.

**Asserted as `undecidable` specifically.** `git merge-base --is-ancestor` exits
0 for yes, 1 for no, and something else for an error. Folding "not 0" into "no"
returns `unrelated` — a *decided* answer meaning a force-push severed the
relationship — for a question the repository could not answer at all. The record
would assert something that was never established, and the number built on it
would be wrong in a way no reader could see.

Step 4 passes with the fold in place. That asymmetry is why this step exists and
why its fixture deliberately deletes an object. Proof P3.

## Step 6: Every state is reachable

**Maps to**: AC-1 through AC-7.

1. Call `reviewer_loop_local_evidence_state` once per row of the plan's
   eleven-row mapping table.

2. Call it once more with a local verdict carrying **no** `reviewed_head`,
   inside an entry whose `head_sha` is set and equal to the external reviewer's
   commit.

**Expected result**: the ten spec states, with `unknown` reached twice — once
from an undecidable ancestry and once from an unrecognised outcome. Call 2
yields **`unknown`**, not `clean_same_commit`.

Call 2 is the entry-head trap. An entry's `head_sha` is the live head at write
time — what the pull request pointed at when the row was written — not the
commit that reviewer examined. Falling back to it compares the external
reviewer's commit against a commit the local reviewer may never have looked at,
and produces a confirmed miss from two unrelated facts. It is invisible whenever
the two coincide, which is most rounds. Proof P16.

## Step 7: What creates a record, and what does not

**Maps to**: AC-5, AC-8, AC-9, AC-10.

1. Run a round whose blocking findings came from the **local** reviewer.
2. Run a round whose external findings are advisory only.
3. Run a round with external blocking findings whose local evidence state is
   `not_clean`.
4. Run two qualifying rounds with identical reviewer, commit and finding count.

5. Run a round with external blocking findings whose **reviewed commit cannot
   be established** from either source.
6. Run two rounds with identical evidence: one external platform that emits
   `REVIEWED_HEAD`, one that emits nothing — **with `loop_head_sha` set**, so a
   plausible substitute is available.

**Expected result**: no record for 1, 2 or 5; a record for 3; **two** records
for 4, neither replacing the other. Case 5's output states the attribution
failure and its reason.

Case 6's first round produces a record; the second produces **none** and an
attribution-failure report. `loop_head_sha` is deliberately available during the
second, because it is what an implementer reaches for: it is right there, and
substituting it turns an empty telemetry into one that produces data.

It is the wrong data. The dispatched head is what the loop *sent*, not what the
reviewer *read* — a reviewer that started late read a newer commit — and
`clean_same_commit` is defined against the commit the external reviewer
reviewed. Substituting would put unearned entries into the confirmed count,
invisibly. AC-11 requires no record when the commit cannot be established, and
that is what this case asserts. Proof P15.

Which is why the external adapters are extended **in this item** to emit
`REVIEWED_HEAD` from their own artifacts — a review comment's `commit_id`, a
check run's `head_sha`. Deferring that would have left every external round
rejected here and every acceptance criterion unreachable in operation, which is
not a shippable state. Step 7a covers the extraction and its two fail-closed
rules.

Case 5 is the third of the spec's three no-record paths, and the only one that
reaches attribution before failing — the other two are excluded before the
commit is ever consulted. Without it the only tested no-record cases would be
the two that never get that far.

Case 3 is the denominator, and it is the one an implementation drops first: a
record that is not a miss looks like noise. Without it the reported rate is
always 100%, because the numerator is the only thing counted. Proof P2.

Case 4 asserts that no de-duplication occurs even on identical records — the
loop genuinely ran twice, and two rounds finding the same thing is a real
observation about the reviewer, not a duplicate row.

## Step 7a: Each adapter emits the head from its own artifact

**Maps to**: AC-11, and the attribution rule.

1. A round whose review comments all carry the **same** `commit_id`.
2. A round whose review comments carry **two different** `commit_id` values —
   a reviewer that posted across a push.
3. A platform that produced only a **check run**, no comments.
4. A platform that produced a comment with **no** `commit_id`.

**Expected result**: cases 1 and 3 emit `REVIEWED_HEAD` — the comments'
`commit_id` and the check run's `head_sha` respectively — and produce records.
Cases 2 and 4 emit **no** head, produce no record, and report the attribution
failure.

Case 2 is the one that looks like ordinary defaulting. Taking the first
`commit_id` of two is the obvious implementation, and it names a commit that
some of the round's findings do not belong to — after which a
`clean_same_commit` can follow from a comparison against the wrong commit. A
reviewer whose findings straddle a push did not review one commit, and the
honest answer is that there is no head. Proof P17.

Both fail-closed rules land on AC-11's existing path, so nothing new is
introduced to handle them: no head, no record, reason reported.

5. Run one case per adapter from the plan's ten-row table, each against a
   fixture of its own artifact shape.

**Expected result**: nine emit a head; `claude-code-action` emits **none**.

GitHub attaches a commit to *review* comments and to *reviews*, never to issue
comments — so an adapter whose only artifact is an issue comment has no evidence
to offer. `claude-code-action` is that adapter today, and `pr-agent` escapes it
only because it also produces a check run. The no-head row is the one most
likely to be implemented wrong, because "every adapter emits a head" is the
natural reading of the requirement, so it is asserted per adapter rather than
described once. Proof P18.

## Step 8: An unwritable history reports only what was owed

**Maps to**: AC-7a, AC-7b.

1. With the history unwritable (`append_safe` at 0) and an external round
   reporting blocking findings on an establishable commit: run it.
2. With the history unwritable and **no** record owed — findings from the local
   reviewer, or advisory only: run it.

3. With the history unwritable and **no prior history block at all**: run it.

3a. Repeat case 1 once per unavailable reason: `malformed_history`,
   `unknown_schema`, `missing_history_json` and `prior_unavailable`.

**Expected result**: case 1 writes no record, leaves the previously posted
history block **byte-for-byte unchanged** — compared against a saved copy of the
prior body, never against a re-render — and states in the summary body that
telemetry could not be recorded and why, naming the reason the loop already
computed — one of the four: `malformed_history`, `unknown_schema`,
`missing_history_json`, or `prior_unavailable`. Case 2
produces **no** telemetry-failure report. Case 3 writes the unavailable stub,
which is what the stub is for.

Case 3a's four reasons are the complete set the loop produces, read from the
code rather than remembered: `missing_history_json` (`pr-review-loop.sh:6992`)
fires when the history marker is present but its JSON block is gone, which is
what a hand-edited comment produces and is the likeliest of the four in
practice.

Case 1 is a **change**, not a confirmation. Today the loop builds a replacement
payload with empty entries and renders it over the previous block, so a history
that merely failed to parse once loses every entry it held — and the loss is
invisible, because the stub looks like a well-formed report of a problem rather
than a deletion. Proof P7.

Case 2 fails whenever the two tests are ordered the other way, and that ordering
is the natural one: writability is a property of the loop and eligibility a
property of the round, so a programmer checks the cheap global first. It then
reports a failure nobody was waiting for, on rounds this feature had nothing to
do with. Proof P5.

## Step 9: The summary line and its bound

**Maps to**: AC-13, AC-14, AC-14a, AC-15.

1. Render a record whose findings touch **twelve** distinct files, all path
   names short.
2. Render a record touching twelve files whose paths each exceed 60 characters.
3. Render a record built from **eight** blocking findings spread over three
   files.
4. Render an entry carrying twenty records with long paths.
5. Render a record whose findings touch **two** files, both short.
6. Render a record whose path names are sized so the list would fill the line to
   exactly 200 characters **without** the remainder text.
7. Render the worst case: reviewer `claude-code-action`, state
   `Clean, unrelated commit`, classification `confirmed miss`, and both counts
   above 9,999.

**Expected result**: one line per record, each at most 200 characters, naming at
most three paths and **always** the total file count. Case 1 names three of its
twelve files. Case 2 names **zero** paths — the bound stops the list before the
first one fits — and still states the total, the state and the classification: a
valid line, not a failure. Case 3 reports `path_total` **3**, not 8, and names
three distinct files. Case 4 adds at most twenty lines and 4,000 characters.
Case 5 names both of its two files.

Read case 1's **record** as well as its line: the record holds all twelve
paths, de-duplicated and in first-appearance order, while the line names three.
The three-path bound is AC-14 and governs the line; AC-1 asks the record to
capture the files the findings touch and AC-16 requires it to be readable in
full later. A builder that stored three would pass every other step here,
because they all read the rendered line. Proof P20.

Case 6 is the boundary. The bound is met by **reservation**, not by writing
order: the renderer computes `budget = 200 − prefix − suffix − remainder_max`
*before* appending any path, where `remainder_max` is the longest `, +N more`
this record could produce. Appending until full and adding the remainder
afterwards overflows by exactly the text that announces the omission — so the
one line guaranteed to be short is the one that says it left something out.
Cases 1 through 5 pass with that defect in place, because none is near the
boundary. Proof P23.

Case 7 shows the bound is closed rather than merely usually satisfied. Both
counts render clamped as `9999+`, and the worst case still leaves at least 58
characters for paths: literals 42, reviewer 18, short SHA 8, two counts at 5,
state label 23, classification 14, `remainder_max` 13 — 142 of 200. The clamp is
the only one of those bounds this plan introduces, and it is what closes the
sum; a seven-digit count would reopen it. Proof P24.

Reserving the *maximum* rather than the actual remainder is deliberate: the
actual value is not known until the list stops, and a budget that depends on the
answer cannot be used to compute it.

Every line that omits files states **how many more**, computed from the paths
actually named rather than from a fixed three: case 1 reads `+9 more`, case 2's
zero-path line reads `+12 more`, and case 5 omits the remainder entirely rather
than printing `+0 more`. A renderer that subtracts a constant
three is correct only when exactly three paths fit — the common case, which is
why the other two are the ones tested. Proof P13.

Case 3 is the de-duplication check. `reviewer_loop_blocking_paths_from_output`
emits one line per **finding**, so three blockers in one file yield that path
three times. AC-14 asks for the number of *files*: without de-duplication a
record claiming twelve files on a pull request touching four overstates the
blast radius of every finding, and the three path slots can be filled by three
copies of one name. Proof P12.

The bound is enforced by **reservation**, not by truncation and not by writing
order — the paths sit in the middle of the line, so no ordering would protect
the suffix. The renderer computes
`budget = 200 − prefix − suffix − remainder_max` before appending any path, and
paths stop at the first that would exceed it. Truncating a finished line instead
removes the tail, which is where the state and the classification live, leaving
the reader a line of file names and no verdict — exactly inverted from what the
line is for. Proof P6.

## Step 10: The ledger keeps its contract

**Maps to**: the additive-schema decision.

1. Read a history entry produced by the implementation.
2. Assert each of the eighteen existing fields by name and type, and the
   `phase_after_clean` object with its five keys.
3. Assert `platform_results` and `missed_findings` are present and are arrays.
4. Assert `schema` still reads `reviewer_loop_history.v1`.

**Expected result**: all present and unchanged; exactly two fields added; the
schema string unchanged.

Asserted field by field rather than by counting, so an accidental rename cannot
be masked by an accidental addition. The schema string is deliberately not
bumped: the change is additive, and a bump would break a reader that validates
the string exactly while a new key it ignores would not.

## Step 11: Records carry their own classification

**Maps to**: AC-16, AC-17, AC-17a.

1. Read the records for a pull request that has one `clean_same_commit`, one
   `clean_earlier_commit` and three other states.
2. Produce the confirmed-miss count and the possible-miss count from the records
   alone.

**Expected result**: one confirmed, one possible, five records total. Neither
count folds into the other, and no reader-side mapping from state to
classification is needed.

`classification` is stored rather than re-derived because AC-17a requires a
later report to separate the counts, and a reader that re-derives it keeps a
second copy of the confirmed/possible rule. Two copies of a rule is one that
drifts.

## Step 12: The feature observes and nothing else

**Maps to**: AC-12.

1. Run a pull request to readiness with missed-finding records present.
2. Run the same pull request with the feature disabled.

**Expected result**: identical review outcome, readiness label and tracker
status. The records change what is *known*, never what happens.

## Step 12a: Documentation agrees with the implementation

**Maps to**: the documentation-drift risk.

1. Read the reviewer-loop history section of
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
2. Run `scripts/development-workflow/pr-review-loop.sh --help` and read the
   ledger description.
3. Read `changelog.d/1651.added.missed-finding-telemetry.md`.

**Expected result**: both describe the same two added fields
(`platform_results`, `missed_findings`), the same ten local evidence states, and
the same summary-line format including the remainder text. Neither may describe
`classification` as depending on anything but the local evidence state, and
neither may mention a dispatched-head fallback. Reading them against Steps 0
through 11 must surface no contradiction.

The fragment exists, is named `<item>.<kind>.<slug>.md` with a bare `1651`, and
its body reads as a finished changelog bullet from the reader's perspective —
what a pull request now records, and what it does not claim. A fragment that
describes the implementation rather than the change is the common failure and is
not what Protocol 03 Step 6 asks for.

## Step 13: Static checks

1. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh`.
2. Run

   <!-- workflow-shell-contract: bash -->

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-internal-reviewer-effectiveness
   ```

3. Run `markdownlint-cli2` on the changed documentation.

**Expected result**: all three exit 0.

## Step 14: Planted-violation proofs

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P24 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: twenty-four proofs in three groups — **fifteen**
overclaiming, **eight** contract, **one** under-recording, per the plan's
proof-group table.

The overclaiming group carries the weight because that direction has no symptom:
each of its plants produces a plausible number, and a number is believed. P3 is
the one to read twice — its plant passes every test written against a healthy
repository.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 10. The derivation functions
must be absent, and a freshly written history entry must carry neither
`platform_results` nor `missed_findings`.
