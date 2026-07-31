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
- [ ] Export the canonical workflow-hub fixture config and a run-specific
      temporary directory:

      ```bash
   set -euo pipefail
      export ROUTING_CONFIG="scripts/development-workflow/tests/fixtures/1354-routing/config-workflow-hub.json"
      export ROUTING_TMP="$(mktemp -d "${TMPDIR:-/tmp}/1354-routing.XXXXXX")"
      ```

- [ ] Confirm #1353 ownership and release contract behavior is present on the
      branch under test.

---

## Test Data

| Item | Value |
| --- | --- |
| Workflow mode | `workflow_hub` fixture |
| Product repository key A | `mobile-app` |
| Product repository key B | `admin-portal` |
| Workflow-hub config fixture | `scripts/development-workflow/tests/fixtures/1354-routing/config-workflow-hub.json` |
| Product-owned fixture | `scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json` |
| Product-owned peer fixture | `scripts/development-workflow/tests/fixtures/1354-routing/product-owned-admin-portal.json` |
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
   set -euo pipefail
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --config "$ROUTING_CONFIG" \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json \
     --json | tee "$ROUTING_TMP/product-owned.json"
   ```

2. Confirm the command exits `0`.
3. Run:

   ```bash
   set -euo pipefail
   jq -e '
     .outcome_code == "product_owned"
     and .continue_allowed == true
     and .selected_product_repo_key == "mobile-app"
     and .artifact_owner == "selected_product_repository"
     and (.configured_product_repo_keys | sort) == ["admin-portal", "mobile-app"]
     and has("stop_reason")
     and .stop_reason == null
   ' "$ROUTING_TMP/product-owned.json"
   ```

**Expected result**: The output shows `Product owned`, selected key
`mobile-app`, `outcome_code=product_owned`, `continue_allowed=true`, artifact
owner `selected_product_repository`, and no stop reason.

### Step 2: Missing Product Target Stops Before Mutation

**Maps to**: AC2

1. Run:

   ```bash
   set -euo pipefail
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --config "$ROUTING_CONFIG" \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/missing-target.json \
     --json | tee "$ROUTING_TMP/missing-target.json"
   ```

2. Confirm the command exits `0`.
3. Run:

   ```bash
   set -euo pipefail
   jq -e '
     .outcome_code == "missing_target"
     and .continue_allowed == false
     and has("selected_product_repo_key")
     and .selected_product_repo_key == null
     and .artifact_owner == "none"
     and (.configured_product_repo_keys | sort) == ["admin-portal", "mobile-app"]
     and .stop_reason != null
   ' "$ROUTING_TMP/missing-target.json"
   ```

4. Run the orchestration regression that exercises the same stop fixture:

   ```bash
   set -euo pipefail
   bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh
   ```

**Expected result**: The output shows `Missing target` or equivalent stop
evidence, `outcome_code=missing_target`, `continue_allowed=false`, and allows
only hub-owned stop evidence to be recorded. The orchestration regression
asserts that no product branch, PR, reviewer, CI, or cleanup command is invoked.

### Step 3: Ambiguous Product Target Stops Before Mutation

**Maps to**: AC3

1. Run:

   ```bash
   set -euo pipefail
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --config "$ROUTING_CONFIG" \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/ambiguous-target.json \
     --json | tee "$ROUTING_TMP/ambiguous-target.json"
   ```

2. Confirm the command exits `0`.
3. Run:

   ```bash
   set -euo pipefail
   jq -e '
     .outcome_code == "ambiguous_target"
     and .continue_allowed == false
     and has("selected_product_repo_key")
     and .selected_product_repo_key == null
     and .artifact_owner == "none"
     and (.configured_product_repo_keys | sort) == ["admin-portal", "mobile-app"]
     and .required_human_action != null
   ' "$ROUTING_TMP/ambiguous-target.json"
   ```

4. Run the orchestration regression that exercises the same stop fixture:

   ```bash
   set -euo pipefail
   bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh
   ```

**Expected result**: The output shows `Ambiguous target` or equivalent stop
evidence, `outcome_code=ambiguous_target`, `continue_allowed=false`, and
identifies the required routing clarification. The orchestration regression
asserts that no product branch, PR, reviewer, CI, or cleanup command is invoked.

### Step 4: Multiple Product Targets Require Split Or Narrowing

**Maps to**: AC4

1. Run:

   ```bash
   set -euo pipefail
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --config "$ROUTING_CONFIG" \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/multiple-targets.json \
     --json | tee "$ROUTING_TMP/multiple-targets.json"
   ```

2. Confirm the command exits `0`.
3. Run:

   ```bash
   set -euo pipefail
   jq -e '
     .outcome_code == "multiple_targets"
     and .continue_allowed == false
     and has("selected_product_repo_key")
     and .selected_product_repo_key == null
     and .artifact_owner == "none"
     and (.configured_product_repo_keys | sort) == ["admin-portal", "mobile-app"]
     and (.required_human_action | test("split|narrow"; "i"))
   ' "$ROUTING_TMP/multiple-targets.json"
   ```

**Expected result**: The output shows `Multiple targets` and instructs the
operator to split the request into repository-scoped children or narrow the
child to one selected product repository key. The JSON output includes
`outcome_code=multiple_targets` and `continue_allowed=false`.

### Step 5: Cross-Repository Request Uses Epic Plus Children

**Maps to**: AC5

1. Run the docs regression test:

   ```bash
   set -euo pipefail
   bash scripts/development-workflow/tests/test-workflow-hub-docs.sh
   ```

2. Assert each product-owned child fixture routes to exactly one product
   repository and none returns `multiple_targets`:

   ```bash
   set -euo pipefail
   for fixture in \
     scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json \
     scripts/development-workflow/tests/fixtures/1354-routing/product-owned-admin-portal.json
   do
     output="$ROUTING_TMP/child-$(basename "$fixture")"
     python3 scripts/development-workflow/work-item-repository-routing.py \
       --config "$ROUTING_CONFIG" \
       --fixture "$fixture" \
       --json | tee "$output"
     jq -e '
       .outcome_code == "product_owned"
       and .outcome_code != "multiple_targets"
       and (.selected_product_repo_keys | length) == 1
       and (.configured_product_repo_keys | sort) == ["admin-portal", "mobile-app"]
     ' "$output"
   done
   ```

**Expected result**: The request is not represented as one multi-target child,
and each product-owned child has exactly one selected product repository key.

### Step 6: Hub-Only Work Does Not Require Product Key

**Maps to**: AC6

1. Run:

   ```bash
   set -euo pipefail
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --config "$ROUTING_CONFIG" \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/hub-only.json \
     --json | tee "$ROUTING_TMP/hub-only.json"
   ```

2. Confirm the command exits `0`.
3. Run:

   ```bash
   set -euo pipefail
   jq -e '
     .outcome_code == "hub_only"
     and .continue_allowed == true
     and has("selected_product_repo_key")
     and .selected_product_repo_key == null
     and .artifact_owner == "hub_repository"
     and (.configured_product_repo_keys | sort) == ["admin-portal", "mobile-app"]
   ' "$ROUTING_TMP/hub-only.json"
   ```

**Expected result**: The output shows `Hub only`, routes hub-owned artifacts to
the hub repository, does not require a product repository selector, and includes
`outcome_code=hub_only` with `continue_allowed=true`.

### Step 7: Single-Repository Work Keeps Current Behavior

**Maps to**: AC8

1. Run:

   ```bash
   set -euo pipefail
   python3 scripts/development-workflow/work-item-repository-routing.py \
     --config "$ROUTING_CONFIG" \
     --fixture scripts/development-workflow/tests/fixtures/1354-routing/single-repo.json \
     --json | tee "$ROUTING_TMP/single-repo.json"
   ```

2. Confirm the command exits `0`.
3. Run:

   ```bash
   set -euo pipefail
   jq -e '
     .outcome_code == "single_repo"
     and .continue_allowed == true
     and has("selected_product_repo_key")
     and .selected_product_repo_key == null
     and .artifact_owner == "current_repository"
   ' "$ROUTING_TMP/single-repo.json"
   ```

**Expected result**: The output shows single-repository behavior using the
current repository as artifact owner and includes `outcome_code=single_repo`.

### Step 8: Out-Of-Scope Epic Peers Remain Separate

**Maps to**: AC9

1. Run:

   ```bash
   set -euo pipefail
   git rev-parse --verify origin/develop-multi-repo-releases >/dev/null
   changed_files="$(git diff --name-only origin/develop-multi-repo-releases...HEAD -- \
     scripts/development-workflow docs/workflow/development-workflow)"
   test -n "$changed_files"
   match_count=0
   printf '%s\n' "$changed_files" > "$ROUTING_TMP/changed-files.txt"
   while IFS= read -r file; do
     set +e
     rg -n "#1356|#1357|#1358|#1359|release execution|delivery-bundle|milestone|adoption" "$file"
     rg_status=$?
     set -e
     if [ "$rg_status" -eq 0 ]; then
       match_count=$((match_count + 1))
     elif [ "$rg_status" -eq 1 ]; then
       :
     else
       exit "$rg_status"
     fi
   done < "$ROUTING_TMP/changed-files.txt"
   test "$match_count" -eq 0
   ```

2. Confirm the command exits `0`, proving the #1354 implementation changed
   files did not absorb peer epic behavior.

**Expected result**: Product release execution remains scoped to #1356,
delivery-bundle behavior to #1357, milestone reconciliation to #1358, and
adoption assurance to #1359.

### Last Step: Validate And Shut Down

- Verify all assertions in the checklist below are met.
- Remove any temporary smoke output files created during the smoke run:

  ```bash
   set -euo pipefail
  test -n "$ROUTING_TMP"
  rm -rf "$ROUTING_TMP"
  test ! -e "$ROUTING_TMP"
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
