# Smoke Test Runbook: Artifact Ownership and Product Release Contract

**Feature**: Artifact ownership and product release contract
**Spec**:
[`docs/specs/developments/20260730174200_1353-artifact-ownership-product-release-contract/1_1353-artifact-ownership-product-release-contract_specs.md`](../../specs/developments/20260730174200_1353-artifact-ownership-product-release-contract/1_1353-artifact-ownership-product-release-contract_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] Use the implementation branch for issue #1353.
- [ ] `bash`, `python3`, `jq`, `rg`, and Node/npm for markdownlint are
      available.
- [ ] No test fixture contains real local checkout paths, credentials, tokens,
      private keys, secret names, secret values, or environment-specific account
      details.
- [ ] The implementation PR targets `develop-multi-repo-releases`.

---

## Test Data

| Item | Value |
| --- | --- |
| Workflow hub fixture | `mode: workflow_hub` with two product repositories |
| Product repository fixture | `mode: product_repo` with a workflow hub reference |
| Single repository fixture | Missing `mode` or `mode: single_repo` |
| Valid release branch pattern | `release/v{version}` |
| Invalid branch examples | whitespace, `..`, `@{`, `//`, leading/trailing slash, `?`, `^`, `~`, `:`, backslash, `#` |
| Product role sync expectation | Product runtime entries selected; hub-only coordination skipped |
| Hub role sync expectation | Hub coordination selected; product-only injection skipped |

---

## Smoke Test Steps

### Step 1: Validate product release contract parsing

