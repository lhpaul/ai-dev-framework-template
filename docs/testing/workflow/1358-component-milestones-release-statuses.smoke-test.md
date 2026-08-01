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
| Parent issue number | `$PARENT_ISSUE` |
| Component child issue number | `$COMPONENT_ISSUE` |
| Delivery bundle issue number | `$DELIVERY_BUNDLE_ISSUE` |
| Product repository key | `mobile-app` |
| Component tag | `mobile-v1.4.0` |
| Namespaced milestone | `mobile-app@mobile-v1.4.0` |
| Non-hub release milestone | `v999.999.999` |
| Evidence path | `$SMOKE_TMP/mobile-evidence.json` |
| Partial delivery bundle path | `$PARTIAL_BUNDLE` |
| Finalized delivery bundle path | `$FINALIZED_BUNDLE` |
| Blocked delivery bundle path | `$BLOCKED_BUNDLE` |
| Mocked GitHub call log | `$GH_CALL_LOG` |
| Helper | `scripts/development-workflow/component-milestone-reconciliation.sh` |
| Fixture helper | `scripts/development-workflow/tests/setup-component-milestone-fixture.sh` |

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
FIXTURE_HELPER="scripts/development-workflow/tests/setup-component-milestone-fixture.sh"
PRODUCT_REPO="mobile-app"
COMPONENT_TAG="mobile-v1.4.0"
MILESTONE_TITLE="${PRODUCT_REPO}@${COMPONENT_TAG}"
SINGLE_REPO_VERSION="v999.999.999"

fixture_json="$SMOKE_TMP/fixtures.json"
bash "$FIXTURE_HELPER" --output-dir "$SMOKE_TMP" --json > "$fixture_json"

export PATH="$(jq -r '.mock_gh.bin_dir' "$fixture_json"):$PATH"
GH_CALL_LOG="$(jq -r '.mock_gh.call_log' "$fixture_json")"
PARENT_ISSUE="$(jq -r '.issues.parent' "$fixture_json")"
COMPONENT_ISSUE="$(jq -r '.issues.component_child' "$fixture_json")"
DELIVERY_BUNDLE_ISSUE="$(jq -r '.issues.delivery_bundle' "$fixture_json")"
EVIDENCE="$(jq -r '.evidence.complete' "$fixture_json")"
MISMATCHED_EVIDENCE="$(jq -r '.evidence.mismatched_product' "$fixture_json")"
MISSING_EVIDENCE_PATH="$(jq -r '.evidence.missing_path' "$fixture_json")"
PARTIAL_BUNDLE="$(jq -r '.bundles.partial' "$fixture_json")"
FINALIZED_BUNDLE="$(jq -r '.bundles.finalized' "$fixture_json")"
BLOCKED_BUNDLE="$(jq -r '.bundles.blocked' "$fixture_json")"
STATUS_WRITE_FAILURE_BUNDLE="$(jq -r '.bundles.status_write_failure' "$fixture_json")"
STATUS_WRITE_FAILURE_TARGET="$(jq -r '.status_write_failure_target' "$fixture_json")"

gh_log_hash() {
  git hash-object "$GH_CALL_LOG" 2>/dev/null || printf '%s\n' empty
}

count_gh_calls() {
  local pattern="$1"
  local count
  count="$(rg -c -- "$pattern" "$GH_CALL_LOG" 2>/dev/null || true)"
  if [ -z "$count" ]; then
    printf '%s\n' 0
  else
    printf '%s\n' "$count"
  fi
}
```

The fixture helper is mandatory. It must create every file path emitted in
`fixtures.json`, install a mocked `gh` command directory, and initialize
`$GH_CALL_LOG` before any apply-mode step runs.

---

## Smoke Test Steps

### Step 1: Inspect Complete Component Evidence

**Maps to**: Acceptance Criteria 1, 4, 5, and 13

```bash
"$HELPER" inspect-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$SMOKE_TMP/component-ready.json"

jq -e \
  --arg milestone "$MILESTONE_TITLE" '
    .schema_version == "component_milestone_reconciliation.v1" and
    (.reconciliation_outcome | IN(
      "component_released",
      "component_release_pending",
      "component_release_not_ready",
      "component_target_mismatch",
      "component_tag_missing"
    )) and
    .reconciliation_outcome == "component_released" and
    (.child_release_state | IN("not_started", "pending", "released", "blocked", "failed")) and
    .child_release_state == "released" and
    (.parent_release_state | IN("not_released", "partially_released", "blocked")) and
    .milestone_title == $milestone and
    .mutation_allowed == true and
    (.required_next_action | type == "string" and length > 0) and
    (.blockers | type == "array") and
    (.milestone_assignment | type == "object")
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
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$SMOKE_TMP/component-apply.json"

