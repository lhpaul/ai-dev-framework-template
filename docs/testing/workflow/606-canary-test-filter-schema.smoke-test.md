# Smoke Test Runbook: Canary Test Requirement for Filter-Schema Additions

**Feature**: Canary test requirement for filter-schema additions (#606)
**Spec**: [Spec](../../specs/developments/20260518000000_606-canary-test-filter-schema/1_606-canary-test-filter-schema_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation PR is merged to `develop`
- [ ] You have read access to the repository

---

## Test Data

| Item | Value |
| --- | --- |
| Protocol 03 file | `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` |
| REVIEW.md file | `REVIEW.md` |
| Testing best-practices file | `docs/best-practices/3-testing.md` |
| Claude Code developer agent | `.claude/agents/developer.md` |
| Cursor developer agent | `.cursor/agents/developer.md` |

---

## Smoke Test Steps

### Step 1: Verify protocol 03 — Filter-Schema Canary Test Checklist

**Maps to**: Acceptance Criterion 1 (AC-1)

1. Open `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
2. Search for "Filter-Schema Canary Test" (or equivalent heading).
3. Confirm a conditional checklist section exists that fires when a PR adds a new filter parameter to a tool schema.
4. Confirm the checklist includes: a canary test for each new filter, two-invocation pattern (filter set vs. absent/different), assertion that result sets differ, same-PR inclusion requirement, and the exemption for modifications to existing filters.
5. Confirm each path's verify step (Full Pipeline Step 5, Refactor Step 5, Fast Track Step 4/5, Hotfix Step 5) contains a cross-reference to this section.

**Expected result**: The section exists once, all checklist items are present, and all verify steps reference it.

### Step 2: Verify REVIEW.md — blocking code-review check

**Maps to**: Acceptance Criterion 2 (AC-2)

1. Open `REVIEW.md`.
2. Navigate to "Pass 2: Code Quality" in the Code Review Checklist.
3. Search for filter-schema or canary-test language in the additional checks.
4. Confirm a dedicated block exists for PRs that add new filter parameters to a tool schema.
5. Confirm the block covers: filter-wiring verification, canary test presence, same-PR inclusion, and the exemption.
6. Confirm the check is described as a typical `blocking` issue (listed under "Typical `blocking` issues" or equivalent).

**Expected result**: The blocking check block exists in Pass 2, covers all four points.

### Step 3: Verify testing best-practices — canary test rule

**Maps to**: Acceptance Criterion 3 (AC-3)

1. Open `docs/best-practices/3-testing.md`.
2. Search for "Filter-Schema Canary Tests" (or equivalent section heading).
3. Confirm a section exists describing the canary test rule.
4. Confirm the three-step pattern is present: call with filter set → call with filter absent/different → assert results differ.
5. Confirm a rationale is provided (silent no-op risk).
6. Confirm the exemption for modifications to existing filters is stated.
7. Confirm the rule is described as framework-agnostic.

**Expected result**: Section exists with all required elements.

### Step 4: Verify two-invocation-plus-assertion pattern is framework-agnostic

**Maps to**: Acceptance Criterion 4 (AC-4)

1. In any of the three files checked above, confirm the rule describes the pattern in terms of behavior (two invocations, differing results) without prescribing a specific test framework, assertion library, or test-file naming convention.
2. Confirm the exemption text matches BR-7: modifications to existing filters that do not change the schema contract are exempt.

**Expected result**: Framework-agnostic language confirmed; no specific tool or library required.

### Step 5: Verify developer agent files are consistent

**Maps to**: Acceptance Criterion 1 (AC-1) — agent guidance consistency

1. Open `.claude/agents/developer.md`.
2. In the "Key rules:" list, confirm a bullet describing the canary-test obligation for filter-schema additions is present.
3. Open `.cursor/agents/developer.md`.
4. Confirm the same bullet is present with identical or equivalent text.

**Expected result**: Both agent files have the canary-test key rule.

### Step 6: Confirm blocking enforcement is explicit

**Maps to**: Acceptance Criterion 5 (AC-5)

1. In `REVIEW.md`, confirm the canary-test check is categorized as a typical `blocking` finding (not `important` or `suggestion`).
2. Confirm that protocol 03's checklist makes clear that a missing canary test prevents opening the PR (or must be resolved before the PR is merged).

**Expected result**: Blocking language is explicit in REVIEW.md; protocol 03 treats the missing check as a gate, not a recommendation.

---

## Assertions Checklist

- [ ] Protocol 03 contains a "Filter-Schema Canary Test" conditional checklist section present before Path 1 (AC-1)
- [ ] Each path's verify step in protocol 03 cross-references the canary-test section (AC-1)
- [ ] `REVIEW.md` Pass 2 contains a blocking check for filter-schema canary tests (AC-2)
- [ ] `docs/best-practices/3-testing.md` contains a Filter-Schema Canary Tests section with the three-step pattern (AC-3)
- [ ] All files describe the rule in framework-agnostic terms (AC-4)
- [ ] Blocking enforcement language is explicit in REVIEW.md (AC-5)
- [ ] The exemption for modifications to existing filters is stated in all relevant documents (AC-6, BR-7)
- [ ] `.claude/agents/developer.md` has the canary-test key rule bullet (consistency)
- [ ] `.cursor/agents/developer.md` has the canary-test key rule bullet (consistency)

---

## Seed Data Reference

None — documentation-only change. No application seed data required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Section heading not found in protocol 03 | Implementation step 1 was missed or incorrectly placed | Search for "canary" in the file; verify placement after Test Harness Coverage Checklist |
| REVIEW.md check is listed as `important` not `blocking` | Wrong severity applied | Update to list under "Typical `blocking` issues" |
| Agent files inconsistent | One was updated and the other was not | Compare the two files and sync the canary-test bullet |

---

## Known Limitations

- This smoke test verifies documentation content only — it cannot test runtime enforcement in a live project. Verification that downstream projects adopt the rule is out of scope for this runbook.
