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
- [ ] Run all command blocks below in the same Bash shell after **Fixture Setup**
      so the guarded temporary directory and exported variables are shared.

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

## Fixture Setup

Run this setup once. It creates an owned temporary directory, loads the
single-repository and workflow-hub fixtures, and records the exact paths and
test-only tracker state used by later scenarios.

```bash
set -euo pipefail

SMOKE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/1356-component-release.XXXXXX")"
cleanup_smoke_tmp() {
  case "$(basename "${SMOKE_TMP:-}")" in
    1356-component-release.*)
      [ -d "$SMOKE_TMP" ] && rm -rf "$SMOKE_TMP"
      ;;
  esac
}
trap cleanup_smoke_tmp EXIT

real_path() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

require_owned_path() {
  candidate="$1"
  test -e "$candidate"
  resolved_candidate="$(real_path "$candidate")"
  resolved_root="$(real_path "$SMOKE_TMP")"
  case "$resolved_candidate" in
    "$resolved_root"/*) ;;
    *)
      echo "fixture path escapes SMOKE_TMP: $candidate" >&2
      exit 1
      ;;
  esac
}

require_clean_git() {
  repo_path="$1"
  status_file="$2"
  git -C "$repo_path" status --porcelain > "$status_file"
  test ! -s "$status_file"
}

expect_no_remote_ref() {
  repo_path="$1"
  ref_kind="$2"
  ref_name="$3"
  output_file="$4"

  set +e
  git -C "$repo_path" ls-remote --exit-code "$ref_kind" origin "$ref_name" \
    > "$output_file"
  status=$?
  set -e

  case "$status" in
    2) ;;
    0)
      echo "remote ref still exists: $ref_kind $ref_name" >&2
      exit 1
      ;;
    *)
      echo "remote ref check failed with status $status: $ref_kind $ref_name" >&2
      exit "$status"
      ;;
  esac
}

FIXTURE_JSON="$SMOKE_TMP/fixtures.json"

bash scripts/development-workflow/tests/setup-component-release-fixture.sh \
  --work-dir "$SMOKE_TMP" \
  --json > "$FIXTURE_JSON"

export SMOKE_TMP FIXTURE_JSON
export SINGLE_REPO_FIXTURE
export HUB_FIXTURE PRODUCT_REPO_KEY ALT_PRODUCT_REPO_KEY PRODUCT_REPO_PATH
export RELEASE_VERSION TEST_TRACKER_ISSUE TRACKER_STATE_FILE

SINGLE_REPO_FIXTURE="$(jq -r '.single_repo.path' "$FIXTURE_JSON")"
HUB_FIXTURE="$(jq -r '.workflow_hub.path' "$FIXTURE_JSON")"
PRODUCT_REPO_KEY="$(jq -r '.workflow_hub.selected_product_repo_key' "$FIXTURE_JSON")"
ALT_PRODUCT_REPO_KEY="$(jq -r '.workflow_hub.alternate_product_repo_key' "$FIXTURE_JSON")"
PRODUCT_REPO_PATH="$(jq -r '.workflow_hub.selected_product_repo_path' "$FIXTURE_JSON")"
RELEASE_VERSION="$(jq -r '.release.version' "$FIXTURE_JSON")"
TEST_TRACKER_ISSUE="$(jq -r '.tracker.issue' "$FIXTURE_JSON")"
TRACKER_STATE_FILE="$(jq -r '.tracker.state_file' "$FIXTURE_JSON")"

jq -e '.workflow_hub.product_repos | length >= 2' "$FIXTURE_JSON"
jq --arg expected "$PRODUCT_REPO_KEY" \
  -e '.workflow_hub.product_repos | index($expected)' "$FIXTURE_JSON"
jq --arg expected "$ALT_PRODUCT_REPO_KEY" \
  -e '.workflow_hub.product_repos | index($expected)' "$FIXTURE_JSON"
jq --arg expected "$PRODUCT_REPO_PATH" \
  -e '.workflow_hub.local_paths[$expected] == true' "$FIXTURE_JSON"
jq -e '.workflow_hub.release_contract.branch_pattern | length > 0' "$FIXTURE_JSON"
jq -e '.invalid_fixtures | keys | length >= 6' "$FIXTURE_JSON"
jq -e '.evidence_mismatch_fixtures | keys | length >= 5' "$FIXTURE_JSON"
jq -e '.cleanup.seeded_branch == true' "$FIXTURE_JSON"
jq -e '.cleanup.seeded_tag == true' "$FIXTURE_JSON"
jq -e '.cleanup.seeded_lock == true' "$FIXTURE_JSON"
jq -e '.invalid_fixtures.malformed | length > 0' "$FIXTURE_JSON"
jq -e '.cleanup.mismatched_evidence_file | length > 0' "$FIXTURE_JSON"

case "$TEST_TRACKER_ISSUE" in
  test:*|mock:*|fixture:*) ;;
  *)
    echo "refusing live tracker issue: $TEST_TRACKER_ISSUE" >&2
    exit 1
    ;;
esac

test -d "$SINGLE_REPO_FIXTURE/.git"
test -d "$HUB_FIXTURE/.git"
test -d "$PRODUCT_REPO_PATH/.git"
test -f "$TRACKER_STATE_FILE"
require_owned_path "$SINGLE_REPO_FIXTURE"
require_owned_path "$HUB_FIXTURE"
require_owned_path "$PRODUCT_REPO_PATH"
require_owned_path "$TRACKER_STATE_FILE"
require_owned_path "$(jq -r '.cleanup.mismatched_evidence_file' "$FIXTURE_JSON")"
require_clean_git "$PRODUCT_REPO_PATH" "$SMOKE_TMP/product-status.txt"
```

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
set -euo pipefail
: "${SMOKE_TMP:?run fixture setup first}"

