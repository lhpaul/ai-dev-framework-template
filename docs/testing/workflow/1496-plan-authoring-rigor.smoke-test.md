# Plan-Authoring Rigor Smoke Test

**Feature**: Plan-authoring rigor for factual claims in implementation plans
**Spec**:
[1_1496-plan-authoring-rigor_specs.md](../../specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md)
**Plan**:
[2_1496-plan-authoring-rigor_implementation-plan.md](../../specs/developments/20260911230253_1496-plan-authoring-rigor/2_1496-plan-authoring-rigor_implementation-plan.md)

## Purpose

Verify that plan authors receive portable authoring obligations, plan reviewers
receive the matching backstop check, and plan pull requests carry a current
per-rule outcome record without introducing automated rule enforcement.

## Preconditions

- Scenarios execute during implementation QA on the feature branch for #1496, before merge into `develop`.
- A test tracker issue exists with an approved spec suitable for a short plan
  exercise (or reuse a docs-only refactor brief).
- Markdown lint passes on changed workflow documents.

## Scenario 1: Canonical rules surface

1. Open `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`.
2. Confirm it states all six rules with trigger, required evidence, and pass
   condition using the spec's outcome labels (`Satisfied`, `Not applicable`,
   `Unsatisfied`).
3. Grep mirror surfaces listed in the implementation plan's mirror table.

Expected result: no mirror surface adds a seventh rule or weakens a pass
condition relative to the canonical file.

## Scenario 2: Authoring guidance routing

