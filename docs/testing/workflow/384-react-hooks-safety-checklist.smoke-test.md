# Smoke Test Runbook: React Hooks Safety Checklist

**Feature**: React Hooks Safety Checklist for React / React Native Implementation Plans
**Spec**: [docs/specs/developments/20260428141908_react-hooks-safety-checklist/1_react-hooks-safety-checklist_specs.md](../../specs/developments/20260428141908_react-hooks-safety-checklist/1_react-hooks-safety-checklist_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR has been merged to `develop`
- [ ] You have local copies of `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` and `REVIEW.md` at the merged revision
- [ ] No application runtime is required — this is a documentation-only change

---

## Test Data

| Item | Value |
|---|---|
| Target protocol file | `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` |
| Target review file | `REVIEW.md` |
| Issue number | `#384` |

---

## Smoke Test Steps

### Step 1: Verify `02-generate-implementation-plan-protocol.md` contains the React Hooks Safety section

**Maps to**: AC-1, AC-2, AC-3, BR-1, BR-4

1. Open `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`.
2. Search for "React Hooks Safety".
3. Confirm a clearly titled conditional section is present (e.g., "### React Hooks Safety Checklist plans: React / React Native state, effects, or async operations" or equivalent).
4. Confirm the section includes an explicit activation condition that references React / React Native component state, effects, or async operations.
5. Confirm all six checklist items are present:
   - `useEffect` dependency arrays
   - Cleanup in async effects
   - Input component stability
   - Async form submit ordering
   - Exclusion parameters in validators
   - Design token imports
6. Confirm each checklist item includes a plain-language description of the failure mode it prevents (one or two sentences).

**Expected result**: The section is present, has a clear activation condition, lists all six items, and each item describes its failure mode.

---

### Step 2: Verify activation condition is stated in one sentence

**Maps to**: AC-1, UX Rules

1. In the React Hooks Safety section of `02-generate-implementation-plan-protocol.md`, read the opening sentence of the activation condition.
2. Confirm a reader can determine from that single sentence whether the section applies to their plan without needing to read additional context.

**Expected result**: The activation condition is unambiguous in one sentence.

---

### Step 3: Verify `REVIEW.md` Plan Review Checklist contains the React Hooks Safety block

**Maps to**: AC-4, BR-1, BR-3

1. Open `REVIEW.md`.
2. Navigate to the "Plan Review Checklist" section.
3. Search for "React Hooks Safety" or "React / React Native".
4. Confirm a conditional block is present in the Plan Review section.
5. Confirm the activation condition is stated (when to apply).
6. Confirm all six checklist item concerns are listed.
7. Confirm the block mentions that individual items may be marked "not applicable" only with a brief rationale (BR-3).

**Expected result**: A conditional block covering all six items is present in the Plan Review section.

---

### Step 4: Verify `REVIEW.md` Code Review Checklist contains the React Hooks Safety block

**Maps to**: AC-5, BR-1

1. In `REVIEW.md`, navigate to the "Code Review Checklist" section.
2. Search for "React Hooks Safety" or "Additional checks for React / React Native".
3. Confirm a conditional block is present in the Code Review section.
4. Confirm all six checklist item concerns are represented.

**Expected result**: A conditional block covering all six items is present in the Code Review section.

---

### Step 5: Verify consistent formatting with existing conditional blocks

**Maps to**: AC-6

1. In `REVIEW.md`, compare the React Hooks Safety block in the Plan Review section with adjacent conditional blocks (e.g., the parser-risk or concurrent-event-source blocks).
2. Confirm the formatting style (heading level, bullet format, condition statement) is consistent.
3. In `02-generate-implementation-plan-protocol.md`, compare the React Hooks Safety block with the adjacent "Concurrent-event-source plans" block.
4. Confirm the formatting style (classification paragraph, sub-sections, checklist item format) is consistent.

**Expected result**: New blocks match the style and structure of adjacent conditional blocks.

---

### Step 6: Verify scope compliance (BR-5)

**Maps to**: BR-5, AC-7

1. From the repository root, run:
   ```bash
   git log --oneline -5
   git show --name-only HEAD
   ```
2. Confirm the implementation commit modifies only `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`, `REVIEW.md`, and `CHANGELOG.md`.
3. Confirm no agent files (`.claude/agents/`, `.cursor/agents/`, `.codex/skills/`) were modified.

**Expected result**: Exactly three files are modified.

---

### Step 7: Verify CHANGELOG entry

**Maps to**: AC-8

1. Open `CHANGELOG.md`.
2. Navigate to the `[Unreleased]` section.
3. Confirm an entry exists for issue #384 describing the React Hooks Safety checklist addition.
4. Confirm the entry uses the `**Bold Title** (#N):` format.

**Expected result**: Entry is present, correctly formatted, and references #384.

---

## Assertions Checklist

- [ ] AC-1: `02-generate-implementation-plan-protocol.md` contains a "React Hooks Safety Checklist" conditional section with explicit activation condition
- [ ] AC-2: The section in `02-generate-implementation-plan-protocol.md` includes all six checklist items from BR-4
- [ ] AC-3: Each checklist item states the failure mode it prevents in plain language
- [ ] AC-4: `REVIEW.md` Plan Review section contains a conditional React Hooks Safety block with all six items
- [ ] AC-5: `REVIEW.md` Code Review section contains a conditional React Hooks Safety block with all six items
- [ ] AC-6: Both `REVIEW.md` additions are formatted consistently with existing conditional blocks
- [ ] AC-7 (BR-5): No files other than `02-generate-implementation-plan-protocol.md`, `REVIEW.md`, and `CHANGELOG.md` were modified
- [ ] AC-8: CHANGELOG entry present under `[Unreleased]` using `**Bold Title** (#N):` format

---

## Seed Data Reference

None required — documentation-only change.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| React Hooks Safety section not found in `02-generate-implementation-plan-protocol.md` | PR not yet merged, or wrong file revision | Confirm you are on `develop` after merge; run `git pull` |
| Only one of Plan Review / Code Review blocks present in `REVIEW.md` | Implementation missed one block | Re-read AC-4 and AC-5; open a fix PR |
| Formatting inconsistent | Indentation or heading level mismatch | Compare heading levels with adjacent blocks; file a fix |

---

## Known Limitations

- This smoke test validates documentation content by inspection only. There is no automated test that verifies the checklist is actually followed during plan writing.