TARGET_JSON="$SMOKE_TMP/single-repo-target.json"
SINGLE_REPO_STATUS_BEFORE="$SMOKE_TMP/single-repo-status-before.txt"
SINGLE_REPO_STATUS_AFTER="$SMOKE_TMP/single-repo-status-after.txt"

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
set -euo pipefail
: "${SMOKE_TMP:?run fixture setup first}"

TARGET_JSON="$SMOKE_TMP/component-target.json"
TARGET_BINDING_JSON="$SMOKE_TMP/component-target-binding.json"
HUB_STATUS_BEFORE="$SMOKE_TMP/hub-status-before.txt"
HUB_STATUS_AFTER="$SMOKE_TMP/hub-status-after.txt"

test -d "$HUB_FIXTURE/.git"
git -C "$HUB_FIXTURE" status --porcelain > "$HUB_STATUS_BEFORE"

scripts/development-workflow/component-release-target.sh \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --require-local \
  --json > "$TARGET_JSON"

git -C "$HUB_FIXTURE" status --porcelain > "$HUB_STATUS_AFTER"
PRODUCT_REPO_PATH="$(jq -r '.local_checkout.path' "$TARGET_JSON")"
require_owned_path "$PRODUCT_REPO_PATH"
cp "$TARGET_JSON" "$TARGET_BINDING_JSON"

jq -e '.routing_outcome == "component_release_routed"' "$TARGET_JSON"
jq --arg expected "$PRODUCT_REPO_KEY" \
  -e '.selected_product_repo_key == $expected' "$TARGET_JSON"
jq -e '.canonical_repository_identity | length > 0' "$TARGET_JSON"
jq -e '.local_checkout.path | length > 0' "$TARGET_JSON"
jq -e '.release_base | length > 0' "$TARGET_JSON"
jq -e '.release_branch_pattern | length > 0' "$TARGET_JSON"
jq -e '.artifact_owners.release == "product_repository"' "$TARGET_JSON"
jq -e '.artifact_owners.ci == "product_repository"' "$TARGET_JSON"
jq -e '.artifact_owners.deployment == "product_repository"' "$TARGET_JSON"
jq -e '.artifact_owners.cleanup == "product_repository"' "$TARGET_JSON"
jq -e '.artifact_owners.tracker == "hub_repository"' "$TARGET_JSON"
jq -e '.release_correlation_key | length > 0' "$TARGET_JSON"
jq -e '.contract_revision | length > 0' "$TARGET_JSON"
test -d "$PRODUCT_REPO_PATH/.git"
require_clean_git "$PRODUCT_REPO_PATH" "$SMOKE_TMP/product-status-after-target.txt"
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
set -euo pipefail
: "${SMOKE_TMP:?run fixture setup first}"

