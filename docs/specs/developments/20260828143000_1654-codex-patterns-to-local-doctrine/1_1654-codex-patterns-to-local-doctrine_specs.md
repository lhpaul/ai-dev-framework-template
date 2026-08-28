# Review Doctrine from External Findings — Spec

**Depends on**: 1653-split-reviewer-prompts-by-stage

---

## Overview

External reviewers keep finding the same *kinds* of problem. Not the same problem — the same shape of problem, in different documents, months apart: a matrix that disagrees with the criteria above it, an opt-out whose source of truth is named in two places, a rule whose worked example contradicts it. The local reviewer runs first and cheaply, and could look for those shapes before an expensive reviewer is ever dispatched. Today it cannot, because nothing turns a finding that already happened into something the next review is told to look for.

This feature adds a maintained **review doctrine**: a short catalogue of recurring finding patterns, each written as a general shape with a minimal example and the question a reviewer should ask, never as a story about the pull request it came from. The doctrine is supplied to the local reviewer with every review, and the reviewer reports whether it was supplied — because a review that silently proceeds without the doctrine it claims to apply is worse than one that never claimed it.

The catalogue is deliberately small and deliberately bounded. Its value is that a reviewer actually reads all of it; a doctrine that grows without limit becomes a document nobody consults, and the first thing that stops fitting is the last pattern added.

---

## Issue-Objective Traceability

The objectives below are the discrete requirements stated in issue #1654. Every one maps to acceptance criteria and use cases here, or to an explicit entry under **Out of Scope (MVP)** with a deferral note. No objective is dropped.

| # | Objective (from #1654) | Where it is satisfied |
| --- | --- | --- |
| 1 | *Problem* — external findings are not converted into reusable local review doctrine | Use Cases 1 and 5; AC-1, AC-2, AC-16 |
| 2 | *Outcome* — findings become maintained examples or checklist doctrine consumed by the local reviewer | Use Cases 1-4; AC-3 through AC-9; Operational Visibility |
| 3 | *Scope* — seed the five patterns observed on PR #1646: criteria/matrix mismatch, opt-out ambiguity, parser-surface conflict, trigger ambiguity, and examples contradicting rules | AC-2 and the five seeded entries in Statuses / Enum Values; Use Case 5 |
| 4 | *Scope* — tests or fixtures proving the doctrine is included in local review context | AC-6, AC-7, AC-10; Use Case 2; Operational Visibility |
| 5 | *Scope* — keep examples generalized rather than tied to one pull request | AC-4, AC-5; the generality rule in Business Rules; Use Case 5, Considerations |

---

## Use Cases

### Use Case 1: A review runs with the doctrine supplied

**Actor**: The reviewer loop, running on behalf of the agent or maintainer advancing a pull request.
**Preconditions**: The doctrine catalogue exists and is within its size bound.

**Steps**:

1. The loop starts a local review of a pull request.
2. The reviewer assembles the review context it already builds — the changed files, the diff summary, the review contract, and (from the previous item) the stage and its checklists.
3. The reviewer adds the doctrine catalogue to that context.
4. The reviewer records that the doctrine was supplied, and which version of it.
5. The review proceeds.

**Postconditions**: The review was performed with the doctrine available, and the record says so.

**Information shown**:

- That the doctrine was supplied, and the catalogue's identifying version.
- The number of patterns supplied.

**Considerations**:

- The doctrine is supplied for **every** stage, not only for one. A criteria/matrix mismatch is a defect in a spec, a plan and a protocol alike; scoping the doctrine to one stage would mean discovering the same shape three times.
- The doctrine adds to the review context. It never replaces the review contract, the stage checklists, or the changed files.

---

### Use Case 2: The doctrine cannot be supplied

**Actor**: The reviewer loop.
**Preconditions**: The catalogue is missing, unreadable, or larger than its bound.

**Steps**:

1. The loop starts a local review.
2. The reviewer tries to read the catalogue and cannot, or reads it and finds it over the bound.
3. The reviewer records the specific reason.
4. The review proceeds **without** the doctrine, and its result is reported as it would be today.

**Postconditions**: The review completed, and the record states plainly that it ran without the doctrine and why.

**Information shown**:

- The reason the doctrine was not supplied, distinguishing absent from unreadable from over-bound.

**Considerations**:

