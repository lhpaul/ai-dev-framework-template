# Reviewer Effectiveness Report — Spec

**Depends on**: 1648-reviewer-loop-current-head-evidence, 1651-missed-findings-telemetry

---

## Overview

This epic has spent nine items making the reviewer loop record what it did: which reviewer ran, on which commit, what it found, what an external reviewer found afterwards that the local one had already cleared, and how often each strict check fired. Every one of those records lives in a pull request's reviewer-loop history, one comment per pull request, and nobody has ever read a hundred of them.

This feature reads them. It reports, for one pull request or for a window of recent ones, how many rounds the loop took, what the local reviewer found, what external reviewers found, how many of those the local reviewer had already called clean, how often the expensive `codex-github` reviewer was invoked, and whether the final verdict was made against the current head.

**The whole feature is a reader.** It runs no reviewer, writes to no pull request, changes no gate and stores nothing. Its only output is a report, and its only input is history that already exists.

The hard part is not arithmetic. It is that this report will be used to decide whether the strict checks earn the right to block, whether the local reviewer is worth its cost, and whether the epic's premise held — and a number that quietly averages over pull requests it could not read would answer all three wrongly, in the flattering direction. So the accounting rules below are the substance of this specification, and the counts are what falls out of them.

---

## Issue-Objective Traceability

Every objective stated in issue #1657 maps to acceptance criteria and use cases here, or to an explicit entry under **Out of Scope (MVP)** with a deferral note. No objective is dropped.

| # | Objective (from #1657) | Where it is satisfied |
| --- | --- | --- |
| 1 | *Problem* — evidence on whether the local reviewer reduces external cycles, not just that it ran | Use Cases 1 and 3; AC-1, AC-4, AC-5 |
| 2 | *Outcome* — a report summarising effectiveness per pull request and across recent ones | Use Cases 1 and 2; AC-1, AC-2 |
| 3 | *Scope* — total cycles | Measure 1; AC-3 |
| 4 | *Scope* — local findings | **Deferred** — Out of Scope 8, with the reason: the history attributes no finding and no blocking result to the local reviewer, and no item in this epic adds one. Measure 3 reports the aggregate that does exist; AC-4b forbids inventing the split |
| 5 | *Scope* — external findings | Measure 2, as **rounds** with a stated floor, plus Measure 3 for the aggregate count; AC-4, AC-4a |
| 6 | *Scope* — missed-by-local findings | Measures 4 and 5; AC-5, AC-5a, AC-5b |
| 7 | *Scope* — `codex-github` invocations | Measure 6; AC-6 |
| 8 | *Scope* — final current-head evidence | Measure 7; AC-7 |
| 9 | *Scope* — support a single pull request and a recent-PR window | Use Cases 1 and 2; AC-2, AC-9 |
| 10 | *Scope* — use existing reviewer-loop history comments where possible | Business Rules, the single-source rule; AC-8, AC-16 |

---

## Use Cases

### Use Case 1: A maintainer reads one pull request's numbers

**Actor**: A maintainer, or an agent advancing an item.
**Preconditions**: The pull request has a reviewer-loop history comment.

**Steps**:

1. They ask for the report for that pull request.
2. The report reads the pull request's reviewer-loop history.
3. It presents the seven measures, each with the rounds it was computed from.

**Postconditions**: Nothing changed. The reader has the numbers and, for each one, whether it is complete.

**Information shown**:

- The seven measures below, per pull request.
- For each measure, whether the history contained the fields it needs — and when it did not, that it did not.

**Considerations**:

- **A missing field is not a zero.** The fields these measures read are added by other items in this epic, and a pull request reviewed before one of them shipped has a history without that field. Reporting `0` for it would say *this never happened*; the report says *this was not recorded*, which is a different fact with a different remedy.
- The report is read-only in the strongest sense: it does not write a comment, apply a label, or touch the pull request in any way.

---

### Use Case 2: A maintainer reads a window of recent pull requests

**Actor**: A maintainer.

**Steps**:

1. They ask for the report over the most recent *n* pull requests.
2. The report reads each one's reviewer-loop history.
3. It presents each pull request's row, then the aggregate, then the accounting for what the aggregate is over.

