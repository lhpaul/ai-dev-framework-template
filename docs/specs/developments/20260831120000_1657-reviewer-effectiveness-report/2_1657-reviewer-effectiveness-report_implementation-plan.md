# Reviewer Effectiveness Report — Implementation Plan

**Spec**:
[1_1657-reviewer-effectiveness-report_specs.md](./1_1657-reviewer-effectiveness-report_specs.md)
**Smoke test runbook**:
[1657-reviewer-effectiveness-report.smoke-test.md](../../../testing/workflow/1657-reviewer-effectiveness-report.smoke-test.md)

---

## Summary

**Approach**: One new script, `reviewer-effectiveness-report.sh`, which fetches
each pull request's reviewer-loop summary comment, extracts its history payload,
and prints seven measures per pull request plus an aggregate and an exclusion
accounting. It writes nothing anywhere.

Three decisions carry the plan:

1. **The marker, the schema and the extractor move to `workflow-lib.sh`.** The
   history's format is currently defined inside `pr-review-loop.sh` — the
   producer — and this item adds a second reader. Two copies of a comment format
   drift silently, and the drift would show up as pull requests reported as
   having no history when they have one.
2. **The report does not reuse `reviewer_loop_history_entries_count`**, and this
   is the single most important line in the plan. That function returns
   `0 0 available` for a body with no history marker at all — it treats *no
   history* as *zero rounds, and trustworthy*. That is correct for its own
   caller, which is asking "how many cycles has this pull request used"; it is
   exactly the silence-as-zero conflation the spec forbids, and reusing it would
   put pull requests the loop never ran on into every denominator as clean.
3. **Availability is decided per measure, from the fields actually present.**
   The report reads which fields a round carries rather than assuming a schema
   version implies them, so a history written before an epic item shipped
   reports `not_recorded` for that item's measures and numbers for the rest.

**Estimated complexity**: M

**Rationale**: The arithmetic is small and the fetching is patterned on code
that exists. What makes it M is that every failure mode is a wrong number rather
than an error: a conflated denominator, a `//` default that turns absence into
zero, an incidence sum over rounds. None of them crashes, and all of them
produce a report that reads as authoritative.

