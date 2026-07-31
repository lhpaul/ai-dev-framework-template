# Smoke Test Runbook: Route Component Releases To The Selected Product Repository

**Feature**: Route component releases to the selected product repository
**Spec**:
[`docs/specs/developments/20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md`](../../specs/developments/20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in the workflow hub checkout.
- [ ] A workflow-hub fixture or test repository configuration has at least two
      product repositories and local-only checkout entries for the selected
      product repository.
- [ ] The selected product repository checkout is clean.
- [ ] The implementation branch for #1356 is checked out or merged into the
      test branch.

---

## Test Data

| Item | Value |
| --- | --- |
| Hub mode | `workflow_hub` |
| Selected product repository | One configured product repository key, such as `mobile-app` |
| Alternate product repository | A second configured product repository key |
| Release version | Test version such as `9.9.9-test` |
| Release correlation key | Stable value for the test release attempt |
| Hub tracker reference | GitHub issue #1356 or a fixture tracker URL |

---

## Smoke Test Steps

### Step 1: Validate single-repository compatibility

**Maps to**: AC7

1. Use a single-repository fixture or omit workflow-hub mode.
2. Run the implemented release target resolution command without a product
   repository selector.
3. Confirm the routing outcome is `single_repo_release`.
4. Confirm no product repository selector is required.

**Expected result**: The release path remains current-repository owned and does
not require workflow-hub product selection.

### Step 2: Validate selected product release routing

**Maps to**: AC1, AC4

1. Use a workflow-hub fixture with one selected product repository.
2. Run the implemented release target resolution command with that selected
   product repository.
3. Confirm the routing outcome is `component_release_routed`.
4. Confirm the output names the selected product repository, canonical
   repository identity, local checkout source, release base, release branch
   pattern, product artifact owners, hub tracker owner, release correlation key,
   and contract revision or digest.

**Expected result**: Product release artifacts are assigned only to the selected
product repository, while tracker reconciliation remains hub-owned.

### Step 3: Validate fail-closed unsafe selection outcomes

**Maps to**: AC2, AC3

1. Run release target resolution with no selected product repository in
   workflow-hub mode.
2. Repeat with multiple selected products.
3. Repeat with an unknown selected product.
4. Repeat with ambiguous product selection fixture data.
5. Repeat with an invalid release artifact owner.
6. Repeat with a selected product whose local checkout is required but
   unavailable.

**Expected result**: Each run stops before mutation and reports exactly one
canonical routing outcome: `missing_product_selection`,
`multiple_product_targets`, `unknown_product_repository`,
`ambiguous_product_selection`, `invalid_release_contract`, or
`unavailable_product_repository_checkout`.

### Step 4: Validate component release evidence

**Maps to**: AC8

1. Generate a component release evidence record for a pending release attempt.
2. Generate records for completed, failed, and blocked release attempts.
3. Confirm each record includes canonical product repository identity, product
   repository key, release correlation key, contract revision, routing outcome,
   release outcome, CI outcome, deployment outcome, cleanup outcome, and hub
   tracker reference.
4. Try an invalid outcome value and a missing required field.

**Expected result**: Valid evidence records are accepted and deterministic;
invalid or incomplete records are rejected with a clear error.

### Step 5: Validate rerunnable cleanup guard

**Maps to**: AC5, AC6

1. Run release cleanup with evidence whose repository identity, release
   correlation key, and contract revision match the current selected product
   repository.
2. Confirm already-complete cleanup steps are reported as already complete.
3. Confirm missing product cleanup steps are completed in the selected product
   repository.
4. Confirm hub tracker reconciliation happens only after product cleanup
   evidence is confirmed.
5. Repeat with evidence whose repository identity, release correlation key, or
   contract revision differs from the current target.

**Expected result**: Matching evidence allows safe rerunnable cleanup;
mismatched evidence stops before product or hub tracker mutation.

### Last Step: Validate & Shut Down

- Verify all assertions below are satisfied.
- Remove any temporary fixture files or test branches created for the smoke run.

---

## Assertions Checklist

- [ ] A workflow-hub component release with one selected product repository
      routes release artifacts only to that product repository.
- [ ] Missing product selection stops before branch, pull request, changelog,
      tag, deployment, cleanup, or tracker mutation.
- [ ] Ambiguous, unknown, unavailable, and multiple product targets stop before
      mutation with canonical routing outcomes.
- [ ] Release preparation shows release base, release branch, artifact owners,
      product CI evidence source, deployment evidence owner, cleanup evidence
      owner, and hub tracker reconciliation owner.
- [ ] Cleanup validates repository identity, release correlation key, and
      contract revision before mutation.
- [ ] Cleanup reruns report already-complete steps and complete only missing
      selected-product cleanup.
- [ ] Single-repository release and hotfix behavior remains selector-free.
- [ ] Component release evidence includes routing, release, CI, deployment,
      cleanup, and hub tracker reconciliation information for later bundle work.

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
| --- | --- | --- |
| Workflow-hub config fixture | Two product repositories with valid release contracts | Test fixture created by implementation tests |
| Local config fixture | Selected product checkout path stored outside versioned config | Test fixture created by implementation tests |
| Evidence fixture | Matching and mismatched release correlation records | Test fixture created by implementation tests |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Target resolution reports missing product selection | The workflow-hub release command omitted the selected product repository | Rerun with one product repository key from the release contract. |
| Cleanup stops on contract revision mismatch | Evidence was generated from a different release contract than the current selection | Reconfirm the intended release target before retrying cleanup. |
| Product checkout unavailable | Local-only config does not point to a clean product checkout | Correct local-only checkout configuration and rerun target resolution. |

---

## Known Limitations

- This smoke test uses workflow fixtures or non-production repositories. Do not
  run release branch or tag mutation against a production product repository
  during smoke validation.