**What *n* may be**, since a window size is an input like any other and its edges decide behavior:

| *n* | Behavior |
| --- | --- |
| Absent | **Twenty** — the default — and the report states the size it used |
| A positive whole number | That many of the most recent pull requests, or all of them when fewer exist |
| `0`, negative, or not a whole number | The report refuses, names the value it was given, and produces no report |

**Fewer pull requests than requested is not a refusal.** A repository with nine pull requests and a request for forty produces a report over nine, with requested reconciling against what was found rather than against what was asked — a window is a maximum, not a demand.

**A malformed *n* is refused rather than defaulted.** Silently substituting the default would produce a report whose window the reader believes they chose, and every aggregate in it would be over a denominator they did not ask for.

**Twenty has one source and no second one.** The value is stated here and in the report's own help output, and the **only** way to use a different window is to pass one. No configuration file, environment variable or flag sets it, because a window size that two readers of the same command could disagree about is a denominator that two readers of the same report could disagree about.

**Postconditions**: Nothing changed.

**Information shown**:

- One row per pull request.
- The aggregate of each measure.
- **Three counts that must reconcile**: pull requests requested, pull requests included in the aggregate, and pull requests excluded — the last broken down by reason.

**Considerations**:

- **Every aggregate names its denominator, and the denominator is never the requested count unless they are equal.** A window of forty pull requests where six had no readable history is a report over thirty-four, and saying so is the difference between a measurement and a number.
- The excluded ones are listed, not just counted. A reader who sees six exclusions all from the same week learns something the count alone hides.

---

### Use Case 3: A maintainer decides whether a strict check earns the right to block

**Actor**: A maintainer, reading accumulated strict-check data.
**Preconditions**: #1650's and #1655's checks have been running long enough to have fired.

**Steps**:

1. They read, per check, on how many pull requests it fired and on how many it was applied.
2. They decide, per check, whether to make it blocking.

**Postconditions**: A decision informed by incidence, taken one check at a time.

**Considerations**:

- **Incidence is per pull request, never per round.** A round repeats an unresolved finding by design, so summing rounds would make a check look more frequent the longer its pull request stayed open. A check fired on a pull request when **any** of its rounds reported it.
- **Coverage is the denominator and it varies by check.** #1655's three source-dependent checks are applied to fewer pull requests than its four others, so a single denominator would understate all three. The report divides each check by the pull requests it was actually applied to.
- The report presents incidence. It does **not** recommend a threshold, and there is no configured one — the decision is the reader's, per check, and the epic has no validated basis for automating it.

---

### Use Case 4: A pull request's history cannot be read

**Actor**: The report.
**Preconditions**: A pull request in the requested set has no reviewer-loop history comment, or has one that cannot be parsed, or has one whose recorded status is itself `unavailable`.

**Steps**:

1. The report attempts to read the history.
2. It excludes that pull request from every aggregate.
3. It lists it among the exclusions with the reason.

**Postconditions**: The aggregates are over the pull requests that had data, and say so. The report's exit status is unaffected — an unreadable history is a fact about the data, not a failure of the report.

**Considerations**:

- **The three causes are distinct and are not merged**: no history comment at all, a comment whose payload cannot be parsed, and a payload the loop itself recorded as unavailable. The first is a pull request the loop never ran on; the second is corruption; the third is the loop telling you it already knew. They have different remedies.
- Excluding is not the same as scoring zero, and this is the case that would be most tempting to get wrong. A pull request with no history contributes nothing to any numerator **and** nothing to any denominator.

---

### Use Case 5: A measure's field is absent from an otherwise readable history

**Actor**: The report.
**Preconditions**: The history is readable, and a round in it lacks a field one of the measures reads — because the item that writes that field had not shipped when the round ran.

**Steps**:

1. The report computes the measures it can.
2. For the measure whose field is missing, it reports **not recorded** rather than a number.
3. It excludes that pull request from **that measure's** aggregate only, and from no other.

**Postconditions**: Some measures over the full window and others over a subset, each saying which.

**Considerations**:

- **Exclusion is per measure, not per pull request, and a pull request can be excluded from several measures at once.** One that predates #1651 loses measures 2, 4 and 5 together, since all three read its records; it keeps rounds, blocking findings, `codex-github` invocations and the final head evidence. Dropping the pull request entirely would discard four sound measures to avoid three absent ones.
- The count of measures a pull request loses is not fixed and is not the point. What is fixed is that each measure decides for itself, and that a measure whose fields are absent says so rather than reporting a number.
- This makes the denominators differ *between* measures within one report, which is correct and must be visible. Each measure carries its own included count.

---

## Business Rules

- The report is **read-only**. It runs no reviewer, writes no comment, applies no label, changes no tracker state, and stores nothing between runs.
- **The reviewer-loop history comment is the only source.** The report does not re-run a reviewer, re-read a diff, or reconstruct a number the history does not contain. Where a measure cannot be computed from history, it is reported as not recorded rather than derived from somewhere else.
- **A field's absence is reported as absence, never as zero.** `0` means the history recorded the thing and it was none; not recorded means the history did not record it.
- **Every aggregate carries its own denominator**, and the denominator is the count of pull requests that contributed to *that measure*, not the count requested.
- **The requested, included and excluded counts reconcile** for the window as a whole: requested equals included plus excluded, and every exclusion carries one of the enumerated reasons.
- **The seven measures are totals and states, not incidence.** Measures 1, 2 and 6 total rounds; measure 3 totals findings; measures 4 and 5 total records; measure 7 is a state. A pull request with four external blocking rounds contributes four to measure 2, and any rule that capped it at one would contradict measure 1's own definition.
- **Incidence applies to the strict checks alone**, where it means: per check, a pull request contributes at most **one** to the numerator however many of its rounds reported that check. Rounds repeat an unresolved finding by design, so summing them would make a check look more frequent the longer its pull request stayed open. This rule governs the strict-check reporting and nothing else.
- **Confirmed and possible misses are never summed.** #1651 separates them because a clean verdict on an ancestor commit is weaker evidence, and a report that adds them would undo that distinction in the one place it matters.
- **Strict-check incidence is divided by the pull requests each check was applied to**, never by the window's pull-request count. A check applied to twelve pull requests and fired on three is three in twelve, whatever the window's size.
- **The denominator is derived differently for the two checklists, because they record differently.** #1650 records a state, a count and the identifiers that **fired**; it records no applied set, because every check it defines is applied whenever its state is `applied`. So a spec check's denominator is the pull requests whose spec state was `applied`. #1655 records an applied set explicitly, because its coverage varies; so a plan check's denominator is the pull requests whose recorded applied set contains that check. The report must not assume one shape for both, and must not read an applied set from #1650's records — there is none to read.
- Reading the report changes no decision by itself. It presents no threshold, no verdict, no recommendation and no single composite score.
- The report's **exit status reflects whether the report was produced**, not what it found. Unreadable histories, missing fields and alarming numbers all exit successfully; only an inability to produce the report at all does not.

---

## UX Rules

The reader is a maintainer at a terminal or an agent parsing output.

- Every measure is shown with its denominator adjacent to it, not in a footnote. A number a reader has to scroll to qualify will be quoted without its qualification.
- **Not recorded** is rendered as a word, never as an empty cell, a dash or a zero. An empty cell reads as zero to everyone.
- The per-pull-request rows come before the aggregate, and the exclusion accounting comes after it, so a reader who stops early has seen the data and a reader who continues sees what it was over.
- A window with zero included pull requests renders the accounting and no aggregates. Aggregates over nothing are not shown as zeroes.

---

## Statuses / Enum Values

### The seven measures

| # | Measure | Unit | What it counts | Source in the history |
| --- | --- | --- | --- | --- |
| 1 | Rounds | rounds | Loop iterations recorded for the pull request | one per history entry |
| 2 | External blocking rounds | rounds | Rounds in which an external reviewer reported blocking findings and the commit it reviewed could be established | #1651's missed-finding records — one per qualifying external round, whatever the local verdict was |
| 3 | Blocking findings | findings | Blocking findings recorded for the round, across all reviewers together | the round's aggregate blocking count |
| 4 | Confirmed miss records | records | Records in which the local reviewer had cleared the **exact** commit the external reviewer reviewed | #1651's records, state `clean_same_commit` |
| 5 | Possible miss records | records | Records in which the local reviewer's clean verdict covered an **ancestor** of that commit | #1651's records, state `clean_earlier_commit` |
| 6 | `codex-github` invocations | rounds | Rounds in which the `codex-github` reviewer was dispatched | the per-round platform list |
| 7 | Final current-head evidence | state | Whether the last recorded round's verdict was made against the pull request's current head | #1648's per-platform reviewed-head states on the last entry |