- **The review is not failed for this.** The doctrine is an improvement to a review, not a precondition for one, and a repository that has not adopted a catalogue must still get local review. What must never happen is the silent case: a review that ran without the doctrine and reports nothing about it.
- The three reasons are kept distinct because they have different owners. Absent is a repository that has not adopted the doctrine. Unreadable is an environment fault. Over-bound is a maintainer who added one pattern too many, and it is the only one that appears *after* the catalogue was working.

---

### Use Case 3: A maintainer adds a pattern

**Actor**: A maintainer, or an agent acting for one, who has just seen an external reviewer find something the local reviewer missed.
**Preconditions**: The finding has been resolved and its shape is understood.

**Steps**:

1. The maintainer writes a new entry: the pattern's name, the general shape, a minimal example, and the question a reviewer should ask to detect it.
2. The maintainer removes every trace of the specific occurrence — no pull request number, no issue number, no file path from the incident, no title.
3. The maintainer opens a pull request in the ordinary way.
4. The repository's checks confirm the entry is well-formed, is generic, and that the catalogue still fits its bound.

**Postconditions**: The catalogue has one more pattern and is still within bound.

**Actions available**:

- Add a pattern; revise an existing pattern's wording; remove a pattern that has stopped recurring.

**Considerations**:

- If the catalogue would exceed its bound, the maintainer must remove or merge a pattern rather than raise the bound. The bound exists to force that choice; a bound that moves whenever it binds is not a bound. Raising it is a deliberate, separately reviewed change to this feature's own contract.

---

### Use Case 4: A reviewer applies the doctrine and reports a finding

**Actor**: The local reviewer.
**Preconditions**: The doctrine was supplied.

**Steps**:

1. The reviewer reads the document under review against the doctrine's patterns.
2. It finds a passage matching one of the shapes.
3. It reports the finding in its ordinary format, naming the pattern it matched.

**Postconditions**: The finding carries the pattern's name, so a later reader can tell doctrine-driven findings from the rest.

**Considerations**:

- Naming the pattern is required of the report, not of the judgement. A reviewer must not withhold a real finding because it fits no catalogued pattern, and the doctrine says so in its own preamble. The catalogue is a list of things worth looking for, never the list of things worth reporting.

---

### Use Case 5: Someone reads the catalogue to understand what it is for

**Actor**: A maintainer, a reviewer, or an agent onboarding to the repository.

**Steps**:

1. The reader opens the catalogue.
2. Each entry states its shape, its example and its question in the same order, so entries can be scanned rather than read.

**Postconditions**: The reader can apply a pattern to a document they have never seen.

**Considerations**:

- **Generality is the property that makes an entry reusable, and the easiest one to lose.** "PR #1646's decision matrix disagreed with its acceptance criteria" teaches nothing about the next document. "A table that enumerates decisions must agree with the criteria stated above it; check each row against the criterion it claims to implement" applies everywhere. The first is a memory, the second is doctrine, and the difference is enforceable: an entry that names a pull request, an issue, or a person is not general.
- The five seeded patterns come from one pull request's findings. Their *wording* must not.

---

## Business Rules

- The doctrine is **supplementary**. Every review that runs today still runs, with or without it. It adds patterns to look for; it removes nothing and blocks nothing.
- The doctrine is supplied to **every** local review, at every stage.
- A review that runs without the doctrine must **say so**, with the reason. Silence is not permitted.
- Every entry is **general**: no pull request number, no issue number, no person, no title, no path from the incident that produced it.
- Every entry has the same four parts, in the same order: name, shape, minimal example, detection question.
- The catalogue has a **fixed size bound of 12,000 bytes**, measured on the document's stored text — what `wc -c` reports for the file. Bytes rather than characters, words or tokens: bytes are the only unit every check, script and reader measures identically, and a multi-byte character must not make two catalogues of the same apparent length disagree about whether they fit.
- The bound is part of this feature's contract. Exceeding it is a repository error to be fixed by editing the catalogue, never by silently truncating it and never by raising the bound in the same change that breaches it.
- The catalogue's **version is the first twelve hexadecimal characters of the SHA-256 of its stored bytes**. Derived rather than declared: a version a maintainer has to remember to bump is a version that silently stops changing, and the one question the version must answer — *did this review see the same catalogue as that one* — is exactly what a content hash answers.
- A truncated doctrine is **never** supplied. Partial doctrine is worse than none: it looks complete to the reviewer, and the patterns it drops are the ones added most recently, which are the ones nobody has internalised yet.
- The catalogue's version is recorded with every review that uses it, so a later report can tell which reviews saw which patterns.
- Every entry is subject to two different kinds of generality rule, and the spec keeps them apart. One is **mechanically checkable** and is enforced (AC-5); the other is a **human review** obligation and is not claimed to be automated. Asserting a check for the unautomatable half would be a declared-but-unverifiable control.

