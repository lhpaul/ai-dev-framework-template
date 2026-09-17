# Plan-Authoring Rigor — Implementation Plan

**Spec**:
[1_1496-plan-authoring-rigor_specs.md](./1_1496-plan-authoring-rigor_specs.md)
**Smoke test runbook**:
[1496-plan-authoring-rigor.smoke-test.md](../../../testing/workflow/1496-plan-authoring-rigor.smoke-test.md)

---

## Summary

**Approach**: Add one canonical, framework-portable rules document for the six
plan-authoring rules, wire it into Protocol 02 and plan-writer agent/skill
surfaces as authoring obligations, extend `REVIEW.md` and the plan-reviewer
agents with the matching backstop check, extend the implementation-plan
template so firing-rule evidence has a predictable home in the plan body, and
extend Protocol 02's existing `Document Quality Gate` PR-description block with a
mandatory **per-rule outcome record** (Groups A and H). No linter, bot, or
script enforces the rules automatically — Out of Scope for MVP.

**Canonical surface decision (spec Business Rules — mirror surfaces)**: The
single canonical statement of the six rules **and** the plan review gate
extension lives in
`docs/workflow/development-workflow/plan-authoring-rigor-rules.md`. Every other
surface agrees with it: same rule names (`Rule 1` … `Rule 6`), same three
outcome labels (`Satisfied`, `Not applicable`, `Unsatisfied`), same blocking vs
non-blocking classifications for gate rows. The spec's full Decision-Gate
Consistency Matrix is **copied into** that file as the normative gate section
during implementation (do not paraphrase pass conditions). The approved spec
remains historical product intent; after merge, engineers treat the new rules
file as authoritative for day-to-day plan work.

**Estimated complexity**: L

**Rationale**: Six rules with a large gate matrix, five mirror surfaces, and
cross-cutting updates to protocols, `REVIEW.md`, four agent files, one Codex
skill, a template, and a mirror-consistency test harness. No runtime code, but
documentation must stay internally consistent or downstream adopters inherit
silent drift — the failure mode this feature exists to prevent.