while read -r fixture expected
do
  FIXTURE_ROOT="$(jq -r --arg key "$fixture" \
    '.invalid_fixtures[$key]' "$FIXTURE_JSON")"
  TARGET_JSON="$SMOKE_TMP/${fixture}.json"
  require_owned_path "$FIXTURE_ROOT"

  if ! scripts/development-workflow/component-release-target.sh \
    --repo-root "$FIXTURE_ROOT" \
    --require-local \
    --json > "$TARGET_JSON"
  then
    echo "classified stop outcome returned nonzero: $fixture" >&2
    exit 1
  fi

  jq --arg expected "$expected" \
    -e '.routing_outcome == $expected' "$TARGET_JSON"
  jq -e '.mutation_allowed == false' "$TARGET_JSON"
done <<'CASES'
missing_product_selection missing_product_selection
multiple_product_targets multiple_product_targets
unknown_product_repository unknown_product_repository
ambiguous_product_selection ambiguous_product_selection
invalid_release_contract invalid_release_contract
unavailable_product_repository_checkout unavailable_product_repository_checkout
CASES

MALFORMED_FIXTURE_ROOT="$(jq -r '.invalid_fixtures.malformed' "$FIXTURE_JSON")"
require_owned_path "$MALFORMED_FIXTURE_ROOT"

if scripts/development-workflow/component-release-target.sh \
  --repo-root "$MALFORMED_FIXTURE_ROOT" \
  --json > "$SMOKE_TMP/malformed-target.json"
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
set -euo pipefail
: "${SMOKE_TMP:?run fixture setup first}"

TARGET_JSON="$SMOKE_TMP/component-target.json"
TARGET_BINDING_JSON="$SMOKE_TMP/component-target-binding.json"
EVIDENCE_JSON="$SMOKE_TMP/component-evidence.json"
EVIDENCE_DUPLICATE_JSON="$SMOKE_TMP/component-evidence-duplicate.json"

scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_JSON" \
  --binding-file "$TARGET_BINDING_JSON" \
  --release-outcome pending \
  --ci-outcome pending \
  --deployment-outcome not_applicable \
  --cleanup-outcome not_started \
  --hub-tracker-ref "$TEST_TRACKER_ISSUE" \
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
jq --arg expected "$TEST_TRACKER_ISSUE" \
  -e '.hub_tracker_ref == $expected' "$EVIDENCE_JSON"

scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_JSON" \
  --binding-file "$TARGET_BINDING_JSON" \
  --release-outcome pending \
  --ci-outcome pending \
  --deployment-outcome not_applicable \
  --cleanup-outcome not_started \
  --hub-tracker-ref "$TEST_TRACKER_ISSUE" \
  --json > "$EVIDENCE_DUPLICATE_JSON"

cmp "$EVIDENCE_JSON" "$EVIDENCE_DUPLICATE_JSON"

for release_outcome in completed failed blocked
do
  scripts/development-workflow/component-release-evidence.sh \
    --target-file "$TARGET_JSON" \
    --binding-file "$TARGET_BINDING_JSON" \
    --release-outcome "$release_outcome" \
    --ci-outcome passed \
    --deployment-outcome recorded \
    --cleanup-outcome complete \
    --hub-tracker-ref "$TEST_TRACKER_ISSUE" \
    --json > "$SMOKE_TMP/${release_outcome}-evidence.json"

  jq -e --arg value "$release_outcome" \
    '.release_outcome == $value' "$SMOKE_TMP/${release_outcome}-evidence.json"
done

