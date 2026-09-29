# Matrix Coherence Preflight — Implementation Plan

**Work item brief**: GitHub issue #1759 (Refactor — the brief replaces the spec)
**Smoke test runbook**: [`docs/testing/workflow/1759-matrix-coherence-preflight.smoke-test.md`](../../../testing/workflow/1759-matrix-coherence-preflight.smoke-test.md)

---

## Summary

**Approach**: Add a documentation-only **matrix-coherence preflight** to the spec/plan workflow. When a spec (or, for Refactor items, the work item brief) contains a stateful contract — a decision matrix, state table, lifecycle, precedence rules, or similar — the creator-stage agent must run a six-check coherence audit over that matrix **before** pushing the PR and entering the reviewer loop, and the loop-side guidance must require the loop runner to re-run the same audit **after two consecutive review cycles whose findings implicate the same matrix** (matrix identity and counter-reset semantics defined in the Protocol 93 edit). The audit is an existing-doctrine consolidation: the six checks are the `Criteria/matrix mismatch` and `Trigger ambiguity` patterns already canonised in [`review-doctrine.md`](../../../workflow/development-workflow/review-doctrine.md), plus the phase-ordering and evidence-freshness disciplines already stated in Protocol 01/02. No new script, parser, or configuration surface is added.

**Estimated complexity**: S

**Rationale**: The change is confined to protocol/guidance markdown plus the review contract's checklist bullets. The nearest prior art, #1561's reviewer preflight, is a shell/Python tool for reviewer-*configuration* coherence; this item audits spec *content* coherence and deliberately builds no tool (see Decision 1).

**Dependencies**: None. #1561's surfaces are already merged at `361a7972` (verified in the Cross-Cutting Operational Assumption Check); this change composes with — never duplicates — them.

---

## Verification Log

