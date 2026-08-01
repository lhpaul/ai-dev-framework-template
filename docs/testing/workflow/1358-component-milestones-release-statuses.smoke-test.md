# Smoke Test Runbook: Component Milestones And Release Statuses

**Feature**: Component milestones and release statuses
**Spec**:
[`1_1358-component-milestones-release-statuses_specs.md`](../../specs/developments/20260731193728_1358-component-milestones-release-statuses/1_1358-component-milestones-release-statuses_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the #1358 implementation branch after the implementation PR
      changes are present.
- [ ] `jq`, `git`, `python3`, Bash, and `gh` are available.
- [ ] The repository has no unrelated local changes that would obscure smoke
      test output.
- [ ] `scripts/development-workflow/component-milestone-reconciliation.sh`
      exists and is executable.
- [ ] The smoke can run with a mocked `gh` executable or in a disposable test
      repository. Do not run apply-mode steps against production issues.

---

## Test Data

| Item | Value |
| --- | --- |
| Parent epic | `#1352` |
| Component child | `#1358` or a disposable test child issue |
| Delivery bundle issue | Disposable delivery bundle issue or fixture ref |
| Product repository key | `mobile-app` |
| Component tag | `mobile-v1.4.0` |
| Namespaced milestone | `mobile-app@mobile-v1.4.0` |
| Non-hub release milestone | `v999.999.999-smoke` |
| Evidence path | `$SMOKE_TMP/mobile-evidence.json` |
| Delivery bundle path | `$SMOKE_TMP/delivery-bundle.json` |
| Helper | `scripts/development-workflow/component-milestone-reconciliation.sh` |

Create a temp directory and common shell variables before running the steps:

```bash
set -euo pipefail

if ! SMOKE_TMP="$(mktemp -d)" || [ -z "$SMOKE_TMP" ] || [ ! -d "$SMOKE_TMP" ]; then
  echo "ERROR_CODE=smoke_tmp_setup_failed message='failed to create temp directory'" >&2
  exit 1
fi
cleanup_smoke_tmp() {
  if [ -n "${SMOKE_TMP:-}" ] && [ -d "$SMOKE_TMP" ]; then
    rm -rf "$SMOKE_TMP"
  fi
}
trap cleanup_smoke_tmp EXIT

HELPER="scripts/development-workflow/component-milestone-reconciliation.sh"
EVIDENCE="$SMOKE_TMP/mobile-evidence.json"
BUNDLE="$SMOKE_TMP/delivery-bundle.json"
PRODUCT_REPO="mobile-app"
COMPONENT_TAG="mobile-v1.4.0"
MILESTONE_TITLE="${PRODUCT_REPO}@${COMPONENT_TAG}"
```

The implementation may provide a fixture helper. If it does, use that helper to
write `$EVIDENCE` and `$BUNDLE`. If no helper exists, create minimal
`component_release_evidence.v1` and `delivery_bundle_manifest.v1` files matching
the final helper's required fields.

---

## Smoke Test Steps

### Step 1: Inspect Complete Component Evidence

**Maps to**: Acceptance Criteria 1, 4, 5, and 13

```bash
"$HELPER" inspect-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$SMOKE_TMP/component-ready.json"

jq -e \
  --arg milestone "$MILESTONE_TITLE" '
    .schema_version == "component_milestone_reconciliation.v1" and
    .reconciliation_outcome == "component_released" and
    .child_release_state == "released" and
    .parent_release_state != "released" and
    .milestone_title == $milestone and
    .mutation_allowed == true
  ' "$SMOKE_TMP/component-ready.json"
```

**Expected result**: The helper reports `component_released`, computes
`mobile-app@mobile-v1.4.0`, marks only the child eligible for released state,
and does not imply parent release.

### Step 2: Apply A Namespaced Component Milestone

**Maps to**: Acceptance Criteria 1, 5, 7, 8, and 13

Run this step only with a mocked `gh` executable or disposable test issue.

```bash
"$HELPER" apply-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$SMOKE_TMP/component-apply.json"

jq -e \
  --arg milestone "$MILESTONE_TITLE" '
    .reconciliation_outcome == "component_released" and
    .milestone_title == $milestone and
    .milestone_assignment.target_issue == 1358 and
    .milestone_assignment.parent_epic_stamped == false and
    .milestone_assignment.delivery_bundle_stamped == false
  ' "$SMOKE_TMP/component-apply.json"
```

**Expected result**: The helper creates or reuses the namespaced milestone and
assigns it only to the component child. Parent epic and delivery bundle issues
remain milestone-free.

### Step 3: Reapply Identical Component Evidence

**Maps to**: Acceptance Criteria 1, 5, and 13

```bash
"$HELPER" apply-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$SMOKE_TMP/component-reapply.json"

jq -e '
  .reconciliation_outcome == "component_released" and
  (.idempotent == true or .milestone_assignment.action == "reused")
' "$SMOKE_TMP/component-reapply.json"
```

**Expected result**: Reapplying the same complete evidence is idempotent and
does not create duplicate milestones or duplicate assignments.

### Step 4: Verify Missing And Invalid Evidence Stop Before Mutation

**Maps to**: Acceptance Criteria 2, 3, 4, and 6

```bash
missing_output="$SMOKE_TMP/missing-evidence.json"
"$HELPER" inspect-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --json > "$missing_output"

jq -e '
  .reconciliation_outcome == "component_release_pending" and
  .child_release_state == "pending" and
  .mutation_allowed == false
' "$missing_output"

cp "$EVIDENCE" "$SMOKE_TMP/mismatched-evidence.json"
jq '.selected_product_repo_key = "web-app"' \
  "$SMOKE_TMP/mismatched-evidence.json" > "$SMOKE_TMP/mismatched.tmp"
mv "$SMOKE_TMP/mismatched.tmp" "$SMOKE_TMP/mismatched-evidence.json"

if "$HELPER" apply-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$SMOKE_TMP/mismatched-evidence.json" \
  --json 2> "$SMOKE_TMP/mismatch.err"
then
  echo "mismatched evidence was accepted" >&2
  exit 1
fi

rg -q 'component_target_mismatch\|component_release_not_ready' \
  "$SMOKE_TMP/mismatch.err"
```

**Expected result**: No evidence record stays pending. Mismatched or invalid
evidence blocks before milestone or tracker mutation.

### Step 5: Reject Parent And Delivery Milestone Writes

**Maps to**: Acceptance Criteria 7 and 8

```bash
for target_kind in parent_epic delivery_bundle; do
  if "$HELPER" apply-component \
    --issue 1352 \
    --target-kind "$target_kind" \
    --product-repo "$PRODUCT_REPO" \
    --component-tag "$COMPONENT_TAG" \
    --evidence-file "$EVIDENCE" \
    --json 2> "$SMOKE_TMP/${target_kind}.err"
  then
    echo "$target_kind accepted a component milestone" >&2
    exit 1
  fi
  rg -q 'milestone_target_not_allowed' "$SMOKE_TMP/${target_kind}.err"
done
```

**Expected result**: Parent epics and delivery bundle issues reject all
workflow-hub milestone writes.

### Step 6: Inspect Partial Parent Release State

**Maps to**: Acceptance Criterion 9

```bash
"$HELPER" inspect-parent \
  --parent-issue 1352 \
  --delivery-manifest "$BUNDLE" \
  --json > "$SMOKE_TMP/parent-partial.json"

jq -e '
  .reconciliation_outcome == "parent_partially_released" and
  .parent_release_state == "partially_released" and
  .mutation_allowed == false
' "$SMOKE_TMP/parent-partial.json"
```

**Expected result**: A bundle with at least one released component and at least
one unreleased current component reports partial release without finalizing the
parent.

### Step 7: Inspect Final Parent Release State

**Maps to**: Acceptance Criterion 10

```bash
"$HELPER" inspect-parent \
  --parent-issue 1352 \
  --delivery-manifest "$BUNDLE" \
  --require-finalized \
  --json > "$SMOKE_TMP/parent-final.json"

jq -e '
  .reconciliation_outcome == "parent_released" and
  .parent_release_state == "released" and
  .milestone_assignment.parent_epic_stamped == false and
  .milestone_assignment.delivery_bundle_stamped == false
' "$SMOKE_TMP/parent-final.json"
```

**Expected result**: A finalized bundle moves parent release state to released
without creating a component, parent, delivery, or shared suite milestone.

### Step 8: Verify Non-Hub Release Compatibility

**Maps to**: Acceptance Criteria 11 and 12

```bash
"$HELPER" inspect-component \
  --mode single_repo \
  --issue 1358 \
  --target-kind component_child \
  --version v999.999.999-smoke \
  --json > "$SMOKE_TMP/single-repo.json"

jq -e '
  .reconciliation_outcome == "single_repo_milestone" and
  .milestone_title == "v999.999.999-smoke" and
  .requires_delivery_bundle == false
' "$SMOKE_TMP/single-repo.json"
```

**Expected result**: Non-hub mode keeps existing plain release milestone
behavior and does not require a namespaced component milestone or delivery
bundle finalization.

### Last Step: Validate And Shut Down

- Verify all assertions in the checklist below are met.
- Remove temporary files and mocked GitHub API logs.

---

## Assertions Checklist

- [ ] A workflow-hub component release stamps `<product-repo>@<tag>` only on
      the matching component child.
- [ ] Missing product selection, missing evidence, and missing tag stop before
      tracker mutation.
- [ ] Mismatched product evidence stops before tracker mutation.
- [ ] Complete component evidence requires repository identity, correlation,
      contract revision, cleanup, hub tracker reference, and tracker
      reconciliation.
- [ ] A component child reaches released state independently.
- [ ] Failed, blocked, pending, stale, incomplete, invalid, or conflicting
      evidence does not release the child.
- [ ] Parent epics remain milestone-free.
- [ ] Delivery bundle issues remain milestone-free.
- [ ] Partial parent release state is visible before finalization.
- [ ] Parent released state requires finalized bundle evidence.
- [ ] A one-product workflow-hub delivery uses namespaced component milestone
      behavior.
- [ ] Non-hub `vX.Y.Z` milestone behavior is unchanged.
- [ ] Audit or JSON output identifies target child, selected product
      repository, component tag, outcome, and required next action.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Component evidence | Complete, missing, mismatched, pending, failed, blocked, stale, and conflicting | Fixture writer from `test-component-milestone-reconciliation.sh` or temporary JSON files in `$SMOKE_TMP` |
| Delivery bundle | Partial, blocked, finalized, and corrected-after-blocked parent states | Fixture writer from `test-component-milestone-reconciliation.sh` or `delivery-bundle-manifest.sh` test fixtures |
| GitHub API | Existing milestone, missing milestone, issue assignment, and duplicate reapply | Mock `gh` executable in `$SMOKE_TMP/bin` or disposable test repository |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Helper tries to mutate a real issue during smoke | Mock `gh` is not first in `PATH` or disposable repo is not selected | Stop immediately, restore `PATH`, and rerun in dry-run or fixture mode |
| `component_release_pending` appears for a supposedly complete fixture | Evidence file path is missing or schema is not `component_release_evidence.v1` | Regenerate the fixture and verify the schema with `jq -r '.schema_version'` |
| Parent finalization reports `blocked` | Bundle fixture has incomplete, stale, or conflicting component evidence | Inspect bundle blockers and correct component evidence before rerunning |
| Non-hub mode still requires product repo | Mode override or config fixture still sets `workflow_hub` | Use `--mode single_repo` or a non-hub fixture for compatibility checks |

---

## Known Limitations

- Apply-mode smoke steps should use mocked GitHub API responses unless the
  operator deliberately prepared disposable test issues and milestones.