**Maps to**: AC-3, AC-4, AC-5, AC-8

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   ```

2. Confirm valid `workflow_hub.product_repos[]` release contracts report
   explicit and defaulted values.
3. Confirm `single_repo` fixtures pass without requiring product release
   metadata.
4. Confirm missing product repository selection remains ambiguous when multiple
   product repositories are configured.
5. Confirm versioned config rejects release contract values containing local
   paths, credentials, tokens, secret names, secret values, or
   environment-specific account details.

**Expected result**: Product-owned release work has validated non-secret
metadata, while single-repository compatibility remains unchanged.

### Step 2: Validate branch and pattern rules

**Maps to**: AC-3, AC-4

1. Inspect the branch validation cases in
   `scripts/development-workflow/tests/test-workflow-config-resolver.sh`.
2. Confirm valid branch names include `main`, `develop`, `release/v1.2.3`,
   `product_repo/release-v1.2.3`, and `team.alpha/release_1`.
3. Confirm invalid values include empty strings, empty path segments,
   whitespace, `..`, `@{`, `//`, leading slash, trailing slash, `?`, `^`,
   `~`, `:`, backslash, and `#`.
4. Confirm valid release branch patterns use only `{version}` and
   `{product_repo}` placeholders and resolve to exactly one valid branch.
5. Confirm unknown or unresolved placeholders fail before mutation.

**Expected result**: Release branch inputs are portable and
machine-checkable before any release artifact is created.

### Step 3: Validate role-aware sync selection

**Maps to**: AC-6, AC-7, AC-8

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh
   ```

2. Preview the real manifest selections:

   ```bash
   python3 scripts/development-workflow/select-sync-manifest-entries.py \
     --manifest sync-manifest.yaml \
     --role product_repo
   python3 scripts/development-workflow/select-sync-manifest-entries.py \
     --manifest sync-manifest.yaml \
     --role workflow_hub
   python3 scripts/development-workflow/select-sync-manifest-entries.py \
     --manifest sync-manifest.yaml \
     --role single_repo
   ```

3. Confirm `product_repo` output includes only shared and product injection
   release runtime surfaces.
4. Confirm `product_repo` output skips hub-only coordination files such as
   historical specs, implementation plans, workflow protocols, hub scripts, and
   hub-only runbooks.
5. Confirm `workflow_hub` output includes hub coordination files and skips
   product-only injection files.
6. Confirm `single_repo` output preserves the compatibility file set.

**Expected result**: The sync manifest implements the ownership contract for
all supported roles and fails closed for unknown roles.

### Step 4: Validate skeleton ownership

**Maps to**: AC-1, AC-2, AC-6, AC-7

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh
   python3 scripts/development-workflow/validate-workflow-hub-skeletons.py
   ```

2. Confirm the workflow-hub skeleton owns coordination, protocols, hub scripts,
   and hub runbooks.
3. Confirm the product-repository skeleton includes only the minimum product
   release runtime entries and shared guidance.
4. Confirm invalid fixtures fail when product injection includes hub-owned
   planning or coordination artifacts without an explicit required exception.

**Expected result**: Skeleton manifests match the release ownership contract.

### Step 5: Validate documentation ownership map

**Maps to**: AC-1, AC-2, AC-3, AC-4

1. Inspect:

   ```bash
   rg -n "Release artifact|Product release contract|changelog|GitHub Release|tracker reconciliation" \
     docs/workflow/development-workflow/repository-modes.md \
     docs/workflow/development-workflow/workflow-hub-setup.md \
     docs/workflow/development-workflow/product-repo-injection.md \
     docs/workflow/development-workflow/cross-repo-pr-flow.md \
     docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md
   ```

2. Confirm tracker work, specs/plans, product code, changelog entries, release
   branches, tags, GitHub Releases, deployment evidence, delivery manifests,
   product cleanup evidence, and tracker reconciliation evidence each have one
   owner in `single_repo`, `workflow_hub`, and `product_repo` contexts.
3. Confirm setup guidance names required non-secret fields, defaults, and stop
   reasons for missing or ambiguous product release configuration.
4. Confirm no guidance tells operators to store local paths or credentials in
   versioned config.

**Expected result**: Operators can identify one owner for every release
artifact before mutating product or hub release state.

### Step 6: Validate markdown and heuristic lint

**Maps to**: AC-1 through AC-8

1. Run:

   ```bash
   npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"
   find docs/specs/developments docs/testing/workflow -name "*.md" -print0 \
     | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
   ```

2. Confirm no markdown, relative-link, or heuristic errors remain.

**Expected result**: Plan, runbook, and implementation docs are lint-clean.

---

## Assertions Checklist

- [ ] The workflow documentation includes an ownership map for all release
      artifact categories named in the spec.
- [ ] Every artifact has exactly one owner for workflow-hub,
      product-repository, and single-repository contexts.
- [ ] Product release configuration records only non-secret portable metadata
      and reports defaults versus explicit values.
- [ ] Validation fails before release-artifact mutation when required product
      release contract information is missing or ambiguous.
- [ ] Validation rejects forbidden local paths, credentials, tokens, secret
      names, secret values, and environment-specific account details.
- [ ] Product repository sync includes minimum product release runtime files and
      excludes hub-only coordination files.
- [ ] Automated tests prove sync selection for workflow hub, product repository,
      and single repository roles.
- [ ] Existing single-repository setup, release, and sync behavior remains
      compatible.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Workflow config fixtures | Valid and invalid hub/product/single-repo release contracts | Created inside `test-workflow-config-resolver.sh` |
| Sync manifest fixtures | Role-aware shared, hub-only, product injection, and release runtime entries | Created inside `test-sync-template-mode-scopes.sh` |
| Skeleton fixtures | Valid and invalid release runtime ownership entries | Created inside `test-workflow-hub-skeletons.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Product role selects hub-only files | `sync-manifest.yaml` entry has the wrong `mode_scope` | Correct the entry and rerun sync mode-scope tests |
| Release contract accepts a local path | Forbidden-data scan missed a nested key or value pattern | Add the failing fixture and update resolver validation |
| Single-repo validation requires product metadata | Product release contract was made globally mandatory | Limit required fields to product-owned release mutation paths |
| Skeleton validation fails on missing source path | Manifest references a file not present in the template | Add the intended source file or remove the manifest entry |

---

## Known Limitations

- The runbook validates contract, sync, and documentation behavior. It does not
  execute a real product release or create real GitHub Releases, tags, or
  deployment evidence.