Measures 4 and 5 are reported as a pair and never added together.

**There is no measure for what the local reviewer found, and its absence is the honest answer rather than an oversight.** The round entry records **one aggregate blocking count across all reviewers** and a list of which reviewers ran; it does not attribute a finding, or a blocking result, to the reviewer that produced it. No item in this epic adds one. So *how many* findings the local reviewer raised is not recoverable, and neither is *in how many rounds it raised any* — the second looked derivable and is not, because the only per-reviewer outcome the history gains is #1651's local **evidence state**, which is written on qualifying **external** rounds and says nothing about a round the local reviewer was alone in.

Reporting it anyway would mean inventing an observation, which is the one thing this report must never do. Objective 4 is therefore deferred with its reason — **Out of Scope 8** — and the question the brief actually asks is still answerable without it: the local reviewer's miss rate is measures 4 and 5 over measure 2.

**Measures 4 and 5 count records, not findings.** #1651 writes one record per qualifying external round, and a single record can describe several blocking findings. Summing the findings inside them would produce a third unit nobody asked for and would weight one noisy round above three quiet ones. The pair is a count of *occasions*, and the unit column says so.

**Measure 2 is bounded below and says so.** #1651 deliberately writes no record for an external round whose reviewed commit cannot be established, so a pull request with such rounds has more external blocking rounds than this measure reports. That is a floor, not an estimate, and the report does not correct for it — correcting would mean inferring the commit #1651 refused to infer.

### Per-measure availability

| Value | Display label | Meaning |
| --- | --- | --- |
| `computed` | the measure's own value — a count for the six counting measures, a state for measure 7 | The history carried the fields this measure reads |
| `not_recorded` | Not recorded | The history is readable and does not carry them |

**`computed` is not a synonym for "a number".** Measure 7 is a state, and rendering its `computed` value as a number would require inventing one. The display is whatever that measure's unit says it is.

### Pull-request exclusion reasons

| Code value | Display label | Meaning |
| --- | --- | --- |
| `no_history` | No history comment | The pull request has no reviewer-loop history comment |
| `unparseable_history` | History unparseable | The comment exists and its payload cannot be read |
| `history_unavailable` | History unavailable | The payload is readable and the loop recorded its own status as unavailable |

The list is closed. A pull request that is readable is included, and one that is not carries exactly one of these three.

---

## Decision Matrix

Per pull request, from the report starting to that pull request's contribution existing or not. Rows are evaluated in order and the first match decides.

The order is: is there a history comment, can its payload be parsed, does the payload claim to be available, and does it carry the fields a given measure reads. Each question is unanswerable until the previous one is answered — a payload that cannot be parsed has no status to read, and a payload with no status has no fields to inspect.

| # | History comment | Payload parses | Payload status | Measure's fields present | Included in aggregates | Exclusion reason | Measure value |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **No** | — | — | — | No | `no_history` | — |
| 2 | Yes | **No** | — | — | No | `unparseable_history` | — |
| 3 | Yes | Yes | `unavailable` | — | No | `history_unavailable` | — |
| 4 | Yes | Yes | available | **No** | In every **other** measure | none | `not_recorded` |
| 5 | Yes | Yes | available | Yes | Yes | none | the measure's own value |

**Rows 1 through 3 exclude the whole pull request; row 4 excludes one measure.** That is the distinction Use Case 5 exists for, and collapsing it in either direction is a real error: excluding the pull request entirely discards its sound measures, and including it with `0` for the missing one puts a fabricated observation into an aggregate.