---

## UX Rules

Not applicable — there is no user interface. The reader-facing surfaces are the catalogue document itself and the reviewer's recorded output, both covered under Operational Visibility.

---

## Statuses / Enum Values

### Doctrine supply states

Four states, mutually exclusive and exhaustive over the reasons a review can begin:

| State | Meaning | Who fixes it |
| --- | --- | --- |
| `supplied` | The catalogue was read and added to the review context | — |
| `absent` | No catalogue exists in this repository | a maintainer, by adopting one; not an error |
| `unreadable` | A catalogue exists but could not be read | the environment |
| `oversized` | A catalogue exists and is larger than the bound | a maintainer, by editing the catalogue |

### The five seeded patterns

The catalogue ships with exactly these five, which are the shapes observed on PR #1646:

| # | Pattern name | Shape |
| --- | --- | --- |
| 1 | Criteria/matrix mismatch | A table that enumerates decisions disagrees with the criteria stated above it, or omits a combination those criteria admit |
| 2 | Opt-out ambiguity | A way to disable or bypass behavior has its source of truth stated in more than one place, or in none |
| 3 | Parser-surface conflict | A rule about how input is recognised conflicts with the syntax the document elsewhere requires, or assumes a capability the stated tooling lacks |
| 4 | Trigger ambiguity | A condition that starts behavior does not say what happens when its inputs are absent, empty, or malformed |
| 5 | Example contradicting rule | A worked example demonstrates something the rule beside it forbids, or omits a step the rule requires |

Each ships with a minimal example and a detection question. None names PR #1646.

---

## Decision Matrix

Every combination of the **three** inputs that decide the supply state — presence, readability, and fit within the bound. No combination is omitted, and no row is unreachable.

| # | Catalogue present? | Readable? | Within bound? | State | Doctrine in context? | Review runs? |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | no | — | — | `absent` | no | yes |
| 2 | yes | no | — | `unreadable` | no | yes |
| 3 | yes | yes | no | `oversized` | no | yes |
| 4 | yes | yes | yes | `supplied` | yes | yes |

Rows 1 to 3 all end with the review running and the reason recorded. The distinction between them is not academic: row 1 is a repository that never adopted the doctrine, row 2 is a broken environment, and row 3 is a maintainer's edit that needs undoing. Collapsing them into one "no doctrine" state would make the only actionable case invisible.

The matrix has no state of its own for "read but empty". An empty catalogue is `supplied` with zero patterns, and the count reported alongside the state is what distinguishes it. Treating empty as a failure would make adopting the doctrine a two-step operation for no benefit.

Later rows are unreachable when an earlier input fails, which is why those cells read `—` rather than carrying a value: a catalogue that is absent has no readability to assess, and one that cannot be read has no size to compare. The dashes are "not evaluated", not "either value".

### What is reported in each state

The three reported values are defined for every state, so no implementer has to choose a sentinel:

| State | Supply state reported | Pattern count | Catalogue version |
| --- | --- | --- | --- |
| `supplied` | `supplied` | the number of entries in the catalogue, `0` for an empty one | the twelve-character hash |
| `oversized` | `oversized` | `0` — no pattern was supplied, whatever the file contains | the twelve-character hash: the file was read, and *which* version was too large is the first thing a maintainer needs |
| `unreadable` | `unreadable` | `0` | empty — no bytes were obtained, so no hash exists |
| `absent` | `absent` | `0` | empty — there is nothing to hash |

The count is *patterns supplied*, never *patterns present*. An `oversized` catalogue with nine entries reports `0`, because zero reached the review. Reporting nine would make the effectiveness data claim coverage that never happened.

---

## Operational Visibility

