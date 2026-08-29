# Strict Spec Contract Review — Implementation Plan

**Spec**:
[1_1650-strict-spec-contract-review_specs.md](./1_1650-strict-spec-contract-review_specs.md)
**Smoke test runbook**:
[1650-strict-spec-contract-review.smoke-test.md](../../../testing/workflow/1650-strict-spec-contract-review.smoke-test.md)

---

## Summary

**Approach**: Three of the four pieces already have a shape in this epic. A
checklist document supplied to the reviewer when the stage matches is #1654's
catalogue pattern; the stage itself is #1653's resolution; the state-and-count
reporting is the `key=value` and evidence plumbing both use.

The fourth piece is the one with no precedent and is where this plan spends its
attention: **the reviewer's parser has no third class of finding.** It sorts
each finding into blocking or advisory, and — this is the part that matters —
anything it cannot sort is counted as **blocking**. Strict findings must be
neither. Emitted without a change to that parser, eight new checks would turn
every spec review red.

So the plan adds an explicit marker on the finding, a third branch in the
parser that recognises it before the blocking test runs, and a rule that a
finding claiming to be strict but naming no known check is **not** treated as
strict — because the fail-open and the fail-closed here point in opposite
directions and the choice has to be made deliberately.

**Estimated complexity**: M

**Rationale**: The document, the supply and the reporting are each small and
patterned on merged plans. The parser change is not: it sits in a `jq` program
whose current invariant is *every finding is blocking unless proven advisory*,
and this feature adds a class that is neither while that invariant must keep
holding for everything else.

**Dependencies**: **#1653 must be implemented and merged before this item's
implementation PR opens** — the checks run only at the spec stage, and the
stage resolution is #1653's. **#1654 is not a dependency but overlaps**: both
add a document supplied through the context bundle and both add `print_kv`
lines. Whichever lands second inherits the other's fields; the plan records the
seam in **Interaction with #1654** rather than sequencing them.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `85dea08b` |
| The parser has two classes, and the residue is blocking | `sed -n '440,480p' scripts/development-workflow/local-ai-reviewer.sh` | `blocking` and `advisory` are `jq` predicates over severity and scope text. `$unknown` is `blocking \| not` **and** `advisory \| not`, and `$blocking_findings` is `blocking or ((blocking \| not) and (advisory \| not))` — so a finding matching neither predicate is emitted as blocking |
| An unclassifiable finding also forces `needs_fixes` | `sed -n '473,476p' scripts/development-workflow/local-ai-reviewer.sh` | `if $unknown > 0 then … RESULT=needs_fixes` — regardless of what the reviewer itself concluded. This is the behaviour strict findings must be exempted from, and the exemption must not weaken it for anything else |
| Blocking findings are what the loop forwards | Same range | `BLOCKING_<n>_PATH` / `_LINE` / `_BODY` are emitted from `$blocking_findings` only. A strict finding must not appear there, or the loop will treat it as a blocker regardless of the reviewer's own count |
| The bundle is built in one `jq -n` call | `sed -n '339,366p' scripts/development-workflow/local-ai-reviewer.sh` | Thirteen fields at this revision; #1653 adds three and #1654 four. This plan adds two more, at the same site |
| The stage resolution is #1653's | #1653's merged plan | `review_stage` is `spec` for `spec/*` branches; the strict checks key on that value and resolve nothing themselves |
| Evidence keys reach the loop summary unchanged | `sed -n '754,772p' scripts/development-workflow/pr-review-loop.sh` | `emit_prefixed_platform_output` re-emits every key it does not skip, so `STRICT_SPEC_*` needs no loop change |

**What this log does not establish.** It does not show how often the eight
checks will fire. That is the measurement the spec defers to #1657, and the
reason this feature reports counts rather than blocking on them.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1650 | 2026-08-29, repo SHA `85dea08b` | Epic #1647 items | `Verified` |
| The stage resolution exists | `review_stage` = `spec`, from #1653 | #1653's merged plan | 2026-08-29, repo SHA `85dea08b` | #1653 and #1650 | `Conflict` — see below |
| The parser's residue-is-blocking rule | A finding matching neither predicate is emitted as blocking and forces `needs_fixes` | `local-ai-reviewer.sh:440-476` | 2026-08-29, repo SHA `85dea08b` | `local-ai-reviewer.sh` and its two suites | `Verified` |