**Row 4 is evaluated once per measure, not once per pull request.** A pull request can be row 4 for confirmed misses and row 5 for everything else. Its "included" cell says *in every other measure* rather than yes or no because the answer is per measure by construction.

**No row produces a zero for an absent field.** `0` appears only in row 5, and only for a measure whose unit is a count — where the history recorded the thing and the count was none. Measure 7's row-5 value is a state; a `0` there would be an invented number rather than an observation.

### What each outcome requires, on every surface

| Outcome | Per-PR row | Aggregate | Exclusion accounting |
| --- | --- | --- | --- |
| Rows 1-3 | listed with its reason, no measures | contributes to no measure's numerator or denominator | counted, listed, and its reason named |
| Row 4 | the measure shows **Not recorded**; the others show their own computed values | contributes to every other measure only | not counted as an exclusion — the pull request is included |
| Row 5 | each measure's own computed value — a count, or a state for measure 7 | contributes to every measure | not counted |

A pull request excluded by rows 1-3 appears **only** in the exclusion accounting. A pull request in row 4 appears in the rows and in the aggregates it can join, and its absence from one measure is visible in that measure's denominator rather than in the exclusion list — two different lists for two different facts.

---

## Operational Visibility

- **Per pull request**: the seven measures, each `computed` with a value or `not_recorded`.
- **Per window**: each measure's aggregate with its own included count; the requested, included and excluded counts; and the exclusions listed with reasons.
- **Strict checks**: per check, the pull requests it fired on over the pull requests it was applied to — a pair, never a single percentage that hides either half.
- **What the report does not show**: any composite score, any threshold, any pass/fail verdict, and any recommendation.

**The report's audience includes a reader deciding to make a check blocking**, and that decision is the one this epic deferred twice. It is worth stating what would make the report useless for it: a denominator that silently includes pull requests the check never ran on, and a numerator that counts rounds instead of pull requests. Both are ruled out above, and both are the errors a straightforward implementation makes.

---

## Acceptance Criteria

- [ ] **AC-1.** For a single pull request with a readable history, the report presents all seven measures listed in Statuses / Enum Values.
- [ ] **AC-2.** The report supports a single pull request and a window of the most recent *n* pull requests, and produces the same per-pull-request values in both.
- [ ] **AC-2a.** With no window size given, the report uses **twenty** and states the size it used.
- [ ] **AC-2d.** Twenty has exactly one source: no configuration, environment variable or flag changes the default, and passing a window size is the only way to use a different one.
- [ ] **AC-2b.** A window size that is `0`, negative, or not a whole number is refused: the report names the value it was given and produces no report.
- [ ] **AC-2c.** A window larger than the number of pull requests that exist produces a report over the ones that exist, and is not a refusal. The requested count reconciles against what was found.
- [ ] **AC-3.** Rounds equals the number of history entries recorded for the pull request.
- [ ] **AC-4.** External blocking rounds counts the rounds for which a missed-finding record exists, whatever local evidence state that record carries.
- [ ] **AC-4a.** Blocking findings is reported as its own measure, in findings, and is **not** apportioned between reviewers. A report that attributes any part of the aggregate count to a named reviewer fails this criterion, because the history does not say who raised what.
- [ ] **AC-4b.** The report presents **no** measure of what the local reviewer found. A measure purporting to count local findings or local blocking rounds fails this criterion.
- [ ] **AC-5.** Confirmed miss records and possible miss records are reported as two values and are never summed into one.
- [ ] **AC-5a.** A pull request with both kinds of record shows both; a report presenting only their total fails this criterion.
- [ ] **AC-5b.** Both measures count **records**, one per qualifying external round. A record describing three blocking findings contributes one, not three.
- [ ] **AC-6.** `codex-github` invocations equals the number of rounds in which that reviewer was dispatched, counted from the per-round platform list.
- [ ] **AC-7.** Final current-head evidence reflects the **last** recorded round, and states whether that round's verdict was made against the pull request's current head. Its `computed` value is that state, not a number.
- [ ] **AC-8.** Every measure is computed from the reviewer-loop history alone. No measure re-runs a reviewer, reads a diff, or derives a value the history does not contain.
- [ ] **AC-9.** In window mode the report shows one row per included pull request, then the aggregates, then the exclusion accounting.
- [ ] **AC-10.** Requested, included and excluded counts reconcile: requested equals included plus excluded.
- [ ] **AC-11.** Every excluded pull request carries exactly one of `no_history`, `unparseable_history` or `history_unavailable`, and the three are distinguishable in the output.
- [ ] **AC-12.** A pull request excluded by rows 1-3 contributes to no measure's numerator and no measure's denominator.
- [ ] **AC-13.** A measure whose fields are absent from a readable history reports **not recorded**, never `0`, and never an empty rendering.
- [ ] **AC-13b.** A pull request may be **not recorded** for more than one measure at once, and each such measure independently excludes it from that measure's denominator alone.
- [ ] **AC-13a.** A pull request in that state still contributes to every other measure, and is **not** listed as an excluded pull request.
- [ ] **AC-14.** Each measure's aggregate carries its own included count, and two measures in one report may have different included counts.
- [ ] **AC-15.** The seven measures are totals and states: a pull request with four external blocking rounds contributes four to that measure, not one. No measure is capped at one per pull request.
- [ ] **AC-15a.** The per-pull-request cap applies to **strict-check incidence only**: a check reported on three rounds of one pull request contributes one to that check's numerator.
- [ ] **AC-16.** Strict-check incidence is reported per check as pull requests fired over pull requests the check was applied to, never over the window's pull-request count.
- [ ] **AC-16b.** The denominator for a **spec** check is the pull requests whose recorded spec strict-check state was `applied`; the denominator for a **plan** check is the pull requests whose recorded applied set contains that check. The report does not read an applied set from #1650's records, which contain none.
- [ ] **AC-16a.** Checks in one report may have different applied counts from each other, and each check's own applied count is shown beside its incidence.
- [ ] **AC-17.** The report writes nothing: no pull-request comment, no label, no tracker change, no file that persists between runs.
- [ ] **AC-18.** The report's exit status indicates whether the report was produced. Excluded pull requests, not-recorded measures and any particular values do not change it.
- [ ] **AC-19.** A window in which every pull request is excluded produces the exclusion accounting and **no** aggregates, rather than aggregates of zero.
- [ ] **AC-20.** The report presents no composite score, no threshold, and no recommendation about whether any check should block.

