# Smoke Test Runbook: One Product Repository Per Implementation Item

**Feature**: One product repository per implementation item
**Spec**:
[`1_1354-one-product-repository-per-implementation-item_specs.md`](../../specs/developments/20260731064618_1354-one-product-repository-per-implementation-item/1_1354-one-product-repository-per-implementation-item_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Use a clean checkout on the implementation branch for #1354.
- [ ] Confirm the #1354 implementation and its required tests are landed in the
      branch under test. This runbook validates the post-merge implementation
      state.
- [ ] Run from the repository root.
- [ ] Prepare workflow-hub fixture config with two configured product
      repository keys, such as `mobile-app` and `admin-portal`.
- [ ] Confirm #1353 ownership and release contract behavior is present on the
      branch under test.

---

## Test Data

| Item | Value |
| --- | --- |
| Workflow mode | `workflow_hub` fixture |
| Product repository key A | `mobile-app` |
| Product repository key B | `admin-portal` |
| Product-owned fixture | `scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json` |
| Missing-target fixture | `scripts/development-workflow/tests/fixtures/1354-routing/missing-target.json` |
| Ambiguous fixture | `scripts/development-workflow/tests/fixtures/1354-routing/ambiguous-target.json` |
| Multi-target fixture | `scripts/development-workflow/tests/fixtures/1354-routing/multiple-targets.json` |
| Hub-only fixture | `scripts/development-workflow/tests/fixtures/1354-routing/hub-only.json` |
| Single-repository fixture | `scripts/development-workflow/tests/fixtures/1354-routing/single-repo.json` |

---

## Smoke Test Steps

### Step 1: Product-Owned Child Routes To One Repository

**Maps to**: AC1, AC7

1. Run:

   ```bash
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json \
     --json
   ```

2. Confirm the command exits `0`.

**Expected result**: The output shows `Product owned`, selected key
`mobile-app`, `outcome_code=product_owned`, `continue_allowed=true`, artifact
owner `selected_product_repository`, and no stop reason.

### Step 2: Missing Product Target Stops Before Mutation

**Maps to**: AC2

1. Run:

   ```bash
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/missing-target.json \
     --json
   ```

2. Confirm the command exits `0`.
3. Run the corresponding orchestration dry-run fixture and confirm no product
   branch, PR, reviewer, CI, or cleanup command is invoked.

**Expected result**: The output shows `Missing target` or equivalent stop
evidence, `outcome_code=missing_target`, `continue_allowed=false`, and allows
only hub-owned stop evidence to be recorded.

### Step 3: Ambiguous Product Target Stops Before Mutation

**Maps to**: AC3

1. Run:

   ```bash
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/ambiguous-target.json \
     --json
   ```

2. Confirm the command exits `0`.
3. Run the corresponding orchestration dry-run fixture and confirm no product
   branch, PR, reviewer, CI, or cleanup command is invoked.

**Expected result**: The output shows `Ambiguous target` or equivalent stop
evidence, `outcome_code=ambiguous_target`, `continue_allowed=false`, and
identifies the required routing clarification.

### Step 4: Multiple Product Targets Require Split Or Narrowing

**Maps to**: AC4

1. Run:

   ```bash
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/multiple-targets.json \
     --json
   ```

2. Confirm the command exits `0`.
3. Inspect the required next action.

**Expected result**: The output shows `Multiple targets` and instructs the
operator to split the request into repository-scoped children or narrow the
child to one selected product repository key. The JSON output includes
`outcome_code=multiple_targets` and `continue_allowed=false`.

### Step 5: Cross-Repository Request Uses Epic Plus Children

**Maps to**: AC5

1. Run the docs regression test:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-docs.sh
   ```

2. Inspect the fixture directory:

   ```bash
   find scripts/development-workflow/tests/fixtures/1354-routing -maxdepth 1 -type f -name "*.json" -print
   ```

**Expected result**: The request is not represented as one multi-target child,
and each product-owned child has exactly one selected product repository key.

### Step 6: Hub-Only Work Does Not Require Product Key

**Maps to**: AC6

1. Run:

   ```bash
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/hub-only.json \
     --json
   ```

2. Confirm the command exits `0`.
3. Inspect artifact owner and mutation target output.

**Expected result**: The output shows `Hub only`, routes hub-owned artifacts to
the hub repository, does not require a product repository selector, and includes
`outcome_code=hub_only` with `continue_allowed=true`.

### Step 7: Single-Repository Work Keeps Current Behavior

**Maps to**: AC8

1. Run:

   ```bash
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/single-repo.json \
     --json
   ```

2. Confirm the command exits `0`.
3. Confirm no product repository selector is required.

**Expected result**: The output shows single-repository behavior using the
current repository as artifact owner and includes `outcome_code=single_repo`.

### Step 8: Out-Of-Scope Epic Peers Remain Separate

**Maps to**: AC9

1. Run:

   ```bash
   rg -n "#1356|#1357|#1358|#1359|release execution|delivery-bundle|milestone|adoption" \
     docs/workflow/development-workflow \
     docs/specs/developments/20260731064618_1354-one-product-repository-per-implementation-item
   ```

2. Confirm #1354 only enforces one-target routing and tracker decomposition.

**Expected result**: Product release execution remains scoped to #1356,
delivery-bundle behavior to #1357, milestone reconciliation to #1358, and
adoption assurance to #1359.

### Last Step: Validate And Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary smoke output files created during the smoke run:

  ```bash
  rm -f /tmp/1354-routing-*.json
  ```

---

## Assertions Checklist

- [ ] Product-owned hub work with exactly one selected key can advance and shows
      that key as the product mutation target.
- [ ] Product-owned hub work with no selected key stops before product artifact
      mutation and reports `Missing target` or equivalent evidence.
- [ ] Product-owned hub work with ambiguous target evidence stops before product
      artifact mutation and reports `Ambiguous target` or equivalent evidence.
- [ ] Product-owned hub work with multiple selected keys stops before mutation
      and asks for split or narrowing.
- [ ] Cross-repository requests use a hub epic plus one product-owned child per
      product repository.
- [ ] Hub-only coordination work routes in the hub without a product key.
- [ ] Selected repository context is visible in implementation, review, CI,
      cleanup, and release handoff summaries.
- [ ] `single_repo` workflows do not require product repository selection.
- [ ] #1354 does not implement release execution, delivery bundles, milestones,
      or adoption assurance behavior.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Workflow-hub config | Two product repositories | `scripts/development-workflow/tests/fixtures/1354-routing/config-workflow-hub.json` |
| Product-owned child | One selected key | `scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json` |
| Missing-target child | No selected key | `scripts/development-workflow/tests/fixtures/1354-routing/missing-target.json` |
| Ambiguous child | Conflicting or unresolved target evidence | `scripts/development-workflow/tests/fixtures/1354-routing/ambiguous-target.json` |
| Hub-only child | Hub-owned work with no selected key | `scripts/development-workflow/tests/fixtures/1354-routing/hub-only.json` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Command falls back to the hub for product-owned work | Routing classifier was skipped or product-owned role was not passed | Re-run with the fixture that exercises the shared classifier and inspect stop evidence. |
| Multi-target child advances | Selected-key parser accepted more than one key | Check routing classifier tests for the multiple-target case. |
| Hub-only child asks for a product key | Hub-only marker is not being passed to the classifier | Verify the hub-only fixture and command handoff. |

---

## Known Limitations

- This smoke test uses deterministic fixtures rather than live product
  repositories. Live product release behavior belongs to #1356.