- The reviewer's recorded output carries the supply state, the pattern count, and the catalogue version.
- These reach the reviewer-loop summary through the same mechanism the stage values use, so a reader of a pull request can see whether the doctrine was in play without re-running anything.
- The evidence artifact carries the same three values, so a later effectiveness report can group reviews by which doctrine they saw.

---

## Acceptance Criteria

1. **AC-1**: A review-doctrine catalogue exists in the repository as a single document.
2. **AC-2**: The catalogue contains the five seeded patterns named in Statuses / Enum Values, and each has a name, a shape, a minimal example and a detection question.
3. **AC-3**: The catalogue's preamble states that it lists shapes worth looking for and is not the set of things worth reporting.
4. **AC-4**: No catalogue entry contains any of these **mechanically detectable** references to a specific incident: a `#` followed by digits; a URL whose host is the repository's forge; the word `PR` or `issue` followed by digits, case-insensitively; or a path beginning `docs/specs/developments/`.
5. **AC-5**: A repository check fails when an entry violates AC-4, and passes when it does not. The check's authoritative prohibited set is exactly the four forms listed in AC-4 — no more, so the check is implementable, and no fewer, so it is worth running.
5a. **AC-5a**: The remaining half of the generality rule — no person's name, no document title, no wording that only makes sense to someone who saw the original incident — is a **human review** obligation, listed in the catalogue's own contribution guidance and in the `Workflow Policy Review Checklist`. No automated check is claimed for it. A person's name and a document title have no reliable machine representation, and a check that pretended to catch them would report clean on the cases it cannot see, which is worse than having no check at all.
6. **AC-6**: When the catalogue is present, readable and within bound, its full text is present in the review context supplied to the local reviewer.
7. **AC-7**: When AC-6 holds, the reviewer reports the supply state `supplied`, the number of patterns, and the catalogue's version.
8. **AC-8**: When the catalogue is absent, unreadable, or over the bound, the reviewer reports the corresponding state from the four-state list and the review still runs.
8a. **AC-8a**: In every state, all three values are reported with exactly the values given in **What is reported in each state** — including the empty version for `absent` and `unreadable`, and the zero count for `oversized`.
9. **AC-9**: The doctrine is never supplied in truncated form. If the full text does not fit the bound, the state is `oversized` and no part of the catalogue is supplied.
10. **AC-10**: A test asserts that the doctrine's text is present in the review context, by matching text from the catalogue rather than by asserting that a field is non-empty.
11. **AC-11**: A repository check fails when the catalogue exceeds 12,000 bytes as `wc -c` measures them, and passes at or below it.
12. **AC-12**: The size bound's value is stated in one place, and the check and the reviewer both read it from there rather than each carrying a copy.
12a. **AC-12a**: The catalogue's version is the first twelve hexadecimal characters of the SHA-256 of its stored bytes, and the same derivation is used by every surface that reports it.
13. **AC-13**: The doctrine is supplied for every stage the reviewer recognises, and for the default stage.
14. **AC-14**: Supplying the doctrine does not remove or shorten any part of the review context that exists today.
15. **AC-15**: The supply state, pattern count and version appear in the reviewer's evidence artifact as well as its immediate output.
16. **AC-16**: The catalogue's document explains how to add a pattern, including the requirement to remove incident-specific detail and what to do when the bound is reached.

---

## Out of Scope (MVP)

1. **An effectiveness report over doctrine-driven findings** — which patterns catch the most, which have gone quiet. Deferred to #1657, which owns reporting; this feature's job is to record the version each review saw so that report is possible.
2. **Automatic extraction of patterns from external reviewer output.** Every entry is written by a human or an agent acting deliberately. Automatic extraction would fill the catalogue with incident-shaped text, which is the failure the generality rule exists to prevent, and it would do so faster than review could catch it.
3. **Patterns observed outside PR #1646.** The brief names five seeds and this feature ships exactly those. Later patterns — including any drawn from this epic's own review history — are added through Use Case 3 like any other, once someone has seen the shape recur.
4. **Per-stage doctrine subsets.** The catalogue is supplied whole to every stage. Splitting it by stage is a plausible later refinement and would need evidence that a stage's reviewer is being distracted by patterns that do not apply to it; no such evidence exists.
5. **Enforcing that a reviewer used the doctrine.** The feature can supply the doctrine and record that it did. Whether a model applied it is not observable from outside, and a check that claimed to verify it would be a declared-but-unverifiable control.