1. Inspect Protocol 02 Step 3 quality guardrails and Document Quality Gate.
2. Inspect `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and
   `.codex/skills/workflow-plan-writer/SKILL.md`.

Expected result: each routes plan authors to the canonical rules doc and requires
evidence in the plan document (not pull request comments).

## Test setup for Scenarios 3–7 (temporary integration branch)

Scenarios 3–7 need a draft plan PR that contains the **unmerged** Protocol 02
and `REVIEW.md` changes under test. Protocol 02 normally branches plans from
`develop`, which lacks those changes, so this runbook uses the workflow's
supported temporary **integration branch** (`develop-<slug>`), which Protocol 02
and the CI base filters (`develop`, `develop-**`, `main`) already accept:

1. Create and push `develop-smoke-1496` at the implementation PR branch's head,
   so it carries the unmerged changes.
2. Run Protocol 02 for a scratch **Refactor work item with no spec** (mandatory
   — this is the only exercise of the no-spec path, spec line 468) with
   `develop-smoke-1496` as the approved integration base (the run's
   `--base develop-smoke-1496`, as `/run-item` passes it to Protocol 02's
   artifact-base resolution); optionally repeat for a scratch item that has a spec.
   Protocol 02 itself checks out that base at its remote head and creates its
   own `implementation-plan/*` branch and draft PR targeting it — do not create
   a branch by hand. Author the scratch plan by hand while following
   Protocol 02: a short plan (one page) for a hypothetical refactor of a single
   small script, written to Protocol 02's template, with its per-rule outcome
   record. No fixture file or Protocol 02 input step is involved. Scenario 4
   then deliberately edits that plan (see there).
3. Run Scenarios 3–7 against that PR.
4. Cleanup (required, recorded in the implementation PR): close the scratch PR
   unmerged, delete the `implementation-plan/*` branch Protocol 02 created and
   `develop-smoke-1496`, locally and on the remote, and confirm the
   implementation PR's diff is unchanged.

## Scenario 3: Per-rule outcome record on a plan PR

1. Run Protocol 02 for the test issue and open a draft plan PR.
2. Inspect the PR description `Document Quality Gate` section.

Expected result: a `Plan authoring rigor — per-rule outcome record` block lists
all six rules, the plan revision SHA, a rationale beside each `Not applicable`
outcome, and obeys the stale-revision rules from Group H of the spec.

## Scenario 4: Reviewer backstop

1. Apply `REVIEW.md` Plan Review Checklist to the draft plan PR from Scenario 3.
2. Deliberately omit evidence for one firing rule in the plan while recording
   `Satisfied` in the outcome record. Commit and push that mutation, then
   refresh the outcome record's plan revision to the new PR head **keeping the
   intentionally incorrect `Satisfied` label**, so the stale-revision gate does
   not confound the finding.
3. After the finding is observed, restore the omitted evidence, push, and
   refresh the record's revision and label to the new head, so Scenario 7 can
   continue the same PR.

Expected result: the backstop checklist yields a blocking finding naming the
rule and the defect; the finding class matches the spec gate matrix row for that
situation.

## Scenario 5: Verification Log and template

1. Open `docs/workflow/development-workflow/templates/implementation-plan-template.md`.
2. Confirm the template directs authors to record Rule 3/4/5 repository-derived
   evidence in the Verification Log (or linked plan sections) rather than in PR
   comments.

Expected result: the template change is guidance-only; existing merged plans are
not retrofitted.

## Scenario 6: Mirror consistency test harness

1. Run `bash scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`.

Expected result: exit `0`; the harness fails if rule names, outcome labels, or
required mirror paths drift.

## Scenario 7: Existing gates remain authoritative

1. Continue the plan PR through Step 7a, automated review, CI, and readiness
   labels per Protocol 91.

Expected result: the per-rule record supplements — does not replace — internal
review, `REVIEW.md`, strict plan checks, and CI.

## Acceptance traceability matrix

Manual desk-check (or scripted where noted). Each row
names an acceptance theme, the exercise, and the expected gate class.

| ID | Spec focus | Exercise | Expected result |
| --- | --- | --- | --- |
| B1 | Rule 1 — no record | Plan depending on vendor text with zero sampling/contract/enumeration | Blocking — missing sampling record |
| B2 | Rule 1 — two occurrences | Sampling record with two locators only | Blocking — floor not met |
| B3 | Rule 1 — contract fixed set | Design binds to literals with cited producer contract | Check passed — no sampling required |
| B4 | Rule 1 — tolerant open set | No contract; plan states stable part + unseen behavior | Check passed when record complete |
| C1 | Rule 2 — disagreeing duplicate | Same count stated differently in two sections | Blocking — contradiction |
| C2 | Rule 2 — agreeing duplicate | Same fact twice, identical wording | Non-blocking consolidation; Satisfied |
| C3 | Rule 2 — size is not a criterion | Very long plan, no other defect | No finding — size never fails a rule |
| C4 | Rule 2 — correction round | Correction adds a second statement instead of editing the first | Blocking — fact asserted twice |
| D1 | Rule 3 — bad partition | Count by subtracting unrelated totals | Blocking — partition not shown |
| D2 | Rule 3 — scope by count | Step uses number without enumeration | Blocking — missing enumeration |
| D3 | Rule 3 — non-homogeneous population | Correct arithmetic over a population whose members do not share the reasoned-about property | Blocking — population not homogeneous |
| E1 | Rule 4 — delegated support | "Test exists" from investigation summary only | Blocking — no recorded search |
| E2 | Rule 4 — narrow non-existence | "Helper absent" after searching one directory | Blocking — implausible scope |
| F1 | Rule 5 — unit-only expectation | Delete shared guard; expect new return at unit | Blocking — missing consumer site |
| F2 | Rule 5 — branch removal | Remove branch without reroute statement | Blocking — absorbed inputs |
| G1 | Rule 6 — scopeless conditional | "Required then" with no governed edges | Blocking — missing scope/discharge |
| G2 | Rule 6 — scope by stand-in word | Conditional scoped only by a word such as "those" or "all relevant" | Blocking — scope not named |
| G3 | Rule 6 — unbounded explanation | Statement explains why an obligation cannot always be met without naming governed occurrences | Blocking — governed occurrences not named |
| G4 | Rule 6 — role of review | A surface describes plan review as where this defect is expected to be found | Blocking — surface must call review a backstop |
| H1 | Missing outcome record | Plan PR with no per-rule table | Blocking — treated Unsatisfied |
| H2 | Stale record SHA | Record names earlier commit than PR head | Blocking — revision mismatch |
| H3 | Wrong N/A rationale | Rule 3 recorded `Not applicable` while the plan states artifact counts | Blocking — rationale contradicts claim |
| B5 | Rule 1 — short-retention source | Sampling locator only to a deletable log | Blocking — durable copy or retained artifact required |
| B6 | Rule 1 — restricted occurrence | Sampling occurrence contains secrets/PII with raw text pasted | Blocking — must use redacted shape record |
| B7 | Rule 1 — restricted and short-retention | Source is both deletable and access-restricted | Blocking unless both handling requirements are met |
| B8 | Rule 1 — heterogeneous sample adequacy | Population documented as having two producer variants; sample drawn from one; record silent on the other | Blocking — known heterogeneity unaddressed |
| B11 | Rule 1 — unpersuasive adequacy rationale | Same population, record states an adequacy rationale that is complete in form but weak | Non-blocking — recorded as a suggestion; Satisfied |
| B12 | Rule 1 — fixed literal set, no contract | Design binds to a fixed set of literals; large sample; no contract fixing the set | Blocking — contract required |
| B13 | Rule 1 — incomplete sampling record | Otherwise-complete record with exactly one required field omitted (producer; population and window; occurrences examined; distinct variants; saturation status; a per-occurrence locator) — run once per omitted field | Blocking — names the missing field |
| B9 | Rule 1 — curated examples | Occurrences are hand-picked examples | Blocking — not a sample of the population |
| B10 | Rule 1 — closed-population enumeration | Enumeration command shown with no closure provenance (nothing shows the set cannot grow), or members not listed | Blocking — enumeration record incomplete |
| E3 | Rule 4 — completeness claim | "All X verified" with no search scope | Blocking — completeness unsupported |
| F3 | Rule 5 — search scope | Consumer enumeration omits searched scope | Blocking — scope not recorded |
| F5 | Rule 5 — hand-recalled consumer list | Consumer list from memory with no recorded search | Blocking — search record missing |
| F6 | Rule 5 — expected behavior at the changed unit only | Expectation names only the changed unit, no observation point in the enumeration | Blocking — observation point missing |
| F4 | Rule 5 — untouched consumer | Untouched consumer omitted, or listed without its post-change outcome | Blocking — consumer or outcome missing |
| H4 | Outcome record — malformed | Record names a nonexistent commit | Blocking — revision does not resolve |
| H5 | Outcome record — label reassessed | Round re-reads recorded finding, label not reassessed | Blocking — label stale |
| H6 | Complete evidence, recorded Unsatisfied | Every rule's evidence is complete but the record says `Unsatisfied` | Blocking — outcome contradicts evidence |
| H7 | Absent trigger recorded Satisfied | Rule's trigger absent, record says `Satisfied` | Blocking — must be `Not applicable` with rationale |
| H8 | Invalid outcome label | Record uses a label outside the three defined | Blocking — invalid label |
| H9 | External-source finding not persisted | Rule 1 outcome cites an inspection with no persisted finding | Blocking — persisted finding missing |
| H10 | Incomplete evidence record | Rule 3/4/5 evidence record missing its revision, command, or result | Blocking — record incomplete |
| H11 | Non-reproducing or population-changed evidence | Recorded command does not reproduce at its recorded revision, or later plan text changes the population the evidence describes | Blocking — evidence does not support the claim |
| H12 | Repository-only drift | Repository changed after gathering but no claim the plan makes is affected | Non-outcome — no finding; record unchanged |
| H13 | Evidence only in PR comments | Firing rule's evidence exists only in a PR comment or chat transcript | Blocking — evidence must be moved into the plan document |
| H17 | Evidence only in the PR description | Firing rule's evidence exists only in the PR description, not in the plan document | Blocking — evidence must be moved into the plan document |
| H18 | Occurrence locator re-inspected every round | Round 1 inspects a sampling locator; before round 2 the locator's target changes or disappears; round 2 reuses a stored finding for it | Blocking — locators have no persisted-finding path and must be inspected directly each round |
| H14 | Not applicable, no rationale | Rule recorded `Not applicable` with an empty rationale | Blocking — treated as Unsatisfied |
| H15 | Single rule with no recorded outcome | Table present but one rule has no row | Blocking — that rule treated as Unsatisfied |
| H16 | Blocking outcomes enumerated with clearing action | Read the canonical gate section for every outcome that holds a plan back | Each outcome states whether it blocks and the action that clears it |

Scenarios 1–6 above cover wiring; this matrix covers criterion-level outcomes. Every row is a **required** case in implementation verification (executed and recorded in the implementation PR), not optional desk-checking. The matrix below plus the Scenarios, the mirror harness, and the mapping table in the next section together exercise every acceptance criterion. **Per-row assertion for every Blocking row:** the observed finding must name the applicable rule and the specific defect (what was missing, failed to reproduce, or was contradicted, naming the claim or the contradicting outcome); a Blocking result whose finding lacks either fails that row (spec line 533). Every matrix row is **required** (executed and recorded in the implementation PR). The rows exercise behavior that wiring alone cannot prove. Before marking implementation complete, execute
every matrix row above (B1–B13, C1–C4, D1–D3, E1–E3, F1–F6, G1–G4, H1–H18), as
the implementation plan Testing Strategy requires, including at least one
blocking and one non-blocking outcome on real or fixture plan text.

## Criterion-to-exercise mapping (spec Groups A–H)

Every acceptance criterion of the spec, by its line in
`1_1496-plan-authoring-rigor_specs.md`, mapped to the exercise that fails if it
is unmet. **H** = mirror-harness assertion; **S** = smoke scenario.

| Spec lines | Group and criterion | Exercise |
| --- | --- | --- |
| 463 | A — trigger, evidence, pass condition per rule | S1 (each rule states all three) + H (rule headings) |
| 464 | A — author/reviewer share name and pass condition | S1 pass-condition equivalence + S2 + H (mirror references) |
| 465 | A — exactly one canonical surface | S1 + H (canonical path referenced from every mirror) |
| 466 | A — checks need only plan, repo, record, search | S4 (reviewer applies backstop with those inputs only) |
| 467 | A — no language/framework/path in rule text | S1 (read rule text for stack or path names) |
| 468 | A — applies to no-spec and Refactor plans | S3 on the mandatory Refactor/no-spec scratch plan from the test setup (the outcome record is present) |
| 472 | B — no record fails | B1, B12 |
| 473 | B — record completeness | B2, B13 |
| 474 | B — short-retention locator | B5 |
| 475 | B — access-restricted occurrence | B6 |
| 476 | B — both short-retention and restricted | B7 |
| 477 | B — fixed set needs a contract | B3, B12 |
| 478 | B — open set: stable part and unseen behavior | B4 |
| 479 | B — adequacy rationale | B8, B11 |
| 480 | B — curated / two-or-fewer occurrences | B2, B9 |
| 481 | B — enumeration with closure provenance | B10 |
| 485 | C — single assertion, others point to it | C1, C2 |
| 486 | C — disagreeing vs agreeing pair | C1, C2 |
| 487 | C — size is never a criterion | C3 |
| 488 | C — correction edits, not adds | C4 |
| 492 | D — command, revision, population | D1 + H10 |
| 493 | D — arithmetic over disjoint exhaustive sets | D1 |
| 494 | D — homogeneous population | D3 |
| 495 | D — enumeration behind a scoping number | D2 |
| 499 | E — existence claim needs recorded search | E1 |
| 500 | E — delegated support fails | E1 |
| 501 | E — completeness needs per-item evidence | E3 |
| 502 | E — non-existence names plausible places | E2 |
| 506 | F — every consumer enumerated with outcome | F1, F4 |
| 507 | F — recorded reproducible search | F5 |
| 508 | F — search scope where consumers live | F3 |
| 509 | F — unmodified consumers on the path | F4 |
| 510 | F — observation point in the enumeration | F6 |
| 511 | F — branch removal names the receiving branch | F2 |
| 515 | G — scope and discharge named | G1 |
| 516 | G — stand-in word is not scope | G2 |
| 517 | G — explanation without governed occurrences | G3 |
| 518 | G — author obligation, review a backstop | G4 |
| 522 | H — three labels spelled identically | H8 + H (label assertions) |
| 523 | H — no recorded outcome is Unsatisfied | H1, H15 |
| 524 | H — Not applicable needs a non-contradicted rationale | H3, H14 |
| 525 | H — outcome from evidence, not label | H6 |
| 526 | H — absent trigger recorded Satisfied/Unsatisfied | H7 |
| 527 | H — invalid label is Unsatisfied | H8 |
| 528 | H — gate log lists rules, revision, rationale | S3 + H2, H4 |
| 529 | H — first-inspection finding carried; locators re-inspected | H9, H18 |
| 530 | H — outcomes re-determined every round | H5, H11, H12 |
| 531 | H — blocking outcomes enumerated with clearing action | H16 |
| 532 | H — evidence in the plan document | H13, H17 |
| 533 | H — findings name the rule and what failed | Every matrix row whose expected result is Blocking, via the per-row assertion in the matrix introduction |