jq -e \
  --arg milestone "$MILESTONE_TITLE" \
  --argjson component_issue "$COMPONENT_ISSUE" '
    .reconciliation_outcome == "component_released" and
    .milestone_title == $milestone and
    .milestone_assignment.target_issue == $component_issue and
    .milestone_assignment.parent_epic_stamped == false and
    .milestone_assignment.delivery_bundle_stamped == false
  ' "$SMOKE_TMP/component-apply.json"

test "$(count_gh_calls "issues/${COMPONENT_ISSUE}.*milestone")" = "1"
test "$(count_gh_calls "issues/${PARENT_ISSUE}.*milestone")" = "0"
test "$(count_gh_calls "issues/${DELIVERY_BUNDLE_ISSUE}.*milestone")" = "0"
log_hash_after_apply="$(gh_log_hash)"
```

**Expected result**: The helper creates or reuses the namespaced milestone and
assigns it only to the component child. Parent epic and delivery bundle issues
remain milestone-free.

### Step 3: Reapply Identical Component Evidence

**Maps to**: Acceptance Criteria 1, 5, and 13

```bash
"$HELPER" apply-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$EVIDENCE" \
  --json > "$SMOKE_TMP/component-reapply.json"

jq -e '
  .reconciliation_outcome == "component_released" and
  (.idempotent == true or .milestone_assignment.action == "reused")
' "$SMOKE_TMP/component-reapply.json"

log_hash_after_reapply="$(gh_log_hash)"
test "$log_hash_after_apply" = "$log_hash_after_reapply"
```

**Expected result**: Reapplying the same complete evidence is idempotent and
does not create duplicate milestones or duplicate assignments.

### Step 4: Verify Missing And Invalid Evidence Stop Before Mutation

**Maps to**: Acceptance Criteria 2, 3, 4, and 6

```bash
missing_output="$SMOKE_TMP/missing-evidence-result.json"
"$HELPER" inspect-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$MISSING_EVIDENCE_PATH" \
  --json > "$missing_output"

jq -e '
  .reconciliation_outcome == "component_release_pending" and
  .child_release_state == "pending" and
  .mutation_allowed == false
' "$missing_output"

set +e
"$HELPER" apply-component \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --product-repo "$PRODUCT_REPO" \
  --component-tag "$COMPONENT_TAG" \
  --evidence-file "$MISMATCHED_EVIDENCE" \
  --json > "$SMOKE_TMP/mismatch.json" 2> "$SMOKE_TMP/mismatch.err"
mismatch_status=$?
set -e
if [ "$mismatch_status" -eq 0 ]; then
  echo "ERROR_CODE=mismatched_evidence_accepted message='mismatched evidence was accepted'" >&2
  exit 1
fi

jq -e '
  .reconciliation_outcome == "component_target_mismatch" and
  .mutation_allowed == false
' "$SMOKE_TMP/mismatch.json"
```

**Expected result**: No evidence record stays pending. Mismatched or invalid
evidence blocks before milestone or tracker mutation.

### Step 5: Reject Parent And Delivery Milestone Writes

**Maps to**: Acceptance Criteria 7 and 8

```bash
log_hash_before_rejections="$(gh_log_hash)"
for target_kind in parent_epic delivery_bundle; do
  case "$target_kind" in
    parent_epic) target_issue="$PARENT_ISSUE" ;;
    delivery_bundle) target_issue="$DELIVERY_BUNDLE_ISSUE" ;;
  esac
  if "$HELPER" apply-component \
    --issue "$target_issue" \
    --target-kind "$target_kind" \
    --product-repo "$PRODUCT_REPO" \
    --component-tag "$COMPONENT_TAG" \
    --evidence-file "$EVIDENCE" \
    --json 2> "$SMOKE_TMP/${target_kind}.err"
  then
    echo "ERROR_CODE=milestone_target_accepted message='$target_kind accepted a component milestone'" >&2
    exit 1
  fi
  rg -q 'milestone_target_not_allowed' "$SMOKE_TMP/${target_kind}.err"
