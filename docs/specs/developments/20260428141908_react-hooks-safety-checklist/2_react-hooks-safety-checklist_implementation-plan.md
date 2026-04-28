# React Hooks Safety Checklist — Implementation Plan

**Spec**: [React Hooks Safety Checklist Spec](1_react-hooks-safety-checklist_specs.md)
**Smoke test runbook**: [docs/testing/workflow/384-react-hooks-safety-checklist.smoke-test.md](../../../../docs/testing/workflow/384-react-hooks-safety-checklist.smoke-test.md)

---

## Summary

**Approach**: Insert a new conditional section titled "React Hooks Safety Checklist" into the existing conditional-guidance block area of `02-generate-implementation-plan-protocol.md` Step 3, and add corresponding conditional blocks to the Plan Review and Code Review checklists in `REVIEW.md`. No new files are created and no scripts or agent files are modified; the change is purely additive documentation edits to two protocol files and one CHANGELOG entry.

**Estimated complexity**: S

**Rationale**: Three documentation files are edited with additive text blocks. There is no code generation, no configuration change, and no dependency on external services. The content is predetermined by the spec's six checklist items.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `8375405` |
| Conditional guidance blocks in `02-generate-implementation-plan-protocol.md` | `grep -n "### " docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Lines 109 "parser-risk plans", 139 "cross-cutting checklist plans", 171 "concurrent-event-source plans", 195 "Examples" |
| Plan Review Checklist conditional blocks in `REVIEW.md` | `grep -n "Parser-risk\|concurrent-event-source\|Cross-cutting" REVIEW.md` | Lines 93, 100, 103 — three existing conditional blocks in Plan Review |
| Code Review conditional blocks in `REVIEW.md` | `grep -n "concurrent event sources\|Additional checks" REVIEW.md` | Lines 152, 143 — two existing "Additional checks" blocks in Code Review |
| Files referenced by spec BR-5 | manual cross-check against spec | `02-generate-implementation-plan-protocol.md`, `REVIEW.md`, `CHANGELOG.md` — exactly 3 files |

---

## Layer-by-Layer Changes

### Workflow Documentation

- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — add "React Hooks Safety Checklist" conditional guidance block in Step 3, after the "Concurrent-event-source plans" block and before the "Examples" heading (AC-1, AC-2, AC-3, BR-1 through BR-4)
- [ ] `REVIEW.md` — add conditional React Hooks Safety block in "Plan Review Checklist" section (AC-4, BR-1, BR-3); add conditional React Hooks Safety block in "Code Review Checklist" section under "Additional checks" (AC-5, BR-1); both blocks formatted consistently with existing conditional patterns (AC-6)
- [ ] `CHANGELOG.md` — add entry under `[Unreleased]` in the `### Added` section

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. React / React Native plan — activation condition met (maps to AC-1, AC-2, AC-3, BR-1, BR-2)
2. Non-React plan — activation condition not met (maps to BR-1)
3. Plan reviewer reads `REVIEW.md` for a React plan (maps to AC-4, BR-3)
4. Code reviewer reads `REVIEW.md` for a React implementation PR (maps to AC-5, BR-3)
5. "Not applicable" item opt-out with rationale accepted (maps to BR-3)
6. BR-5 scope compliance — only the three designated files are modified

**Smoke test runbook**: `docs/testing/workflow/384-react-hooks-safety-checklist.smoke-test.md`

---

## Seed Data

None — this is a documentation-only change with no runtime data requirements.

---

## Documentation Updates

None — the files modified by this feature (`02-generate-implementation-plan-protocol.md` and `REVIEW.md`) are workflow documentation files, not project documentation files in `docs/project/` or `AGENTS.md`. No separate documentation update pass is needed.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Inserted block breaks existing markdown rendering (heading levels, fencing) | Low | Low | Run `markdownlint-cli2` pre-commit; verify heading hierarchy matches adjacent blocks |
| React Hooks block placed in wrong location in `02-generate-implementation-plan-protocol.md` | Low | Medium | Place immediately after the "concurrent-event-source plans" block, before the "### Examples" heading — confirmed by Verification Log line counts |
| `REVIEW.md` Plan Review insertion in wrong location | Low | Low | Place after the "Cross-cutting checklist completeness" block, before "Documentation updates" line — confirmed by Verification Log |
| Checklist items reference undefined terms or failure modes not in spec | Low | Medium | Derive each item description word-for-word from spec BR-4 and issue #384 failure modes |

---

## Implementation Order

1. **Edit `02-generate-implementation-plan-protocol.md`** — insert the "React Hooks Safety Checklist" conditional guidance block immediately after the "Concurrent-event-source plans" block (after the closing text of that block, before the `### Examples` heading). The block must follow the same structural pattern as adjacent blocks:
   - Opening paragraph classifying when the block applies
   - Classification sub-section listing the activation signals
   - Mandatory guidance sub-section with the six checklist items, each including the failure mode prevented
   - Verify: open the file and confirm the six items are present with failure mode descriptions; confirm heading level `###` matches adjacent guidance blocks; confirm placement is after the concurrent-event-source block.

2. **Edit `REVIEW.md` Plan Review section** — insert a conditional React Hooks Safety block after the existing "Cross-cutting checklist completeness" block in the Plan Review Checklist. The block should follow the same conditional pattern as the existing plan review blocks (plain-language condition statement followed by bullet list). Include all six checklist items and the "not applicable with rationale" opt-out rule. Verify: open `REVIEW.md` and confirm the block appears in the Plan Review section (between the cross-cutting checklist block and the "Documentation updates" line); confirm formatting matches existing conditional blocks.

3. **Edit `REVIEW.md` Code Review section** — insert a conditional React Hooks Safety block as a new "Additional checks for React / React Native components" subsection in the Code Review Checklist, after the existing "Additional checks for features with concurrent event sources" block. Follow the same "Additional checks for..." format as the concurrent-event-source block. Include all six checklist items in reviewer-verb form. Verify: open `REVIEW.md` and confirm the new block appears in the Code Review section after the concurrent-event-source block; confirm formatting matches adjacent "Additional checks for..." blocks.

4. **Run pre-commit lint check** on both modified protocol files:
   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md" \
     "REVIEW.md"
   ```
   Fix any reported violations before committing.

5. **Update `CHANGELOG.md`** — add the following entry under `[Unreleased]` in the `### Added` section (create the `### Added` subsection if it does not exist under `[Unreleased]`):
   ```
   - **React Hooks Safety checklist for React / React Native plans** (#384): Added a conditional "React Hooks Safety Checklist" section to `02-generate-implementation-plan-protocol.md` covering six concern areas (useEffect dependency arrays, async effect cleanup, input component stability, async form submit ordering, exclusion parameters in validators, and design token imports). Added corresponding conditional reviewer blocks to the Plan Review and Code Review checklists in `REVIEW.md`.
   ```

6. **Verify scope compliance (BR-5)** — run `git diff --name-only` and confirm only `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`, `REVIEW.md`, and `CHANGELOG.md` appear in the diff.

7. **Commit and push**: `git add` the three files, commit with message `docs: add React Hooks Safety checklist to plan protocol and REVIEW.md (#384)`, push to `implementation-plan/384-react-hooks-safety-checklist`.
