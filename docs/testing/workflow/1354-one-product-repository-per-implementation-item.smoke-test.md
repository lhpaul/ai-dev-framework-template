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
| Product-owned child | Fixture issue or command input selecting `mobile-app` |
| Missing-target child | Fixture issue or command input with no selected key |
| Ambiguous child | Fixture issue or command input with conflicting or unresolved target evidence |
| Multi-target child | Fixture issue or command input selecting both product keys |
| Hub-only child | Fixture issue or command input explicitly marked hub-only with no product key |
| Single-repository fixture | Default or `single_repo` mode config |

---

## Smoke Test Steps

### Step 1: Product-Owned Child Routes To One Repository

**Maps to**: AC1, AC7

1. Run the routing or orchestration command for a product-owned child that
   selects `mobile-app`.
2. Inspect the command output.

**Expected result**: The output shows `Product owned`, selected key
`mobile-app`, product artifact owner `selected product repository`, and no stop
reason.

### Step 2: Missing Product Target Stops Before Mutation

**Maps to**: AC2

1. Run the routing or orchestration command for a product-owned child with no
   selected product repository key.
2. Confirm no product branch, PR, reviewer, CI, or cleanup mutation occurs.

**Expected result**: The output shows `Missing target` or equivalent stop
evidence and allows only hub-owned stop evidence to be recorded.

### Step 3: Ambiguous Product Target Stops Before Mutation

**Maps to**: AC3

1. Run the routing or orchestration command for a product-owned child whose
   tracker context cannot resolve to one configured key.
2. Confirm no product branch, PR, reviewer, CI, or cleanup mutation occurs.

**Expected result**: The output shows `Ambiguous target` or equivalent stop
evidence and identifies the required routing clarification.

### Step 4: Multiple Product Targets Require Split Or Narrowing

**Maps to**: AC4

1. Run the routing or orchestration command for a child that names both
   `mobile-app` and `admin-portal`.
2. Inspect the required next action.

**Expected result**: The output shows `Multiple targets` and instructs the
operator to split the request into repository-scoped children or narrow the
child to one selected product repository key.

### Step 5: Cross-Repository Request Uses Epic Plus Children

**Maps to**: AC5

1. Review the documentation and fixture data for a cross-repository request.
2. Confirm it uses one hub epic plus one product-owned child per selected
   product repository.

**Expected result**: The request is not represented as one multi-target child,
and each product-owned child has exactly one selected product repository key.

### Step 6: Hub-Only Work Does Not Require Product Key

**Maps to**: AC6

1. Run the routing or orchestration command for a hub-only child with no
   product repository key.
2. Inspect artifact owner and mutation target output.

**Expected result**: The output shows `Hub only`, routes hub-owned artifacts to
the hub repository, and does not require a product repository selector.

### Step 7: Single-Repository Work Keeps Current Behavior

**Maps to**: AC8

1. Run the routing or orchestration command in the default or `single_repo`
   fixture.
2. Confirm no product repository selector is required.

**Expected result**: The output shows single-repository behavior using the
current repository as artifact owner.

### Step 8: Out-Of-Scope Epic Peers Remain Separate

**Maps to**: AC9

1. Review docs and implementation output for release execution, delivery bundle,
   milestone, and adoption behavior.
2. Confirm #1354 only enforces one-target routing and tracker decomposition.

**Expected result**: Product release execution remains scoped to #1356,
delivery-bundle behavior to #1357, milestone reconciliation to #1358, and
adoption assurance to #1359.

### Last Step: Validate And Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary fixture directories created during the smoke run.

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
| Workflow-hub config | Two product repositories | Use the fixture created by the #1354 implementation tests. |
| Product-owned child | One selected key | Use the fixture issue/input for `mobile-app`. |
| Missing-target child | No selected key | Use the fixture issue/input with product-owned role and no key. |
| Ambiguous child | Conflicting or unresolved target evidence | Use the fixture issue/input with ambiguous target context. |
| Hub-only child | Hub-owned work with no selected key | Use the fixture issue/input marked hub-only. |

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
