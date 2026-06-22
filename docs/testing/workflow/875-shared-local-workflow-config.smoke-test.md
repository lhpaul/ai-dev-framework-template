# Smoke Test Runbook: Shared and Local Workflow Configuration

**Feature**: Shared and local workflow configuration
**Spec**: [1_875-shared-local-workflow-config_specs.md](../../specs/developments/20260610135749_875-shared-local-workflow-config/1_875-shared-local-workflow-config_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #875.
- [ ] #874 is already merged into `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Shared config | `.ai-dev-workflow.yaml` |
| Local config example | `.ai-dev-workflow.local.example.yaml` |
| Local config ignore path | `.ai-dev-workflow.local.yaml` |
| Workflow library | `scripts/development-workflow/workflow-lib.sh` |
| Validation command | `scripts/development-workflow/validate-workflow-config.sh` |
| Resolver tests | `scripts/development-workflow/tests/test-workflow-config-resolver.sh` |

---

## Smoke Test Steps

### Step 1: Confirm Required Files and Ignore Rules

**Maps to**: AC5, AC6

1. Confirm `.gitignore` includes `.ai-dev-workflow.local.yaml`.
2. Confirm `.ai-dev-workflow.local.example.yaml` exists.
3. Confirm the example uses placeholder paths, repository names, and secret
   references only.
4. Confirm the example documents checkout root defaults, per-product local
   paths, private key paths or secret references, and local reviewer/tool
   overrides.

**Expected result**: The real local config file is ignored by git, and the
example file is safe to commit.

### Step 2: Verify Shared Configuration Documentation

**Maps to**: AC1, AC2, AC3, AC4

1. Locate the workflow configuration documentation.
2. Confirm it documents these fields:
   - `mode`
   - `workflow_hub.product_repos[]`
   - `product_repo.workflow_hub`
3. Confirm it defines the valid mode values:
   - `single_repo`
   - `workflow_hub`
   - `product_repo`
4. Confirm it states that missing `mode` resolves as `single_repo`.
5. Confirm it states that shared product repository entries may contain stable
   non-secret identity and metadata only.

**Expected result**: Readers can configure shared repository identity without
putting local paths or secrets in version control.

### Step 3: Run Repository-Context Unit Tests

**Maps to**: AC1, AC3, AC7, AC8, AC9, AC10, AC11

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   ```

2. Confirm the output includes passing cases for:
   - missing mode -> `single_repo`
   - valid `workflow_hub`
   - invalid `workflow_hub`
   - valid `product_repo`
   - local path override
   - derived local path
   - missing local path
   - review overrides from `.ai-dev-workflow.local.yaml`

**Expected result**: The test harness passes and covers each mode and required
local path behavior.

### Step 4: Validate Shell-Callable Helper Output

**Maps to**: AC7, AC8

1. Source the workflow library from Bash.
2. Run the new repository-context helper against a valid fixture or local test
   config.
3. Confirm the output uses shell-safe `KEY=value` lines.
4. Confirm the output includes mode, repository name, local path when required,
   remote identity, default branch, and tracker hints when configured.

**Expected result**: Existing shell scripts can consume repository context
without parsing nested YAML themselves.

### Step 5: Validate Failure Messages

**Maps to**: AC8, AC9

1. Run the validation command against a duplicate product repository name
   fixture.
2. Run it against a product repository entry missing both `github_repo` and
   `git_url`.
3. Run it against a workflow hub target that needs a local checkout path but has
   no override or derivable default.

**Expected result**: Each failure names the missing or ambiguous value and the
config file the user should edit.

### Step 6: Verify Local Review Overrides

**Maps to**: AC10

1. Create a temporary fixture with shared `.ai-dev-workflow.yaml` review
   settings.
2. Create a temporary `.ai-dev-workflow.local.yaml` with local review override
   settings.
3. Run the helper or validation path that resolves effective review overrides.

**Expected result**: The resolver uses `.ai-dev-workflow.local.yaml` for local
review overrides and reports that file as the override source.

### Step 7: Run Existing Workflow Regressions

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh
   ```

2. If the implementation adds a Python resolver, run:

   ```bash
   python3 -m py_compile scripts/development-workflow/<resolver-script>.py
   ```

**Expected result**: Existing review-loop and tracker helper behavior still
passes after the config changes.

### Step 8: Run Markdown and Changelog Validation

1. Run:

   ```bash
   npx markdownlint-cli2 "docs/specs/developments/20260610135749_875-shared-local-workflow-config/*.md" "docs/testing/workflow/875-shared-local-workflow-config.smoke-test.md" "CHANGELOG.md"
   python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/875-shared-local-workflow-config.smoke-test.md CHANGELOG.md
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

**Expected result**: All commands pass with no errors.

---

## Assertions Checklist

- [ ] AC1: A repository with no mode declaration resolves as `single_repo`.
- [ ] AC2: Shared workflow documentation describes `mode`,
      `workflow_hub.product_repos[]`, and `product_repo.workflow_hub`.
- [ ] AC3: A workflow hub can declare multiple product repositories by stable
      name plus GitHub repository slug or git URL.
- [ ] AC4: Versioned product repository entries are limited to stable
      non-secret identity and metadata.
- [ ] AC5: Local paths, checkout defaults, secret references, and local
      reviewer/tool overrides are documented as local-only configuration.
- [ ] AC6: `.ai-dev-workflow.local.yaml` is ignored by git, and the example
      file contains no real secrets or private paths.
- [ ] AC7: Repository-context helpers expose shell-callable mode, path, remote,
      branch, and tracker output.
- [ ] AC8: Local path resolution uses explicit override, documented default, or
      clear error.
- [ ] AC9: Validation fails clearly for missing, duplicated, or ambiguous
      product repository configuration.
- [ ] AC10: Local review overrides resolve from `.ai-dev-workflow.local.yaml`
      and report that file as the override source.
- [ ] AC11: Tests cover `single_repo`, valid and invalid `workflow_hub`,
      `product_repo`, local path overrides, and missing local path cases.

---

## Seed Data Reference

No committed seed data is required. Tests should create temporary fixture files.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Resolver tests pass locally but fail in CI | The implementation relies on an undeclared parser dependency | Use stdlib-only parsing or declare and install the dependency in CI. |
| `.ai-dev-workflow.local.yaml` appears in `git status` | The gitignore entry is missing or misspelled | Add the exact path to `.gitignore`. |
| Existing review-loop override tests fail | The resolver is not reading `.ai-dev-workflow.local.yaml` review overrides | Update the resolver to use the local YAML review keys and adjust tests. |
| Validation error is generic | Failure path does not include field/file context | Update the resolver to name the missing field and relevant config file. |

---

## Known Limitations

- This smoke test validates repository-context behavior and local config
  boundaries. It does not validate full cross-repository orchestration.