**Dependencies**: **none that block.** This is the one item in the epic that can
ship before its data producers, and the spec is built for it: measures whose
fields are absent report `not_recorded`. #1648 supplies measure 7's fields,
#1651 supplies measures 2, 4 and 5, and #1650 and #1655 supply the strict-check
section. Until each lands, the report says so per measure rather than reporting
zero — which is the behaviour AC-13 requires and scenario 6 asserts against a
fixture written to today's schema.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `77cdb1c5` — after this item's spec (#1682) merged. Every row below was run at this revision |
| The history's marker and schema are defined in the producer | `grep -n 'REVIEWER_LOOP_HISTORY_SCHEMA=\|REVIEWER_LOOP_HISTORY_MARKER=' scripts/development-workflow/pr-review-loop.sh` | Lines 6720 and 6721, as top-level constants in `pr-review-loop.sh`. Nothing outside that script can reference them today |
| The payload extractor is there too | `sed -n '6722,6750p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_extract_latest_json` — an `awk` program that takes a comment body on stdin, finds the last marker, and prints the fenced JSON block that follows it |
| The comment is found by two literal strings | `sed -n '7129,7145p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_select_latest_summary_record` selects comments containing both `### Automated Reviewer Loop Summary` and ``*Posted automatically by `pr-review-loop.sh`.*``, sorts by `created_at`, and takes the last. It reads `gh api repos/<repo>/issues/<pr>/comments --paginate` output |
| The fetch is already written, with retries | `sed -n '7628,7648p' scripts/development-workflow/pr-review-loop.sh` | `gh api … --paginate \| reviewer_loop_history_select_latest_summary_record`, retried, then `jq -r '.body'`. The report's fetch is this shape |
| **The existing counter conflates no-history with zero** | `sed -n '7341,7352p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_entries_count` returns `0 0 available` for an empty body **and** for a body with no marker, and its own comment block says so: *"a body with no history marker at all is the normal 'no prior reviewer-loop run' state … it is not an error condition"*. Correct for cycle counting; forbidden here |
| It does distinguish the other two causes | Same range, plus `sed -n '7353,7370p'` | Marker present with no parseable block → `unavailable`; schema mismatch, non-array `entries`, or a persisted `history_status` that is not `available` → `unavailable`. **Two of the spec's three exclusion reasons already have code**; only `no_history` has to be split back out |
| The payload's shape | `sed -n '7057,7075p' scripts/development-workflow/pr-review-loop.sh` | `{schema, pr_number, updated_at, history_status, history_unavailable_reason, entries}`. The unavailable stub carries `entries: []` — which is why a status check is required and an entry count is not sufficient |
| The entry's fields today | `sed -n '6926,6950p' scripts/development-workflow/pr-review-loop.sh \| grep -cE '^ {6}[a-z_]+:'` | **Seventeen** keys, sixteen scalar or array and one nested object: `iteration`, `recorded_at`, `head_sha`, `run_id`, `result`, `reason`, `platforms`, `blocking_count`, `suggestion_count`, `unresolved_thread_count`, `late_threads_found`, `phase_after_clean` (nested), and the five `small_findings_*`. **Measures 1, 3 and 6 are computable from this alone**; measures 2, 4, 5 and 7 are not |
| `platforms` is a plain name list | `sed -n '6751,6756p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_platforms_json` splits a comma list and drops `none`. Measure 6 tests for `codex-github` in that array |
| `blocking_count` is one number for the round | `sed -n '6932p' scripts/development-workflow/pr-review-loop.sh` | `blocking_count: $blockingCount` — the round's aggregate across reviewers. This is measure 3, and it is the reason the spec has no per-reviewer measure |
| The producer is sourceable for tests | `sed -n '16,19p' scripts/development-workflow/pr-review-loop.sh` | `HARNESS_MODE=1` plus `BASH_SOURCE[0] != $0`. The new script uses the same guard so its functions are unit-testable |
| The shared library both scripts already load | `grep -n 'workflow-lib.sh' scripts/development-workflow/pr-review-loop.sh` | Line 10. `workflow-lib.sh` is 3328 lines and is the home the moved constants and extractor get |

**What this log does not establish.** It does not show what any of the seven
measures will read once #1648 and #1651 ship — their fields do not exist at this
revision, which is why the plan tests them against **fixtures** rather than
against the live schema, and why `not_recorded` is exercised by the schema that
exists today rather than by a contrived one.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1657 | 2026-08-31, repo SHA `77cdb1c5` | Epic #1647 items | `Verified` |
| The history comment's two identifying strings | `### Automated Reviewer Loop Summary` and ``*Posted automatically by `pr-review-loop.sh`.*`` | `pr-review-loop.sh:7135-7137` | 2026-08-31, repo SHA `77cdb1c5` | `pr-review-loop.sh` | `Verified` — the report reuses the selector rather than restating the strings |
| The existing counter treats no-marker as zero | `0 0 available` | `pr-review-loop.sh:7341-7352` and its own comment block | 2026-08-31, repo SHA `77cdb1c5` | that function and its callers | `Verified` — and it is the reason the report does not call it |
| The fields measures 2, 4, 5 and 7 read | Not present at this revision | #1648's and #1651's merged plans | 2026-08-31, repo SHA `77cdb1c5` | #1648, #1651, #1657 | `Verified` as **absent**, which is the case the report is built to handle |

**No `Conflict` row.** The fields four measures read do not exist yet, and that
is not a conflict: the spec's `not_recorded` state is the contract for exactly
this, and shipping before them is a property of the design rather than a risk to
be sequenced around. The implementer re-verifies all four rows at start.

### Not applicable

**Overall result for this check**: `Applicable`.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no deployment target. The external API is
GitHub's, read through `gh`, and the report performs no writes against it.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Move the history format's definition into `workflow-lib.sh`**:
      `REVIEWER_LOOP_HISTORY_SCHEMA`, `REVIEWER_LOOP_HISTORY_MARKER`,
      `reviewer_loop_history_extract_latest_json` and
      `reviewer_loop_history_select_latest_summary_record`.
      `pr-review-loop.sh` already sources the library at line 10, so the move is
      a deletion there and an addition in one place.

      **The four move together because they are one format.** A reader that has
      the marker but restates the selector's two identifying strings would find
      no comment on a pull request whose summary heading changed, and would
      report `no_history` for a pull request that has one — a wrong number, not
      an error.

      The move is behaviour-preserving for the producer, and that is asserted
      rather than assumed: `pr-review-loop.sh`'s existing suite runs unchanged.

- [ ] **Add `scripts/development-workflow/reviewer-effectiveness-report.sh`**,
      with the same source-only harness guard `pr-review-loop.sh` uses at lines
      16-19, so its classifier and measure functions are unit-testable without
      running a report.

      ```text
      reviewer-effectiveness-report.sh --pr <number> [--json]
      reviewer-effectiveness-report.sh [--window <n>] [--repo <owner/repo>] [--json]
      ```

      `--window` defaults to **20**, per AC-2a. **No environment variable and no
      configuration file sets it** — AC-2d — so the only way to change the
      window is to pass one. The `--help` block states the default, which is the
      spec's second stated source and is the same fact rather than a second one.

- [ ] **Classify each pull request into one of four states**, and do it in the
      spec's matrix order — comment, then parse, then status:

      ```text
      body="$(fetch_summary_body "$pr")"                     # may be empty
      if ! printf '%s\n' "$body" | grep -Fq "$MARKER"; then
        state=no_history
      elif ! json="$(printf '%s\n' "$body" | extract_latest_json)" \
           || [ -z "$json" ]; then
        state=unparseable_history
      elif ! printf '%s\n' "$json" | jq -e --arg s "$SCHEMA" '
              .schema == $s and (.entries | type) == "array"
              and ((.history_status // "available") == "available")' >/dev/null 2>&1; then
        state=history_unavailable
      else
        state=included
      fi
      ```

      **The marker test comes first and is what separates `no_history` from the
      other two.** The existing counter does not make this split — it returns
      the same answer for "no marker" as for "zero entries" — and the whole
      exclusion accounting depends on it.

      **The status test must be a status test, not an entry count.** The
      unavailable stub the loop writes carries `entries: []`, so a report that
      inferred availability from a non-empty entry list would classify a
      recorded `unavailable` as a pull request with zero rounds. That is row 3
      of the matrix collapsing into a clean number.

      A `gh` failure while fetching is **not** one of the three reasons. It is a
      failure to produce the report for that pull request, and the report exits
      non-zero rather than recording a fourth exclusion cause — AC-18 says the
      exit status reflects whether the report was produced, and a fetch that did
      not happen is not evidence about the pull request.

- [ ] **Compute each measure, and decide its availability from the fields
      present**:

      | # | Measure | Computed from | `not_recorded` when |
      | --- | --- | --- | --- |
      | 1 | Rounds | `entries \| length` | never — an included payload has an array |
      | 2 | External blocking rounds | rounds with at least one missed-finding record | no entry carries the records field |
      | 3 | Blocking findings | `[.entries[].blocking_count] \| add` | no entry carries `blocking_count` |
      | 4 | Confirmed miss records | records with state `clean_same_commit` | as measure 2 |
      | 5 | Possible miss records | records with state `clean_earlier_commit` | as measure 2 |
      | 6 | `codex-github` invocations | rounds whose `platforms` contains it | no entry carries `platforms` |
      | 7 | Final current-head evidence | the last entry's reviewed-head states | **the last entry** carries none — see the exemption below |

      **Availability is read with `has()`, never with `//`.** `// 0` and `// []`
      are the idiomatic defaults and both are silent failures here: they turn an
      absent field into a number, which is the one thing AC-13 forbids. A
      measure is `computed` when **at least one** entry carries its field and
      `not_recorded` when none does.

      **At least one, not all.** A pull request whose first three rounds predate
      #1651 and whose last two carry records has the records; reporting
      `not_recorded` because an early round lacked them would discard data that
      is present. The measure is over the rounds that have the field, and
      measure 1 is over all of them — so rounds and external blocking rounds can
      legitimately have different bases within one pull request.

      **Measure 7 is exempt from that rule, and the exemption follows from what
      it measures.** It reports whether the **final** verdict was made against
      the current head, so its scope is the last entry and nothing else: its
      availability is decided by whether **the last entry** carries the
      reviewed-head states, and an earlier entry carrying them is not evidence
      about the final round. A pull request whose earlier rounds have the states
      and whose last round does not is `not_recorded` for measure 7 — under the
      generic rule it would be `computed`, from a round that is not the one the
      measure is about.

      This is the only measure whose scope is a single entry, which is why the
      exemption is one line rather than a second general rule. Scenario 11b
      asserts both directions.

- [ ] **Aggregate per measure, each with its own included count.** A pull
      request contributes to a measure's aggregate only when that measure is
      `computed` for it, so the report carries seven denominators and not one.
      AC-14.

- [ ] **Report the strict checks separately**, per check, as pull requests fired
      over pull requests applied, with the two denominators the spec requires:

      - a **spec** check's denominator is the pull requests whose spec
        strict-check state was `applied` — #1650 records no applied set, because
        every check it defines is applied whenever its state is;
      - a **plan** check's denominator is the pull requests whose recorded
        applied set contains that check.

      **Incidence is per pull request here and only here.** A check reported on
      three rounds of one pull request contributes one. Everything else in the
      report is a total, and AC-15 says a pull request with four external
      blocking rounds contributes four.

      When neither strict item has shipped, no check has a denominator and the
      section reports nothing rather than an empty table of zeroes.

- [ ] **Render, and keep absence a word.** Text output by default, `--json` for
      a machine. In both, a `not_recorded` measure is that state and never `0`,
      an empty string, or a dash — AC-13, and the UX rule that an empty cell
      reads as zero to everyone. In JSON the measure is an object carrying its
      availability and, when `computed`, its value; it is never `null`.

- [ ] **Print in the spec's order**: per-pull-request rows, then aggregates,
      then the exclusion accounting. A window with zero included pull requests
      prints the accounting and **no** aggregate section — AC-19, since
      aggregates over nothing rendered as zeroes are the report's own version of
      the error it exists to prevent.

### Frontend / UI

Not applicable.

### Infrastructure / Configuration

- [ ] Document the script, its two modes, the seven measures, the three
      exclusion reasons and the `not_recorded` state in
      `scripts/development-workflow/README.md` and in the `--help` block.
- [ ] `changelog.d/1657.added.reviewer-effectiveness-report.md`.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. One case per row of the spec's five-row matrix: no marker; marker with no
   parseable block; a payload whose `history_status` is `unavailable`; a
   readable payload missing a measure's field; and a readable complete payload.
1b. **Rounds equals the number of recorded entries, exactly.** A payload with
   five entries reports 5; one with a single entry reports 1; and an included
   payload never reports `not_recorded` for this measure, since an included
   payload has an array by definition. AC-3. Asserted against a payload whose
   entries carry differing field sets, so the count is of entries and not of
   entries that happen to look complete.
1a. **The two modes agree.** The same pull request reported with `--pr` and
   inside a window produces **identical** per-pull-request values for all seven
   measures and identical availability states. AC-2. Asserted by comparing the
   two JSON outputs field for field, since a divergence would be invisible in
   the text rendering and would make a window's aggregate inconsistent with the
   rows a reader can check individually.
2. The three exclusion reasons are distinguishable in the output, and each
   excluded pull request carries exactly one. AC-11.
3. **A recorded `unavailable` payload carrying `entries: []` is excluded, not
   reported as zero rounds.** This is the stub the loop actually writes, and a
   report that tested the entry list instead of the status would pass every
   other scenario and fail this one.
4. Requested, included and excluded counts reconcile. AC-10.
5. An excluded pull request contributes to no numerator and no denominator.
   AC-12.
6. **A history written to today's schema** — no missed-finding records, no
   reviewed-head states — reports measures 1, 3 and 6 as numbers and measures
   2, 4, 5 and 7 as `not_recorded`, and is **not** listed as excluded. AC-13,
   AC-13a, AC-13b. This is the fixture that proves the report ships before its
   producers.
7. `not_recorded` is never rendered as `0`, empty or a dash, in text and in
   JSON. In JSON the measure is never `null`.
8. A pull request whose early rounds lack a field and whose later rounds carry
   it reports that measure as `computed` over the rounds that have it, while
   measure 1 counts all rounds.
9. Two measures in one report have different included counts, and both are
   shown. AC-14.
10. Measures 4 and 5 are reported separately and no output sums them. AC-5,
    AC-5a. A record describing three findings contributes one. AC-5b.
10a. **External blocking rounds equals the number of missed-finding records,
    across every local-evidence state.** A fixture whose records carry
    `clean_same_commit`, `clean_earlier_commit` and a non-clean state in turn
    contributes **one** to measure 2 for each — the measure counts qualifying
    external rounds, and what the local reviewer's verdict had been decides only
    which of measures 4 and 5 the record also feeds, or neither. AC-4.
10b. A round with **no** record contributes nothing to measure 2, including a
    round whose reviewers reported advisory findings only. #1651 writes records
    for blocking findings alone, and the measure inherits that boundary rather
    than restating it.
11. Measure 3 is the sum of the rounds' aggregate blocking counts and is
    **not** attributed to any reviewer. AC-4a.
11a. **Measure 6 counts exactly the rounds that dispatched `codex-github`.** A
    fixture with five rounds, three of which list it in `platforms`, reads 3 —
    asserted against both a round listing several reviewers including it and a
    round listing others only, so neither a substring match nor a
    presence-anywhere test passes. AC-6.
11b. **Measure 7 reads the last round and no other.** A fixture whose earlier
    rounds carry current-head evidence and whose **last** round does not
    reports the last round's state, not an earlier one's; and a fixture where
    only the last round carries it reports that state rather than
    `not_recorded`. AC-7. Its `computed` value is a state, never a number.
12. **No measure of what the local reviewer found appears anywhere** in either
    output format. AC-4b, asserted by absence over the rendered output and the
    JSON keys, since a measure nobody computes is invisible to a value
    assertion.
13. Strict-check incidence: a check reported on three rounds of one pull request
    contributes **one**; a pull request with four external blocking rounds
    contributes **four** to that measure. AC-15, AC-15a.
14. The spec-check denominator is the pull requests whose spec state was
    `applied`; the plan-check denominator is the pull requests whose applied set
    contains the check; two checks in one report may have different denominators.
    AC-16, AC-16a, AC-16b.
15. The window: absent uses 20 and says so; a positive number takes that many; a
    window larger than the population reports over the population and
    reconciles against it; `0`, a negative number and a non-integer are each
    refused with the value named. AC-2a, AC-2b, AC-2c.
16. **No configuration changes the default window.** Asserted by grep over the
    implementation and the `--help` block for a second name, since a setting
    nobody sets is invisible to behavioural tests. AC-2d.
17. The report writes nothing: no comment posted, no label applied, no file left
    behind. Asserted by running against a recording `gh` stub and requiring
    every invocation to be a read. AC-17.
18. Exit status is zero for a window with exclusions, for `not_recorded`
    measures, and for any values; non-zero only when the report could not be
    produced. AC-18.
19. A window with zero included pull requests prints the accounting and no
    aggregates. AC-19.
20. The report presents no composite score, threshold or recommendation.
    AC-20, asserted by absence.
21. **`pr-review-loop.sh`'s suite passes unchanged** after the four definitions
    move to `workflow-lib.sh`.
22. **The report and the loop agree about which comment is the history.** Given
    one pull request body, the moved selector returns the same record to both
    callers — asserted by calling it from each and comparing, which is the
    property the move exists to guarantee.

**Files**:

- `scripts/development-workflow/tests/test-reviewer-effectiveness-report.sh` —
  new, scenarios 1 through 20 and 22, the lettered ones included. Fixtures are comment bodies fed to the
  real functions; `gh` is a recording stub so reads can be asserted and writes
  detected.
- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenario 21,
  unchanged assertions.

**Smoke test runbook**:
`docs/testing/workflow/1657-reviewer-effectiveness-report.smoke-test.md`

**Regression suite**: both harnesses named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Comment bodies | Seven: no marker; marker with no fenced block; a payload with `history_status: unavailable` and `entries: []`; a payload on **today's** schema; one with the fields #1648 and #1651 add; one whose early rounds lack those fields and whose later rounds carry them; and one with strict-check objects from both #1650 and #1655 | `scripts/development-workflow/tests/fixtures/reviewer-effectiveness/` |
| `gh` stub | A recording script that serves the fixture bodies for `issues/<n>/comments` and `pr list`, records every invocation, and **fails the test if any invocation is a write** | inline in the new suite |
| Window inputs | Absent, `1`, a number larger than the population, `0`, `-3`, `abc` | inline |

---

## Documentation Updates

- `scripts/development-workflow/README.md` — the script, its modes and its
  states.
- The `--help` block, including the default window and that nothing else sets
  it.
- `changelog.d/1657.added.reviewer-effectiveness-report.md` — `added`: a report
  that did not exist; nothing changes for anyone who does not run it.

---

## Cross-Cutting Checklist Classification

**Classification**: `Not applicable`. Protocol 02's three signals are adding or
renaming a checklist category in `REVIEW.md` or a planning document; imposing an
acceptance criterion on every plan; and adding a conditional guidance block to a
planning or implementation protocol. This item adds a **read-only script** and
moves four definitions between two files it already couples. It changes no
`REVIEW.md` section and requires nothing of any future plan.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The report reuses `reviewer_loop_history_entries_count` | **High** — it exists, it parses the same payload, and reusing it looks like good practice | **High** — it returns `0 0 available` for a pull request with no history, so every pull request the loop never ran on enters every denominator as clean, and the rate is wrong in the flattering direction | The report classifies for itself, marker test first. Scenario 1; proof **P1** |
| A recorded `unavailable` payload is read as zero rounds | **High** — the stub carries `entries: []`, so an entry-count test passes it | **High** — the loop's own statement that it could not record is reported as a clean pull request | The status is tested, not the entry count. Scenario 3; proof **P2** |
| `// 0` or `// []` turns an absent field into a number | **High** — it is the idiomatic jq default | **High** — `not_recorded` becomes `0`, and the distinction the whole spec is built on disappears at the last step | Availability is read with `has()`. Scenarios 6 and 7; proof **P3** |
| Incidence is summed over rounds | Med | Med — a strict check looks more frequent the longer its pull request stayed open, which inverts the ranking the reader is about to act on | Per pull request for strict checks only; totals stay totals. Scenario 13; proof **P4** |
| One denominator is used for both checklists | Med — the two records look alike | Med — spec checks divided by a set #1650 does not record, or plan checks divided by the window | Two derivations, named. Scenario 14; proof **P5** |
| The selector's identifying strings are restated in the new script | Med | Med — a heading change makes the report see no history where the loop sees one, reported as `no_history` rather than as an error | The selector moves to `workflow-lib.sh` and both callers use it. Scenarios 21 and 22 |
| The report writes something | Low — nothing in it intends to | **High** — a reporting tool that mutates a pull request is a different tool, and the spec's first business rule is that it does not | A recording `gh` stub fails the suite on any write. Scenario 17; proof **P6** |
| A `gh` failure is recorded as an exclusion reason | Med — three reasons exist and a fourth is tempting | Med — a network failure enters the data as a fact about the pull request, and the accounting says something false about the repository | A fetch failure is a failure to produce the report, and exits non-zero. Scenario 18 |
| Aggregates over an empty window render as zeroes | Med | Med — a window where nothing was readable reads as a window where nothing happened | No aggregate section when the included count is zero. Scenario 19 |

---

## Code Samples

The availability test, which is the line every measure depends on:

```text
# `computed` when at least one entry carries the field; `not_recorded` when none
# does. has() and never //, because // turns absence into a number and the
# distinction between "none happened" and "not recorded" is this report's whole
# subject.
measure_available() {           # <payload> <field>
  printf '%s\n' "$1" | jq -e --arg f "$2" '
    [ .entries[]? | select(has($f)) ] | length > 0
  ' >/dev/null 2>&1
}

# Measure 7 only. Its scope is the final round, so an earlier entry carrying the
# field is not evidence about the one the measure describes.
measure7_available() {          # <payload> <field>
  printf '%s\n' "$1" | jq -e --arg f "$2" '
    (.entries | last) as $e | ($e != null) and ($e | has($f))
  ' >/dev/null 2>&1
}
```

**`select(has($f))` rather than `select(.[$f] != null)`.** A field explicitly
present and `null` is a producer that recorded nothing, and a field absent is a
producer that did not run; `has()` separates them and `!= null` does not. The
distinction matters here more than anywhere: the second is `not_recorded` and
the first is a defect in whoever wrote the entry.

And the exclusion classifier's first branch, which is the one the existing
counter does not have:

```text
if ! printf '%s\n' "$body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
  state=no_history          # NOT "zero rounds, available"
fi
```

`grep -Fq` is a test in a conditional, so its exit 1 is consumed by the `if`
rather than reaching `set -e`. That is the same trap #1650 records on `grep -c`,
avoided here by position rather than by a status variable — a `grep` whose
status is the condition needs no rescue, and one whose status is a value does.

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. **Six** proofs, all in one
group: every one plants a defect that produces a **wrong number rather than an
error**, which is this item's entire risk surface.

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Call `reviewer_loop_history_entries_count` and treat its `available` as inclusion | a scratch copy of the classifier | scenario 1 fails: a pull request with no history comment is included with zero rounds, so every pull request the loop never ran on enters every denominator as clean and the miss rate falls; restoring the marker test passes |
| P2 | Test `entries \| length > 0` instead of `history_status` | same scratch copy | scenario 3 fails: the loop's own `unavailable` stub, which carries `entries: []`, is reported as a pull request with zero rounds — the loop saying *I could not record this* read as *nothing happened*; restoring the status test passes |
| P3 | Replace the `has()` availability test with `// 0` and `// []` | a scratch copy of the measure step | scenarios 6 and 7 fail: a history on today's schema reports `0` for four measures instead of `not_recorded`, so pull requests that predate the epic's telemetry look like pull requests where the telemetry found nothing; restoring `has()` passes |
| P4 | Sum strict-check occurrences over rounds instead of per pull request | a scratch copy of the strict-check step | scenario 13 fails: a check reported on three rounds of one pull request contributes three, so the checks that fire on long-lived pull requests rank highest and the blocking decision is taken on the wrong ordering; restoring the per-pull-request cap passes |
| P5 | Use the window's pull-request count as the denominator for every check | same scratch copy | scenario 14 fails: plan checks that were applied to a third of the window are divided by all of it, understating exactly the three source-dependent checks #1655 introduced coverage reporting for; restoring the two derivations passes |
| P6 | Post the report as a pull-request comment when a `--publish`-shaped path is added | a scratch copy of the render step | scenario 17 fails: the recording stub sees a write, and a read-only report becomes a tool that mutates the pull requests it measures; removing the write passes |

P1 and P3 are the pair to read together. Neither produces an error, both produce
a plausible report, and both move every rate in the flattering direction — the
direction nobody questions.

---

## Implementation Order

0. **No hard stop.** Confirm the four assumption rows at `77cdb1c5`, in
   particular that the fields measures 2, 4, 5 and 7 read are still absent — if
   #1648 or #1651 has landed meanwhile, scenario 6's fixture stays as written
   (it is a fixture, not a live read) and the live smoke step gains those
   measures.
1. Move the marker, the schema, the extractor and the selector to
   `workflow-lib.sh` and delete them from `pr-review-loop.sh`. **Verify**:
   scenarios 21 and 22.
2. Add the script with its harness guard, argument parsing and window semantics.
   **Verify**: scenarios 15 and 16.
3. Add the classifier. **Verify**: scenarios 1, 1a, 1b, 2, 3, 4, 5 and 18.
4. Add the measures and their availability test. **Verify**: scenarios 6, 7, 8,
   10, 10a, 10b, 11 and 12.
5. Add the aggregation and the strict-check section. **Verify**: scenarios 9,
   11a, 11b, 13 and 14.
6. Add the rendering, text and JSON. **Verify**: scenarios 7, 17, 19 and 20.
7. Update the README, the `--help` block and add the changelog fragment.
   **Verify**: runbook Step 8.
8. Produce the **six** planted-violation proofs and record them in the pull
   request with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation pull request. It removes the script, its suite, its
fixtures, the README section and the changelog fragment.

**The `workflow-lib.sh` move is independently revertable and need not be.**
`pr-review-loop.sh` behaves identically whether the four definitions live in it
or in the library it already sources, and step 1 asserts that. Leaving them in
the library costs nothing and reverting them is a second change; mixing the two
into one revert is the only way this rollback could touch the reviewer loop,
which this item otherwise does not modify at all.
