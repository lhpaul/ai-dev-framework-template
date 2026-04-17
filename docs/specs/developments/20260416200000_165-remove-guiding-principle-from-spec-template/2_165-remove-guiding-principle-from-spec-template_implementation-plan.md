# Remove Boilerplate 'Guiding Principle' Section from Spec Template — Implementation Plan

**Spec**: [`1_165-remove-guiding-principle-from-spec-template_specs.md`](1_165-remove-guiding-principle-from-spec-template_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/165-remove-guiding-principle-from-spec-template.smoke-test.md`](../../../../testing/workflow/165-remove-guiding-principle-from-spec-template.smoke-test.md)

---

## Summary

**Approach**: Remove the "Guiding principle (important)" section from the spec template and all 4 existing merged spec files that still contain it. Verify that the product-focused authoring guidance is already present (in equivalent form) in `01-generate-spec-protocol.md` — it is (the "Product-first boundary" section), so no additions are needed there. Confirm `REVIEW.md`'s spec checklist already checks implementation-detail cleanliness rather than the presence of a named boilerplate section — it does, so no changes are needed there.

**Estimated complexity**: S
<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->
**Rationale**: All changes are mechanical find-and-delete operations on Markdown files. No code, no configuration, no tests, no schema changes. The guidance is already present in `01-generate-spec-protocol.md` and `REVIEW.md` requires no update.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Documentation / Template Files

- [ ] Remove the "Guiding principle (important)" section (lines 7–14 in the current template) from `docs/ai/development-workflow/templates/spec-template.md`.
- [ ] Remove the "Guiding principle (important)" section from `docs/specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md`.
- [ ] Remove the "Guiding principle (important)" section from `docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md`.
- [ ] Remove the "Guiding principle (important)" section from `docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md`.
- [ ] Remove the "Guiding principle (important)" section from `docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md`.
- [ ] Confirm (read-only verification, no edit needed) that `docs/ai/development-workflow/protocols/01-generate-spec-protocol.md` already contains equivalent product-focused authoring guidance under the "Product-first boundary (critical)" section.
- [ ] Confirm (read-only verification, no edit needed) that `REVIEW.md` spec checklist checks implementation-detail cleanliness on substance, not on the presence of a named section.

### Infrastructure / Configuration

_(No changes required)_

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:
1. Open `spec-template.md` and verify the "Guiding principle (important)" section is absent — maps to Acceptance Criterion 1.
2. Open `01-generate-spec-protocol.md` and verify the product-focused authoring guidance is present — maps to Acceptance Criterion 2.
3. Open `REVIEW.md` and verify the spec checklist enforces implementation-detail cleanliness, not the presence of a boilerplate section — maps to Acceptance Criterion 3.
4. Open each of the 4 existing spec files and verify the "Guiding principle (important)" section has been removed — maps to Acceptance Criterion 4.

**Smoke test runbook**: [`docs/testing/workflow/165-remove-guiding-principle-from-spec-template.smoke-test.md`](../../../../testing/workflow/165-remove-guiding-principle-from-spec-template.smoke-test.md)

**Regression suite**: No automated regression suite exists in this repository for documentation changes.

---

## Seed Data

None — this feature affects documentation files only.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/templates/spec-template.md` — remove the "Guiding principle (important)" section (this is the primary deliverable, not a secondary doc update).

All other doc changes in this plan are the primary deliverable (removing the boilerplate from existing spec files). No separate documentation updates are required beyond what is listed in the Layer-by-Layer Changes section above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A spec file lists content immediately after the "Guiding principle" section with no blank line separator, causing the wrong lines to be deleted | Low | Low | Read each file before editing; remove only the section header and its body bullets, verify surrounding content is intact |
| A future spec author or agent re-adds the "Guiding principle" section because they are copying from a cached/stale template | Low | Low | The spec review gate in `REVIEW.md` does not require the section; automated reviewers will not flag its absence — adding it back would be neutral noise, not a broken workflow |

---

## Implementation Order

1. Read `docs/ai/development-workflow/templates/spec-template.md` — locate and delete the "Guiding principle (important)" section (the `## Guiding principle (important)` heading and its 4-line body, including the surrounding blank lines).
2. Repeat the same deletion for the 4 existing spec files:
   a. `docs/specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md`
   b. `docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md`
   c. `docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md`
   d. `docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md`
3. Verify `01-generate-spec-protocol.md` already has the product-focused boundary guidance (read-only check; no edits expected).
4. Verify `REVIEW.md` spec checklist does not require the "Guiding principle" section (read-only check; no edits expected).
5. Run the smoke test runbook manually to confirm all acceptance criteria pass.
6. Update CHANGELOG under `[Unreleased]`.
