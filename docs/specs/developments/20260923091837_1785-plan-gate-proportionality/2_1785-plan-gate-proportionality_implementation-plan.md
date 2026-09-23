# Plan Gate Proportionality — Implementation Plan

**Source of truth**: GitHub issue #1785 (Refactor item — there is no spec; the
work item brief is normative).
**Smoke test runbook**: [`1785-plan-gate-proportionality.smoke-test.md`](../../../testing/workflow/1785-plan-gate-proportionality.smoke-test.md)

---

## Summary

**Approach**: Make the review contract score the *substance* a plan enumeration
was protecting instead of its *literal shape*. The work makes three moves together:

- A blocking finding on a test-scope enumeration delta now requires a
  **Coverage-Harm Statement** — the reviewer must name the specific coverage the
  removed items provided and the defect class that now escapes. A delta with no
  articulable harm is not blocking.
- An implementer who ships a smaller-but-equivalent test scope records a
  **Test-Scope Deviation Record** in the PR, which is what the gate evaluates.
- Plan authoring stops emitting accidental contracts: a plan enumeration is
  **indicative** unless the plan marks it binding, and plan review gains an
  advisory (never blocking) test-scope sanity signal implemented as one new row
  in the existing strict-plan-checks registry.

The normative text lives in one new canonical document; every other surface
gains a short pointer plus the minimum wording change needed to stay consistent.

**Estimated complexity**: M

**Rationale**: No new executable logic. The work is a review-contract change
(prose across mirrored surfaces), one data row added to an already data-driven
registry, and the mechanical test/fixture updates that data row implies. The
cost is in breadth of mirror surfaces and in getting the blocking/non-blocking
boundary exactly right, not in code.

**Dependencies**: None. PR #1783 is explicitly out of scope per the brief and is
not modified, rebased, or re-reviewed by this work.

---

## Interpretation and Scope Boundary

One interpretation drives the whole plan and must be read before the rest.

The brief says "the strict implementation-plan review gate added in #1655
enforces a merged plan's literal enumerations". The strict plan machinery from
#1655 cannot block: `docs/workflow/development-workflow/strict-plan-checks.md`
states "Findings produced by these checks are **non-blocking**. They never
change a review's verdict.", and Protocol 93 repeats that `STRICT_PLAN_*` keys
"never change the ordinary verdict". The surface that actually blocked the
reduced revision is the **code review gate**: `REVIEW.md` → `Code Review
Checklist` → `Pass 1: Spec Compliance`, whose first bullet requires
"no missing or extra behaviours", with the matching blocking entry
"Implementation diverges from the approved spec or plan in a way that changes
observable behaviour".

Therefore:

- **AC-1's blocking threshold is changed in `REVIEW.md` Pass 1**, which is where
  blocking happens.
- **The #1655 strict plan review mode is aligned in the same change** (brief
  scope item 3) by adding the advisory proportionality row to its checklist, and
  by making its authoring counterpart in Protocol 02 agree.

Two further boundaries, stated so this change cannot be read as a general
relaxation:

- **Production-code correctness review is untouched.** The relaxed threshold
  applies only to deltas in *test scaffolding* (fixture manifests, proof-cycle
  lists, case tables, scenario enumerations). Any delta that changes observable
  behavior or drops acceptance-criterion coverage stays blocking under the
  existing rule, with no Coverage-Harm Statement required beyond naming the
  affected criterion or behavior.
