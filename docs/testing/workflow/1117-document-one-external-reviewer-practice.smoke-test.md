# Smoke Test Runbook: One External Reviewer Practice

**Feature**: One external reviewer practice
**Spec**: [1_1117-document-one-external-reviewer-practice_specs.md](../../specs/developments/20260702121239_1117-document-one-external-reviewer-practice/1_1117-document-one-external-reviewer-practice_specs.md)
**Created in**: Plan Ready stage
**Updated in**: Plan Ready stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for #1117.
- [ ] Repository dependencies required for shell tests are installed.
- [ ] `gh`, `jq`, `python3`, and `npx` are available.

## Test Data

No application seed data is required.

Use temporary workflow config fixtures created by
`scripts/development-workflow/tests/test-workflow-config-resolver.sh`.

## Smoke Test Steps

### Step 1: Verify Documentation Recommendation

**Maps to**: AC-1, AC-2, AC-3, AC-5

1. Open `docs/workflow/development-workflow/integrations/pr-review-platform.md`.
2. Confirm it recommends one external automated reviewer per repository or
   product plus internal runner review as the default pattern.
3. Confirm it describes multi-bot external review as advanced usage.
4. Confirm it names cost, latency, duplicated findings, and conflicting advice
   as trade-offs.
5. Open `docs/workflow/development-workflow/README.md` and
   `docs/workflow/development-workflow/repository-modes.md`.
6. Confirm both files point maintainers to the same recommendation without
   contradicting the canonical guidance.

**Expected result**: The docs consistently recommend one external reviewer by
default while preserving multi-bot support as advanced usage.

### Step 2: Verify Non-Blocking Warning Behavior

**Maps to**: AC-4, AC-5

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   ```

2. Confirm the test output includes passing coverage for:
   - a single-reviewer config with no warning,
   - multiple draft reviewers with a warning and success exit,
   - multiple ready reviewers with a warning and success exit.

**Expected result**: Multi-reviewer configurations remain valid and produce only
non-blocking warnings.

### Step 3: Verify Repository Config Validation

**Maps to**: AC-4, AC-5

1. Run:

   ```bash
   bash scripts/development-workflow/validate-workflow-config.sh
   ```

2. Confirm the command exits successfully.

**Expected result**: The repository's current workflow configuration remains
valid.

### Step 4: Verify Markdown And Changelog Hygiene

**Maps to**: AC-1, AC-2, AC-3

1. Run:

   ```bash
   npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"
   ```

2. Run:

   ```bash
   find docs/specs/developments docs/testing/workflow -name "*.md" -print0 \
     | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
   ```

3. Run:

   ```bash
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

4. Run:

   ```bash
   git diff --check
   ```

**Expected result**: Markdown, heuristic, changelog, and whitespace checks pass.

## Assertions Checklist

- [ ] AC-1: External review documentation recommends one external reviewer per
      repository or product plus internal runner review.
- [ ] AC-2: Documentation describes multi-bot usage as advanced and names cost,
      latency, duplicated findings, and conflict trade-offs.
- [ ] AC-3: Repository-mode or related configuration guidance points to the same
      recommendation.
- [ ] AC-4: Multiple external reviewers produce a non-blocking warning when the
      validator warning is implemented.
- [ ] AC-5: Existing multi-reviewer configurations remain supported.

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Config resolver tests fail on missing warning | Warning helper is not called from validation path | Confirm `validate_workflow_config` invokes the helper for shared and local config. |
| Warning appears on stdout | Warning output stream changed | Emit warnings to stderr so existing stdout consumers keep working. |
| Markdown lint fails on long tables | New prose was added to a table cell | Wrap long guidance in paragraphs instead of wide table cells. |
