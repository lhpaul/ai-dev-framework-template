# Smoke Test: Reviewer Effectiveness Report (#1657)

**Item**: [#1657](https://github.com/lhpaul/ai-dev-framework-template/issues/1657)
**Spec**: [1_1657-reviewer-effectiveness-report_specs.md](../../specs/developments/20260831120000_1657-reviewer-effectiveness-report/1_1657-reviewer-effectiveness-report_specs.md)
**Plan**: [2_1657-reviewer-effectiveness-report_implementation-plan.md](../../specs/developments/20260831120000_1657-reviewer-effectiveness-report/2_1657-reviewer-effectiveness-report_implementation-plan.md)

Steps 1 through 6 run the **real** script against fixture comment bodies served
by a recording `gh` stub. The stub is as much the test as the fixtures: it fails
the run on any invocation that is not a read.

Step 7 runs against this repository's own pull requests, which is the only step
that shows what the report says about real data.

---

## Step 1: The three exclusion reasons stay apart

**Maps to**: AC-11, AC-12, and the spec's matrix rows 1-3.

1. Run a window over three fixture pull requests: one with **no history
   marker**; one with the marker and **no parseable JSON block**; one whose
   payload records `history_status: unavailable` and carries `entries: []`.
2. Read the exclusion accounting.

**Expected result**: all three excluded, with `no_history`,
`unparseable_history` and `history_unavailable` respectively. No aggregate
counts any of them, in any numerator or denominator.

**The third fixture is the one that catches the likely implementation.** It is
the stub the loop actually writes, and its empty entry list makes an
entry-count test pass it as a pull request with zero rounds — the loop's own
statement that it *could not record* read as *nothing happened*. Proof P2.

**The first is the one that catches the tempting reuse.**
`reviewer_loop_history_entries_count` already parses this payload and returns
`0 0 available` for a body with no marker, by design and correctly for its own
caller. Reused here it puts every pull request the loop never ran on into every
denominator as clean. Proof P1.

## Step 2: A history on today's schema reports numbers and absences

**Maps to**: AC-13, AC-13a, AC-13b.

1. Run against a fixture written to the schema that exists **before** #1648 and
   #1651 ship: entries with `platforms`, `blocking_count` and no missed-finding
   records or reviewed-head states.
2. Read the seven measures.

**Expected result**: rounds, blocking findings and `codex-github` invocations
are numbers. External blocking rounds, both miss-record measures and final
current-head evidence are **Not recorded**. The pull request is **included**,
and appears in no exclusion list.

This is the step that demonstrates the report ships before its data producers.
Reporting `0` for the four absent measures would say *this never happened* about
telemetry that did not exist yet — and would put those pull requests into
#1657's own denominators as evidence of a clean record. Proof P3.

Check the rendering in both formats: `Not recorded` is a word in text and a
state in JSON, never `0`, never an empty cell, never `null`.

## Step 3: Absence and presence can coexist in one pull request

**Maps to**: AC-13b, AC-14.

1. Run against a fixture whose first three rounds predate the telemetry and
   whose last two carry it.
2. Compare rounds against external blocking rounds.

**Expected result**: rounds counts **five**; the telemetry measures are
`computed` over the two rounds that carry them. Both appear, with different
bases, and neither is `not_recorded`.

A measure is available when **at least one** round carries its field. Requiring
all of them would discard data that is present, on a pull request that spans the
moment a producer shipped — which is every pull request open that week.

## Step 4: Totals are totals; incidence is per pull request

**Maps to**: AC-15, AC-15a, AC-16, AC-16a, AC-16b.

1. Run against a fixture pull request with **four** external blocking rounds and
   a strict check reported on **three** rounds.
2. Read that measure and that check's incidence.
3. Run a window mixing pull requests whose spec strict-check state was `applied`
   with pull requests whose plan applied set contains only some checks.

**Expected result**: the external blocking rounds measure reads **4**. The
check's incidence numerator reads **1**. In step 3, a spec check's denominator
is the pull requests whose spec state was `applied`, a plan check's is the pull
requests whose applied set contains it, and two checks show different
denominators.

**These are two different arithmetics in one report and the report must not
apply one rule to both.** Summing a check over rounds makes it look more
frequent the longer its pull request stayed open, which inverts the ranking a
reader is about to act on; capping a total at one per pull request contradicts
the rounds measure. Proofs P4 and P5.

## Step 5: There is no measure of what the local reviewer found

**Maps to**: AC-4a, AC-4b.

1. Run against the richest fixture and search both output formats for any
   measure naming the local reviewer.
2. Read the blocking findings measure.

**Expected result**: **nothing** names the local reviewer. Blocking findings is
the round's aggregate across all reviewers, unattributed.

The history carries one aggregate count and a list of which reviewers ran; it
attributes no finding to any of them. A report that split the aggregate would be
inventing an observation, which is the one thing this report must never do. The
brief's question is still answered: the miss rate is the two miss-record
measures over external blocking rounds.

## Step 6: The window's edges

**Maps to**: AC-2a, AC-2b, AC-2c, AC-2d, AC-10, AC-19.

1. Run with no window. 2. With `1`. 3. With a number larger than the number of
   pull requests that exist. 4. With `0`, `-3` and `abc` in turn.
5. Run a window in which **every** pull request is excluded.
6. Grep the implementation and the `--help` block for a second name that sets
   the window.

**Expected result**: no window uses **20** and says so. `1` reports one. A
window larger than the population reports over the population, and requested
reconciles against what was **found** — a window is a maximum, not a demand.
`0`, `-3` and `abc` are each **refused with the value named**, not defaulted.
Step 5 prints the accounting and **no aggregate section**. Step 6 finds no
second name.

Defaulting a malformed window would produce a report whose window the reader
believes they chose, with every aggregate over a denominator they did not ask
for. And aggregates of zero over an empty window are this report's own version
of the error it exists to prevent.

## Step 7: Against this repository

**Maps to**: AC-1, AC-8, AC-9, AC-17, AC-18.

1. Run `--pr` against a merged pull request from epic #1647 — one with a real
   reviewer-loop history.
2. Run the default window.
3. Check the pull requests afterwards for any new comment, label or state
   change. Check the working tree for any new file.
4. Check the exit status of a run whose window contained exclusions.

**Expected result**: the per-pull-request rows come first, then the aggregates,
then the accounting. **Nothing was written** — no comment, no label, no file.
The exit status is zero despite the exclusions: it reflects whether the report
was produced, never what it found. Proof P6.

Read the output as a maintainer would. If a rate is quotable without its
denominator beside it, the layout has failed the UX rule even where every number
is right.

## Step 8: Documentation says what the code does

**Maps to**: the documentation updates.

Confirm the `--help` block and `scripts/development-workflow/README.md` describe
the same two modes, seven measures, three exclusion reasons, `not_recorded`
state and default window as the implementation emits — and that the changelog
fragment exists.