**Conflict record.** The checks run only at the spec stage, and the stage
resolution does not exist on the base branch: #1653's plan is merged, its
implementation is not. Affected plan statements: the supply condition and every
scenario that exercises it.

**Resolution status**: `Resolved` by sequencing — **Implementation Order step
0**, a hard stop on #1653. Decision owner: LH — if #1653 is implemented with
different stage values, this plan must be revised rather than adapted.

### Not applicable

**Overall result for this check**: `Applicable` — the three rows above must be
re-verified at implementation start.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no external API, no deployment target.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Add the checklist**,
      `docs/workflow/development-workflow/strict-spec-checks.md`, one level-3
      section per check, in the spec's order, each carrying its identifier, its
      question and the shape of finding it produces.

      The identifiers are a **closed set**, and the document is where they are
      defined. The parser and the tests read them from here rather than
      repeating them, so a ninth check is one edit and not four.

- [ ] **Supply it when the stage is `spec`.** Two fields on the context bundle,
      at the same `jq -n` site the other epic items use:

      ```text
      strict_spec_checks:       "<the checklist's stored bytes, or empty>"
      strict_spec_check_state:  "applied" | "not_applicable" | "unavailable"
      ```

      The state is decided by the spec's five-row matrix, whose three inputs are
      evaluated in order: can the stage be resolved, is it `spec`, is the
      checklist readable. The text is read with `jq --rawfile`, as #1654's is
      and for the same reason.

      Note what is **not** here: the count. It is not known when the bundle is
      built — the checks have not run — and it appears only in the output and
      the evidence, after the reviewer replies.

- [ ] **Give strict findings a marker the parser can see.** Each finding the
      reviewer emits for a strict check carries `strict_check: "<identifier>"`.
      The prompt instructs it; the parser keys on it.

      A marker on the finding rather than a separate array, because the finding
      already travels through `findings[]` with a path and a body, and a
      parallel array would need its own path and body handling and its own
      failure mode when the two disagree about length.