All commands run at repo revision `361a7972` (branch `develop`, `2026-09-27`).

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `361a7972` |
| No existing matrix-coherence preflight guidance (Rule 4 non-existence) | `grep -rin "coherence" docs/workflow/ scripts/ REVIEW.md AGENTS.md` excluding `docs/specs/developments/`; plus `grep -rin "coherence" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/` | 1 hit in the first search, unrelated: `docs/workflow/development-workflow/integrations/coderabbit.md:286` describes #1561's reviewer preflight as "a configuration-coherence verdict" — different surface (reviewer config, not spec content). Second search: 0 hits — no agent/skill guidance tree carries any coherence guidance to duplicate or extend |
| #1561 prior-art files exist (Rule 4 existence) | `ls scripts/development-workflow/ \| grep preflight` | `reviewer-preflight.sh`, `reviewer_preflight.py`, `reviewer_preflight_build_input.py`, `reviewer_preflight_coderabbit.py` exist |
| #1561 preflight is config-scoped, not spec-content-scoped (Rule 4 "already covered" check) | Read `scripts/development-workflow/reviewer-preflight.sh` lines 1-120 | Header: "cross-check reviewer configuration before dispatch … shared workflow reviewer configuration, the machine-local override, and each reviewer platform's own configuration". No spec-content reading anywhere |
| Triggering-example matrix exists (Rule 4 existence) | `ls docs/specs/developments/20260915075927_1757-resolved-codex-findings/` | `1_1757-resolved-codex-findings_specs.md` present; its `## Complex Workflow Decision-Gate Matrix` section (lines 197-247) is the dense precedence matrix the brief cites |
| Doctrine already carries the core patterns (Rule 4 existence; avoids duplicating #1561-style tooling) | `grep -n "^### " docs/workflow/development-workflow/review-doctrine.md` | 6 patterns: `Criteria/matrix mismatch`, `Opt-out ambiguity`, `Parser-surface conflict`, `Trigger ambiguity`, `Example contradicting rule`, `Enumeration treated as contract`; file is 4,104 bytes against the 12,000-byte `REVIEW_DOCTRINE_MAX_BYTES` bound |
| Reviewer-loop re-run hook location (Rule 4 existence) | `grep -n "Long spec/plan review-cycle guidance" docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | Section exists at line 1022 ("Long spec/plan review-cycle guidance") — the natural anchor for the re-run requirement |
| Protocol 01 spec-side gate location (Rule 4 existence) | `grep -n "Complex workflow decision-gate matrix" docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` | Guidance exists at lines 190-199 within the Document Quality Gate pre-PR verification list |
| Full 22-file population (Rule 3 direct union query; disjoint by construction, each path listed once) | `P=docs/workflow/development-workflow/protocols; ls $P/01-generate-spec-protocol.md $P/02-generate-implementation-plan-protocol.md $P/03-implement-development-protocol.md $P/91-orchestrate-work-protocol.md $P/93-automated-reviewer-loop-protocol.md docs/workflow/development-workflow/review-doctrine.md REVIEW.md .claude/agents/{product-manager,spec-reviewer,tech-lead,developer,automated-reviewer-loop}.md .cursor/agents/{product-manager,spec-reviewer,tech-lead,developer,automated-reviewer-loop}.md .codex/skills/{workflow-spec-writer,workflow-spec-reviewer,workflow-plan-writer,workflow-implementer,workflow-reviewer-loop}/SKILL.md \| wc -l` | `22` (5 protocols + `review-doctrine.md` + `REVIEW.md` + 5 `.claude` + 5 `.cursor` + 5 `.codex` mirrors; every path exists, no path repeats) |
| Protocol 91 reviewer dispatch routing (Rule 4 existence) | `sed -n 1955,1990p docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | "Reviewer dispatch map" table routes `spec/*` PRs to `spec-reviewer` / `workflow-spec-reviewer` / CodeRabbit / `codex-github-reviewer.sh` — the surfaces the preflight feeds |
| Live search: all agent/skill files that reference the affected stage protocols (cross-cutting checklist enumeration, Rule 5) | `grep -rln "01-generate-spec-protocol\|93-automated-reviewer-loop-protocol\|01-review-spec-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/` | 9 files: `.claude/agents/{product-manager,spec-reviewer,automated-reviewer-loop}.md`, `.cursor/agents/{product-manager,spec-reviewer,automated-reviewer-loop}.md`, `.codex/skills/{workflow-spec-writer,workflow-spec-reviewer,workflow-reviewer-loop}/SKILL.md` |
| Live search: plan-stage mirror surfaces (cross-cutting checklist enumeration) | `grep -rln "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/` | 6 files: `.claude/agents/{developer,tech-lead}.md`, `.cursor/agents/{developer,tech-lead}.md`, `.codex/skills/{workflow-plan-writer,workflow-implementer}/SKILL.md` |
| Every direct consumer of the changed `REVIEW.md` checklists is enumerated (Rule 5 consumer check) | Broad search: `grep -rlE "REVIEW\.md\|review-spec-protocol\|review-implementation-plan-protocol" .claude .cursor .codex .agents \| grep -v openai.yaml` (21 files: the review roles (4 code-review entrypoints, 3 spec-review, 3 plan-review), writer roles, three Cursor `review-*` commands, `.cursor/rules/workflow.mdc`, and sync-template surfaces); plus `grep -ci matrix .cursor/agents/implementation-plan-reviewer.md .cursor/agents/spec-reviewer.md` (2 and 0) | Spec-review consumers (`spec-reviewer` x3, `.cursor/commands/review-spec.md`) and plan-review consumers (`implementation-plan-reviewer` x3, `.cursor/commands/review-implementation-plan.md`) read `REVIEW.md` directly or via `01-`/`02-review-*-protocol.md`; `code-reviewer` x3 (`.claude/agents/code-reviewer.md`, `.cursor/agents/code-reviewer.md`, `.codex/skills/workflow-code-reviewer/SKILL.md`) plus `.cursor/commands/review-code.md` consume the Code Review Checklist bullet. Post-change outcome: all pick up the new `REVIEW.md` bullets with no edit of their own (the commands and code-reviewers instruct "use `REVIEW.md`" and so inherit it); `.cursor/rules/workflow.mdc` only names `REVIEW.md` in a table; the sync-template files copy files and do not review; writer roles are the 15 mirrors already in the plan. The Cursor plan-reviewer's 2 `matrix` hits are the phrase "canonical gate matrix" |

---

## Factual claim evidence

**Rule 6 — scoped obligations.** Every conditional this plan introduces is stated with its governed scope and discharge point in the same statement:

1. "The matrix-coherence preflight is required when the spec or work item brief contains a decision matrix, state table, lifecycle, precedence rules, or similarly stateful contract" — governed scope: `spec/*` and `implementation-plan/*` PRs' primary artifact (the spec file or plan document), and for Refactor items the work item brief as recorded in the plan's header; discharge point: Protocol 01 Step "pre-PR verification" for specs, Protocol 02 Step 5 (cross-section consistency self-check) for plans — both before the first push.
2. "The preflight re-runs after two consecutive review cycles whose findings implicate the same matrix" — governed scope: reviewer-loop cycles on `spec/*` / `implementation-plan/*` PRs only (implementation PRs are out of scope; their Pass 1 spec-compliance check is unchanged); discharge point: Protocol 93's "Long spec/plan review-cycle guidance" section, checked and performed by the loop runner alone (matrix identity and counter-reset semantics as stated in the Protocol 93 edit) before dispatching the next fixer, with the audit result passed to that fixer.
3. "Simple specs gain no ceremony" — governed scope: artifacts whose prose defines no stateful contract (no matrix, state table, lifecycle, or precedence rules); discharge point: the classification signal recorded in the Document Quality Gate log as `Matrix coherence preflight: Not applicable — no stateful contract` (rationale required, same shape as every other `Not applicable` row).

**Rule 1 — sampling or enumeration record.** Not applicable. The design binds to no external free-text output distribution: it adds review guidance over documents this repository authors. No third-party output is matched, parsed, classified, or enumerated. (Trigger absent: no producer, no population, no occurrence set.)

### Per-rule outcome record (this plan revision — the PR head that contains this section; same-head label)

Outcome labels per `plan-authoring-rigor-rules.md`:

| Rule | Outcome | Evidence pointer |
| --- | --- | --- |
| Rule 1 — Sampling an external output distribution | `Not applicable` — no external free-text producer, population, or occurrence set; guidance targets this repository's own documents | "Factual claim evidence" → Rule 1 paragraph above |
| Rule 2 — One normative statement per fact | `Satisfied` — the six-check definition and the 22-file enumeration each appear once as normative; all other mentions are cross-references | "The six audit checks" section; Layer-by-Layer total line |
| Rule 3 — Counts of codebase artifacts | `Satisfied` — 22-file count derived from the recorded direct union query (Verification Log row "Full 22-file population") at `361a7972`; the two greps corroborate the protocol and mirror subsets | Verification Log row "Full 22-file population" (`ls ... \| wc -l` = 22); Layer-by-Layer "Total: 22 files" |
| Rule 4 — Independent verification of existence claims | `Satisfied` — non-existence claim covers all plausible locations (docs, scripts, REVIEW.md, AGENTS.md, and the four agent/skill trees); plan-reviewer exemption cites its direct grep | Verification Log row 1 (both recorded searches); Layer-by-Layer total line: `grep -ci "matrix" ...` evidence |
| Rule 5 — Consumer enumeration at composed call sites | `Satisfied` — every direct consumer enumerated by a broad recorded search with post-change outcomes | Verification Log row "Every direct consumer of the changed `REVIEW.md` checklists is enumerated" |
| Rule 6 — Conditional obligations name scope + discharge point | `Satisfied` — all three conditionals carry scope + discharge point in the same statement | "Factual claim evidence" → Rule 6 list |

### Reversal note (published workflow contract changes)

This plan changes published workflow-contract text (protocols 01/02/03/91/93, `review-doctrine.md`, `REVIEW.md`, and the 15 agent/skill mirrors). Reversal path: each change is an additive bullet, row, or pointer sentence in versioned markdown on `develop` — reverting the implementing PR's commits (or a follow-up `git revert`) restores the prior text with no data migration, no config keys to remove, and no runtime state. No script, schema, or generated surface is touched, so there is no tooling rollback to sequence. The new doctrine pattern `Stateful-contract outcome gaps` reverts with the rest of `review-doctrine.md`'s diff.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this plan PR | `develop` (tip `361a7972`) | Batch handoff + `git rev-parse origin/develop` | 2026-09-27, `361a7972` | Current invocation item list: `1759, 1445, 1444, 1408, 1390, 1386, 1378, 1538, 1559, 1564`; zero open PRs in this repository at dispatch (`gh pr list --state open` → empty) | `Verified` |
| Nearest prior art surface — #1561 reviewer preflight | `scripts/development-workflow/reviewer-preflight.sh` + `reviewer_preflight*.py`, merged in `361a7972 Merge PR #1802 (feature/1561-reviewer-preflight)` | Git history + file headers | 2026-09-27, `361a7972` | Same item list; no open PR touches these files (zero open PRs) | `Verified` |
| Batch foundational fix on the shared reviewer-loop script | Item `1390` repairs `scripts/development-workflow/pr-review-loop.sh`; other batch items hold until it merges | Batch handoff (parent orchestrator) | 2026-09-27 | This plan's changes touch no script, so #1390's outcome cannot invalidate any plan statement | `Verified` (no conflict surface) |

No `Conflict` evidence. The plan's design decision (build no tool; compose with #1561 rather than duplicate it) is an architecture choice, not an operational assumption. #1561's preflight checks reviewer *configuration* coherence; this plan adds spec *content* coherence guidance — different assumption surfaces, so shared "preflight" terminology alone is not conflict evidence.

---

## Decisions

- **Decision 1 — documentation-only audit, no new script.** The brief says "detect or require the reviewer/spec workflow to audit matrices." Building a matrix parser would (a) duplicate the doctrine catalogue's existing human-checkable patterns, (b) violate Gate B proportionality (a prose-only deliverable proposing a custom parser is the exact anti-pattern), and (c) sit awkwardly next to #1561's config preflight, which solves a different problem. The audit is therefore a required, evidenced *checklist pass*, not a tool. Upgrade path: if a future item wants mechanical matrix analysis, the six audit checks in the "The six audit checks" section are its requirement list.
- **Decision 2 — extend doctrine, don't fork it.** The six audit checks map onto `review-doctrine.md`'s `Criteria/matrix mismatch` and `Trigger ambiguity` patterns. The doctrine file gets one new pattern (`Stateful-contract outcome gaps`) only for the checks doctrine does not yet name (terminal/waiting/escalation coverage, stale-vs-current evidence, precedence-order ambiguity); the rest cross-reference the existing patterns. The doctrine file is 4,104 bytes of a 12,000-byte budget, so one compact pattern fits without touching the bound.
- **Decision 3 — two places in the workflow, one definition.** The preflight's first run belongs at creator stage, pre-push (Protocol 01 for specs; Protocol 02 Step 5 for plans, where it extends the existing cross-section consistency self-check). The re-run belongs in Protocol 93's "Long spec/plan review-cycle guidance" — the section that already governs what to inspect when a document PR loops repeatedly — and is the loop runner's responsibility: the runner identifies the implicated matrix (its section heading/table/step anchor), counts consecutive cycles against it, resets the count on a non-implicating cycle or after a re-audit, performs the re-audit, and passes its result to the dispatched fixer. Protocol 91 needs no new step: its reviewer dispatch already routes through the protocols changed here; its only edit is one cross-reference sentence in the existing dispatch-map area so a runner following P91 can find the requirement.
- **Decision 4 — scope gate is the Document Quality Gate log.** "Targeted to matrix/state-machine specs only" is enforced by the same mechanism as every other conditional gate in this workflow: a `Matrix coherence preflight` row in the Document Quality Gate log that must read `Checked` (with evidence summary) or `Not applicable — no stateful contract` (rationale). A missing row is a reviewer finding, exactly like the existing matrix and checklist rows. No new config key, no `MATRIX_*` environment variable, no branch-type special-casing.

---

## Layer-by-Layer Changes

### Documentation / Workflow Layer (only layer affected)

- [ ] **`docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`** — in the pre-PR "Before the PR is opened, verify" list, directly after the existing "Complex workflow decision-gate matrix" bullet: add a "Matrix coherence preflight" bullet defining the trigger (spec contains a decision matrix, state table, lifecycle, precedence rules, or similarly stateful contract), the full audit-check list inlined verbatim from the "The six audit checks" section below (this protocol is the canonical shipped home of the list), the timing (before first push, i.e. before Step 7/Step 7's reviewer loop is ever entered), and the evidence requirement (a `Matrix coherence preflight` row in the Document Quality Gate log: `Checked` with a one-line audit summary naming each check and its pass/fail, or `Not applicable` with the no-stateful-contract rationale).
- [ ] **`docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`** — Step 5 (cross-section consistency self-check): add a sub-bullet extending the check to the plan's own decision tables and to the work item brief for Refactor items; and in the Document Quality Gate template block, add the `Matrix coherence preflight` row example (`Checked` / `Not applicable - no stateful contract in the plan or brief`).
- [ ] **`docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`** — in "Long spec/plan review-cycle guidance" (line 1022): add the re-run rule — when **two consecutive cycles' blocking findings implicate the same decision matrix, state table, or precedence rule set** of the spec/plan under review, the loop runner must re-run the full six-check coherence audit on that matrix before the next fix push, and record the audit result in the fix commit comment. Matrix identity: a matrix is identified by its normative location — the section heading, table, or step anchor in the reviewed document; a blocking finding implicates a matrix when resolving it requires editing that matrix's rows, states, or precedence rules. Counter semantics: the consecutive-cycle count for a given matrix increments for each cycle whose blocking findings implicate that matrix, resets to zero when a cycle's blocking findings do not implicate it, and resets after the re-audit runs. The re-audit is the loop runner's responsibility alone; dispatched fixers receive its result with the fix dispatch rather than performing it. The existing no-progress/stuck-loop escalation path stays unchanged and still applies when the audit itself does not clear the loop.
- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`** — one cross-reference sentence in the "Reviewer dispatch map" area: when a spec/plan fixer dispatch follows a matrix-coherence re-audit, the dispatch carries the loop runner's audit result (the re-audit itself is performed by the loop runner per Protocol 93's long-cycle guidance, not by the fixer). No new step, no new gate, no change to reviewer routing.
- [ ] **`docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`** — one pointer sentence under its documentation-PR guidance: implementation PRs are not in the preflight's scope (the preflight gates spec and plan artifacts); implementation docs follow their existing review path unchanged.
- [ ] **`docs/workflow/development-workflow/review-doctrine.md`** — add one pattern, `### Stateful-contract outcome gaps` (Shape / Example / Detect), covering the checks the existing `Criteria/matrix mismatch` and `Trigger ambiguity` patterns do not name: outcome classes absent (terminal vs waiting vs escalation), evidence-currency rules (stale vs current), and precedence/order ambiguity among rules that fire together. Cross-reference the existing two patterns from the new entry's Detect line rather than restating them. Keep incident traces out per the file's own rules.
- [ ] **`REVIEW.md`** — `Spec Review Checklist`: one check bullet — "When the spec contains a stateful contract, the PR's Document Quality Gate log carries a `Matrix coherence preflight` row with the six-check audit summary or a reasoned `Not applicable`"; `Plan Review Checklist`: the mirror bullet for plan decision tables and Refactor briefs; both under the existing blocking-class framing for missing/unreasoned gate rows, and both bullets also state that a `Not applicable — no stateful contract` row is a blocking finding whenever the reviewed artifact actually contains a stateful contract (misclassification; the fixer runs the six-check audit). `Code Review Checklist` (documentation PRs additional checks): one bullet — on `spec/*` / `implementation-plan/*` PRs, verify a matrix-bearing document carries the row.
- [ ] **Agent / skill mirror surfaces (cross-cutting checklist enumeration — all updated so no required target is missing; each change is a pointer sentence, not restated rules):**

  `.claude/agents/product-manager.md`, `.cursor/agents/product-manager.md`, `.codex/skills/workflow-spec-writer/SKILL.md` (spec-writing role: run the preflight before first push);
  `.claude/agents/spec-reviewer.md`, `.cursor/agents/spec-reviewer.md`, `.codex/skills/workflow-spec-reviewer/SKILL.md` (spec-review role: check the row; on loop re-entry after two same-matrix cycles, the loop runner re-runs the audit and passes its result to the fixer — reviewers do not perform the re-audit);
  `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-plan-writer/SKILL.md` (plan-writing role: extend the Step 5 self-check);
  `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `.codex/skills/workflow-implementer/SKILL.md` (pointer only: implementation PRs are out of the preflight's scope — keep these edits to one sentence so implementation guidance gains no ceremony);
  `.claude/agents/automated-reviewer-loop.md`, `.cursor/agents/automated-reviewer-loop.md`, `.codex/skills/workflow-reviewer-loop/SKILL.md` (loop role: apply Protocol 93's re-run rule).

  Total: 22 files — 5 protocol files (01, 02, 03, 91, 93) + `review-doctrine.md` + `REVIEW.md` + 15 agent/skill mirrors enumerated in the role groups above. The plan-stage protocol's own cross-cutting checklist rule requires the enumeration to cover the developer implementation protocol and both tech-lead/developer role files; those are `03-implement-development-protocol.md` (its own bullet above) and the developer/implementer files listed above. Codex plan-reviewer skill (`workflow-plan-reviewer`) and `implementation-plan-reviewer` agent files need no separate edit: verified directly — `grep -ci "matrix" .codex/skills/workflow-plan-reviewer/SKILL.md .claude/agents/implementation-plan-reviewer.md` returns 0 and 2 respectively, and the 2 hits are the phrase "canonical gate matrix" referring to `plan-authoring-rigor-rules.md`, not restated checklist content; both surfaces route through `REVIEW.md`, which this plan already updates.

### Database / Backend / Shared Packages / Frontend / Infrastructure

Not applicable — documentation-only change. No schema, script, service, package, UI, or configuration surface changes.

### Complex workflow decision-gate matrix (this plan's own changed surface)

This plan modifies workflow decision-gate behavior (a new conditional gate with inputs, outcomes, and mirror surfaces), so it carries its own consistency matrix:

| Gate input | Allowed outcomes | Required next action | Mirror surfaces | Examples |
| --- | --- | --- | --- | --- |
| Spec/plan/brief contains a stateful contract (matrix, state table, lifecycle, precedence rules) | `Checked` (six-check audit passed) | Proceed to push / reviewer loop unchanged | Protocol 01 + 02 gate lists, REVIEW.md spec/plan checklists, PM/tech-lead/spec-reviewer agents and Codex skills, doctrine pattern | Spec #1757's decision-gate matrix: audit must pass all six checks before its PR's reviewer loop |
| Spec/plan/brief contains a stateful contract, audit finds a gap | `Checked — gaps found` (blocking) | Fix the matrix before push; re-audit; log lists each failed check | Same as above | A matrix with rows only for the resolved-conversation case and none for dismissed (overlapping/missing-state class) |
| Spec/plan/brief contains no stateful contract | `Not applicable — no stateful contract` | Proceed; no ceremony added | Same as above | A UI-feature spec with no decision table or lifecycle |
| Log row says `Not applicable — no stateful contract` but the artifact contains a stateful contract (misclassification) | Reviewer finding (blocking) | Fixer runs the six-check audit and replaces the row with `Checked` or `Checked — gaps found` | REVIEW.md checklists, spec/plan reviewer protocols | A spec with a decision table whose gate row claims no stateful contract |
| Log row missing or unreasoned | Reviewer finding (blocking, same class as other missing gate rows) | Fixer adds the row with audit or rationale | REVIEW.md checklists, spec/plan reviewer protocols | Matrix-bearing spec PR whose Document Quality Gate log omits the row |
| Reviewer loop: two consecutive cycles' blocking findings implicate the same matrix (matrix identity: its section heading/table/step anchor; resets per Protocol 93 rule) | Re-run required | Loop runner re-runs the six checks before next fix push; result recorded in fix commit comment and passed to the dispatched fixer | Protocol 93 long-cycle guidance, reviewer-loop agents/skills | #1757/#1758-style repeated adjacent ambiguity in Codex evidence classification |
| Two consecutive cycles, findings do not share a matrix | No re-run (existing long-cycle guidance still applies) | Continue normal fix/escalate path | Protocol 93 long-cycle guidance | Two cycles of unrelated wording findings |

Not-applicable rows: none — every input has an outcome.

### Parser-risk / concurrent-event-source classification

Not applicable — no files under `scripts/lint/`, `scripts/parse/`, no parser/scanner/tokenizer modules, no regex-over-text behavior, no event listeners or shared mutable state. The deliverable is protocol prose. (Gate B note: this documentation-only plan proposes no parser, scanner, or matcher — the deliberate choice recorded in Decision 1.)

---

## The six audit checks (single normative definition)

The plan document itself is a plan artifact, not shipped workflow text. The implementer **inlines this six-check list verbatim into `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`** as the shipped canonical definition (Protocol 02's Step 5 sub-bullet and all other files cross-reference that Protocol 01 list and `review-doctrine.md`'s patterns rather than restating it — Rule 2). For a decision matrix, state table, lifecycle, or precedence-rule set:

1. **Overlapping rows** — can two rows match the same input combination, and if so, does the document state which wins? (doctrine: `Criteria/matrix mismatch`)
2. **Missing states** — for every input combination the surrounding prose admits, is there a row/branch, including malformed or unknown input handling? (doctrine: `Criteria/matrix mismatch` + `Trigger ambiguity`)
3. **Precedence / order ambiguity** — when rules or rows fire together, is the ordering stated? (new doctrine pattern)
4. **Malformed / unknown input handling** — is the outcome defined for missing, empty, invalid, or unrecognized inputs? (doctrine: `Trigger ambiguity`)
5. **Stale vs current evidence** — do the rules say which evidence revision/currency governs, when recency decides? (new doctrine pattern)
6. **Terminal vs waiting vs escalation outcomes** — does every path end in one of the stated outcome classes, with no gap where the loop could neither proceed, wait, nor escalate? (new doctrine pattern)

---

## Testing Strategy

**Test types**: Smoke (documentation runbook). No unit tests — no executable behavior is added (the planted-violation proof rule applies to automated checks; this adds none).

**Key scenarios to test**:

1. Matrix-bearing spec PR carries the audit row — maps to brief scope bullet 3 ("Document where the pass belongs … and what evidence it should produce").
2. Simple spec PR records a reasoned `Not applicable` — maps to brief scope bullet 2 ("ordinary simple specs do not gain unnecessary ceremony").
3. Re-run trigger after two same-matrix cycles — maps to the brief's desired-outcome sentence ("run … again after repeated meaningful reviewer findings on the same matrix").
4. Mirror surfaces cross-reference, do not restate — maps to Decision 2/Rule 2 (no drift between the 22 enumerated files and the canonical six-check definition).

**Coverage intent**: the runbook walks the document changes as a reviewer would; each scenario is a read-and-confirm step. Enumeration is indicative.

**Smoke test runbook**: `docs/testing/workflow/1759-matrix-coherence-preflight.smoke-test.md`

**Regression suite**: no automated regression suite covers protocol markdown; none is added.

---

## Seed Data

None — documentation-only.

---

## Documentation Updates

Executed by the implementer (this PR's own file list — the change *is* documentation):

- [ ] All 22 files enumerated in Layer-by-Layer Changes (5 protocols, `review-doctrine.md`, `REVIEW.md`, 15 agent/skill mirrors — see the live-search rows in the Verification Log for the exact derivation)
- [ ] `AGENTS.md` — no update needed: its workflow table already points at the protocols changed here, and it carries no matrix-guidance text of its own (verified by the `grep -rin "coherence"` search above returning no AGENTS.md hit)
- [ ] Project docs (`docs/project/`, `docs/best-practices/`) — None: the change is workflow-process guidance, not product or stack guidance

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror-surface drift: 22 files restate the six checks differently | Medium | Medium | Files carry pointer sentences only; the canonical shipped definition is the six-check list inlined into Protocol 01 (see "The six audit checks"); REVIEW.md gate row catches drift |
| Audit becomes ceremony on borderline docs (a simple two-row table) | Medium | Low | Trigger wording requires a *stateful contract*; the `Not applicable` row with rationale is the escape valve; doctrine Detect questions keep the audit meaningful |
| Re-run rule misread as a new escalation path | Low | Medium | Protocol 93 edit explicitly states the existing stuck-loop escalation is unchanged and still applies |
| Doctrine 12,000-byte budget exceeded | Low | Low | Current 4,104 bytes + one compact pattern (~700 bytes) stays far under; if the entry grows, merge patterns per the file's own rule, never raise the bound |

---

## Implementation Order

1. Add the `### Stateful-contract outcome gaps` pattern to `docs/workflow/development-workflow/review-doctrine.md` (checks 3, 5, 6; cross-references the two existing patterns for the rest).
2. Update `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` — pre-PR verification bullet + Document Quality Gate example row, cross-referencing doctrine.
3. Update `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — Step 5 sub-bullet + Document Quality Gate template row.
4. Update `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — re-run rule in "Long spec/plan review-cycle guidance".
5. Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — one cross-reference sentence near the reviewer dispatch map.
6. Update `REVIEW.md` — Spec Review Checklist, Plan Review Checklist, and documentation-PR additional-check bullets.
7. Update the 15 agent/skill mirror files (pointer sentences only, per the role groups in Layer-by-Layer Changes).
8. Confirm no drift: run `grep -rn "Matrix coherence preflight"` over the 22 implementation targets only (the retained plan and smoke-runbook artifacts under `docs/specs/developments/` and `docs/testing/workflow/` necessarily restate the six checks and are excluded) and confirm every hit is either the canonical definition, a pointer to it, or the gate-row name — no restated variant of the audit checks defined in "The six audit checks" section.
9. Verify the smoke runbook: `docs/testing/workflow/1759-matrix-coherence-preflight.smoke-test.md`.
10. Update project docs per the Documentation Updates section (none beyond this PR's own files).
11. Add a `changelog.d/1759.changed.matrix-coherence-preflight.md` fragment using the project's format: `- **Add matrix coherence preflight for spec reviewer loops** (#1759): <description>`. (Refactor implementation PR merged to `develop` — fragment required; not conventional-commit format.)

> Skipped: mechanical matrix analysis tooling — add when repeated audits show the human checklist pass is the bottleneck, not the reviewer cycles.
