# Parser and Regex Plan Rigor — Implementation Plan

**Spec**: [`1_201-tech-lead-parser-regex-plan-requirements_specs.md`](./1_201-tech-lead-parser-regex-plan-requirements_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/201-tech-lead-parser-regex-plan-requirements.smoke-test.md`](../../../testing/workflow/201-tech-lead-parser-regex-plan-requirements.smoke-test.md)

---

## Summary

**Approach**: Extend the canonical implementation-plan authoring protocol (`02-generate-implementation-plan-protocol.md`) with a clearly labelled **conditional** subsection that applies only when a plan is classified as **parser-risk** (custom scanning, parsing, regex-heavy linting, or structured-text rules). The subsection mandates three reviewer-verifiable elements: concrete edge-case enumeration, a unit-test strategy that maps one or more automated tests per enumerated case, and conditional suppression semantics when inline or directive-based suppression exists. Mirror the same structure as an optional block in `implementation-plan-template.md`, add matching bullets to `REVIEW.md` under the Plan Review Checklist, and align both `tech-lead` agent entrypoints (`.cursor/agents/tech-lead.md` and `.claude/agents/tech-lead.md`) so authors run the classifier before writing Step 3 and cannot silently skip the block on qualifying work.

**Estimated complexity**: S

**Rationale**: All deliverables are prose in existing workflow documents plus two short agent prompt tweaks. No runtime code, migrations, or CI wiring. The only coordination risk is keeping the two tech-lead agent files in sync.

**Dependencies**: None

**Parser-risk note (this item)**: This work item changes workflow documentation only. It does **not** introduce new parser or scanner code, so this plan is **not** required to include the new parser-risk enumeration/test-mapping block for itself — the block is specified for downstream plans that touch parser-risk layers.

---

## Layer-by-Layer Changes

### Shared workflow documentation (protocols / templates / review contract)

- [ ] **`docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md`** — In **Step 3: Write the Implementation Plan** (after the existing "Quality guardrails" bullet list and before the "### Examples" subsection), insert a new top-level subsection titled **"Parser-risk plans: custom parsers, regex, and structured-text scanning"** containing:
  - **Classification (parser-risk)**: Deterministic signals — treat a plan as parser-risk when Layer-by-Layer changes introduce or materially change any of: (a) files under `scripts/lint/`, `scripts/parse/`, or similar conventional tooling directories; (b) new or renamed modules whose filenames suggest lint, parser, scanner, tokenizer, or regex-engine responsibilities (e.g. `*lint*.py`, `*parser*.mjs`, `*scanner*.ts`); (c) explicit description of regex-heavy scanning, structured-text parsing, or rule engines over markdown/code/config/logs. State that if **none** of these apply, the author skips the entire conditional block.
  - **Mandatory when parser-risk — Edge-case enumeration**: Bulleted guidance requiring specific example inputs (not vague "handle edge cases") covering at minimum: boundary-character variants; negative cases (strings that resemble matches but must not match); multiple occurrences on one line; nested or overlapping constructs where relevant; normative-spec flexibility when applicable (e.g. CommonMark closing fence length ≥ opening fence length).
  - **Mandatory when parser-risk — Unit tests**: Require the Testing Strategy to name a concrete unit test file (language appropriate to the repo) and map **at least one automated unit test per enumerated edge case**; state explicitly that smoke-only or manual-only plans are insufficient for parser-risk work.
  - **Conditional — Suppression semantics**: If the feature supports inline or directive-based suppression, require a short subsection naming recognized directives, where they may appear, and how multiple suppressions on one line are interpreted.
  - Cross-reference this spec file path once for traceability (relative link from repo root is acceptable). (AC1, BR in spec)

- [ ] **`docs/ai/development-workflow/templates/implementation-plan-template.md`** — After the existing `## Testing Strategy` section (or within it as a clearly delimited block), add a short **optional** markdown block titled **"Parser-risk addendum (include only when Step 3 classifier applies)"** with placeholder headings: Edge-case enumeration; Unit test mapping; Suppression semantics (if applicable). Each heading should restate in one line what must appear so template users mirror protocol language without duplicating the full protocol text. (AC1, AC4 discoverability)

- [ ] **`REVIEW.md`** — Under **## Plan Review Checklist** / **Check:**, add a compact bullet group **"Parser-risk completeness (when the plan triggers parser-risk signals per protocol 02 Step 3)"** that requires reviewers to verify: (1) edge-case enumeration present and concrete; (2) unit test file named with per-case mapping; (3) suppression subsection present when suppressions exist. (AC3)

- [ ] **`.cursor/agents/tech-lead.md`** — After the existing paragraph that points to protocol `02-generate-implementation-plan-protocol.md`, add 2–3 sentences: before finishing Step 3, classify parser-risk using the same deterministic signals as protocol 02; when parser-risk applies, include the mandatory subsections before deep Layer-by-Layer file walkthroughs; when suppression exists, document semantics. Keep front matter intact. (AC2)

- [ ] **`.claude/agents/tech-lead.md`** — Apply the **identical** addition as `.cursor/agents/tech-lead.md` (dual-agent sync). (AC2)

---

## Testing Strategy

**Test types**: Manual / smoke (document inspection after implementation PR merges — no automated test harness for markdown policy text in MVP per spec out-of-scope)

**Key scenarios to test**:

1. Protocol 02 Step 3 contains the parser-risk subsection with classifier + three mandatory elements + conditional suppression — maps to AC1 and spec BR
2. Implementation-plan template contains the optional parser-risk addendum — maps to AC1
3. `REVIEW.md` plan checklist references the three elements for parser-risk plans — maps to AC3
4. Both tech-lead agent files reference classification and mandatory subsections — maps to AC2
5. Both tech-lead files stay text-identical in the new guidance — dual-agent rule
6. A reader can derive an acceptable outline for a hypothetical markdown-lint feature from protocol + template alone — maps to AC4 (validated via smoke runbook walkthrough)

**Smoke test runbook**: [`../../../testing/workflow/201-tech-lead-parser-regex-plan-requirements.smoke-test.md`](../../../testing/workflow/201-tech-lead-parser-regex-plan-requirements.smoke-test.md)

---

## Seed Data

None — documentation-only change.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — primary deliverable (see Layer-by-Layer)
- [ ] `docs/ai/development-workflow/templates/implementation-plan-template.md` — parser-risk addendum (see Layer-by-Layer)
- [ ] `REVIEW.md` — plan review checklist (see Layer-by-Layer)
- [ ] `.cursor/agents/tech-lead.md` — author guidance (see Layer-by-Layer)
- [ ] `.claude/agents/tech-lead.md` — author guidance (see Layer-by-Layer)
- [ ] `CHANGELOG.md` — add `[Unreleased]` entry under **Documentation** (or **Changed**) describing the parser-risk plan requirements for issue #201

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Heuristic path/filename signals miss a legitimate parser-risk change | Med | Med | Keep signals as inclusive disjunction; prefer false-positive (author includes block) over false-negative; encourage "when in doubt, treat as parser-risk" one-liner in protocol |
| Reviewers disagree on whether a plan is parser-risk | Low | Low | Deterministic bullet list in protocol + same list summarized in `REVIEW.md` |
| `.cursor` vs `.claude` tech-lead files drift | Low | Med | Single edit pass touching both files; smoke runbook includes byte-level identity check for the new paragraph |

---

## Implementation Order

1. Amend `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — add the full Step 3 parser-risk subsection (classification + three elements + suppression + spec cross-link).
2. Update `docs/ai/development-workflow/templates/implementation-plan-template.md` — add the optional parser-risk addendum block.
3. Extend `REVIEW.md` — add parser-risk bullets under Plan Review Checklist.
4. Update `.cursor/agents/tech-lead.md` and `.claude/agents/tech-lead.md` — add identical classifier guidance after the protocol pointer.
5. Update `CHANGELOG.md` under `[Unreleased]` for issue #201.
6. Run the smoke test runbook mentally or locally on the implementation branch before opening the implementation PR.