- [ ] **Add the third class to the parser, before the blocking test.** In the
      `jq` program in `local-ai-reviewer.sh`, a predicate and a partition:

      ```text
      def strict: (.strict_check? | type) == "string"
                  and ((.strict_check | ascii_downcase) as $c
                       | $known_checks | index($c) != null);

      $findings | map(select(strict))           as $strict_findings
      $findings | map(select(strict | not))     as $ordinary
      ```

      Every existing computation — `blocking`, `advisory`, `$unknown`,
      `$blocking_findings` and the `BLOCKING_<n>_*` lines — then runs over
      `$ordinary` and not over `$findings`. That single substitution is the
      whole behavioural change for ordinary findings: **none**. Scenario 5
      asserts byte-identical output for a review with no strict findings.

      **`$known_checks` is passed in from the checklist**, via `--argjson`, so
      the closed set has one definition. A strict finding naming a check the
      checklist does not define is **not** strict: it falls into `$ordinary`
      and is classified as it would be today, which for an unrecognised finding
      means blocking.

      **The partition is necessary and not sufficient: the emitted verdict has
      to be derived from ordinary findings, not inherited from a field the
      strict checks may have influenced.** Removing strict findings from the
      blocking set fixes the count; the parser's last branch honours the
      reviewer's own `result`, so a reviewer that read the checks, found three
      contradictions and concluded `needs_fixes` blocks with
      `BLOCKING_COUNT=0` — strict findings changing the verdict, which AC-3
      forbids.

      Two earlier revisions of this plan tried to repair that after the fact.
      One downgraded `needs_fixes` to `clean` whenever no ordinary blocker was
      parsed and a strict finding was present — which also unblocks a reviewer
      that blocked for a reason it never expressed as a finding. The other left
      the verdict alone and merely reported the ambiguity — which leaves strict
      findings blocking the pull request. **Both are withdrawn**; neither
      satisfies a rule that forbids movement in *either* direction, because both
      were guessing at a cause the response did not state.

      The response has to state it. Three parts:

      1. **The reviewer emits `ordinary_result`** alongside `result`: its verdict
         on the ordinary review, explicitly excluding strict findings. The
         prompt and the checklist's preamble require it.
      2. **The parser uses `ordinary_result` as the verdict** when present, and
         `result` only when it is absent — which is every review before this
         feature, and every review from a reviewer that emits no strict
         findings.
      3. **When `ordinary_result` is absent and strict findings are present**,
         the parser **does not infer a verdict**. It escalates: `RESULT=escalate`
         with the existing reason `malformed_output`, plus
         `STRICT_SPEC_VERDICT_UNRESOLVED=1`.

      The third part is the one two earlier revisions got wrong, in opposite
      directions, and the reason both were wrong is the same: with
      `ordinary_result` missing there is **no** verdict in the response that is
      known to exclude strict findings, and deriving one from the ordinary
      findings unblocks a review whose `needs_fixes` came from an ordinary
      reason the reviewer never wrote as a finding. Keeping `result` blocks a
      review whose verdict came from the strict checks. Every automatic
      resolution moves the verdict in one direction or the other, and AC-3
      forbids both.

      Escalating moves it in neither. The response failed to honour a contract
      the review depends on, which is what `malformed_output` already means, and
      the loop's existing handling — escalate, surface to a human, no fixer
      dispatched for a parse failure — is exactly right. Reusing the reason
      rather than minting one is the same choice #1656 made and for the same
      cause: the token carries behaviour, and a new one would inherit none of
      it. The finer detail lives in `STRICT_SPEC_VERDICT_UNRESOLVED`, which
      #1657 can count as the proxy for reviewers ignoring the contract.

      This is a real cost, stated rather than hidden: a reviewer that emits
      strict findings and omits `ordinary_result` produces no usable review, and
      the round is escalated. That is the price of a rule which forbids the
      verdict from moving in either direction, and it falls on a contract
      violation rather than on an ordinary review.

      **Reviewers that emit no strict findings are unaffected in every case.**
      `ordinary_result` absent and no strict findings means `result` is used
      exactly as today, which is what lets scenario 5 demand byte-identical
      output.

      Scenarios 9a through 9d cover the four combinations.

      That direction is deliberate and is the plan's sharpest choice. The
      alternative — treat any `strict_check` marker as strict — makes the
      marker a way to opt out of blocking: a reviewer that mislabels, or a
      future prompt that over-applies the field, silently downgrades real
      findings, and nothing in the output would show it. Fail-closed here means
      an unknown marker is treated as an ordinary finding, and the cost of the
      error is a false blocker rather than a missed one.

- [ ] **Report the state and the count.** Three `print_kv` lines beside the
      existing block:

      ```text
      STRICT_SPEC_STATE=applied|not_applicable|unavailable
      STRICT_SPEC_REASON=stage_unresolved|checklist_unreadable   # only when unavailable
      STRICT_SPEC_COUNT=<n>            # only when applied; empty otherwise
      STRICT_SPEC_CHECKS=<ids>         # comma-separated; only when applied
      STRICT_SPEC_VERDICT_UNRESOLVED=1 # only when ordinary_result was absent
                                       # and strict findings were present
      ```

      **`unavailable` has two causes and they have different owners**, which is
      why the state alone is not enough: `stage_unresolved` is a branch the
      resolver could not classify, and `checklist_unreadable` is a missing or
      unreadable document. The first is a defect in the pull request's shape,
      the second in the repository's contents, and a reader seeing only
      `unavailable` cannot tell which to go and fix. The spec's outcome table
      requires the cause to be reported; the reason key is where it lives.

      `STRICT_SPEC_REASON` is empty in `applied` and `not_applicable`, by the
      same rule that empties the count outside `applied`: a value present where
      it has no meaning invites a reader to interpret it.

      `STRICT_SPEC_COUNT` and `STRICT_SPEC_CHECKS` are **empty** in the two
      non-applied states, never `0` and never an empty list rendered as
      something. The spec's reason: `0` means the checks ran and found nothing,
      and it is the only thing distinguishing a clean specification from one
      they never examined. A `0` written for `unavailable` would put unexamined
      rounds into the denominator of #1657's rate.

      The same **four** values go into the evidence JSON under a `strict_spec`
      object, and into the ledger entry, so incidence can be computed per pull
      request without re-reading comments.

