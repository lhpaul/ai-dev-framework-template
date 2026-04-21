# Smoke Test Runbook: Parser and Regex Plan Rigor

**Feature**: Parser and regex plan rigor (issue #201)
**Spec**: [`docs/specs/developments/20260420120000_201-tech-lead-parser-regex-plan-requirements/1_201-tech-lead-parser-regex-plan-requirements_specs.md`](../../specs/developments/20260420120000_201-tech-lead-parser-regex-plan-requirements/1_201-tech-lead-parser-regex-plan-requirements_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR for issue #201 has been merged into `develop`
- [ ] You have a local clone of the repository on the `develop` branch

---

## Test Data

| Item | Value |
|---|---|
| Protocol 02 path | `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Plan template path | `docs/ai/development-workflow/templates/implementation-plan-template.md` |
| Review contract path | `REVIEW.md` |
| Cursor tech-lead agent | `.cursor/agents/tech-lead.md` |
| Claude tech-lead agent | `.claude/agents/tech-lead.md` |

---

## Smoke Test Steps

### Step 1: Protocol 02 parser-risk subsection (AC1)

**Maps to**: Acceptance criterion — conditional block with three mandatory elements

1. Open `docs/ai/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
2. Locate Step 3 and the subsection for parser-risk / custom text scanning

**Expected result**:

- A **classification** section lists deterministic signals (conventional tooling paths, filename heuristics, or explicit scanning/parsing description) and states that authors skip the block when none apply
- When parser-risk applies, the protocol requires **edge-case enumeration** with the minimum coverage called out in the spec (boundaries, negatives, multiples per line, nesting/overlap where relevant, spec flexibility)
- When parser-risk applies, the protocol requires **unit test mapping** (concrete test file + at least one automated unit test per enumerated case; smoke/manual-only called out as insufficient)
- When suppressions exist, **suppression semantics** are mandatory (directives, placement, multiple per line)

### Step 2: Plan template addendum (AC1, AC4)

**Maps to**: Acceptance criterion — template supports deriving an outline

1. Open `docs/ai/development-workflow/templates/implementation-plan-template.md`
2. Find the optional parser-risk addendum

**Expected result**:

- Headings or short prompts exist for edge cases, unit test mapping, and conditional suppression
- Text clearly states the addendum is included only when the Step 3 classifier applies

### Step 3: Plan review checklist (AC3)

**Maps to**: Acceptance criterion — reviewers can reject incomplete parser-risk plans

1. Open `REVIEW.md` → **Plan Review Checklist**
2. Locate the parser-risk bullet group

**Expected result**:

- Checklist explicitly references edge-case enumeration, unit test file + per-case mapping, and suppression semantics when applicable
- Wording aligns with protocol 02 so reviewers do not need undocumented rules

### Step 4: Tech-lead agent guidance (AC2)

**Maps to**: Acceptance criterion — tech-lead detects parser-risk

1. Open `.cursor/agents/tech-lead.md` and read the paragraph after the protocol pointer
2. Open `.claude/agents/tech-lead.md` and compare the same section

**Expected result**:

- Both files instruct the author to classify parser-risk before finishing Step 3 using the same signals as protocol 02
- Both files require the mandatory subsections when parser-risk applies
- The new guidance text is identical between the two files

### Step 5: Hypothetical markdown-lint outline (AC4)

**Maps to**: Acceptance criterion — reader can outline a markdown-lint-style feature without undocumented rules

1. Using only protocol 02 Step 3 and the plan template addendum (no other internal docs), sketch a bullet outline for "add GLOB002 heuristic to `scripts/lint/foo-lint.py`"
2. Verify your outline naturally includes edge-case bullets, a named unit test file with case IDs, and (if suppressions exist) a suppression paragraph

**Expected result**:

- You can complete the outline without inventing requirements absent from those two sources

---

## Rollback

Revert the merge commit for the implementation PR or restore the five files above from the parent revision if the change must be backed out.
