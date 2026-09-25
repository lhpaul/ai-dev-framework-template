# Test-Scope Proportionality

This document is the single normative source for how review gates weigh a
delta between a plan's projected test scaffolding and what an implementation
ships. `REVIEW.md`, Protocol 02, Protocol 03, `strict-plan-checks.md`, and the
tech-lead/developer/code-reviewer agent and skill mirrors each carry one
sentence plus a link here. If a mirror and this document ever disagree, this
document governs.

## Scope of this rule

This rule applies only to deltas in **test scaffolding** — fixture manifests,
proof-cycle lists, case tables, and scenario enumerations that a plan
projected for the tests that exercise a deliverable. It does not apply to:

- **Production-code correctness.** Any delta that changes observable behavior,
  or drops the coverage of an acceptance criterion, stays governed by the
  unchanged Pass 1 rule in `REVIEW.md` ("no missing or extra behaviours"),
  whatever it does to test counts. This is exclusion X1 in Gate A below, and
  it is never relaxed by this document.
- **Third-party reviewer output.** Nothing here weakens verdict-string,
  approval-text, or platform-status matching. The governing distinction: be
  literal about what a third party emits; be substantive about what your own
  team delivers. This is the inverse failure of the exact-match fix built for
  issue #1491.

## Indicative by default, binding only when marked

An enumeration in a merged plan is **indicative** unless the plan marks it
with the exact literal `**Binding enumeration**` on, or immediately above,
the line that introduces it. An unmarked enumeration expresses coverage
intent and may be satisfied by a different, coverage-equivalent set. An
enumeration marked with the exact literal binds the implementer to the listed
items; a delta that removes at least one listed item is blocking regardless
of any Coverage-Harm Statement. An implementation that retains every listed
item and only adds further cases is an addition-only delta — Gate A exclusion
X2 applies, and it is not blocking under this marking either.

The exact literal is required — a marker in a different form, or attached to
an unclear span, does not make the enumeration binding (see Gate A row A8
below). This keeps a plan from becoming binding by accidental phrasing, and
keeps the default permissive because over-binding is the defect this document
fixes.

## The Test-Scope Deviation Record

An implementer whose shipped test scaffolding removes at least one item the
plan projected — the same trigger Gate A's exclusion X2 uses, so a net-even
or net-larger swap that drops a projected item still qualifies, and an
addition-only delta never does — but is coverage-equivalent, records a
**Test-Scope Deviation Record** in the PR. The format and authoring
obligation live in
`docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
(`## Test-Scope Deviation Record`). This is what Gate A evaluates.

## The Coverage-Harm Statement

A blocking finding on a test-scope enumeration delta requires a
**Coverage-Harm Statement**: the reviewer names both

1. the specific coverage the removed items provided, and
2. the defect class that now escapes because that coverage is gone.

A finding that names only one half does not satisfy the rule and is not
blocking on that ground alone.

## Gate A — Reviewer evaluating a test-scope delta

Gate A resolves on two independent questions, in this order: **what the delta
touches**, then **whether anything was removed**. Both are scope questions,
settled before any row is read. A delta that either exclusion catches never
reaches the table; only a delta caught by neither is resolved by a row.

**Exclusion X1 — what the delta touches.** A delta touching observable
behavior, or the coverage of an acceptance criterion, is governed by the
unchanged Pass 1 rule and is `blocking` there, whatever it does to test
counts and whatever this gate says. Gate A neither relaxes nor restates that
rule, and a behavior delta never enters the table below.

**Exclusion X2 — whether anything was removed.** A delta that removes
nothing — the delivered scope only adds to, or leaves intact, every item the
plan projected — produces no finding from this gate, whatever the totals and
whatever the plan marking or record. Ordinary Pass 2 quality review still
applies.

The two exclusions are independent and neither overrides the other: a
behavior delta is Pass 1's business whatever its test totals, and an
addition-only scaffolding delta is outside Gate A whatever its marking or
record.

**In scope, therefore:** a delta that touches test scaffolding only **and**
removes at least one item the plan projected. Rows A2–A8 cover exactly that
set and are mutually exclusive on `Plan marking` x `Deviation record` x
`Harm statement available`.

**Item count is never a gate input.** X2 asks whether anything was removed,
not whether the delivered scope is smaller or larger. A removal that nets
even or larger — a swap, a consolidation, a rewrite — is still a removal,
does not satisfy X2, and is treated exactly as the equivalent shrinking
delta. A raised total is never a defense against a coverage loss.

