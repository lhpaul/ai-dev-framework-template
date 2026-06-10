# Smoke Test Runbook: Workflow Hub Operating Model

**Feature**: Workflow hub operating model and artifact ownership
**Spec**: [1_874-workflow-hub-operating-model_specs.md](../../specs/developments/20260610135131_874-workflow-hub-operating-model/1_874-workflow-hub-operating-model_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #874.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Architecture note | `docs/workflow/development-workflow/repository-modes.md` |
| Root README | `README.md` |
| Workflow README | `docs/workflow/development-workflow/README.md` |
| Spec | `docs/specs/developments/20260610135131_874-workflow-hub-operating-model/1_874-workflow-hub-operating-model_specs.md` |

---

## Smoke Test Steps

### Step 1: Confirm Required Files Exist

**Maps to**: AC1, AC2

1. Confirm `docs/workflow/development-workflow/repository-modes.md` exists.
2. Confirm `README.md` links to the architecture note.
3. Confirm `docs/workflow/development-workflow/README.md` links to the
   architecture note.

**Expected result**: The architecture note exists and both required entry points
link to it with relative links that render from their file locations.

### Step 2: Verify Repository Modes and Default Behavior

**Maps to**: AC1, AC3, AC9

1. Open the architecture note.
2. Confirm it defines exactly these mode code values:
   - `single_repo`
   - `workflow_hub`
   - `product_repo`
3. Confirm each mode has a display label and user-facing description.
4. Confirm the note states that a missing mode declaration is interpreted as
   `single_repo`.
5. Confirm the `single_repo` section says existing adopters keep current
   behavior when no mode is declared.

**Expected result**: A reader can identify all supported modes and understand
that missing mode means no migration or new configuration is required.

### Step 3: Verify Artifact Ownership Coverage

**Maps to**: AC4, AC5

1. Locate the artifact ownership table.
2. Confirm it covers:
   - backlog or tracker items
   - specs
   - plans
   - hub-owned smoke runbooks
   - product-owned smoke runbooks
   - implementation branches
   - spec PRs
   - plan PRs
   - code PRs
   - CI checks
   - reviewer-loop checks
3. Confirm the note states where spec PRs, plan PRs, and code PRs are opened in
   every supported mode.

**Expected result**: Every artifact named in the spec has an owner in each mode,
and PR ownership is explicit.

### Step 4: Verify Target Repository Selection

**Maps to**: AC6

1. Locate the target product repository selection section.
2. Confirm the note says hub-managed implementation work must identify one
   visible, unambiguous target product repository.
3. Confirm the note says missing or ambiguous targets are flagged before product
   implementation routing.
4. Confirm the note avoids prescribing a storage format for the target
   repository value.

**Expected result**: The rule is clear enough for later script and agent work,
but storage details remain open for later implementation items.

### Step 5: Verify Hub-Owned and Product-Injected Content

**Maps to**: AC7

1. Locate the section that distinguishes hub-owned content from product-injected
   content.
2. Confirm the note lists workflow-hub content such as tracker coordination,
   specs, plans, and cross-repository workflow documentation.
3. Confirm the note lists product-repo content such as local agent wrappers,
   workflow helper injection, CI/reviewer-loop hooks, and product smoke
   runbooks when later implementation items provide them.

**Expected result**: Readers can tell what remains centralized and what may be
copied or injected into product repositories.

### Step 6: Verify Generic Multi-Product Example

**Maps to**: AC8

1. Locate the multi-product hub example.
2. Confirm it uses generic repository names.
3. Confirm it shows one hub coordinating more than one product repository.
4. Confirm it contains no private project, repository, team, customer, or domain
   details.

**Expected result**: The example explains the intended topology without
hardcoding private project information.

### Step 7: Verify Documentation-Only Scope

**Maps to**: AC10

1. Run:

   ```bash
   git diff --name-only origin/develop-workflow-hub-mode...HEAD
   ```

2. Confirm the diff contains only documentation files and `CHANGELOG.md`.
3. Confirm no shell scripts, workflow automation, CI files, or runtime config
   files changed.

**Expected result**: The implementation introduces no runtime behavior changes.

### Step 8: Run Markdown Validation

1. Run:

   ```bash
   npx markdownlint-cli2 "README.md" "docs/workflow/development-workflow/**/*.md" "docs/testing/workflow/874-workflow-hub-operating-model.smoke-test.md" "CHANGELOG.md"
   python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/874-workflow-hub-operating-model.smoke-test.md CHANGELOG.md
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

**Expected result**: All commands pass with no errors.

---

## Assertions Checklist

- [ ] AC1: The architecture note defines `single_repo`, `workflow_hub`, and
      `product_repo` with display labels and descriptions.
- [ ] AC2: The architecture note is linked from `README.md` and
      `docs/workflow/development-workflow/README.md`.
- [ ] AC3: Missing mode declaration is interpreted as `single_repo`.
- [ ] AC4: Artifact ownership covers all artifacts named in the spec.
- [ ] AC5: Spec PR, plan PR, and code PR ownership is explicit in every mode.
- [ ] AC6: Target product repository selection is visible and missing or
      ambiguous targets are flagged before implementation routing.
- [ ] AC7: Hub-owned content and product-injected content are distinguished.
- [ ] AC8: The multi-product example is generic and private-detail-free.
- [ ] AC9: Existing single-repository behavior is preserved by default.
- [ ] AC10: The implementation is documentation-only.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| README link fails markdown lint | Relative path is wrong for the source file | Adjust the link relative to the file that contains it. |
| Artifact ownership table omits smoke runbook split | Hub-owned and product-owned runbooks were merged into one row | Split the row or make ownership explicit for both runbook types. |
| Diff includes scripts or config | Scope expanded beyond #874 | Remove runtime/config changes or move them to later workflow-hub implementation items. |

---

## Known Limitations

- This smoke test validates documentation content, not runtime behavior.