- [ ] **Render the findings separately.** The strict findings are emitted as
      their own `key=value` block — `STRICT_<n>_CHECK`, `STRICT_<n>_PATH`,
      `STRICT_<n>_LINE`, `STRICT_<n>_BODY` — parallel to `BLOCKING_<n>_*` and
      never mixed into it. A strict finding in the blocking block would be
      forwarded by the loop as a blocker whatever the counts say.

### Frontend / UI

- [ ] In the reviewer-loop summary, one grouped section for strict findings,
      each line naming its check. The section appears only when the state is
      `applied` and the count is above zero — the spec's outcome table has the
      comment surface touched in exactly one row.

### Infrastructure / Configuration

- [ ] Document the five keys, the three states, the two `unavailable` reasons,
      the unresolved flag's two conditions, the `ordinary_result` contract and
      its escalation, and the closed identifier set in
      the `--help` block, in
      `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`,
      and in Protocol 93.
- [ ] Add the checklist to `markdown-lint.yml`'s `paths` filter — a
      checklist-only change must still be linted, the same gap #1654 found in
      its own CI wiring.
- [ ] `changelog.d/1650.added.strict-spec-contract-review.md`.

---

## Interaction with #1654

Both items add a document to the context bundle, `print_kv` lines to the same
block, and an evidence object. They do not conflict in behaviour and do conflict
in lines:

| | #1654 | This item |
| --- | --- | --- |
| Document | the review doctrine, all stages | the strict checks, spec stage only |
| Bundle fields | four | two |
| Supplies when | always | `review_stage` is `spec` |
| Findings | none of its own | a third class, marked and partitioned |

Whichever lands second re-reads the merged `jq -n` object and the merged
`print_kv` block rather than this plan's copy of them. Scenario 11's enumerated
field list is built at implementation time for that reason.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. The state is `applied` at the spec stage with a readable checklist,
   `not_applicable` at every other stage, and `unavailable` when the stage
   cannot be resolved or the checklist cannot be read — one case per row of the
   spec's five-row matrix.
1a. The two `unavailable` rows are **distinguishable by their reason**:
   `stage_unresolved` for row 1, `checklist_unreadable` for row 3. Asserted as
   two different values, since the state alone leaves a reader unable to tell a
   defect in the pull request's shape from one in the repository's contents.
   `STRICT_SPEC_REASON` is empty in the other three rows.
2. `STRICT_SPEC_COUNT` and `STRICT_SPEC_CHECKS` are **empty** in
   `not_applicable` and `unavailable`, and present in `applied` — including
   `0` and an empty list when the checks found nothing. `STRICT_SPEC_REASON` is
   the mirror: present only in `unavailable`, empty in the other two.
3. A round recorded as `unavailable` is distinguishable from one recorded as
   `applied` with count `0`, by reading the ledger entry alone.
4. A finding carrying a **known** `strict_check` identifier is counted as
   strict, appears in `STRICT_<n>_*`, does not appear in `BLOCKING_<n>_*`, and
   does not change `RESULT`.
5. A review whose findings are all ordinary produces **byte-identical**
   `key=value` output to the same review before this change, excluding the keys
   this item adds. The unresolved flag cannot fire there — it requires a strict
   finding — so its absence is part of the comparison rather than an exclusion. The partition must be invisible to every existing path.
6. A finding carrying an **unknown** `strict_check` identifier is **not** strict:
   it is classified as an ordinary finding, which for an unrecognised finding
   means blocking, and `RESULT` becomes `needs_fixes`. This is the fail-closed
   direction, and the scenario fails if the marker alone is trusted.