done
test "$log_hash_before_rejections" = "$(gh_log_hash)"
```

**Expected result**: Parent epics and delivery bundle issues reject all
workflow-hub milestone writes.

### Step 6: Inspect Partial Parent Release State

**Maps to**: Acceptance Criterion 9

```bash
"$HELPER" inspect-parent \
  --parent-issue "$PARENT_ISSUE" \
  --delivery-manifest "$PARTIAL_BUNDLE" \
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
  --parent-issue "$PARENT_ISSUE" \
  --delivery-manifest "$FINALIZED_BUNDLE" \
  --require-finalized \
  --json > "$SMOKE_TMP/parent-final.json"

jq -e '
  .reconciliation_outcome == "parent_released" and
  .parent_release_state == "released" and
  .milestone_assignment.parent_epic_stamped == false and
  .milestone_assignment.delivery_bundle_stamped == false
' "$SMOKE_TMP/parent-final.json"

log_hash_before_parent_apply="$(gh_log_hash)"
"$HELPER" apply-parent \
  --parent-issue "$PARENT_ISSUE" \
  --delivery-manifest "$FINALIZED_BUNDLE" \
  --require-finalized \
  --json > "$SMOKE_TMP/parent-apply.json"

jq -e \
  --argjson parent_issue "$PARENT_ISSUE" '
  .release_status.parent_issue == $parent_issue and
  .release_status.state == "released" and
  .reconciliation_outcome == "parent_released"
' "$SMOKE_TMP/parent-apply.json"
jq -e '
  .release_status.state == "released" and
  ([.audit_events[] | select(.event == "parent_release_status_updated")] | length) >= 1
' "$FINALIZED_BUNDLE"
test "$log_hash_before_parent_apply" = "$(gh_log_hash)"

failed_hash_before="$(git hash-object "$STATUS_WRITE_FAILURE_BUNDLE")"
set +e
"$HELPER" apply-parent \
  --parent-issue "$PARENT_ISSUE" \
  --delivery-manifest "$STATUS_WRITE_FAILURE_BUNDLE" \
  --status-output "$STATUS_WRITE_FAILURE_TARGET" \
  --require-finalized \
  --json > "$SMOKE_TMP/parent-write-failure.json" 2> "$SMOKE_TMP/parent-write-failure.err"
failed_status=$?
set -e
if [ "$failed_status" -eq 0 ]; then
  echo "ERROR_CODE=parent_status_write_failure_not_exercised message='apply-parent unexpectedly succeeded'" >&2
  exit 1
fi
test "$failed_hash_before" = "$(git hash-object "$STATUS_WRITE_FAILURE_BUNDLE")"
```

**Expected result**: A finalized bundle moves parent release state to released
without creating a component, parent, delivery, or shared suite milestone.

### Step 8: Verify Non-Hub Release Compatibility

**Maps to**: Acceptance Criteria 11 and 12

```bash
"$HELPER" inspect-component \
  --mode single_repo \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --version "$SINGLE_REPO_VERSION" \
  --json > "$SMOKE_TMP/single-repo.json"

jq -e \
  --arg version "$SINGLE_REPO_VERSION" '
  .reconciliation_outcome == "single_repo_milestone" and
  .milestone_title == $version and
  .requires_delivery_bundle == false
' "$SMOKE_TMP/single-repo.json"

single_repo_hash_before="$(gh_log_hash)"
"$HELPER" apply-component \
  --mode single_repo \
  --issue "$COMPONENT_ISSUE" \
  --target-kind component_child \
  --version "$SINGLE_REPO_VERSION" \
  --json > "$SMOKE_TMP/single-repo-apply.json"

jq -e \
  --arg version "$SINGLE_REPO_VERSION" '
  .reconciliation_outcome == "single_repo_milestone" and
  .milestone_title == $version and
  .requires_delivery_bundle == false
' "$SMOKE_TMP/single-repo-apply.json"
test "$single_repo_hash_before" != "$(gh_log_hash)"
rg -q "v999.999.999|issues/${COMPONENT_ISSUE}.*milestone" "$GH_CALL_LOG"
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
| Component evidence | Complete, missing, mismatched, pending, failed, blocked, stale, and conflicting | `bash scripts/development-workflow/tests/setup-component-milestone-fixture.sh --output-dir "$SMOKE_TMP" --json` |
| Delivery bundle | Partial, blocked, finalized, corrected-after-blocked, and write-failure parent states | `bash scripts/development-workflow/tests/setup-component-milestone-fixture.sh --output-dir "$SMOKE_TMP" --json` |
| GitHub API | Existing milestone, missing milestone, issue assignment, duplicate reapply, and call log | Mock `gh` executable emitted by `setup-component-milestone-fixture.sh` |

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