while read -r mismatch
do
  MISMATCH_TARGET="$(jq -r --arg key "$mismatch" \
    '.evidence_mismatch_fixtures[$key]' "$FIXTURE_JSON")"
  MISMATCH_OUTPUT="$SMOKE_TMP/${mismatch}-accepted-evidence.json"
  require_owned_path "$MISMATCH_TARGET"

  if scripts/development-workflow/component-release-evidence.sh \
    --target-file "$MISMATCH_TARGET" \
    --binding-file "$TARGET_BINDING_JSON" \
    --release-outcome pending \
    --ci-outcome pending \
    --deployment-outcome not_applicable \
    --cleanup-outcome not_started \
    --hub-tracker-ref "$TEST_TRACKER_ISSUE" \
    --json > "$MISMATCH_OUTPUT"
  then
    echo "mismatched evidence was accepted: $mismatch" >&2
    exit 1
  fi

  test ! -s "$MISMATCH_OUTPUT"
done <<'MISMATCHES'
repository_key
canonical_repository_identity
artifact_owner
release_correlation_key
contract_revision
MISMATCHES

if scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_JSON" \
  --binding-file "$TARGET_BINDING_JSON" \
  --release-outcome invalid \
  --ci-outcome pending \
  --deployment-outcome not_applicable \
  --cleanup-outcome not_started \
  --hub-tracker-ref "$TEST_TRACKER_ISSUE" \
  --json > "$SMOKE_TMP/invalid-evidence.json"
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
set -euo pipefail
: "${SMOKE_TMP:?run fixture setup first}"

TARGET_JSON="$SMOKE_TMP/component-target.json"
EVIDENCE_JSON="$SMOKE_TMP/component-evidence.json"
CLEANUP_JSON="$SMOKE_TMP/cleanup-output.json"
CLEANUP_RERUN_JSON="$SMOKE_TMP/cleanup-rerun-output.json"
PRODUCT_STATE_BEFORE="$SMOKE_TMP/product-state-before.txt"
PRODUCT_STATE_AFTER_REJECT="$SMOKE_TMP/product-state-after-reject.txt"
TRACKER_STATE_BEFORE_REJECT="$SMOKE_TMP/tracker-before-reject.json"
TRACKER_STATE_AFTER_REJECT="$SMOKE_TMP/tracker-after-reject.json"
PRODUCT_REPO_PATH="$(jq -r '.local_checkout.path' "$TARGET_JSON")"
require_owned_path "$PRODUCT_REPO_PATH"
MISMATCHED_EVIDENCE_FILE="$(jq -r '.cleanup.mismatched_evidence_file' "$FIXTURE_JSON")"
require_owned_path "$MISMATCHED_EVIDENCE_FILE"
RELEASE_BRANCH_PATTERN="$(jq -r '.release_branch_pattern' "$TARGET_JSON")"
RELEASE_BRANCH="${RELEASE_BRANCH_PATTERN//\{version\}/$RELEASE_VERSION}"
RELEASE_BRANCH="${RELEASE_BRANCH//\{product_repo\}/$PRODUCT_REPO_KEY}"
RELEASE_TAG="v$RELEASE_VERSION"

case "$TEST_TRACKER_ISSUE" in
  test:*|mock:*|fixture:*) ;;
  *)
    echo "refusing live tracker issue: $TEST_TRACKER_ISSUE" >&2
    exit 1
    ;;
esac

git -C "$PRODUCT_REPO_PATH" ls-remote --exit-code --heads origin \
  "$RELEASE_BRANCH" > "$SMOKE_TMP/pre-cleanup-branch.txt"
git -C "$PRODUCT_REPO_PATH" ls-remote --exit-code --tags origin \
  "refs/tags/$RELEASE_TAG" > "$SMOKE_TMP/pre-cleanup-tag.txt"
git -C "$PRODUCT_REPO_PATH" ls-remote --heads --tags origin \
  > "$PRODUCT_STATE_BEFORE"

scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  "$RELEASE_BRANCH" \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --evidence-file "$EVIDENCE_JSON" \
  --issues "$TEST_TRACKER_ISSUE" \
  --json > "$CLEANUP_JSON"

scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  "$RELEASE_BRANCH" \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --evidence-file "$EVIDENCE_JSON" \
  --issues "$TEST_TRACKER_ISSUE" \
  --json > "$CLEANUP_RERUN_JSON"

jq -e '.cleanup_outcome == "complete"' "$CLEANUP_JSON"
jq -e '.tracker_mutation.repository_owner == "hub_repository"' "$CLEANUP_JSON"
jq --arg expected "$TEST_TRACKER_ISSUE" \
  -e '.tracker_mutation.issue == $expected' "$CLEANUP_JSON"
jq --arg expected "$PRODUCT_REPO_KEY" \
  -e '.product_cleanup.repository_key == $expected' "$CLEANUP_JSON"
jq -e '.cleanup_lock.owner | length > 0' "$CLEANUP_JSON"
jq -e '.cleanup_lock.release_correlation_key | length > 0' "$CLEANUP_JSON"
jq -e '.product_cleanup.remote_branch_deleted == true' "$CLEANUP_JSON"
jq -e '.product_cleanup.remote_tag_deleted == true' "$CLEANUP_JSON"
jq -e '.cleanup_evidence.status == "complete"' "$CLEANUP_JSON"
jq -e '.tracker_mutation.after_product_cleanup == true' "$CLEANUP_JSON"
jq -e '.product_cleanup.already_complete == true' "$CLEANUP_RERUN_JSON"
require_clean_git "$PRODUCT_REPO_PATH" "$SMOKE_TMP/product-status-after-cleanup.txt"
expect_no_remote_ref "$PRODUCT_REPO_PATH" --heads "$RELEASE_BRANCH" \
  "$SMOKE_TMP/post-cleanup-branch.txt"
expect_no_remote_ref "$PRODUCT_REPO_PATH" --tags "refs/tags/$RELEASE_TAG" \
  "$SMOKE_TMP/post-cleanup-tag.txt"

git -C "$PRODUCT_REPO_PATH" ls-remote --heads --tags origin \
  > "$PRODUCT_STATE_BEFORE"
cp "$TRACKER_STATE_FILE" "$TRACKER_STATE_BEFORE_REJECT"

if scripts/development-workflow/prepare-release-post-merge-cleanup.sh \
  "$RELEASE_BRANCH" \
  --repo "$PRODUCT_REPO_KEY" \
  --repo-root "$HUB_FIXTURE" \
  --evidence-file "$MISMATCHED_EVIDENCE_FILE" \
  --issues "$TEST_TRACKER_ISSUE" \
  --json > "$SMOKE_TMP/mismatched-cleanup.json"
then
  echo "mismatched evidence cleanup was accepted" >&2
  exit 1
fi

git -C "$PRODUCT_REPO_PATH" ls-remote --heads --tags origin \
  > "$PRODUCT_STATE_AFTER_REJECT"
cp "$TRACKER_STATE_FILE" "$TRACKER_STATE_AFTER_REJECT"
cmp "$PRODUCT_STATE_BEFORE" "$PRODUCT_STATE_AFTER_REJECT"
cmp "$TRACKER_STATE_BEFORE_REJECT" "$TRACKER_STATE_AFTER_REJECT"
```

**Expected result**: Matching evidence allows safe rerunnable cleanup;
mismatched evidence stops before product or hub tracker mutation.

### Last Step: Validate & Shut Down

- Verify all assertions below are satisfied.
- Remove any temporary fixture files or test branches created for the smoke run.

```bash
set -euo pipefail
: "${SMOKE_TMP:?run fixture setup first}"

for repo in "$SINGLE_REPO_FIXTURE" "$HUB_FIXTURE" "$PRODUCT_REPO_PATH"
do
  if [ -n "${repo:-}" ] && [ -d "$repo/.git" ]; then
    require_clean_git "$repo" "$SMOKE_TMP/$(basename "$repo")-final-status.txt"
  fi
done

cleanup_smoke_tmp
trap - EXIT
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