| # | Plan marking | Deviation record | Harm statement available | Outcome | Required next action |
| --- | --- | --- | --- | --- | --- |
| A2 | Indicative (unmarked) | Present and complete | Yes — reviewer names the lost coverage **and** the defect class | `blocking` | Reviewer states both halves; implementer restores that coverage or narrows the deviation |
| A3 | Indicative | Present and complete | No | Not blocking; `suggestion` at most | Accept the recorded rationale; do not restate the count as a requirement |
| A4 | Indicative | Missing or incomplete | No | `important` | Request the record before `ready-for-human-review`; do not block on the delta alone |
| A5 | `**Binding enumeration**` | Present | Not required | `blocking` | Restore the listed items, or obtain a human decision to amend the plan |
| A6 | `**Binding enumeration**` | Missing | Not required | `blocking` | Same as A5 |
| A7 | Indicative | Missing or incomplete | Yes — reviewer names the lost coverage **and** the defect class | `blocking` | A stated harm is blocking whether or not the record was written; reviewer states both halves and also requests the record |
| A8 | Marking malformed — marker text present in a form other than the exact literal, or attached to an unclear span | Any | Any | `important` on the plan wording; the delta itself follows A2/A3/A4/A7 as indicative | Ask for the plan marker to be corrected; missing or malformed marking never upgrades the delta to blocking |

## Gate B — Plan reviewer applying the advisory test-scope sanity signal

Outcome is `suggestion` in every firing row. This gate never blocks
readiness and never changes a review verdict.

| # | Signal | Outcome | Required next action |
| --- | --- | --- | --- |
| B1 | Projected test scaffolding exceeds the size of the deliverable it protects | `suggestion` | Plan states why the scaffolding is proportionate, or reduces it |
| B2 | A prose-only or documentation-only deliverable proposes a custom parser, scanner, or matcher to validate it | `suggestion` | Plan justifies the parser, or replaces it with a simpler check |
| B3 | Neither signal present | No finding | None |
| B4 | Sizes cannot be estimated from the plan | No finding | Do not guess a ratio; optionally ask the plan to state expected test volume |

This gate judges proportionality of projected volume, not the derivation of
any count the plan states; when a plan does give a test-scaffolding count,
[`plan-authoring-rigor-rules.md`](plan-authoring-rigor-rules.md) Rule 3
governs how that count must be derived and recorded.

Gate B's trigger is deliberately marked indicative: it is implemented as one
advisory row (`test_scope_proportionality`, `Source: not required`) in
`docs/workflow/development-workflow/strict-plan-checks.md`, whose own
contract makes every finding it produces non-blocking.

## Blocking rules this change does not relax

The following rules continue to require their specific kind of coverage,
regardless of item counts, and are unaffected by the indicative default or
the Coverage-Harm Statement threshold above:

- **Planted-violation proof** — any PR that adds or materially modifies an
  automated check, guard, lint rule, or CI job must still prove, at a
  concrete file and line, that the check fails on the violation and passes
  once it is removed.
- **E2E fixture contract** — a feature PR in a repository with a committed
  E2E suite must still extend the suite's seed/fixture data with the
  feature's edge cases.
- **Filter-schema canary test** — a new filter parameter on a tool schema
  must still carry a canary test proving filtered and unfiltered results
  differ.
- **Scope-residual evidence** — sweep, batch, helper-extraction,
  numeric-target, or pattern-completeness work must still produce and verify
  residual evidence before readiness.
- **Acceptance-criterion coverage** — every acceptance criterion must still
  have at least one test, scenario, or proof that would fail if the
  criterion were unmet.

None of these is judged by a row count; each is judged by whether the kind
of coverage it names is present. A delta that touches one of these rules is
also, by definition, within exclusion X1 or is a distinct rule from Gate A
and is evaluated under its own terms.

## Worked example — the motivating scenario

A plan for a documentation deliverable specified a large literal fixture
manifest and a proof-cycle list. The implementation shipped a curated subset
of that manifest with coverage-equivalent tests and was rejected as a
unilateral scope reduction.

Read against the revised gate, the same delta resolves differently depending
on what the reviewer can say about it:

- **If the only objection available is that the delivered count differs from
  the plan's count** — no reviewer can name a specific piece of coverage the
  removed rows uniquely provided, or the defect class that now escapes — the
  delta lands on **row A3**: not blocking, `suggestion` at most, the recorded
  rationale is accepted.
- **If the reviewer can name a behavior the removed rows uniquely exercised,
  and the defect class that now escapes without them** — the delta lands on
  **row A2**: `blocking`, with both halves of the Coverage-Harm Statement
  stated in the finding.

The historical figures above are a record of what happened in that case, not
a requirement for future plans; do not read them as a minimum or maximum test
count.