**Dependencies**: None. Spec merged (#1736). Does not depend on #1655 strict
plan checks; strict checks stay non-blocking; this feature adds blocking
backstop obligations in `REVIEW.md` only where the spec gate matrix says
blocking.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop` | `32605700` — every row below run at this revision |
| Spec merged | `test -f docs/specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md` | present on branch |
| Rule headings in spec | `awk '/^### Rule [0-9]/{c++} END{print c}' docs/specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md` | `6` |
| Existing plan Document Quality Gate | `grep -n 'Document Quality Gate' docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Step 5 item 7 (~441+) — extension point for per-rule record |
| Plan review checklist location | `awk '/^## Plan Review Checklist/{print NR; exit}' REVIEW.md` | line `117` |
| Agent/skill protocol references | `grep -rl '02-generate-implementation-plan-protocol\|03-implement-development-protocol' .claude/agents/ .cursor/agents/ .codex/skills/` | six paths: `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md` |
| Plan reviewer agents | `ls .claude/agents/implementation-plan-reviewer.md .cursor/agents/implementation-plan-reviewer.md` | both present |
| Strict plan checks (orthogonal) | `head -5 docs/workflow/development-workflow/strict-plan-checks.md` | non-blocking contract checks — unchanged scope |
| Markdown CI covers workflow docs | `sed -n '12,16p' .github/workflows/markdown-lint.yml` | includes `docs/workflow/**` |
| No existing rules file | `test ! -e docs/workflow/development-workflow/plan-authoring-rigor-rules.md` | true at plan-write time — file is created in implementation |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop` | Batch handoff / Protocol 91 default | 2026-09-17, SHA `32605700` | Item #1496 only | `Verified` |
| Batch invocation peers | `1757,1462,1496,1515,1561,1583,1529` | Parent `/run-items` explicit list | 2026-09-17 | Same-surface open PRs: none per handoff | `Verified` — no same-surface plan/spec PR conflict for #1496 |
| Canonical rules not yet on disk | rules file absent | Verification Log last row | 2026-09-17 | N/A | `Verified` — implementation creates it |

**Overall result**: `Applicable` — re-verify base branch at implementation start.

### Not applicable

Database, runtime services, product repositories, deployment targets, and
external API contracts do not apply.

---

## Decision gate — plan review backstop (extended)

This feature **modifies** the plan review gate: new inputs (per-rule outcome
record, evidence in plan body, repository re-runs) and new blocking /
non-blocking outcomes. The **full** gate inputs, triggers, allowed outcomes,
required next actions, mirror surfaces, and examples are defined in the spec
section **Decision-Gate Consistency Matrix**. Implementation copies that section
into `plan-authoring-rigor-rules.md` under a dedicated heading so the canonical
rules file carries both authoring rules and reviewer gate behavior (spec mirror
table row "plan review checklist" + "quality gate log").

Summary for plan reviewers reading **this** document only:

| Gate input (added or emphasized) | Source |
| --- | --- |
| Whether each rule fires | Plan text |
| Evidence for firing rules | Plan document only |
| Reproducibility at recorded revision / population / window | Re-run recorded commands |
| Per-rule outcome record | Plan PR `Document Quality Gate` |
| Stale outcome record vs plan HEAD | Compare record's plan revision to PR head SHA |

| Representative blocking situation | Author next action |
| --- | --- |
| Firing rule with no evidence in plan | Add evidence or remove claim |
| Record missing or wrong revision SHA | Re-determine all outcomes at current head |
| Rule 4 claim supported only by delegation | Record direct search or drop claim |
| Rule 2 disagreeing duplicate assertions | Resolve to one assertion |

| Representative non-blocking situation | Notes |
| --- | --- |
| Rule 2 agreeing duplicates | Consolidation finding; rule stays Satisfied |
| Rule 1 adequacy rationale structurally complete but unpersuasive | Reviewer judgment; Satisfied while open |

**Triggers**: plan PR reaches plan review gate; each correction round
re-determines outcomes afresh (Group H).

**Mirror surfaces** (implementation must update every row):

| Surface | Role | Consistency requirement |
| --- | --- | --- |
| `plan-authoring-rigor-rules.md` | Canonical rules + gate matrix | Full normative text |
| Protocol 02 Step 3 + Document Quality Gate | Authoring obligations + outcome record schema | Points to canonical file; no weaker pass conditions |
| `implementation-plan-template.md` | Evidence placement in plan body | Verification Log / plan sections hold Rule 3/4/5 evidence |
| `REVIEW.md` Plan Review Checklist | Backstop check | Same rule names and blocking classes |
| `.claude/.cursor/agents/tech-lead.md` + Codex `workflow-plan-writer` | Plan-writer routing | Author obligations only |
| `.claude/.cursor/agents/implementation-plan-reviewer.md` | Reviewer routing | Backstop + outcome record checks |
| Plan PR `Document Quality Gate` | Per-rule outcome record | All six rules + revision SHA + N/A rationales |

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable.

### Shared Packages / Libraries

Not applicable.

### Documentation / Workflow

- [ ] **Create `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`.**
      Structure:

      1. Purpose (one paragraph — plans read as fact; backstop complements diff
         review).
      2. Rules 1–6 — port **verbatim** from the spec **Business Rules**
         section (including "Rules that apply across all six"). Do not introduce
         repository-specific paths or stack names.
      3. Status labels — table from spec **Statuses / Enum Values** (code values
         may stay in backticks for tooling; display labels must match Group H).
      4. **Plan review gate** — copy spec **Decision-Gate Consistency Matrix**
         subsections (Gate inputs, Triggers, Allowed outcomes and required next
         actions, Mirror surfaces, Examples) unchanged in substance.
      5. Cross-link to spec dev folder for historical context only.

      Maps to Groups A, B–G (normative text), H (gate).

- [ ] **Protocol 02 — authoring and PR gate.**
      File:
      `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`.

      - Step 3 **Quality guardrails**: add a bullet block "Plan authoring
        rigor" requiring authors to read the canonical rules file, record
        firing-rule evidence **in the plan** (Verification Log and/or dedicated
        subsections), and treat Rule 2 as firing on every non-empty plan.
      - Step 5 **Document Quality Gate**: extend the example markdown with a
        subsection:

        ```markdown
        ### Plan authoring rigor — per-rule outcome record

        Plan revision: `<git rev-parse --short HEAD of plan branch>`

        | Rule | Outcome | Rationale / first external inspection finding |
        | --- | --- | --- |
        | Rule 1 | Not applicable | No design depends on external free-text output. |
        | Rule 2 | Satisfied | Single assertion per fact; see Verification Log. |
        | … | … | … |
        ```

        Document that:

        - All six rules appear exactly once.
        - Outcomes use the three display labels only.
        - `Not applicable` rows include a one-line trigger rationale.
        - Rows for Rules 1 external citations (contract, manifest, notice,
          protected artifact) include the first-inspecting round's finding when
          applicable.
        - Authors refresh the record whenever plan text changes; revision SHA
          must match PR head before `ready-for-human-review`.
      - Step 3 cross-cutting checklist enumeration: this plan **is** a
        cross-cutting checklist change — the Files to modify section below is
        authoritative.

      Maps to Groups A, H; Operational Visibility.

- [ ] **`REVIEW.md` Plan Review Checklist.**
      Add a checklist block **Plan authoring rigor (backstop)** after existing
      items (before Typical blocking issues):

      - Read the canonical rules file and the plan's per-rule outcome record.
      - For each rule recorded as firing, re-run repository-derived evidence at
        the recorded revision; for Rule 1 sampling/enumeration, follow spec
        Group A external-source exception.
      - Raise blocking findings per the gate matrix; distinguish non-blocking
        consolidation and adequacy judgments.
      - Treat missing outcome record, missing N/A rationale, stale revision SHA,
        or evidence only in PR comments as blocking per Group H.

      Do **not** duplicate the full matrix prose — reference the canonical file.

      Maps to Use Case 7; Group H.

- [ ] **Plan review protocol pointer.**
      File:
      `docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md`.
      Add one paragraph: plan reviewers apply the backstop in `REVIEW.md` and
      the gate matrix in `plan-authoring-rigor-rules.md`; outcome record lives
      in PR description Document Quality Gate.

- [ ] **Implementation plan template.**
      File:
      `docs/workflow/development-workflow/templates/implementation-plan-template.md`.

      - Expand Verification Log intro to state it holds Rule 3 count
        derivations, Rule 4 existence searches, and Rule 5 consumer enumerations
        when those rules fire.
      - Add optional subsection **Factual claim evidence** (after Verification
        Log) with placeholders for Rule 1 sampling/enumeration records and Rule
        6 scoped obligations — authors delete if not applicable.

      Maps to mirror surface "plan document evidence area".

- [ ] **Agent and skill mirrors.**
      - `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md`: before
        Document Quality Gate step, require reading canonical rules file,
        filling in-plan evidence, and completing per-rule outcome record in PR
        description.
      - `.claude/agents/implementation-plan-reviewer.md` and
        `.cursor/agents/implementation-plan-reviewer.md`: require backstop
        check against canonical gate matrix and outcome record freshness.
      - `.codex/skills/workflow-plan-writer/SKILL.md`: same author obligations
        as tech-lead; delegate to Protocol 02, do not restate rules.

      Maps to Groups A, G (Rule 6 author obligation wording in canonical file
      only — agents point there).

- [ ] **`AGENTS.md` Key Documentation table** (Documentation Updates — executed
      during implementation): add row linking
      `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`.

### Infrastructure / Configuration

Not applicable.

---

## Files to modify

Live search at SHA `32605700` (`grep -rl` for protocol references) plus spec
mirror table:

| File | Change |
| --- | --- |
| `docs/workflow/development-workflow/plan-authoring-rigor-rules.md` | **Create** — canonical rules + gate matrix |
| `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Authoring + Document Quality Gate extension |
| `docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md` | Reviewer pointer |
| `docs/workflow/development-workflow/templates/implementation-plan-template.md` | Evidence sections |
| `REVIEW.md` | Backstop checklist block |
| `.claude/agents/tech-lead.md` | Author routing |
| `.cursor/agents/tech-lead.md` | Author routing |
| `.claude/agents/implementation-plan-reviewer.md` | Reviewer routing |
| `.cursor/agents/implementation-plan-reviewer.md` | Reviewer routing |
| `.codex/skills/workflow-plan-writer/SKILL.md` | Author routing |
| `scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh` | **Create** — mirror consistency harness |
| `docs/testing/workflow/1496-plan-authoring-rigor.smoke-test.md` | Already on plan branch — verify scenarios after implementation |
| `AGENTS.md` | Key docs table row |

### Cross-cutting checklist — Protocol 02 targets not edited

Protocol 02 requires naming every surface in its cross-cutting checklist block.
This plan modifies plan-stage authoring and review only; the spec **Out of
Scope** entry "Extension to other artifacts" keeps specs, code reviews, and
implementation protocols out of scope unless they duplicate plan-stage
obligations.

| Required Protocol 02 target | Disposition | Rationale |
| --- | --- | --- |
| `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | **No edit** | Rules apply at plan authoring/review; implementers execute approved plans. No new implementer checklist category is introduced. |
| `.claude/agents/developer.md` | **No edit** | Developer role does not write implementation plans. |
| `.cursor/agents/developer.md` | **No edit** | Same as Claude developer agent. |
| `.codex/skills/workflow-implementer/SKILL.md` | **No edit** | Implementation skill delegates to Protocol 03; plan evidence is already fixed when implementation starts. |

**Other explicit non-edits** (spec Out of Scope): workflow scripts
(`local-ai-reviewer.sh`, new linters), `strict-plan-checks.md` behavior, merged
plans retrofits.

---

## Testing Strategy

**Test types**: Shell mirror-consistency test; manual smoke test runbook.

**Key scenarios**:

1. Mirror harness — rule names and outcome labels appear in canonical file,
   `REVIEW.md`, and Protocol 02 (`test-plan-authoring-rigor-mirror.sh`).
2. Smoke Scenarios 1–7 in
   `docs/testing/workflow/1496-plan-authoring-rigor.smoke-test.md`.
3. Negative: remove one rule from outcome record table in a test PR — reviewer
   checklist treats as blocking (Group H).

**Regression suite**: Not applicable — no browser/product regression suite for
workflow docs.

### Mirror test harness (new)

Create `scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`:

- Assert canonical file exists and contains headings `Rule 1` through `Rule 6`.
- Assert `REVIEW.md` references `plan-authoring-rigor-rules.md` and all six
  rule names.
- Assert Protocol 02 references canonical path and
  `Plan authoring rigor — per-rule outcome record`.
- Assert tech-lead and implementation-plan-reviewer agents (Claude + Cursor)
  reference the canonical file.
- Exit non-zero on first failure; follow pattern of
  `test-protocol-02-portable-parser-guidance.sh`.

**Planted-violation proof (implementation PR evidence)** — required before the
mirror test is considered done:

1. Temporarily remove one rule name from the canonical file (for example delete
   the `Rule 6` heading line) or break a mirror reference in `REVIEW.md`.
2. Run `bash scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`
   and confirm non-zero exit with a message naming the defect.
3. Revert the deliberate defect; re-run the script and confirm exit `0`.
4. Record the failing and passing exit codes in the implementation PR
   description (no need to commit the planted defect).

Wire into existing workflow test aggregator if one lists sibling `test-*.sh`
files under `scripts/development-workflow/tests/` (grep for invocations and add
one line — record exact file in Verification Log during implementation).

---

## Seed Data

Not applicable.

---

## Documentation Updates

- [ ] `AGENTS.md` — add Key Documentation row for `plan-authoring-rigor-rules.md`.
- [ ] `docs/workflow/development-workflow/README.md` — optional one-line pointer
      under plan stage if that index lists stage artifacts (skip if no such
      section exists at implementation time).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror surfaces drift after merge | Med | High | Mirror shell test in CI path via existing workflow test runner |
| Authors put evidence only in PR comments | Med | Med | Protocol 02 + template + blocking REVIEW findings |
| Gate matrix copy introduces typos vs spec | Low | High | Verbatim copy from merged spec; spec reviewer diff in implementation PR |
| Plan PR description record stale vs HEAD | Med | Med | Protocol 02 requires SHA match; REVIEW blocking row Group H |
| Rule 1 external-source inspection burden | Low | Med | Document first-inspection finding field in outcome record; no re-inspect on later rounds per spec |

---

## Implementation Order

1. Create `plan-authoring-rigor-rules.md` with verbatim spec rules + gate matrix.
2. Update `implementation-plan-template.md` evidence sections.
3. Extend Protocol 02 Step 3 guardrails and Document Quality Gate example.
4. Extend `REVIEW.md` backstop checklist.
5. Update `02-review-implementation-plan-protocol.md` pointer.
6. Update tech-lead, implementation-plan-reviewer, and workflow-plan-writer
   mirrors (four agent files + one skill).
7. Add `test-plan-authoring-rigor-mirror.sh`; register in test aggregator if
   present; run planted-violation proof (fail then pass).
8. Update `AGENTS.md` (and README pointer if applicable).
9. Run markdown lint on all touched paths; run mirror test at exit `0`.
10. Execute smoke runbook Scenarios 1–7 on a sample plan PR or dry-run checklist.

**Changelog fragment** (for later feature PR — not on this plan branch):

```markdown
### Added

- **Plan authoring rigor rules** (#1496): Six portable plan-authoring rules, reviewer backstop, and per-rule outcome record on plan pull requests.
```

---

## Acceptance criteria traceability

| Spec group | Plan coverage |
| --- | --- |
| A — Rules stated for both roles | Canonical file + mirror table + agents |
| B — Rule 1 | Canonical Rule 1 text + gate rows |
| C — Rule 2 | Canonical Rule 2 + REVIEW duplicate findings |
| D — Rule 3 | Template + Verification Log guidance |
| E — Rule 4 | Template + REVIEW delegated-claim blocking |
| F — Rule 5 | Template consumer enumeration guidance |
| G — Rule 6 | Canonical Rule 6 author obligation + REVIEW backstop wording |
| H — Outcomes and gate | Outcome record schema + REVIEW + copied gate matrix |

Brief Coverage Matrix objectives: all covered; no Out of Scope deferrals beyond
spec's deliberate rejections (automation, size ceiling, etc.).
