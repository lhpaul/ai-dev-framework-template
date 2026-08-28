# Missed-Finding Telemetry — Spec

**Depends on**: 1648-reviewer-loop-current-head-evidence

---

## Overview

The reviewer loop runs a cheap local reviewer before it runs slow external ones, on the premise that front-loading findings costs fewer review rounds. Nobody can currently say whether that premise holds. The loop records that each reviewer ran and what it concluded, but not the one thing that would settle the question: how often an external reviewer finds something blocking on a pull request the local reviewer had already called clean.

This feature records exactly that. When an external reviewer reports blocking findings on a pull request where the local reviewer had previously reported clean, the loop writes a compact record of the miss into the pull request's reviewer-loop history — which reviewer found it, on which commit, how many findings and where, and what the local reviewer's verdict had been at the time. The record is deliberately conservative: it claims a miss only when the local reviewer demonstrably said clean, and says so plainly when the evidence is too weak to make the claim. Its purpose is measurement, and a measurement that inflates its own numbers is worthless.


---

## Issue-Objective Traceability

The objectives below are the discrete requirements stated in issue #1651. Every
one maps to acceptance criteria and use cases here, or to an explicit entry
under **Out of Scope (MVP)** with a deferral note. No objective is dropped.

| # | Objective (from #1651) | Where it is satisfied |
| --- | --- | --- |
| 1 | *Problem* — quantify whether the local reviewer reduces external rounds, by tracking what external reviewers found after a local clean result | Use Cases 1-4; the counting rule and the record-every-qualifying-round rule in Business Rules; the Decision Matrix rows 4-7; AC-1 through AC-7 |
| 2 | *Outcome* — the reviewer-loop history records missed-by-local findings when an external reviewer reports blockers after a local clean result | Use Case 1; AC-1 through AC-3; Operational Visibility, reviewer-loop history |
| 3 | *Scope* — capture the reviewer | AC-1; Use Case 1, Information shown |
| 4 | *Scope* — capture the head commit | AC-1; the attribution rule in Business Rules; AC-11 for the case where it cannot be established |
| 5 | *Scope* — capture the finding count | AC-1 |
| 6 | *Scope* — capture the paths | AC-1; AC-14 bounds how many are shown |
| 7 | *Scope* — capture whether the local reviewer was clean on the same head or an ancestor | AC-1 through AC-4; the four clean-ancestry states, which Business Rules forbid merging |
| 8 | *Scope* — keep the record compact enough for PR comments | AC-13 through AC-15, with character and path bounds rather than an adjective; Use Case 4, Considerations |
| 9 | *Scope* — support later effectiveness reporting | AC-16 (records readable in full without re-running a reviewer); the report itself is **deferred** to Out of Scope item 1 (#1657) |

---

## Use Cases

### Use Case 1: An external reviewer finds something the local reviewer cleared

**Actor**: The reviewer loop, running on behalf of the agent or maintainer advancing a pull request.
**Preconditions**: The pull request has an existing reviewer-loop history. The local reviewer ran earlier in the pull request's life and reported clean. An external reviewer — any configured reviewer other than the local one — has now reported at least one blocking finding.

**Steps**:

1. The external reviewer returns a result carrying blocking findings.
2. The loop looks back at the local reviewer's most recent verdict for this pull request.
3. It establishes whether that verdict was clean, and whether it described the same commit the external reviewer just reviewed or an earlier one.
4. It writes a missed-finding record into the pull request's reviewer-loop history.
5. It shows the record in the reviewer-loop summary on the pull request.

**Postconditions**: The pull request carries a durable, machine-readable record of the miss alongside the history the loop already keeps. Nothing about the review outcome changes — the findings are handled exactly as they are today, and the record neither blocks nor unblocks anything.

**Information shown**:

- Which external reviewer reported the findings.
- The commit it reviewed.
- How many blocking findings it reported, and which files they touched.
- What the local reviewer's verdict had been, and whether it covered the same commit or an earlier one.

**Actions available**:

- None. The record is evidence, not a prompt. A human reading it may choose to act on the pattern it reveals, but the loop asks nothing of them.

**Considerations**:

- A pull request can accumulate several missed-finding records, one per external reviewer round that qualifies. They accumulate rather than overwrite, because the shape of the sequence is itself the signal.
- The record must survive the pull request being re-reviewed, force-pushed, or converted between draft and ready, since the history it lives in already does.

---

### Use Case 2: An external reviewer finds something, but the local reviewer never cleared it

**Actor**: The reviewer loop.
**Preconditions**: An external reviewer has reported blocking findings, and the local reviewer's most recent verdict for this pull request was anything other than clean — it reported findings, was skipped, was unavailable, or never ran at all.

**Steps**:

1. The external reviewer returns a result carrying blocking findings.
2. The loop looks back at the local reviewer's most recent verdict.
3. It finds no clean verdict to have been missed against.
4. It writes a record that names what the local evidence actually was, and does not count the findings as missed.

**Postconditions**: The history records that an external reviewer found something and that no local clean verdict preceded it. The effectiveness numbers are unaffected.

**Information shown**:

- The same reviewer, commit, count and paths as Use Case 1.
- The local evidence state, stated explicitly rather than left blank — the local reviewer reported findings, was skipped, was unavailable, or never ran.

**Considerations**:

- This is the common case early in a pull request's life, and it must not be mistaken for a miss. A reviewer that never claimed the code was clean cannot have missed anything.
- The distinction matters most when the local reviewer was *unavailable*. An unavailable reviewer looks superficially like a reviewer that found nothing, and conflating the two would make an outage read as a quality failure.

---

### Use Case 3: The local evidence cannot be established

**Actor**: The reviewer loop.
**Preconditions**: An external reviewer has reported blocking findings, and the loop cannot determine what the local reviewer's most recent verdict was — the history is unreadable, or it predates the point where the loop began recording the evidence this feature reads.

**Steps**:

1. The external reviewer returns a result carrying blocking findings.
2. The loop attempts to establish the local reviewer's most recent verdict and fails.
3. It writes a record whose local evidence state is `unknown`.

**Postconditions**: The history records the external findings and records that the local evidence could not be established. The findings are **not** counted as missed.

**Information shown**:

- The reviewer, commit, count and paths.
- An explicit `unknown` local evidence state, distinguishable from every state in which the evidence *was* established.

**Considerations**:

- Not counting is the conservative direction here, and it is deliberate. A miss recorded on absent evidence would overstate the local reviewer's failures, and the entire value of this record is that its numbers can be trusted.
- `unknown` must be distinguishable from "the local reviewer ran and found nothing" and from "the record is missing". A reader who cannot tell those apart cannot use the data.

---

### Use Case 4: A human or a later report reads the accumulated records

**Actor**: A maintainer reading the pull request, or the reviewer-effectiveness report built on this data.
**Preconditions**: The pull request has one or more missed-finding records in its reviewer-loop history.

**Steps**:

1. The reader opens the reviewer-loop summary on the pull request, or a later report reads the history directly.
2. They see each qualifying external round, its local evidence state, and its finding count and paths.

**Postconditions**: The reader can tell, for this pull request, how many times an external reviewer found something after the local reviewer said clean, and on which commits.

**Information shown**:

- One line per missed-finding record in the summary, compact enough to read without expanding anything.
- The full structured record in the history, for a report to consume.

**Considerations**:

- The summary comment already carries the reviewer-loop history and is close to the length a human will read. The missed-finding lines must not push it past that, which is why the record is per-round rather than per-finding.

---

## Business Rules

- A finding counts as **missed by the local reviewer** only when the local reviewer's most recent verdict was clean **and** covered the commit the external reviewer reviewed or one of its ancestors — states `clean_same_commit` and `clean_earlier_commit`. Every other state does not count. The counting rule enumerates the states that *do* count rather than the states that do not, so a state introduced later is excluded until someone deliberately includes it.
- The local evidence state is recorded on every external round that reports blocking findings, whether or not it counts as a miss. A record that only appeared for confirmed misses would make the denominator unknowable, and a rate needs both halves.
- A clean local verdict is classified by its ancestry relationship to the commit the external reviewer reviewed — same, ancestor, descendant, or unrelated — and the four are recorded as distinct states that are never merged. Only same and ancestor count. A descendant clean means the local reviewer cleared newer code than the external reviewer looked at, and an unrelated clean means a force-push severed the relationship; neither is evidence that the local reviewer saw what was found.
- A local reviewer that is **configured but has not yet produced a verdict** is recorded distinctly from one that is **not configured at all**. The first describes a pull request early in its life, the second a repository that will never produce local evidence, and summing them would make the two indistinguishable in the numbers.
- Only **blocking** external findings qualify. Advisory or suggestion-level findings do not create a record, because the local reviewer is not expected to surface them and counting them would inflate the miss rate.
- The **local** reviewer's own findings never create a missed-finding record. The record exists to compare an external reviewer against the local one; a reviewer cannot miss its own findings.
- Records accumulate; they are never overwritten or de-duplicated. Two external rounds finding the same thing on the same commit are two records, because the loop genuinely ran twice.
- No missed-finding record changes any review outcome, readiness label, tracker status, or merge decision. This feature only observes.
- Every record is attributable to a specific commit. A record that cannot name the commit the external reviewer reviewed is not written, and the loop reports why rather than writing an unattributable record.

---

## Statuses / Enum Values

The **local evidence state** recorded on each external round that reports
blocking findings. The list is closed: any situation not described by a row is
recorded as `unknown`.

| Code value | Display label | Description | Counts as missed |
| --- | --- | --- | --- |
| `clean_same_commit` | Clean, same commit | The local reviewer reported clean on the exact commit the external reviewer reviewed. | Yes |
| `clean_earlier_commit` | Clean, earlier commit | The local reviewer's most recent clean verdict was on an ancestor of the commit the external reviewer reviewed. | Yes |
| `clean_later_commit` | Clean, later commit | The local reviewer's most recent clean verdict was on a descendant of the commit the external reviewer reviewed — it cleared newer code than the external reviewer looked at. | No |
| `clean_unrelated_commit` | Clean, unrelated commit | The local reviewer's most recent clean verdict was on a commit with no ancestry relationship to the one the external reviewer reviewed, which a force-push can produce. | No |
| `not_clean` | Reported findings | The local reviewer's most recent verdict reported findings of its own. | No |
| `skipped` | Skipped | The local reviewer was configured and deliberately skipped this round. | No |
| `unavailable` | Unavailable | The local reviewer was configured but could not run — a timeout, an outage, or a credentials failure. | No |
| `not_yet_run` | Not yet run | The local reviewer is configured and has not yet produced any verdict on this pull request. | No |
| `not_configured` | Not configured | The local reviewer is not configured for this repository, so it will never run. | No |
| `unknown` | Unknown | The local reviewer's verdict could not be established from the available history. | No |

Exactly two of the ten states count as missed: `clean_same_commit` and
`clean_earlier_commit`. Every other state, including `unknown` and any situation
this table does not describe, does not count.

`clean_later_commit` and `clean_unrelated_commit` are separated from
`clean_earlier_commit` deliberately. A clean verdict on newer or unrelated code
is not evidence that the local reviewer looked at what the external reviewer
found, so counting it would attribute a miss to a reviewer that never saw the
code. `not_yet_run` is separated from `not_configured` for the same reason the
spec separates `unavailable` from `not_clean`: "has not run yet" and "will never
run" describe different repositories and must not be summed.

**Valid transitions**: none. The state is decided once, when the record is
written, and describes the evidence at that moment. It is never revised — a
later local run does not rewrite an earlier record, because the record is a
historical observation rather than a current status.

---

## Decision Matrix

The complete gate, from an external reviewer returning a result to a record
existing or not. Rows are evaluated in order and the first match decides.

| # | External result | Commit attributable | Local evidence state | Record written | Counts as missed | Next action |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Reported by the local reviewer itself | — | — | No | No | Nothing; a reviewer cannot miss its own findings |
| 2 | No blocking findings — clean, skipped, or advisory only | — | — | No | No | Nothing; only blocking external findings qualify |
| 3 | Blocking findings | **No** | — | No | No | Report why the commit could not be established; write no unattributable record |
| 4 | Blocking findings | Yes | `clean_same_commit` | Yes | **Yes** | Show in the summary; include in the effectiveness numbers |
| 5 | Blocking findings | Yes | `clean_earlier_commit` | Yes | **Yes** | Show in the summary; include in the effectiveness numbers |
| 6 | Blocking findings | Yes | Any other state in the Statuses table | Yes | No | Show in the summary; include in the denominator only |
| 7 | Blocking findings | Yes | Not describable by any row of the Statuses table | Yes, as `unknown` | No | Show in the summary; include in the denominator only |

Rows 4 through 7 are the reason a record is written on every qualifying external
round rather than only on confirmed misses: rows 6 and 7 are the denominator,
and a rate needs both halves.

---

## Operational Visibility

- **Reviewer-loop summary**: each missed-finding record appears as one line in the pull request's reviewer-loop summary, naming the external reviewer, the commit, the finding count, and the local evidence state.
- **Reviewer-loop history**: the full structured record is written into the history the loop already maintains on the pull request, in the same place and with the same lifecycle as the entries already there.
- **Audit trail**: no separate audit surface is introduced. The pull request is the record, deliberately — telemetry stored somewhere a reviewer never looks does not get checked against reality.

---

## Acceptance Criteria

- [ ] **AC-1.** When an external reviewer reports blocking findings on a commit for which the local reviewer's most recent verdict was clean on that same commit, the reviewer-loop history gains a record naming that reviewer, that commit, the number of blocking findings, the files they touch, and the local evidence state `clean_same_commit`.
- [ ] **AC-2.** When the local reviewer's most recent clean verdict was on an ancestor of the commit the external reviewer reviewed, the record's local evidence state is `clean_earlier_commit`, and it is distinguishable from `clean_same_commit` without inspecting commits by hand.
- [ ] **AC-3.** When the local reviewer's most recent clean verdict was on a descendant of the commit the external reviewer reviewed, the state is `clean_later_commit` and it does not count as missed.
- [ ] **AC-4.** When the local reviewer's most recent clean verdict was on a commit with no ancestry relationship to the one the external reviewer reviewed, the state is `clean_unrelated_commit` and it does not count as missed.
- [ ] **AC-5.** When the local reviewer's most recent verdict reported findings, the record is still written and its local evidence state is `not_clean`, and it does not count as missed.
- [ ] **AC-6.** When the local reviewer was skipped, was unavailable, is configured but has not yet produced a verdict, or is not configured at all, the record is written with the corresponding state, and the four are distinguishable from one another and from `not_clean`.
- [ ] **AC-7.** When the local reviewer's verdict cannot be established from the history, the record is written with state `unknown` and does not count as missed.
- [ ] **AC-8.** Advisory or suggestion-level external findings produce no missed-finding record.
- [ ] **AC-9.** Findings reported by the local reviewer itself produce no missed-finding record.
- [ ] **AC-10.** Two qualifying external rounds on the same pull request produce two records; neither replaces the other.
- [ ] **AC-11.** When the commit an external reviewer reviewed cannot be established, no record is written and the loop reports the reason.
- [ ] **AC-12.** A pull request carrying missed-finding records reaches exactly the same review outcome, readiness label, and tracker status it would reach without them.
- [ ] **AC-13.** Each record adds exactly one line to the reviewer-loop summary, and that line is at most 200 characters.
- [ ] **AC-14.** A record's summary line names at most three file paths; when the findings touch more than three files, the line names three and states how many more there are.
- [ ] **AC-15.** A pull request carrying twenty records adds at most twenty lines and 4,000 characters to the reviewer-loop summary, whatever the number of findings or the length of their paths.
- [ ] **AC-16.** The records for a pull request can be read back in full by a later report without re-running any reviewer.

---

## Out of Scope (MVP)

- **Reporting or aggregating across pull requests.** This feature produces the per-pull-request record; turning it into an effectiveness report, per pull request or across a window, is item #1657. Deferral note: the brief's "support later effectiveness reporting" objective is met here by producing a readable, complete record, not by producing the report itself. No human confirmation requested — the split follows the epic's own decomposition.
- **Attributing a miss to a cause.** The record says the local reviewer cleared a commit on which an external reviewer later found something. It does not say why — whether the finding was outside the local reviewer's checklist, beyond its context window, or a genuine oversight. Deferral note: cause attribution needs the doctrine work in #1654 to have landed first, and guessing at causes would pollute the measurement this item exists to make trustworthy. No human confirmation requested.
- **Acting on the records.** Nothing in this feature changes a gate, a threshold, or a reviewer's configuration in response to what is recorded. Deferral note: measurement first, response second; a control loop built on unvalidated telemetry is worse than none. No human confirmation requested.
- **Recording near-misses.** An external reviewer that reports advisory findings after a local clean verdict is not recorded. Deferral note: the brief scopes this to blockers, and advisory findings are not something the local reviewer is expected to surface. No human confirmation requested.
