# Smoke Test Runbook: Workflow Hub Template Skeletons

**Feature**: Workflow hub and product repository template skeletons
**Spec**: [1_876-workflow-hub-template-skeletons_specs.md](../../specs/developments/20260610140419_876-workflow-hub-template-skeletons/1_876-workflow-hub-template-skeletons_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #876.
- [ ] #874 is already merged into `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Workflow hub skeleton | `template/workflow-hub/` |
| Product repository injection skeleton | `template/product-repo-injection/` |
| Sync manifest | `sync-manifest.yaml` |
| Root README | `README.md` |
| Setup protocol | `docs/workflow/setup/protocol.md` |
| Skeleton validation harness | `scripts/development-workflow/tests/test-workflow-hub-skeletons.sh` |

---

## Smoke Test Steps

### Step 1: Confirm Skeleton Directories Exist

**Maps to**: AC1, AC2, AC3

1. Confirm `template/workflow-hub/` exists.
2. Confirm `template/workflow-hub/README.md` exists.
3. Confirm `template/workflow-hub/skeleton-manifest.yaml` exists.
4. Confirm `template/product-repo-injection/` exists.
5. Confirm `template/product-repo-injection/README.md` exists.
6. Confirm `template/product-repo-injection/skeleton-manifest.yaml` exists.

**Expected result**: Both role-specific skeletons can be browsed directly, and
opening them does not run setup, sync, or injection behavior.

### Step 2: Verify Workflow Hub Skeleton Scope

**Maps to**: AC1

1. Open `template/workflow-hub/README.md`.
2. Confirm it says the skeleton is for a `workflow_hub` repository.
3. Confirm it lists workflow-owned categories:
   - protocols and workflow documentation
   - workflow helper scripts
   - agent and skill wrappers
   - project workflow configuration
   - runbooks or test harnesses
4. Open `template/workflow-hub/skeleton-manifest.yaml`.
5. Confirm referenced canonical source paths exist or are clearly marked as
   generated/example-only.

**Expected result**: The hub skeleton clearly represents workflow-owned content
without product repository application code.

### Step 3: Verify Product Repository Injection Scope

**Maps to**: AC2, AC4

1. Open `template/product-repo-injection/README.md`.
2. Confirm it says the skeleton is for a `product_repo` that participates in a
   workflow hub.
3. Confirm it states product repository injection is minimal.
4. Open `template/product-repo-injection/skeleton-manifest.yaml`.
5. Confirm it excludes hub-owned tracker, spec, and plan artifacts unless a
   specific entry is explicitly marked as required for product repository
   participation.

**Expected result**: Product repository injection does not copy the full
framework or hub-owned planning artifacts into product repositories.

### Step 4: Verify Sync Manifest Mode Scopes

**Maps to**: AC5

1. Open `sync-manifest.yaml`.
2. Confirm it defines the scope values:
   - `shared`
   - `hub_only`
   - `product_repo_injection`
3. Confirm current manifest categories remain present:
   - `always_sync`
   - `special_handling`
   - `project_specific`
4. Confirm the skeleton directories are included in the manifest.
5. Confirm the implementation notes that mode-scope metadata is informational
   until a later mode-aware sync implementation consumes it.

**Expected result**: The manifest can model mode-specific ownership without
changing current sync-template behavior.

### Step 5: Verify README Setup Guidance

**Maps to**: AC6, AC7, AC8, AC9

1. Open `README.md`.
2. Confirm generated repository guidance explains when to choose:
   - `single_repo`
   - `workflow_hub`
   - `product_repo`
3. Confirm existing repository guidance explains how to adopt a workflow hub or
   connect a product repository to one.
4. Confirm the current root template remains documented as the valid default
   `single_repo` setup.
5. Confirm examples use generic names only.

**Expected result**: Both new and existing adopters can choose the correct
setup path, and private topology details are not hardcoded.

### Step 6: Run Skeleton Validation

**Maps to**: AC1, AC2, AC4, AC5, AC9

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh
   ```

2. Confirm it validates skeleton existence, source path references, mode scopes,
   and product-repo-injection exclusions.

**Expected result**: The validation harness passes and would fail if product
repository injection included hub-only planning artifacts.

### Step 7: Run Markdown and Changelog Validation

1. Run:

   ```bash
   npx markdownlint-cli2 "README.md" "docs/workflow/**/*.md" "template/**/*.md" "docs/specs/developments/20260610140419_876-workflow-hub-template-skeletons/*.md" "docs/testing/workflow/876-workflow-hub-template-skeletons.smoke-test.md" "CHANGELOG.md"
   python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/876-workflow-hub-template-skeletons.smoke-test.md CHANGELOG.md
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

**Expected result**: All commands pass with no errors.

---

## Assertions Checklist

- [ ] AC1: `template/workflow-hub/` exists as an inspectable skeleton for
      workflow-owned protocols, scripts, agents, project configuration, and
      runbooks.
- [ ] AC2: `template/product-repo-injection/` exists as an inspectable skeleton
      for minimal product repository integration files.
- [ ] AC3: Inspecting the new skeletons does not change current single-repo
      setup behavior.
- [ ] AC4: Product repository injection excludes hub-owned tracker, spec, and
      plan artifacts unless explicitly required.
- [ ] AC5: The sync manifest model can distinguish shared, hub-only, and
      product-repo-injection files.
- [ ] AC6: README guidance explains when a generated repository chooses
      `single_repo`, `workflow_hub`, or `product_repo` setup.
- [ ] AC7: README guidance explains how an existing repository chooses between
      `single_repo`, `workflow_hub`, and `product_repo` setup.
- [ ] AC8: The current root template remains valid for `single_repo` adopters.
- [ ] AC9: Skeleton and README examples avoid hardcoded private project,
      repository, or team details.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Skeleton validation reports a missing source path | A manifest entry points to a path that does not exist and is not marked generated/example-only | Correct the path or mark the entry explicitly as generated/example-only. |
| Product injection validation fails on `docs/specs/` | The product skeleton includes hub-owned planning artifacts | Remove the entry or document why it is explicitly required for product participation. |
| Sync-template behavior changes unexpectedly | Mode-scope metadata was treated as active sync behavior | Keep scope metadata informational in this item and preserve existing manifest categories. |
| README examples look project-specific | Generic placeholder names were replaced with private topology | Replace examples with generic names. |

---

## Known Limitations

- This smoke test validates static skeletons and scope metadata. It does not
  validate automatic mode-aware sync or skeleton application behavior.
