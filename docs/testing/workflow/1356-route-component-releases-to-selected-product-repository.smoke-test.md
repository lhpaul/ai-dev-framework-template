# Smoke Test Runbook: Route Component Releases To The Selected Product Repository

**Feature**: Route component releases to the selected product repository
**Spec**:
[`docs/specs/developments/20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md`](../../specs/developments/20260731105659_1356-route-component-releases-to-selected-product-repository/1_1356-route-component-releases-to-selected-product-repository_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running every scenario:

- [ ] The implementation branch for #1356 is checked out or merged into the
      test branch.
- [ ] Hub tracker mutation uses a mocked tracker or disposable fixture issue.
      The smoke test must reject live work-item references unless the operator
      passes an explicit destructive-test option supported by the implementation.

Before Step 1:

- [ ] A single-repository fixture or temporary checkout is available. Step 1
      must not require workflow-hub fixture data or a product selector.

Before Steps 2 through 5:

- [ ] You are in the workflow hub checkout.
- [ ] A workflow-hub fixture or test repository configuration has at least two
      product repositories and local-only checkout entries for the selected
      product repository.
- [ ] The selected product repository checkout is clean.

---

## Test Data

| Item | Value |
| --- | --- |
| Hub mode | `workflow_hub` |
| Selected product repository | One configured product repository key, such as `mobile-app` |
| Alternate product repository | A second configured product repository key |
| Release version | Test version such as `9.9.9-test` |
| Release correlation key | Stable value for the test release attempt |
| Hub tracker reference | `test:*`, `mock:*`, or `fixture:*` tracker reference only |

---

## Smoke Test Steps

### Step 1: Validate single-repository compatibility

**Maps to**: AC7

1. Use a single-repository fixture or omit workflow-hub mode.
2. Run the implemented release target resolution command without a product
   repository selector.
3. Confirm the routing outcome is `single_repo_release`.
4. Confirm no product repository selector is required.

```bash
SINGLE_REPO_FIXTURE="/tmp/1356-single-repo"
TARGET_JSON="/tmp/1356-single-repo-target.json"
SINGLE_REPO_STATUS_BEFORE="/tmp/1356-single-repo-status-before.txt"
SINGLE_REPO_STATUS_AFTER="/tmp/1356-single-repo-status-after.txt"

test -d "$SINGLE_REPO_FIXTURE/.git"
git -C "$SINGLE_REPO_FIXTURE" status --porcelain \
  > "$SINGLE_REPO_STATUS_BEFORE"

scripts/development-workflow/component-release-target.sh \
  --repo-root "$SINGLE_REPO_FIXTURE" \
  --json > "$TARGET_JSON"

git -C "$SINGLE_REPO_FIXTURE" status --porcelain \
  > "$SINGLE_REPO_STATUS_AFTER"

jq -e '.routing_outcome == "single_repo_release"' "$TARGET_JSON"
jq -e '.selected_product_repo_key == null' "$TARGET_JSON"
jq -e '.mutation_allowed == true' "$TARGET_JSON"
cmp "$SINGLE_REPO_STATUS_BEFORE" "$SINGLE_REPO_STATUS_AFTER"
```

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
   and `contract_revision`.

```bash
HUB_FIXTURE="/tmp/1356-workflow-hub"
PRODUCT_REPO_KEY="mobile-app"
TARGET_JSON="/tmp/1356-component-target.json"
HUB_STATUS_BEFORE="/tmp/1356-hub-status-before.txt"
HUB_STATUS_AFTER="/tmp/1356-hub-status-after.txt"

test -d "$HUB_FIXTURE/.git"
git -C "$HUB_FIXTURE" status --porcelain > "$HUB_STATUS_BEFORE"

scripts/development-workflow/component-release-target.sh \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --require-local \
  --json > "$TARGET_JSON"

git -C "$HUB_FIXTURE" status --porcelain > "$HUB_STATUS_AFTER"
PRODUCT_REPO_PATH="$(jq -r '.local_checkout.path' "$TARGET_JSON")"

jq -e '.routing_outcome == "component_release_routed"' "$TARGET_JSON"
jq -e '.selected_product_repo_key == env.PRODUCT_REPO_KEY' "$TARGET_JSON"
jq -e '.canonical_repository_identity | length > 0' "$TARGET_JSON"
jq -e '.local_checkout.path | length > 0' "$TARGET_JSON"
jq -e '.release_base | length > 0' "$TARGET_JSON"
jq -e '.release_branch_pattern | length > 0' "$TARGET_JSON"
jq -e '.artifact_owners.release == "product_repository"' "$TARGET_JSON"
jq -e '.artifact_owners.tracker == "hub_repository"' "$TARGET_JSON"
jq -e '.release_correlation_key | length > 0' "$TARGET_JSON"
jq -e '.contract_revision | length > 0' "$TARGET_JSON"
test -d "$PRODUCT_REPO_PATH/.git"
test -z "$(git -C "$PRODUCT_REPO_PATH" status --porcelain)"
cmp "$HUB_STATUS_BEFORE" "$HUB_STATUS_AFTER"
```

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

```bash
HUB_FIXTURE="/tmp/1356-workflow-hub"

for fixture in \
  missing-product-selection \
  multiple-product-targets \
  unknown-product-repository \
  ambiguous-product-selection \
  invalid-release-contract \
  unavailable-product-repository-checkout
do
  TARGET_JSON="/tmp/1356-${fixture}.json"

  scripts/development-workflow/component-release-target.sh \
    --repo-root "$HUB_FIXTURE/fixtures/$fixture" \
    --require-local \
    --json > "$TARGET_JSON"

  case "$fixture" in
    missing-product-selection)
      jq -e '.routing_outcome == "missing_product_selection"' "$TARGET_JSON"
      ;;
    multiple-product-targets)
      jq -e '.routing_outcome == "multiple_product_targets"' "$TARGET_JSON"
      ;;
    unknown-product-repository)
      jq -e '.routing_outcome == "unknown_product_repository"' "$TARGET_JSON"
      ;;
    ambiguous-product-selection)
      jq -e '.routing_outcome == "ambiguous_product_selection"' "$TARGET_JSON"
      ;;
    invalid-release-contract)
      jq -e '.routing_outcome == "invalid_release_contract"' "$TARGET_JSON"
      ;;
    unavailable-product-repository-checkout)
      jq -e \
        '.routing_outcome == "unavailable_product_repository_checkout"' \
        "$TARGET_JSON"
      ;;
  esac

  jq -e '.mutation_allowed == false' "$TARGET_JSON"
done

if scripts/development-workflow/component-release-target.sh \
  --repo-root "$HUB_FIXTURE/fixtures/malformed" \
  --json > /tmp/1356-malformed-target.json
then
  echo "malformed target input was accepted" >&2
  exit 1
fi
```

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

```bash
TARGET_JSON="/tmp/1356-component-target.json"
EVIDENCE_JSON="/tmp/1356-component-evidence.json"

scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_JSON" \
  --release-outcome pending \
  --ci-outcome pending \
  --deployment-outcome not_applicable \
  --cleanup-outcome not_started \
  --hub-tracker-ref "fixture:1356-smoke" \
  --json > "$EVIDENCE_JSON"

TARGET_REPOSITORY="$(jq -r '.canonical_repository_identity' "$TARGET_JSON")"
TARGET_CORRELATION="$(jq -r '.release_correlation_key' "$TARGET_JSON")"
TARGET_REVISION="$(jq -r '.contract_revision' "$TARGET_JSON")"

jq -e --arg value "$TARGET_REPOSITORY" \
  '.canonical_repository_identity == $value' "$EVIDENCE_JSON"
jq -e --arg value "$TARGET_CORRELATION" \
  '.release_correlation_key == $value' "$EVIDENCE_JSON"
jq -e --arg value "$TARGET_REVISION" \
  '.contract_revision == $value' "$EVIDENCE_JSON"
jq -e '.routing_outcome == "component_release_routed"' "$EVIDENCE_JSON"
jq -e '.hub_tracker_ref == "fixture:1356-smoke"' "$EVIDENCE_JSON"

for release_outcome in completed failed blocked
do
  scripts/development-workflow/component-release-evidence.sh \
    --target-file "$TARGET_JSON" \
    --release-outcome "$release_outcome" \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "fixture:1356-smoke" \
    --json > "/tmp/1356-${release_outcome}-evidence.json"

  jq -e --arg value "$release_outcome" \
    '.release_outcome == $value' "/tmp/1356-${release_outcome}-evidence.json"
done

if scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_JSON" \
  --release-outcome invalid \
  --ci-outcome pending \
  --deployment-outcome not_applicable \
  --cleanup-outcome not_started \
  --hub-tracker-ref "fixture:1356-smoke" \
  --json > /tmp/1356-invalid-evidence.json
then
  echo "invalid evidence was accepted" >&2
  exit 1
fi
```

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

```bash
HUB_FIXTURE="/tmp/1356-workflow-hub"
PRODUCT_REPO_KEY="mobile-app"
TARGET_JSON="/tmp/1356-component-target.json"
EVIDENCE_JSON="/tmp/1356-component-evidence.json"
TEST_TRACKER_REF="fixture:1356-smoke"
TEST_TRACKER_ISSUE="fixture-1356-smoke"
CLEANUP_JSON="/tmp/1356-cleanup-output.json"
CLEANUP_RERUN_JSON="/tmp/1356-cleanup-rerun-output.json"
PRODUCT_REPO_PATH="$(jq -r '.local_checkout.path' "$TARGET_JSON")"
RELEASE_BRANCH="release/v9.9.9-test"

case "$TEST_TRACKER_REF" in
  test:*|mock:*|fixture:*) ;;
  *)
    echo "refusing live tracker reference: $TEST_TRACKER_REF" >&2
    exit 1
    ;;
esac

scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --evidence-file "$EVIDENCE_JSON" \
  --issues "$TEST_TRACKER_ISSUE" \
  --best-effort \
  --json > "$CLEANUP_JSON"

scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --evidence-file "$EVIDENCE_JSON" \
  --issues "$TEST_TRACKER_ISSUE" \
  --best-effort \
  --json > "$CLEANUP_RERUN_JSON"

jq -e '.cleanup_outcome == "complete"' "$CLEANUP_JSON"
jq -e '.tracker_mutation.repository_owner == "hub_repository"' "$CLEANUP_JSON"
jq -e '.tracker_mutation.issue == env.TEST_TRACKER_ISSUE' "$CLEANUP_JSON"
jq -e '.product_cleanup.repository_key == env.PRODUCT_REPO_KEY' "$CLEANUP_JSON"
jq -e '.product_cleanup.already_complete == true' "$CLEANUP_RERUN_JSON"
test -z "$(git -C "$PRODUCT_REPO_PATH" status --porcelain)"
! git -C "$PRODUCT_REPO_PATH" ls-remote --exit-code --heads origin \
  "$RELEASE_BRANCH"

if scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --evidence-file "/tmp/1356-mismatched-evidence.json" \
  --issues "$TEST_TRACKER_ISSUE" \
  --best-effort \
  --json > /tmp/1356-mismatched-cleanup.json
then
  echo "mismatched evidence cleanup was accepted" >&2
  exit 1
fi
```

**Expected result**: Matching evidence allows safe rerunnable cleanup;
mismatched evidence stops before product or hub tracker mutation.

### Last Step: Validate & Shut Down

- Verify all assertions below are satisfied.
- Remove any temporary fixture files or test branches created for the smoke run.

```bash
rm -f /tmp/1356-*.json /tmp/1356-*.txt

for repo in "$SINGLE_REPO_FIXTURE" "$HUB_FIXTURE" "$PRODUCT_REPO_PATH"
do
  if [ -n "${repo:-}" ] && [ -d "$repo/.git" ]; then
    test -z "$(git -C "$repo" status --porcelain)"
  fi
done
```

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
- [ ] Cleanup uses only a disposable fixture issue or mocked tracker by default,
      never live issue #1356.
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