- **Rules that match third-party reviewer output are untouched.** The governing
  distinction: be literal about what a third party emits; be substantive about
  what your own team delivers. Nothing in this change weakens verdict-string,
  approval-text, or platform-status matching. (This is the inverse failure the
  exact-match fix for #1491 / PR #1492 was built to prevent.)

---

## Verification Log

All commands run from the repository root at plan-write time.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `28ad4dfb` (branch `implementation-plan/1785-plan-gate-proportionality`, based on `develop`) |
| Blocking bullet exists in Pass 1 | `grep -n "no missing or extra behaviours" REVIEW.md` | one hit, `REVIEW.md:217`, inside `### Pass 1: Spec Compliance` |
| Strict findings are non-blocking | `grep -n "non-blocking" docs/workflow/development-workflow/strict-plan-checks.md` | one hit; confirms the strict mode cannot be the blocking surface |
| Strict plan checklist size | `grep -c '^### ' docs/workflow/development-workflow/strict-plan-checks.md` | `7` identifiers today |
| Registry is data-driven (no hard-coded count in code) | `grep -n "extract_strict_checklist_known_checks" -A 30 scripts/development-workflow/local-ai-reviewer.sh` | identifiers are read from the document; the only structural constraints are one `### <identifier>` heading per check and exactly one `Source:` line per section |
| Hard-coded identifier expectations to update | `grep -rn "source_declaration" scripts/development-workflow/tests/ docs/workflow/development-workflow/integrations/ docs/testing/workflow/` | hits in `test-local-ai-reviewer.sh` (applied-set strings, shipped-id/source arrays, planted-pair array), `run-strict-plan-smoke-fixtures.sh` (`positives`), the four `fixtures/strict-plan-checks/*.md` checklist fixtures, `integrations/local-ai-reviewer.md`, and `docs/testing/workflow/1655-strict-plan-review-mode.smoke-test.md`. One hit in `test-pr-review-loop.sh` is a synthetic forwarding string, not derived from any checklist |
| Doctrine catalogue headroom | `grep -c '^### ' docs/workflow/development-workflow/review-doctrine.md; wc -c docs/workflow/development-workflow/review-doctrine.md` | `5` patterns, `3417` bytes against the `12000`-byte bound |
| Doctrine count asserted in tests | `grep -rn "REVIEW_DOCTRINE_PATTERN_COUNT=5" scripts/` | one assertion in `test-local-ai-reviewer.sh`, fed by the **shipped** catalogue |
| Mirror surfaces (live search, cross-cutting rule) | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/ .cursor/ .codex/ .agents/` | `.claude/agents/{developer,tech-lead}.md`, `.cursor/agents/{developer,tech-lead}.md`, `.codex/skills/workflow-{implementer,plan-writer}/SKILL.md`, `.cursor/commands/{generate-implementation-plan,implement-development}.md`, `.cursor/rules/workflow.mdc` |
| Reviewer-side mirrors | `grep -rln "REVIEW.md" .claude/ .cursor/ .codex/ .agents/` | adds `.claude/agents/code-reviewer.md`, `.cursor/agents/code-reviewer.md`, `.codex/skills/workflow-code-reviewer/SKILL.md`; the `.cursor/commands/review-*.md` files and the review wrapper protocols are pointers that restate no rule text |
| `.agents/skills` duplication risk | `readlink .agents/skills/workflow-plan-writer .agents/skills/workflow-implementer .agents/skills/workflow-code-reviewer` | all three are symlinks into `.codex/skills/`; editing the Codex skill covers the `.agents` surface, and a separate edit there is not possible |
| Shell-snippet lint scope | `sed -n '13p' scripts/lint/workflow-shell-snippet-lint.py` (`ROOTS`) | covers `docs/workflow/`, `docs/best-practices/`, the agent/skill trees and `scripts/development-workflow/`; `docs/testing/` and `docs/specs/` are out of scope |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner / repository mode | This repository owns the plan (`single_repo` default) | `.ai-dev-workflow.yaml` has no `mode`, `workflow_hub`, or `product_repo` key | 2026-09-23, repo `28ad4dfb` | Current invocation only | `Verified` |
| Approved base branch | `develop` for both the plan PR and the later implementation PR | Parent handoff policy `--base develop`; branch `implementation-plan/1785-plan-gate-proportionality` is cut from `develop` | 2026-09-23, repo `28ad4dfb` | Current invocation only | `Verified` |
| Shipped strict-plan checklist contents (the registry this plan adds a row to) | Seven identifiers, listed in `strict-plan-checks.md`, mirrored by hard-coded expectations in the reviewer tests and the integration doc | `docs/workflow/development-workflow/strict-plan-checks.md` plus the Verification Log discovery grep | 2026-09-23, repo `28ad4dfb` | Same-surface open PR check: the only open PR is #1783; `gh pr diff 1783 --name-only` filtered for `REVIEW.md`, `strict-plan-checks`, protocols 02/03, `local-ai-reviewer`, and the tech-lead/developer/code-reviewer mirrors returns no match across its 195 files | `Verified` |

No conflict found. The bounded scope is the current invocation plus same-surface
open PRs; no repository-wide PR scan was performed. Shared subject matter with
#1783 (it is the motivating evidence) is not treated as conflict evidence
because it changes none of these files.

At implementation start, re-verify the third row (checklist contents and the
discovery grep) and record `Still valid` or return `Stale or conflicting`
evidence to the parent before editing files.

---

## Classification

| Classifier | Applies | Rationale |
| --- | --- | --- |
| Cross-cutting checklist | **Yes** | The change adds a review category (test-scope proportionality) that applies across independent feature implementations and modifies `REVIEW.md`, Protocol 02, and Protocol 03. Full file enumeration is in **Layer-by-Layer Changes** below, built from the live search recorded in the Verification Log. |
| Complex workflow decision-gate | **Yes** | The blocking threshold now depends on several inputs. See **Decision-Gate Matrices**. |
| Parser-risk | **No** | No parser, scanner, lint rule, or regex engine is added or modified. The strict registry already reads identifiers from the document; this change adds a data row. The parser-adjacent *constraint* it imposes is recorded in **Risks & Mitigations** and enforced by an implementation-order verification step. |
| Concurrent-event-source | **No** | No listeners, timers, async queues, or shared mutable state are introduced or modified. |
| Executable workflow shell snippets | **No new snippets planned** | The canonical document is prose plus a record format. If implementation nevertheless adds an executable fence under `docs/workflow/**` or `docs/best-practices/**`, it must carry an adjacent `<!-- workflow-shell-contract: bash-zsh -->` marker and pass `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`. |

---

## Design Decisions

Each decision keeps its index everywhere it is referenced in this document.

**Decision 1 — One canonical document, pointers everywhere else.**
Create `docs/workflow/development-workflow/test-scope-proportionality.md` to
hold the definitions, the Test-Scope Deviation Record format, the Coverage-Harm
Statement rule, the advisory heuristic, and the worked example. Every other
surface gets a short rule statement plus a link. Rejected alternative: writing
the full rule into `REVIEW.md`, Protocol 02, and Protocol 03 separately — three
independent copies of a nuanced rule drift apart, and a contract with more than
one source of truth is the harder failure to detect later.

**Decision 2 — Canonical names, fixed for all surfaces.**

| Concept | Canonical name / literal |
| --- | --- |
| Canonical document | `docs/workflow/development-workflow/test-scope-proportionality.md` |
| Reviewer obligation before blocking | **Coverage-Harm Statement** |
| Implementer's PR block | `## Test-Scope Deviation Record` |
| Marker that makes an enumeration binding | the exact literal `**Binding enumeration**` |
| Strict-plan check identifier | `test_scope_proportionality` |
| Review-doctrine pattern heading | `### Enumeration treated as contract` |

**Decision 3 — Indicative by default, binding only when marked.**
An enumeration in a merged plan is *indicative* unless the plan marks it with
the exact literal `**Binding enumeration**` on, or immediately above, the line
that introduces it. Unmarked enumerations express coverage intent and may be
satisfied by a different, coverage-equivalent set. The default is deliberately
permissive because over-binding is the defect being fixed; the fail-closed
direction is preserved by routing behavior and acceptance-criterion deltas back
to the unchanged Pass 1 rule (matrix row A1). An exact literal is used rather
than a loose grammar so that a plan cannot become binding by accidental
phrasing.

**Decision 4 — The advisory signal is a new row in the existing strict-plan
registry, not new machinery.**
Add `test_scope_proportionality` to `strict-plan-checks.md` with
`Source: not required`. Advisory-not-blocking is then guaranteed by that
document's existing contract rather than by a new flag, and no reviewer code
changes. `Source: not required` is chosen because proportionality is judged from
the plan alone and must also apply to Refactor plans, which have no spec.
Rejected alternative: a bespoke heuristic script — it would need thresholds,
configuration, and a planted-violation proof for a signal that is advisory by
design.

**Decision 5 — No new Document Quality Gate row.**
The gate's row list is mirrored across `REVIEW.md`, the spec- and
plan-generation protocols, Protocols 91 and 93, the product-manager and
tech-lead agent files for two tools, the Codex plan-writer skill, and existing
smoke runbooks — the full set is whatever
`grep -rln "Document Quality Gate"` returns. Adding a row there to carry an
advisory signal that the plan-review checklist and the strict registry already
carry would multiply surfaces for no added detection. This plan applies to
itself the proportionality judgment it asks reviewers to make.

**Decision 6 — Add one review-doctrine pattern.**
`### Enumeration treated as contract` is the generic shape of this failure and
the doctrine is already supplied to the internal reviewer at review time. The
catalogue has ample headroom against its byte bound (Verification Log). The
entry must be incident-free — no PR number, no issue number, no path from the
incident — per the catalogue's own rules and `review-doctrine-lint.sh`.

---

## Decision-Gate Matrices

### Gate A — Reviewer evaluating a delta between the plan's projected test scope and the delivered test scope

Inputs: whether the delivered scope **removes** anything the plan projected;
what the delta touches; how the plan marked the enumeration; whether a
Test-Scope Deviation Record is present and complete; whether the reviewer can
state both halves of a Coverage-Harm Statement.

**Rows are evaluated in order; the first matching row wins.** Row A0 is this
gate's entry condition and is evaluated before every other row: a delta that
removes nothing never reaches A1-A6, so a change that only adds tests is never
`important` or `blocking` under this gate. Rows A1-A6 apply to removals only.

**Item count is never a gate input.** Gate A keys on whether anything was
removed, not on whether the delivered scope is smaller or larger than the
projection. A removal that nets even or larger — a swap, a consolidation, a
rewrite — is still a removal and is treated exactly as the equivalent shrinking
delta; a raised total is never a defense against a coverage loss.

| # | Delta touches | Plan marking | Deviation record | Harm statement available | Outcome | Required next action |
| --- | --- | --- | --- | --- | --- | --- |
| A0 | **Nothing is removed** — the delivered scope only adds to, or leaves intact, every item the plan projected, whatever the totals | Any | Not required | Not applicable | No finding; **Gate A does not apply** | Ordinary Pass 2 quality review still applies |
| A1 | Observable behavior, or coverage of an acceptance criterion | Any | Any | Not required | `blocking` | Unchanged Pass 1 rule; name the criterion or behavior affected |
| A2 | Test scaffolding only | Indicative (unmarked) | Present and complete | Yes — reviewer names the lost coverage **and** the defect class | `blocking` | Reviewer states both halves; implementer restores that coverage or narrows the deviation |
| A3 | Test scaffolding only | Indicative | Present and complete | No | Not blocking; `suggestion` at most | Accept the recorded rationale; do not restate the count as a requirement |
| A4 | Test scaffolding only | Indicative | Missing or incomplete | Any | `important` | Request the record before `ready-for-human-review`; do not block on the delta alone |
| A5 | Test scaffolding only | `**Binding enumeration**` | Present | Not required | `blocking` | Restore the listed items, or obtain a human decision to amend the plan |
| A6 | Test scaffolding only | `**Binding enumeration**` | Missing | Not required | `blocking` | Same as A5 |
| A8 | Test scaffolding only, but the marking is malformed — marker text present in a form other than the exact literal, or attached to an unclear span | Treated as indicative | Any | Any | `important` on the plan wording; delta itself follows A2/A3/A4 | Ask for the plan marker to be corrected; missing or malformed marking never upgrades the delta to blocking |

### Gate B — Plan reviewer applying the advisory test-scope sanity signal

Outcome is `suggestion` in every firing row. This gate never blocks readiness
and never changes a review verdict.

| # | Signal | Outcome | Required next action |
| --- | --- | --- | --- |
| B1 | Projected test scaffolding exceeds the size of the deliverable it protects | `suggestion` | Plan states why the scaffolding is proportionate, or reduces it |
| B2 | A prose-only or documentation-only deliverable proposes a custom parser, scanner, or matcher to validate it | `suggestion` | Plan justifies the parser, or replaces it with a simpler check |
| B3 | Neither signal present | No finding | None |
| B4 | Sizes cannot be estimated from the plan | No finding | Do not guess a ratio; optionally ask the plan to state expected test volume |

**Mirror surfaces for both gates**: `REVIEW.md` (`Core Rules` statement plus the
Plan Review and Pass 1 checklist entries), the canonical document from
Decision 1, the Test-Scope Deviation Record format in Protocol 03, the authoring
rule in Protocol 02, and the one-line summaries in the tech-lead, developer, and
code-reviewer agent and skill mirrors. All mirrors must state the same outcomes;
only the canonical document carries the full text.

---

## Layer-by-Layer Changes

This plan is classified cross-cutting-checklist, so the enumeration below is the
complete set of files to modify, built from the live search in the Verification
Log. Nothing is delegated to implementation-time discovery.

### Review contract and canonical rule

- [ ] **New** `docs/workflow/development-workflow/test-scope-proportionality.md`
      — the canonical document (Decision 1). Contents: scope of the rule
      (test scaffolding only) and the two explicit non-weakening clauses from
      **Interpretation and Scope Boundary**; indicative-vs-binding default
      (Decision 3) with the exact marker literal; the Test-Scope Deviation
      Record field list; the Coverage-Harm Statement rule with both required
      halves; the advisory heuristic (Gate B) with its trigger marked
      indicative and its rationale; a named list of blocking rules this change
      does **not** relax — planted-violation proof, E2E fixture contract,
      filter-schema canary, scope-residual evidence, and acceptance-criterion
      coverage — each of which specifies a *kind* of coverage rather than a row
      count; and the worked example below.
- [ ] **Worked example inside that document** (AC-5): the PR #1783 scenario.
      Record it as history, not as scope: a plan specified a large literal
      fixture manifest and a proof-cycle list for a documentation deliverable;
      a revision shipped a curated subset with equivalent coverage and was
      rejected as a unilateral scope reduction. Show both outcomes under the
      revised gate — matrix row A3 when the reviewer can only cite the plan's
      number (not blocking, record accepted), and matrix row A2 when the
      reviewer can name a behavior the removed rows uniquely exercised and the
      defect class it lets through (blocking, with both halves stated). Label
      the historical figures explicitly as a record of what happened, not as a
      requirement.
- [ ] `REVIEW.md` — add a compact `### Test-scope proportionality` subsection
      under `Core Rules` stating the default, the Coverage-Harm Statement
      requirement, the two non-weakening clauses, and a link to the canonical
      document.
- [ ] `REVIEW.md` — `Code Review Checklist` → `Pass 1: Spec Compliance`: amend
      the bullet beginning "Implementation matches the approved spec and plan"
      so that a delta confined to test scaffolding is evaluated under Gate A
      rather than under "no missing or extra behaviours", and amend the blocking
      entry "Implementation diverges from the approved spec or plan in a way
      that changes observable behaviour" so it names the Coverage-Harm Statement
      requirement for test-scope deltas. Behavior and acceptance-criterion
      deltas keep their current force (row A1).
- [ ] `REVIEW.md` — `Plan Review Checklist`: add one bullet for the advisory
      Gate B signal (explicitly `suggestion`, never blocking) and one bullet
      requiring that any enumeration the plan intends as binding carries the
      exact marker.

### Planning and implementation protocols

- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      — in Step 3 **Quality guardrails**, add the authoring rule: express test
      **coverage intent** (classes of behavior and input that must be
      exercised); when a count is given, say why that number is enough and mark
      it binding or indicative; a literal manifest binds only when marked with
      the exact literal. Add an explicit note that this rule and the existing
      **Pattern completeness checks** / **Explicit freeze exception** bullets
      govern *different axes* — those two bound what the plan must cover
      (source to plan), this one bounds how literally the plan's own enumeration
      binds the implementer (plan to implementation) — so the surfaces are not
      in conflict.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      — add a short Step 3 self-check directing the author to apply Gate B to
      their own plan before committing. Per Decision 5, do **not** add a row to
      the Document Quality Gate list.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      — add a shared `## Test-Scope Deviation Record` section (alongside the
      existing `## Scope-Residual Evidence Gate`) defining when the record is
      required, its fields, and the link to the canonical document. Fields:
      which plan enumeration was reduced and where it appears in the plan; what
      was delivered instead; the coverage classes retained and which tests
      exercise them; the coverage argument; and residual risk accepted, or
      "none identified".
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      — in Path 1 and Path 2 PR-description templates, extend the existing
      bullet "Any deviations from the plan (with justification)" to require the
      Test-Scope Deviation Record format when the deviation reduces planned test
      scaffolding. Paths 3 and 4 are not plan-backed and are left unchanged.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      — in the `## Pre-Submission Self-Review Pass` coverage check, add: when
      the delivered test scope differs from what the plan projected, write the
      record before opening the PR.

### Strict plan review mode (advisory signal)

- [ ] `docs/workflow/development-workflow/strict-plan-checks.md` — add one
      section `### test_scope_proportionality` with `Source: not required`,
      following the exact shape of its siblings: the level-3 heading is the
      identifier, exactly one `Source:` line, one `**Question:**` paragraph and
      one `**Finding shape:**` paragraph. The question asks whether the plan
      states what coverage each group of projected test scaffolding provides,
      marks any enumeration it intends as binding, and keeps projected volume
      proportionate to the deliverable. **Constraint**: do not add any other
      level-3 heading or any additional `Source:` line to this file — both would
      make the registry extraction refuse the document.
- [ ] `docs/workflow/development-workflow/integrations/local-ai-reviewer.md` —
      update the strict-plan section so its stated identifier count and its
      no-spec applied-set list ("the applied set is exactly ...") match the
      document after the change. Derive both from the file rather than from this
      plan.
- [ ] `docs/testing/workflow/1655-strict-plan-review-mode.smoke-test.md` —
      update only the statements that enumerate the applied set or state an
      identifier count, so the runbook still describes what an operator will
      observe. Leave its scenario structure alone.

### Review doctrine

- [ ] `docs/workflow/development-workflow/review-doctrine.md` — add
      `### Enumeration treated as contract` with exactly one `**Shape**:`, one
      `**Example**:` and one `**Detect**:` paragraph. Shape: a delta from a
      previously agreed list is treated as a defect in itself, with no statement
      of what the missing entries were protecting. Detect: for each entry called
      missing, can you name the behavior it exercised and the failure that now
      goes unnoticed? The entry must contain no issue number, PR number, path,
      or wording that only makes sense to someone who saw the incident.

### Tests and fixtures

- [ ] `scripts/development-workflow/tests/fixtures/strict-plan-checks/well-formed.md`
      — add the new identifier section so the harness's checklist fixture admits
      it. The other checklist fixtures in that directory exist to exercise
      malformed shapes and must not be "completed".
- [ ] **New** `scripts/development-workflow/tests/fixtures/strict-plan-plans/test_scope_proportionality/`
      — a minimal fail-variant fixture plan (plus its sibling fixture spec, as
      the existing pairs have) that plainly exhibits the finding shape.
- [ ] **New** `scripts/development-workflow/tests/fixtures/strict-plan-plans-pass/test_scope_proportionality/`
      — the pass variant of the same fixture, differing only in the element that
      removes the violation, matching how the existing pass fixtures are built.
- [ ] `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — update
      every expectation that enumerates the applied identifier set or the
      shipped identifier/source arrays, and add the new identifier to the
      planted fail/pass pair array. Find them with the Verification Log
      discovery grep rather than by line number; re-derive each expected value
      from the edited checklist, and rename any test identifier whose name
      states a count so the name stays true. Note that the single hit in
      `test-pr-review-loop.sh` is a synthetic forwarding string and must stay as
      it is.
- [ ] `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — update
      the shipped review-doctrine pattern-count assertion to match the catalogue
      after Decision 6.
- [ ] `scripts/development-workflow/tests/run-strict-plan-smoke-fixtures.sh` —
      add the new identifier to the `positives` array so the manual model-level
      smoke helper exercises it.

### Agent and skill mirrors

Each mirror gets one sentence: the blocking threshold for test-scope deltas,
or the authoring default, or the record obligation — plus the canonical link.
No mirror restates the full rule.

- [ ] `.claude/agents/tech-lead.md` — authoring default (Decision 3) and Gate B
      self-check.
- [ ] `.cursor/agents/tech-lead.md` — same.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` — same.
- [ ] `.claude/agents/developer.md` — the Test-Scope Deviation Record
      obligation.
- [ ] `.cursor/agents/developer.md` — same.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` — same.
- [ ] `.claude/agents/code-reviewer.md` — the Coverage-Harm Statement
      requirement before blocking on a test-scope delta.
- [ ] `.cursor/agents/code-reviewer.md` — same.
- [ ] `.codex/skills/workflow-code-reviewer/SKILL.md` — same.

**Deliberately not modified, with reasons**: `.agents/skills/workflow-*` are
symlinks into `.codex/skills/` (Verification Log), so the Codex edits cover
them and a separate edit is impossible. `.cursor/commands/*.md`,
`.cursor/rules/workflow.mdc`, and the `0x-review-*-protocol.md` wrappers are
pointers that restate no rule text — the wrapper states "`REVIEW.md` is
authoritative. If this wrapper and `REVIEW.md` ever differ, follow `REVIEW.md`."

### Documentation index and best practices

- [ ] `docs/workflow/development-workflow/README.md` — register the canonical
      document in the supporting-document list near the `Review Contract`
      entries, with a one-line description.
- [ ] `docs/best-practices/3-testing.md` — add a short implementer-facing
      section pointing at the canonical document, matching how
      `Planted-Violation Proofs` and `E2E Fixture Contract` already pair a
      `REVIEW.md` rule with its implementer-facing version.
- [ ] `docs/workflow/development-workflow/templates/implementation-plan-template.md`
      — in the Testing Strategy block, prompt the author for coverage intent and
      for marking any enumeration binding, so new plans comply by default.
- [ ] `changelog.d/1785.changed.plan-gate-proportionality.md` — new fragment
      (the implementation branch is `refactor/*`, which is not exempt). Literal
      body for the implementer to adapt:

```markdown
- **Review gates weigh test-scope proportionality, not literal conformance** (#1785): a delta between a plan's projected test scaffolding and what an implementation ships is blocking only when the reviewer names the specific coverage the removed items provided and the defect class that now escapes. Implementers record reduced test scope in a Test-Scope Deviation Record that the gate evaluates, plan enumerations are indicative unless explicitly marked binding, and plan review gains an advisory, never-blocking signal when projected test scaffolding outweighs the deliverable it protects. Review of production-code correctness and of third-party reviewer output is unchanged.
```

---

## Testing Strategy

**Test types**: existing automated shell test suites, repository lint gates, and
a manual runbook. No new test harness is created.

This section states coverage intent rather than a fixture manifest. Every count
below is marked, per Decision 3.

### Coverage classes that must be exercised

1. **Registry admission** — the new identifier is extracted from the shipped
   checklist with its `Source:` metadata, and appears in the applied set for a
   plan-stage review. Covered by the existing shipped-identifier and
   shipped-source assertions in `test-local-ai-reviewer.sh` once they are
   re-derived.
2. **Applied-set arithmetic** — the applied set is correct both when a sibling
   spec is present and when it is absent, given that the new check is
   `Source: not required`. Covered by the existing applied-set assertions once
   re-derived.
3. **Finding carriage** — a strict finding naming the new identifier reaches the
   reviewer's structured output at a concrete path and line.
4. **Absence** — the pass variant of the same fixture produces no finding for
   the identifier.
5. **Unknown-identifier filtering still works** — an identifier absent from the
   checklist is still dropped and counted as unknown. Covered by the existing
   mixed-plan scenario; it must remain untouched and green.
6. **Document well-formedness gates** — the review-doctrine lint (well-formed
   entry, incident-free, within byte bound), `markdownlint-cli2` on changed
   markdown, and the markdown heuristic lint on plan/runbook/changelog paths.

**How many planted fixture pairs is enough, and why**: one pair — fail and pass
— for the one new identifier. This count is **indicative**, and the reasoning is
the point: classes 3 and 4 exercise a code path that is already proven for the
existing identifiers by identical pairs, so the new pair proves only the part
that is actually new (that *this* identifier is admitted and carried). A second
pair would re-execute the same path with different prose and add no detection.
If implementation finds that the new identifier travels a different code path
than the existing ones, add pairs until each distinct path is covered and say so
in the PR.

### Planted-violation proof

The new strict registry row is proved the same way the existing rows are: the
fail-variant fixture with a planted finding must surface the identifier at a
concrete fixture path and line, and the pass variant at the same location must
not. Record both runs in the PR evidence.

The prose changes to `REVIEW.md`, Protocol 02, and Protocol 03 are **not**
automated checks and have no planted-violation proof. They are reviewer and
author instructions; their verification is the reviewer-behavior walkthrough in
the smoke runbook and the worked example. State this rationale in the PR rather
than leaving the exemption implicit.

### Suites to run before readiness

- `bash scripts/development-workflow/tests/test-local-ai-reviewer.sh`
- `bash scripts/development-workflow/tests/test-pr-review-loop.sh` (guards the
  forwarding path that must not change)
- `bash scripts/lint/review-doctrine-lint.sh`
- `markdownlint-cli2` over the changed markdown, plus
  `python3 scripts/lint/markdown-heuristic-lint.py` over the plan, runbook, and
  changelog fragment
- `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
  — expected to report nothing, since no executable fence is planned on an
  in-scope surface
- `shellcheck --severity=warning` on any changed `*.sh`

**Residual verification strategy**: this change touches a set of mirrored
surfaces, so the residual evidence for readiness is the mirror-consistency
sweep — re-run the two Verification Log discovery greps
(`source_declaration` across tests/integration/runbook paths, and the
agent/skill live search) at implementation time, and show in the PR that every
hit is either updated or explicitly justified as unchanged. That output, not a
prose claim, is the evidence.

**Smoke test runbook**: `docs/testing/workflow/1785-plan-gate-proportionality.smoke-test.md`

**Regression suite**: the repository's E2E job is a placeholder, so no
end-to-end regression spec applies.

---

## Seed Data

None. This change introduces no application data. The fixture plans named in
**Layer-by-Layer Changes** are test inputs, not seed data, and are created by the
implementation steps that reference them.

---

## Documentation Updates

The documentation *is* the deliverable here, so every doc edit is listed in
**Layer-by-Layer Changes** and is part of implementation rather than a follow-up.
Beyond that list:

- [ ] `docs/project/*` — None. This change adds no domain entity, repository
      structure change, architecture decision, or data model change.
- [ ] `AGENTS.md` / `CLAUDE.md` — None required. The Key Documentation table
      indexes top-level contracts (`REVIEW.md`, protocols, the workflow README);
      the new document is a supporting workflow doc reached from `REVIEW.md` and
      the workflow README, in the same way `strict-plan-checks.md` and
      `design-assets.md` are. Add an entry only if review asks for it.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The rule is read as a general licence to ship less testing | Med | High | The canonical document scopes the rule to test scaffolding, names the blocking rules it does not relax, and routes behavior and acceptance-criterion deltas back to the unchanged Pass 1 rule (row A1) |
| A reviewer uses "no harm statement available" to wave through a real coverage gap | Med | High | Row A3 fires only when the record is present and complete and the reviewer still cannot name either half of a Coverage-Harm Statement; a reviewer who can name the harm states it and the delta becomes A2 instead. The unchanged rules — planted-violation proof, E2E fixture contract, filter-schema canary, scope-residual evidence, and acceptance-criterion coverage (row A1) — continue to require their specific coverage kinds regardless of counts, a missing record is `important` rather than silently accepted (A4), and binding enumerations stay blocking regardless (A5/A6) |
| Someone applies the new permissiveness to matching third-party reviewer output | Low | High | Explicit non-weakening clause in both `REVIEW.md` and the canonical document, stated as: be literal about what a third party emits; be substantive about what your own team delivers |
| Editing `strict-plan-checks.md` breaks registry extraction (an extra level-3 heading or a second `Source:` line makes extraction refuse the file) | Med | High | Explicit constraint in the layer list, plus a dedicated extraction verification step in the Implementation Order before any test is touched |
| Stale identifier counts left behind in the integration doc, the #1655 runbook, or test expectations | High | Med | The discovery grep is recorded in the Verification Log and re-run as the residual-evidence sweep before readiness |
| The advisory Gate B trigger hardens into a de-facto binding threshold | Med | Med | The trigger is marked indicative in the canonical document and its outcome is `suggestion` in every firing row |
| Mirror sentences drift from the canonical text over time | Med | Med | Decision 1 keeps exactly one normative copy; mirrors carry one sentence plus a link |

---

## Implementation Order

1. Re-verify the third row of the **Cross-Cutting Operational Assumption Check**
   (shipped checklist contents and the discovery grep) and record `Still valid`
   in the pre-submission evidence, or stop and return the evidence to the parent.
2. Write `docs/workflow/development-workflow/test-scope-proportionality.md` —
   the canonical rule, the record format, the Coverage-Harm Statement, Gate A
   and Gate B outcomes, the non-weakening clauses, and the worked example. Every
   later step points at this file, so it comes first.
3. Update `REVIEW.md`: the `Core Rules` subsection, the two Pass 1 entries, and
   the two Plan Review Checklist bullets.
4. Update Protocol 02 (authoring default, two-axes note, Gate B self-check) and
   Protocol 03 (shared record section, the two PR-template bullets, the
   pre-submission coverage check).
5. Add the `### test_scope_proportionality` section to `strict-plan-checks.md`.
   Immediately verify extraction still succeeds before touching any test —
   source the reviewer in harness mode and run the checklist extractors against
   the edited file, confirming the new identifier appears with its `Source:`
   value and that the section extractor does not refuse the document. If it
   refuses, fix the heading or `Source:` shape before continuing.
6. Update `integrations/local-ai-reviewer.md` and the #1655 smoke runbook so
   their stated counts and applied-set lists match the edited checklist. Derive
   the values from the file.
7. Add the review-doctrine pattern and run `scripts/lint/review-doctrine-lint.sh`
   until it passes.
8. Add the new identifier section to the `well-formed.md` checklist fixture, add
   the fail and pass fixture plan pair, extend the planted-pair array and the
   smoke helper's `positives` array, and re-derive every applied-set, shipped-id,
   shipped-source, and doctrine-count expectation found by the discovery grep.
   Run `test-local-ai-reviewer.sh` and `test-pr-review-loop.sh` until green.
9. Update the agent and skill mirrors (three tech-lead surfaces, three developer
   surfaces, three code-reviewer surfaces), keeping each to one sentence plus the
   canonical link.
10. Update `README.md`'s supporting-document list, `docs/best-practices/3-testing.md`,
    and the implementation-plan template.
11. Add the changelog fragment
    `changelog.d/1785.changed.plan-gate-proportionality.md` using the literal in
    **Layer-by-Layer Changes**, adapted if scope changed during implementation.
    This precedes the runbook walk because the runbook's consistency sweep lints
    the fragment.
12. Walk the smoke test runbook and record the observed results.
13. Run the full lint and test list from **Testing Strategy**, then the residual
    mirror-consistency sweep, and put both outputs in the PR evidence.

---

## Acceptance Criteria Mapping

| Brief acceptance criterion | Where it is satisfied | How it is verified |
| --- | --- | --- |
| Strict plan review mode blocks an enumeration delta only when the reviewer names the specific coverage lost and the defect class it lets through | `REVIEW.md` Pass 1 entries and `Core Rules` subsection, backed by the canonical document; Gate A rows A2/A3. See **Interpretation and Scope Boundary** for why the blocking surface is Pass 1 rather than the non-blocking strict mode | Smoke runbook walkthroughs for the equivalent-reduction and coverage-losing cases |
| A recorded-deviation format exists for reduced test scope, and the gate documents how it is evaluated | `## Test-Scope Deviation Record` in Protocol 03 (format) plus Gate A in `REVIEW.md` and the canonical document (evaluation) | Smoke runbook steps covering a complete record and a missing record |
| Protocol 02 plan-authoring guidance states that enumerations are binding only when explicitly marked, and otherwise express coverage intent | Protocol 02 Step 3 quality guardrails (Decision 3), mirrored in the plan template and the three tech-lead surfaces | Smoke runbook step reading the guardrail and the marker literal; mirror-consistency sweep |
| Plan review surfaces an advisory flag when projected test scaffolding greatly exceeds the deliverable | `### test_scope_proportionality` in `strict-plan-checks.md` (non-blocking by that document's contract) plus the `REVIEW.md` Plan Review Checklist bullet; Gate B | Planted fail/pass fixture pair in the reviewer test suite; optional model-level run of the strict smoke helper |
| The PR #1783 scenario is captured as a worked example: the reduced revision passes the revised gate, or the gate names the concrete coverage it lost | Worked example in the canonical document, showing both the A3 and A2 outcomes | Smoke runbook step reading the worked example against the Gate A matrix |

Out-of-scope items from the brief are honored: PR #1783 itself is not touched,
no external reviewer platform configuration changes, and no gate on
production-code correctness is relaxed.
