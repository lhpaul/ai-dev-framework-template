# Smoke Test Runbook: Remove 'Guiding Principle' Section from Spec Template

**Feature**: Remove boilerplate 'Guiding principle' section from spec template
**Spec**: [`docs/specs/developments/20260416200000_165-remove-guiding-principle-from-spec-template/1_165-remove-guiding-principle-from-spec-template_specs.md`](../../specs/developments/20260416200000_165-remove-guiding-principle-from-spec-template/1_165-remove-guiding-principle-from-spec-template_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The feature branch has been merged into `develop` (or is checked out locally)
- [ ] You have file read access to the repository

---

## Test Data

| Item | Value |
|---|---|
| Spec template | `docs/workflow/development-workflow/templates/spec-template.md` |
| Spec generation protocol | `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` |
| Review contract | `REVIEW.md` |
| Retrospective spec | `docs/specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md` |
| Batch merge spec | `docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md` |
| Shellcheck spec | `docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md` |
| Agent timeout spec | `docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md` |
| Batch merge FF pull retry spec | `docs/specs/developments/20260416120000_batch-merge-ff-pull-retry/1_batch-merge-ff-pull-retry_specs.md` |
| CodeRabbit success fallback spec | `docs/specs/developments/20260416120000_coderabbit-success-fallback/1_coderabbit-success-fallback_specs.md` |
| Markdown lint plan spec docs spec | `docs/specs/developments/20260416180000_173-markdown-lint-plan-spec-docs/1_173-markdown-lint-plan-spec-docs_specs.md` |

---

## Smoke Test Steps

### Step 1: Verify spec template no longer contains "Guiding principle" section

**Maps to**: Acceptance Criterion 1

1. Open `docs/workflow/development-workflow/templates/spec-template.md`.
2. Search for the text `Guiding principle`.
3. Search for the text `product-focused`.

**Expected result**: The string `Guiding principle` is not present. The template begins with the `## Overview` section (or `## Depends on`) immediately after the title line.

---

### Step 2: Verify authoring guidance is present in the spec generation protocol

**Maps to**: Acceptance Criterion 2

1. Open `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`.
2. Search for guidance that instructs spec authors to write product-focused content and avoid implementation details.

**Expected result**: The file contains a section (e.g., "Product-first boundary (critical)") that instructs authors to write user-facing behavior and avoid implementation details such as database tables, endpoints, file paths, or class names.

---

### Step 3: Verify REVIEW.md spec checklist does not require the "Guiding principle" section

**Maps to**: Acceptance Criterion 3

1. Open `REVIEW.md`.
2. Search for the text `Guiding principle`.
3. Read the "Spec Review Checklist" section.

**Expected result**: The string `Guiding principle` is not present in `REVIEW.md`. The spec checklist checks that the spec does not contain implementation details (table names, endpoints, file paths, class names, migration design) — it does not require the presence of a named boilerplate section.

---

### Step 4: Verify all existing spec files no longer contain "Guiding principle" section

**Maps to**: Acceptance Criterion 4 and spec Business Rule (all merged spec files must be updated)

For each of the following files:
- `docs/specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md`
- `docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md`
- `docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md`
- `docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md`
- `docs/specs/developments/20260416120000_batch-merge-ff-pull-retry/1_batch-merge-ff-pull-retry_specs.md`
- `docs/specs/developments/20260416120000_coderabbit-success-fallback/1_coderabbit-success-fallback_specs.md`
- `docs/specs/developments/20260416180000_173-markdown-lint-plan-spec-docs/1_173-markdown-lint-plan-spec-docs_specs.md`

1. Open the file.
2. Search for the text `Guiding principle`.
3. Verify the remaining content (Overview, Use Cases, Business Rules, Acceptance Criteria, etc.) is intact.

**Expected result**: The string `Guiding principle` is not present in any of the 7 files. All other spec content is unmodified.

---

### Last Step: Validate all assertions

- Verify all checkboxes in the Assertions Checklist below are met.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] `docs/workflow/development-workflow/templates/spec-template.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` contains product-focused authoring guidance (verbatim or equivalent).
- [ ] `REVIEW.md` spec checklist does not require the "Guiding principle" section; instead it checks that specs avoid implementation details.
- [ ] `docs/specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/specs/developments/20260416120000_batch-merge-ff-pull-retry/1_batch-merge-ff-pull-retry_specs.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/specs/developments/20260416120000_coderabbit-success-fallback/1_coderabbit-success-fallback_specs.md` does not contain the "Guiding principle (important)" section.
- [ ] `docs/specs/developments/20260416180000_173-markdown-lint-plan-spec-docs/1_173-markdown-lint-plan-spec-docs_specs.md` does not contain the "Guiding principle (important)" section.

---

## Seed Data Reference

None — this feature affects documentation files only.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Guiding principle` still appears in a spec file | The file was not updated during implementation | Edit the file and remove the section |
| Remaining spec content appears truncated or garbled | Incorrect deletion during implementation removed too many lines | Restore from git history and redo the removal carefully |

---

## Known Limitations

- This smoke test is entirely manual (file inspection). No automated test runner is available for Markdown content structure verification.