---

## Out of Scope (MVP)

1. **Deciding anything.** The report does not make a check blocking, change a reviewer's configuration, or set a threshold. Deferral note: this epic's whole sequence is measurement before response, and a control loop built on a report nobody has read yet would inherit every error in it.
2. **A composite effectiveness score.** Combining seven measures into one number requires weights, and no basis for choosing them exists. Deferral note: the reader compares the measures; when a weighting has been argued for on real data, it can be added.
3. **Attributing a miss to a cause.** #1651 records that a miss happened, not why, and the report does not guess. Deferral note: cause attribution is #1651's own deferral and nothing here changes it.
4. **Reconstructing history the loop did not write.** A pull request reviewed before a field existed does not get that field inferred from its diff, its comments or its checks. Deferral note: an inferred value is indistinguishable in the output from a recorded one, and this report's value depends entirely on that distinction holding.
5. **Trends over time.** The window is the most recent *n* pull requests, not a time series, and the report draws no line through them. Deferral note: a trend over a denominator that changes between measures would mislead more than it shows.
6. **Storing or caching results.** Each run reads the histories again. Deferral note: a cache would have to be invalidated when a pull request is re-reviewed, and the report is cheap enough that the correctness risk is not worth the saving.
7. **Reporting across repositories.** One repository per run. Deferral note: nothing in the design forbids it, and nothing in this epic needs it.
8. **Anything the local reviewer found, per reviewer.** The history records one aggregate blocking count per round and a list of which reviewers ran; it attributes no finding and no blocking result to a reviewer, and no item in this epic adds one. #1651's local evidence state is written on qualifying **external** rounds and says nothing about a round the local reviewer was alone in. Deferral note: recovering this means changing what the reviewer loop **writes**, and this item is a reader — an item that both extended the ledger and reported over it would ship its own denominator. The brief's question is still answerable without it: the miss rate is measures 4 and 5 over measure 2.