7. A finding carrying `strict_check` with a non-string value — a number, an
   object, `null` — is also not strict, and the parser **does not abort**:
   `ascii_downcase` raises on a non-string, so the type guard has to run first.
   Asserted on all three values, since a program that errors here fails the
   whole review rather than classifying one finding.
8. A mixed review — two ordinary blocking findings and three strict — reports
   `BLOCKING_COUNT` 2, `STRICT_SPEC_COUNT` 3, and `RESULT=needs_fixes` driven by
   the two, not the three.
9a. `ordinary_result` **present** and `clean`, with `result` `needs_fixes` and
   three strict findings: the emitted verdict is `clean`, and
   `STRICT_SPEC_VERDICT_DERIVED` is absent. The reviewer stated its ordinary
   verdict; nothing is inferred.
9b. `ordinary_result` **present** and `needs_fixes`, with ordinary blocking
   findings: the emitted verdict is `needs_fixes`. The field is used in both
   directions, not only to unblock.
9c. `ordinary_result` **absent** with strict findings present: `RESULT=escalate`
   with reason `malformed_output` and `STRICT_SPEC_VERDICT_UNRESOLVED=1`. No
   verdict is inferred. Run with `result` `needs_fixes` **and** with `result`
   `clean`, and with ordinary findings present and absent — the escalation does
   not depend on which, because the missing field is what makes the response
   unusable.
9d. `ordinary_result` absent and **no** strict findings: `result` is used
   exactly as today, and `STRICT_SPEC_VERDICT_UNRESOLVED` is absent. Nothing
   escalates: with no strict findings there is nothing that could have
   influenced the verdict. This is every
   review before this feature and every ordinary review after it, which is what
   scenario 5's byte-identical requirement rests on.
9. A review with **only** strict findings reports `RESULT=clean`,
   `BLOCKING_COUNT` 0 and `STRICT_SPEC_COUNT` above zero. This is the spec's
   central claim and the one an implementation is most likely to get wrong by
   leaving `$unknown` computed over `$findings`.
10. `STRICT_SPEC_CHECKS` names the **distinct** checks that fired, not one entry
    per finding. Exercised with three findings drawn from a pair of checks: the
    key reports that pair, not three identifiers.
11. The bundle keeps every field present before this change — enumerated from
    the merged object at implementation time, not from this plan — and adds
    exactly two.
12. All **four** values reach the evidence JSON and the ledger entry, and the
    ledger's `strict_spec` object is present on every round at any stage — with
    the count and identifiers empty where the state is not `applied`, and the
    reason empty where it is not `unavailable`.
13. The checklist's identifiers are read from the document: adding a ninth
    section to a fixture checklist makes a finding carrying that ninth
    identifier strict, with no change to the parser or the tests.
14. **The checks fire on planted violations.** Eleven fixture specifications:
    **eight** positives, one per check, each containing exactly one planted
    instance of that check's shape; and **three** negative controls, one per
    acceptance criterion that requires *no* finding — a gate enumerating every
    reachable combination (AC-7); a gate that short-circuits and **states its
    evaluation order** (AC-6a); and an unsettled phrase appearing only in a
    rationale (AC-13). The reviewer is run against each with the checklist
    supplied, and the check that fired is recorded.
15. The same eleven fixtures with the checklist **absent**: the state is
    `unavailable` and no strict finding is produced. This is what separates *the
    reviewer found the violation because the checklist told it to look* from
    *the reviewer would have found it anyway* — without it, scenario 14 proves
    only that the reviewer is capable, not that this feature caused anything.

**Files**:

- `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — scenarios 1
  through 13. The parser scenarios run the real `jq` program with crafted
  reviewer output, not a stub, since the partition is the thing under test.
- The **smoke runbook** — scenarios 14 and 15, which need a real model.

**Scenarios 14 and 15 are recorded, not asserted, and the plan says so rather
than pretending otherwise.** Whether a model notices a planted contradiction is
not deterministic: a run may miss one, and a suite that failed the build on that
would be red for reasons no implementer could fix. What *is* deterministic —
that the checklist is supplied at the spec stage, that a marked finding is
partitioned, that the counts are reported — is scenarios 1 through 13, and those
are automated.

So the implementer runs the eleven fixtures both ways and **records which checks
fired in each**, in the pull request. A check that fires on its own planted
violation and not on the no-checklist run has demonstrated it does something; a
check that fires in neither has not, and that is a finding about the check worth
knowing before the counts start accumulating. Neither outcome gates the merge —
the same reasoning that makes the findings non-blocking makes this evidence
rather than a gate.

**Smoke test runbook**:
`docs/testing/workflow/1650-strict-spec-contract-review.smoke-test.md`

**Regression suite**: the harness named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Fixture specifications | **Eleven** short specification documents: eight positives, one per check, each with a single planted instance of that check's shape; and three negatives — a gate enumerating every reachable combination (AC-7), a gate that short-circuits and states its evaluation order (AC-6a), and an unsettled phrase confined to a rationale (AC-13) | `scripts/development-workflow/tests/fixtures/strict-spec-specs/` |
| Reviewer outputs | Eight JSON documents: all-ordinary; all-strict; mixed; a known identifier; an unknown identifier; a non-string `strict_check`; three findings from two checks; and one with no findings | inline in `scripts/development-workflow/tests/test-local-ai-reviewer.sh` |
| Checklist fixtures | A well-formed eight-section checklist; a nine-section one for scenario 13; and an unreadable one | `scripts/development-workflow/tests/fixtures/strict-spec-checks/` |
| Bundle field list | The field names present before this change, enumerated from the merged `jq -n` object at implementation time | inline in the same suite |

---

## Documentation Updates

- `docs/workflow/development-workflow/strict-spec-checks.md` — the checklist.
- The integration document and Protocol 93 — the keys, states and identifier
  set.
- The `--help` block of `local-ai-reviewer.sh`.
- `.github/workflows/markdown-lint.yml` — the checklist in `paths`.
- `changelog.d/1650.added.strict-spec-contract-review.md` — `added`: a class of
  finding that did not exist, and nothing changes for a repository whose
  reviewer emits none.

---

## Cross-Cutting Checklist Classification

**Classification**: `Not applicable`. Protocol 02's three signals are adding or
renaming a checklist category in `REVIEW.md` or a planning document; imposing an
acceptance criterion on every plan; and adding a conditional guidance block to a
planning or implementation protocol. This item adds a **new document read by one
script**, changes no `REVIEW.md` section, and requires nothing of any future
plan.

The contrast with #1653 is the useful one: that item added a section to
`REVIEW.md`, which is the first signal exactly. A checklist consumed only by
`local-ai-reviewer.sh` is not a review-contract category, and no agent or skill
file enumerates it.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Strict findings turn every spec review red | **High** without the parser change — the residue class is blocking | **High** — the feature is switched off within a day, and the counts it exists to produce are never gathered | The partition runs before `blocking`, and every existing computation reads `$ordinary`. Scenarios 4 and 9; proof **P1** leaves `$unknown` over `$findings` |
| The verdict is inherited from a field the strict checks may have influenced | **High** — `result` is what the parser reads today | **High** — AC-3 fails on the review the feature exists to produce: counts say non-blocking, pull request red | The reviewer emits `ordinary_result` and the parser prefers it; when it is absent with strict findings present, the round escalates rather than inferring. Scenarios 9a-9d; proofs **P8** and **P9** |
| A reviewer omits `ordinary_result` and its reviews stop working | Med — it is a new field | Med — spec reviews escalate until the prompt is fixed, which is visible immediately rather than silently wrong | Accepted and stated: escalation falls on a contract violation, and every automatic alternative moves the verdict in a direction AC-3 forbids. `STRICT_SPEC_VERDICT_UNRESOLVED` names it so the cause is unambiguous |
| The marker becomes a way to opt out of blocking | Med | **High** — a mislabelled or over-applied marker downgrades real findings, invisibly | Only identifiers the checklist defines count as strict; anything else is ordinary, which for an unrecognised finding means blocking. Scenarios 6 and 7; proof **P2** trusts the marker alone |
| A strict finding is forwarded as a blocker by the loop | Med | **High** — `BLOCKING_<n>_*` is what the loop reads; counts elsewhere would not save it | Strict findings are emitted in their own `STRICT_<n>_*` block and never in the blocking one. Scenario 4 and proof **P3** |
| The partition changes ordinary output | Med | Med — every review's output shifts for a feature that should be invisible to them | Byte-identical output required for an all-ordinary review. Scenario 5 and proof **P4** |
| `unavailable` is reported without its cause | Med | Med — a reader cannot tell a pull request whose stage could not be resolved from a repository missing the checklist, and the two have different owners | `STRICT_SPEC_REASON` carries `stage_unresolved` or `checklist_unreadable`. Scenario 1a and proof **P7** |
| `0` is written where the checks did not run | **High** — an empty numeric field invites a default | **High** — unexamined rounds enter #1657's denominator and the rate is wrong in the flattering direction | Count and identifiers are empty outside `applied`. Scenarios 2 and 3; proof **P5** |
| The identifier set is duplicated in the parser | Med | Med — a ninth check works in the document and not in the code, or the reverse | `$known_checks` is passed from the checklist. Scenario 13 and proof **P6** |

---

## Code Samples

The partition, and why it precedes everything:

```text
# `$known_checks` comes from the checklist via --argjson: one definition of the
# closed set, and a ninth check needs no parser edit.
def strict:
  ((.strict_check? // null)
     | if type == "string" then ascii_downcase else null end) as $c
  | $c != null and ($known_checks | index($c) != null);

. as $root
| (findings) as $all
| ($all | map(select(strict)))       as $strict_findings
| ($all | map(select(strict | not))) as $findings   # everything below is unchanged
```

Two details of that predicate are not stylistic. The identifier is captured into
`$c` **before** `$known_checks` becomes the input, because inside
`index(...)` the `.` is the array, not the finding — `index(.strict_check)`
raises *Cannot index array with string*. And the `if type == "string"` guard
runs before `ascii_downcase`, which errors on a number or an object: scenario 7
feeds exactly those, and without the guard the parser aborts rather than
classifying them as ordinary.

`findings` is the program's existing definition, which normalises `findings`,
`comments` or `issues` into one array; the sample calls it rather than reading
`.findings` so the partition sees the same set the rest of the program does.

Binding `$findings` to the ordinary subset is the whole change: `blocking`,
`advisory`, `$unknown`, `$blocking_findings` and the `BLOCKING_<n>_*` lines keep
their present text and now operate on the ordinary findings alone.

Verified as a standalone program against a four-finding fixture — one known
identifier, one unmarked, one unknown identifier, one numeric — which partitions
1 strict and 3 ordinary.

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The nine proofs fall into
two groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Blocking | **5** | P1, P3, P4, P8, P9 | a non-blocking class that blocks, or changes what does |
| Measurement | **4** | P2, P5, P6, P7 | a count or a class that admits what it should not |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P8 | Ignore `ordinary_result` and keep using `result` as the verdict | a scratch copy of the `jq` program | scenario 9a fails: a reviewer that stated a `clean` ordinary verdict is blocked by its own strict findings, which AC-3 forbids. Scenarios 9b and 9d pass, because there the two fields agree or neither is present; only a review whose strict findings changed its overall conclusion separates them; restoring the field's precedence passes |
| P9 | Infer a verdict when `ordinary_result` is absent — either by keeping `result` or by deriving from the ordinary findings | same scratch copy | scenario 9c fails on whichever half the plant chooses: keeping `result` blocks a review whose verdict came from the strict checks, deriving unblocks one whose `needs_fixes` came from an ordinary reason never written as a finding. Both move the verdict, and AC-3 forbids both. Scenario 9d passes either way, because with no strict findings there is nothing to be influenced by; restoring the escalation passes |
| P1 | Compute `$unknown` and `$blocking_findings` over `$all` instead of the ordinary subset | a scratch copy of the `jq` program | scenario 9 fails: a review whose only findings are strict reports `needs_fixes`, because the residue class is blocking — so every specification with eight checks applied turns red and the feature is switched off before it produces a single count; restoring the partition passes |
| P2 | Treat any `strict_check` marker as strict, without consulting the checklist | same scratch copy | scenario 6 fails: a finding naming an undefined check is exempted from blocking, so the marker becomes a way to opt out and a mislabelled real finding disappears from the blocking count with nothing in the output to show it; restoring the identifier test passes |
| P3 | Emit strict findings in the `BLOCKING_<n>_*` block as well as their own | same scratch copy | scenario 4 fails: the loop reads `BLOCKING_<n>_*` and forwards each as a blocker regardless of `BLOCKING_COUNT`, so the non-blocking guarantee holds in the reviewer and breaks one layer up; restoring the separate block passes |
| P4 | Rebuild the `BLOCKING_<n>_*` lines from a re-sorted array while partitioning | same scratch copy | scenario 5 fails: an all-ordinary review's output differs from before the change — different order, or a renumbered index — so a feature that should be invisible to ordinary reviews is not; restoring the untouched computation passes |
| P5 | Write `0` and an empty list for `unavailable` and `not_applicable` | a scratch copy of the print block | scenarios 2 and 3 fail: a round the checks never examined is indistinguishable from one where they found nothing, so #1657's rate counts unexamined specifications as clean — an error in the flattering direction, which is the one nobody questions; restoring the empty values passes |
| P7 | Report `unavailable` without a reason, or with one constant value | a scratch copy of the print block | scenario 1a fails: the two `unavailable` rows become indistinguishable, so a reader sees a state with two possible owners and no way to tell which — and the more likely of the two, a missing checklist, is the one a maintainer could fix in a minute. Every other scenario passes, because none reads the reason; restoring the two values passes |
| P6 | Hard-code the eight identifiers in the parser | same scratch copy | scenario 13 fails: a ninth check added to the checklist is recognised by no code, so its findings are classified as ordinary and block. The eight shipped checks still pass, which is why the scenario adds a ninth; restoring `$known_checks` passes |

P1 is the proof to read first: without the partition the feature does not
merely fail, it makes every specification review red, and the resulting pressure
is to disable the checks rather than to fix the parser.

---

## Implementation Order

0. **Hard stop**: confirm #1653 is implemented and merged and that
   `review_stage` carries `spec`. Re-read the merged `jq -n` object and
   `print_kv` block, which #1654 may also have changed.
1. Add the checklist document with its eight sections and identifiers.
   **Verify**: the identifiers match the spec's list, by extraction.
2. Add the partition to the `jq` program, binding `$findings` to the ordinary
   subset, **and** the `ordinary_result` precedence with its escalation.
   **Verify**: scenarios 4, 5, 6, 7, 8, 9, 9a, 9b, 9c and 9d — the parser scenarios
   first, because everything else is reporting.
3. Add the two bundle fields and the supply condition, carrying the cause when
   the state is `unavailable`. **Verify**: scenarios 1, 1a and 11.
4. Add the four `print_kv` lines, the `STRICT_<n>_*` block, the evidence object
   and the ledger fields. **Verify**: scenarios 1a, 2, 3, 10 and 12.
5. Pass `$known_checks` from the checklist. **Verify**: scenario 13.
6. Add the summary rendering. **Verify**: runbook Step 7.
6a. Write the eleven fixture specifications — eight positives, three negatives —
   and run the reviewer against each
   with the checklist supplied and again without it. **Verify**: scenarios 14
   and 15 — record which checks fired in each run, in the pull request. This is
   evidence, not a gate: a check firing in neither run is a finding about that
   check, and one worth having before the counts accumulate.
7. Update the `--help` block, the integration document, Protocol 93, the
   `paths` filter, and add the changelog fragment. **Verify**: runbook Step 9.
8. Produce the nine planted-violation proofs (P1-P9) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. It removes the checklist, the partition, two
bundle fields, four `key=value` keys, the `STRICT_<n>_*` block, the evidence
object, the ledger fields, the summary section, the `paths` entry and the
documentation updates. Reverting restores the two-class parser exactly; a
reviewer that still emits `strict_check` markers afterwards has them ignored,
and its findings are classified as they were before the feature existed.
